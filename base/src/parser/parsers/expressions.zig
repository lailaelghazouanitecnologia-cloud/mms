const std = @import("std");
const ast = @import("../../ast/nodes.zig");

/// Expression parsing utilities and helpers
pub const ExpressionParser = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    /// Create a binary expression node
    pub fn createBinaryExpr(
        self: *Self,
        operator: []const u8,
        left: *ast.Node,
        right: *ast.Node,
    ) !*ast.Node {
        const data = ast.NodeData{
            .binary_expr = .{
                .operator = operator,
                .left = left,
                .right = right,
            },
        };
        return ast.createNode(self.allocator, .binary_expr, ast.defaultSpan(), data);
    }

    /// Create a unary expression node
    pub fn createUnaryExpr(
        self: *Self,
        operator: []const u8,
        operand: *ast.Node,
        prefix: bool,
    ) !*ast.Node {
        const data = ast.NodeData{
            .unary_expr = .{
                .operator = operator,
                .operand = operand,
                .prefix = prefix,
            },
        };
        return ast.createNode(self.allocator, .unary_expr, ast.defaultSpan(), data);
    }

    /// Create a member expression node
    pub fn createMemberExpr(
        self: *Self,
        object: *ast.Node,
        property: *ast.Node,
        computed: bool,
        optional: bool,
    ) !*ast.Node {
        const data = ast.NodeData{
            .member_expr = .{
                .object = object,
                .property = property,
                .computed = computed,
                .optional = optional,
            },
        };
        return ast.createNode(self.allocator, .member_expr, ast.defaultSpan(), data);
    }

    /// Create a call expression node
    pub fn createCallExpr(
        self: *Self,
        callee: *ast.Node,
        arguments: std.ArrayList(*ast.Node),
    ) !*ast.Node {
        const data = ast.NodeData{
            .call_expr = .{
                .callee = callee,
                .arguments = arguments,
            },
        };
        return ast.createNode(self.allocator, .call_expr, ast.defaultSpan(), data);
    }

    /// Create an assignment expression node
    pub fn createAssignmentExpr(
        self: *Self,
        operator: []const u8,
        left: *ast.Node,
        right: *ast.Node,
    ) !*ast.Node {
        const data = ast.NodeData{
            .assignment_expr = .{
                .operator = operator,
                .left = left,
                .right = right,
            },
        };
        return ast.createNode(self.allocator, .assignment_expr, ast.defaultSpan(), data);
    }

    /// Create a conditional (ternary) expression node
    pub fn createConditionalExpr(
        self: *Self,
        condition: *ast.Node,
        consequent: *ast.Node,
        alternate: *ast.Node,
    ) !*ast.Node {
        const data = ast.NodeData{
            .conditional_expr = .{
                .condition = condition,
                .consequent = consequent,
                .alternate = alternate,
            },
        };
        return ast.createNode(self.allocator, .conditional_expr, ast.defaultSpan(), data);
    }

    /// Create an identifier expression node
    pub fn createIdentifier(self: *Self, name: []const u8) !*ast.Node {
        const data = ast.NodeData{
            .identifier_expr = .{ .name = name },
        };
        return ast.createNode(self.allocator, .identifier_expr, ast.defaultSpan(), data);
    }

    /// Create a literal expression node
    pub fn createLiteral(
        self: *Self,
        value: []const u8,
        kind: ast.LiteralKind,
    ) !*ast.Node {
        const data = ast.NodeData{
            .literal_expr = .{
                .value = value,
                .kind = kind,
            },
        };
        return ast.createNode(self.allocator, .literal_expr, ast.defaultSpan(), data);
    }

    /// Create an array expression node
    pub fn createArrayExpr(self: *Self, elements: std.ArrayList(*ast.Node)) !*ast.Node {
        const data = ast.NodeData{
            .array_expr = .{ .elements = elements },
        };
        return ast.createNode(self.allocator, .array_expr, ast.defaultSpan(), data);
    }

    /// Create an object expression node
    pub fn createObjectExpr(self: *Self, properties: std.ArrayList(*ast.Node)) !*ast.Node {
        const data = ast.NodeData{
            .object_expr = .{ .properties = properties },
        };
        return ast.createNode(self.allocator, .object_expr, ast.defaultSpan(), data);
    }

    /// Create a property node for object expressions
    pub fn createProperty(
        self: *Self,
        key: []const u8,
        value: ?*ast.Node,
        shorthand: bool,
        computed: bool,
    ) !*ast.Node {
        const data = ast.NodeData{
            .property = .{
                .key = key,
                .value = value,
                .shorthand = shorthand,
                .computed = computed,
            },
        };
        return ast.createNode(self.allocator, .property, ast.defaultSpan(), data);
    }

    /// Create an arrow function node
    pub fn createArrowFunction(
        self: *Self,
        params: std.ArrayList(*ast.Node),
        body: *ast.Node,
        expression: bool,
    ) !*ast.Node {
        const data = ast.NodeData{
            .arrow_function = .{
                .params = params,
                .body = body,
                .expression = expression,
                .async_ = false,
            },
        };
        return ast.createNode(self.allocator, .arrow_function, ast.defaultSpan(), data);
    }

    /// Create a spread element node
    pub fn createSpreadElement(self: *Self, argument: *ast.Node) !*ast.Node {
        const data = ast.NodeData{
            .spread_element = .{ .argument = argument },
        };
        return ast.createNode(self.allocator, .spread_element, ast.defaultSpan(), data);
    }

    /// Create a new expression node
    pub fn createNewExpr(
        self: *Self,
        callee: *ast.Node,
        arguments: std.ArrayList(*ast.Node),
    ) !*ast.Node {
        const data = ast.NodeData{
            .new_expr = .{
                .callee = callee,
                .arguments = arguments,
            },
        };
        return ast.createNode(self.allocator, .new_expr, ast.defaultSpan(), data);
    }

    /// Create an await expression node
    pub fn createAwaitExpr(self: *Self, argument: *ast.Node) !*ast.Node {
        const data = ast.NodeData{
            .await_expression = .{ .argument = argument },
        };
        return ast.createNode(self.allocator, .await_expression, ast.defaultSpan(), data);
    }

    /// Create a template literal node
    pub fn createTemplateLiteral(self: *Self, parts: std.ArrayList(*ast.Node)) !*ast.Node {
        const data = ast.NodeData{
            .template_literal = .{ .parts = parts },
        };
        return ast.createNode(self.allocator, .template_literal, ast.defaultSpan(), data);
    }
};

