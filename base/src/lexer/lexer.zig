const std = @import("std");
const ast = @import("../ast/nodes.zig");

pub const Lexer = struct {
    source: []const u8,
    pos: u32,
    line: u32,
    column: u32,
    tokens: std.ArrayList(ast.Token),
    allocator: std.mem.Allocator,
    in_tag: bool,
    in_mustache: bool,
    in_script: bool,
    in_style: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Self {
        return Self{
            .source = source,
            .pos = 0,
            .line = 1,
            .column = 1,
            .tokens = std.ArrayList(ast.Token).init(allocator),
            .allocator = allocator,
            .in_tag = false,
            .in_mustache = false,
            .in_script = false,
            .in_style = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
    }

    pub fn tokenize(self: *Self) ![]ast.Token {
        while (!self.isAtEnd()) {
            try self.scanToken();
        }
        try self.tokens.append(.{
            .type = .eof,
            .value = "",
            .span = self.makeSpan(self.pos, self.pos),
        });
        return self.tokens.items;
    }

    fn scanToken(self: *Self) !void {
        const start_pos = self.pos;
        const c = self.advance();

        if (self.in_script) {
            try self.scanScriptContent(start_pos);
            return;
        }

        if (self.in_style) {
            try self.scanStyleContent(start_pos);
            return;
        }

        switch (c) {
            '<' => {
                if (self.match('!')) {
                    if (self.match('-') and self.match('-')) {
                        try self.scanComment(start_pos);
                    } else {
                        try self.scanDoctype(start_pos);
                    }
                } else if (self.match('/')) {
                    self.in_tag = true;
                    try self.tokens.append(.{
                        .type = .close_tag,
                        .value = "</",
                        .span = self.makeSpan(start_pos, self.pos),
                    });
                } else {
                    self.in_tag = true;
                    try self.tokens.append(.{
                        .type = .open_tag,
                        .value = "<",
                        .span = self.makeSpan(start_pos, self.pos),
                    });
                }
            },
            '>' => {
                self.in_tag = false;
                try self.tokens.append(.{
                    .type = .rbracket,
                    .value = ">",
                    .span = self.makeSpan(start_pos, self.pos),
                });
            },
            '/' => {
                if (self.in_tag and self.peek() == '>') {
                    _ = self.advance();
                    self.in_tag = false;
                    try self.tokens.append(.{
                        .type = .self_close_tag,
                        .value = "/>",
                        .span = self.makeSpan(start_pos, self.pos),
                    });
                } else {
                    try self.tokens.append(.{
                        .type = .slash,
                        .value = "/",
                        .span = self.makeSpan(start_pos, self.pos),
                    });
                }
            },
            '{' => {
                if (self.match('#')) {
                    try self.scanBlockOpen(start_pos);
                } else if (self.match('/')) {
                    try self.scanBlockClose(start_pos);
                } else if (self.match(':')) {
                    try self.scanBlockContinue(start_pos);
                } else if (self.match('@')) {
                    try self.scanSpecialTag(start_pos);
                } else {
                    self.in_mustache = true;
                    try self.tokens.append(.{
                        .type = .mustache_open,
                        .value = "{",
                        .span = self.makeSpan(start_pos, self.pos),
                    });
                }
            },
            '}' => {
                self.in_mustache = false;
                try self.tokens.append(.{
                    .type = .mustache_close,
                    .value = "}",
                    .span = self.makeSpan(start_pos, self.pos),
                });
            },
            '=' => {
                if (self.match('=')) {
                    if (self.match('=')) {
                        try self.tokens.append(.{ .type = .eq, .value = "===", .span = self.makeSpan(start_pos, self.pos) });
                    } else {
                        try self.tokens.append(.{ .type = .eq, .value = "==", .span = self.makeSpan(start_pos, self.pos) });
                    }
                } else {
                    try self.tokens.append(.{ .type = .eq, .value = "=", .span = self.makeSpan(start_pos, self.pos) });
                }
            },
            '!' => {
                if (self.match('=')) {
                    if (self.match('=')) {
                        try self.tokens.append(.{ .type = .neq, .value = "!==", .span = self.makeSpan(start_pos, self.pos) });
                    } else {
                        try self.tokens.append(.{ .type = .neq, .value = "!=", .span = self.makeSpan(start_pos, self.pos) });
                    }
                } else {
                    try self.tokens.append(.{ .type = .not, .value = "!", .span = self.makeSpan(start_pos, self.pos) });
                }
            },
            '&' => {
                if (self.match('&')) {
                    try self.tokens.append(.{ .type = .and_op, .value = "&&", .span = self.makeSpan(start_pos, self.pos) });
                }
            },
            '|' => {
                if (self.match('|')) {
                    try self.tokens.append(.{ .type = .or_op, .value = "||", .span = self.makeSpan(start_pos, self.pos) });
                } else {
                    try self.tokens.append(.{ .type = .pipe, .value = "|", .span = self.makeSpan(start_pos, self.pos) });
                }
            },
            '+' => try self.tokens.append(.{ .type = .plus, .value = "+", .span = self.makeSpan(start_pos, self.pos) }),
            '-' => try self.tokens.append(.{ .type = .minus, .value = "-", .span = self.makeSpan(start_pos, self.pos) }),
            '*' => try self.tokens.append(.{ .type = .star, .value = "*", .span = self.makeSpan(start_pos, self.pos) }),
            '%' => try self.tokens.append(.{ .type = .percent, .value = "%", .span = self.makeSpan(start_pos, self.pos) }),
            '?' => try self.tokens.append(.{ .type = .question, .value = "?", .span = self.makeSpan(start_pos, self.pos) }),
            ':' => try self.tokens.append(.{ .type = .colon, .value = ":", .span = self.makeSpan(start_pos, self.pos) }),
            '.' => try self.tokens.append(.{ .type = .dot, .value = ".", .span = self.makeSpan(start_pos, self.pos) }),
            ',' => try self.tokens.append(.{ .type = .comma, .value = ",", .span = self.makeSpan(start_pos, self.pos) }),
            ';' => try self.tokens.append(.{ .type = .semicolon, .value = ";", .span = self.makeSpan(start_pos, self.pos) }),
            '(' => try self.tokens.append(.{ .type = .lparen, .value = "(", .span = self.makeSpan(start_pos, self.pos) }),
            ')' => try self.tokens.append(.{ .type = .rparen, .value = ")", .span = self.makeSpan(start_pos, self.pos) }),
            '[' => try self.tokens.append(.{ .type = .lbracket, .value = "[", .span = self.makeSpan(start_pos, self.pos) }),
            ']' => try self.tokens.append(.{ .type = .rbracket, .value = "]", .span = self.makeSpan(start_pos, self.pos) }),
            '@' => try self.tokens.append(.{ .type = .at, .value = "@", .span = self.makeSpan(start_pos, self.pos) }),
            '#' => try self.tokens.append(.{ .type = .hash, .value = "#", .span = self.makeSpan(start_pos, self.pos) }),
            '"', '\'' => try self.scanString(c, start_pos),
            '\n' => {
                self.line += 1;
                self.column = 1;
                try self.tokens.append(.{ .type = .newline, .value = "\n", .span = self.makeSpan(start_pos, self.pos) });
            },
            ' ', '\t', '\r' => try self.scanWhitespace(start_pos),
            else => {
                if (isDigit(c)) {
                    try self.scanNumber(start_pos);
                } else if (isAlpha(c)) {
                    try self.scanIdentifier(start_pos);
                } else if (!self.in_tag and !self.in_mustache) {
                    try self.scanText(start_pos);
                }
            },
        }
    }

    fn scanString(self: *Self, quote: u8, start_pos: u32) !void {
        while (!self.isAtEnd() and self.peek() != quote) {
            if (self.peek() == '\n') {
                self.line += 1;
                self.column = 1;
            }
            if (self.peek() == '\\') _ = self.advance();
            _ = self.advance();
        }
        if (self.isAtEnd()) {
            try self.tokens.append(.{ .type = .error_token, .value = "Unterminated string", .span = self.makeSpan(start_pos, self.pos) });
            return;
        }
        _ = self.advance();
        try self.tokens.append(.{ .type = .string, .value = self.source[start_pos + 1 .. self.pos - 1], .span = self.makeSpan(start_pos, self.pos) });
    }

    fn scanNumber(self: *Self, start_pos: u32) !void {
        while (isDigit(self.peek())) _ = self.advance();
        if (self.peek() == '.' and isDigit(self.peekNext())) {
            _ = self.advance();
            while (isDigit(self.peek())) _ = self.advance();
        }
        try self.tokens.append(.{ .type = .number, .value = self.source[start_pos..self.pos], .span = self.makeSpan(start_pos, self.pos) });
    }

    fn scanIdentifier(self: *Self, start_pos: u32) !void {
        while (isAlphaNumeric(self.peek())) _ = self.advance();
        const value = self.source[start_pos..self.pos];
        const token_type = self.identifierType(value);
        if (self.in_tag and self.peek() == ':') {
            _ = self.advance();
            const directive_type = self.directiveType(value);
            if (directive_type) |dt| {
                try self.tokens.append(.{ .type = dt, .value = value, .span = self.makeSpan(start_pos, self.pos) });
                return;
            }
        }
        try self.tokens.append(.{ .type = token_type, .value = value, .span = self.makeSpan(start_pos, self.pos) });
        if (std.mem.eql(u8, value, "script")) self.in_script = true;
        if (std.mem.eql(u8, value, "style")) self.in_style = true;
    }

    fn identifierType(self: *Self, value: []const u8) ast.TokenType {
        _ = self;
        if (std.mem.eql(u8, value, "if")) return .kw_if;
        if (std.mem.eql(u8, value, "else")) return .kw_else;
        if (std.mem.eql(u8, value, "each")) return .kw_each;
        if (std.mem.eql(u8, value, "await")) return .kw_await;
        if (std.mem.eql(u8, value, "then")) return .kw_then;
        if (std.mem.eql(u8, value, "catch")) return .kw_catch;
        if (std.mem.eql(u8, value, "key")) return .kw_key;
        if (std.mem.eql(u8, value, "snippet")) return .kw_snippet;
        if (std.mem.eql(u8, value, "render")) return .kw_render;
        if (std.mem.eql(u8, value, "html")) return .kw_html;
        if (std.mem.eql(u8, value, "const")) return .kw_const;
        if (std.mem.eql(u8, value, "debug")) return .kw_debug;
        if (std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "false")) return .boolean;
        if (std.mem.eql(u8, value, "null")) return .null_literal;
        return .identifier;
    }

    fn directiveType(self: *Self, value: []const u8) ?ast.TokenType {
        _ = self;
        if (std.mem.eql(u8, value, "on")) return .directive_on;
        if (std.mem.eql(u8, value, "bind")) return .directive_bind;
        if (std.mem.eql(u8, value, "class")) return .directive_class;
        if (std.mem.eql(u8, value, "style")) return .directive_style;
        if (std.mem.eql(u8, value, "use")) return .directive_use;
        if (std.mem.eql(u8, value, "transition")) return .directive_transition;
        if (std.mem.eql(u8, value, "animate")) return .directive_animate;
        if (std.mem.eql(u8, value, "in")) return .directive_in;
        if (std.mem.eql(u8, value, "out")) return .directive_out;
        if (std.mem.eql(u8, value, "let")) return .directive_let;
        return null;
    }

    fn scanText(self: *Self, start_pos: u32) !void {
        while (!self.isAtEnd()) {
            const c = self.peek();
            if (c == '<' or c == '{') break;
            if (c == '\n') {
                self.line += 1;
                self.column = 1;
            }
            _ = self.advance();
        }
        if (self.pos > start_pos) {
            try self.tokens.append(.{ .type = .text, .value = self.source[start_pos..self.pos], .span = self.makeSpan(start_pos, self.pos) });
        }
    }

    fn scanWhitespace(self: *Self, start_pos: u32) !void {
        while (!self.isAtEnd()) {
            const c = self.peek();
            if (c != ' ' and c != '\t' and c != '\r') break;
            _ = self.advance();
        }
        try self.tokens.append(.{ .type = .whitespace, .value = self.source[start_pos..self.pos], .span = self.makeSpan(start_pos, self.pos) });
    }

    fn scanComment(self: *Self, start_pos: u32) !void {
        while (!self.isAtEnd()) {
            if (self.peek() == '-' and self.peekNext() == '-') {
                _ = self.advance();
                _ = self.advance();
                if (self.peek() == '>') {
                    _ = self.advance();
                    break;
                }
            }
            if (self.peek() == '\n') {
                self.line += 1;
                self.column = 1;
            }
            _ = self.advance();
        }
        try self.tokens.append(.{ .type = .comment, .value = self.source[start_pos..self.pos], .span = self.makeSpan(start_pos, self.pos) });
    }

    fn scanDoctype(self: *Self, start_pos: u32) !void {
        while (!self.isAtEnd() and self.peek() != '>') _ = self.advance();
        if (!self.isAtEnd()) _ = self.advance();
        try self.tokens.append(.{ .type = .doctype, .value = self.source[start_pos..self.pos], .span = self.makeSpan(start_pos, self.pos) });
    }

    fn scanBlockOpen(self: *Self, start_pos: u32) !void {
        while (isAlpha(self.peek())) _ = self.advance();
        const keyword = self.source[start_pos + 2 .. self.pos];
        if (std.mem.eql(u8, keyword, "if")) try self.tokens.append(.{ .type = .kw_if, .value = "{#if", .span = self.makeSpan(start_pos, self.pos) });
        if (std.mem.eql(u8, keyword, "each")) try self.tokens.append(.{ .type = .kw_each, .value = "{#each", .span = self.makeSpan(start_pos, self.pos) });
        if (std.mem.eql(u8, keyword, "await")) try self.tokens.append(.{ .type = .kw_await, .value = "{#await", .span = self.makeSpan(start_pos, self.pos) });
        if (std.mem.eql(u8, keyword, "key")) try self.tokens.append(.{ .type = .kw_key, .value = "{#key", .span = self.makeSpan(start_pos, self.pos) });
        if (std.mem.eql(u8, keyword, "snippet")) try self.tokens.append(.{ .type = .kw_snippet, .value = "{#snippet", .span = self.makeSpan(start_pos, self.pos) });
    }

    fn scanBlockClose(self: *Self, start_pos: u32) !void {
        while (isAlpha(self.peek())) _ = self.advance();
        try self.tokens.append(.{ .type = .mustache_close, .value = self.source[start_pos..self.pos], .span = self.makeSpan(start_pos, self.pos) });
    }

    fn scanBlockContinue(self: *Self, start_pos: u32) !void {
        while (isAlpha(self.peek())) _ = self.advance();
        const keyword = self.source[start_pos + 2 .. self.pos];
        if (std.mem.eql(u8, keyword, "else")) try self.tokens.append(.{ .type = .kw_else, .value = "{:else", .span = self.makeSpan(start_pos, self.pos) });
        if (std.mem.eql(u8, keyword, "then")) try self.tokens.append(.{ .type = .kw_then, .value = "{:then", .span = self.makeSpan(start_pos, self.pos) });
        if (std.mem.eql(u8, keyword, "catch")) try self.tokens.append(.{ .type = .kw_catch, .value = "{:catch", .span = self.makeSpan(start_pos, self.pos) });
    }

    fn scanSpecialTag(self: *Self, start_pos: u32) !void {
        while (isAlpha(self.peek())) _ = self.advance();
        const keyword = self.source[start_pos + 2 .. self.pos];
        if (std.mem.eql(u8, keyword, "html")) try self.tokens.append(.{ .type = .kw_html, .value = "{@html", .span = self.makeSpan(start_pos, self.pos) });
        if (std.mem.eql(u8, keyword, "render")) try self.tokens.append(.{ .type = .kw_render, .value = "{@render", .span = self.makeSpan(start_pos, self.pos) });
        if (std.mem.eql(u8, keyword, "const")) try self.tokens.append(.{ .type = .kw_const, .value = "{@const", .span = self.makeSpan(start_pos, self.pos) });
        if (std.mem.eql(u8, keyword, "debug")) try self.tokens.append(.{ .type = .kw_debug, .value = "{@debug", .span = self.makeSpan(start_pos, self.pos) });
    }

    fn scanScriptContent(self: *Self, start_pos: u32) !void {
        _ = start_pos;
        while (!self.isAtEnd()) {
            if (self.source[self.pos..].len >= 9) {
                if (std.mem.eql(u8, self.source[self.pos .. self.pos + 9], "</script>")) {
                    self.in_script = false;
                    break;
                }
            }
            if (self.peek() == '\n') {
                self.line += 1;
                self.column = 1;
            }
            _ = self.advance();
        }
    }

    fn scanStyleContent(self: *Self, start_pos: u32) !void {
        _ = start_pos;
        while (!self.isAtEnd()) {
            if (self.source[self.pos..].len >= 8) {
                if (std.mem.eql(u8, self.source[self.pos .. self.pos + 8], "</style>")) {
                    self.in_style = false;
                    break;
                }
            }
            if (self.peek() == '\n') {
                self.line += 1;
                self.column = 1;
            }
            _ = self.advance();
        }
    }

    fn isAtEnd(self: *Self) bool {
        return self.pos >= self.source.len;
    }

    fn peek(self: *Self) u8 {
        if (self.isAtEnd()) return 0;
        return self.source[self.pos];
    }

    fn peekNext(self: *Self) u8 {
        if (self.pos + 1 >= self.source.len) return 0;
        return self.source[self.pos + 1];
    }

    fn advance(self: *Self) u8 {
        const c = self.source[self.pos];
        self.pos += 1;
        self.column += 1;
        return c;
    }

    fn match(self: *Self, expected: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.source[self.pos] != expected) return false;
        self.pos += 1;
        self.column += 1;
        return true;
    }

    fn makeSpan(self: *Self, start: u32, end: u32) ast.Span {
        return .{
            .start = .{ .line = self.line, .column = self.column - (end - start), .offset = start },
            .end = .{ .line = self.line, .column = self.column, .offset = end },
        };
    }
};

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_' or c == '$';
}

fn isAlphaNumeric(c: u8) bool {
    return isAlpha(c) or isDigit(c);
}
