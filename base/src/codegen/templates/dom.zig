const std = @import("std");
const ast = @import("../../ast/nodes.zig");
const buffer = @import("../../utils/buffer.zig");

pub const DomTemplate = struct {
    buf: buffer.WriteBuffer,
    allocator: std.mem.Allocator,
    template_count: u32,
    block_count: u32,
    scope_id: ?*const [8]u8,
    hydrate: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .buf = buffer.WriteBuffer.init(allocator),
            .allocator = allocator,
            .template_count = 0,
            .block_count = 0,
            .scope_id = null,
            .hydrate = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buf.deinit();
    }

    pub fn generate(self: *Self, node: *ast.Node) ![]u8 {
        if (self.hydrate) {
            try self.buf.writeLine("import * as $ from 'mms/internal/client/hydrate';");
        } else {
            try self.buf.writeLine("import * as $ from 'mms/internal/client';");
        }

        if (node.node_type == .root) {
            const root = node.data.root;
            if (root.instance) |script| {
                try self.emitModuleLevelImports(script);
            }
        }

        try self.buf.writeLine("");
        try self.emitComponent(node);
        return try self.buf.toOwnedSlice();
    }

    fn emitModuleLevelImports(self: *Self, node: *ast.Node) !void {
        if (node.node_type != .script) return;

        const script = node.data.script;
        if (script.content.len > 0) {
            var lines = std.mem.splitSequence(u8, script.content, "\n");
            while (lines.next()) |line| {
                const trimmed = std.mem.trim(u8, line, " \t");
                if (std.mem.startsWith(u8, trimmed, "import ")) {
                    try self.buf.write(trimmed);
                    try self.buf.writeLine("");
                }
            }
        }
    }

    fn emitComponent(self: *Self, node: *ast.Node) std.mem.Allocator.Error!void {
        try self.buf.writeLine("export default function Component($$anchor, $$props) {");
        self.buf.indent();

        if (node.node_type == .root) {
            const root = node.data.root;

            if (root.instance) |script| {
                try self.emitScriptContent(script);
                try self.buf.writeLine("");
            }

            try self.emitNode(root.fragment);
        }

        self.buf.dedent();
        try self.buf.writeLine("}");
    }

    fn emitScriptContent(self: *Self, node: *ast.Node) std.mem.Allocator.Error!void {
        if (node.node_type != .script) return;

        const script = node.data.script;
        if (script.content.len > 0) {
            var lines = std.mem.splitSequence(u8, script.content, "\n");
            while (lines.next()) |line| {
                const trimmed = std.mem.trim(u8, line, " \t");
                if (trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, "import ")) {
                    try self.buf.writeIndent();
                    try self.emitTransformedLine(trimmed);
                    try self.buf.writeLine("");
                }
            }
        }
    }

    fn emitTransformedLine(self: *Self, line: []const u8) !void {
        if (std.mem.indexOf(u8, line, "$props()")) |idx| {
            try self.buf.write(line[0..idx]);
            try self.buf.write("$$props");
            const after_props = idx + 8;
            if (after_props < line.len) {
                try self.buf.write(line[after_props..]);
            }
        } else if (std.mem.indexOf(u8, line, "$bindable(")) |idx| {
            try self.buf.write(line[0..idx]);
            try self.buf.write("$.bindable(");
            const after = idx + 10;
            if (after < line.len) {
                try self.buf.write(line[after..]);
            }
        } else if (std.mem.indexOf(u8, line, "$inspect(")) |idx| {
            try self.buf.write(line[0..idx]);
            try self.buf.write("$.inspect(");
            const after = idx + 9;
            if (after < line.len) {
                try self.buf.write(line[after..]);
            }
        } else if (std.mem.indexOf(u8, line, "$state(")) |idx| {
            try self.buf.write(line[0..idx]);
            try self.buf.write("$.state(");
            const after_state = idx + 7;
            if (after_state < line.len) {
                try self.buf.write(line[after_state..]);
            }
        } else if (std.mem.indexOf(u8, line, "$derived(")) |idx| {
            try self.buf.write(line[0..idx]);
            try self.buf.write("$.derived(() => ");
            if (std.mem.indexOf(u8, line[idx + 9 ..], ")")) |end_idx| {
                try self.buf.write(line[idx + 9 .. idx + 9 + end_idx]);
                try self.buf.write(")");
                const after = idx + 9 + end_idx + 1;
                if (after < line.len) {
                    try self.buf.write(line[after..]);
                }
            } else {
                try self.buf.write(line[idx + 9 ..]);
            }
        } else if (std.mem.indexOf(u8, line, "$effect(")) |_| {
            try self.buf.write("$.effect(");
            if (std.mem.indexOf(u8, line, "$effect(")) |idx| {
                try self.buf.write(line[idx + 8 ..]);
            }
        } else {
            try self.buf.write(line);
        }
    }

    pub fn emitNode(self: *Self, node: *ast.Node) std.mem.Allocator.Error!void {
        switch (node.node_type) {
            .fragment => {
                for (node.data.fragment.children.items) |child| {
                    try self.emitNode(child);
                }
            },
            .element => {
                const name = node.data.element.name;
                if (std.mem.eql(u8, name, "script") or std.mem.eql(u8, name, "style")) {
                    return;
                }
                try self.emitElement(node);
            },
            .component => try self.emitComponentUsage(node),
            .slot => try self.emitSlot(node),
            .text_node => try self.emitText(node),
            .expression_tag => try self.emitExpressionTag(node),
            .if_block => try self.emitIfBlock(node),
            .each_block => try self.emitEachBlock(node),
            .await_block => try self.emitAwaitBlock(node),
            .key_block => try self.emitKeyBlock(node),
            .snippet_block => try self.emitSnippet(node),
            .html_tag => try self.emitHtmlTag(node),
            .render_tag => try self.emitRenderTag(node),
            .const_tag => try self.emitConstTag(node),
            .debug_tag => try self.emitDebugTag(node),
            else => {},
        }
    }

    fn emitElement(self: *Self, node: *ast.Node) std.mem.Allocator.Error!void {
        const element = node.data.element;
        const id = self.template_count;
        self.template_count += 1;

        const is_void = isVoidElement(element.name);
        const static_content = self.getStaticContent(element.children.items);

        try self.buf.writeIndent();
        try self.buf.write("var $$t_");
        try self.buf.writeNumber(id);
        try self.buf.write(" = $.template(`<");
        try self.buf.write(element.name);

        if (self.scope_id) |sid| {
            try self.buf.write(" class=\"svelte-");
            try self.buf.write(sid[0..7]);
            try self.buf.write("\"");
        }

        for (element.attributes.items) |attr| {
            if (attr.node_type == .attribute) {
                try self.emitStaticAttribute(attr);
            }
        }

        if (is_void) {
            try self.buf.writeLine(" />`);");
        } else {
            try self.buf.write(">");
            if (static_content) |content| {
                try self.buf.write(content);
            }
            try self.buf.write("</");
            try self.buf.write(element.name);
            try self.buf.writeLine(">`);");
        }

        try self.buf.writeIndent();
        try self.buf.write("var $$n_");
        try self.buf.writeNumber(id);
        try self.buf.write(" = $.open($$anchor, $$t_");
        try self.buf.writeNumber(id);
        try self.buf.writeLine(");");

        for (element.attributes.items) |attr| {
            if (attr.node_type == .directive) {
                try self.emitDirective(attr, id);
            } else if (attr.node_type == .attribute) {
                try self.emitDynamicAttribute(attr, id);
            } else if (attr.node_type == .spread_attribute) {
                try self.emitSpreadAttribute(attr, id);
            }
        }

        if (static_content == null) {
            for (element.children.items) |child| {
                try self.emitNode(child);
            }
        }

        try self.buf.writeIndent();
        try self.buf.write("$.close($$anchor, $$n_");
        try self.buf.writeNumber(id);
        try self.buf.writeLine(");");
    }

    fn getStaticContent(self: *Self, children: []*ast.Node) ?[]const u8 {
        _ = self;
        if (children.len == 0) return null;
        if (children.len == 1) {
            const child = children[0];
            if (child.node_type == .text_node) {
                const text = child.data.text_node.data;
                const trimmed = std.mem.trim(u8, text, " \t\n\r");
                if (trimmed.len > 0) {
                    return trimmed;
                }
            }
        }
        return null;
    }

    fn isVoidElement(name: []const u8) bool {
        const void_elements = [_][]const u8{
            "area", "base", "br", "col", "embed", "hr", "img", "input",
            "link", "meta", "param", "source", "track", "wbr",
        };
        for (void_elements) |ve| {
            if (std.mem.eql(u8, name, ve)) return true;
        }
        return false;
    }

    fn emitStaticAttribute(self: *Self, node: *ast.Node) !void {
        const attr = node.data.attribute;
        switch (attr.value) {
            .text => |text| {
                try self.buf.write(" ");
                try self.buf.write(attr.name);
                try self.buf.write("=\"");
                try self.buf.write(text);
                try self.buf.write("\"");
            },
            .boolean => |val| {
                if (val) {
                    try self.buf.write(" ");
                    try self.buf.write(attr.name);
                }
            },
            else => {},
        }
    }

    fn emitDynamicAttribute(self: *Self, node: *ast.Node, element_id: u32) !void {
        const attr = node.data.attribute;
        switch (attr.value) {
            .expression => |expr| {
                const is_event = std.mem.startsWith(u8, attr.name, "on");
                try self.buf.writeIndent();
                if (is_event) {
                    try self.buf.write("$.on($$n_");
                    try self.buf.writeNumber(element_id);
                    try self.buf.write(", \"");
                    try self.buf.write(attr.name[2..]);
                    try self.buf.write("\", ");
                    try self.emitExpression(expr);
                    try self.buf.writeLine(");");
                } else {
                    try self.buf.write("$.attr($$n_");
                    try self.buf.writeNumber(element_id);
                    try self.buf.write(", \"");
                    try self.buf.write(attr.name);
                    try self.buf.write("\", () => ");
                    try self.emitExpression(expr);
                    try self.buf.writeLine(");");
                }
            },
            else => {},
        }
    }

    fn emitSpreadAttribute(self: *Self, node: *ast.Node, element_id: u32) !void {
        const spread = node.data.spread_attribute;
        try self.buf.writeIndent();
        try self.buf.write("$.spread($$n_");
        try self.buf.writeNumber(element_id);
        try self.buf.write(", () => ");
        try self.emitExpression(spread.expression);
        try self.buf.writeLine(");");
    }

    fn emitDirective(self: *Self, node: *ast.Node, element_id: u32) !void {
        const dir = node.data.directive;

        switch (dir.directive_type) {
            .on => {
                try self.buf.writeIndent();
                try self.buf.write("$.on($$n_");
                try self.buf.writeNumber(element_id);
                try self.buf.write(", \"");
                try self.buf.write(dir.name);
                try self.buf.write("\", ");
                if (dir.expression) |expr| {
                    try self.emitExpression(expr);
                } else {
                    try self.buf.write("() => {}");
                }
                if (dir.modifiers.items.len > 0) {
                    try self.buf.write(", { ");
                    for (dir.modifiers.items, 0..) |mod, i| {
                        if (i > 0) try self.buf.write(", ");
                        try self.buf.write(mod);
                        try self.buf.write(": true");
                    }
                    try self.buf.write(" }");
                }
                try self.buf.writeLine(");");
            },
            .bind => {
                try self.buf.writeIndent();
                try self.buf.write("$.bind_");
                try self.buf.write(dir.name);
                try self.buf.write("($$n_");
                try self.buf.writeNumber(element_id);
                if (dir.expression) |expr| {
                    try self.buf.write(", () => ");
                    try self.emitExpression(expr);
                    try self.buf.write(", v => ");
                    try self.emitExpression(expr);
                    try self.buf.write(" = v");
                }
                try self.buf.writeLine(");");
            },
            .class_directive => {
                try self.buf.writeIndent();
                try self.buf.write("$.toggle_class($$n_");
                try self.buf.writeNumber(element_id);
                try self.buf.write(", \"");
                try self.buf.write(dir.name);
                try self.buf.write("\", () => ");
                if (dir.expression) |expr| {
                    try self.emitExpression(expr);
                } else {
                    try self.buf.write("true");
                }
                try self.buf.writeLine(");");
            },
            .style_directive => {
                try self.buf.writeIndent();
                try self.buf.write("$.set_style($$n_");
                try self.buf.writeNumber(element_id);
                try self.buf.write(", \"");
                try self.buf.write(dir.name);
                try self.buf.write("\", () => ");
                if (dir.expression) |expr| {
                    try self.emitExpression(expr);
                } else {
                    try self.buf.write("\"\"");
                }
                try self.buf.writeLine(");");
            },
            .use => {
                try self.buf.writeIndent();
                try self.buf.write("$.action($$n_");
                try self.buf.writeNumber(element_id);
                try self.buf.write(", ");
                try self.buf.write(dir.name);
                if (dir.expression) |expr| {
                    try self.buf.write(", ");
                    try self.emitExpression(expr);
                }
                try self.buf.writeLine(");");
            },
            .transition => {
                try self.buf.writeIndent();
                try self.buf.write("$.transition($$n_");
                try self.buf.writeNumber(element_id);
                try self.buf.write(", ");
                try self.buf.write(dir.name);
                if (dir.expression) |expr| {
                    try self.buf.write(", ");
                    try self.emitExpression(expr);
                }
                try self.buf.writeLine(");");
            },
            else => {},
        }
    }

    fn emitComponentUsage(self: *Self, node: *ast.Node) !void {
        const comp = node.data.component;
        const has_children = comp.children.items.len > 0;

        try self.buf.writeIndent();
        try self.buf.write(comp.name);
        try self.buf.write("($$anchor, {");

        var first = true;
        for (comp.attributes.items) |attr| {
            if (attr.node_type == .attribute) {
                if (!first) try self.buf.write(", ");
                first = false;
                try self.buf.write(attr.data.attribute.name);
                try self.buf.write(": ");
                switch (attr.data.attribute.value) {
                    .text => |text| {
                        try self.buf.write("\"");
                        try self.buf.write(text);
                        try self.buf.write("\"");
                    },
                    .expression => |expr| try self.emitExpression(expr),
                    .boolean => |val| try self.buf.write(if (val) "true" else "false"),
                    else => {},
                }
            } else if (attr.node_type == .spread_attribute) {
                if (!first) try self.buf.write(", ");
                first = false;
                try self.buf.write("...");
                try self.emitExpression(attr.data.spread_attribute.expression);
            }
        }

        if (has_children) {
            if (!first) try self.buf.write(", ");
            try self.buf.write("children: ($$anchor) => {");
            try self.buf.writeLine("");
            self.buf.indent();
            for (comp.children.items) |child| {
                try self.emitNode(child);
            }
            self.buf.dedent();
            try self.buf.writeIndent();
            try self.buf.write("}");
        }

        try self.buf.writeLine("});");
    }

    fn emitSlot(self: *Self, node: *ast.Node) !void {
        const slot = node.data.slot;
        const slot_name = if (slot.name.len > 0) slot.name else "default";

        try self.buf.writeIndent();
        try self.buf.write("$.slot($$anchor, $$props, \"");
        try self.buf.write(slot_name);
        try self.buf.write("\"");

        if (slot.children.items.len > 0) {
            try self.buf.write(", ($$anchor) => {");
            try self.buf.writeLine("");
            self.buf.indent();
            for (slot.children.items) |child| {
                try self.emitNode(child);
            }
            self.buf.dedent();
            try self.buf.writeIndent();
            try self.buf.write("}");
        }

        try self.buf.writeLine(");");
    }

    fn emitText(self: *Self, node: *ast.Node) !void {
        const text = node.data.text_node;
        const trimmed = std.mem.trim(u8, text.data, " \t\n\r");
        if (trimmed.len == 0) return;

        try self.buf.writeIndent();
        try self.buf.write("$.text($$anchor, `");
        try self.buf.write(text.data);
        try self.buf.writeLine("`);");
    }

    fn emitExpressionTag(self: *Self, node: *ast.Node) !void {
        const id = self.template_count;
        self.template_count += 1;

        try self.buf.writeIndent();
        try self.buf.write("var $$text_");
        try self.buf.writeNumber(id);
        try self.buf.writeLine(" = $.text($$anchor);");

        try self.buf.writeIndent();
        try self.buf.write("$.template_effect(() => $.set_text($$text_");
        try self.buf.writeNumber(id);
        try self.buf.write(", ");
        try self.emitExpression(node.data.expression_tag.expression);
        try self.buf.writeLine("));");
    }

    fn emitIfBlock(self: *Self, node: *ast.Node) std.mem.Allocator.Error!void {
        const if_block = node.data.if_block;
        const id = self.block_count;
        self.block_count += 1;

        try self.buf.writeIndent();
        try self.buf.write("$.if($$anchor, () => ");
        try self.emitExpression(if_block.condition);
        try self.buf.writeLine(", ($$anchor) => {");

        self.buf.indent();
        try self.emitNode(if_block.consequent);
        self.buf.dedent();

        try self.buf.writeIndent();
        try self.buf.write("}");

        if (if_block.alternate) |alt| {
            try self.buf.writeLine(", ($$anchor) => {");
            self.buf.indent();
            try self.emitNode(alt);
            self.buf.dedent();
            try self.buf.writeIndent();
            try self.buf.write("}");
        }

        try self.buf.writeLine(");");
        _ = id;
    }

    fn emitEachBlock(self: *Self, node: *ast.Node) std.mem.Allocator.Error!void {
        const each = node.data.each_block;

        try self.buf.writeIndent();
        try self.buf.write("$.each($$anchor, () => ");
        try self.emitExpression(each.expression);
        try self.buf.write(", (");
        try self.emitExpression(each.context);
        if (each.index) |idx| {
            try self.buf.write(", ");
            try self.buf.write(idx);
        }
        try self.buf.writeLine(") => {");

        self.buf.indent();
        for (each.children.items) |child| {
            try self.emitNode(child);
        }
        self.buf.dedent();

        try self.buf.writeIndent();
        try self.buf.write("}");

        if (each.fallback) |fb| {
            try self.buf.writeLine(", () => {");
            self.buf.indent();
            try self.emitNode(fb);
            self.buf.dedent();
            try self.buf.writeIndent();
            try self.buf.write("}");
        }

        try self.buf.writeLine(");");
    }

    fn emitAwaitBlock(self: *Self, node: *ast.Node) std.mem.Allocator.Error!void {
        const await_block = node.data.await_block;

        try self.buf.writeIndent();
        try self.buf.write("$.await($$anchor, () => ");
        try self.emitExpression(await_block.expression);
        try self.buf.writeLine(", {");
        self.buf.indent();

        if (await_block.pending) |pending| {
            try self.buf.writeIndentedLine("pending: ($$anchor) => {");
            self.buf.indent();
            try self.emitNode(pending);
            self.buf.dedent();
            try self.buf.writeIndentedLine("},");
        }

        if (await_block.then_node) |then_node| {
            try self.buf.writeIndent();
            try self.buf.write("then: ($$anchor, ");
            if (await_block.value) |v| {
                try self.emitExpression(v);
            } else {
                try self.buf.write("_");
            }
            try self.buf.writeLine(") => {");
            self.buf.indent();
            try self.emitNode(then_node);
            self.buf.dedent();
            try self.buf.writeIndentedLine("},");
        }

        if (await_block.catch_node) |catch_node| {
            try self.buf.writeIndent();
            try self.buf.write("catch: ($$anchor, ");
            if (await_block.error_node) |e| {
                try self.emitExpression(e);
            } else {
                try self.buf.write("_");
            }
            try self.buf.writeLine(") => {");
            self.buf.indent();
            try self.emitNode(catch_node);
            self.buf.dedent();
            try self.buf.writeIndentedLine("},");
        }

        self.buf.dedent();
        try self.buf.writeIndentedLine("});");
    }

    fn emitKeyBlock(self: *Self, node: *ast.Node) std.mem.Allocator.Error!void {
        const key_block = node.data.key_block;

        try self.buf.writeIndent();
        try self.buf.write("$.key($$anchor, () => ");
        try self.emitExpression(key_block.expression);
        try self.buf.writeLine(", ($$anchor) => {");

        self.buf.indent();
        for (key_block.children.items) |child| {
            try self.emitNode(child);
        }
        self.buf.dedent();

        try self.buf.writeIndentedLine("});");
    }

    fn emitSnippet(self: *Self, node: *ast.Node) std.mem.Allocator.Error!void {
        const snippet = node.data.snippet_block;

        try self.buf.writeIndent();
        try self.buf.write("function ");
        try self.buf.write(snippet.name);
        try self.buf.write("($$anchor");
        for (snippet.parameters.items) |param| {
            try self.buf.write(", ");
            try self.emitExpression(param);
        }
        try self.buf.writeLine(") {");

        self.buf.indent();
        try self.emitNode(snippet.body);
        self.buf.dedent();

        try self.buf.writeIndentedLine("}");
    }

    fn emitHtmlTag(self: *Self, node: *ast.Node) !void {
        try self.buf.writeIndent();
        try self.buf.write("$.html($$anchor, () => ");
        try self.emitExpression(node.data.html_tag.expression);
        try self.buf.writeLine(");");
    }

    fn emitRenderTag(self: *Self, node: *ast.Node) !void {
        const render = node.data.render_tag;

        try self.buf.writeIndent();

        if (render.expression.node_type == .call_expr) {
            const call = render.expression.data.call_expr;
            try self.emitExpression(call.callee);
            try self.buf.write("($$anchor");
            for (call.arguments.items) |arg| {
                try self.buf.write(", ");
                try self.emitExpression(arg);
            }
            try self.buf.writeLine(");");
        } else {
            try self.emitExpression(render.expression);
            try self.buf.write("($$anchor");
            if (render.argument) |arg| {
                try self.buf.write(", ");
                try self.emitExpression(arg);
            }
            try self.buf.writeLine(");");
        }
    }

    fn emitConstTag(self: *Self, node: *ast.Node) !void {
        const const_tag = node.data.const_tag;
        try self.buf.writeIndent();
        try self.buf.write("const ");
        try self.emitExpression(const_tag.declaration);
        try self.buf.writeLine(";");
    }

    fn emitDebugTag(self: *Self, node: *ast.Node) !void {
        const debug_tag = node.data.debug_tag;
        try self.buf.writeIndent();
        try self.buf.write("console.log(");
        for (debug_tag.identifiers.items, 0..) |ident, i| {
            if (i > 0) try self.buf.write(", ");
            try self.buf.write("{");
            try self.emitExpression(ident);
            try self.buf.write(": ");
            try self.emitExpression(ident);
            try self.buf.write("}");
        }
        try self.buf.writeLine(");");
    }

    pub fn emitExpression(self: *Self, node: *ast.Node) !void {
        switch (node.node_type) {
            .identifier_expr => try self.buf.write(node.data.identifier_expr.name),
            .literal_expr => {
                const lit = node.data.literal_expr;
                switch (lit.value) {
                    .string => |s| {
                        try self.buf.write("\"");
                        try self.buf.write(s);
                        try self.buf.write("\"");
                    },
                    .number => |n| try self.buf.writeNumber(n),
                    .boolean => |b| try self.buf.write(if (b) "true" else "false"),
                    .null_val => try self.buf.write("null"),
                }
            },
            .member_expr => {
                const m = node.data.member_expr;
                try self.emitExpression(m.object);
                if (m.computed) {
                    try self.buf.write("[");
                    try self.emitExpression(m.property);
                    try self.buf.write("]");
                } else {
                    try self.buf.write(".");
                    try self.emitExpression(m.property);
                }
            },
            .call_expr => {
                const c = node.data.call_expr;
                try self.emitExpression(c.callee);
                try self.buf.write("(");
                for (c.arguments.items, 0..) |arg, i| {
                    if (i > 0) try self.buf.write(", ");
                    try self.emitExpression(arg);
                }
                try self.buf.write(")");
            },
            .binary_expr => {
                const b = node.data.binary_expr;
                try self.buf.write("(");
                try self.emitExpression(b.left);
                try self.buf.write(" ");
                try self.buf.write(b.operator);
                try self.buf.write(" ");
                try self.emitExpression(b.right);
                try self.buf.write(")");
            },
            .unary_expr => {
                const u = node.data.unary_expr;
                if (u.prefix) {
                    try self.buf.write(u.operator);
                    try self.emitExpression(u.argument);
                } else {
                    try self.emitExpression(u.argument);
                    try self.buf.write(u.operator);
                }
            },
            .conditional_expr => {
                const c = node.data.conditional_expr;
                try self.buf.write("(");
                try self.emitExpression(c.condition);
                try self.buf.write(" ? ");
                try self.emitExpression(c.consequent);
                try self.buf.write(" : ");
                try self.emitExpression(c.alternate);
                try self.buf.write(")");
            },
            .array_expr => {
                const a = node.data.array_expr;
                try self.buf.write("[");
                for (a.elements.items, 0..) |elem, i| {
                    if (i > 0) try self.buf.write(", ");
                    if (elem) |e| try self.emitExpression(e);
                }
                try self.buf.write("]");
            },
            .object_expr => {
                const o = node.data.object_expr;
                try self.buf.write("{");
                for (o.properties.items, 0..) |prop, i| {
                    if (i > 0) try self.buf.write(", ");
                    try self.emitExpression(prop);
                }
                try self.buf.write("}");
            },
            .arrow_expr => {
                const arrow = node.data.arrow_expr;
                try self.buf.write("(");
                for (arrow.params.items, 0..) |param, i| {
                    if (i > 0) try self.buf.write(", ");
                    try self.emitExpression(param);
                }
                try self.buf.write(") => ");
                try self.emitExpression(arrow.body);
            },
            .update_expr => {
                const upd = node.data.update_expr;
                if (upd.prefix) {
                    try self.buf.write(upd.operator);
                    try self.emitExpression(upd.argument);
                } else {
                    try self.emitExpression(upd.argument);
                    try self.buf.write(upd.operator);
                }
            },
            .assignment_expr => {
                const assign = node.data.assignment_expr;
                try self.emitExpression(assign.left);
                try self.buf.write(" ");
                try self.buf.write(assign.operator);
                try self.buf.write(" ");
                try self.emitExpression(assign.right);
            },
            else => {},
        }
    }
};
