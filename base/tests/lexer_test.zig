const std = @import("std");
const Lexer = @import("../src/lexer/lexer.zig").Lexer;
const ast = @import("../src/ast/nodes.zig");

test "lexer basic element" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "<div>Hello</div>");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    try std.testing.expect(tokens.len > 0);
    try std.testing.expectEqual(tokens[0].type, ast.TokenType.open_tag);
}

test "lexer mustache" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "{name}");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    try std.testing.expect(tokens.len > 0);
}

test "lexer if block" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "{#if condition}content{/if}");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    try std.testing.expect(tokens.len > 0);
}

test "lexer each block" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "{#each items as item}{/each}");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    try std.testing.expect(tokens.len > 0);
}

test "lexer string" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "\"hello world\"");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    try std.testing.expect(tokens.len > 0);
    try std.testing.expectEqual(tokens[0].type, ast.TokenType.string);
}

test "lexer number" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "123.45");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    try std.testing.expect(tokens.len > 0);
    try std.testing.expectEqual(tokens[0].type, ast.TokenType.number);
}

test "lexer directive" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "<button on:click={handler}>");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    try std.testing.expect(tokens.len > 0);
}

test "lexer self closing" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "<input />");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    try std.testing.expect(tokens.len > 0);
}
