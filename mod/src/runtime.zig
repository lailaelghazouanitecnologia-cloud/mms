const std = @import("std");

pub const Signal = struct {
    value: *anyopaque,
    subscribers: std.ArrayList(*Effect),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, value: *anyopaque) Self {
        return Self{
            .value = value,
            .subscribers = std.ArrayList(*Effect).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.subscribers.deinit();
    }

    pub fn get(self: *Self) *anyopaque {
        if (current_effect) |effect| {
            self.subscribe(effect);
        }
        return self.value;
    }

    pub fn set(self: *Self, new_value: *anyopaque) void {
        self.value = new_value;
        self.notify();
    }

    fn subscribe(self: *Self, effect: *Effect) void {
        for (self.subscribers.items) |sub| {
            if (sub == effect) return;
        }
        self.subscribers.append(effect) catch {};
    }

    fn notify(self: *Self) void {
        for (self.subscribers.items) |effect| {
            scheduleEffect(effect);
        }
    }
};

pub const Effect = struct {
    callback: *const fn () void,
    cleanup: ?*const fn () void,
    dependencies: std.ArrayList(*Signal),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, callback: *const fn () void) Self {
        return Self{
            .callback = callback,
            .cleanup = null,
            .dependencies = std.ArrayList(*Signal).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.dependencies.deinit();
    }

    pub fn run(self: *Self) void {
        if (self.cleanup) |cleanup| cleanup();
        const prev = current_effect;
        current_effect = self;
        self.callback();
        current_effect = prev;
    }
};

var current_effect: ?*Effect = null;
var pending_effects: std.ArrayList(*Effect) = undefined;
var batching: bool = false;
var initialized: bool = false;

pub fn initRuntime(allocator: std.mem.Allocator) void {
    if (!initialized) {
        pending_effects = std.ArrayList(*Effect).init(allocator);
        initialized = true;
    }
}

pub fn deinitRuntime() void {
    if (initialized) {
        pending_effects.deinit();
        initialized = false;
    }
}

fn scheduleEffect(effect: *Effect) void {
    if (batching) {
        for (pending_effects.items) |e| {
            if (e == effect) return;
        }
        pending_effects.append(effect) catch {};
    } else {
        effect.run();
    }
}

pub fn batch(callback: *const fn () void) void {
    batching = true;
    callback();
    batching = false;
    flush();
}

pub fn flush() void {
    while (pending_effects.items.len > 0) {
        const effect = pending_effects.orderedRemove(0);
        effect.run();
    }
}

pub fn untrack(callback: *const fn () void) void {
    const prev = current_effect;
    current_effect = null;
    callback();
    current_effect = prev;
}

pub const Derived = struct {
    compute: *const fn () *anyopaque,
    cached: ?*anyopaque,
    dirty: bool,
    subscribers: std.ArrayList(*Effect),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, compute: *const fn () *anyopaque) Self {
        return Self{
            .compute = compute,
            .cached = null,
            .dirty = true,
            .subscribers = std.ArrayList(*Effect).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.subscribers.deinit();
    }

    pub fn get(self: *Self) *anyopaque {
        if (self.dirty) {
            self.cached = self.compute();
            self.dirty = false;
        }
        if (current_effect) |effect| {
            for (self.subscribers.items) |sub| {
                if (sub == effect) return self.cached.?;
            }
            self.subscribers.append(effect) catch {};
        }
        return self.cached.?;
    }

    pub fn invalidate(self: *Self) void {
        self.dirty = true;
        for (self.subscribers.items) |effect| {
            scheduleEffect(effect);
        }
    }
};

pub const DomNode = struct {
    tag: []const u8,
    attributes: std.StringHashMap([]const u8),
    children: std.ArrayList(*DomNode),
    text_content: ?[]const u8,
    parent: ?*DomNode,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, tag: []const u8) Self {
        return Self{
            .tag = tag,
            .attributes = std.StringHashMap([]const u8).init(allocator),
            .children = std.ArrayList(*DomNode).init(allocator),
            .text_content = null,
            .parent = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.attributes.deinit();
        for (self.children.items) |child| {
            child.deinit();
            self.allocator.destroy(child);
        }
        self.children.deinit();
    }

    pub fn setAttribute(self: *Self, name: []const u8, value: []const u8) void {
        self.attributes.put(name, value) catch {};
    }

    pub fn getAttribute(self: *Self, name: []const u8) ?[]const u8 {
        return self.attributes.get(name);
    }

    pub fn appendChild(self: *Self, child: *DomNode) void {
        child.parent = self;
        self.children.append(child) catch {};
    }

    pub fn removeChild(self: *Self, child: *DomNode) void {
        for (self.children.items, 0..) |c, i| {
            if (c == child) {
                _ = self.children.orderedRemove(i);
                child.parent = null;
                break;
            }
        }
    }

    pub fn insertBefore(self: *Self, new_child: *DomNode, ref_child: ?*DomNode) void {
        new_child.parent = self;
        if (ref_child) |ref| {
            for (self.children.items, 0..) |c, i| {
                if (c == ref) {
                    self.children.insert(i, new_child) catch {};
                    return;
                }
            }
        }
        self.children.append(new_child) catch {};
    }

    pub fn setTextContent(self: *Self, text: []const u8) void {
        self.text_content = text;
        self.children.clearRetainingCapacity();
    }

    pub fn render(self: *Self, writer: anytype) !void {
        if (self.text_content) |text| {
            try writer.writeAll(text);
            return;
        }

        try writer.writeAll("<");
        try writer.writeAll(self.tag);

        var iter = self.attributes.iterator();
        while (iter.next()) |entry| {
            try writer.writeAll(" ");
            try writer.writeAll(entry.key_ptr.*);
            try writer.writeAll("=\"");
            try writer.writeAll(entry.value_ptr.*);
            try writer.writeAll("\"");
        }

        if (self.children.items.len == 0) {
            try writer.writeAll(" />");
        } else {
            try writer.writeAll(">");
            for (self.children.items) |child| {
                try child.render(writer);
            }
            try writer.writeAll("</");
            try writer.writeAll(self.tag);
            try writer.writeAll(">");
        }
    }
};

