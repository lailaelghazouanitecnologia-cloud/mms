const std = @import("std");
const ast = @import("../../ast/nodes.zig");
const rule = @import("../rule.zig");

pub const SecurityRule = struct {
    base: rule.Rule,

    const Self = @This();

    pub fn init() Self {
        return .{
            .base = .{
                .name = "security",
                .severity = .warning,
                .validate_fn = validate,
            },
        };
    }

    fn validate(r: *const rule.Rule, node: *ast.Node, ctx: *rule.ValidationContext) rule.RuleError!void {
        _ = r;
        switch (node.node_type) {
            .html_tag => try validateHtmlTag(node, ctx),
            .element => try validateElement(node, ctx),
            .directive => try validateDirective(node, ctx),
            else => {},
        }
    }

    fn validateHtmlTag(node: *ast.Node, ctx: *rule.ValidationContext) !void {
        try ctx.addWarning(
            "security-xss",
            "@html can lead to XSS vulnerabilities if used with untrusted content",
            node.span,
        );
    }

    fn validateElement(node: *ast.Node, ctx: *rule.ValidationContext) !void {
        const element = node.data.element;

        if (std.mem.eql(u8, element.name, "script")) {
            for (element.attributes.items) |attr| {
                if (attr.node_type == .attribute) {
                    const a = attr.data.attribute;
                    if (std.mem.eql(u8, a.name, "src")) {
                        switch (a.value) {
                            .expression => {
                                try ctx.addWarning(
                                    "security-script-src",
                                    "Dynamic script src can be a security risk",
                                    node.span,
                                );
                            },
                            else => {},
                        }
                    }
                }
            }
        }

        if (std.mem.eql(u8, element.name, "iframe")) {
            var has_sandbox = false;
            for (element.attributes.items) |attr| {
                if (attr.node_type == .attribute) {
                    if (std.mem.eql(u8, attr.data.attribute.name, "sandbox")) {
                        has_sandbox = true;
                        break;
                    }
                }
            }
            if (!has_sandbox) {
                try ctx.addWarning(
                    "security-iframe-sandbox",
                    "Consider adding sandbox attribute to iframe for security",
                    node.span,
                );
            }
        }

        for (element.attributes.items) |attr| {
            if (attr.node_type == .attribute) {
                const a = attr.data.attribute;
                if (std.mem.eql(u8, a.name, "href") or std.mem.eql(u8, a.name, "src")) {
                    switch (a.value) {
                        .text => |text| {
                            if (std.mem.startsWith(u8, text, "javascript:")) {
                                try ctx.addWarning(
                                    "security-javascript-url",
                                    "javascript: URLs can be a security risk",
                                    node.span,
                                );
                            }
                        },
                        else => {},
                    }
                }
            }
        }
    }

    fn validateDirective(node: *ast.Node, ctx: *rule.ValidationContext) !void {
        const directive = node.data.directive;

        if (directive.directive_type == .on) {
            if (directive.expression) |expr| {
                if (containsEval(expr)) {
                    try ctx.addWarning(
                        "security-eval",
                        "Using eval() in event handlers is a security risk",
                        node.span,
                    );
                }
            }
        }
    }

    fn containsEval(node: *ast.Node) bool {
        switch (node.node_type) {
            .call_expr => {
                const call = node.data.call_expr;
                if (call.callee.node_type == .identifier_expr) {
                    const name = call.callee.data.identifier_expr.name;
                    if (std.mem.eql(u8, name, "eval") or std.mem.eql(u8, name, "Function")) {
                        return true;
                    }
                }
            },
            else => {},
        }
        return false;
    }
};
