const std = @import("std");
const ast = @import("../ast/nodes.zig");
const context = @import("../pipeline/context.zig");
const dom = @import("templates/dom.zig");
const ssr = @import("templates/ssr.zig");

pub const EmitError = error{
    EmitFailed,
    InvalidNode,
    OutOfMemory,
};

pub const EmitResult = struct {
    js: []const u8,
    css: ?[]const u8,
    source_map: ?[]const u8,
};

pub const Emitter = struct {
    allocator: std.mem.Allocator,
    root: *ast.Node,
    options: context.CompilerOptions,
    dom_template: dom.DomTemplate,
    ssr_template: ssr.SsrTemplate,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, root: *ast.Node, options: context.CompilerOptions) !Self {
        return Self{
            .allocator = allocator,
            .root = root,
            .options = options,
            .dom_template = dom.DomTemplate.init(allocator),
            .ssr_template = ssr.SsrTemplate.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.dom_template.deinit();
        self.ssr_template.deinit();
    }

    pub fn emit(self: *Self) !EmitResult {
        const js = switch (self.options.generate) {
            .dom, .hydrate => try self.dom_template.generate(self.root),
            .ssr => try self.ssr_template.generate(self.root),
        };

        const css = self.emitCss();

        return EmitResult{
            .js = js,
            .css = css,
            .source_map = null,
        };
    }

    fn emitCss(self: *Self) ?[]const u8 {
        if (self.root.node_type != .root) return null;

        const root = self.root.data.root;
        if (root.css == null) return null;

        const style = root.css.?.data.style;
        if (style.content.len == 0) return null;
        return style.content;
    }

    fn generateSourceMap(self: *Self) !?[]const u8 {
        _ = self;
        return null;
    }
};

pub const SourceMapGenerator = struct {
    allocator: std.mem.Allocator,
    mappings: std.ArrayList(Mapping),
    sources: std.ArrayList([]const u8),
    names: std.ArrayList([]const u8),

    const Mapping = struct {
        generated_line: u32,
        generated_column: u32,
        source_index: u32,
        source_line: u32,
        source_column: u32,
        name_index: ?u32,
    };

    pub fn init(allocator: std.mem.Allocator) SourceMapGenerator {
        return .{
            .allocator = allocator,
            .mappings = std.ArrayList(Mapping).init(allocator),
            .sources = std.ArrayList([]const u8).init(allocator),
            .names = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *SourceMapGenerator) void {
        self.mappings.deinit();
        self.sources.deinit();
        self.names.deinit();
    }

    pub fn addSource(self: *SourceMapGenerator, source: []const u8) !u32 {
        try self.sources.append(source);
        return @intCast(self.sources.items.len - 1);
    }

    pub fn addMapping(
        self: *SourceMapGenerator,
        generated_line: u32,
        generated_column: u32,
        source_index: u32,
        source_line: u32,
        source_column: u32,
    ) !void {
        try self.mappings.append(.{
            .generated_line = generated_line,
            .generated_column = generated_column,
            .source_index = source_index,
            .source_line = source_line,
            .source_column = source_column,
            .name_index = null,
        });
    }

    pub fn generate(self: *SourceMapGenerator) ![]const u8 {
        _ = self;
        return "{}";
    }
};
