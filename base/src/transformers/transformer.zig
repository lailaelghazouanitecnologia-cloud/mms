const std = @import("std");
const ast = @import("../ast/nodes.zig");
const pass = @import("pass.zig");
const reactivity = @import("passes/reactivity.zig");
const css_scope = @import("passes/css_scope.zig");
const optimize = @import("passes/optimize.zig");
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
    pass_chain: pass.PassChain,

    reactivity_pass: reactivity.ReactivityPass,
    css_scope_pass: css_scope.CssScopePass,
    optimize_pass: optimize.OptimizePass,

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

        var transformer = Self{
            .allocator = allocator,
            .root = root,
            .ctx = pass.TransformContext.init(allocator, transform_options),
            .pass_chain = pass.PassChain.init(allocator),
            .reactivity_pass = reactivity.ReactivityPass.init(),
            .css_scope_pass = css_scope.CssScopePass.init(),
            .optimize_pass = optimize.OptimizePass.init(),
        };

        transformer.pass_chain.add(&transformer.reactivity_pass.base) catch {};
        transformer.pass_chain.add(&transformer.css_scope_pass.base) catch {};
        transformer.pass_chain.add(&transformer.optimize_pass.base) catch {};

        return transformer;
    }

    pub fn deinit(self: *Self) void {
        self.ctx.deinit();
        self.pass_chain.deinit();
    }

    pub fn transform(self: *Self) !TransformResult {
        const transformed = try self.pass_chain.run(self.root, &self.ctx);

        return TransformResult{
            .root = transformed,
            .metadata = self.ctx.metadata,
        };
    }

    pub fn addPass(self: *Self, p: *const pass.Pass) !void {
        try self.pass_chain.add(p);
    }
};
