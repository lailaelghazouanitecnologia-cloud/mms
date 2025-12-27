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
    scope_id: ?[]const u8,
};

pub const Emitter = struct {
    allocator: std.mem.Allocator,
    root: *ast.Node,
    options: context.CompilerOptions,
    dom_template: dom.DomTemplate,
    ssr_template: ssr.SsrTemplate,
    scope_id: [8]u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, root: *ast.Node, options: context.CompilerOptions) !Self {
        var emitter = Self{
            .allocator = allocator,
            .root = root,
            .options = options,
            .dom_template = dom.DomTemplate.init(allocator),
            .ssr_template = ssr.SsrTemplate.init(allocator),
            .scope_id = undefined,
        };
        emitter.generateScopeId();
        return emitter;
    }

    pub fn deinit(self: *Self) void {
        self.dom_template.deinit();
        self.ssr_template.deinit();
    }

    fn generateScopeId(self: *Self) void {
        var hash: u32 = 5381;
        if (self.root.node_type == .root) {
            if (self.root.data.root.css) |css_node| {
                const content = css_node.data.style.content;
                for (content) |c| {
                    hash = ((hash << 5) +% hash) +% c;
                }
            }
        }
        const chars = "abcdefghijklmnopqrstuvwxyz";
        var i: usize = 0;
        var h = hash;
        while (i < 7) : (i += 1) {
            self.scope_id[i] = chars[h % 26];
            h = h / 26;
        }
        self.scope_id[7] = 0;
    }

    pub fn emit(self: *Self) !EmitResult {
        self.dom_template.scope_id = &self.scope_id;
        self.ssr_template.scope_id = &self.scope_id;
        self.dom_template.hydrate = (self.options.generate == .hydrate);

        const js = switch (self.options.generate) {
            .dom, .hydrate => try self.dom_template.generate(self.root),
            .ssr => try self.ssr_template.generate(self.root),
        };

        const css = try self.emitScopedCss();

        return EmitResult{
            .js = js,
            .css = css,
            .source_map = null,
            .scope_id = &self.scope_id,
        };
    }

    fn emitScopedCss(self: *Self) !?[]const u8 {
        if (self.root.node_type != .root) return null;

        const root = self.root.data.root;
        if (root.css == null) return null;

        const style = root.css.?.data.style;
        if (style.content.len == 0) return null;

        var result = std.ArrayList(u8).init(self.allocator);
        var i: usize = 0;
        const content = style.content;

        while (i < content.len) {
            if (content[i] == '{') {
                try result.appendSlice(".svelte-");
                try result.appendSlice(self.scope_id[0..7]);
                try result.append('{');
                i += 1;
            } else if (content[i] == ',' and i + 1 < content.len and content[i + 1] != '\n') {
                try result.append(',');
                i += 1;
                while (i < content.len and (content[i] == ' ' or content[i] == '\n')) {
                    try result.append(content[i]);
                    i += 1;
                }
            } else {
                try result.append(content[i]);
                i += 1;
            }
        }

        return try result.toOwnedSlice();
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
