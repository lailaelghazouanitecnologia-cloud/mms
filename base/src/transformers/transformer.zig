const std = @import("std");
const ast = @import("../ast/nodes.zig");
const pass = @import("pass.zig");
const context = @import("../pipeline/context.zig");

pub const TransformError = error{
    TransformFailed,
    InvalidNode,
    OutOfMemory,
};

pub const TransformResult = struct {
    root: *ast.Node,
    metadata: std.StringHashMap([]const u8),
};

pub const Transformer = struct {
    allocator: std.mem.Allocator,
    root: *ast.Node,
    ctx: pass.TransformContext,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, root: *ast.Node, options: context.CompilerOptions) Self {
        const transform_options = pass.TransformOptions{
            .dev = options.dev,
            .hmr = options.hmr,
            .preserve_whitespace = options.preserve_whitespace,
            .css_hash = options.css_hash,
            .generate_mode = switch (options.generate) {
                .dom => .dom,
                .ssr => .ssr,
                .hydrate => .hydrate,
            },
        };

        return Self{
            .allocator = allocator,
            .root = root,
            .ctx = pass.TransformContext.init(allocator, transform_options),
        };
    }

    pub fn deinit(self: *Self) void {
        self.ctx.deinit();
    }

    pub fn transform(self: *Self) !TransformResult {
        return TransformResult{
            .root = self.root,
            .metadata = self.ctx.metadata,
        };
    }
};
