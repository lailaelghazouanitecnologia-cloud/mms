const std = @import("std");
const nodes = @import("nodes.zig");

pub const Builder = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn root(self: *Self, fragment: *nodes.Node) !*nodes.Node {
        return nodes.createNode(self.allocator, .root, nodes.defaultSpan(), .{
            .root = .{
                .fragment = fragment,
                .instance = null,
                .module = null,
                .options = null,
                .css = null,
                .metadata = .{},
            },
        });
    }

    pub fn fragment(self: *Self, children: []*nodes.Node) !*nodes.Node {
        var child_list = std.ArrayList(*nodes.Node).init(self.allocator);
        try child_list.appendSlice(children);

        return nodes.createNode(self.allocator, .fragment, nodes.defaultSpan(), .{
            .fragment = .{
                .children = child_list,
                .transparent = false,
            },
        });
    }

    pub fn element(self: *Self, name: []const u8, attrs: []*nodes.Node, children: []*nodes.Node) !*nodes.Node {
        var attr_list = std.ArrayList(*nodes.Node).init(self.allocator);
        try attr_list.appendSlice(attrs);

        var child_list = std.ArrayList(*nodes.Node).init(self.allocator);
        try child_list.appendSlice(children);

        return nodes.createNode(self.allocator, .element, nodes.defaultSpan(), .{
            .element = .{
                .name = name,
                .attributes = attr_list,
                .children = child_list,
                .self_closing = children.len == 0,
            },
        });
    }

    pub fn component(self: *Self, name: []const u8, attrs: []*nodes.Node, children: []*nodes.Node) !*nodes.Node {
        var attr_list = std.ArrayList(*nodes.Node).init(self.allocator);
        try attr_list.appendSlice(attrs);

        var child_list = std.ArrayList(*nodes.Node).init(self.allocator);
        try child_list.appendSlice(children);

        return nodes.createNode(self.allocator, .component, nodes.defaultSpan(), .{
            .component = .{
                .name = name,
                .attributes = attr_list,
                .children = child_list,
            },
        });
    }

    pub fn text(self: *Self, data: []const u8) !*nodes.Node {
        return nodes.createNode(self.allocator, .text_node, nodes.defaultSpan(), .{
            .text_node = .{
                .data = data,
                .raw = data,
            },
        });
    }

    pub fn attribute(self: *Self, name: []const u8, value: nodes.AttributeValue) !*nodes.Node {
        return nodes.createNode(self.allocator, .attribute, nodes.defaultSpan(), .{
            .attribute = .{
                .name = name,
                .value = value,
            },
        });
    }

    pub fn textAttribute(self: *Self, name: []const u8, value: []const u8) !*nodes.Node {
        return self.attribute(name, .{ .text = value });
    }

    pub fn boolAttribute(self: *Self, name: []const u8) !*nodes.Node {
        return self.attribute(name, .{ .boolean = true });
    }

    pub fn exprAttribute(self: *Self, name: []const u8, expr: *nodes.Node) !*nodes.Node {
        return self.attribute(name, .{ .expression = expr });
    }

    pub fn directive(self: *Self, dtype: nodes.DirectiveType, name: []const u8, expr: ?*nodes.Node) !*nodes.Node {
        return nodes.createNode(self.allocator, .directive, nodes.defaultSpan(), .{
            .directive = .{
                .directive_type = dtype,
                .name = name,
                .expression = expr,
                .modifiers = std.ArrayList([]const u8).init(self.allocator),
            },
        });
    }

    pub fn ifBlock(self: *Self, test_expr: *nodes.Node, consequent: *nodes.Node, alternate: ?*nodes.Node) !*nodes.Node {
        return nodes.createNode(self.allocator, .if_block, nodes.defaultSpan(), .{
            .if_block = .{
                .test = test_expr,
                .consequent = consequent,
                .alternate = alternate,
                .elseif = false,
            },
        });
    }

    pub fn eachBlock(self: *Self, expr: *nodes.Node, ctx: *nodes.Node, children: []*nodes.Node) !*nodes.Node {
        var child_list = std.ArrayList(*nodes.Node).init(self.allocator);
        try child_list.appendSlice(children);

        return nodes.createNode(self.allocator, .each_block, nodes.defaultSpan(), .{
            .each_block = .{
                .expression = expr,
                .context = ctx,
                .index = null,
                .key = null,
                .children = child_list,
                .fallback = null,
            },
        });
    }

    pub fn expressionTag(self: *Self, expr: *nodes.Node) !*nodes.Node {
        return nodes.createNode(self.allocator, .expression_tag, nodes.defaultSpan(), .{
            .expression_tag = .{
                .expression = expr,
            },
        });
    }

    pub fn identifier(self: *Self, name: []const u8) !*nodes.Node {
        return nodes.createNode(self.allocator, .identifier_expr, nodes.defaultSpan(), .{
            .identifier_expr = .{
                .name = name,
            },
        });
    }

    pub fn stringLiteral(self: *Self, value: []const u8) !*nodes.Node {
        return nodes.createNode(self.allocator, .literal_expr, nodes.defaultSpan(), .{
            .literal_expr = .{
                .value = .{ .string = value },
                .raw = value,
            },
        });
    }

    pub fn numberLiteral(self: *Self, value: f64, raw: []const u8) !*nodes.Node {
        return nodes.createNode(self.allocator, .literal_expr, nodes.defaultSpan(), .{
            .literal_expr = .{
                .value = .{ .number = value },
                .raw = raw,
            },
        });
    }

    pub fn boolLiteral(self: *Self, value: bool) !*nodes.Node {
        return nodes.createNode(self.allocator, .literal_expr, nodes.defaultSpan(), .{
            .literal_expr = .{
                .value = .{ .boolean = value },
                .raw = if (value) "true" else "false",
            },
        });
    }

    pub fn nullLiteral(self: *Self) !*nodes.Node {
        return nodes.createNode(self.allocator, .literal_expr, nodes.defaultSpan(), .{
            .literal_expr = .{
                .value = .{ .null_val = {} },
                .raw = "null",
            },
        });
    }

    pub fn binaryExpr(self: *Self, op: []const u8, left: *nodes.Node, right: *nodes.Node) !*nodes.Node {
        return nodes.createNode(self.allocator, .binary_expr, nodes.defaultSpan(), .{
            .binary_expr = .{
                .operator = op,
                .left = left,
                .right = right,
            },
        });
    }

    pub fn callExpr(self: *Self, callee: *nodes.Node, args: []*nodes.Node) !*nodes.Node {
        var arg_list = std.ArrayList(*nodes.Node).init(self.allocator);
        try arg_list.appendSlice(args);

        return nodes.createNode(self.allocator, .call_expr, nodes.defaultSpan(), .{
            .call_expr = .{
                .callee = callee,
                .arguments = arg_list,
            },
        });
    }

    pub fn memberExpr(self: *Self, object: *nodes.Node, property: *nodes.Node, computed: bool) !*nodes.Node {
        return nodes.createNode(self.allocator, .member_expr, nodes.defaultSpan(), .{
            .member_expr = .{
                .object = object,
                .property = property,
                .computed = computed,
            },
        });
    }
};
