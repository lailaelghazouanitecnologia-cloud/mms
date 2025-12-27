const std = @import("std");
const ast = @import("../ast/nodes.zig");

pub const CompilerContext = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    filename: ?[]const u8,
    options: CompilerOptions,
    diagnostics: Diagnostics,

    pub fn init(allocator: std.mem.Allocator, source: []const u8, options: CompilerOptions) CompilerContext {
        return .{
            .allocator = allocator,
            .source = source,
            .filename = options.filename,
            .options = options,
            .diagnostics = Diagnostics.init(allocator),
        };
    }

    pub fn deinit(self: *CompilerContext) void {
        self.diagnostics.deinit();
    }

    pub fn addError(self: *CompilerContext, code: []const u8, message: []const u8, span: ast.Span) !void {
        try self.diagnostics.errors.append(.{
            .code = code,
            .message = message,
            .span = span,
        });
    }

    pub fn addWarning(self: *CompilerContext, code: []const u8, message: []const u8, span: ast.Span) !void {
        try self.diagnostics.warnings.append(.{
            .code = code,
            .message = message,
            .span = span,
        });
    }

    pub fn hasErrors(self: *CompilerContext) bool {
        return self.diagnostics.errors.items.len > 0;
    }
};

pub const CompilerOptions = struct {
    generate: GenerateMode = .dom,
    dev: bool = false,
    hmr: bool = false,
    source_maps: bool = false,
    preserve_comments: bool = false,
    preserve_whitespace: bool = false,
    css_hash: ?[]const u8 = null,
    filename: ?[]const u8 = null,
    hydratable: bool = false,
};

pub const GenerateMode = enum {
    dom,
    ssr,
    hydrate,
};

pub const Diagnostic = struct {
    code: []const u8,
    message: []const u8,
    span: ast.Span,
};

pub const Diagnostics = struct {
    errors: std.ArrayList(Diagnostic),
    warnings: std.ArrayList(Diagnostic),

    pub fn init(allocator: std.mem.Allocator) Diagnostics {
        return .{
            .errors = std.ArrayList(Diagnostic).init(allocator),
            .warnings = std.ArrayList(Diagnostic).init(allocator),
        };
    }

    pub fn deinit(self: *Diagnostics) void {
        self.errors.deinit();
        self.warnings.deinit();
    }

    pub fn merge(self: *Diagnostics, other: *const Diagnostics) !void {
        try self.errors.appendSlice(other.errors.items);
        try self.warnings.appendSlice(other.warnings.items);
    }
};
