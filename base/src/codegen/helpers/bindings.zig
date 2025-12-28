const std = @import("std");

/// Binding type categories for code generation
pub const BindingCategory = enum {
    standard,
    group,
    this_ref,
    media_readonly,
    media_writable,
    dimension,
};

/// Determines the binding category for proper code generation
pub fn getBindingCategory(name: []const u8) BindingCategory {
    if (std.mem.eql(u8, name, "group")) return .group;
    if (std.mem.eql(u8, name, "this")) return .this_ref;
    if (isReadonlyMediaBinding(name)) return .media_readonly;
    if (isMediaBinding(name)) return .media_writable;
    if (isDimensionBinding(name)) return .dimension;
    return .standard;
}

/// Media element bindings (video/audio)
const media_bindings = [_][]const u8{
    "currentTime",
    "duration",
    "paused",
    "volume",
    "muted",
    "playbackRate",
    "seeking",
    "ended",
    "buffered",
    "played",
    "seekable",
    "readyState",
    "videoWidth",
    "videoHeight",
};

/// Read-only media bindings (cannot be set by user)
const readonly_media_bindings = [_][]const u8{
    "duration",
    "seeking",
    "ended",
    "buffered",
    "played",
    "seekable",
    "readyState",
    "videoWidth",
    "videoHeight",
};

/// Dimension bindings for element measurements
const dimension_bindings = [_][]const u8{
    "clientWidth",
    "clientHeight",
    "offsetWidth",
    "offsetHeight",
    "contentRect",
    "contentBoxSize",
    "borderBoxSize",
    "devicePixelContentBoxSize",
};

pub fn isMediaBinding(name: []const u8) bool {
    for (media_bindings) |binding| {
        if (std.mem.eql(u8, name, binding)) return true;
    }
    return false;
}

pub fn isReadonlyMediaBinding(name: []const u8) bool {
    for (readonly_media_bindings) |binding| {
        if (std.mem.eql(u8, name, binding)) return true;
    }
    return false;
}

pub fn isDimensionBinding(name: []const u8) bool {
    for (dimension_bindings) |binding| {
        if (std.mem.eql(u8, name, binding)) return true;
    }
    return false;
}

/// Runtime function names for different binding types
pub const RuntimeBindings = struct {
    pub const group = "$.bind_group";
    pub const this_ref = "$.bind_this";
    pub const media = "$.bind_media";
    pub const media_readonly = "$.bind_media_readonly";
    pub const dimension = "$.bind_dimension";

    pub fn getStandardBinding(name: []const u8) []const u8 {
        // Returns the prefix for standard bindings like $.bind_value, $.bind_checked
        _ = name;
        return "$.bind_";
    }
};

test "binding category detection" {
    const testing = std.testing;

    try testing.expectEqual(BindingCategory.group, getBindingCategory("group"));
    try testing.expectEqual(BindingCategory.this_ref, getBindingCategory("this"));
    try testing.expectEqual(BindingCategory.media_writable, getBindingCategory("currentTime"));
    try testing.expectEqual(BindingCategory.media_readonly, getBindingCategory("duration"));
    try testing.expectEqual(BindingCategory.dimension, getBindingCategory("clientWidth"));
    try testing.expectEqual(BindingCategory.standard, getBindingCategory("value"));
}
