const std = @import("std");
const ast = @import("../../ast/nodes.zig");

/// Block parsing utilities for control flow blocks
pub const BlockParser = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    /// Create an if block node
    pub fn createIfBlock(
        self: *Self,
        condition: *ast.Node,
        consequent: *ast.Node,
        alternate: ?*ast.Node,
        elseif: bool,
    ) !*ast.Node {
        const data = ast.NodeData{
            .if_block = .{
                .condition = condition,
                .consequent = consequent,
                .alternate = alternate,
                .elseif = elseif,
            },
        };
        return ast.createNode(self.allocator, .if_block, ast.defaultSpan(), data);
    }

    /// Create an each block node
    pub fn createEachBlock(
        self: *Self,
        expression: *ast.Node,
        context: *ast.Node,
        index: ?[]const u8,
        key: ?*ast.Node,
        children: std.ArrayList(*ast.Node),
        fallback: ?*ast.Node,
    ) !*ast.Node {
        const data = ast.NodeData{
            .each_block = .{
                .expression = expression,
                .context = context,
                .index = index,
                .key = key,
                .children = children,
                .fallback = fallback,
            },
        };
        return ast.createNode(self.allocator, .each_block, ast.defaultSpan(), data);
    }

    /// Create an await block node
    pub fn createAwaitBlock(
        self: *Self,
        expression: *ast.Node,
        value: ?[]const u8,
        error_name: ?[]const u8,
        pending: ?*ast.Node,
        then: ?*ast.Node,
        catch_block: ?*ast.Node,
    ) !*ast.Node {
        const data = ast.NodeData{
            .await_block = .{
                .expression = expression,
                .value = value,
                .error_name = error_name,
                .pending = pending,
                .then = then,
                .catch_block = catch_block,
            },
        };
        return ast.createNode(self.allocator, .await_block, ast.defaultSpan(), data);
    }

    /// Create a key block node
    pub fn createKeyBlock(
        self: *Self,
        expression: *ast.Node,
        children: std.ArrayList(*ast.Node),
    ) !*ast.Node {
        const data = ast.NodeData{
            .key_block = .{
                .expression = expression,
                .children = children,
            },
        };
        return ast.createNode(self.allocator, .key_block, ast.defaultSpan(), data);
    }

    /// Create a snippet block node
    pub fn createSnippetBlock(
        self: *Self,
        name: []const u8,
        parameters: std.ArrayList(*ast.Node),
        body: *ast.Node,
    ) !*ast.Node {
        const data = ast.NodeData{
            .snippet_block = .{
                .name = name,
                .parameters = parameters,
                .body = body,
            },
        };
        return ast.createNode(self.allocator, .snippet_block, ast.defaultSpan(), data);
    }

    /// Create a fragment node
    pub fn createFragment(
        self: *Self,
        children: std.ArrayList(*ast.Node),
        transparent: bool,
    ) !*ast.Node {
        const data = ast.NodeData{
            .fragment = .{
                .children = children,
                .transparent = transparent,
            },
        };
        return ast.createNode(self.allocator, .fragment, ast.defaultSpan(), data);
    }
};

/// Block type enumeration for parsing
pub const BlockType = enum {
    if_block,
    each_block,
    await_block,
    key_block,
    snippet_block,
    unknown,

    pub fn fromKeyword(keyword: []const u8) BlockType {
        if (std.mem.eql(u8, keyword, "if")) return .if_block;
        if (std.mem.eql(u8, keyword, "each")) return .each_block;
        if (std.mem.eql(u8, keyword, "await")) return .await_block;
        if (std.mem.eql(u8, keyword, "key")) return .key_block;
        if (std.mem.eql(u8, keyword, "snippet")) return .snippet_block;
        return .unknown;
    }
};

/// Check if a token value is a block closing keyword
pub fn isBlockClosingKeyword(value: []const u8) bool {
    return std.mem.eql(u8, value, "/if") or
        std.mem.eql(u8, value, "/each") or
        std.mem.eql(u8, value, "/await") or
        std.mem.eql(u8, value, "/key") or
        std.mem.eql(u8, value, "/snippet");
}

/// Check if a token value is a block continuation keyword
pub fn isBlockContinuationKeyword(value: []const u8) bool {
    return std.mem.startsWith(u8, value, ":else") or
        std.mem.startsWith(u8, value, ":then") or
        std.mem.startsWith(u8, value, ":catch");
}

test "block parser" {
    const testing = std.testing;

    try testing.expectEqual(BlockType.if_block, BlockType.fromKeyword("if"));
    try testing.expectEqual(BlockType.each_block, BlockType.fromKeyword("each"));
    try testing.expect(isBlockClosingKeyword("/if"));
    try testing.expect(!isBlockClosingKeyword("if"));
}
