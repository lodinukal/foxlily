pub const coord = c_int;
pub const node = extern struct {
    x: coord = 0,
    y: coord = 0,
    next: [*c]node = null,
};
pub const context = extern struct {
    width: c_int = 0,
    height: c_int = 0,
    @"align": c_int = 0,
    init_mode: c_int = 0,
    heuristic: c_int = 0,
    num_nodes: c_int = 0,
    active_head: [*c]node = null,
    free_head: [*c]node = null,
    extra: [2]node = @splat(.{}),
};
pub const rect = extern struct {
    id: c_int = 0,
    w: coord = 0,
    h: coord = 0,
    x: coord = 0,
    y: coord = 0,
    was_packed: c_int = 0,
};
pub const pack_rects = stbrp_pack_rects;
extern fn stbrp_pack_rects(ctx: [*c]context, rects: [*c]rect, num_rects: c_int) c_int;
pub const init_target = stbrp_init_target;
extern fn stbrp_init_target(ctx: [*c]context, width: c_int, height: c_int, nodes: [*c]node, num_nodes: c_int) void;
pub const setup_allow_out_of_mem = stbrp_setup_allow_out_of_mem;
extern fn stbrp_setup_allow_out_of_mem(ctx: [*c]context, allow_out_of_mem: c_int) void;
pub const setup_heuristic = stbrp_setup_heuristic;
extern fn stbrp_setup_heuristic(ctx: [*c]context, heuristic: c_int) void;
pub const HEURISTIC_Skyline_default: c_int = 0;
pub const HEURISTIC_Skyline_BL_sortHeight: c_int = 0;
pub const HEURISTIC_Skyline_BF_sortHeight: c_int = 1;
