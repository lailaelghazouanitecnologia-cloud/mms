const std = @import("std");

pub const ast = @import("ast/nodes.zig");
pub const lexer = @import("lexer/lexer.zig");
pub const parser = @import("parser/parser.zig");
pub const analyzer = @import("analyzer/analyzer.zig");
pub const codegen = @import("codegen/codegen.zig");

pub const CompileOptions = struct {
    generate: codegen.GenerateMode = .dom,
    dev: bool = false,
    hmr: bool = false,
    source_maps: bool = false,
    preserve_comments: bool = false,
    preserve_whitespace: bool = false,
    css_hash: ?[]const u8 = null,
    filename: ?[]const u8 = null,
};

pub const CompileResult = codegen.CompileResult;

pub fn compile(allocator: std.mem.Allocator, source: []const u8, options: CompileOptions) !CompileResult {
    var lex = lexer.Lexer.init(allocator, source);
    defer lex.deinit();
    const tokens = try lex.tokenize();

    var parse = parser.Parser.init(allocator, tokens);
    defer parse.deinit();
    const ast_root = try parse.parse();

    var analyze = try analyzer.Analyzer.init(allocator, ast_root, source);
    const analysis = try analyze.analyze();

    var gen = codegen.CodeGenerator.init(allocator, analysis, .{
        .dev = options.dev,
        .hmr = options.hmr,
        .generate = options.generate,
        .source_maps = options.source_maps,
        .preserve_comments = options.preserve_comments,
        .preserve_whitespace = options.preserve_whitespace,
        .css_hash = options.css_hash,
        .filename = options.filename,
    });
    defer gen.deinit();

    return try gen.generate();
}

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !*ast.Node {
    var lex = lexer.Lexer.init(allocator, source);
    defer lex.deinit();
    const tokens = try lex.tokenize();

    var p = parser.Parser.init(allocator, tokens);
    defer p.deinit();
    return try p.parse();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
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
    } else if (std.mem.eql(u8, command, "version") or std.mem.eql(u8, command, "-v")) {
        std.debug.print("mms 0.3.0\n", .{});
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "-h")) {
        try printUsage();
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        try printUsage();
    }
}

fn printUsage() !void {
    const usage =
        \\MMS Compiler v0.3
        \\
        \\Usage: mms <command> [options]
        \\
        \\Commands:
        \\  compile, c <file>    Compile a component file
        \\  parse <file>         Parse a file and print AST
        \\  version, -v          Print version
        \\  help, -h             Print this help
        \\
        \\Compile Options:
        \\  --dev                Enable development mode
        \\  --ssr                Generate server-side rendering code
        \\  --sourcemap          Generate source maps
        \\  -o, --output <file>  Output file (default: stdout)
        \\
    ;
    std.debug.print("{s}", .{usage});
}

const CliOptions = struct {
    dev: bool = false,
    ssr: bool = false,
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

fn compileFile(allocator: std.mem.Allocator, filename: []const u8, cli_options: CliOptions) !void {
    const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
        std.debug.print("Error opening file '{s}': {}\n", .{ filename, err });
        return;
    };
    defer file.close();

    const source = file.readToEndAlloc(allocator, 1024 * 1024 * 10) catch |err| {
        std.debug.print("Error reading file: {}\n", .{err});
        return;
    };
    defer allocator.free(source);

    const options = CompileOptions{
        .dev = cli_options.dev,
        .generate = if (cli_options.ssr) .ssr else .dom,
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
    } else {
        const stdout = std.io.getStdOut().writer();
        stdout.writeAll(result.js) catch {};
    }
}

fn parseFile(allocator: std.mem.Allocator, filename: []const u8) !void {
    const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
        std.debug.print("Error opening file '{s}': {}\n", .{ filename, err });
        return;
    };
    defer file.close();

    const source = file.readToEndAlloc(allocator, 1024 * 1024 * 10) catch |err| {
        std.debug.print("Error reading file: {}\n", .{err});
        return;
    };
    defer allocator.free(source);

    const ast_root = parse(allocator, source) catch |err| {
        std.debug.print("Parse error: {}\n", .{err});
        return;
    };

    std.debug.print("AST Root: {}\n", .{ast_root.node_type});
    std.debug.print("Parse successful!\n", .{});
}
