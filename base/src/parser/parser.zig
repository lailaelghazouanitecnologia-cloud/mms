const std = @import("std");
const ast = @import("../ast/nodes.zig");
const Lexer = @import("../lexer/lexer.zig").Lexer;

pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEof,
    InvalidSyntax,
    UnclosedTag,
    UnclosedBlock,
    InvalidExpression,
    OutOfMemory,
};

pub const Parser = struct {
    tokens: []ast.Token,
    current: usize,
    allocator: std.mem.Allocator,
    errors: std.ArrayList(ParserError),

    const Self = @This();

    pub const ParserError = struct {
        message: []const u8,
        span: ast.Span,
    };

    pub fn init(allocator: std.mem.Allocator, tokens: []ast.Token) Self {
        return Self{
            .tokens = tokens,
            .current = 0,
            .allocator = allocator,
            .errors = std.ArrayList(ParserError).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.errors.deinit();
    }

    pub fn parse(self: *Self) ParseError!*ast.Node {
        const fragment = try self.parseFragment();

        var instance: ?*ast.Node = null;
        var module: ?*ast.Node = null;
        var css: ?*ast.Node = null;

        var filtered_children = std.ArrayList(*ast.Node).init(self.allocator);

        for (fragment.data.fragment.children.items) |child| {
            if (child.node_type == .element) {
                const name = child.data.element.name;

                if (std.mem.eql(u8, name, "script")) {
                    const script_content = self.extractTextContent(child);
                    const is_module = self.hasModuleAttribute(child);

                    if (is_module) {
                        const mod_data = ast.NodeData{
                            .module_script = .{ .content = script_content },
                        };
                        module = try ast.createNode(self.allocator, .module_script, child.span, mod_data);
                    } else {
                        const script_data = ast.NodeData{
                            .script = .{
                                .content = script_content,
                                .context = .default,
                            },
                        };
                        instance = try ast.createNode(self.allocator, .script, child.span, script_data);
                    }
                } else if (std.mem.eql(u8, name, "style")) {
                    const style_content = self.extractTextContent(child);
                    const style_data = ast.NodeData{
                        .style = .{
                            .content = style_content,
                            .attributes = child.data.element.attributes,
                        },
                    };
                    css = try ast.createNode(self.allocator, .style, child.span, style_data);
                } else {
                    try filtered_children.append(child);
                }
            } else {
                try filtered_children.append(child);
            }
        }

        const new_frag_data = ast.NodeData{
            .fragment = .{
                .children = filtered_children,
                .transparent = false,
            },
        };
        const new_fragment = try ast.createNode(self.allocator, .fragment, ast.defaultSpan(), new_frag_data);

        const root_data = ast.NodeData{
            .root = .{
                .fragment = new_fragment,
                .instance = instance,
                .module = module,
                .options = null,
                .css = css,
                .metadata = .{
                    .ts = false,
                    .runes = true,
                },
            },
        };

        return ast.createNode(
            self.allocator,
            .root,
            ast.defaultSpan(),
            root_data,
        );
    }

    fn extractTextContent(self: *Self, element: *ast.Node) []const u8 {
        _ = self;
        for (element.data.element.children.items) |child| {
            if (child.node_type == .text_node) {
                return child.data.text_node.data;
            }
        }
        return "";
    }

    fn hasModuleAttribute(self: *Self, element: *ast.Node) bool {
        _ = self;
        for (element.data.element.attributes.items) |attr| {
            if (attr.node_type == .attribute) {
                if (std.mem.eql(u8, attr.data.attribute.name, "context")) {
                    switch (attr.data.attribute.value) {
                        .text => |text| {
                            if (std.mem.eql(u8, text, "module")) return true;
                        },
                        else => {},
                    }
                }
            }
        }
        return false;
    }

    fn parseFragment(self: *Self) ParseError!*ast.Node {
        var children = std.ArrayList(*ast.Node).init(self.allocator);

        while (!self.isAtEnd()) {
            const token = self.peek();

            switch (token.type) {
                .open_tag => {
                    const element = try self.parseElement();
                    try children.append(element);
                },
                .close_tag => {
                    break;
                },
                .text => {
                    const text = try self.parseText();
                    try children.append(text);
                },
                .mustache_open => {
                    const expr = try self.parseExpressionTag();
                    try children.append(expr);
                },
                .kw_if => {
                    const if_block = try self.parseIfBlock();
                    try children.append(if_block);
                },
                .kw_each => {
                    const each_block = try self.parseEachBlock();
                    try children.append(each_block);
                },
                .kw_await => {
                    const await_block = try self.parseAwaitBlock();
                    try children.append(await_block);
                },
                .kw_key => {
                    const key_block = try self.parseKeyBlock();
                    try children.append(key_block);
                },
                .kw_snippet => {
                    const snippet = try self.parseSnippetBlock();
                    try children.append(snippet);
                },
                .kw_html => {
                    const html = try self.parseHtmlTag();
                    try children.append(html);
                },
                .kw_render => {
                    const render = try self.parseRenderTag();
                    try children.append(render);
                },
                .kw_const => {
                    const const_tag = try self.parseConstTag();
                    try children.append(const_tag);
                },
                .kw_debug => {
                    const debug = try self.parseDebugTag();
                    try children.append(debug);
                },
                .comment => {
                    const comment = try self.parseComment();
                    try children.append(comment);
                },
                .whitespace, .newline => {
                    _ = self.advance();
                },
                .kw_else, .kw_then, .kw_catch, .block_close => break,
                .eof => break,
                else => {
                    _ = self.advance();
                },
            }
        }

        const fragment_data = ast.NodeData{
            .fragment = .{
                .children = children,
                .transparent = false,
            },
        };

        return ast.createNode(
            self.allocator,
            .fragment,
            ast.defaultSpan(),
            fragment_data,
        );
    }

    fn parseElement(self: *Self) ParseError!*ast.Node {
        const start_token = self.advance();
        _ = start_token;

        const name_token = self.advance();
        if (name_token.type != .identifier) {
            return ParseError.UnexpectedToken;
        }

        const name = name_token.value;
        const is_component = isUpperCase(name[0]);
        const is_svelte_element = std.mem.startsWith(u8, name, "svelte:");
        const is_slot = std.mem.eql(u8, name, "slot");

        var attributes = std.ArrayList(*ast.Node).init(self.allocator);
        var children = std.ArrayList(*ast.Node).init(self.allocator);

        while (!self.isAtEnd()) {
            self.skipWhitespace();
            const token = self.peek();

            if (token.type == .self_close_tag) {
                _ = self.advance();
                break;
            }

            if (token.type == .rbracket) {
                _ = self.advance();
                children = (try self.parseFragment()).data.fragment.children;
                try self.expectClosingTag(name);
                break;
            }

            if (token.type == .identifier or
                token.type == .directive_on or
                token.type == .directive_bind or
                token.type == .directive_class or
                token.type == .directive_style or
                token.type == .directive_use or
                token.type == .directive_transition or
                token.type == .directive_animate or
                token.type == .directive_in or
                token.type == .directive_out or
                token.type == .directive_let)
            {
                const attr = try self.parseAttribute();
                try attributes.append(attr);
            } else if (token.type == .mustache_open) {
                const spread = try self.parseSpreadAttribute();
                try attributes.append(spread);
            } else {
                _ = self.advance();
            }
        }

        if (is_svelte_element) {
            return try self.createSvelteElement(name, attributes, children);
        } else if (is_slot) {
            var slot_name: []const u8 = "default";
            for (attributes.items) |attr| {
                if (attr.node_type == .attribute) {
                    const a = attr.data.attribute;
                    if (std.mem.eql(u8, a.name, "name")) {
                        switch (a.value) {
                            .text => |t| slot_name = t,
                            else => {},
                        }
                    }
                }
            }
            const slot_data = ast.NodeData{
                .slot = .{
                    .name = slot_name,
                    .attributes = attributes,
                    .children = children,
                },
            };
            return ast.createNode(
                self.allocator,
                .slot,
                ast.defaultSpan(),
                slot_data,
            );
        } else if (is_component) {
            const component_data = ast.NodeData{
                .component = .{
                    .name = name,
                    .attributes = attributes,
                    .children = children,
                },
            };
            return ast.createNode(
                self.allocator,
                .component,
                ast.defaultSpan(),
                component_data,
            );
        } else {
            const element_data = ast.NodeData{
                .element = .{
                    .name = name,
                    .attributes = attributes,
                    .children = children,
                    .self_closing = children.items.len == 0,
                },
            };
            return ast.createNode(
                self.allocator,
                .element,
                ast.defaultSpan(),
                element_data,
            );
        }
    }

    fn createSvelteElement(
        self: *Self,
        name: []const u8,
        attributes: std.ArrayList(*ast.Node),
        children: std.ArrayList(*ast.Node),
    ) ParseError!*ast.Node {
        if (std.mem.eql(u8, name, "svelte:head")) {
            const data = ast.NodeData{
                .svelte_head = .{
                    .children = children,
                },
            };
            return ast.createNode(self.allocator, .svelte_head, ast.defaultSpan(), data);
        } else if (std.mem.eql(u8, name, "svelte:body")) {
            const data = ast.NodeData{
                .svelte_body = .{
                    .attributes = attributes,
                },
            };
            return ast.createNode(self.allocator, .svelte_body, ast.defaultSpan(), data);
        } else if (std.mem.eql(u8, name, "svelte:window")) {
            const data = ast.NodeData{
                .svelte_window = .{
                    .attributes = attributes,
                },
            };
            return ast.createNode(self.allocator, .svelte_window, ast.defaultSpan(), data);
        } else if (std.mem.eql(u8, name, "svelte:document")) {
            const data = ast.NodeData{
                .svelte_document = .{
                    .attributes = attributes,
                },
            };
            return ast.createNode(self.allocator, .svelte_document, ast.defaultSpan(), data);
        } else if (std.mem.eql(u8, name, "svelte:options")) {
            const data = ast.NodeData{
                .svelte_options = .{
                    .attributes = attributes,
                },
            };
            return ast.createNode(self.allocator, .svelte_options, ast.defaultSpan(), data);
        } else if (std.mem.eql(u8, name, "svelte:fragment")) {
            const data = ast.NodeData{
                .svelte_fragment = .{
                    .attributes = attributes,
                    .children = children,
                },
            };
            return ast.createNode(self.allocator, .svelte_fragment, ast.defaultSpan(), data);
        } else if (std.mem.eql(u8, name, "svelte:self")) {
            const data = ast.NodeData{
                .svelte_self = .{
                    .attributes = attributes,
                    .children = children,
                },
            };
            return ast.createNode(self.allocator, .svelte_self, ast.defaultSpan(), data);
        } else {
            const data = ast.NodeData{
                .element = .{
                    .name = name,
                    .attributes = attributes,
                    .children = children,
                    .self_closing = false,
                },
            };
            return ast.createNode(self.allocator, .element, ast.defaultSpan(), data);
        }
    }

    fn parseAttribute(self: *Self) ParseError!*ast.Node {
        const name_token = self.advance();

        switch (name_token.type) {
            .directive_on,
            .directive_bind,
            .directive_class,
            .directive_style,
            .directive_use,
            .directive_transition,
            .directive_animate,
            .directive_in,
            .directive_out,
            .directive_let,
            => {
                return try self.parseDirective(name_token);
            },
            else => {},
        }

        const name = name_token.value;
        var value: ast.AttributeValue = .{ .boolean = true };

        if (self.check(.assign)) {
            _ = self.advance();

            self.skipWhitespace();

            if (self.check(.string)) {
                const str_token = self.advance();
                value = .{ .text = str_token.value };
            } else if (self.check(.mustache_open)) {
                _ = self.advance();
                const expr = try self.parseExpression();
                value = .{ .expression = expr };
                if (self.check(.mustache_close)) {
                    _ = self.advance();
                }
            }
        }

        const attr_data = ast.NodeData{
            .attribute = .{
                .name = name,
                .value = value,
            },
        };

        return ast.createNode(
            self.allocator,
            .attribute,
            ast.defaultSpan(),
            attr_data,
        );
    }

    fn parseDirective(self: *Self, token: ast.Token) ParseError!*ast.Node {
        const directive_type: ast.DirectiveType = switch (token.type) {
            .directive_on => .on,
            .directive_bind => .bind,
            .directive_class => .class_directive,
            .directive_style => .style_directive,
            .directive_use => .use,
            .directive_transition => .transition,
            .directive_animate => .animate,
            .directive_in => .in_directive,
            .directive_out => .out_directive,
            .directive_let => .let_directive,
            else => unreachable,
        };

        var name: []const u8 = "";
        var modifiers = std.ArrayList([]const u8).init(self.allocator);

        if (self.check(.identifier)) {
            name = self.advance().value;

            while (self.check(.pipe)) {
                _ = self.advance();
                if (self.check(.identifier)) {
                    try modifiers.append(self.advance().value);
                }
            }
        }

        var expression: ?*ast.Node = null;

        if (self.check(.assign)) {
            _ = self.advance();
            self.skipWhitespace();

            if (self.check(.mustache_open)) {
                _ = self.advance();
                expression = try self.parseExpression();
                if (self.check(.mustache_close)) {
                    _ = self.advance();
                }
            } else if (self.check(.string)) {
                const str_token = self.advance();
                const lit_data = ast.NodeData{
                    .literal_expr = .{
                        .value = .{ .string = str_token.value },
                        .raw = str_token.value,
                    },
                };
                expression = try ast.createNode(self.allocator, .literal_expr, str_token.span, lit_data);
            }
        }

        const directive_data = ast.NodeData{
            .directive = .{
                .directive_type = directive_type,
                .name = name,
                .expression = expression,
                .modifiers = modifiers,
            },
        };

        return ast.createNode(
            self.allocator,
            .directive,
            ast.defaultSpan(),
            directive_data,
        );
    }

    fn parseSpreadAttribute(self: *Self) ParseError!*ast.Node {
        if (self.check(.mustache_open)) {
            _ = self.advance();
        }

        if (self.check(.spread)) {
            _ = self.advance();
        }

        self.skipWhitespace();
        const expr = try self.parseExpression();

        if (self.check(.mustache_close)) {
            _ = self.advance();
        }

        const spread_data = ast.NodeData{
            .spread_attribute = .{
                .expression = expr,
            },
        };

        return ast.createNode(
            self.allocator,
            .spread_attribute,
            ast.defaultSpan(),
            spread_data,
        );
    }

    fn parseIfBlock(self: *Self) ParseError!*ast.Node {
        _ = self.advance();

        self.skipWhitespace();
        const test_expr = try self.parseExpression();

        if (self.check(.mustache_close)) {
            _ = self.advance();
        }

        const consequent = try self.parseFragment();

        var alternate: ?*ast.Node = null;

        if (self.check(.kw_else)) {
            _ = self.advance();

            self.skipWhitespace();

            if (self.check(.kw_if)) {
                alternate = try self.parseIfBlock();
            } else {
                if (self.check(.mustache_close)) {
                    _ = self.advance();
                }
                alternate = try self.parseFragment();
            }
        }

        if (self.check(.block_close)) {
            _ = self.advance();
        }

        const if_data = ast.NodeData{
            .if_block = .{
                .condition = test_expr,
                .consequent = consequent,
                .alternate = alternate,
                .is_elseif = false,
            },
        };

        return ast.createNode(
            self.allocator,
            .if_block,
            ast.defaultSpan(),
            if_data,
        );
    }

    fn parseEachBlock(self: *Self) ParseError!*ast.Node {
        _ = self.advance();

        self.skipWhitespace();
        const list_expr = try self.parseExpression();

        self.skipWhitespace();
        if (self.check(.identifier)) {
            _ = self.advance();
        }

        self.skipWhitespace();
        const context = try self.parseExpression();

        var index: ?[]const u8 = null;
        var key: ?*ast.Node = null;

        if (self.check(.comma)) {
            _ = self.advance();
            self.skipWhitespace();
            if (self.check(.identifier)) {
                index = self.advance().value;
            }
        }

        if (self.check(.lparen)) {
            _ = self.advance();
            key = try self.parseExpression();
            if (self.check(.rparen)) {
                _ = self.advance();
            }
        }

        if (self.check(.mustache_close)) {
            _ = self.advance();
        }

        const body = try self.parseFragment();
        var fallback: ?*ast.Node = null;

        if (self.check(.kw_else)) {
            _ = self.advance();
            if (self.check(.mustache_close)) {
                _ = self.advance();
            }
            fallback = try self.parseFragment();
        }

        if (self.check(.block_close)) {
            _ = self.advance();
        }

        const each_data = ast.NodeData{
            .each_block = .{
                .expression = list_expr,
                .context = context,
                .index = index,
                .key = key,
                .children = body.data.fragment.children,
                .fallback = fallback,
            },
        };

        return ast.createNode(
            self.allocator,
            .each_block,
            ast.defaultSpan(),
            each_data,
        );
    }

    fn parseAwaitBlock(self: *Self) ParseError!*ast.Node {
        _ = self.advance();

        self.skipWhitespace();
        const promise_expr = try self.parseExpression();

        var value_node: ?*ast.Node = null;
        var pending_node: ?*ast.Node = null;
        var then_node: ?*ast.Node = null;
        var error_node: ?*ast.Node = null;
        var catch_node: ?*ast.Node = null;

        self.skipWhitespace();
        if (self.check(.kw_then)) {
            _ = self.advance();
            self.skipWhitespace();
            if (!self.check(.mustache_close)) {
                value_node = try self.parseExpression();
            }
        }

        if (self.check(.mustache_close)) {
            _ = self.advance();
        }

        const first_block = try self.parseFragment();

        if (self.check(.kw_then)) {
            pending_node = first_block;
            _ = self.advance();
            self.skipWhitespace();
            if (!self.check(.mustache_close)) {
                value_node = try self.parseExpression();
            }
            if (self.check(.mustache_close)) {
                _ = self.advance();
            }
            then_node = try self.parseFragment();
        } else {
            then_node = first_block;
        }

        if (self.check(.kw_catch)) {
            _ = self.advance();
            self.skipWhitespace();
            if (!self.check(.mustache_close)) {
                error_node = try self.parseExpression();
            }
            if (self.check(.mustache_close)) {
                _ = self.advance();
            }
            catch_node = try self.parseFragment();
        }

        if (self.check(.block_close)) {
            _ = self.advance();
        }

        const await_data = ast.NodeData{
            .await_block = .{
                .expression = promise_expr,
                .pending = pending_node,
                .value = value_node,
                .then_node = then_node,
                .error_node = error_node,
                .catch_node = catch_node,
            },
        };

        return ast.createNode(
            self.allocator,
            .await_block,
            ast.defaultSpan(),
            await_data,
        );
    }

    fn parseKeyBlock(self: *Self) ParseError!*ast.Node {
        _ = self.advance();

        self.skipWhitespace();
        const key_expr = try self.parseExpression();

        if (self.check(.mustache_close)) {
            _ = self.advance();
        }

        const body = try self.parseFragment();

        const key_data = ast.NodeData{
            .key_block = .{
                .expression = key_expr,
                .children = body.data.fragment.children,
            },
        };

        return ast.createNode(
            self.allocator,
            .key_block,
            ast.defaultSpan(),
            key_data,
        );
    }

    fn parseSnippetBlock(self: *Self) ParseError!*ast.Node {
        _ = self.advance();

        self.skipWhitespace();
        var name: []const u8 = "";
        if (self.check(.identifier)) {
            name = self.advance().value;
        }

        var parameters = std.ArrayList(*ast.Node).init(self.allocator);

        if (self.check(.lparen)) {
            _ = self.advance();
            while (!self.check(.rparen) and !self.isAtEnd()) {
                self.skipWhitespace();
                if (self.check(.identifier)) {
                    const param = try self.parseExpression();
                    try parameters.append(param);
                }
                if (self.check(.comma)) {
                    _ = self.advance();
                }
            }
            if (self.check(.rparen)) {
                _ = self.advance();
            }
        }

        if (self.check(.mustache_close)) {
            _ = self.advance();
        }

        const body = try self.parseFragment();

        if (self.check(.block_close)) {
            _ = self.advance();
        }

        const snippet_data = ast.NodeData{
            .snippet_block = .{
                .name = name,
                .parameters = parameters,
                .body = body,
            },
        };

        return ast.createNode(
            self.allocator,
            .snippet_block,
            ast.defaultSpan(),
            snippet_data,
        );
    }

    fn parseHtmlTag(self: *Self) ParseError!*ast.Node {
        _ = self.advance();

        self.skipWhitespace();
        const expr = try self.parseExpression();

        if (self.check(.mustache_close)) {
            _ = self.advance();
        }

        const html_data = ast.NodeData{
            .html_tag = .{
                .expression = expr,
            },
        };

        return ast.createNode(
            self.allocator,
            .html_tag,
            ast.defaultSpan(),
            html_data,
        );
    }

    fn parseRenderTag(self: *Self) ParseError!*ast.Node {
        _ = self.advance();

        self.skipWhitespace();
        const expr = try self.parseExpression();

        if (self.check(.mustache_close)) {
            _ = self.advance();
        }

        const render_data = ast.NodeData{
            .render_tag = .{
                .expression = expr,
                .argument = null,
            },
        };

        return ast.createNode(
            self.allocator,
            .render_tag,
            ast.defaultSpan(),
            render_data,
        );
    }

    fn parseConstTag(self: *Self) ParseError!*ast.Node {
        _ = self.advance();

        self.skipWhitespace();
        const decl = try self.parseExpression();

        if (self.check(.mustache_close)) {
            _ = self.advance();
        }

        const const_data = ast.NodeData{
            .const_tag = .{
                .declaration = decl,
            },
        };

        return ast.createNode(
            self.allocator,
            .const_tag,
            ast.defaultSpan(),
            const_data,
        );
    }

    fn parseDebugTag(self: *Self) ParseError!*ast.Node {
        _ = self.advance();

        var identifiers = std.ArrayList(*ast.Node).init(self.allocator);

        while (!self.check(.mustache_close) and !self.isAtEnd()) {
            self.skipWhitespace();
            if (self.check(.identifier)) {
                const id = try self.parseExpression();
                try identifiers.append(id);
            }
            if (self.check(.comma)) {
                _ = self.advance();
            }
        }

        if (self.check(.mustache_close)) {
            _ = self.advance();
        }

        const debug_data = ast.NodeData{
            .debug_tag = .{
                .identifiers = identifiers,
            },
        };

        return ast.createNode(
            self.allocator,
            .debug_tag,
            ast.defaultSpan(),
            debug_data,
        );
    }

    fn parseText(self: *Self) ParseError!*ast.Node {
        const token = self.advance();

        const text_data = ast.NodeData{
            .text_node = .{
                .data = token.value,
                .raw = token.value,
            },
        };

        return ast.createNode(
            self.allocator,
            .text_node,
            token.span,
            text_data,
        );
    }

    fn parseExpressionTag(self: *Self) ParseError!*ast.Node {
        _ = self.advance();

        const expr = try self.parseExpression();

        if (self.check(.mustache_close)) {
            _ = self.advance();
        }

        const expr_data = ast.NodeData{
            .expression_tag = .{
                .expression = expr,
            },
        };

        return ast.createNode(
            self.allocator,
            .expression_tag,
            ast.defaultSpan(),
            expr_data,
        );
    }

    fn parseComment(self: *Self) ParseError!*ast.Node {
        const token = self.advance();

        const comment_data = ast.NodeData{
            .comment_node = .{
                .data = token.value,
            },
        };

        return ast.createNode(
            self.allocator,
            .comment_node,
            token.span,
            comment_data,
        );
    }

    fn parseExpression(self: *Self) ParseError!*ast.Node {
        return self.parseConditional();
    }

    fn parseConditional(self: *Self) ParseError!*ast.Node {
        var expr = try self.parseOr();

        if (self.check(.question)) {
            _ = self.advance();
            const consequent = try self.parseExpression();

            if (self.check(.colon)) {
                _ = self.advance();
            }

            const alternate = try self.parseExpression();

            const cond_data = ast.NodeData{
                .conditional_expr = .{
                    .condition = expr,
                    .consequent = consequent,
                    .alternate = alternate,
                },
            };

            expr = try ast.createNode(
                self.allocator,
                .conditional_expr,
                ast.defaultSpan(),
                cond_data,
            );
        }

        return expr;
    }

    fn parseOr(self: *Self) ParseError!*ast.Node {
        var left = try self.parseAnd();

        self.skipWhitespace();
        while (self.check(.or_op)) {
            const op = self.advance().value;
            self.skipWhitespace();
            const right = try self.parseAnd();

            const binary_data = ast.NodeData{
                .binary_expr = .{
                    .operator = op,
                    .left = left,
                    .right = right,
                },
            };

            left = try ast.createNode(
                self.allocator,
                .binary_expr,
                ast.defaultSpan(),
                binary_data,
            );
        }

        return left;
    }

    fn parseAnd(self: *Self) ParseError!*ast.Node {
        var left = try self.parseEquality();

        self.skipWhitespace();
        while (self.check(.and_op)) {
            const op = self.advance().value;
            self.skipWhitespace();
            const right = try self.parseEquality();

            const binary_data = ast.NodeData{
                .binary_expr = .{
                    .operator = op,
                    .left = left,
                    .right = right,
                },
            };

            left = try ast.createNode(
                self.allocator,
                .binary_expr,
                ast.defaultSpan(),
                binary_data,
            );
        }

        return left;
    }

    fn parseEquality(self: *Self) ParseError!*ast.Node {
        var left = try self.parseComparison();

        self.skipWhitespace();
        while (self.check(.eq) or self.check(.neq)) {
            const op = self.advance().value;
            self.skipWhitespace();
            const right = try self.parseComparison();

            const binary_data = ast.NodeData{
                .binary_expr = .{
                    .operator = op,
                    .left = left,
                    .right = right,
                },
            };

            left = try ast.createNode(
                self.allocator,
                .binary_expr,
                ast.defaultSpan(),
                binary_data,
            );
        }

        return left;
    }

    fn parseComparison(self: *Self) ParseError!*ast.Node {
        var left = try self.parseAdditive();

        self.skipWhitespace();
        while (self.check(.lt) or self.check(.gt) or self.check(.lte) or self.check(.gte)) {
            const op = self.advance().value;
            self.skipWhitespace();
            const right = try self.parseAdditive();

            const binary_data = ast.NodeData{
                .binary_expr = .{
                    .operator = op,
                    .left = left,
                    .right = right,
                },
            };

            left = try ast.createNode(
                self.allocator,
                .binary_expr,
                ast.defaultSpan(),
                binary_data,
            );
        }

        return left;
    }

    fn parseAdditive(self: *Self) ParseError!*ast.Node {
        var left = try self.parseMultiplicative();

        self.skipWhitespace();
        while (self.check(.plus) or self.check(.minus)) {
            const op = self.advance().value;
            self.skipWhitespace();
            const right = try self.parseMultiplicative();

            const binary_data = ast.NodeData{
                .binary_expr = .{
                    .operator = op,
                    .left = left,
                    .right = right,
                },
            };

            left = try ast.createNode(
                self.allocator,
                .binary_expr,
                ast.defaultSpan(),
                binary_data,
            );
        }

        return left;
    }

    fn parseMultiplicative(self: *Self) ParseError!*ast.Node {
        var left = try self.parseUnary();

        self.skipWhitespace();
        while (self.check(.star) or self.check(.slash) or self.check(.percent)) {
            const op = self.advance().value;
            self.skipWhitespace();
            const right = try self.parseUnary();

            const binary_data = ast.NodeData{
                .binary_expr = .{
                    .operator = op,
                    .left = left,
                    .right = right,
                },
            };

            left = try ast.createNode(
                self.allocator,
                .binary_expr,
                ast.defaultSpan(),
                binary_data,
            );
        }

        return left;
    }

    fn parseUnary(self: *Self) ParseError!*ast.Node {
        if (self.check(.not) or self.check(.minus)) {
            const op = self.advance().value;
            const argument = try self.parseUnary();

            const unary_data = ast.NodeData{
                .unary_expr = .{
                    .operator = op,
                    .argument = argument,
                    .prefix = true,
                },
            };

            return ast.createNode(
                self.allocator,
                .unary_expr,
                ast.defaultSpan(),
                unary_data,
            );
        }

        return self.parsePostfix();
    }

    fn parsePostfix(self: *Self) ParseError!*ast.Node {
        var expr = try self.parsePrimary();

        while (true) {
            if (self.check(.dot)) {
                _ = self.advance();
                if (self.check(.identifier)) {
                    const property_token = self.advance();
                    const property_data = ast.NodeData{
                        .identifier_expr = .{
                            .name = property_token.value,
                        },
                    };
                    const property = try ast.createNode(
                        self.allocator,
                        .identifier_expr,
                        property_token.span,
                        property_data,
                    );

                    const member_data = ast.NodeData{
                        .member_expr = .{
                            .object = expr,
                            .property = property,
                            .computed = false,
                        },
                    };

                    expr = try ast.createNode(
                        self.allocator,
                        .member_expr,
                        ast.defaultSpan(),
                        member_data,
                    );
                }
            } else if (self.check(.lbracket)) {
                _ = self.advance();
                const index = try self.parseExpression();

                if (self.check(.rbracket)) {
                    _ = self.advance();
                }

                const member_data = ast.NodeData{
                    .member_expr = .{
                        .object = expr,
                        .property = index,
                        .computed = true,
                    },
                };

                expr = try ast.createNode(
                    self.allocator,
                    .member_expr,
                    ast.defaultSpan(),
                    member_data,
                );
            } else if (self.check(.lparen)) {
                _ = self.advance();
                var arguments = std.ArrayList(*ast.Node).init(self.allocator);

                while (!self.check(.rparen) and !self.isAtEnd()) {
                    self.skipWhitespace();
                    const arg = try self.parseExpression();
                    try arguments.append(arg);
                    self.skipWhitespace();
                    if (self.check(.comma)) {
                        _ = self.advance();
                    }
                }

                if (self.check(.rparen)) {
                    _ = self.advance();
                }

                const call_data = ast.NodeData{
                    .call_expr = .{
                        .callee = expr,
                        .arguments = arguments,
                    },
                };

                expr = try ast.createNode(
                    self.allocator,
                    .call_expr,
                    ast.defaultSpan(),
                    call_data,
                );
            } else if (self.check(.plus_plus) or self.check(.minus_minus)) {
                const op_token = self.advance();
                const update_data = ast.NodeData{
                    .update_expr = .{
                        .operator = op_token.value,
                        .argument = expr,
                        .prefix = false,
                    },
                };
                expr = try ast.createNode(
                    self.allocator,
                    .update_expr,
                    ast.defaultSpan(),
                    update_data,
                );
            } else {
                break;
            }
        }

        return expr;
    }

    fn parsePrimary(self: *Self) ParseError!*ast.Node {
        const token = self.peek();

        switch (token.type) {
            .identifier => {
                _ = self.advance();
                const id_data = ast.NodeData{
                    .identifier_expr = .{
                        .name = token.value,
                    },
                };
                return ast.createNode(
                    self.allocator,
                    .identifier_expr,
                    token.span,
                    id_data,
                );
            },
            .number => {
                _ = self.advance();
                const num_value = std.fmt.parseFloat(f64, token.value) catch 0.0;
                const lit_data = ast.NodeData{
                    .literal_expr = .{
                        .value = .{ .number = num_value },
                        .raw = token.value,
                    },
                };
                return ast.createNode(
                    self.allocator,
                    .literal_expr,
                    token.span,
                    lit_data,
                );
            },
            .string => {
                _ = self.advance();
                const lit_data = ast.NodeData{
                    .literal_expr = .{
                        .value = .{ .string = token.value },
                        .raw = token.value,
                    },
                };
                return ast.createNode(
                    self.allocator,
                    .literal_expr,
                    token.span,
                    lit_data,
                );
            },
            .boolean => {
                _ = self.advance();
                const bool_val = std.mem.eql(u8, token.value, "true");
                const lit_data = ast.NodeData{
                    .literal_expr = .{
                        .value = .{ .boolean = bool_val },
                        .raw = token.value,
                    },
                };
                return ast.createNode(
                    self.allocator,
                    .literal_expr,
                    token.span,
                    lit_data,
                );
            },
            .null_literal => {
                _ = self.advance();
                const lit_data = ast.NodeData{
                    .literal_expr = .{
                        .value = .{ .null_val = {} },
                        .raw = token.value,
                    },
                };
                return ast.createNode(
                    self.allocator,
                    .literal_expr,
                    token.span,
                    lit_data,
                );
            },
            .lparen => {
                const start_span = token.span;
                _ = self.advance();

                var params = std.ArrayList(*ast.Node).init(self.allocator);
                var is_arrow = false;

                if (self.check(.rparen)) {
                    _ = self.advance();
                    self.skipWhitespace();
                    if (self.check(.arrow)) {
                        is_arrow = true;
                        _ = self.advance();
                    }
                } else {
                    const first_expr = try self.parseExpression();
                    self.skipWhitespace();

                    if (self.check(.comma)) {
                        try params.append(first_expr);
                        while (self.check(.comma)) {
                            _ = self.advance();
                            self.skipWhitespace();
                            const param = try self.parseExpression();
                            try params.append(param);
                            self.skipWhitespace();
                        }
                        if (self.check(.rparen)) {
                            _ = self.advance();
                            self.skipWhitespace();
                            if (self.check(.arrow)) {
                                is_arrow = true;
                                _ = self.advance();
                            }
                        }
                    } else if (self.check(.rparen)) {
                        _ = self.advance();
                        self.skipWhitespace();
                        if (self.check(.arrow)) {
                            is_arrow = true;
                            _ = self.advance();
                            try params.append(first_expr);
                        } else {
                            return first_expr;
                        }
                    } else {
                        return first_expr;
                    }
                }

                if (is_arrow) {
                    self.skipWhitespace();
                    const body = try self.parseExpression();
                    const arrow_data = ast.NodeData{
                        .arrow_expr = .{
                            .params = params,
                            .body = body,
                        },
                    };
                    return ast.createNode(self.allocator, .arrow_expr, start_span, arrow_data);
                }

                if (params.items.len == 1) {
                    return params.items[0];
                }

                const id_data = ast.NodeData{
                    .identifier_expr = .{ .name = "" },
                };
                return ast.createNode(self.allocator, .identifier_expr, ast.defaultSpan(), id_data);
            },
            .lbracket => {
                return try self.parseArrayExpression();
            },
            .lbrace => {
                return try self.parseObjectExpression();
            },
            else => {
                const id_data = ast.NodeData{
                    .identifier_expr = .{
                        .name = "",
                    },
                };
                return ast.createNode(
                    self.allocator,
                    .identifier_expr,
                    ast.defaultSpan(),
                    id_data,
                );
            },
        }
    }

    fn parseArrayExpression(self: *Self) ParseError!*ast.Node {
        _ = self.advance();

        var elements = std.ArrayList(?*ast.Node).init(self.allocator);

        while (!self.check(.rbracket) and !self.isAtEnd()) {
            self.skipWhitespace();

            if (self.check(.comma)) {
                try elements.append(null);
                _ = self.advance();
            } else {
                const element = try self.parseExpression();
                try elements.append(element);
                self.skipWhitespace();
                if (self.check(.comma)) {
                    _ = self.advance();
                }
            }
        }

        if (self.check(.rbracket)) {
            _ = self.advance();
        }

        const array_data = ast.NodeData{
            .array_expr = .{
                .elements = elements,
            },
        };

        return ast.createNode(
            self.allocator,
            .array_expr,
            ast.defaultSpan(),
            array_data,
        );
    }

    fn parseObjectExpression(self: *Self) ParseError!*ast.Node {
        _ = self.advance();

        var properties = std.ArrayList(*ast.Node).init(self.allocator);

        while (!self.check(.rbrace) and !self.isAtEnd()) {
            self.skipWhitespace();

            if (self.check(.identifier) or self.check(.string)) {
                const key = try self.parsePrimary();

                self.skipWhitespace();
                if (self.check(.colon)) {
                    _ = self.advance();
                }
                self.skipWhitespace();

                const value = try self.parseExpression();

                const prop_data = ast.NodeData{
                    .binary_expr = .{
                        .operator = ":",
                        .left = key,
                        .right = value,
                    },
                };

                const prop = try ast.createNode(
                    self.allocator,
                    .binary_expr,
                    ast.defaultSpan(),
                    prop_data,
                );

                try properties.append(prop);
            }

            self.skipWhitespace();
            if (self.check(.comma)) {
                _ = self.advance();
            }
        }

        if (self.check(.rbrace)) {
            _ = self.advance();
        }

        const obj_data = ast.NodeData{
            .object_expr = .{
                .properties = properties,
            },
        };

        return ast.createNode(
            self.allocator,
            .object_expr,
            ast.defaultSpan(),
            obj_data,
        );
    }

    fn expectClosingTag(self: *Self, name: []const u8) ParseError!void {
        if (self.check(.close_tag)) {
            _ = self.advance();
            self.skipWhitespace();
            if (self.check(.identifier)) {
                const close_name = self.advance();
                if (!std.mem.eql(u8, close_name.value, name)) {
                    try self.errors.append(.{
                        .message = "Mismatched closing tag",
                        .span = close_name.span,
                    });
                }
            }
            self.skipWhitespace();
            if (self.check(.rbracket)) {
                _ = self.advance();
            }
        }
    }

    fn isAtEnd(self: *Self) bool {
        return self.current >= self.tokens.len or self.peek().type == .eof;
    }

    fn peek(self: *Self) ast.Token {
        if (self.current >= self.tokens.len) {
            return .{
                .type = .eof,
                .value = "",
                .span = ast.defaultSpan(),
            };
        }
        return self.tokens[self.current];
    }

    fn advance(self: *Self) ast.Token {
        if (!self.isAtEnd()) {
            self.current += 1;
        }
        return self.tokens[self.current - 1];
    }

    fn check(self: *Self, token_type: ast.TokenType) bool {
        if (self.isAtEnd()) return false;
        return self.peek().type == token_type;
    }

    fn skipWhitespace(self: *Self) void {
        while (self.check(.whitespace) or self.check(.newline)) {
            _ = self.advance();
        }
    }
};

fn isUpperCase(c: u8) bool {
    return c >= 'A' and c <= 'Z';
}

test "parser basic element" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var lex = Lexer.init(allocator, "<div></div>");
    defer lex.deinit();
    const tokens = try lex.tokenize();

    var p = Parser.init(allocator, tokens);
    defer p.deinit();

    const ast_root = try p.parse();
    try std.testing.expectEqual(ast_root.node_type, .root);
}
