const std = @import("std");
const ast = @import("../ast/nodes.zig");
const analyzer = @import("../analyzer/analyzer.zig");

pub const CodeGenError = error{
    InvalidNode,
    UnsupportedFeature,
    OutOfMemory,
};

pub const CompileResult = struct {
    js: []const u8,
    css: ?[]const u8,
    source_map: ?[]const u8,
    warnings: []analyzer.Warning,
    errors: []analyzer.Error,
};

pub const CodeGenOptions = struct {
    dev: bool = false,
    hmr: bool = false,
    css_hash: ?[]const u8 = null,
    generate: GenerateMode = .dom,
    hydratable: bool = false,
    preserve_comments: bool = false,
    preserve_whitespace: bool = false,
    source_maps: bool = false,
    filename: ?[]const u8 = null,
};

pub const GenerateMode = enum {
    dom,
    ssr,
};

pub const CodeGenerator = struct {
    analysis: *analyzer.ComponentAnalysis,
    options: CodeGenOptions,
    output: std.ArrayList(u8),
    css_output: std.ArrayList(u8),
    indent_level: u32,
    allocator: std.mem.Allocator,

    current_block_id: u32,
    template_count: u32,
    binding_count: u32,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        analysis: *analyzer.ComponentAnalysis,
        options: CodeGenOptions,
    ) Self {
        return Self{
            .analysis = analysis,
            .options = options,
            .output = std.ArrayList(u8).init(allocator),
            .css_output = std.ArrayList(u8).init(allocator),
            .indent_level = 0,
            .allocator = allocator,
            .current_block_id = 0,
            .template_count = 0,
            .binding_count = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.output.deinit();
        self.css_output.deinit();
    }

    pub fn generate(self: *Self) CodeGenError!CompileResult {
        if (self.options.generate == .ssr) {
            try self.generateSSR();
        } else {
            try self.generateDOM();
        }

        return CompileResult{
            .js = self.output.items,
            .css = if (self.css_output.items.len > 0) self.css_output.items else null,
            .source_map = null,
            .warnings = self.analysis.warnings.items,
            .errors = self.analysis.errors.items,
        };
    }

    fn generateDOM(self: *Self) CodeGenError!void {
        try self.writeImports();

        try self.writeLine("");
        try self.writeLine("export default function Component($$anchor, $$props) {");
        self.indent_level += 1;

        if (self.analysis.uses_props_rune) {
            try self.writeIndent();
            try self.write("let { ");
            for (self.analysis.props.items, 0..) |prop, i| {
                if (i > 0) try self.write(", ");
                try self.write(prop.name);
            }
            try self.writeLine(" } = $props();");
        }

        try self.generateInstanceVariables();

        try self.generateTemplate(self.analysis.root.data.root.fragment);

        try self.generateEffects();

        self.indent_level -= 1;
        try self.writeLine("}");
    }

    fn generateSSR(self: *Self) CodeGenError!void {
        try self.writeLine("import * as $ from 'mms/internal/server';");
        try self.writeLine("");

        try self.writeLine("export default function Component($$payload, $$props) {");
        self.indent_level += 1;

        try self.writeIndent();
        try self.write("$$payload.out += `");
        try self.generateSSRTemplate(self.analysis.root.data.root.fragment);
        try self.writeLine("`;");

        self.indent_level -= 1;
        try self.writeLine("}");
    }

    fn writeImports(self: *Self) CodeGenError!void {
        try self.writeLine("import * as $ from 'mms/internal/client';");

        if (self.analysis.uses_state_rune) {
            try self.writeLine("const { state } = $;");
        }
        if (self.analysis.uses_derived_rune) {
            try self.writeLine("const { derived } = $;");
        }
        if (self.analysis.uses_effect_rune) {
            try self.writeLine("const { effect } = $;");
        }
    }

    fn generateInstanceVariables(self: *Self) CodeGenError!void {
        _ = self;
    }

    fn generateTemplate(self: *Self, node: *ast.Node) CodeGenError!void {
        switch (node.node_type) {
            .fragment => {
                const fragment = node.data.fragment;
                for (fragment.children.items) |child| {
                    try self.generateTemplate(child);
                }
            },
            .element => try self.generateElement(node),
            .component => try self.generateComponent(node),
            .text_node => try self.generateText(node),
            .expression_tag => try self.generateExpressionTag(node),
            .if_block => try self.generateIfBlock(node),
            .each_block => try self.generateEachBlock(node),
            .await_block => try self.generateAwaitBlock(node),
            .key_block => try self.generateKeyBlock(node),
            .snippet_block => try self.generateSnippetBlock(node),
            .html_tag => try self.generateHtmlTag(node),
            .render_tag => try self.generateRenderTag(node),
            else => {},
        }
    }

    fn generateElement(self: *Self, node: *ast.Node) CodeGenError!void {
        const element = node.data.element;
        const template_id = self.template_count;
        self.template_count += 1;

        try self.writeIndent();
        try self.write("var ");
        try self.writeTemplateVar(template_id);
        try self.write(" = $.template(`<");
        try self.write(element.name);

        for (element.attributes.items) |attr| {
            if (attr.node_type == .attribute) {
                const attribute = attr.data.attribute;
                switch (attribute.value) {
                    .text => |text| {
                        try self.write(" ");
                        try self.write(attribute.name);
                        try self.write("=\"");
                        try self.write(text);
                        try self.write("\"");
                    },
                    .boolean => |val| {
                        if (val) {
                            try self.write(" ");
                            try self.write(attribute.name);
                        }
                    },
                    else => {},
                }
            }
        }

        if (element.self_closing) {
            try self.writeLine(" />`);");
        } else {
            try self.write(">`);");
            try self.writeLine("");
        }

        try self.writeIndent();
        try self.write("var ");
        try self.writeNodeVar(template_id);
        try self.write(" = $.first_child(");
        try self.writeTemplateVar(template_id);
        try self.writeLine("());");

        for (element.attributes.items) |attr| {
            if (attr.node_type == .directive) {
                try self.generateDirective(attr, template_id);
            } else if (attr.node_type == .attribute) {
                const attribute = attr.data.attribute;
                switch (attribute.value) {
                    .expression => |expr| {
                        try self.generateDynamicAttribute(attribute.name, expr, template_id);
                    },
                    else => {},
                }
            }
        }

        if (!element.self_closing) {
            for (element.children.items) |child| {
                try self.generateTemplate(child);
            }
        }

        try self.writeIndent();
        try self.write("$.append($$anchor, ");
        try self.writeNodeVar(template_id);
        try self.writeLine(");");
    }

    fn generateComponent(self: *Self, node: *ast.Node) CodeGenError!void {
        const component = node.data.component;

        try self.writeIndent();
        try self.write(component.name);
        try self.write("($$anchor, {");

        var first = true;
        for (component.attributes.items) |attr| {
            if (attr.node_type == .attribute) {
                const attribute = attr.data.attribute;
                if (!first) try self.write(", ");
                first = false;

                try self.write(attribute.name);
                try self.write(": ");

                switch (attribute.value) {
                    .text => |text| {
                        try self.write("\"");
                        try self.write(text);
                        try self.write("\"");
                    },
                    .expression => |expr| {
                        try self.generateExpression(expr);
                    },
                    .boolean => |val| {
                        try self.write(if (val) "true" else "false");
                    },
                    else => {},
                }
            }
        }

        try self.writeLine("});");
    }

    fn generateText(self: *Self, node: *ast.Node) CodeGenError!void {
        const text = node.data.text_node;

        const trimmed = std.mem.trim(u8, text.data, " \t\n\r");
        if (trimmed.len == 0 and !self.options.preserve_whitespace) {
            return;
        }

        const template_id = self.template_count;
        self.template_count += 1;

        try self.writeIndent();
        try self.write("$.text($$anchor, `");
        try self.writeEscaped(text.data);
        try self.writeLine("`);");

        _ = template_id;
    }

    fn generateExpressionTag(self: *Self, node: *ast.Node) CodeGenError!void {
        const expr_tag = node.data.expression_tag;
        const template_id = self.template_count;
        self.template_count += 1;

        try self.writeIndent();
        try self.write("var text_");
        try self.writeNumber(template_id);
        try self.writeLine(" = $.text($$anchor);");

        try self.writeIndent();
        try self.write("$.template_effect(() => $.set_text(text_");
        try self.writeNumber(template_id);
        try self.write(", ");
        try self.generateExpression(expr_tag.expression);
        try self.writeLine("));");
    }

    fn generateIfBlock(self: *Self, node: *ast.Node) CodeGenError!void {
        const if_block = node.data.if_block;
        const block_id = self.current_block_id;
        self.current_block_id += 1;

        try self.writeIndent();
        try self.write("var block_");
        try self.writeNumber(block_id);
        try self.write(" = $.if($$anchor, () => ");
        try self.generateExpression(if_block.test);
        try self.writeLine(", ($$anchor) => {");

        self.indent_level += 1;
        try self.generateTemplate(if_block.consequent);
        self.indent_level -= 1;

        try self.writeIndent();
        try self.write("}");

        if (if_block.alternate) |alternate| {
            try self.writeLine(", ($$anchor) => {");
            self.indent_level += 1;
            try self.generateTemplate(alternate);
            self.indent_level -= 1;
            try self.writeIndent();
            try self.write("}");
        }

        try self.writeLine(");");
    }

    fn generateEachBlock(self: *Self, node: *ast.Node) CodeGenError!void {
        const each_block = node.data.each_block;
        const block_id = self.current_block_id;
        self.current_block_id += 1;

        try self.writeIndent();
        try self.write("$.each($$anchor, () => ");
        try self.generateExpression(each_block.expression);
        try self.write(", (");

        try self.generateExpression(each_block.context);
        if (each_block.index) |index| {
            try self.write(", ");
            try self.write(index);
        }

        try self.writeLine(") => {");
        self.indent_level += 1;

        if (each_block.key) |key| {
            _ = key;
        }

        for (each_block.children.items) |child| {
            try self.generateTemplate(child);
        }

        self.indent_level -= 1;
        try self.writeIndent();
        try self.write("}");

        if (each_block.fallback) |fallback| {
            try self.writeLine(", () => {");
            self.indent_level += 1;
            try self.generateTemplate(fallback);
            self.indent_level -= 1;
            try self.writeIndent();
            try self.write("}");
        }

        try self.writeLine(");");

        _ = block_id;
    }

    fn generateAwaitBlock(self: *Self, node: *ast.Node) CodeGenError!void {
        const await_block = node.data.await_block;

        try self.writeIndent();
        try self.write("$.await($$anchor, () => ");
        try self.generateExpression(await_block.expression);
        try self.writeLine(", {");

        self.indent_level += 1;

        if (await_block.pending) |pending| {
            try self.writeIndent();
            try self.writeLine("pending: ($$anchor) => {");
            self.indent_level += 1;
            try self.generateTemplate(pending);
            self.indent_level -= 1;
            try self.writeIndent();
            try self.writeLine("},");
        }

        if (await_block.then_node) |then_node| {
            try self.writeIndent();
            try self.write("then: ($$anchor, ");
            if (await_block.value) |value| {
                try self.generateExpression(value);
            } else {
                try self.write("_");
            }
            try self.writeLine(") => {");
            self.indent_level += 1;
            try self.generateTemplate(then_node);
            self.indent_level -= 1;
            try self.writeIndent();
            try self.writeLine("},");
        }

        if (await_block.catch_node) |catch_node| {
            try self.writeIndent();
            try self.write("catch: ($$anchor, ");
            if (await_block.error_node) |error_val| {
                try self.generateExpression(error_val);
            } else {
                try self.write("_");
            }
            try self.writeLine(") => {");
            self.indent_level += 1;
            try self.generateTemplate(catch_node);
            self.indent_level -= 1;
            try self.writeIndent();
            try self.writeLine("},");
        }

        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeLine("});");
    }

    fn generateKeyBlock(self: *Self, node: *ast.Node) CodeGenError!void {
        const key_block = node.data.key_block;

        try self.writeIndent();
        try self.write("$.key($$anchor, () => ");
        try self.generateExpression(key_block.expression);
        try self.writeLine(", ($$anchor) => {");

        self.indent_level += 1;
        for (key_block.children.items) |child| {
            try self.generateTemplate(child);
        }
        self.indent_level -= 1;

        try self.writeIndent();
        try self.writeLine("});");
    }

    fn generateSnippetBlock(self: *Self, node: *ast.Node) CodeGenError!void {
        const snippet = node.data.snippet_block;

        try self.writeIndent();
        try self.write("function ");
        try self.write(snippet.name);
        try self.write("($$anchor");

        for (snippet.parameters.items) |param| {
            try self.write(", ");
            try self.generateExpression(param);
        }

        try self.writeLine(") {");
        self.indent_level += 1;
        try self.generateTemplate(snippet.body);
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeLine("}");
    }

    fn generateHtmlTag(self: *Self, node: *ast.Node) CodeGenError!void {
        const html_tag = node.data.html_tag;

        try self.writeIndent();
        try self.write("$.html($$anchor, () => ");
        try self.generateExpression(html_tag.expression);
        try self.writeLine(");");
    }

    fn generateRenderTag(self: *Self, node: *ast.Node) CodeGenError!void {
        const render_tag = node.data.render_tag;

        try self.writeIndent();
        try self.generateExpression(render_tag.expression);
        try self.write("($$anchor");

        if (render_tag.argument) |arg| {
            try self.write(", ");
            try self.generateExpression(arg);
        }

        try self.writeLine(");");
    }

    fn generateDirective(self: *Self, node: *ast.Node, element_id: u32) CodeGenError!void {
        const directive = node.data.directive;

        switch (directive.directive_type) {
            .on => {
                try self.writeIndent();
                try self.write("$.event(");
                try self.writeNodeVar(element_id);
                try self.write(", \"");
                try self.write(directive.name);
                try self.write("\", ");
                if (directive.expression) |expr| {
                    try self.generateExpression(expr);
                } else {
                    try self.write("() => {}");
                }
                try self.writeLine(");");
            },
            .bind => {
                try self.writeIndent();
                try self.write("$.bind_");
                try self.write(directive.name);
                try self.write("(");
                try self.writeNodeVar(element_id);
                if (directive.expression) |expr| {
                    try self.write(", () => ");
                    try self.generateExpression(expr);
                    try self.write(", (v) => ");
                    try self.generateExpression(expr);
                    try self.write(" = v");
                }
                try self.writeLine(");");
            },
            .class_directive => {
                try self.writeIndent();
                try self.write("$.class_toggle(");
                try self.writeNodeVar(element_id);
                try self.write(", \"");
                try self.write(directive.name);
                try self.write("\", () => ");
                if (directive.expression) |expr| {
                    try self.generateExpression(expr);
                } else {
                    try self.write("true");
                }
                try self.writeLine(");");
            },
            .style_directive => {
                try self.writeIndent();
                try self.write("$.style(");
                try self.writeNodeVar(element_id);
                try self.write(", \"");
                try self.write(directive.name);
                try self.write("\", () => ");
                if (directive.expression) |expr| {
                    try self.generateExpression(expr);
                }
                try self.writeLine(");");
            },
            .use => {
                try self.writeIndent();
                try self.write("$.action(");
                try self.writeNodeVar(element_id);
                try self.write(", ");
                if (directive.expression) |expr| {
                    try self.generateExpression(expr);
                }
                try self.writeLine(");");
            },
            .transition, .in_directive, .out_directive => {
                try self.writeIndent();
                try self.write("$.transition(");
                try self.writeNodeVar(element_id);
                try self.write(", ");
                if (directive.expression) |expr| {
                    try self.generateExpression(expr);
                }
                try self.writeLine(");");
            },
            .animate => {
                try self.writeIndent();
                try self.write("$.animation(");
                try self.writeNodeVar(element_id);
                try self.write(", ");
                if (directive.expression) |expr| {
                    try self.generateExpression(expr);
                }
                try self.writeLine(");");
            },
            else => {},
        }
    }

    fn generateDynamicAttribute(self: *Self, name: []const u8, expr: *ast.Node, element_id: u32) CodeGenError!void {
        try self.writeIndent();
        try self.write("$.attribute_effect(");
        try self.writeNodeVar(element_id);
        try self.write(", \"");
        try self.write(name);
        try self.write("\", () => ");
        try self.generateExpression(expr);
        try self.writeLine(");");
    }

    fn generateEffects(self: *Self) CodeGenError!void {
        _ = self;
    }

    fn generateSSRTemplate(self: *Self, node: *ast.Node) CodeGenError!void {
        switch (node.node_type) {
            .fragment => {
                const fragment = node.data.fragment;
                for (fragment.children.items) |child| {
                    try self.generateSSRTemplate(child);
                }
            },
            .element => {
                const element = node.data.element;
                try self.write("<");
                try self.write(element.name);

                for (element.attributes.items) |attr| {
                    if (attr.node_type == .attribute) {
                        const attribute = attr.data.attribute;
                        switch (attribute.value) {
                            .text => |text| {
                                try self.write(" ");
                                try self.write(attribute.name);
                                try self.write("=\"");
                                try self.write(text);
                                try self.write("\"");
                            },
                            .expression => {
                                try self.write(" ");
                                try self.write(attribute.name);
                                try self.write("=\"${$.escape(");
                                try self.write(")}\"");
                            },
                            .boolean => |val| {
                                if (val) {
                                    try self.write(" ");
                                    try self.write(attribute.name);
                                }
                            },
                            else => {},
                        }
                    }
                }

                if (element.self_closing) {
                    try self.write(" />");
                } else {
                    try self.write(">");
                    for (element.children.items) |child| {
                        try self.generateSSRTemplate(child);
                    }
                    try self.write("</");
                    try self.write(element.name);
                    try self.write(">");
                }
            },
            .text_node => {
                const text = node.data.text_node;
                try self.writeEscaped(text.data);
            },
            .expression_tag => {
                const expr_tag = node.data.expression_tag;
                try self.write("${$.escape(");
                try self.generateExpression(expr_tag.expression);
                try self.write(")}");
            },
            else => {},
        }
    }

    fn generateExpression(self: *Self, node: *ast.Node) CodeGenError!void {
        switch (node.node_type) {
            .identifier_expr => {
                try self.write(node.data.identifier_expr.name);
            },
            .literal_expr => {
                const lit = node.data.literal_expr;
                switch (lit.value) {
                    .string => |s| {
                        try self.write("\"");
                        try self.writeEscaped(s);
                        try self.write("\"");
                    },
                    .number => |n| {
                        var buf: [32]u8 = undefined;
                        const len = std.fmt.formatFloat(buf[0..], n, .{}) catch 0;
                        try self.write(buf[0..len]);
                    },
                    .boolean => |b| {
                        try self.write(if (b) "true" else "false");
                    },
                    .null_val => {
                        try self.write("null");
                    },
                }
            },
            .member_expr => {
                const member = node.data.member_expr;
                try self.generateExpression(member.object);
                if (member.computed) {
                    try self.write("[");
                    try self.generateExpression(member.property);
                    try self.write("]");
                } else {
                    try self.write(".");
                    try self.generateExpression(member.property);
                }
            },
            .call_expr => {
                const call = node.data.call_expr;
                try self.generateExpression(call.callee);
                try self.write("(");
                for (call.arguments.items, 0..) |arg, i| {
                    if (i > 0) try self.write(", ");
                    try self.generateExpression(arg);
                }
                try self.write(")");
            },
            .binary_expr => {
                const binary = node.data.binary_expr;
                try self.write("(");
                try self.generateExpression(binary.left);
                try self.write(" ");
                try self.write(binary.operator);
                try self.write(" ");
                try self.generateExpression(binary.right);
                try self.write(")");
            },
            .unary_expr => {
                const unary = node.data.unary_expr;
                if (unary.prefix) {
                    try self.write(unary.operator);
                    try self.generateExpression(unary.argument);
                } else {
                    try self.generateExpression(unary.argument);
                    try self.write(unary.operator);
                }
            },
            .conditional_expr => {
                const cond = node.data.conditional_expr;
                try self.write("(");
                try self.generateExpression(cond.test);
                try self.write(" ? ");
                try self.generateExpression(cond.consequent);
                try self.write(" : ");
                try self.generateExpression(cond.alternate);
                try self.write(")");
            },
            .array_expr => {
                const arr = node.data.array_expr;
                try self.write("[");
                for (arr.elements.items, 0..) |elem, i| {
                    if (i > 0) try self.write(", ");
                    if (elem) |e| {
                        try self.generateExpression(e);
                    }
                }
                try self.write("]");
            },
            .object_expr => {
                const obj = node.data.object_expr;
                try self.write("{");
                for (obj.properties.items, 0..) |prop, i| {
                    if (i > 0) try self.write(", ");
                    try self.generateExpression(prop);
                }
                try self.write("}");
            },
            else => {},
        }
    }

    fn write(self: *Self, str: []const u8) CodeGenError!void {
        self.output.appendSlice(str) catch return CodeGenError.OutOfMemory;
    }

    fn writeLine(self: *Self, str: []const u8) CodeGenError!void {
        try self.write(str);
        try self.write("\n");
    }

    fn writeIndent(self: *Self) CodeGenError!void {
        var i: u32 = 0;
        while (i < self.indent_level) : (i += 1) {
            try self.write("\t");
        }
    }

    fn writeNumber(self: *Self, num: u32) CodeGenError!void {
        var buf: [16]u8 = undefined;
        const slice = std.fmt.bufPrint(&buf, "{d}", .{num}) catch return CodeGenError.OutOfMemory;
        try self.write(slice);
    }

    fn writeTemplateVar(self: *Self, id: u32) CodeGenError!void {
        try self.write("$$template_");
        try self.writeNumber(id);
    }

    fn writeNodeVar(self: *Self, id: u32) CodeGenError!void {
        try self.write("$$node_");
        try self.writeNumber(id);
    }

    fn writeEscaped(self: *Self, str: []const u8) CodeGenError!void {
        for (str) |c| {
            switch (c) {
                '\\' => try self.write("\\\\"),
                '"' => try self.write("\\\""),
                '\n' => try self.write("\\n"),
                '\r' => try self.write("\\r"),
                '\t' => try self.write("\\t"),
                '`' => try self.write("\\`"),
                '$' => try self.write("\\$"),
                else => {
                    var buf: [1]u8 = .{c};
                    try self.write(&buf);
                },
            }
        }
    }
};

test "codegen basic" {
}
