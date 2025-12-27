const std = @import("std");
const context = @import("context.zig");
const ast = @import("../ast/nodes.zig");
const lexer = @import("../lexer/lexer.zig");
const parser = @import("../parser/parser.zig");
const validator = @import("../validators/validator.zig");
const transformer = @import("../transformers/transformer.zig");
const emitter = @import("../codegen/emitter.zig");

pub const PipelineError = error{
    LexerFailed,
    ParseFailed,
    ValidationFailed,
    TransformFailed,
    EmitFailed,
    OutOfMemory,
};

pub const Pipeline = struct {
    ctx: *context.CompilerContext,
    allocator: std.mem.Allocator,

    tokens: ?[]ast.Token = null,
    ast_root: ?*ast.Node = null,
    validated: bool = false,
    transformed: bool = false,

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
        self.lex() catch |err| {
            try self.ctx.addError("lexer-error", "Lexer failed", ast.defaultSpan());
            return self.buildOutput("", null, null);
        };

        self.parse() catch |err| {
            try self.ctx.addError("parse-error", "Parser failed", ast.defaultSpan());
            return self.buildOutput("", null, null);
        };

        self.validate() catch {};

        if (self.ctx.hasErrors()) {
            return self.buildOutput("", null, null);
        }

        self.transform() catch {};

        const emit_result = self.emit() catch {
            return self.buildOutput("", null, null);
        };

        return self.buildOutput(emit_result.js, emit_result.css, emit_result.source_map);
    }

    fn lex(self: *Self) !void {
        var l = lexer.Lexer.init(self.allocator, self.ctx.source);
        self.tokens = try l.tokenize();
    }

    fn parse(self: *Self) !void {
        if (self.tokens == null) return PipelineError.LexerFailed;

        var p = parser.Parser.init(self.allocator, self.tokens.?);
        self.ast_root = try p.parse();
    }

    fn validate(self: *Self) !void {
        if (self.ast_root == null) return;

        var v = try validator.Validator.init(self.allocator, self.ast_root.?, self.ctx.source);
        defer v.deinit();

        const result = try v.validate();

        for (result.errors) |err| {
            try self.ctx.addError(err.code, err.message, err.span);
        }

        for (result.warnings) |warn| {
            try self.ctx.addWarning(warn.code, warn.message, warn.span);
        }

        self.validated = true;
    }

    fn transform(self: *Self) !void {
        if (self.ast_root == null) return;

        var t = transformer.Transformer.init(self.allocator, self.ast_root.?, self.ctx.options);
        defer t.deinit();

        const result = try t.transform();
        self.ast_root = result.root;
        self.transformed = true;
    }

    fn emit(self: *Self) !emitter.EmitResult {
        if (self.ast_root == null) return PipelineError.EmitFailed;

        var e = try emitter.Emitter.init(self.allocator, self.ast_root.?, self.ctx.options);
        defer e.deinit();

        return try e.emit();
    }

    fn buildOutput(self: *Self, js: []const u8, css: ?[]const u8, source_map: ?[]const u8) CompileOutput {
        return .{
            .js = js,
            .css = css,
            .source_map = source_map,
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
