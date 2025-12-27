const std = @import("std");
const ast = @import("../ast/nodes.zig");
const rule = @import("rule.zig");
const a11y = @import("rules/a11y.zig");
const bindings = @import("rules/bindings.zig");
const security = @import("rules/security.zig");

pub const ValidationError = error{
    InvalidNode,
    ValidationFailed,
    OutOfMemory,
};

pub const ValidationResult = struct {
    valid: bool,
    errors: []rule.ValidationMessage,
    warnings: []rule.ValidationMessage,
};

pub const Validator = struct {
    allocator: std.mem.Allocator,
    root: *ast.Node,
    ctx: rule.ValidationContext,
    rule_set: rule.RuleSet,

    a11y_rule: a11y.A11yRule,
    security_rule: security.SecurityRule,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, root: *ast.Node, source: []const u8) !Self {
        var validator = Self{
            .allocator = allocator,
            .root = root,
            .ctx = rule.ValidationContext.init(allocator, source, null),
            .rule_set = rule.RuleSet.init(allocator),
            .a11y_rule = a11y.A11yRule.init(),
            .security_rule = security.SecurityRule.init(),
        };

        try validator.rule_set.add(&validator.a11y_rule.base);
        try validator.rule_set.add(&validator.security_rule.base);

        return validator;
    }

    pub fn deinit(self: *Self) void {
        self.ctx.deinit();
        self.rule_set.deinit();
    }

    pub fn validate(self: *Self) !ValidationResult {
        try self.validateNode(self.root);

        return ValidationResult{
            .valid = !self.ctx.hasErrors(),
            .errors = self.ctx.errors.items,
            .warnings = self.ctx.warnings.items,
        };
    }

    fn validateNode(self: *Self, node: *ast.Node) !void {
        try self.rule_set.validateNode(node, &self.ctx);

        switch (node.node_type) {
            .root => {
                const root = node.data.root;
                try self.validateNode(root.fragment);
                if (root.instance) |inst| try self.validateNode(inst);
                if (root.module) |mod| try self.validateNode(mod);
            },
            .fragment => {
                for (node.data.fragment.children.items) |child| {
                    try self.validateNode(child);
                }
            },
            .element => {
                const element = node.data.element;
                for (element.attributes.items) |attr| {
                    try self.validateNode(attr);
                }
                for (element.children.items) |child| {
                    try self.validateNode(child);
                }
            },
            .component => {
                const component = node.data.component;
                for (component.attributes.items) |attr| {
                    try self.validateNode(attr);
                }
                for (component.children.items) |child| {
                    try self.validateNode(child);
                }
            },
            .if_block => {
                const if_block = node.data.if_block;
                try self.validateNode(if_block.condition);
                try self.validateNode(if_block.consequent);
                if (if_block.alternate) |alt| try self.validateNode(alt);
            },
            .each_block => {
                const each = node.data.each_block;
                try self.validateNode(each.expression);
                try self.validateNode(each.context);
                for (each.children.items) |child| {
                    try self.validateNode(child);
                }
                if (each.fallback) |fb| try self.validateNode(fb);
            },
            .await_block => {
                const await_block = node.data.await_block;
                try self.validateNode(await_block.expression);
                if (await_block.pending) |p| try self.validateNode(p);
                if (await_block.then_node) |t| try self.validateNode(t);
                if (await_block.catch_node) |c| try self.validateNode(c);
            },
            .expression_tag => {
                try self.validateNode(node.data.expression_tag.expression);
            },
            .html_tag => {
                try self.validateNode(node.data.html_tag.expression);
            },
            .attribute => {
                switch (node.data.attribute.value) {
                    .expression => |expr| try self.validateNode(expr),
                    else => {},
                }
            },
            .directive => {
                if (node.data.directive.expression) |expr| {
                    try self.validateNode(expr);
                }
            },
            .binary_expr => {
                try self.validateNode(node.data.binary_expr.left);
                try self.validateNode(node.data.binary_expr.right);
            },
            .call_expr => {
                try self.validateNode(node.data.call_expr.callee);
                for (node.data.call_expr.arguments.items) |arg| {
                    try self.validateNode(arg);
                }
            },
            .member_expr => {
                try self.validateNode(node.data.member_expr.object);
                if (node.data.member_expr.computed) {
                    try self.validateNode(node.data.member_expr.property);
                }
            },
            else => {},
        }
    }
};