/// Operator precedence levels
pub const Precedence = enum(u8) {
    none = 0,
    assignment = 1,
    conditional = 2,
    or_op = 3,
    and_op = 4,
    equality = 5,
    comparison = 6,
    additive = 7,
    multiplicative = 8,
    unary = 9,
    postfix = 10,
    primary = 11,
};

/// Get precedence for binary operators
pub fn getBinaryPrecedence(op: []const u8) Precedence {
    if (std.mem.eql(u8, op, "||") or std.mem.eql(u8, op, "??")) return .or_op;
    if (std.mem.eql(u8, op, "&&")) return .and_op;
    if (std.mem.eql(u8, op, "==") or std.mem.eql(u8, op, "!=") or
        std.mem.eql(u8, op, "===") or std.mem.eql(u8, op, "!=="))
        return .equality;
    if (std.mem.eql(u8, op, "<") or std.mem.eql(u8, op, ">") or
        std.mem.eql(u8, op, "<=") or std.mem.eql(u8, op, ">="))
        return .comparison;
    if (std.mem.eql(u8, op, "+") or std.mem.eql(u8, op, "-")) return .additive;
    if (std.mem.eql(u8, op, "*") or std.mem.eql(u8, op, "/") or std.mem.eql(u8, op, "%"))
        return .multiplicative;
    return .none;
}

/// Check if operator is right associative
pub fn isRightAssociative(op: []const u8) bool {
    // Assignment operators are right associative
    return std.mem.eql(u8, op, "=") or
        std.mem.eql(u8, op, "+=") or
        std.mem.eql(u8, op, "-=") or
        std.mem.eql(u8, op, "*=") or
        std.mem.eql(u8, op, "/=");
}

test "expression parser" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var parser = ExpressionParser.init(arena.allocator());

    const id = try parser.createIdentifier("foo");
    try testing.expectEqualStrings("foo", id.data.identifier_expr.name);
}
