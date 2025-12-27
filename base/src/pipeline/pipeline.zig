const std = @import("std");
const context = @import("context.zig");
const ast = @import("../ast/nodes.zig");
const lexer = @import("../lexer/lexer.zig");
const parser = @import("../parser/parser.zig");
const analyzer = @import("../analyzer/analyzer.zig");
const validator = @import("../validators/validator.zig");
const transformer = @import("../transformers/transformer.zig");
const emitter = @import("../codegen/emitter.zig");

pub const PipelineError = error{
    LexerFailed,
    ParseFailed,
    AnalysisFailed,
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
    analysis: ?*analyzer.ComponentAnalysis = null,
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
        self.lex() catch {
            try self.ctx.addError("lexer-error", "Lexer failed", ast.defaultSpan());
            return self.buildOutput("", null, null);
        };

        self.parse() catch {
            try self.ctx.addError("parse-error", "Parser failed", ast.defaultSpan());
            return self.buildOutput("", null, null);
        };

        self.analyze() catch {};

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

    fn analyze(self: *Self) !void {
        if (self.ast_root == null) return;

        var a = try analyzer.Analyzer.init(self.allocator, self.ast_root.?, self.ctx.source);
        self.analysis = try a.analyze();

        for (self.analysis.?.warnings.items) |warn| {
            try self.ctx.addWarning(warn.code, warn.message, warn.span);
        }

        for (self.analysis.?.errors.items) |err| {
            try self.ctx.addError(err.code, err.message, err.span);
        }
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
        var metadata = CompileOutput.Metadata{};

        if (self.analysis) |a| {
            metadata = .{
                .has_script = a.has_script,
                .has_style = a.has_style,
                .uses_slots = a.uses_slots,
                .uses_props_rune = a.uses_props_rune,
                .uses_state_rune = a.uses_state_rune,
                .uses_derived_rune = a.uses_derived_rune,
                .uses_effect_rune = a.uses_effect_rune,
                .is_custom_element = a.is_custom_element,
            };
        }

        return .{
            .js = js,
            .css = css,
            .source_map = source_map,
            .warnings = self.ctx.diagnostics.warnings.items,
            .errors = self.ctx.diagnostics.errors.items,
            .metadata = metadata,
        };
    }
};

pub const CompileOutput = struct {
    js: []const u8,
    css: ?[]const u8,
    source_map: ?[]const u8,
    warnings: []context.Diagnostic,
    errors: []context.Diagnostic,
    metadata: Metadata,

    pub const Metadata = struct {
        has_script: bool = false,
        has_style: bool = false,
        uses_slots: bool = false,
        uses_props_rune: bool = false,
        uses_state_rune: bool = false,
        uses_derived_rune: bool = false,
        uses_effect_rune: bool = false,
        is_custom_element: bool = false,
    };
};

pub fn compile(allocator: std.mem.Allocator, source: []const u8, options: context.CompilerOptions) !CompileOutput {
    var pipeline = try Pipeline.init(allocator, source, options);
    defer pipeline.deinit();
    return try pipeline.run();
}
