const std = @import("std");
const ast = @import("../../ast/nodes.zig");
const rule = @import("../rule.zig");

pub const A11yRule = struct {
    base: rule.Rule,

    const Self = @This();

    pub fn init() Self {
        return .{
            .base = .{
                .name = "a11y",
                .severity = .warning,
                .validate_fn = validate,
            },
        };
    }

    fn validate(r: *const rule.Rule, node: *ast.Node, ctx: *rule.ValidationContext) rule.RuleError!void {
        _ = r;
        switch (node.node_type) {
            .element => try validateElement(node, ctx),
            else => {},
        }
    }

    fn validateElement(node: *ast.Node, ctx: *rule.ValidationContext) !void {
        const element = node.data.element;

        if (std.mem.eql(u8, element.name, "img")) {
            if (!hasAttribute(element.attributes.items, "alt")) {
                try ctx.addWarning("a11y-img-alt", "Image element should have an alt attribute", node.span);
            }
        }

        if (std.mem.eql(u8, element.name, "a")) {
            if (element.children.items.len == 0 and !hasAttribute(element.attributes.items, "aria-label")) {
                try ctx.addWarning("a11y-link-content", "Anchor elements should have content or aria-label", node.span);
            }
        }

        if (std.mem.eql(u8, element.name, "input")) {
            const input_type = getAttributeValue(element.attributes.items, "type");
            if (input_type == null or !std.mem.eql(u8, input_type.?, "hidden")) {
                if (!hasAttribute(element.attributes.items, "aria-label") and
                    !hasAttribute(element.attributes.items, "id"))
                {
                    try ctx.addWarning("a11y-input-label", "Form inputs should have associated labels", node.span);
                }
            }
        }

        if (std.mem.eql(u8, element.name, "button")) {
            if (element.children.items.len == 0 and !hasAttribute(element.attributes.items, "aria-label")) {
                try ctx.addWarning("a11y-button-content", "Button elements should have content or aria-label", node.span);
            }
        }

        const role = getAttributeValue(element.attributes.items, "role");
        if (role) |r| {
            if (std.mem.eql(u8, r, "button") or std.mem.eql(u8, r, "link")) {
                if (!hasAttribute(element.attributes.items, "tabindex")) {
                    try ctx.addWarning("a11y-interactive-tabindex", "Interactive elements should be focusable", node.span);
                }
            }
        }
    }

    fn hasAttribute(attributes: []*ast.Node, name: []const u8) bool {
        for (attributes) |attr| {
            if (attr.node_type == .attribute) {
                if (std.mem.eql(u8, attr.data.attribute.name, name)) {
                    return true;
                }
            }
        }
        return false;
    }

    fn getAttributeValue(attributes: []*ast.Node, name: []const u8) ?[]const u8 {
        for (attributes) |attr| {
            if (attr.node_type == .attribute) {
                if (std.mem.eql(u8, attr.data.attribute.name, name)) {
                    switch (attr.data.attribute.value) {
                        .text => |text| return text,
                        else => return null,
                    }
                }
            }
        }
        return null;
    }
};
