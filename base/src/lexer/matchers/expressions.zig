const std = @import("std");
const scanner = @import("../scanner.zig");

pub const ExpressionMatcher = struct {
    pub fn matchMustacheOpen(s: *scanner.Scanner) ?[]const u8 {
        if (s.peek() != '{') return null;
        const next = s.peekNext();
        if (next == '#' or next == '/' or next == ':' or next == '@') return null;

        const start = s.pos;
        _ = s.advance();
        return s.slice(start, s.pos);
    }

    pub fn matchMustacheClose(s: *scanner.Scanner) ?[]const u8 {
        if (s.peek() != '}') return null;

        const start = s.pos;
        _ = s.advance();
        return s.slice(start, s.pos);
    }

    pub fn matchBlockOpen(s: *scanner.Scanner) ?BlockMatch {
        if (s.peek() != '{') return null;
        if (s.peekNext() != '#') return null;

        const start = s.pos;
        _ = s.advance();
        _ = s.advance();

        const keyword_start = s.pos;
        while (!s.isAtEnd() and isAlpha(s.peek())) {
            _ = s.advance();
        }

        const keyword = s.slice(keyword_start, s.pos);
        return .{
            .full = s.slice(start, s.pos),
            .keyword = keyword,
        };
    }

    pub fn matchBlockClose(s: *scanner.Scanner) ?BlockMatch {
        if (s.peek() != '{') return null;
        if (s.peekNext() != '/') return null;

        const start = s.pos;
        _ = s.advance();
        _ = s.advance();

        const keyword_start = s.pos;
        while (!s.isAtEnd() and isAlpha(s.peek())) {
            _ = s.advance();
        }

        const keyword = s.slice(keyword_start, s.pos);
        return .{
            .full = s.slice(start, s.pos),
            .keyword = keyword,
        };
    }

    pub fn matchBlockContinue(s: *scanner.Scanner) ?BlockMatch {
        if (s.peek() != '{') return null;
        if (s.peekNext() != ':') return null;

        const start = s.pos;
        _ = s.advance();
        _ = s.advance();

        const keyword_start = s.pos;
        while (!s.isAtEnd() and isAlpha(s.peek())) {
            _ = s.advance();
        }

        const keyword = s.slice(keyword_start, s.pos);
        return .{
            .full = s.slice(start, s.pos),
            .keyword = keyword,
        };
    }

    pub fn matchSpecialTag(s: *scanner.Scanner) ?BlockMatch {
        if (s.peek() != '{') return null;
        if (s.peekNext() != '@') return null;

        const start = s.pos;
        _ = s.advance();
        _ = s.advance();

        const keyword_start = s.pos;
        while (!s.isAtEnd() and isAlpha(s.peek())) {
            _ = s.advance();
        }

        const keyword = s.slice(keyword_start, s.pos);
        return .{
            .full = s.slice(start, s.pos),
            .keyword = keyword,
        };
    }

    pub fn matchNumber(s: *scanner.Scanner) ?[]const u8 {
        if (!isDigit(s.peek())) return null;

        const start = s.pos;
        while (!s.isAtEnd() and isDigit(s.peek())) {
            _ = s.advance();
        }

        if (s.peek() == '.' and isDigit(s.peekNext())) {
            _ = s.advance();
            while (!s.isAtEnd() and isDigit(s.peek())) {
                _ = s.advance();
            }
        }

        return s.slice(start, s.pos);
    }

    pub fn matchString(s: *scanner.Scanner) ?[]const u8 {
        const quote = s.peek();
        if (quote != '"' and quote != '\'') return null;

        const start = s.pos;
        _ = s.advance();

        while (!s.isAtEnd() and s.peek() != quote) {
            if (s.peek() == '\\') _ = s.advance();
            _ = s.advance();
        }

        if (!s.isAtEnd()) _ = s.advance();

        return s.slice(start, s.pos);
    }

    pub fn matchIdentifier(s: *scanner.Scanner) ?[]const u8 {
        if (!isAlpha(s.peek())) return null;

        const start = s.pos;
        while (!s.isAtEnd() and isAlphaNumeric(s.peek())) {
            _ = s.advance();
        }

        return s.slice(start, s.pos);
    }
};

pub const BlockMatch = struct {
    full: []const u8,
    keyword: []const u8,
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
