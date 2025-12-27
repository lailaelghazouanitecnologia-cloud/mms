const std = @import("std");
const nodes = @import("nodes.zig");

pub const VisitorError = error{
    VisitFailed,
    OutOfMemory,
};

pub fn Visitor(comptime ContextType: type, comptime ResultType: type) type {
    return struct {
        const Self = @This();

        context: ContextType,
        on_enter: ?*const fn (*Self, *nodes.Node) VisitorError!?ResultType = null,
        on_exit: ?*const fn (*Self, *nodes.Node, ?ResultType) VisitorError!?ResultType = null,

        pub fn visit(self: *Self, node: *nodes.Node) VisitorError!?ResultType {
            var result: ?ResultType = null;

            if (self.on_enter) |enter| {
                result = try enter(self, node);
            }

            try self.visitChildren(node);

            if (self.on_exit) |exit| {
                result = try exit(self, node, result);
            }

            return result;
        }

        fn visitChildren(self: *Self, node: *nodes.Node) VisitorError!void {
            switch (node.node_type) {
                .root => {
                    const root = node.data.root;
                    _ = try self.visit(root.fragment);
                    if (root.instance) |inst| _ = try self.visit(inst);
                    if (root.module) |mod| _ = try self.visit(mod);
                    if (root.options) |opts| _ = try self.visit(opts);
                    if (root.css) |css| _ = try self.visit(css);
                },
                .fragment => {
                    for (node.data.fragment.children.items) |child| {
                        _ = try self.visit(child);
                    }
                },
                .element => {
                    for (node.data.element.attributes.items) |attr| {
                        _ = try self.visit(attr);
                    }
                    for (node.data.element.children.items) |child| {
                        _ = try self.visit(child);
                    }
                },
                .component => {
                    for (node.data.component.attributes.items) |attr| {
                        _ = try self.visit(attr);
                    }
                    for (node.data.component.children.items) |child| {
                        _ = try self.visit(child);
                    }
                },
                .if_block => {
                    _ = try self.visit(node.data.if_block.condition);
                    _ = try self.visit(node.data.if_block.consequent);
                    if (node.data.if_block.alternate) |alt| {
                        _ = try self.visit(alt);
                    }
                },
                .each_block => {
                    _ = try self.visit(node.data.each_block.expression);
                    _ = try self.visit(node.data.each_block.context);
                    if (node.data.each_block.key) |key| {
                        _ = try self.visit(key);
                    }
                    for (node.data.each_block.children.items) |child| {
                        _ = try self.visit(child);
                    }
                    if (node.data.each_block.fallback) |fb| {
                        _ = try self.visit(fb);
                    }
                },
                .await_block => {
                    _ = try self.visit(node.data.await_block.expression);
                    if (node.data.await_block.pending) |p| _ = try self.visit(p);
                    if (node.data.await_block.value) |v| _ = try self.visit(v);
                    if (node.data.await_block.then_node) |t| _ = try self.visit(t);
                    if (node.data.await_block.error_node) |e| _ = try self.visit(e);
                    if (node.data.await_block.catch_node) |c| _ = try self.visit(c);
                },
                .key_block => {
                    _ = try self.visit(node.data.key_block.expression);
                    for (node.data.key_block.children.items) |child| {
                        _ = try self.visit(child);
                    }
                },
                .snippet_block => {
                    for (node.data.snippet_block.parameters.items) |param| {
                        _ = try self.visit(param);
                    }
                    _ = try self.visit(node.data.snippet_block.body);
                },
                .expression_tag => {
                    _ = try self.visit(node.data.expression_tag.expression);
                },
                .html_tag => {
                    _ = try self.visit(node.data.html_tag.expression);
                },
                .render_tag => {
                    _ = try self.visit(node.data.render_tag.expression);
                    if (node.data.render_tag.argument) |arg| {
                        _ = try self.visit(arg);
                    }
                },
                .attribute => {
                    switch (node.data.attribute.value) {
                        .expression => |expr| _ = try self.visit(expr),
                        .concat => |parts| {
                            for (parts.items) |part| {
                                switch (part) {
                                    .expression => |expr| _ = try self.visit(expr),
                                    else => {},
                                }
                            }
                        },
                        else => {},
                    }
                },
                .directive => {
                    if (node.data.directive.expression) |expr| {
                        _ = try self.visit(expr);
                    }
                },
                .member_expr => {
                    _ = try self.visit(node.data.member_expr.object);
                    if (node.data.member_expr.computed) {
                        _ = try self.visit(node.data.member_expr.property);
                    }
                },
                .call_expr => {
                    _ = try self.visit(node.data.call_expr.callee);
                    for (node.data.call_expr.arguments.items) |arg| {
                        _ = try self.visit(arg);
                    }
                },
                .binary_expr => {
                    _ = try self.visit(node.data.binary_expr.left);
                    _ = try self.visit(node.data.binary_expr.right);
                },
                .unary_expr => {
                    _ = try self.visit(node.data.unary_expr.argument);
                },
                .conditional_expr => {
                    _ = try self.visit(node.data.conditional_expr.condition);
                    _ = try self.visit(node.data.conditional_expr.consequent);
                    _ = try self.visit(node.data.conditional_expr.alternate);
                },
                .array_expr => {
                    for (node.data.array_expr.elements.items) |elem| {
                        if (elem) |e| _ = try self.visit(e);
                    }
                },
                .object_expr => {
                    for (node.data.object_expr.properties.items) |prop| {
                        _ = try self.visit(prop);
                    }
                },
                .assignment_expr => {
                    _ = try self.visit(node.data.assignment_expr.left);
                    _ = try self.visit(node.data.assignment_expr.right);
                },
                .sequence_expr => {
                    for (node.data.sequence_expr.expressions.items) |expr| {
                        _ = try self.visit(expr);
                    }
                },
                else => {},
            }
        }
    };
}

