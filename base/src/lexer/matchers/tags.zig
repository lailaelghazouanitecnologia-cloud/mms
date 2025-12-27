const std = @import("std");
const scanner = @import("../scanner.zig");

pub const TagMatcher = struct {
    pub fn matchOpenTag(s: *scanner.Scanner) ?[]const u8 {
        if (s.peek() != '<') return null;
        if (s.peekNext() == '/' or s.peekNext() == '!') return null;

        const start = s.pos;
        _ = s.advance();

        return s.slice(start, s.pos);
    }

    pub fn matchCloseTag(s: *scanner.Scanner) ?[]const u8 {
        if (s.peek() != '<') return null;
        if (s.peekNext() != '/') return null;

        const start = s.pos;
        _ = s.advance();
        _ = s.advance();

        return s.slice(start, s.pos);
    }

    pub fn matchSelfCloseTag(s: *scanner.Scanner) ?[]const u8 {
        if (s.peek() != '/') return null;
        if (s.peekNext() != '>') return null;

        const start = s.pos;
        _ = s.advance();
        _ = s.advance();

        return s.slice(start, s.pos);
    }

    pub fn matchComment(s: *scanner.Scanner) ?[]const u8 {
        if (!s.matchSequence("<!--")) return null;

        const start = s.pos - 4;

        while (!s.isAtEnd()) {
            if (s.peek() == '-' and s.peekNext() == '-' and s.peekAhead(2) == '>') {
                _ = s.advance();
                _ = s.advance();
                _ = s.advance();
                break;
            }
            _ = s.advance();
        }

        return s.slice(start, s.pos);
    }

    pub fn matchDoctype(s: *scanner.Scanner) ?[]const u8 {
        if (s.peek() != '<') return null;
        if (s.peekNext() != '!') return null;

        const remaining = s.remaining();
        if (remaining.len < 9) return null;

        if (!std.mem.startsWith(u8, remaining[2..], "DOCTYPE") and
            !std.mem.startsWith(u8, remaining[2..], "doctype"))
        {
            return null;
        }

        const start = s.pos;
        while (!s.isAtEnd() and s.peek() != '>') {
            _ = s.advance();
        }
        if (!s.isAtEnd()) _ = s.advance();

        return s.slice(start, s.pos);
    }

    pub fn matchTagName(s: *scanner.Scanner) ?[]const u8 {
        if (!isAlpha(s.peek())) return null;

        const start = s.pos;
        while (!s.isAtEnd() and (isAlphaNumeric(s.peek()) or s.peek() == '-' or s.peek() == ':')) {
            _ = s.advance();
        }

        return s.slice(start, s.pos);
    }
};

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isAlphaNumeric(c: u8) bool {
    return isAlpha(c) or (c >= '0' and c <= '9');
}
