const std = @import("std");
const ast = @import("../ast/nodes.zig");
const a11y = @import("rules/a11y.zig");

pub const AnalysisError = error{
    UndefinedVariable,
    InvalidDirective,
    DuplicateDeclaration,
    InvalidExpression,
    UnreachableCode,
    OutOfMemory,
};

pub const Binding = struct {
    name: []const u8,
    kind: BindingKind,
    node: *ast.Node,
    mutated: bool,
    reassigned: bool,
    referenced: bool,
};

pub const BindingKind = enum {
    normal,
    state,
    derived,
    prop,
    bindable,
    each_item,
    each_index,
    snippet_param,
    const_tag,
    store_sub,
};

pub const Scope = struct {
    parent: ?*Scope,
    bindings: std.StringHashMap(Binding),
    references: std.ArrayList(Reference),
    is_component_root: bool,
    in_snippet: bool,

    pub fn init(allocator: std.mem.Allocator, parent: ?*Scope) Scope {
        return .{
            .parent = parent,
            .bindings = std.StringHashMap(Binding).init(allocator),
            .references = std.ArrayList(Reference).init(allocator),
            .is_component_root = false,
            .in_snippet = false,
        };
    }

    pub fn deinit(self: *Scope) void {
        self.bindings.deinit();
        self.references.deinit();
    }

    pub fn declare(self: *Scope, name: []const u8, binding: Binding) !void {
        try self.bindings.put(name, binding);
    }

    pub fn lookup(self: *Scope, name: []const u8) ?Binding {
        if (self.bindings.get(name)) |binding| {
            return binding;
        }
        if (self.parent) |parent| {
            return parent.lookup(name);
        }
        return null;
    }
};

pub const Reference = struct {
    name: []const u8,
    node: *ast.Node,
    is_write: bool,
};

pub const ComponentAnalysis = struct {
    root: *ast.Node,
    source: []const u8,
    allocator: std.mem.Allocator,

    root_scope: Scope,
    reactive_statements: std.ArrayList(*ast.Node),
    template_scope: Scope,

    props: std.ArrayList(PropInfo),
    exports: std.ArrayList(ExportInfo),
    stores: std.ArrayList(StoreInfo),

    warnings: std.ArrayList(Warning),
    errors: std.ArrayList(Error),

    uses_slots: bool,
    uses_component_bindings: bool,
    uses_props_rune: bool,
    uses_state_rune: bool,
    uses_derived_rune: bool,
    uses_effect_rune: bool,
    has_script: bool,
    has_style: bool,
    is_custom_element: bool,

    pub fn init(allocator: std.mem.Allocator, root: *ast.Node, source: []const u8) ComponentAnalysis {
        return .{
            .root = root,
            .source = source,
            .allocator = allocator,
            .root_scope = Scope.init(allocator, null),
            .reactive_statements = std.ArrayList(*ast.Node).init(allocator),
            .template_scope = Scope.init(allocator, null),
            .props = std.ArrayList(PropInfo).init(allocator),
            .exports = std.ArrayList(ExportInfo).init(allocator),
            .stores = std.ArrayList(StoreInfo).init(allocator),
            .warnings = std.ArrayList(Warning).init(allocator),
            .errors = std.ArrayList(Error).init(allocator),
            .uses_slots = false,
            .uses_component_bindings = false,
            .uses_props_rune = false,
            .uses_state_rune = false,
            .uses_derived_rune = false,
            .uses_effect_rune = false,
            .has_script = false,
            .has_style = false,
            .is_custom_element = false,
        };
    }

    pub fn deinit(self: *ComponentAnalysis) void {
        self.root_scope.deinit();
        self.reactive_statements.deinit();
        self.template_scope.deinit();
        self.props.deinit();
        self.exports.deinit();
        self.stores.deinit();
        self.warnings.deinit();
        self.errors.deinit();
    }
};

pub const PropInfo = struct {
    name: []const u8,
    bindable: bool,
    optional: bool,
    default_value: ?*ast.Node,
};

pub const ExportInfo = struct {
    name: []const u8,
    node: *ast.Node,
};

pub const StoreInfo = struct {
    name: []const u8,
    subscribed: bool,
};

pub const Warning = struct {
    code: []const u8,
    message: []const u8,
    span: ast.Span,
};

pub const Error = struct {
    code: []const u8,
    message: []const u8,
    span: ast.Span,
};

