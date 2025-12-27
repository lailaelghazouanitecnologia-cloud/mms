const std = @import("std");
const ast = @import("../../ast/nodes.zig");
const pass = @import("../pass.zig");
const utils = @import("../../utils/utils.zig");

pub const CssScopePass = struct {
    base: pass.Pass,
    scope_id: ?[]const u8,

    const Self = @This();

    pub fn init() Self {
        return .{
            .base = .{
                .name = "css-scope",
                .transform_fn = transform,
            },
            .scope_id = null,
        };
    }

    fn transform(p: *const pass.Pass, node: *ast.Node, ctx: *pass.TransformContext) pass.PassError!*ast.Node {
        _ = p;
        _ = ctx;
        return node;
    }

    fn transformNode(node: *ast.Node, ctx: *pass.TransformContext, scope_id: []const u8) pass.PassError!*ast.Node {
        switch (node.node_type) {
            .root => {
                const root = &node.data.root;
                root.fragment = try transformNode(root.fragment, ctx, scope_id);
            },
            .fragment => {
                var new_children = std.ArrayList(*ast.Node).init(ctx.allocator);
                for (node.data.fragment.children.items) |child| {
                    const transformed = try transformNode(child, ctx, scope_id);
                    try new_children.append(transformed);
                }
                node.data.fragment.children = new_children;
            },
            .element => {
                try addScopeAttribute(node, ctx, scope_id);

                var new_children = std.ArrayList(*ast.Node).init(ctx.allocator);
                for (node.data.element.children.items) |child| {
                    const transformed = try transformNode(child, ctx, scope_id);
                    try new_children.append(transformed);
                }
                node.data.element.children = new_children;
            },
            .if_block => {
                const if_block = &node.data.if_block;
                if_block.consequent = try transformNode(if_block.consequent, ctx, scope_id);
                if (if_block.alternate) |alt| {
                    if_block.alternate = try transformNode(alt, ctx, scope_id);
                }
            },
            .each_block => {
                var new_children = std.ArrayList(*ast.Node).init(ctx.allocator);
                for (node.data.each_block.children.items) |child| {
                    const transformed = try transformNode(child, ctx, scope_id);
                    try new_children.append(transformed);
                }
                node.data.each_block.children = new_children;
            },
            else => {},
        }
        return node;
    }

    fn addScopeAttribute(node: *ast.Node, ctx: *pass.TransformContext, scope_id: []const u8) !void {
        const attr_name = try std.fmt.allocPrint(ctx.allocator, "data-s-{s}", .{scope_id});

        const attr_data = ast.NodeData{
            .attribute = .{
                .name = attr_name,
                .value = .{ .boolean = true },
            },
        };

        const scope_attr = try ast.createNode(
            ctx.allocator,
            .attribute,
            ast.defaultSpan(),
            attr_data,
        );

        try node.data.element.attributes.append(scope_attr);
    }

    fn generateScopeId(ctx: *pass.TransformContext) []const u8 {
        _ = ctx;
        return "xxxxx";
    }
};
