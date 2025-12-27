const std = @import("std");
const ast = @import("../ast/nodes.zig");

pub fn ParserResult(comptime T: type) type {
    return union(enum) {
        success: T,
        failure: ParseFailure,

        pub fn isSuccess(self: @This()) bool {
            return self == .success;
        }

        pub fn getValue(self: @This()) ?T {
            return switch (self) {
                .success => |v| v,
                .failure => null,
            };
        }
    };
}

pub const ParseFailure = struct {
    message: []const u8,
    position: u32,
};

pub fn Parser(comptime T: type) type {
    return struct {
        parse_fn: *const fn (*ParseContext) ParserResult(T),

        const Self = @This();

        pub fn parse(self: Self, ctx: *ParseContext) ParserResult(T) {
            return self.parse_fn(ctx);
        }

        pub fn map(self: Self, comptime U: type, f: *const fn (T) U) Parser(U) {
            const MapParser = struct {
                original: Self,
                mapper: *const fn (T) U,

                fn parse(mp: *@This(), ctx: *ParseContext) ParserResult(U) {
                    const result = mp.original.parse(ctx);
                    return switch (result) {
                        .success => |v| .{ .success = mp.mapper(v) },
                        .failure => |e| .{ .failure = e },
                    };
                }
            };

            var mp = MapParser{ .original = self, .mapper = f };
            return .{ .parse_fn = &mp.parse };
        }

        pub fn or_(self: Self, other: Self) Self {
            const OrParser = struct {
                first: Self,
                second: Self,

                fn parse(op: *@This(), ctx: *ParseContext) ParserResult(T) {
                    const saved_pos = ctx.position;
                    const first_result = op.first.parse(ctx);
                    if (first_result.isSuccess()) return first_result;

                    ctx.position = saved_pos;
                    return op.second.parse(ctx);
                }
            };

            var op = OrParser{ .first = self, .second = other };
            return .{ .parse_fn = &op.parse };
        }
    };
}

pub const ParseContext = struct {
    tokens: []const ast.Token,
    position: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, tokens: []const ast.Token) ParseContext {
        return .{
            .tokens = tokens,
            .position = 0,
            .allocator = allocator,
        };
    }

    pub fn isAtEnd(self: *ParseContext) bool {
        return self.position >= self.tokens.len;
    }

    pub fn peek(self: *ParseContext) ?ast.Token {
        if (self.isAtEnd()) return null;
        return self.tokens[self.position];
    }

    pub fn advance(self: *ParseContext) ?ast.Token {
        if (self.isAtEnd()) return null;
        const token = self.tokens[self.position];
        self.position += 1;
        return token;
    }

    pub fn check(self: *ParseContext, token_type: ast.TokenType) bool {
        const token = self.peek() orelse return false;
        return token.type == token_type;
    }

    pub fn match(self: *ParseContext, token_type: ast.TokenType) ?ast.Token {
        if (!self.check(token_type)) return null;
        return self.advance();
    }

    pub fn expect(self: *ParseContext, token_type: ast.TokenType) !ast.Token {
        return self.match(token_type) orelse error.UnexpectedToken;
    }

    pub fn skipWhitespace(self: *ParseContext) void {
        while (self.check(.whitespace) or self.check(.newline)) {
            _ = self.advance();
        }
    }
};

pub fn sequence(comptime parsers: anytype) Parser(std.meta.Tuple(parsers)) {
    return .{
        .parse_fn = struct {
            fn parse(ctx: *ParseContext) ParserResult(std.meta.Tuple(parsers)) {
                var results: std.meta.Tuple(parsers) = undefined;
                inline for (parsers, 0..) |p, i| {
                    const result = p.parse(ctx);
                    switch (result) {
                        .success => |v| results[i] = v,
                        .failure => |e| return .{ .failure = e },
                    }
                }
                return .{ .success = results };
            }
        }.parse,
    };
}

pub fn optional(comptime T: type, parser: Parser(T)) Parser(?T) {
    return .{
        .parse_fn = struct {
            fn parse(ctx: *ParseContext) ParserResult(?T) {
                const saved = ctx.position;
                const result = parser.parse(ctx);
                return switch (result) {
                    .success => |v| .{ .success = v },
                    .failure => {
                        ctx.position = saved;
                        return .{ .success = null };
                    },
                };
            }
        }.parse,
    };
}

pub fn many(comptime T: type, parser: Parser(T), allocator: std.mem.Allocator) Parser(std.ArrayList(T)) {
    _ = allocator;
    return .{
        .parse_fn = struct {
            fn parse(ctx: *ParseContext) ParserResult(std.ArrayList(T)) {
                var results = std.ArrayList(T).init(ctx.allocator);
                while (true) {
                    const saved = ctx.position;
                    const result = parser.parse(ctx);
                    switch (result) {
                        .success => |v| results.append(v) catch return .{
                            .failure = .{ .message = "Out of memory", .position = @intCast(ctx.position) },
                        },
                        .failure => {
                            ctx.position = saved;
                            break;
                        },
                    }
                }
                return .{ .success = results };
            }
        }.parse,
    };
}

pub fn sepBy(comptime T: type, parser: Parser(T), separator: Parser(void), allocator: std.mem.Allocator) Parser(std.ArrayList(T)) {
    _ = allocator;
    _ = separator;
    return .{
        .parse_fn = struct {
            fn parse(ctx: *ParseContext) ParserResult(std.ArrayList(T)) {
                var results = std.ArrayList(T).init(ctx.allocator);

                const first = parser.parse(ctx);
                switch (first) {
                    .success => |v| results.append(v) catch return .{
                        .failure = .{ .message = "Out of memory", .position = @intCast(ctx.position) },
                    },
                    .failure => return .{ .success = results },
                }

                return .{ .success = results };
            }
        }.parse,
    };
}
