const std = @import("std");
const ast = @import("../ast/nodes.zig");

pub const RuleError = error{
    ValidationFailed,
    OutOfMemory,
};

pub const Severity = enum {
    @"error",
    warning,
    info,
};

pub const Rule = struct {
    name: []const u8,
    severity: Severity,
    validate_fn: *const fn (*const Rule, *ast.Node, *ValidationContext) RuleError!void,

    pub fn validate(self: *const Rule, node: *ast.Node, ctx: *ValidationContext) RuleError!void {
        return self.validate_fn(self, node, ctx);
    }
};

pub const ValidationContext = struct {
    allocator: std.mem.Allocator,
    errors: std.ArrayList(ValidationMessage),
    warnings: std.ArrayList(ValidationMessage),
    source: []const u8,
    filename: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, source: []const u8, filename: ?[]const u8) ValidationContext {
        return .{
            .allocator = allocator,
            .errors = std.ArrayList(ValidationMessage).init(allocator),
            .warnings = std.ArrayList(ValidationMessage).init(allocator),
            .source = source,
            .filename = filename,
        };
    }

    pub fn deinit(self: *ValidationContext) void {
        self.errors.deinit();
        self.warnings.deinit();
    }

    pub fn addError(self: *ValidationContext, code: []const u8, message: []const u8, span: ast.Span) !void {
        try self.errors.append(.{
            .code = code,
            .message = message,
            .span = span,
            .severity = .@"error",
        });
    }

    pub fn addWarning(self: *ValidationContext, code: []const u8, message: []const u8, span: ast.Span) !void {
        try self.warnings.append(.{
            .code = code,
            .message = message,
            .span = span,
            .severity = .warning,
        });
    }

    pub fn hasErrors(self: *ValidationContext) bool {
        return self.errors.items.len > 0;
    }
};

pub const ValidationMessage = struct {
    code: []const u8,
    message: []const u8,
    span: ast.Span,
    severity: Severity,
};

pub const RuleSet = struct {
    rules: std.ArrayList(*const Rule),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) RuleSet {
        return .{
            .rules = std.ArrayList(*const Rule).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RuleSet) void {
        self.rules.deinit();
    }

    pub fn add(self: *RuleSet, r: *const Rule) !void {
        try self.rules.append(r);
    }

    pub fn validateNode(self: *RuleSet, node: *ast.Node, ctx: *ValidationContext) !void {
        for (self.rules.items) |r| {
            try r.validate(node, ctx);
        }
    }
};
