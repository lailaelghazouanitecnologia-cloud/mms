const std = @import("std");
const ast = @import("../../ast/nodes.zig");
const pass = @import("../pass.zig");

pub const ReactivityPass = struct {
    base: pass.Pass,

    const Self = @This();

    pub fn init() Self {
        return .{
            .base = .{
                .name = "reactivity",
                .transform_fn = transform,
            },
        };
    }

    fn transform(p: *const pass.Pass, node: *ast.Node, ctx: *pass.TransformContext) pass.PassError!*ast.Node {
        _ = p;
        _ = ctx;
        return node;
    }

    fn transformNode(node: *ast.Node, ctx: *pass.TransformContext) pass.PassError!*ast.Node {
        switch (node.node_type) {
            .root => {
                const root = node.data.root;
                const transformed_fragment = try transformNode(root.fragment, ctx);
                node.data.root.fragment = transformed_fragment;
            },
            .fragment => {
                var new_children = std.ArrayList(*ast.Node).init(ctx.allocator);
                for (node.data.fragment.children.items) |child| {
                    const transformed = try transformNode(child, ctx);
                    try new_children.append(transformed);
                }
                node.data.fragment.children = new_children;
            },
            .element => {
                var new_children = std.ArrayList(*ast.Node).init(ctx.allocator);
                for (node.data.element.children.items) |child| {
                    const transformed = try transformNode(child, ctx);
                    try new_children.append(transformed);
                }
                node.data.element.children = new_children;

                for (node.data.element.attributes.items) |attr| {
                    _ = try transformNode(attr, ctx);
                }
            },
            .if_block => {
                const if_block = &node.data.if_block;
                if_block.consequent = try transformNode(if_block.consequent, ctx);
                if (if_block.alternate) |alt| {
                    if_block.alternate = try transformNode(alt, ctx);
                }
            },
            .each_block => {
                var new_children = std.ArrayList(*ast.Node).init(ctx.allocator);
                for (node.data.each_block.children.items) |child| {
                    const transformed = try transformNode(child, ctx);
                    try new_children.append(transformed);
                }
                node.data.each_block.children = new_children;
            },
            .expression_tag => {
                node.data.expression_tag.expression = try wrapReactiveExpression(
                    node.data.expression_tag.expression,
                    ctx,
                );
            },
            else => {},
        }
        return node;
    }

    fn wrapReactiveExpression(node: *ast.Node, ctx: *pass.TransformContext) pass.PassError!*ast.Node {
        _ = ctx;
        return node;
    }
};
