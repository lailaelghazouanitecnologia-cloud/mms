const std = @import("std");

pub const ast = @import("ast/nodes.zig");
pub const visitor = @import("ast/visitor.zig");
pub const builder = @import("ast/builder.zig");

pub const lexer = @import("lexer/lexer.zig");
pub const parser = @import("parser/parser.zig");
pub const analyzer = @import("analyzer/analyzer.zig");
pub const validator = @import("validators/validator.zig");
pub const transformer = @import("transformers/transformer.zig");
pub const emitter = @import("codegen/emitter.zig");

pub const pipeline = @import("pipeline/pipeline.zig");
pub const context = @import("pipeline/context.zig");

pub const utils = @import("utils/utils.zig");

pub const CompilerOptions = context.CompilerOptions;
pub const CompileOutput = pipeline.CompileOutput;
pub const GenerateMode = context.GenerateMode;

pub fn compile(allocator: std.mem.Allocator, source: []const u8, options: CompilerOptions) !CompileOutput {
    return pipeline.compile(allocator, source, options);
}

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !*ast.Node {
    var l = lexer.Lexer.init(allocator, source);
    const tokens = try l.tokenize();

    var p = parser.Parser.init(allocator, tokens);
    return try p.parse();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "compile") or std.mem.eql(u8, command, "c")) {
        if (args.len < 3) {
            std.debug.print("Error: No input file specified\n", .{});
            return;
        }
        const input_file = args[2];
        try compileFile(allocator, input_file, parseArgs(args[3..]));
    } else if (std.mem.eql(u8, command, "parse")) {
        if (args.len < 3) {
            std.debug.print("Error: No input file specified\n", .{});
            return;
        }
        const input_file = args[2];
        try parseFile(allocator, input_file);
    } else if (std.mem.eql(u8, command, "validate")) {
        if (args.len < 3) {
            std.debug.print("Error: No input file specified\n", .{});
            return;
        }
        const input_file = args[2];
        try validateFile(allocator, input_file);
    } else if (std.mem.eql(u8, command, "version") or std.mem.eql(u8, command, "-v")) {
        std.debug.print("mms 0.3.0\n", .{});
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "-h")) {
        printUsage();
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        printUsage();
    }
}

fn printUsage() void {
    const usage =
        \\MMS Compiler v0.3
        \\
        \\Usage: mms <command> [options]
        \\
        \\Commands:
        \\  compile, c <file>    Compile a component file
        \\  parse <file>         Parse a file and print AST
        \\  validate <file>      Validate a component file
        \\  version, -v          Print version
        \\  help, -h             Print this help
        \\
        \\Compile Options:
        \\  --dev                Enable development mode
        \\  --ssr                Generate server-side rendering code
        \\  --hydrate            Generate hydration code
        \\  --sourcemap          Generate source maps
        \\  -o, --output <file>  Output file (default: stdout)
        \\
    ;
    std.debug.print("{s}", .{usage});
}

const CliOptions = struct {
    dev: bool = false,
    ssr: bool = false,
    hydrate: bool = false,
    sourcemap: bool = false,
    output: ?[]const u8 = null,
};

fn parseArgs(args: []const []const u8) CliOptions {
    var options = CliOptions{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--dev")) {
            options.dev = true;
        } else if (std.mem.eql(u8, arg, "--ssr")) {
            options.ssr = true;
        } else if (std.mem.eql(u8, arg, "--hydrate")) {
            options.hydrate = true;
        } else if (std.mem.eql(u8, arg, "--sourcemap")) {
            options.sourcemap = true;
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            if (i + 1 < args.len) {
                options.output = args[i + 1];
                i += 1;
            }
        }
    }
    return options;
}

