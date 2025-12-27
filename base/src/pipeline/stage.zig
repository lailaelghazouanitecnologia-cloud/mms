const std = @import("std");
const context = @import("context.zig");

pub const StageError = error{
    StageSkipped,
    StageFailed,
    OutOfMemory,
};

pub fn Stage(comptime InputType: type, comptime OutputType: type) type {
    return struct {
        const Self = @This();

        name: []const u8,
        process_fn: *const fn (*context.CompilerContext, InputType) StageError!OutputType,
        enabled: bool = true,

        pub fn process(self: *const Self, ctx: *context.CompilerContext, input: InputType) StageError!OutputType {
            if (!self.enabled) {
                return StageError.StageSkipped;
            }
            return self.process_fn(ctx, input);
        }

        pub fn enable(self: *Self) void {
            self.enabled = true;
        }

        pub fn disable(self: *Self) void {
            self.enabled = false;
        }
    };
}

pub const StageResult = union(enum) {
    success: void,
    skipped: void,
    failed: []const u8,
};

pub fn StageChain(comptime stages: anytype) type {
    return struct {
        const Self = @This();

        pub fn execute(ctx: *context.CompilerContext, initial_input: anytype) !@TypeOf(getLastOutput(stages)) {
            var current = initial_input;
            inline for (stages) |stage| {
                current = try stage.process(ctx, current);
            }
            return current;
        }

        fn getLastOutput(comptime s: anytype) type {
            const last_stage = s[s.len - 1];
            return @typeInfo(@TypeOf(last_stage.process_fn)).Pointer.child.ReturnType;
        }
    };
}
