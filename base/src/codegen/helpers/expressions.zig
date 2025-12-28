const std = @import("std");
const ast = @import("../../ast/nodes.zig");
const buffer = @import("../../utils/buffer.zig");

/// Shared expression emitter for both DOM and SSR code generation
pub const ExpressionEmitter = struct {
    buf: *buffer.WriteBuffer,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(buf: *buffer.WriteBuffer, allocator: std.mem.Allocator) Self {
        return .{
            .buf = buf,
            .allocator = allocator,
        };
    }

    pub fn emit(self: *Self, node: *ast.Node) std.mem.Allocator.Error!void {
        switch (node.node_type) {
            .identifier_expr => try self.emitIdentifier(node),
            .literal_expr => try self.emitLiteral(node),
            .binary_expr => try self.emitBinary(node),
            .unary_expr => try self.emitUnary(node),
            .member_expr => try self.emitMember(node),
            .call_expr => try self.emitCall(node),
            .array_expr => try self.emitArray(node),
            .object_expr => try self.emitObject(node),
            .arrow_function => try self.emitArrowFunction(node),
            .conditional_expr => try self.emitConditional(node),
            .template_literal => try self.emitTemplateLiteral(node),
            .assignment_expr => try self.emitAssignment(node),
            .await_expression => try self.emitAwait(node),
            .spread_element => try self.emitSpread(node),
            .new_expr => try self.emitNew(node),
            else => {},
        }
    }

    fn emitIdentifier(self: *Self, node: *ast.Node) !void {
        const id = node.data.identifier_expr;
        // Handle store subscriptions ($store -> get(store))
        if (id.name.len > 0 and id.name[0] == '$' and !isRune(id.name)) {
            try self.buf.write("$.get(");
            try self.buf.write(id.name[1..]);
            try self.buf.write(")");
        } else {
            try self.buf.write(id.name);
        }
    }

    fn emitLiteral(self: *Self, node: *ast.Node) !void {
        const lit = node.data.literal_expr;
        switch (lit.kind) {
            .string => {
                try self.buf.write("\"");
                try self.buf.write(lit.value);
                try self.buf.write("\"");
            },
            .number, .boolean => try self.buf.write(lit.value),
            .null_val => try self.buf.write("null"),
            .undefined => try self.buf.write("undefined"),
            .regex => {
                try self.buf.write("/");
                try self.buf.write(lit.value);
                try self.buf.write("/");
            },
        }
    }

    fn emitBinary(self: *Self, node: *ast.Node) !void {
        const bin = node.data.binary_expr;
        try self.buf.write("(");
        try self.emit(bin.left);
        try self.buf.write(" ");
        try self.buf.write(bin.operator);
        try self.buf.write(" ");
        try self.emit(bin.right);
        try self.buf.write(")");
    }

    fn emitUnary(self: *Self, node: *ast.Node) !void {
        const un = node.data.unary_expr;
        if (un.prefix) {
            try self.buf.write(un.operator);
            try self.emit(un.operand);
        } else {
            try self.emit(un.operand);
            try self.buf.write(un.operator);
        }
    }

    fn emitMember(self: *Self, node: *ast.Node) !void {
        const m = node.data.member_expr;
        try self.emit(m.object);
        if (m.computed) {
            if (m.optional) {
                try self.buf.write("?.[");
            } else {
                try self.buf.write("[");
            }
            try self.emit(m.property);
            try self.buf.write("]");
        } else {
            if (m.optional) {
                try self.buf.write("?.");
            } else {
                try self.buf.write(".");
            }
            try self.emit(m.property);
        }
    }

    fn emitCall(self: *Self, node: *ast.Node) !void {
        const call = node.data.call_expr;
        try self.emit(call.callee);
        try self.buf.write("(");
        for (call.arguments.items, 0..) |arg, i| {
            if (i > 0) try self.buf.write(", ");
            try self.emit(arg);
        }
        try self.buf.write(")");
    }

    fn emitArray(self: *Self, node: *ast.Node) !void {
        const arr = node.data.array_expr;
        try self.buf.write("[");
        for (arr.elements.items, 0..) |elem, i| {
            if (i > 0) try self.buf.write(", ");
            try self.emit(elem);
        }
        try self.buf.write("]");
    }

    fn emitObject(self: *Self, node: *ast.Node) !void {
        const obj = node.data.object_expr;
        try self.buf.write("{ ");
        for (obj.properties.items, 0..) |prop, i| {
            if (i > 0) try self.buf.write(", ");
            if (prop.node_type == .spread_element) {
                try self.emitSpread(prop);
            } else if (prop.node_type == .property) {
                const p = prop.data.property;
                if (p.shorthand) {
                    try self.buf.write(p.key);
                } else {
                    if (p.computed) {
                        try self.buf.write("[");
                        try self.buf.write(p.key);
                        try self.buf.write("]");
                    } else {
                        try self.buf.write(p.key);
                    }
                    try self.buf.write(": ");
                    if (p.value) |val| {
                        try self.emit(val);
                    }
                }
            }
        }
        try self.buf.write(" }");
    }

    fn emitArrowFunction(self: *Self, node: *ast.Node) !void {
        const arrow = node.data.arrow_function;
        try self.buf.write("(");
        for (arrow.params.items, 0..) |param, i| {
            if (i > 0) try self.buf.write(", ");
            if (param.node_type == .identifier_expr) {
                try self.buf.write(param.data.identifier_expr.name);
            } else {
                try self.emit(param);
            }
        }
        try self.buf.write(") => ");
        if (arrow.expression) {
            try self.emit(arrow.body);
        } else {
            try self.buf.write("{ ");
            try self.emit(arrow.body);
            try self.buf.write(" }");
        }
    }

    fn emitConditional(self: *Self, node: *ast.Node) !void {
        const cond = node.data.conditional_expr;
        try self.buf.write("(");
        try self.emit(cond.test);
        try self.buf.write(" ? ");
        try self.emit(cond.consequent);
        try self.buf.write(" : ");
        try self.emit(cond.alternate);
        try self.buf.write(")");
    }

    fn emitTemplateLiteral(self: *Self, node: *ast.Node) !void {
        const tpl = node.data.template_literal;
        try self.buf.write("`");
        for (tpl.parts.items) |part| {
            if (part.node_type == .text) {
                try self.buf.write(part.data.text.raw);
            } else {
                try self.buf.write("${");
                try self.emit(part);
                try self.buf.write("}");
            }
        }
        try self.buf.write("`");
    }

    fn emitAssignment(self: *Self, node: *ast.Node) !void {
        const assign = node.data.assignment_expr;
        try self.emit(assign.left);
        try self.buf.write(" ");
        try self.buf.write(assign.operator);
        try self.buf.write(" ");
        try self.emit(assign.right);
    }

    fn emitAwait(self: *Self, node: *ast.Node) !void {
        const aw = node.data.await_expression;
        try self.buf.write("await ");
        try self.emit(aw.argument);
    }

    fn emitSpread(self: *Self, node: *ast.Node) !void {
        const spread = node.data.spread_element;
        try self.buf.write("...");
        try self.emit(spread.argument);
    }

    fn emitNew(self: *Self, node: *ast.Node) !void {
        const new = node.data.new_expr;
        try self.buf.write("new ");
        try self.emit(new.callee);
        try self.buf.write("(");
        for (new.arguments.items, 0..) |arg, i| {
            if (i > 0) try self.buf.write(", ");
            try self.emit(arg);
        }
        try self.buf.write(")");
    }
};

fn isRune(name: []const u8) bool {
    const runes = [_][]const u8{
        "$state",
        "$derived",
        "$effect",
        "$props",
        "$bindable",
        "$inspect",
        "$host",
    };
    for (runes) |rune| {
        if (std.mem.startsWith(u8, name, rune)) return true;
    }
    return false;
}

test "expression emitter" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var buf = buffer.WriteBuffer.init(alloc);
    defer buf.deinit();

    var emitter = ExpressionEmitter.init(&buf, alloc);
    _ = emitter;
    // Add tests here
}
