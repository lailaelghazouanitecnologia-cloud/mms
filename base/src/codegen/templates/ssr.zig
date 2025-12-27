const std = @import("std");
const ast = @import("../../ast/nodes.zig");
const buffer = @import("../../utils/buffer.zig");

pub const SsrTemplate = struct {
    buf: buffer.WriteBuffer,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .buf = buffer.WriteBuffer.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buf.deinit();
    }

    pub fn generate(self: *Self, node: *ast.Node) ![]u8 {
        try self.emitImports();
        try self.buf.writeLine("");
        try self.emitComponent(node);
        return try self.buf.toOwnedSlice();
    }

    fn emitImports(self: *Self) !void {
        try self.buf.writeLine("import * as $ from 'mms/internal/server';");
    }

    fn emitComponent(self: *Self, node: *ast.Node) !void {
        try self.buf.writeLine("export default function Component($$payload, $$props) {");
        self.buf.indent();

        try self.buf.writeIndent();
        try self.buf.write("$$payload.out += `");

        if (node.node_type == .root) {
            try self.emitTemplate(node.data.root.fragment);
        }

        try self.buf.writeLine("`;");

        self.buf.dedent();
        try self.buf.writeLine("}");
    }

    fn emitTemplate(self: *Self, node: *ast.Node) std.mem.Allocator.Error!void {
        switch (node.node_type) {
            .fragment => {
                for (node.data.fragment.children.items) |child| {
                    try self.emitTemplate(child);
                }
            },
            .element => try self.emitElement(node),
            .text_node => try self.emitText(node),
            .expression_tag => try self.emitExpressionTag(node),
            .if_block => try self.emitIfBlock(node),
            .each_block => try self.emitEachBlock(node),
            else => {},
        }
    }

    fn emitElement(self: *Self, node: *ast.Node) std.mem.Allocator.Error!void {
        const element = node.data.element;

        try self.buf.write("<");
        try self.buf.write(element.name);

        for (element.attributes.items) |attr| {
            if (attr.node_type == .attribute) {
                const a = attr.data.attribute;
                switch (a.value) {
                    .text => |text| {
                        try self.buf.write(" ");
                        try self.buf.write(a.name);
                        try self.buf.write("=\"");
                        try self.buf.write(text);
                        try self.buf.write("\"");
                    },
                    .expression => {
                        try self.buf.write(" ");
                        try self.buf.write(a.name);
                        try self.buf.write("=\"${$.escape(");
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
            }
        }

        if (element.self_closing) {
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

        try self.buf.write("${");
        try self.emitExpression(each.expression);
        try self.buf.write(".map((");
        try self.emitExpression(each.context);
        if (each.index) |idx| {
            try self.buf.write(", ");
            try self.buf.write(idx);
        }
        try self.buf.write(") => `");

        for (each.children.items) |child| {
            try self.emitTemplate(child);
        }

        try self.buf.write("`).join('')}");
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
