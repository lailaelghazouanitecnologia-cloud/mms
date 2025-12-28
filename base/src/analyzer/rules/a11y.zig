const std = @import("std");
const ast = @import("../../ast/nodes.zig");

/// A11y warning result
pub const A11yWarning = struct {
    code: []const u8,
    message: []const u8,
    span: ast.Span,
};

/// A11y rule checker for accessibility validation
pub const A11yChecker = struct {
    warnings: std.ArrayList(A11yWarning),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .warnings = std.ArrayList(A11yWarning).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.warnings.deinit();
    }

    /// Check all a11y rules for an element
    pub fn checkElement(self: *Self, node: *ast.Node, element: ast.ElementNode) !void {
        try self.checkAltText(node, element);
        try self.checkAnchorContent(node, element);
        try self.checkAnchorHref(node, element);
        try self.checkTabindex(node, element);
        try self.checkImgAlt(node, element);
        try self.checkMediaCaption(node, element);
        try self.checkClickKeyEvents(node, element);
        try self.checkMouseKeyEvents(node, element);
        try self.checkNonInteractiveTabindex(node, element);
        try self.checkLabelControl(node, element);
    }

    fn addWarning(self: *Self, code: []const u8, message: []const u8, span: ast.Span) !void {
        try self.warnings.append(.{
            .code = code,
            .message = message,
            .span = span,
        });
    }

    /// a11y-alt-text: img, area must have alt attribute
    fn checkAltText(self: *Self, node: *ast.Node, element: ast.ElementNode) !void {
        const name = element.name;
        if (!std.mem.eql(u8, name, "img") and !std.mem.eql(u8, name, "area")) return;

        if (!hasAttribute(element.attributes, "alt") and
            !hasAttribute(element.attributes, "aria-label") and
            !hasAttribute(element.attributes, "aria-labelledby"))
        {
            try self.addWarning(
                "a11y-missing-attribute",
                "Element should have an alt attribute",
                node.span,
            );
        }
    }

    /// a11y-anchor-has-content
    fn checkAnchorContent(self: *Self, node: *ast.Node, element: ast.ElementNode) !void {
        if (!std.mem.eql(u8, element.name, "a")) return;

        if (element.children.items.len == 0 and
            !hasAttribute(element.attributes, "aria-label") and
            !hasAttribute(element.attributes, "aria-labelledby"))
        {
            try self.addWarning(
                "a11y-missing-content",
                "Anchor element should have child content",
                node.span,
            );
        }
    }

    /// a11y-anchor-is-valid
    fn checkAnchorHref(self: *Self, node: *ast.Node, element: ast.ElementNode) !void {
        if (!std.mem.eql(u8, element.name, "a")) return;

        if (getAttributeTextValue(element.attributes, "href")) |href| {
            if (href.len == 0 or std.mem.eql(u8, href, "#") or
                std.mem.eql(u8, href, "javascript:void(0)"))
            {
                try self.addWarning(
                    "a11y-invalid-attribute",
                    "Anchor href should be a valid URL",
                    node.span,
                );
            }
        }
    }

    /// a11y-positive-tabindex
    fn checkTabindex(self: *Self, node: *ast.Node, element: ast.ElementNode) !void {
        if (getAttributeTextValue(element.attributes, "tabindex")) |tabindex| {
            const val = std.fmt.parseInt(i32, tabindex, 10) catch 0;
            if (val > 0) {
                try self.addWarning(
                    "a11y-positive-tabindex",
                    "tabindex should not be greater than 0",
                    node.span,
                );
            }
        }
    }

    /// a11y-img-redundant-alt
    fn checkImgAlt(self: *Self, node: *ast.Node, element: ast.ElementNode) !void {
        if (!std.mem.eql(u8, element.name, "img")) return;

        if (getAttributeTextValue(element.attributes, "alt")) |alt| {
            var buf: [256]u8 = undefined;
            const len = @min(alt.len, 256);
            for (alt[0..len], 0..) |c, i| {
                buf[i] = std.ascii.toLower(c);
            }
            const alt_lower = buf[0..len];

            if (std.mem.indexOf(u8, alt_lower, "image") != null or
                std.mem.indexOf(u8, alt_lower, "picture") != null or
                std.mem.indexOf(u8, alt_lower, "photo") != null)
            {
                try self.addWarning(
                    "a11y-img-redundant-alt",
                    "Avoid using 'image', 'picture', or 'photo' in alt text",
                    node.span,
                );
            }
        }
    }

    /// a11y-media-has-caption
    fn checkMediaCaption(self: *Self, node: *ast.Node, element: ast.ElementNode) !void {
        if (!std.mem.eql(u8, element.name, "video")) return;

        var has_track = false;
        for (element.children.items) |child| {
            if (child.node_type == .element) {
                const child_elem = child.data.element;
                if (std.mem.eql(u8, child_elem.name, "track")) {
                    has_track = true;
                    break;
                }
            }
        }
        if (!has_track and !hasAttribute(element.attributes, "aria-label")) {
            try self.addWarning(
                "a11y-media-has-caption",
                "Video element should have a <track> element for captions",
                node.span,
            );
        }
    }

    /// a11y-click-events-have-key-events
    fn checkClickKeyEvents(self: *Self, node: *ast.Node, element: ast.ElementNode) !void {
        if (!hasDirective(element.attributes, "click")) return;

        if (!hasDirective(element.attributes, "keydown") and
            !hasDirective(element.attributes, "keyup") and
            !hasDirective(element.attributes, "keypress"))
        {
            if (!isInteractiveElement(element.name)) {
                try self.addWarning(
                    "a11y-click-events-have-key-events",
                    "Click handler should have keyboard event handler for accessibility",
                    node.span,
                );
            }
        }
    }

    /// a11y-mouse-events-have-key-events
    fn checkMouseKeyEvents(self: *Self, node: *ast.Node, element: ast.ElementNode) !void {
        if (hasDirective(element.attributes, "mouseenter") or
            hasDirective(element.attributes, "mouseover"))
        {
            if (!hasDirective(element.attributes, "focus")) {
                try self.addWarning(
                    "a11y-mouse-events-have-key-events",
                    "Mouseenter/mouseover handler should have focus handler",
                    node.span,
                );
            }
        }
        if (hasDirective(element.attributes, "mouseleave") or
            hasDirective(element.attributes, "mouseout"))
        {
            if (!hasDirective(element.attributes, "blur")) {
                try self.addWarning(
                    "a11y-mouse-events-have-key-events",
                    "Mouseleave/mouseout handler should have blur handler",
                    node.span,
                );
            }
        }
    }

    /// a11y-no-noninteractive-tabindex
    fn checkNonInteractiveTabindex(self: *Self, node: *ast.Node, element: ast.ElementNode) !void {
        if (isInteractiveElement(element.name) or hasAttribute(element.attributes, "role")) return;

        if (getAttributeTextValue(element.attributes, "tabindex")) |_| {
            try self.addWarning(
                "a11y-no-noninteractive-tabindex",
                "Non-interactive elements should not have tabindex",
                node.span,
            );
        }
    }

    /// a11y-label-has-associated-control
    fn checkLabelControl(self: *Self, node: *ast.Node, element: ast.ElementNode) !void {
        if (!std.mem.eql(u8, element.name, "label")) return;
        if (hasAttribute(element.attributes, "for")) return;

        var has_input = false;
        for (element.children.items) |child| {
            if (child.node_type == .element) {
                const child_elem = child.data.element;
                if (std.mem.eql(u8, child_elem.name, "input") or
                    std.mem.eql(u8, child_elem.name, "textarea") or
                    std.mem.eql(u8, child_elem.name, "select"))
                {
                    has_input = true;
                    break;
                }
            }
        }
        if (!has_input) {
            try self.addWarning(
                "a11y-label-has-associated-control",
                "Label should have 'for' attribute or wrap a form control",
                node.span,
            );
        }
    }
};

