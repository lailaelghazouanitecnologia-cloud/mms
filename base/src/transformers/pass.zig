const std = @import("std");
const ast = @import("../ast/nodes.zig");

pub const PassError = error{
    TransformFailed,
    InvalidNode,
    OutOfMemory,
};

pub const Pass = struct {
    name: []const u8,
    transform_fn: *const fn (*const Pass, *ast.Node, *TransformContext) PassError!*ast.Node,
    enabled: bool = true,

    pub fn transform(self: *const Pass, node: *ast.Node, ctx: *TransformContext) PassError!*ast.Node {
        if (!self.enabled) return node;
        return self.transform_fn(self, node, ctx);
    }
};

pub const TransformContext = struct {
    allocator: std.mem.Allocator,
    options: TransformOptions,
    changes: std.ArrayList(Change),
    metadata: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator, options: TransformOptions) TransformContext {
        return .{
            .allocator = allocator,
            .options = options,
            .changes = std.ArrayList(Change).init(allocator),
            .metadata = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *TransformContext) void {
        self.changes.deinit();
        self.metadata.deinit();
    }

    pub fn recordChange(self: *TransformContext, change: Change) !void {
        try self.changes.append(change);
    }

    pub fn setMetadata(self: *TransformContext, key: []const u8, value: []const u8) !void {
        try self.metadata.put(key, value);
    }

    pub fn getMetadata(self: *TransformContext, key: []const u8) ?[]const u8 {
        return self.metadata.get(key);
    }
};

pub const TransformOptions = struct {
    dev: bool = false,
    hmr: bool = false,
    generate_mode: GenerateMode = .dom,
    preserve_whitespace: bool = false,
    css_hash: ?[]const u8 = null,
};

pub const GenerateMode = enum {
    dom,
    ssr,
    hydrate,
};

pub const Change = struct {
    kind: ChangeKind,
    original: ?*ast.Node,
    replacement: ?*ast.Node,
    description: []const u8,
};

pub const ChangeKind = enum {
    insert,
    replace,
    remove,
    wrap,
    unwrap,
};

pub const PassChain = struct {
    passes: std.ArrayList(*const Pass),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PassChain {
        return .{
            .passes = std.ArrayList(*const Pass).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PassChain) void {
        self.passes.deinit();
    }

    pub fn add(self: *PassChain, pass: *const Pass) !void {
        try self.passes.append(pass);
    }

    pub fn run(self: *PassChain, node: *ast.Node, ctx: *TransformContext) !*ast.Node {
        var current = node;
        for (self.passes.items) |pass| {
            current = try pass.transform(current, ctx);
        }
        return current;
    }
};