pub fn createElement(allocator: std.mem.Allocator, tag: []const u8) !*DomNode {
    const node = try allocator.create(DomNode);
    node.* = DomNode.init(allocator, tag);
    return node;
}

pub fn createTextNode(allocator: std.mem.Allocator, text: []const u8) !*DomNode {
    const node = try allocator.create(DomNode);
    node.* = DomNode.init(allocator, "");
    node.text_content = text;
    return node;
}

pub const Component = struct {
    render: *const fn (allocator: std.mem.Allocator, props: anytype) anyerror!*DomNode,
    effects: std.ArrayList(*Effect),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, render: *const fn (allocator: std.mem.Allocator, props: anytype) anyerror!*DomNode) Self {
        return Self{
            .render = render,
            .effects = std.ArrayList(*Effect).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.effects.items) |effect| {
            if (effect.cleanup) |cleanup| cleanup();
            effect.deinit();
            self.allocator.destroy(effect);
        }
        self.effects.deinit();
    }

    pub fn mount(self: *Self, props: anytype) !*DomNode {
        return try self.render(self.allocator, props);
    }

    pub fn addEffect(self: *Self, effect: *Effect) void {
        self.effects.append(effect) catch {};
    }
};

pub const TransitionConfig = struct {
    duration: u32 = 300,
    delay: u32 = 0,
    easing: *const fn (f64) f64 = linear,
};

pub fn linear(t: f64) f64 {
    return t;
}

pub fn cubicOut(t: f64) f64 {
    const f = t - 1.0;
    return f * f * f + 1.0;
}

pub fn cubicIn(t: f64) f64 {
    return t * t * t;
}

pub fn cubicInOut(t: f64) f64 {
    if (t < 0.5) {
        return 4.0 * t * t * t;
    }
    return 0.5 * std.math.pow(f64, 2.0 * t - 2.0, 3.0) + 1.0;
}

pub fn quadOut(t: f64) f64 {
    return t * (2.0 - t);
}

pub fn quadIn(t: f64) f64 {
    return t * t;
}

pub fn quadInOut(t: f64) f64 {
    if (t < 0.5) {
        return 2.0 * t * t;
    }
    return -1.0 + (4.0 - 2.0 * t) * t;
}

pub const Store = struct {
    value: *anyopaque,
    subscribers: std.ArrayList(*const fn (*anyopaque) void),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, initial: *anyopaque) Self {
        return Self{
            .value = initial,
            .subscribers = std.ArrayList(*const fn (*anyopaque) void).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.subscribers.deinit();
    }

    pub fn subscribe(self: *Self, callback: *const fn (*anyopaque) void) void {
        self.subscribers.append(callback) catch {};
        callback(self.value);
    }

    pub fn set(self: *Self, new_value: *anyopaque) void {
        self.value = new_value;
        for (self.subscribers.items) |callback| {
            callback(self.value);
        }
    }

    pub fn update(self: *Self, updater: *const fn (*anyopaque) *anyopaque) void {
        self.set(updater(self.value));
    }
};

pub fn escapeHtml(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    for (str) |c| {
        switch (c) {
            '&' => try result.appendSlice("&amp;"),
            '<' => try result.appendSlice("&lt;"),
            '>' => try result.appendSlice("&gt;"),
            '"' => try result.appendSlice("&quot;"),
            '\'' => try result.appendSlice("&#039;"),
            else => try result.append(c),
        }
    }
    return result.toOwnedSlice();
}

pub fn noop() void {}

pub fn identity(comptime T: type) fn (T) T {
    return struct {
        fn f(x: T) T {
            return x;
        }
    }.f;
}