pub const SimpleVisitor = Visitor(void, void);

pub fn walkTree(node: *nodes.Node, callback: *const fn (*nodes.Node) void) void {
    callback(node);

    switch (node.node_type) {
        .root => {
            walkTree(node.data.root.fragment, callback);
            if (node.data.root.instance) |inst| walkTree(inst, callback);
        },
        .fragment => {
            for (node.data.fragment.children.items) |child| {
                walkTree(child, callback);
            }
        },
        .element => {
            for (node.data.element.attributes.items) |attr| {
                walkTree(attr, callback);
            }
            for (node.data.element.children.items) |child| {
                walkTree(child, callback);
            }
        },
        else => {},
    }
}

pub fn findNodes(allocator: std.mem.Allocator, root: *nodes.Node, node_type: nodes.NodeType) !std.ArrayList(*nodes.Node) {
    var result = std.ArrayList(*nodes.Node).init(allocator);

    const Collector = struct {
        list: *std.ArrayList(*nodes.Node),
        target_type: nodes.NodeType,

        fn collect(self: *@This(), node: *nodes.Node) void {
            if (node.node_type == self.target_type) {
                self.list.append(node) catch {};
            }
        }
    };

    var collector = Collector{ .list = &result, .target_type = node_type };
    _ = collector;

    try collectNodes(root, node_type, &result);

    return result;
}

fn collectNodes(node: *nodes.Node, target_type: nodes.NodeType, result: *std.ArrayList(*nodes.Node)) !void {
    if (node.node_type == target_type) {
        try result.append(node);
    }

    switch (node.node_type) {
        .root => {
            try collectNodes(node.data.root.fragment, target_type, result);
        },
        .fragment => {
            for (node.data.fragment.children.items) |child| {
                try collectNodes(child, target_type, result);
            }
        },
        .element => {
            for (node.data.element.children.items) |child| {
                try collectNodes(child, target_type, result);
            }
        },
        else => {},
    }
}
