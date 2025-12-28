const std = @import("std");
const ast = @import("../../ast/nodes.zig");
const buffer = @import("../../utils/buffer.zig");
const ExpressionEmitter = @import("expressions.zig").ExpressionEmitter;

/// Base functionality shared between DOM and SSR emitters
pub const EmitterBase = struct {
    buf: *buffer.WriteBuffer,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(buf: *buffer.WriteBuffer, allocator: std.mem.Allocator) Self {
        return .{
            .buf = buf,
            .allocator = allocator,
        };
    }

    /// Extract and emit module-level imports from script
    pub fn emitModuleLevelImports(self: *Self, node: *ast.Node) !void {
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

    /// Emit an expression using the shared expression emitter
    pub fn emitExpression(self: *Self, node: *ast.Node) !void {
        var emitter = ExpressionEmitter.init(self.buf, self.allocator);
        try emitter.emit(node);
    }

    /// Emit non-import script content
    pub fn emitScriptBody(self: *Self, node: *ast.Node) !void {
        if (node.node_type != .script) return;

        const script = node.data.script;
        if (script.content.len > 0) {
            var lines = std.mem.splitSequence(u8, script.content, "\n");
            while (lines.next()) |line| {
                const trimmed = std.mem.trim(u8, line, " \t");
                if (trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, "import ")) {
                    try self.buf.writeIndent();
                    try self.buf.write(trimmed);
                    try self.buf.writeLine("");
                }
            }
        }
    }

    /// Emit text content with proper escaping
    pub fn emitTextContent(self: *Self, text: []const u8) !void {
        for (text) |c| {
            switch (c) {
                '<' => try self.buf.write("&lt;"),
                '>' => try self.buf.write("&gt;"),
                '&' => try self.buf.write("&amp;"),
                '"' => try self.buf.write("&quot;"),
                else => try self.buf.writeChar(c),
            }
        }
    }

    /// Emit escaped text for JavaScript strings
    pub fn emitJsString(self: *Self, text: []const u8) !void {
        for (text) |c| {
            switch (c) {
                '\\' => try self.buf.write("\\\\"),
                '"' => try self.buf.write("\\\""),
                '\n' => try self.buf.write("\\n"),
                '\r' => try self.buf.write("\\r"),
                '\t' => try self.buf.write("\\t"),
                else => try self.buf.writeChar(c),
            }
        }
    }

    /// Emit escaped text for template literals
    pub fn emitTemplateString(self: *Self, text: []const u8) !void {
        for (text) |c| {
            switch (c) {
                '`' => try self.buf.write("\\`"),
                '$' => try self.buf.write("\\$"),
                '\\' => try self.buf.write("\\\\"),
                else => try self.buf.writeChar(c),
            }
        }
    }
};

/// Rune detection for $state, $derived, etc.
pub fn isRune(name: []const u8) bool {
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

/// Check if identifier is a store subscription ($store)
pub fn isStoreSubscription(name: []const u8) bool {
    return name.len > 0 and name[0] == '$' and !isRune(name);
}

test "emitter base" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var buf = buffer.WriteBuffer.init(alloc);
    defer buf.deinit();

    var emitter = EmitterBase.init(&buf, alloc);

    try emitter.emitJsString("hello\nworld");
    const result = try buf.toOwnedSlice();
    try testing.expectEqualStrings("hello\\nworld", result);
}