pub const Analyzer = struct {
    analysis: *ComponentAnalysis,
    current_scope: *Scope,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, root: *ast.Node, source: []const u8) !Self {
        const analysis = try allocator.create(ComponentAnalysis);
        analysis.* = ComponentAnalysis.init(allocator, root, source);

        return Self{
            .analysis = analysis,
            .current_scope = &analysis.root_scope,
            .allocator = allocator,
        };
    }

    pub fn analyze(self: *Self) AnalysisError!*ComponentAnalysis {
        try self.analyzeNode(self.analysis.root);
        return self.analysis;
    }

    fn analyzeNode(self: *Self, node: *ast.Node) AnalysisError!void {
        switch (node.node_type) {
            .root => try self.analyzeRoot(node),
            .fragment => try self.analyzeFragment(node),
            .element => try self.analyzeElement(node),
            .component => try self.analyzeComponent(node),
            .if_block => try self.analyzeIfBlock(node),
            .each_block => try self.analyzeEachBlock(node),
            .await_block => try self.analyzeAwaitBlock(node),
            .key_block => try self.analyzeKeyBlock(node),
            .snippet_block => try self.analyzeSnippetBlock(node),
            .expression_tag => try self.analyzeExpressionTag(node),
            .html_tag => try self.analyzeHtmlTag(node),
            .render_tag => try self.analyzeRenderTag(node),
            .attribute => try self.analyzeAttribute(node),
            .directive => try self.analyzeDirective(node),
            .slot => try self.analyzeSlot(node),
            .identifier_expr => try self.analyzeIdentifier(node),
            .member_expr => try self.analyzeMemberExpr(node),
            .call_expr => try self.analyzeCallExpr(node),
            .binary_expr => try self.analyzeBinaryExpr(node),
            else => {},
        }
    }

    fn analyzeRoot(self: *Self, node: *ast.Node) AnalysisError!void {
        const root = node.data.root;

        if (root.instance) |instance| {
            self.analysis.has_script = true;
            try self.analyzeScript(instance);
        }

        if (root.module) |module| {
            try self.analyzeModuleScript(module);
        }

        if (root.options) |options| {
            try self.analyzeOptions(options);
        }

        try self.analyzeNode(root.fragment);

        if (root.css) |css| {
            self.analysis.has_style = true;
            try self.analyzeStyle(css);
        }
    }

    fn analyzeFragment(self: *Self, node: *ast.Node) AnalysisError!void {
        const fragment = node.data.fragment;

        for (fragment.children.items) |child| {
            try self.analyzeNode(child);
        }
    }

    fn analyzeElement(self: *Self, node: *ast.Node) AnalysisError!void {
        const element = node.data.element;

        for (element.attributes.items) |attr| {
            try self.analyzeNode(attr);
        }

        for (element.children.items) |child| {
            try self.analyzeNode(child);
        }

        if (std.mem.eql(u8, element.name, "slot")) {
            self.analysis.uses_slots = true;
        }

        // A11y checks - delegated to specialized module
        try self.runA11yChecks(node, element);
    }

    /// Run a11y checks using the specialized a11y module
    fn runA11yChecks(self: *Self, node: *ast.Node, element: ast.ElementNode) AnalysisError!void {
        var checker = a11y.A11yChecker.init(self.allocator);
        defer checker.deinit();

        checker.checkElement(node, element) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };

        // Transfer a11y warnings to analysis warnings
        for (checker.warnings.items) |warning| {
            try self.analysis.warnings.append(.{
                .code = warning.code,
                .message = warning.message,
                .span = warning.span,
            });
        }
    }

    fn analyzeComponent(self: *Self, node: *ast.Node) AnalysisError!void {
        const component = node.data.component;

        if (self.current_scope.lookup(component.name) == null) {
            try self.analysis.warnings.append(.{
                .code = "component-not-found",
                .message = "Component not found in scope",
                .span = node.span,
            });
        }

        for (component.attributes.items) |attr| {
            try self.analyzeNode(attr);
        }

        for (component.children.items) |child| {
            try self.analyzeNode(child);
        }
    }

    fn analyzeIfBlock(self: *Self, node: *ast.Node) AnalysisError!void {
        const if_block = node.data.if_block;

        try self.analyzeNode(if_block.condition);

        try self.analyzeNode(if_block.consequent);

        if (if_block.alternate) |alternate| {
            try self.analyzeNode(alternate);
        }
    }

    fn analyzeEachBlock(self: *Self, node: *ast.Node) AnalysisError!void {
        const each_block = node.data.each_block;

        try self.analyzeNode(each_block.expression);

        var each_scope = Scope.init(self.allocator, self.current_scope);
        defer each_scope.deinit();

        const old_scope = self.current_scope;
        self.current_scope = &each_scope;

        try each_scope.declare("item", .{
            .name = "item",
            .kind = .each_item,
            .node = each_block.context,
            .mutated = false,
            .reassigned = false,
            .referenced = false,
        });

        if (each_block.index) |index_name| {
            try each_scope.declare(index_name, .{
                .name = index_name,
                .kind = .each_index,
                .node = node,
                .mutated = false,
                .reassigned = false,
                .referenced = false,
            });
        }

        if (each_block.key) |key| {
            try self.analyzeNode(key);
        }

        for (each_block.children.items) |child| {
            try self.analyzeNode(child);
        }

        if (each_block.fallback) |fallback| {
            try self.analyzeNode(fallback);
        }

        self.current_scope = old_scope;
    }

    fn analyzeAwaitBlock(self: *Self, node: *ast.Node) AnalysisError!void {
        const await_block = node.data.await_block;

        try self.analyzeNode(await_block.expression);

        if (await_block.pending) |pending| {
            try self.analyzeNode(pending);
        }

        if (await_block.then_node) |then_node| {
            var then_scope = Scope.init(self.allocator, self.current_scope);
            defer then_scope.deinit();

            if (await_block.value) |value| {
                _ = value;
            }

            const old_scope = self.current_scope;
            self.current_scope = &then_scope;
            try self.analyzeNode(then_node);
            self.current_scope = old_scope;
        }

        if (await_block.catch_node) |catch_node| {
            var catch_scope = Scope.init(self.allocator, self.current_scope);
            defer catch_scope.deinit();

            if (await_block.error_node) |error_val| {
                _ = error_val;
            }

            const old_scope = self.current_scope;
            self.current_scope = &catch_scope;
            try self.analyzeNode(catch_node);
            self.current_scope = old_scope;
        }
    }

    fn analyzeKeyBlock(self: *Self, node: *ast.Node) AnalysisError!void {
        const key_block = node.data.key_block;

        try self.analyzeNode(key_block.expression);

        for (key_block.children.items) |child| {
            try self.analyzeNode(child);
        }
    }

    fn analyzeSnippetBlock(self: *Self, node: *ast.Node) AnalysisError!void {
        const snippet = node.data.snippet_block;

        var snippet_scope = Scope.init(self.allocator, self.current_scope);
        snippet_scope.in_snippet = true;
        defer snippet_scope.deinit();

        for (snippet.parameters.items) |param| {
            if (param.node_type == .identifier_expr) {
                try snippet_scope.declare(param.data.identifier_expr.name, .{
                    .name = param.data.identifier_expr.name,
                    .kind = .snippet_param,
                    .node = param,
                    .mutated = false,
                    .reassigned = false,
                    .referenced = false,
                });
            }
        }

        const old_scope = self.current_scope;
        self.current_scope = &snippet_scope;
        try self.analyzeNode(snippet.body);
        self.current_scope = old_scope;

        try self.current_scope.declare(snippet.name, .{
            .name = snippet.name,
            .kind = .normal,
            .node = node,
            .mutated = false,
            .reassigned = false,
            .referenced = false,
        });
    }

    fn analyzeExpressionTag(self: *Self, node: *ast.Node) AnalysisError!void {
        const expr_tag = node.data.expression_tag;
        try self.analyzeNode(expr_tag.expression);
    }

    fn analyzeHtmlTag(self: *Self, node: *ast.Node) AnalysisError!void {
        const html_tag = node.data.html_tag;
        try self.analyzeNode(html_tag.expression);

        try self.analysis.warnings.append(.{
            .code = "security-xss",
            .message = "@html can lead to XSS vulnerabilities",
            .span = node.span,
        });
    }

    fn analyzeRenderTag(self: *Self, node: *ast.Node) AnalysisError!void {
        const render_tag = node.data.render_tag;
        try self.analyzeNode(render_tag.expression);

        if (render_tag.argument) |arg| {
            try self.analyzeNode(arg);
        }
    }

    fn analyzeAttribute(self: *Self, node: *ast.Node) AnalysisError!void {
        const attr = node.data.attribute;

        switch (attr.value) {
            .expression => |expr| {
                try self.analyzeNode(expr);
            },
            .concat => |parts| {
                for (parts.items) |part| {
                    switch (part) {
                        .expression => |expr| {
                            try self.analyzeNode(expr);
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }

    fn analyzeDirective(self: *Self, node: *ast.Node) AnalysisError!void {
        const directive = node.data.directive;

        if (directive.expression) |expr| {
            try self.analyzeNode(expr);
        }

        switch (directive.directive_type) {
            .bind => {
                self.analysis.uses_component_bindings = true;
            },
            .use => {
                if (directive.expression) |expr| {
                    if (expr.node_type == .identifier_expr) {
                        const name = expr.data.identifier_expr.name;
                        if (self.current_scope.lookup(name) == null) {
                            try self.analysis.warnings.append(.{
                                .code = "action-not-found",
                                .message = "Action not found in scope",
                                .span = node.span,
                            });
                        }
                    }
                }
            },
            .transition, .in_directive, .out_directive => {},
            .animate => {},
            else => {},
        }
    }

    fn analyzeSlot(self: *Self, node: *ast.Node) AnalysisError!void {
        _ = node;
        self.analysis.uses_slots = true;
    }

    fn analyzeIdentifier(self: *Self, node: *ast.Node) AnalysisError!void {
        const id = node.data.identifier_expr;

        if (self.current_scope.lookup(id.name) == null) {
            if (!isBuiltin(id.name)) {
                try self.analysis.warnings.append(.{
                    .code = "undefined-reference",
                    .message = "Variable not defined",
                    .span = node.span,
                });
            }
        }

        if (std.mem.startsWith(u8, id.name, "$state")) {
            self.analysis.uses_state_rune = true;
        } else if (std.mem.startsWith(u8, id.name, "$derived")) {
            self.analysis.uses_derived_rune = true;
        } else if (std.mem.startsWith(u8, id.name, "$effect")) {
            self.analysis.uses_effect_rune = true;
        } else if (std.mem.startsWith(u8, id.name, "$props")) {
            self.analysis.uses_props_rune = true;
        }
    }

    fn analyzeMemberExpr(self: *Self, node: *ast.Node) AnalysisError!void {
        const member = node.data.member_expr;
        try self.analyzeNode(member.object);
        if (member.computed) {
            try self.analyzeNode(member.property);
        }
    }

    fn analyzeCallExpr(self: *Self, node: *ast.Node) AnalysisError!void {
        const call = node.data.call_expr;
        try self.analyzeNode(call.callee);

        for (call.arguments.items) |arg| {
            try self.analyzeNode(arg);
        }
    }

    fn analyzeBinaryExpr(self: *Self, node: *ast.Node) AnalysisError!void {
        const binary = node.data.binary_expr;
        try self.analyzeNode(binary.left);
        try self.analyzeNode(binary.right);
    }

    fn analyzeScript(self: *Self, node: *ast.Node) AnalysisError!void {
        _ = self;
        _ = node;
    }

    fn analyzeModuleScript(self: *Self, node: *ast.Node) AnalysisError!void {
        _ = self;
        _ = node;
    }

    fn analyzeOptions(self: *Self, node: *ast.Node) AnalysisError!void {
        const options = node.data.svelte_options;

        for (options.attributes.items) |attr| {
            if (attr.node_type == .attribute) {
                const attribute = attr.data.attribute;
                if (std.mem.eql(u8, attribute.name, "customElement")) {
                    self.analysis.is_custom_element = true;
                }
            }
        }
    }

    fn analyzeStyle(self: *Self, node: *ast.Node) AnalysisError!void {
        _ = self;
        _ = node;
    }
};

fn isBuiltin(name: []const u8) bool {
    const builtins = [_][]const u8{
        "undefined",
        "null",
        "true",
        "false",
        "console",
        "window",
        "document",
        "Math",
        "JSON",
        "Object",
        "Array",
        "String",
        "Number",
        "Boolean",
        "Date",
        "Promise",
        "Set",
        "Map",
        "WeakSet",
        "WeakMap",
        "Symbol",
        "BigInt",
        "Infinity",
        "NaN",
        "globalThis",
        "Error",
        "TypeError",
        "SyntaxError",
        "ReferenceError",
        "RangeError",
        "setTimeout",
        "setInterval",
        "clearTimeout",
        "clearInterval",
        "fetch",
        "alert",
        "confirm",
        "prompt",
    };

    for (builtins) |builtin| {
        if (std.mem.eql(u8, name, builtin)) {
            return true;
        }
    }

    return false;
}

test "analyzer basic" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var children = std.ArrayList(*ast.Node).init(allocator);

    const fragment_data = ast.NodeData{
        .fragment = .{
            .children = children,
            .transparent = false,
        },
    };

    const fragment = try ast.createNode(
        allocator,
        .fragment,
        ast.defaultSpan(),
        fragment_data,
    );

    const root_data = ast.NodeData{
        .root = .{
            .fragment = fragment,
            .instance = null,
            .module = null,
            .options = null,
            .css = null,
            .metadata = .{},
        },
    };

    const root = try ast.createNode(
        allocator,
        .root,
        ast.defaultSpan(),
        root_data,
    );

    var a = try Analyzer.init(allocator, root, "");
    const analysis = try a.analyze();

    try std.testing.expect(!analysis.has_script);
}
