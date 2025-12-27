const std = @import("std");

pub const Position = struct {
    line: u32,
    column: u32,
    offset: u32,
};

pub const Span = struct {
    start: Position,
    end: Position,
};

pub const TokenType = enum {
    text,
    number,
    string,
    boolean,
    null_literal,
    identifier,
    kw_if,
    kw_else,
    kw_each,
    kw_await,
    kw_then,
    kw_catch,
    kw_key,
    kw_snippet,
    kw_render,
    kw_html,
    kw_const,
    kw_debug,
    eq,
    neq,
    lt,
    gt,
    lte,
    gte,
    plus,
    minus,
    star,
    slash,
    percent,
    and_op,
    or_op,
    not,
    question,
    colon,
    dot,
    comma,
    semicolon,
    pipe,
    at,
    hash,
    lparen,
    rparen,
    lbrace,
    rbrace,
    lbracket,
    rbracket,
    open_tag,
    close_tag,
    self_close_tag,
    mustache_open,
    mustache_close,
    comment,
    doctype,
    directive_on,
    directive_bind,
    directive_class,
    directive_style,
    directive_use,
    directive_transition,
    directive_animate,
    directive_in,
    directive_out,
    directive_let,
    eof,
    error_token,
    whitespace,
    newline,
};

pub const Token = struct {
    type: TokenType,
    value: []const u8,
    span: Span,
};

pub const NodeType = enum {
    root,
    fragment,
    element,
    component,
    slot,
    svelte_element,
    svelte_component,
    svelte_self,
    svelte_fragment,
    svelte_head,
    svelte_body,
    svelte_window,
    svelte_document,
    svelte_options,
    svelte_boundary,
    if_block,
    else_block,
    else_if_block,
    each_block,
    await_block,
    pending_block,
    then_block,
    catch_block,
    key_block,
    snippet_block,
    text_node,
    expression_tag,
    html_tag,
    const_tag,
    debug_tag,
    render_tag,
    comment_node,
    attribute,
    spread_attribute,
    directive,
    script,
    module_script,
    style,
    identifier_expr,
    literal_expr,
    member_expr,
    call_expr,
    binary_expr,
    unary_expr,
    conditional_expr,
    array_expr,
    object_expr,
    assignment_expr,
    sequence_expr,
};

pub const Node = struct {
    node_type: NodeType,
    span: Span,
    data: NodeData,
};

pub const NodeData = union(NodeType) {
    root: RootNode,
    fragment: FragmentNode,
    element: ElementNode,
    component: ComponentNode,
    slot: SlotNode,
    svelte_element: SvelteElementNode,
    svelte_component: SvelteComponentNode,
    svelte_self: SvelteSelfNode,
    svelte_fragment: SvelteFragmentNode,
    svelte_head: SvelteHeadNode,
    svelte_body: SvelteBodyNode,
    svelte_window: SvelteWindowNode,
    svelte_document: SvelteDocumentNode,
    svelte_options: SvelteOptionsNode,
    svelte_boundary: SvelteBoundaryNode,
    if_block: IfBlockNode,
    else_block: ElseBlockNode,
    else_if_block: ElseIfBlockNode,
    each_block: EachBlockNode,
    await_block: AwaitBlockNode,
    pending_block: PendingBlockNode,
    then_block: ThenBlockNode,
    catch_block: CatchBlockNode,
    key_block: KeyBlockNode,
    snippet_block: SnippetBlockNode,
    text_node: TextNode,
    expression_tag: ExpressionTagNode,
    html_tag: HtmlTagNode,
    const_tag: ConstTagNode,
    debug_tag: DebugTagNode,
    render_tag: RenderTagNode,
    comment_node: CommentNode,
    attribute: AttributeNode,
    spread_attribute: SpreadAttributeNode,
    directive: DirectiveNode,
    script: ScriptNode,
    module_script: ModuleScriptNode,
    style: StyleNode,
    identifier_expr: IdentifierExpr,
    literal_expr: LiteralExpr,
    member_expr: MemberExpr,
    call_expr: CallExpr,
    binary_expr: BinaryExpr,
    unary_expr: UnaryExpr,
    conditional_expr: ConditionalExpr,
    array_expr: ArrayExpr,
    object_expr: ObjectExpr,
    assignment_expr: AssignmentExpr,
    sequence_expr: SequenceExpr,
};

pub const RootNode = struct {
    fragment: *Node,
    instance: ?*Node,
    module: ?*Node,
    options: ?*Node,
    css: ?*Node,
    metadata: Metadata,
};

pub const Metadata = struct {
    ts: bool = false,
    runes: bool = false,
};

pub const FragmentNode = struct {
    children: std.ArrayList(*Node),
    transparent: bool = false,
};

pub const ElementNode = struct {
    name: []const u8,
    attributes: std.ArrayList(*Node),
    children: std.ArrayList(*Node),
    self_closing: bool = false,
};

pub const ComponentNode = struct {
    name: []const u8,
    attributes: std.ArrayList(*Node),
    children: std.ArrayList(*Node),
};

pub const SlotNode = struct {
    name: []const u8,
    attributes: std.ArrayList(*Node),
    children: std.ArrayList(*Node),
};

pub const SvelteElementNode = struct {
    tag: *Node,
    attributes: std.ArrayList(*Node),
    children: std.ArrayList(*Node),
};

pub const SvelteComponentNode = struct {
    expression: *Node,
    attributes: std.ArrayList(*Node),
    children: std.ArrayList(*Node),
};

