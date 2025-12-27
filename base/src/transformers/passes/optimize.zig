const std = @import("std");
const ast = @import("../../ast/nodes.zig");
const pass = @import("../pass.zig");

pub const OptimizePass = struct {
    base: pass.Pass,

    const Self = @This();

    pub fn init() Self {
        return .{
            .base = .{
                .name = "optimize",
                .transform_fn = transform,
            },
        };
    }

    fn transform(p: *const pass.Pass, node: *ast.Node, ctx: *pass.TransformContext) pass.PassError!*ast.Node {
        _ = p;
        _ = ctx;
        return node;
    }

    fn optimizeNode(node: *ast.Node, ctx: *pass.TransformContext) pass.PassError!*ast.Node {
        switch (node.node_type) {
            .root => {
                node.data.root.fragment = try optimizeNode(node.data.root.fragment, ctx);
            },
            .fragment => {
                var optimized_children = std.ArrayList(*ast.Node).init(ctx.allocator);

                var i: usize = 0;
                while (i < node.data.fragment.children.items.len) {
                    const child = node.data.fragment.children.items[i];

                    if (child.node_type == .text_node) {
                        const merged = try mergeAdjacentText(node.data.fragment.children.items, i, ctx);
                        try optimized_children.append(merged.node);
                        i = merged.next_index;
                    } else {
                        const optimized = try optimizeNode(child, ctx);
                        try optimized_children.append(optimized);
                        i += 1;
                    }
                }

                node.data.fragment.children = optimized_children;
            },
            .element => {
                if (!ctx.options.preserve_whitespace) {
                    try trimElementWhitespace(node, ctx);
                }

                var optimized_children = std.ArrayList(*ast.Node).init(ctx.allocator);
                for (node.data.element.children.items) |child| {
                    const optimized = try optimizeNode(child, ctx);
                    if (!isEmptyTextNode(optimized, ctx)) {
                        try optimized_children.append(optimized);
                    }
                }
                node.data.element.children = optimized_children;
            },
            .if_block => {
                const if_block = &node.data.if_block;
                if_block.consequent = try optimizeNode(if_block.consequent, ctx);
                if (if_block.alternate) |alt| {
                    if_block.alternate = try optimizeNode(alt, ctx);
                }

                if (isConstantTrue(if_block.condition)) {
                    return if_block.consequent;
                }
                if (isConstantFalse(if_block.condition)) {
                    if (if_block.alternate) |alt| {
                        return alt;
                    }
                }
            },
            .each_block => {
                var optimized_children = std.ArrayList(*ast.Node).init(ctx.allocator);
                for (node.data.each_block.children.items) |child| {
                    const optimized = try optimizeNode(child, ctx);
                    try optimized_children.append(optimized);
                }
                node.data.each_block.children = optimized_children;
            },
            else => {},
        }
        return node;
    }

    const MergeResult = struct {
        node: *ast.Node,
        next_index: usize,
    };

    fn mergeAdjacentText(children: []*ast.Node, start: usize, ctx: *pass.TransformContext) !MergeResult {
        var merged_text = std.ArrayList(u8).init(ctx.allocator);
        var end = start;

        while (end < children.len and children[end].node_type == .text_node) {
            try merged_text.appendSlice(children[end].data.text_node.data);
            end += 1;
        }

        const merged_data = ast.NodeData{
            .text_node = .{
                .data = try merged_text.toOwnedSlice(),
                .raw = "",
            },
        };

        const merged_node = try ast.createNode(
            ctx.allocator,
            .text_node,
            children[start].span,
            merged_data,
        );

        return .{
            .node = merged_node,
            .next_index = end,
        };
    }

    fn trimElementWhitespace(node: *ast.Node, ctx: *pass.TransformContext) !void {
        _ = ctx;
        const children = node.data.element.children.items;
        if (children.len == 0) return;

        if (children[0].node_type == .text_node) {
            const text = children[0].data.text_node.data;
            children[0].data.text_node.data = std.mem.trimLeft(u8, text, " \t\n\r");
        }

        if (children.len > 1 and children[children.len - 1].node_type == .text_node) {
            const text = children[children.len - 1].data.text_node.data;
            children[children.len - 1].data.text_node.data = std.mem.trimRight(u8, text, " \t\n\r");
        }
    }

    fn isEmptyTextNode(node: *ast.Node, ctx: *pass.TransformContext) bool {
        _ = ctx;
        if (node.node_type != .text_node) return false;
        const trimmed = std.mem.trim(u8, node.data.text_node.data, " \t\n\r");
        return trimmed.len == 0;
    }

    fn isConstantTrue(node: *ast.Node) bool {
        if (node.node_type == .literal_expr) {
            switch (node.data.literal_expr.value) {
                .boolean => |b| return b,
                else => return false,
            }
        }
        return false;
    }

    fn isConstantFalse(node: *ast.Node) bool {
        if (node.node_type == .literal_expr) {
            switch (node.data.literal_expr.value) {
                .boolean => |b| return !b,
                .null_val => return true,
                else => return false,
            }
        }
        return false;
    }
};
