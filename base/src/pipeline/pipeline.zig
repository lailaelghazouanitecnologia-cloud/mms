const std = @import("std");
const context = @import("context.zig");
const stage = @import("stage.zig");
const ast = @import("../ast/nodes.zig");
const lexer = @import("../lexer/lexer.zig");
const parser = @import("../parser/parser.zig");
const validator = @import("../validators/validator.zig");
const transformer = @import("../transformers/transformer.zig");
const emitter = @import("../codegen/emitter.zig");

pub const Pipeline = struct {
    ctx: *context.CompilerContext,
    allocator: std.mem.Allocator,

    tokens: ?[]ast.Token = null,
    ast_root: ?*ast.Node = null,
    validated: bool = false,
    transformed: bool = false,
    output: ?CompileOutput = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, source: []const u8, options: context.CompilerOptions) !Self {
        const ctx = try allocator.create(context.CompilerContext);
        ctx.* = context.CompilerContext.init(allocator, source, options);

        return Self{
            .ctx = ctx,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.ctx.deinit();
        self.allocator.destroy(self.ctx);
    }

    pub fn run(self: *Self) !CompileOutput {
        try self.lex();
        if (self.ctx.hasErrors()) return self.buildErrorOutput();

        try self.parse();
        if (self.ctx.hasErrors()) return self.buildErrorOutput();

        try self.validate();
        if (self.ctx.hasErrors()) return self.buildErrorOutput();

        try self.transform();
        if (self.ctx.hasErrors()) return self.buildErrorOutput();

        try self.emit();

        return self.output orelse self.buildErrorOutput();
    }

    pub fn lex(self: *Self) !void {
        var lex = lexer.Lexer.init(self.allocator, self.ctx.source);
        self.tokens = try lex.tokenize();
    }

    pub fn parse(self: *Self) !void {
        if (self.tokens == null) return error.StageSkipped;

        var p = parser.Parser.init(self.allocator, self.tokens.?);
        self.ast_root = try p.parse();
    }

    pub fn validate(self: *Self) !void {
        if (self.ast_root == null) return error.StageSkipped;

        var v = try validator.Validator.init(self.allocator, self.ast_root.?, self.ctx.source);
        _ = try v.validate();
        self.validated = true;
    }

    pub fn transform(self: *Self) !void {
        if (!self.validated) return error.StageSkipped;

        var t = transformer.Transformer.init(self.allocator, self.ast_root.?, self.ctx.options);
        _ = try t.transform();
        self.transformed = true;
    }

    pub fn emit(self: *Self) !void {
        if (!self.transformed) return error.StageSkipped;

        var e = try emitter.Emitter.init(self.allocator, self.ast_root.?, self.ctx.options);
        const result = try e.emit();

        self.output = .{
            .js = result.js,
            .css = result.css,
            .source_map = result.source_map,
            .warnings = self.ctx.diagnostics.warnings.items,
            .errors = self.ctx.diagnostics.errors.items,
        };
    }

    fn buildErrorOutput(self: *Self) CompileOutput {
        return .{
            .js = "",
            .css = null,
            .source_map = null,
            .warnings = self.ctx.diagnostics.warnings.items,
            .errors = self.ctx.diagnostics.errors.items,
        };
    }
};

pub const CompileOutput = struct {
    js: []const u8,
    css: ?[]const u8,
    source_map: ?[]const u8,
    warnings: []context.Diagnostic,
    errors: []context.Diagnostic,
};

pub fn compile(allocator: std.mem.Allocator, source: []const u8, options: context.CompilerOptions) !CompileOutput {
    var pipeline = try Pipeline.init(allocator, source, options);
    defer pipeline.deinit();
    return try pipeline.run();
}
