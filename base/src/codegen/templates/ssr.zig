const std = @import("std");
const ast = @import("../../ast/nodes.zig");
const buffer = @import("../../utils/buffer.zig");

pub const SsrTemplate = struct {
    buf: buffer.WriteBuffer,
    allocator: std.mem.Allocator,
    scope_id: ?*const [8]u8,
    effect_depth: u32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .buf = buffer.WriteBuffer.init(allocator),
            .allocator = allocator,
            .scope_id = null,
            .effect_depth = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buf.deinit();
    }

    pub fn generate(self: *Self, node: *ast.Node) ![]u8 {
        try self.buf.writeLine("import * as $ from 'mms/internal/server';");

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

    fn emitComponent(self: *Self, node: *ast.Node) !void {
        try self.buf.writeLine("export default function Component($$payload, $$props) {");
        self.buf.indent();

        if (node.node_type == .root) {
            const root = node.data.root;
            if (root.instance) |script| {
                try self.emitScriptContent(script);
            }
        }

        try self.buf.writeIndent();
        try self.buf.write("$$payload.out += `");

        if (node.node_type == .root) {
            try self.emitTemplate(node.data.root.fragment);
        }

        try self.buf.writeLine("`;");

        self.buf.dedent();
        try self.buf.writeLine("}");
    }

    fn emitScriptContent(self: *Self, node: *ast.Node) !void {
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
        if (std.mem.indexOf(u8, line, "$effect(") != null) {
            self.effect_depth += 1;
            return;
        }

        if (self.effect_depth > 0) {
            if (std.mem.indexOf(u8, line, "});") != null) {
                self.effect_depth -= 1;
            }
            return;
        }

        if (std.mem.indexOf(u8, line, "$inspect(") != null) {
            return;
        }

        if (std.mem.indexOf(u8, line, "$props()")) |idx| {
            try self.buf.write(line[0..idx]);
            try self.buf.write("$$props");
            const after_props = idx + 8;
            if (after_props < line.len) {
                try self.buf.write(line[after_props..]);
            }
        } else if (std.mem.indexOf(u8, line, "$bindable(")) |idx| {
            try self.buf.write(line[0..idx]);
            const after = idx + 10;
            if (after < line.len) {
                if (std.mem.lastIndexOf(u8, line, ");")) |close_idx| {
                    try self.buf.write(line[after..close_idx]);
                    try self.buf.write(";");
                } else {
                    try self.buf.write(line[after..]);
                }
            }
        } else if (std.mem.indexOf(u8, line, "$state(")) |idx| {
            try self.buf.write(line[0..idx]);
            const after_state = idx + 7;
            if (after_state < line.len) {
                if (std.mem.lastIndexOf(u8, line, ");")) |close_idx| {
                    try self.buf.write(line[after_state..close_idx]);
                    try self.buf.write(";");
                } else {
                    try self.buf.write(line[after_state..]);
                }
            }
        } else if (std.mem.indexOf(u8, line, "$derived(")) |idx| {
            try self.buf.write(line[0..idx]);
            const after = idx + 9;
            if (after < line.len) {
                if (std.mem.lastIndexOf(u8, line, ");")) |close_idx| {
                    try self.buf.write(line[after..close_idx]);
                    try self.buf.write(";");
                } else {
                    try self.buf.write(line[after..]);
                }
            }
        } else if (std.mem.eql(u8, line, "]);")) {
            try self.buf.write("];");
        } else {
            try self.buf.write(line);
        }
    }

    fn emitTemplate(self: *Self, node: *ast.Node) std.mem.Allocator.Error!void {
        switch (node.node_type) {
            .fragment => {
                for (node.data.fragment.children.items) |child| {
                    try self.emitTemplate(child);
                }
            },
            .element => try self.emitElement(node),
            .component => try self.emitComponentUsage(node),
            .slot => try self.emitSlot(node),
            .text_node => try self.emitText(node),
            .expression_tag => try self.emitExpressionTag(node),
            .if_block => try self.emitIfBlock(node),
            .each_block => try self.emitEachBlock(node),
            .await_block => try self.emitAwaitBlock(node),
            .html_tag => try self.emitHtmlTag(node),
            .const_tag => try self.emitConstTag(node),
            .debug_tag => try self.emitDebugTag(node),
            else => {},
        }
    }

    fn emitComponentUsage(self: *Self, node: *ast.Node) !void {
        const comp = node.data.component;
        try self.buf.write("`;\n");
        try self.buf.writeIndent();
        try self.buf.write(comp.name);
        try self.buf.write("($$payload, {");

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
            }
        }

        if (comp.children.items.len > 0) {
            if (!first) try self.buf.write(", ");
            try self.buf.write("children: ($$payload) => { $$payload.out += `");
            for (comp.children.items) |child| {
                try self.emitTemplate(child);
            }
            try self.buf.write("`; }");
        }

        try self.buf.writeLine("});");
        try self.buf.writeIndent();
        try self.buf.write("$$payload.out += `");
    }

    fn emitSlot(self: *Self, node: *ast.Node) !void {
        const slot = node.data.slot;
        const slot_name = if (slot.name.len > 0) slot.name else "default";

        try self.buf.write("`;\n");
        try self.buf.writeIndent();
        try self.buf.write("if ($$props.");
        if (std.mem.eql(u8, slot_name, "default")) {
            try self.buf.write("children");
        } else {
            try self.buf.write(slot_name);
        }
        try self.buf.write(") { $$props.");
        if (std.mem.eql(u8, slot_name, "default")) {
            try self.buf.write("children");
        } else {
            try self.buf.write(slot_name);
        }
        try self.buf.write("($$payload); } else { $$payload.out += `");
        for (slot.children.items) |child| {
            try self.emitTemplate(child);
        }
        try self.buf.writeLine("`; }");
        try self.buf.writeIndent();
        try self.buf.write("$$payload.out += `");
    }

    fn emitElement(self: *Self, node: *ast.Node) std.mem.Allocator.Error!void {
        const element = node.data.element;

        if (std.mem.eql(u8, element.name, "script") or std.mem.eql(u8, element.name, "style")) {
            return;
        }

        const is_void = isVoidElement(element.name);

        try self.buf.write("<");
        try self.buf.write(element.name);

        if (self.scope_id) |sid| {
            try self.buf.write(" class=\"svelte-");
            try self.buf.write(sid[0..7]);
            try self.buf.write("\"");
        }

        var has_class_attr = false;
        var class_directives = std.ArrayList(*ast.Node).init(self.allocator);
        defer class_directives.deinit();

        for (element.attributes.items) |attr| {
            if (attr.node_type == .attribute) {
                const a = attr.data.attribute;
                if (std.mem.startsWith(u8, a.name, "on")) continue;
                if (std.mem.eql(u8, a.name, "class")) has_class_attr = true;
                switch (a.value) {
                    .text => |text| {
                        try self.buf.write(" ");
                        try self.buf.write(a.name);
                        try self.buf.write("=\"");
                        try self.buf.write(text);
                        try self.buf.write("\"");
                    },
                    .expression => |expr| {
                        try self.buf.write(" ");
                        try self.buf.write(a.name);
                        try self.buf.write("=\"${$.escape(");
                        try self.emitExpression(expr);
                        try self.buf.write(")}\"");
                    },
                    .boolean => |val| {
                        if (val) {
                            try self.buf.write(" ");
                            try self.buf.write(a.name);
                        }
                    },
                    else => {},
                }
            } else if (attr.node_type == .directive) {
                const dir = attr.data.directive;
                if (dir.directive_type == .class_directive) {
                    try class_directives.append(attr);
                } else if (dir.directive_type == .style_directive) {
                    try self.buf.write(" style=\"");
                    try self.buf.write(dir.name);
                    try self.buf.write(": ${");
                    if (dir.expression) |expr| {
                        try self.emitExpression(expr);
                    }
                    try self.buf.write("}\"");
                }
            }
        }

        if (class_directives.items.len > 0) {
            if (!has_class_attr) {
                try self.buf.write(" class=\"");
            }
            try self.buf.write("${[");
            for (class_directives.items, 0..) |dir_node, i| {
                if (i > 0) try self.buf.write(", ");
                const dir = dir_node.data.directive;
                try self.buf.write("[\"");
                try self.buf.write(dir.name);
                try self.buf.write("\", ");
                if (dir.expression) |expr| {
                    try self.emitExpression(expr);
                } else {
                    try self.buf.write("true");
                }
                try self.buf.write("]");
            }
            try self.buf.write("].filter(([,v]) => v).map(([k]) => k).join(' ')}");
            if (!has_class_attr) {
                try self.buf.write("\"");
            }
        }

        if (is_void) {
            try self.buf.write(" />");
        } else {
            try self.buf.write(">");
            for (element.children.items) |child| {
                try self.emitTemplate(child);
            }
            try self.buf.write("</");
            try self.buf.write(element.name);
            try self.buf.write(">");
        }
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

    fn emitText(self: *Self, node: *ast.Node) !void {
        try self.emitEscaped(node.data.text_node.data);
    }

    fn emitExpressionTag(self: *Self, node: *ast.Node) !void {
        try self.buf.write("${$.escape(");
        try self.emitExpression(node.data.expression_tag.expression);
        try self.buf.write(")}");
    }

    fn emitIfBlock(self: *Self, node: *ast.Node) std.mem.Allocator.Error!void {
        const if_block = node.data.if_block;

        try self.buf.write("${");
        try self.emitExpression(if_block.condition);
        try self.buf.write(" ? `");
        try self.emitTemplate(if_block.consequent);
        try self.buf.write("` : `");
        if (if_block.alternate) |alt| {
            try self.emitTemplate(alt);
        }
        try self.buf.write("`}");
    }

    fn emitEachBlock(self: *Self, node: *ast.Node) std.mem.Allocator.Error!void {
        const each = node.data.each_block;
        const has_const = self.hasConstTag(each.children.items);

        try self.buf.write("${");
        try self.emitExpression(each.expression);
        try self.buf.write(".map((");
        try self.emitExpression(each.context);
        if (each.index) |idx| {
            try self.buf.write(", ");
            try self.buf.write(idx);
        }

        if (has_const) {
            try self.buf.write(") => {\n");
            self.buf.indent();
            for (each.children.items) |child| {
                if (child.node_type == .const_tag) {
                    try self.buf.writeIndent();
                    try self.buf.write("const ");
                    try self.emitExpression(child.data.const_tag.declaration);
                    try self.buf.writeLine(";");
                }
            }
            try self.buf.writeIndent();
            try self.buf.write("return `");
            for (each.children.items) |child| {
                if (child.node_type != .const_tag and child.node_type != .debug_tag) {
                    try self.emitTemplate(child);
                }
            }
            try self.buf.writeLine("`;");
            self.buf.dedent();
            try self.buf.writeIndent();
            try self.buf.write("}).join('')}");
        } else {
            try self.buf.write(") => `");
            for (each.children.items) |child| {
                try self.emitTemplate(child);
            }
            try self.buf.write("`).join('')}");
        }
    }

    fn hasConstTag(self: *Self, children: []*ast.Node) bool {
        _ = self;
        for (children) |child| {
            if (child.node_type == .const_tag) return true;
        }
        return false;
    }

    fn emitAwaitBlock(self: *Self, node: *ast.Node) std.mem.Allocator.Error!void {
        const await_block = node.data.await_block;

        if (await_block.pending) |pending| {
            try self.emitTemplate(pending);
        }
    }

    fn emitHtmlTag(self: *Self, node: *ast.Node) std.mem.Allocator.Error!void {
        const html_tag = node.data.html_tag;
        try self.buf.write("${");
        try self.emitExpression(html_tag.expression);
        try self.buf.write("}");
    }

    fn emitConstTag(self: *Self, node: *ast.Node) !void {
        const const_tag = node.data.const_tag;
        try self.buf.write("`;\n");
        try self.buf.writeIndent();
        try self.buf.write("const ");
        try self.emitExpression(const_tag.declaration);
        try self.buf.writeLine(";");
        try self.buf.writeIndent();
        try self.buf.write("$$payload.out += `");
    }

    fn emitDebugTag(self: *Self, node: *ast.Node) !void {
        _ = self;
        _ = node;
    }

    fn emitExpression(self: *Self, node: *ast.Node) !void {
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

    fn emitEscaped(self: *Self, str: []const u8) !void {
        for (str) |c| {
            switch (c) {
                '\\' => try self.buf.write("\\\\"),
                '`' => try self.buf.write("\\`"),
                '$' => try self.buf.write("\\$"),
                else => try self.buf.writeByte(c),
            }
        }
    }
};
