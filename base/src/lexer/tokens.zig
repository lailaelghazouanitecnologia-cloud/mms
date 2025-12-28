const std = @import("std");
const ast = @import("../ast/nodes.zig");

/// Token classification and utilities
pub const TokenClassifier = struct {
    /// Check if token type is a comparison operator
    pub fn isComparisonOp(token_type: ast.TokenType) bool {
        return switch (token_type) {
            .lt, .gt, .lte, .gte => true,
            else => false,
        };
    }

    /// Check if token type is an equality operator
    pub fn isEqualityOp(token_type: ast.TokenType) bool {
        return switch (token_type) {
            .eq, .neq => true,
            else => false,
        };
    }

    /// Check if token type is an additive operator
    pub fn isAdditiveOp(token_type: ast.TokenType) bool {
        return switch (token_type) {
            .plus, .minus => true,
            else => false,
        };
    }

    /// Check if token type is a multiplicative operator
    pub fn isMultiplicativeOp(token_type: ast.TokenType) bool {
        return switch (token_type) {
            .star, .slash, .percent => true,
            else => false,
        };
    }

    /// Check if token type is a unary operator
    pub fn isUnaryOp(token_type: ast.TokenType) bool {
        return switch (token_type) {
            .bang, .minus, .plus => true,
            else => false,
        };
    }

    /// Check if token type is an assignment operator
    pub fn isAssignmentOp(token_type: ast.TokenType) bool {
        return token_type == .assign;
    }

    /// Check if token type is a logical operator
    pub fn isLogicalOp(token_type: ast.TokenType) bool {
        return switch (token_type) {
            .and_op, .or_op, .nullish_coalesce => true,
            else => false,
        };
    }

    /// Check if token type starts an expression
    pub fn startsExpression(token_type: ast.TokenType) bool {
        return switch (token_type) {
            .identifier,
            .number,
            .string,
            .template_start,
            .lparen,
            .lbracket,
            .lbrace,
            .bang,
            .minus,
            .plus,
            .keyword,
            => true,
            else => false,
        };
    }

    /// Check if token type is a literal
    pub fn isLiteral(token_type: ast.TokenType) bool {
        return switch (token_type) {
            .number, .string, .keyword => true,
            else => false,
        };
    }
};

/// Token value helpers
pub const TokenValue = struct {
    /// Check if value is a JavaScript keyword
    pub fn isKeyword(value: []const u8) bool {
        const keywords = [_][]const u8{
            "true",
            "false",
            "null",
            "undefined",
            "new",
            "typeof",
            "instanceof",
            "in",
            "void",
            "delete",
            "await",
            "async",
            "function",
            "class",
            "const",
            "let",
            "var",
            "if",
            "else",
            "for",
            "while",
            "do",
            "switch",
            "case",
            "break",
            "continue",
            "return",
            "throw",
            "try",
            "catch",
            "finally",
            "this",
            "super",
        };
        for (keywords) |kw| {
            if (std.mem.eql(u8, value, kw)) return true;
        }
        return false;
    }

    /// Check if value is a boolean literal
    pub fn isBoolean(value: []const u8) bool {
        return std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "false");
    }

    /// Check if value is null or undefined
    pub fn isNullish(value: []const u8) bool {
        return std.mem.eql(u8, value, "null") or std.mem.eql(u8, value, "undefined");
    }

    /// Check if value is a Svelte rune
    pub fn isRune(value: []const u8) bool {
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
            if (std.mem.startsWith(u8, value, rune)) return true;
        }
        return false;
    }

    /// Check if value is a store reference ($name)
    pub fn isStoreRef(value: []const u8) bool {
        return value.len > 1 and value[0] == '$' and !isRune(value);
    }

    /// Get operator precedence (higher = tighter binding)
    pub fn getOperatorPrecedence(op: []const u8) u8 {
        if (std.mem.eql(u8, op, "||") or std.mem.eql(u8, op, "??")) return 3;
        if (std.mem.eql(u8, op, "&&")) return 4;
        if (std.mem.eql(u8, op, "|")) return 5;
        if (std.mem.eql(u8, op, "^")) return 6;
        if (std.mem.eql(u8, op, "&")) return 7;
        if (std.mem.eql(u8, op, "==") or std.mem.eql(u8, op, "!=") or
            std.mem.eql(u8, op, "===") or std.mem.eql(u8, op, "!=="))
            return 8;
        if (std.mem.eql(u8, op, "<") or std.mem.eql(u8, op, ">") or
            std.mem.eql(u8, op, "<=") or std.mem.eql(u8, op, ">=") or
            std.mem.eql(u8, op, "in") or std.mem.eql(u8, op, "instanceof"))
            return 9;
        if (std.mem.eql(u8, op, "<<") or std.mem.eql(u8, op, ">>") or
            std.mem.eql(u8, op, ">>>"))
            return 10;
        if (std.mem.eql(u8, op, "+") or std.mem.eql(u8, op, "-")) return 11;
        if (std.mem.eql(u8, op, "*") or std.mem.eql(u8, op, "/") or
            std.mem.eql(u8, op, "%"))
            return 12;
        if (std.mem.eql(u8, op, "**")) return 13;
        return 0;
    }
};

/// Directive type detection
pub const DirectiveClassifier = struct {
    pub fn getDirectiveType(name: []const u8) ?ast.DirectiveType {
        if (std.mem.eql(u8, name, "on")) return .on;
        if (std.mem.eql(u8, name, "bind")) return .bind;
        if (std.mem.eql(u8, name, "class")) return .class_directive;
        if (std.mem.eql(u8, name, "style")) return .style_directive;
        if (std.mem.eql(u8, name, "use")) return .use;
        if (std.mem.eql(u8, name, "transition")) return .transition;
        if (std.mem.eql(u8, name, "in")) return .in_directive;
        if (std.mem.eql(u8, name, "out")) return .out_directive;
        if (std.mem.eql(u8, name, "animate")) return .animate;
        if (std.mem.eql(u8, name, "let")) return .let;
        return null;
    }

    pub fn isEventDirective(name: []const u8) bool {
        return std.mem.eql(u8, name, "on");
    }

    pub fn isBindDirective(name: []const u8) bool {
        return std.mem.eql(u8, name, "bind");
    }

    pub fn isTransitionDirective(name: []const u8) bool {
        return std.mem.eql(u8, name, "transition") or
            std.mem.eql(u8, name, "in") or
            std.mem.eql(u8, name, "out");
    }
};

test "token classifier" {
    const testing = std.testing;

    try testing.expect(TokenClassifier.isComparisonOp(.lt));
    try testing.expect(TokenClassifier.isComparisonOp(.gte));
    try testing.expect(!TokenClassifier.isComparisonOp(.plus));

    try testing.expect(TokenValue.isKeyword("true"));
    try testing.expect(TokenValue.isKeyword("await"));
    try testing.expect(!TokenValue.isKeyword("myVar"));

    try testing.expect(TokenValue.isRune("$state"));
    try testing.expect(TokenValue.isRune("$derived.by"));
    try testing.expect(!TokenValue.isRune("$myStore"));

    try testing.expect(TokenValue.isStoreRef("$count"));
    try testing.expect(!TokenValue.isStoreRef("$state"));
}
