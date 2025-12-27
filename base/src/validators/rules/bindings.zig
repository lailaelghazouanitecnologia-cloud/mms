const std = @import("std");
const ast = @import("../../ast/nodes.zig");
const rule = @import("../rule.zig");

pub const BindingsRule = struct {
    base: rule.Rule,
    declared_bindings: std.StringHashMap(BindingInfo),
    current_scope_depth: u32,

    const Self = @This();

    const BindingInfo = struct {
        node: *ast.Node,
        scope_depth: u32,
        kind: BindingKind,
        used: bool,
    };

    const BindingKind = enum {
        variable,
        prop,
        each_item,
        snippet_param,
        const_decl,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base = .{
                .name = "bindings",
                .severity = .@"error",
                .validate_fn = validate,
            },
            .declared_bindings = std.StringHashMap(BindingInfo).init(allocator),
            .current_scope_depth = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.declared_bindings.deinit();
    }

    fn validate(r: *const rule.Rule, node: *ast.Node, ctx: *rule.ValidationContext) rule.RuleError!void {
        _ = r;
        switch (node.node_type) {
            .identifier_expr => try validateIdentifier(node, ctx),
            .each_block => try validateEachBlock(node, ctx),
            .snippet_block => try validateSnippet(node, ctx),
            .directive => try validateDirective(node, ctx),
            else => {},
        }
    }

    fn validateIdentifier(node: *ast.Node, ctx: *rule.ValidationContext) !void {
        const name = node.data.identifier_expr.name;

        if (isBuiltinIdentifier(name)) {
            return;
        }

        if (std.mem.startsWith(u8, name, "$")) {
            if (!isValidRune(name)) {
                try ctx.addError("invalid-rune", "Unknown rune identifier", node.span);
            }
            return;
        }
    }

    fn validateEachBlock(node: *ast.Node, ctx: *rule.ValidationContext) !void {
        const each = node.data.each_block;

        if (each.context.node_type == .identifier_expr) {
            const name = each.context.data.identifier_expr.name;
            if (name.len == 0) {
                try ctx.addError("each-missing-context", "Each block must have a context variable", node.span);
            }
        }
    }

    fn validateSnippet(node: *ast.Node, ctx: *rule.ValidationContext) !void {
        const snippet = node.data.snippet_block;

        if (snippet.name.len == 0) {
            try ctx.addError("snippet-missing-name", "Snippet must have a name", node.span);
        }
    }

    fn validateDirective(node: *ast.Node, ctx: *rule.ValidationContext) !void {
        const directive = node.data.directive;

        if (directive.directive_type == .bind) {
            if (directive.expression == null) {
                try ctx.addError("bind-missing-expression", "Bind directive must have an expression", node.span);
            }
        }

        if (directive.directive_type == .on) {
            if (directive.name.len == 0) {
                try ctx.addError("on-missing-event", "Event directive must specify an event name", node.span);
            }
        }
    }

    fn isBuiltinIdentifier(name: []const u8) bool {
        const builtins = [_][]const u8{
            "undefined", "null", "true", "false", "console", "window", "document",
            "Math", "JSON", "Object", "Array", "String", "Number", "Boolean",
            "Date", "Promise", "Set", "Map", "WeakSet", "WeakMap", "Symbol",
            "BigInt", "Infinity", "NaN", "globalThis", "Error", "TypeError",
            "SyntaxError", "ReferenceError", "RangeError", "setTimeout",
            "setInterval", "clearTimeout", "clearInterval", "fetch",
        };

        for (builtins) |builtin| {
            if (std.mem.eql(u8, name, builtin)) {
                return true;
            }
        }
        return false;
    }

    fn isValidRune(name: []const u8) bool {
        const valid_runes = [_][]const u8{
            "$state", "$derived", "$effect", "$props", "$bindable",
            "$inspect", "$host",
        };

        for (valid_runes) |rune| {
            if (std.mem.startsWith(u8, name, rune)) {
                return true;
            }
        }
        return false;
    }
};
