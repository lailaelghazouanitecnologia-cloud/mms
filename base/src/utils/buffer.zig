const std = @import("std");

pub const WriteBuffer = struct {
    data: std.ArrayList(u8),
    indent_level: u32,
    indent_char: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .data = std.ArrayList(u8).init(allocator),
            .indent_level = 0,
            .indent_char = "\t",
        };
    }

    pub fn initWithIndent(allocator: std.mem.Allocator, indent: []const u8) Self {
        return .{
            .data = std.ArrayList(u8).init(allocator),
            .indent_level = 0,
            .indent_char = indent,
        };
    }

    pub fn deinit(self: *Self) void {
        self.data.deinit();
    }

    pub fn write(self: *Self, str: []const u8) !void {
        try self.data.appendSlice(str);
    }

    pub fn writeByte(self: *Self, byte: u8) !void {
        try self.data.append(byte);
    }

    pub fn writeLine(self: *Self, str: []const u8) !void {
        try self.write(str);
        try self.write("\n");
    }

    pub fn writeIndent(self: *Self) !void {
        var i: u32 = 0;
        while (i < self.indent_level) : (i += 1) {
            try self.write(self.indent_char);
        }
    }

    pub fn writeIndented(self: *Self, str: []const u8) !void {
        try self.writeIndent();
        try self.write(str);
    }

    pub fn writeIndentedLine(self: *Self, str: []const u8) !void {
        try self.writeIndent();
        try self.writeLine(str);
    }

    pub fn writeNumber(self: *Self, num: anytype) !void {
        var buf: [32]u8 = undefined;
        const T = @TypeOf(num);
        if (T == f64 or T == f32) {
            const len = std.fmt.formatFloat(buf[0..], num, .{}) catch 0;
            try self.write(buf[0..len]);
        } else {
            const slice = std.fmt.bufPrint(&buf, "{d}", .{num}) catch return;
            try self.write(slice);
        }
    }

    pub fn indent(self: *Self) void {
        self.indent_level += 1;
    }

    pub fn dedent(self: *Self) void {
        if (self.indent_level > 0) {
            self.indent_level -= 1;
        }
    }

    pub fn clear(self: *Self) void {
        self.data.clearRetainingCapacity();
    }

    pub fn toOwnedSlice(self: *Self) ![]u8 {
        return try self.data.toOwnedSlice();
    }

    pub fn items(self: *Self) []const u8 {
        return self.data.items;
    }

    pub fn len(self: *Self) usize {
        return self.data.items.len;
    }
};

pub const MultiBuffer = struct {
    buffers: std.StringHashMap(WriteBuffer),
    allocator: std.mem.Allocator,
    active: ?[]const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .buffers = std.StringHashMap(WriteBuffer).init(allocator),
            .allocator = allocator,
            .active = null,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.buffers.valueIterator();
        while (it.next()) |buf| {
            buf.deinit();
        }
        self.buffers.deinit();
    }

    pub fn create(self: *Self, name: []const u8) !*WriteBuffer {
        const buf = WriteBuffer.init(self.allocator);
        try self.buffers.put(name, buf);
        return self.buffers.getPtr(name).?;
    }

    pub fn get(self: *Self, name: []const u8) ?*WriteBuffer {
        return self.buffers.getPtr(name);
    }

    pub fn setActive(self: *Self, name: []const u8) void {
        self.active = name;
    }

    pub fn getActive(self: *Self) ?*WriteBuffer {
        if (self.active) |name| {
            return self.get(name);
        }
        return null;
    }
};
