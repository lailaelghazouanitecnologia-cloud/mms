const std = @import("std");

pub fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

pub fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_' or c == '$';
}

pub fn isAlphaNumeric(c: u8) bool {
    return isAlpha(c) or isDigit(c);
}

pub fn isUpperCase(c: u8) bool {
    return c >= 'A' and c <= 'Z';
}

pub fn isLowerCase(c: u8) bool {
    return c >= 'a' and c <= 'z';
}

pub fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r' or c == '\n';
}

pub fn trimWhitespace(str: []const u8) []const u8 {
    return std.mem.trim(u8, str, " \t\n\r");
}

pub fn escape(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    for (str) |c| {
        switch (c) {
            '\\' => try result.appendSlice("\\\\"),
            '"' => try result.appendSlice("\\\""),
            '\n' => try result.appendSlice("\\n"),
            '\r' => try result.appendSlice("\\r"),
            '\t' => try result.appendSlice("\\t"),
            '`' => try result.appendSlice("\\`"),
            '$' => try result.appendSlice("\\$"),
            else => try result.append(c),
        }
    }

    return result.toOwnedSlice();
}

pub fn escapeHtml(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    for (str) |c| {
        switch (c) {
            '&' => try result.appendSlice("&amp;"),
            '<' => try result.appendSlice("&lt;"),
            '>' => try result.appendSlice("&gt;"),
            '"' => try result.appendSlice("&quot;"),
            '\'' => try result.appendSlice("&#39;"),
            else => try result.append(c),
        }
    }

    return result.toOwnedSlice();
}

pub fn camelToKebab(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    for (str, 0..) |c, i| {
        if (isUpperCase(c)) {
            if (i > 0) try result.append('-');
            try result.append(c + 32);
        } else {
            try result.append(c);
        }
    }

    return result.toOwnedSlice();
}

pub fn kebabToCamel(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var capitalize_next = false;
    for (str) |c| {
        if (c == '-') {
            capitalize_next = true;
        } else if (capitalize_next) {
            if (isLowerCase(c)) {
                try result.append(c - 32);
            } else {
                try result.append(c);
            }
            capitalize_next = false;
        } else {
            try result.append(c);
        }
    }

    return result.toOwnedSlice();
}

pub fn hash(str: []const u8) u32 {
    var h: u32 = 5381;
    for (str) |c| {
        h = ((h << 5) +% h) +% c;
    }
    return h;
}

pub fn generateId(allocator: std.mem.Allocator, prefix: []const u8, index: u32) ![]u8 {
    return try std.fmt.allocPrint(allocator, "{s}_{d}", .{ prefix, index });
}