// Helper functions

fn hasAttribute(attributes: std.ArrayList(*ast.Node), name: []const u8) bool {
    for (attributes.items) |attr| {
        if (attr.node_type == .attribute) {
            const a = attr.data.attribute;
            if (std.mem.eql(u8, a.name, name)) return true;
        }
    }
    return false;
}

fn getAttributeTextValue(attributes: std.ArrayList(*ast.Node), name: []const u8) ?[]const u8 {
    for (attributes.items) |attr| {
        if (attr.node_type == .attribute) {
            const a = attr.data.attribute;
            if (std.mem.eql(u8, a.name, name)) {
                switch (a.value) {
                    .text => |t| return t,
                    else => return null,
                }
            }
        }
    }
    return null;
}

fn hasDirective(attributes: std.ArrayList(*ast.Node), event_name: []const u8) bool {
    for (attributes.items) |attr| {
        if (attr.node_type == .directive) {
            const d = attr.data.directive;
            if (d.directive_type == .on and std.mem.eql(u8, d.name, event_name)) {
                return true;
            }
        }
    }
    return false;
}

pub fn isInteractiveElement(name: []const u8) bool {
    const interactive_elements = [_][]const u8{
        "a",
        "button",
        "input",
        "select",
        "textarea",
        "details",
        "embed",
        "iframe",
        "keygen",
        "label",
        "menu",
        "menuitem",
        "object",
        "summary",
        "video",
        "audio",
    };

    for (interactive_elements) |elem| {
        if (std.mem.eql(u8, name, elem)) return true;
    }
    return false;
}

test "a11y checker" {
    const testing = std.testing;
    var checker = A11yChecker.init(testing.allocator);
    defer checker.deinit();
    // Add tests here
}
