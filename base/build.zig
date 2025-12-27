const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "mms",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the compiler");
    run_step.dependOn(&run_cmd.step);

    const lib = b.addStaticLibrary(.{
        .name = "mms",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(lib);

    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const parser_tests = b.addTest(.{
        .root_source_file = b.path("src/parser/parser.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lexer_tests = b.addTest(.{
        .root_source_file = b.path("src/lexer/lexer.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);
    const run_parser_tests = b.addRunArtifact(parser_tests);
    const run_lexer_tests = b.addRunArtifact(lexer_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_main_tests.step);
    test_step.dependOn(&run_parser_tests.step);
    test_step.dependOn(&run_lexer_tests.step);

    const check = b.addExecutable(.{
        .name = "mms-check",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const check_step = b.step("check", "Check for compilation errors");
    check_step.dependOn(&check.step);
}
