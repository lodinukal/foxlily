const std = @import("std");
const stb = @import("stb");

pub const Metrics = extern struct {
    left_bearing: c_int,
    advance: c_int,
    ix0: c_int,
    ix1: c_int,
    iy0: c_int,
    iy1: c_int,
};

/// Generates a bitmap from the specified character (c)
/// Bitmap is a 3-channel float array (3*w*h)
/// Returned result is 1 for success or 0 in case of an error
pub extern fn ex_msdf_glyph_mem(
    font: *const stb.TrueType.fontinfo,
    c: u32,
    w: usize,
    h: usize,
    bitmap: [*]f32,
    metrics: *Metrics,
    autofit: c_int,
) c_int;
pub extern fn ex_msdf_glyph(
    font: *const stb.TrueType.fontinfo,
    c: u32,
    w: usize,
    h: usize,
    metrics: *Metrics,
    autofit: c_int,
) ?[*]f32;

pub fn free_msdf_glyph(glyph: ?[*]f32) void {
    if (glyph) |g| {
        stb.zstbFree(g);
    }
}
