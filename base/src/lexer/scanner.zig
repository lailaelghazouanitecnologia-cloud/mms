const std = @import("std");

pub const Scanner = struct {
    source: []const u8,
    pos: u32,
    line: u32,
    column: u32,

    const Self = @This();

    pub fn init(source: []const u8) Self {
        return .{
            .source = source,
            .pos = 0,
            .line = 1,
            .column = 1,
        };
    }

    pub fn isAtEnd(self: *Self) bool {
        return self.pos >= self.source.len;
    }

    pub fn peek(self: *Self) u8 {
        if (self.isAtEnd()) return 0;
        return self.source[self.pos];
    }

    pub fn peekNext(self: *Self) u8 {
        if (self.pos + 1 >= self.source.len) return 0;
        return self.source[self.pos + 1];
    }

    pub fn peekAhead(self: *Self, offset: u32) u8 {
        if (self.pos + offset >= self.source.len) return 0;
        return self.source[self.pos + offset];
    }

    pub fn advance(self: *Self) u8 {
        const c = self.source[self.pos];
        self.pos += 1;
        if (c == '\n') {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }
        return c;
    }

    pub fn match(self: *Self, expected: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.source[self.pos] != expected) return false;
        _ = self.advance();
        return true;
    }

    pub fn matchSequence(self: *Self, expected: []const u8) bool {
        if (self.pos + expected.len > self.source.len) return false;
        if (!std.mem.eql(u8, self.source[self.pos..][0..expected.len], expected)) return false;
        for (expected) |_| {
            _ = self.advance();
        }
        return true;
    }

    pub fn skipWhitespace(self: *Self) void {
        while (!self.isAtEnd()) {
            const c = self.peek();
            switch (c) {
                ' ', '\t', '\r' => _ = self.advance(),
                else => break,
            }
        }
    }

    pub fn skipLine(self: *Self) void {
        while (!self.isAtEnd() and self.peek() != '\n') {
            _ = self.advance();
        }
    }

    pub fn remaining(self: *Self) []const u8 {
        return self.source[self.pos..];
    }

    pub fn slice(self: *Self, start: u32, end: u32) []const u8 {
        return self.source[start..end];
    }

    pub fn currentPosition(self: *Self) Position {
        return .{
            .line = self.line,
            .column = self.column,
            .offset = self.pos,
        };
    }
};

pub const Position = struct {
    line: u32,
    column: u32,
    offset: u32,
};

pub const Span = struct {
    start: Position,
    end: Position,
};