pub const SvelteSelfNode = struct {
    attributes: std.ArrayList(*Node),
    children: std.ArrayList(*Node),
};

pub const SvelteFragmentNode = struct {
    attributes: std.ArrayList(*Node),
    children: std.ArrayList(*Node),
};

pub const SvelteHeadNode = struct {
    children: std.ArrayList(*Node),
};

pub const SvelteBodyNode = struct {
    attributes: std.ArrayList(*Node),
};

pub const SvelteWindowNode = struct {
    attributes: std.ArrayList(*Node),
};

pub const SvelteDocumentNode = struct {
    attributes: std.ArrayList(*Node),
};

pub const SvelteOptionsNode = struct {
    attributes: std.ArrayList(*Node),
};

pub const SvelteBoundaryNode = struct {
    attributes: std.ArrayList(*Node),
    children: std.ArrayList(*Node),
    failed: ?*Node,
    pending: ?*Node,
};

pub const IfBlockNode = struct {
    condition: *Node,
    consequent: *Node,
    alternate: ?*Node,
    is_elseif: bool = false,
};

pub const ElseBlockNode = struct {
    children: std.ArrayList(*Node),
};

pub const ElseIfBlockNode = struct {
    condition: *Node,
    consequent: *Node,
    alternate: ?*Node,
};

pub const EachBlockNode = struct {
    expression: *Node,
    context: *Node,
    index: ?[]const u8,
    key: ?*Node,
    children: std.ArrayList(*Node),
    fallback: ?*Node,
};

pub const AwaitBlockNode = struct {
    expression: *Node,
    pending: ?*Node,
    value: ?*Node,
    then_node: ?*Node,
    error_node: ?*Node,
    catch_node: ?*Node,
};

pub const PendingBlockNode = struct {
    children: std.ArrayList(*Node),
};

pub const ThenBlockNode = struct {
    children: std.ArrayList(*Node),
};

pub const CatchBlockNode = struct {
    children: std.ArrayList(*Node),
};

pub const KeyBlockNode = struct {
    expression: *Node,
    children: std.ArrayList(*Node),
};

pub const SnippetBlockNode = struct {
    name: []const u8,
    parameters: std.ArrayList(*Node),
    body: *Node,
};

pub const TextNode = struct {
    data: []const u8,
    raw: []const u8,
};

pub const ExpressionTagNode = struct {
    expression: *Node,
};

pub const HtmlTagNode = struct {
    expression: *Node,
};

pub const ConstTagNode = struct {
    declaration: *Node,
};

pub const DebugTagNode = struct {
    identifiers: std.ArrayList(*Node),
};

pub const RenderTagNode = struct {
    expression: *Node,
    argument: ?*Node,
};

pub const CommentNode = struct {
    data: []const u8,
};

pub const AttributeNode = struct {
    name: []const u8,
    value: AttributeValue,
};

pub const AttributeValue = union(enum) {
    text: []const u8,
    expression: *Node,
    concat: std.ArrayList(AttributeValuePart),
    boolean: bool,
};

pub const AttributeValuePart = union(enum) {
    text: []const u8,
    expression: *Node,
};

pub const SpreadAttributeNode = struct {
    expression: *Node,
};

pub const DirectiveType = enum {
    on,
    bind,
    class_directive,
    style_directive,
    use,
    transition,
    animate,
    in_directive,
    out_directive,
    let_directive,
};

pub const DirectiveNode = struct {
    directive_type: DirectiveType,
    name: []const u8,
    expression: ?*Node,
    modifiers: std.ArrayList([]const u8),
};

pub const ScriptNode = struct {
    content: []const u8,
    context: ScriptContext,
};

pub const ScriptContext = enum {
    default,
    module,
};

pub const ModuleScriptNode = struct {
    content: []const u8,
};

pub const StyleNode = struct {
    content: []const u8,
    attributes: std.ArrayList(*Node),
};

pub const IdentifierExpr = struct {
    name: []const u8,
};

pub const LiteralExpr = struct {
    value: LiteralValue,
    raw: []const u8,
};

pub const LiteralValue = union(enum) {
    string: []const u8,
    number: f64,
    boolean: bool,
    null_val: void,
};

pub const MemberExpr = struct {
    object: *Node,
    property: *Node,
    computed: bool,
};

pub const CallExpr = struct {
    callee: *Node,
    arguments: std.ArrayList(*Node),
};

pub const BinaryExpr = struct {
    operator: []const u8,
    left: *Node,
    right: *Node,
};

pub const UnaryExpr = struct {
    operator: []const u8,
    argument: *Node,
    prefix: bool,
};

pub const ConditionalExpr = struct {
    condition: *Node,
    consequent: *Node,
    alternate: *Node,
};

pub const ArrayExpr = struct {
    elements: std.ArrayList(?*Node),
};

pub const ObjectExpr = struct {
    properties: std.ArrayList(*Node),
};

pub const AssignmentExpr = struct {
    operator: []const u8,
    left: *Node,
    right: *Node,
};

pub const SequenceExpr = struct {
    expressions: std.ArrayList(*Node),
};

pub fn createNode(allocator: std.mem.Allocator, node_type: NodeType, span: Span, data: NodeData) !*Node {
    const node = try allocator.create(Node);
    node.* = .{
        .node_type = node_type,
        .span = span,
        .data = data,
    };
    return node;
}

pub fn defaultSpan() Span {
    return .{
        .start = .{ .line = 0, .column = 0, .offset = 0 },
        .end = .{ .line = 0, .column = 0, .offset = 0 },
    };
}