fn compileFile(base_allocator: std.mem.Allocator, filename: []const u8, cli_options: CliOptions) !void {
    var arena = std.heap.ArenaAllocator.init(base_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
        std.debug.print("Error opening file '{s}': {}\n", .{ filename, err });
        return;
    };
    defer file.close();

    const source = file.readToEndAlloc(allocator, 1024 * 1024 * 10) catch |err| {
        std.debug.print("Error reading file: {}\n", .{err});
        return;
    };

    const gen_mode: GenerateMode = if (cli_options.ssr) .ssr else if (cli_options.hydrate) .hydrate else .dom;
    const options = CompilerOptions{
        .dev = cli_options.dev,
        .generate = gen_mode,
        .source_maps = cli_options.sourcemap,
        .filename = filename,
    };

    const result = compile(allocator, source, options) catch |err| {
        std.debug.print("Compilation error: {}\n", .{err});
        return;
    };

    for (result.warnings) |warning| {
        std.debug.print("Warning [{s}]: {s}\n", .{ warning.code, warning.message });
    }

    for (result.errors) |err| {
        std.debug.print("Error [{s}]: {s}\n", .{ err.code, err.message });
    }

    if (cli_options.output) |output_file| {
        const out = std.fs.cwd().createFile(output_file, .{}) catch |err| {
            std.debug.print("Error creating output file: {}\n", .{err});
            return;
        };
        defer out.close();
        out.writeAll(result.js) catch |err| {
            std.debug.print("Error writing output: {}\n", .{err});
            return;
        };
        std.debug.print("Compiled to {s}\n", .{output_file});

        if (result.css) |css| {
            const css_file = std.fmt.allocPrint(allocator, "{s}.css", .{output_file}) catch return;
            const css_out = std.fs.cwd().createFile(css_file, .{}) catch |err| {
                std.debug.print("Error creating CSS file: {}\n", .{err});
                return;
            };
            defer css_out.close();
            css_out.writeAll(css) catch {};
            std.debug.print("CSS written to {s}\n", .{css_file});
        }
    } else {
        const stdout = std.io.getStdOut().writer();
        stdout.writeAll(result.js) catch {};
        if (result.css) |css| {
            stdout.writeAll("\n/* --- CSS --- */\n") catch {};
            stdout.writeAll(css) catch {};
        }
    }
}

fn parseFile(base_allocator: std.mem.Allocator, filename: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(base_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
        std.debug.print("Error opening file '{s}': {}\n", .{ filename, err });
        return;
    };
    defer file.close();

    const source = file.readToEndAlloc(allocator, 1024 * 1024 * 10) catch |err| {
        std.debug.print("Error reading file: {}\n", .{err});
        return;
    };

    const ast_root = parse(allocator, source) catch |err| {
        std.debug.print("Parse error: {}\n", .{err});
        return;
    };

    std.debug.print("AST Root: {}\n", .{ast_root.node_type});
    std.debug.print("Parse successful!\n", .{});
}

fn validateFile(base_allocator: std.mem.Allocator, filename: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(base_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
        std.debug.print("Error opening file '{s}': {}\n", .{ filename, err });
        return;
    };
    defer file.close();

    const source = file.readToEndAlloc(allocator, 1024 * 1024 * 10) catch |err| {
        std.debug.print("Error reading file: {}\n", .{err});
        return;
    };

    const ast_root = parse(allocator, source) catch |err| {
        std.debug.print("Parse error: {}\n", .{err});
        return;
    };

    var v = try validator.Validator.init(allocator, ast_root, source);
    defer v.deinit();

    const result = try v.validate();

    for (result.warnings) |warning| {
        std.debug.print("Warning [{s}]: {s}\n", .{ warning.code, warning.message });
    }

    for (result.errors) |err| {
        std.debug.print("Error [{s}]: {s}\n", .{ err.code, err.message });
    }

    if (result.valid) {
        std.debug.print("Validation passed!\n", .{});
    } else {
        std.debug.print("Validation failed with {} errors.\n", .{result.errors.len});
    }
}

test {
    _ = lexer;
    _ = parser;
    _ = ast;
    _ = analyzer;
    _ = validator;
    _ = transformer;
    _ = emitter;
    _ = pipeline;
    _ = context;
    _ = utils;
    _ = visitor;
    _ = builder;
}
