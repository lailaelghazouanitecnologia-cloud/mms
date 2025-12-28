const std = @import("std");
const ast = @import("../../ast/nodes.zig");

/// Element and tag parsing utilities
pub const ElementParser = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    /// Create an element node
    pub fn createElement(
        self: *Self,
        name: []const u8,
        attributes: std.ArrayList(*ast.Node),
        children: std.ArrayList(*ast.Node),
        self_closing: bool,
    ) !*ast.Node {
        const data = ast.NodeData{
            .element = .{
                .name = name,
                .attributes = attributes,
                .children = children,
                .self_closing = self_closing,
            },
        };
        return ast.createNode(self.allocator, .element, ast.defaultSpan(), data);
    }

    /// Create a component node (capitalized elements)
    pub fn createComponent(
        self: *Self,
        name: []const u8,
        attributes: std.ArrayList(*ast.Node),
        children: std.ArrayList(*ast.Node),
    ) !*ast.Node {
        const data = ast.NodeData{
            .component = .{
                .name = name,
                .attributes = attributes,
                .children = children,
            },
        };
        return ast.createNode(self.allocator, .component, ast.defaultSpan(), data);
    }

    /// Create an attribute node
    pub fn createAttribute(
        self: *Self,
        name: []const u8,
        value: ast.AttributeValue,
    ) !*ast.Node {
        const data = ast.NodeData{
            .attribute = .{
                .name = name,
                .value = value,
            },
        };
        return ast.createNode(self.allocator, .attribute, ast.defaultSpan(), data);
    }

    /// Create a directive node
    pub fn createDirective(
        self: *Self,
        directive_type: ast.DirectiveType,
        name: []const u8,
        expression: ?*ast.Node,
        modifiers: std.ArrayList([]const u8),
    ) !*ast.Node {
        const data = ast.NodeData{
            .directive = .{
                .directive_type = directive_type,
                .name = name,
                .expression = expression,
                .modifiers = modifiers,
            },
        };
        return ast.createNode(self.allocator, .directive, ast.defaultSpan(), data);
    }

    /// Create a text node
    pub fn createText(self: *Self, raw: []const u8) !*ast.Node {
        const data = ast.NodeData{
            .text = .{
                .raw = raw,
                .data = raw,
            },
        };
        return ast.createNode(self.allocator, .text, ast.defaultSpan(), data);
    }

    /// Create a comment node
    pub fn createComment(self: *Self, content: []const u8) !*ast.Node {
        const data = ast.NodeData{
            .comment = .{ .data = content },
        };
        return ast.createNode(self.allocator, .comment, ast.defaultSpan(), data);
    }

    /// Create an expression tag node ({expression})
    pub fn createExpressionTag(self: *Self, expression: *ast.Node) !*ast.Node {
        const data = ast.NodeData{
            .expression_tag = .{ .expression = expression },
        };
        return ast.createNode(self.allocator, .expression_tag, ast.defaultSpan(), data);
    }

    /// Create an @html tag node
    pub fn createHtmlTag(self: *Self, expression: *ast.Node) !*ast.Node {
        const data = ast.NodeData{
            .html_tag = .{ .expression = expression },
        };
        return ast.createNode(self.allocator, .html_tag, ast.defaultSpan(), data);
    }

    /// Create an @render tag node
    pub fn createRenderTag(
        self: *Self,
        expression: *ast.Node,
        arguments: std.ArrayList(*ast.Node),
    ) !*ast.Node {
        const data = ast.NodeData{
            .render_tag = .{
                .expression = expression,
                .arguments = arguments,
            },
        };
        return ast.createNode(self.allocator, .render_tag, ast.defaultSpan(), data);
    }

    /// Create an @const tag node
    pub fn createConstTag(
        self: *Self,
        declaration: *ast.Node,
    ) !*ast.Node {
        const data = ast.NodeData{
            .const_tag = .{ .declaration = declaration },
        };
        return ast.createNode(self.allocator, .const_tag, ast.defaultSpan(), data);
    }

    /// Create an @debug tag node
    pub fn createDebugTag(
        self: *Self,
        identifiers: std.ArrayList(*ast.Node),
    ) !*ast.Node {
        const data = ast.NodeData{
            .debug_tag = .{ .identifiers = identifiers },
        };
        return ast.createNode(self.allocator, .debug_tag, ast.defaultSpan(), data);
    }
};

/// Check if element name indicates a component (starts with uppercase or contains dot/colon)
pub fn isComponentName(name: []const u8) bool {
    if (name.len == 0) return false;
    // Starts with uppercase letter
    if (name[0] >= 'A' and name[0] <= 'Z') return true;
    // Contains dot (namespaced component)
    if (std.mem.indexOf(u8, name, ".") != null) return true;
    return false;
}

/// Check if element is a svelte: special element
pub fn isSvelteElement(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "svelte:");
}

/// Get svelte element type
pub const SvelteElementType = enum {
    self,
    component,
    element,
    window,
    document,
    body,
    head,
    options,
    fragment,
    boundary,
    unknown,

    pub fn fromName(name: []const u8) SvelteElementType {
        if (!std.mem.startsWith(u8, name, "svelte:")) return .unknown;
        const suffix = name[7..];
        if (std.mem.eql(u8, suffix, "self")) return .self;
        if (std.mem.eql(u8, suffix, "component")) return .component;
        if (std.mem.eql(u8, suffix, "element")) return .element;
        if (std.mem.eql(u8, suffix, "window")) return .window;
        if (std.mem.eql(u8, suffix, "document")) return .document;
        if (std.mem.eql(u8, suffix, "body")) return .body;
        if (std.mem.eql(u8, suffix, "head")) return .head;
        if (std.mem.eql(u8, suffix, "options")) return .options;
        if (std.mem.eql(u8, suffix, "fragment")) return .fragment;
        if (std.mem.eql(u8, suffix, "boundary")) return .boundary;
        return .unknown;
    }
};

/// Void elements that don't need closing tags
const void_elements = [_][]const u8{
    "area",
    "base",
    "br",
    "col",
    "embed",
    "hr",
    "img",
    "input",
    "link",
    "meta",
    "param",
    "source",
    "track",
    "wbr",
};

pub fn isVoidElement(name: []const u8) bool {
    for (void_elements) |elem| {
        if (std.mem.eql(u8, name, elem)) return true;
    }
    return false;
}

test "element parser helpers" {
    const testing = std.testing;

    try testing.expect(isComponentName("Button"));
    try testing.expect(isComponentName("my.Component"));
    try testing.expect(!isComponentName("div"));
    try testing.expect(!isComponentName("button"));

    try testing.expect(isSvelteElement("svelte:head"));
    try testing.expect(!isSvelteElement("div"));

    try testing.expect(isVoidElement("br"));
    try testing.expect(isVoidElement("img"));
    try testing.expect(!isVoidElement("div"));
}
