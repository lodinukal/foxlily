const std = @import("std");

const FontAtlas = @This();

const ila = @import("../root.zig");

const msdfgen = @import("msdfgen");
const msdfatlasgen = @import("msdfatlasgen");

allocator: std.mem.Allocator,
glyph_quads: []GlyphQuad = &.{},
codepoint_to_quad: std.AutoArrayHashMapUnmanaged(u21, usize) = .empty,
font_size: f32 = 0,
image: ila.Resource.Image = .{},
max_padding: u32 = 0,
max_padding_scaled: f32 = 0,

pub fn loadFromData(allocator: std.mem.Allocator, data: []const u8, width: u32, height: u32) !FontAtlas {
    var out_image: ila.Resource.Image = try .initResolution(allocator, width, height, .RGBA32F);
    errdefer out_image.deinit();
    const slice: []u8 = out_image.data.slice() orelse unreachable;
    const slice_floats: []align(1) f32 = std.mem.bytesAsSlice(f32, slice);
    @memset(slice_floats, 0.0);

    const padding = 10;

    const ft = try getFreetypeLib();

    const ft_font = ft.loadFontData(data) orelse {
        std.log.err("Failed to load font data", .{});
        return error.LoadFontDataFailed;
    };
    defer ft_font.deinit();

    const charset = msdfatlasgen.Charset.init() orelse {
        std.log.err("Failed to create charset", .{});
        return error.InitCharsetFailed;
    };
    defer charset.deinit();

    var codepoint_to_quad: std.AutoArrayHashMapUnmanaged(u21, usize) = .empty;
    errdefer codepoint_to_quad.deinit(allocator);

    for (&codepoint_ranges.lod_japanese) |range| {
        if (range[0] == 0 and range[1] == 0) break;
        for (range[0]..range[1]) |codepoint| {
            const cp: u21 = @intCast(codepoint);
            charset.add(cp);
        }
    }
    try codepoint_to_quad.ensureTotalCapacity(allocator, charset.size());

    const glyph_quads = try allocator.alloc(
        GlyphQuad,
        charset.size(),
    );
    errdefer allocator.free(glyph_quads);

    const font_geometry = msdfatlasgen.FontGeometry.init() orelse {
        std.log.err("Failed to create font geometry", .{});
        return error.InitFontGeometryFailed;
    };
    defer font_geometry.deinit();

    const char_scale = 1.0;
    const load_charset_res = font_geometry.loadCharset(ft_font, char_scale, charset);
    _ = load_charset_res;
    const glyphs = font_geometry.getGlyphs();
    for (0..glyphs.count) |i| {
        glyphs.setEdgeColoring(i, .by_distance, 3.0, 0);
    }

    const packer = msdfatlasgen.Packer.init() orelse {
        std.log.err("Failed to create packer", .{});
        return error.InitPackerFailed;
    };
    defer packer.deinit();

    packer.setDimensionsConstraint(.square);
    packer.setMinimumScale(24.0);
    packer.setPixelRange(-1.0, 1.0);
    packer.setMiterLimit(1.0);
    packer.setDimensions(@intCast(width), @intCast(height));
    packer.setOuterPixelPadding(padding, padding, padding, padding);
    const pack_res = packer.pack(glyphs);
    if (pack_res != 0) {
        std.log.err("Failed to pack glyphs {}", .{pack_res});
        return error.PackFontRangeFailed;
    }

    const generator = msdfatlasgen.ImmediateAtlasGenerator.init(width, height) orelse {
        std.log.err("Failed to create atlas generator", .{});
        return error.InitAtlasGeneratorFailed;
    };
    defer generator.deinit();

    generator.setThreadCount(16);
    generator.generate(glyphs);
    const scale = packer.getScale();

    const bitmap = generator.getBitmap();
    const bitmap_slice = bitmap.slice();

    // write the image first
    for (0..height) |inv_h| {
        for (0..width) |w| {
            const h = height - 1 - inv_h; // flip y axis
            const idx: usize = (w + inv_h * width) * 3;
            const idx_4_channel: usize = (w + h * width) * 4;

            const red_float: f32 = bitmap_slice[idx];
            const green_float: f32 = bitmap_slice[idx + 1];
            const blue_float: f32 = bitmap_slice[idx + 2];

            slice_floats[idx_4_channel] = red_float; // R
            slice_floats[idx_4_channel + 1] = green_float; // G
            slice_floats[idx_4_channel + 2] = blue_float; // B
            slice_floats[idx_4_channel + 3] = 1.0; // A
        }
    }

    for (0..glyphs.count) |i| {
        const advance = glyphs.getAdvance(i);
        const box = glyphs.getBoxRect(i);
        const bounds = glyphs.getQuadPlaneBounds(i);
        const quad: *GlyphQuad = &glyph_quads[i];
        quad.advance = advance;
        quad.x_offset = .{ bounds.left, bounds.right };
        quad.y_offset = .{ bounds.top, bounds.bottom };
        if (box.w == 0 or box.h == 0) {
            quad.top_left_texture = .{ 0, 0 };
            quad.bottom_right_texture = .{ 0, 0 };
            continue; // skip empty glyphs
        }
        quad.top_left_texture = .{ box.x + 1, box.y + 1 };
        quad.bottom_right_texture = .{ box.x + box.w - 1, box.y + box.h - 1 };
        codepoint_to_quad.putAssumeCapacity(@intCast(glyphs.getCodepoint(i)), i);
    }

    var found_metrics = ft_font.getMetrics(.NONE) orelse {
        std.log.err("Failed to get font metrics", .{});
        return error.GetFontMetricsFailed;
    };
    const geometry_scale = char_scale / (if (found_metrics.em_size <= 0.0) 2048.0 else found_metrics.em_size);
    found_metrics.em_size *= geometry_scale;
    found_metrics.ascender_y *= geometry_scale;
    found_metrics.descender_y *= geometry_scale;
    found_metrics.line_height *= geometry_scale;
    found_metrics.underline_y *= geometry_scale;
    found_metrics.underline_thickness *= geometry_scale;

    return .{
        .allocator = allocator,
        .glyph_quads = glyph_quads,
        .font_size = @floatCast(found_metrics.ascender_y - found_metrics.descender_y),
        .image = out_image,
        .max_padding = padding,
        .max_padding_scaled = @floatCast(@as(f32, padding) / scale),
        .codepoint_to_quad = codepoint_to_quad,
    };
}

var ft_lib: ?*msdfgen.FreetypeHandle = null;
fn getFreetypeLib() !*msdfgen.FreetypeHandle {
    if (ft_lib) |lib| return lib;
    const new_lib = msdfgen.FreetypeHandle.init() orelse {
        std.log.err("Failed to initialize FreeType", .{});
        return error.InitFreetypeFailed;
    };
    ft_lib = new_lib;
    return new_lib;
}

pub fn loadTTFFromPath(allocator: std.mem.Allocator, path: []const u8, width: u32, height: u32) !FontAtlas {
    const file = std.fs.cwd().openFile(path, .{}) catch return error.FileNotFound;
    defer file.close();

    const stat = file.stat() catch return error.LoadFontFailed;
    const font_mem = file.reader().readAllAlloc(allocator, @intCast(stat.size)) catch return error.OutOfMemory;
    defer allocator.free(font_mem);

    return try loadFromData(
        allocator,
        font_mem,
        width,
        height,
    );
}

pub fn deinit(self: *FontAtlas) void {
    self.allocator.free(self.glyph_quads);
    self.image.deinit();
    self.codepoint_to_quad.deinit(self.allocator);
}

/// Represents a glyph quad in the font atlas.
pub const GlyphQuad = struct {
    /// the top left corner coordinate (in pixel space)
    top_left_texture: [2]u32 = .{ 0, 0 },
    /// the bottom right corner coordinate (in pixel space)
    bottom_right_texture: [2]u32 = .{ 0, 0 },
    /// the x offset of the glyph, for the left and right edges
    x_offset: [2]f64 = .{ 0, 0 },
    /// the y offset of the glyph, for the top and bottom edges
    y_offset: [2]f64 = .{ 0, 0 },
    /// how much to advance the cursor after rendering this glyph
    advance: f32 = 0,
};

pub const CharQuad = struct {
    uv_top_left: [2]f32 = .{ 0, 0 },
    uv_bottom_right: [2]f32 = .{ 0, 0 },
    position_top_left: [2]f32 = .{ 0, 0 },
    position_bottom_right: [2]f32 = .{ 0, 0 },

    pub fn width(self: CharQuad) f32 {
        return @abs(self.position_bottom_right[0] - self.position_top_left[0]);
    }

    pub fn height(self: CharQuad) f32 {
        return @abs(self.position_bottom_right[1] - self.position_top_left[1]);
    }

    pub fn center(self: CharQuad) [2]f32 {
        return .{
            (self.position_top_left[0] + self.position_bottom_right[0]) / 2,
            (self.position_top_left[1] + self.position_bottom_right[1]) / 2,
        };
    }

    pub fn topLeft(self: CharQuad) [2]f32 {
        const c = self.center();
        return .{
            c[0] - self.width() / 2,
            c[1] + self.height() / 2,
        };
    }
};

/// size in pixels
pub fn getCharQuad(self: *const FontAtlas, codepoint: u21, size: f32) CharQuad {
    var x_pos: f32 = 0;
    var y_pos: f32 = 0;
    return self.getCharQuadMoving(codepoint, size, &x_pos, &y_pos);
}

/// size in pixels
pub fn getCharQuadMoving(self: *const FontAtlas, codepoint: u21, size: f32, x_pos: *f32, y_pos: *f32) CharQuad {
    const scale = size / self.font_size;
    const max_padding: f32 = self.max_padding_scaled * scale;
    const glyph = self.glyph_quads[self.codepoint_to_quad.get(codepoint) orelse return .{}];

    const x0 = x_pos.* + (glyph.x_offset[0]) * scale - max_padding;
    const y0 = y_pos.* - (glyph.y_offset[0]) * scale - max_padding;
    const x1 = x_pos.* + (glyph.x_offset[1]) * scale + max_padding;
    const y1 = y_pos.* - (glyph.y_offset[1]) * scale + max_padding;

    const s0 = @as(f32, @floatFromInt(glyph.top_left_texture[0] - 0)) / @as(f32, @floatFromInt(self.image.width));
    const s1 = @as(f32, @floatFromInt(glyph.bottom_right_texture[0] + 0)) / @as(f32, @floatFromInt(self.image.width));

    const t0 = @as(f32, @floatFromInt(glyph.top_left_texture[1] - 0)) / @as(f32, @floatFromInt(self.image.height));
    const t1 = @as(f32, @floatFromInt(glyph.bottom_right_texture[1] + 0)) / @as(f32, @floatFromInt(self.image.height));

    x_pos.* += glyph.advance * scale;

    const quad: CharQuad = .{
        .uv_top_left = .{ s0, 1 - t1 },
        .uv_bottom_right = .{ s1, 1 - t0 },
        // .uv_offset = .{ 0, 0.5 },
        // .uv_scale = .{ 0.5, 0.5 },
        .position_top_left = .{ @floatCast(x0), @floatCast(y0) },
        .position_bottom_right = .{ @floatCast(x1), @floatCast(y1) },
    };

    return quad;
}

// codepoint ranges from https://github.com/Jack-Ji/jok/tree/main/src
// MIT License

// Copyright (c) 2022 jack

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
const codepoint_ranges = struct {
    /// Useful codepoint ranges
    pub const default = [_][2]u32{
        .{ 0x0020, 0x00FF },
        .{ 0, 0 },
    };

    pub const chinese_full = [_][2]u32{
        .{ 0x0020, 0x00FF }, // Basic Latin + Latin Supplement
        .{ 0x2000, 0x206F }, // General Punctuation
        .{ 0x3000, 0x30FF }, // CJK Symbols and Punctuations, Hiragana, Katakana
        .{ 0x31F0, 0x31FF }, // Katakana Phonetic Extensions
        .{ 0xFF00, 0xFFEF }, // Half-width characters
        .{ 0xFFFD, 0xFFFD }, // Invalid
        .{ 0x4e00, 0x9FAF }, // CJK Ideograms
        .{ 0, 0 },
    };

    pub const chinese_common = genRanges(
        &[_][2]u32{
            .{ 0x0020, 0x00FF }, // Basic Latin + Latin Supplement
            .{ 0x2000, 0x206F }, // General Punctuation
            .{ 0x3000, 0x30FF }, // CJK Symbols and Punctuations, Hiragana, Katakana
            .{ 0x31F0, 0x31FF }, // Katakana Phonetic Extensions
            .{ 0xFF00, 0xFFEF }, // Half-width characters
            .{ 0xFFFD, 0xFFFD }, // Invalid
        },
        0x4E00,
        &[_]u32{
            0,  1,  2,  4,  1,  1,  1,  1,  2,  1,  3,  2,  1,  2,  2,  1,  1,   1,   1,  1,  5,  2,  1,  2,  3,  3,   3,   2,  2,  4,  1,  1,  1,  2,  1,  5,   2,  3,  1,  2,  1,   2,  1,  1,   2,  1,  1,  2,   2,  1,   4,  1,  1,  1,  1,   5,   10,  1,   2,   19, 2,  1,   2,  1,   2,   1,  2,  1,  2,
            1,  5,  1,  6,  3,  2,  1,  2,  2,  1,  1,  1,  4,  8,  5,  1,  1,   4,   1,  1,  3,  1,  2,  1,  5,  1,   2,   1,  1,  1,  10, 1,  1,  5,  2,  4,   6,  1,  4,  2,  2,   2,  12, 2,   1,  1,  6,  1,   1,  1,   4,  1,  1,  4,  6,   5,   1,   4,   2,   2,  4,  10,  7,  1,   1,   4,  2,  4,  2,
            1,  4,  3,  6,  10, 12, 5,  7,  2,  14, 2,  9,  1,  1,  6,  7,  10,  4,   7,  13, 1,  5,  4,  8,  4,  1,   1,   2,  28, 5,  6,  1,  1,  5,  2,  5,   20, 2,  2,  9,  8,   11, 2,  9,   17, 1,  8,  6,   8,  27,  4,  6,  9,  20, 11,  27,  6,   68,  2,   2,  1,  1,   1,  2,   1,   2,  2,  7,  6,
            11, 3,  3,  1,  1,  3,  1,  2,  1,  1,  1,  1,  1,  3,  1,  1,  8,   3,   4,  1,  5,  7,  2,  1,  4,  4,   8,   4,  2,  1,  2,  1,  1,  4,  5,  6,   3,  6,  2,  12, 3,   1,  3,  9,   2,  4,  3,  4,   1,  5,   3,  3,  1,  3,  7,   1,   5,   1,   1,   1,  1,  2,   3,  4,   5,   2,  3,  2,  6,
            1,  1,  2,  1,  7,  1,  7,  3,  4,  5,  15, 2,  2,  1,  5,  3,  22,  19,  2,  1,  1,  1,  1,  2,  5,  1,   1,   1,  6,  1,  1,  12, 8,  2,  9,  18,  22, 4,  1,  1,  5,   1,  16, 1,   2,  7,  10, 15,  1,  1,   6,  2,  4,  1,  2,   4,   1,   6,   1,   1,  3,  2,   4,  1,   6,   4,  5,  1,  2,
            1,  1,  2,  1,  10, 3,  1,  3,  2,  1,  9,  3,  2,  5,  7,  2,  19,  4,   3,  6,  1,  1,  1,  1,  1,  4,   3,   2,  1,  1,  1,  2,  5,  3,  1,  1,   1,  2,  2,  1,  1,   2,  1,  1,   2,  1,  3,  1,   1,  1,   3,  7,  1,  4,  1,   1,   2,   1,   1,   2,  1,  2,   4,  4,   3,   8,  1,  1,  1,
            2,  1,  3,  5,  1,  3,  1,  3,  4,  6,  2,  2,  14, 4,  6,  6,  11,  9,   1,  15, 3,  1,  28, 5,  2,  5,   5,   3,  1,  3,  4,  5,  4,  6,  14, 3,   2,  3,  5,  21, 2,   7,  20, 10,  1,  2,  19, 2,   4,  28,  28, 2,  3,  2,  1,   14,  4,   1,   26,  28, 42, 12,  40, 3,   52,  79, 5,  14, 17,
            3,  2,  2,  11, 3,  4,  6,  3,  1,  8,  2,  23, 4,  5,  8,  10, 4,   2,   7,  3,  5,  1,  1,  6,  3,  1,   2,   2,  2,  5,  28, 1,  1,  7,  7,  20,  5,  3,  29, 3,  17,  26, 1,  8,   4,  27, 3,  6,   11, 23,  5,  3,  4,  6,  13,  24,  16,  6,   5,   10, 25, 35,  7,  3,   2,   3,  3,  14, 3,
            6,  2,  6,  1,  4,  2,  3,  8,  2,  1,  1,  3,  3,  3,  4,  1,  1,   13,  2,  2,  4,  5,  2,  1,  14, 14,  1,   2,  2,  1,  4,  5,  2,  3,  1,  14,  3,  12, 3,  17, 2,   16, 5,  1,   2,  1,  8,  9,   3,  19,  4,  2,  2,  4,  17,  25,  21,  20,  28,  75, 1,  10,  29, 103, 4,   1,  2,  1,  1,
            4,  2,  4,  1,  2,  3,  24, 2,  2,  2,  1,  1,  2,  1,  3,  8,  1,   1,   1,  2,  1,  1,  3,  1,  1,  1,   6,   1,  5,  3,  1,  1,  1,  3,  4,  1,   1,  5,  2,  1,  5,   6,  13, 9,   16, 1,  1,  1,   1,  3,   2,  3,  2,  4,  5,   2,   5,   2,   2,   3,  7,  13,  7,  2,   2,   1,  1,  1,  1,
            2,  3,  3,  2,  1,  6,  4,  9,  2,  1,  14, 2,  14, 2,  1,  18, 3,   4,   14, 4,  11, 41, 15, 23, 15, 23,  176, 1,  3,  4,  1,  1,  1,  1,  5,  3,   1,  2,  3,  7,  3,   1,  1,  2,   1,  2,  4,  4,   6,  2,   4,  1,  9,  7,  1,   10,  5,   8,   16,  29, 1,  1,   2,  2,   3,   1,  3,  5,  2,
            4,  5,  4,  1,  1,  2,  2,  3,  3,  7,  1,  6,  10, 1,  17, 1,  44,  4,   6,  2,  1,  1,  6,  5,  4,  2,   10,  1,  6,  9,  2,  8,  1,  24, 1,  2,   13, 7,  8,  8,  2,   1,  4,  1,   3,  1,  3,  3,   5,  2,   5,  10, 9,  4,  9,   12,  2,   1,   6,   1,  10, 1,   1,  7,   7,   4,  10, 8,  3,
            1,  13, 4,  3,  1,  6,  1,  3,  5,  2,  1,  2,  17, 16, 5,  2,  16,  6,   1,  4,  2,  1,  3,  3,  6,  8,   5,   11, 11, 1,  3,  3,  2,  4,  6,  10,  9,  5,  7,  4,  7,   4,  7,  1,   1,  4,  2,  1,   3,  6,   8,  7,  1,  6,  11,  5,   5,   3,   24,  9,  4,  2,   7,  13,  5,   1,  8,  82, 16,
            61, 1,  1,  1,  4,  2,  2,  16, 10, 3,  8,  1,  1,  6,  4,  2,  1,   3,   1,  1,  1,  4,  3,  8,  4,  2,   2,   1,  1,  1,  1,  1,  6,  3,  5,  1,   1,  4,  6,  9,  2,   1,  1,  1,   2,  1,  7,  2,   1,  6,   1,  5,  4,  4,  3,   1,   8,   1,   3,   3,  1,  3,   2,  2,   2,   2,  3,  1,  6,
            1,  2,  1,  2,  1,  3,  7,  1,  8,  2,  1,  2,  1,  5,  2,  5,  3,   5,   10, 1,  2,  1,  1,  3,  2,  5,   11,  3,  9,  3,  5,  1,  1,  5,  9,  1,   2,  1,  5,  7,  9,   9,  8,  1,   3,  3,  3,  6,   8,  2,   3,  2,  1,  1,  32,  6,   1,   2,   15,  9,  3,  7,   13, 1,   3,   10, 13, 2,  14,
            1,  13, 10, 2,  1,  3,  10, 4,  15, 2,  15, 15, 10, 1,  3,  9,  6,   9,   32, 25, 26, 47, 7,  3,  2,  3,   1,   6,  3,  4,  3,  2,  8,  5,  4,  1,   9,  4,  2,  2,  19,  10, 6,  2,   3,  8,  1,  2,   2,  4,   2,  1,  9,  4,  4,   4,   6,   4,   8,   9,  2,  3,   1,  1,   1,   1,  3,  5,  5,
            1,  3,  8,  4,  6,  2,  1,  4,  12, 1,  5,  3,  7,  13, 2,  5,  8,   1,   6,  1,  2,  5,  14, 6,  1,  5,   2,   4,  8,  15, 5,  1,  23, 6,  62, 2,   10, 1,  1,  8,  1,   2,  2,  10,  4,  2,  2,  9,   2,  1,   1,  3,  2,  3,  1,   5,   3,   3,   2,   1,  3,  8,   1,  1,   1,   11, 3,  1,  1,
            4,  3,  7,  1,  14, 1,  2,  3,  12, 5,  2,  5,  1,  6,  7,  5,  7,   14,  11, 1,  3,  1,  8,  9,  12, 2,   1,   11, 8,  4,  4,  2,  6,  10, 9,  13,  1,  1,  3,  1,  5,   1,  3,  2,   4,  4,  1,  18,  2,  3,   14, 11, 4,  29, 4,   2,   7,   1,   3,   13, 9,  2,   2,  5,   3,   5,  20, 7,  16,
            8,  5,  72, 34, 6,  4,  22, 12, 12, 28, 45, 36, 9,  7,  39, 9,  191, 1,   1,  1,  4,  11, 8,  4,  9,  2,   3,   22, 1,  1,  1,  1,  4,  17, 1,  7,   7,  1,  11, 31, 10,  2,  4,  8,   2,  3,  2,  1,   4,  2,   16, 4,  32, 2,  3,   19,  13,  4,   9,   1,  5,  2,   14, 8,   1,   1,  3,  6,  19,
            6,  5,  1,  16, 6,  2,  10, 8,  5,  1,  2,  3,  1,  5,  5,  1,  11,  6,   6,  1,  3,  3,  2,  6,  3,  8,   1,   1,  4,  10, 7,  5,  7,  7,  5,  8,   9,  2,  1,  3,  4,   1,  1,  3,   1,  3,  3,  2,   6,  16,  1,  4,  6,  3,  1,   10,  6,   1,   3,   15, 2,  9,   2,  10,  25,  13, 9,  16, 6,
            2,  2,  10, 11, 4,  3,  9,  1,  2,  6,  6,  5,  4,  30, 40, 1,  10,  7,   12, 14, 33, 6,  3,  6,  7,  3,   1,   3,  1,  11, 14, 4,  9,  5,  12, 11,  49, 18, 51, 31, 140, 31, 2,  2,   1,  5,  1,  8,   1,  10,  1,  4,  4,  3,  24,  1,   10,  1,   3,   6,  6,  16,  3,  4,   5,   2,  1,  4,  2,
            57, 10, 6,  22, 2,  22, 3,  7,  22, 6,  10, 11, 36, 18, 16, 33, 36,  2,   5,  5,  1,  1,  1,  4,  10, 1,   4,   13, 2,  7,  5,  2,  9,  3,  4,  1,   7,  43, 3,  7,  3,   9,  14, 7,   9,  1,  11, 1,   1,  3,   7,  4,  18, 13, 1,   14,  1,   3,   6,   10, 73, 2,   2,  30,  6,   1,  11, 18, 19,
            13, 22, 3,  46, 42, 37, 89, 7,  3,  16, 34, 2,  2,  3,  9,  1,  7,   1,   1,  1,  2,  2,  4,  10, 7,  3,   10,  3,  9,  5,  28, 9,  2,  6,  13, 7,   3,  1,  3,  10, 2,   7,  2,  11,  3,  6,  21, 54,  85, 2,   1,  4,  2,  2,  1,   39,  3,   21,  2,   2,  5,  1,   1,  1,   4,   1,  1,  3,  4,
            15, 1,  3,  2,  4,  4,  2,  3,  8,  2,  20, 1,  8,  7,  13, 4,  1,   26,  6,  2,  9,  34, 4,  21, 52, 10,  4,   4,  1,  5,  12, 2,  11, 1,  7,  2,   30, 12, 44, 2,  30,  1,  1,  3,   6,  16, 9,  17,  39, 82,  2,  2,  24, 7,  1,   7,   3,   16,  9,   14, 44, 2,   1,  2,   1,   2,  3,  5,  2,
            4,  1,  6,  7,  5,  3,  2,  6,  1,  11, 5,  11, 2,  1,  18, 19, 8,   1,   3,  24, 29, 2,  1,  3,  5,  2,   2,   1,  13, 6,  5,  1,  46, 11, 3,  5,   1,  1,  5,  8,  2,   10, 6,  12,  6,  3,  7,  11,  2,  4,   16, 13, 2,  5,  1,   1,   2,   2,   5,   2,  28, 5,   2,  23,  10,  8,  4,  4,  22,
            39, 95, 38, 8,  14, 9,  5,  1,  13, 5,  4,  3,  13, 12, 11, 1,  9,   1,   27, 37, 2,  5,  4,  4,  63, 211, 95,  2,  2,  2,  1,  3,  5,  2,  1,  1,   2,  2,  1,  1,  1,   3,  2,  4,   1,  2,  1,  1,   5,  2,   2,  1,  1,  2,  3,   1,   3,   1,   1,   1,  3,  1,   4,  2,   1,   3,  6,  1,  1,
            3,  7,  15, 5,  3,  2,  5,  3,  9,  11, 4,  2,  22, 1,  6,  3,  8,   7,   1,  4,  28, 4,  16, 3,  3,  25,  4,   4,  27, 27, 1,  4,  1,  2,  2,  7,   1,  3,  5,  2,  28,  8,  2,  14,  1,  8,  6,  16,  25, 3,   3,  3,  14, 3,  3,   1,   1,   2,   1,   4,  6,  3,   8,  4,   1,   1,  1,  2,  3,
            6,  10, 6,  2,  3,  18, 3,  2,  5,  5,  4,  3,  1,  5,  2,  5,  4,   23,  7,  6,  12, 6,  4,  17, 11, 9,   5,   1,  1,  10, 5,  12, 1,  1,  11, 26,  33, 7,  3,  6,  1,   17, 7,  1,   5,  12, 1,  11,  2,  4,   1,  8,  14, 17, 23,  1,   2,   1,   7,   8,  16, 11,  9,  6,   5,   2,  6,  4,  16,
            2,  8,  14, 1,  11, 8,  9,  1,  1,  1,  9,  25, 4,  11, 19, 7,  2,   15,  2,  12, 8,  52, 7,  5,  19, 2,   16,  4,  36, 8,  1,  16, 8,  24, 26, 4,   6,  2,  9,  5,  4,   36, 3,  28,  12, 25, 15, 37,  27, 17,  12, 59, 38, 5,  32,  127, 1,   2,   9,   17, 14, 4,   1,  2,   1,   1,  8,  11, 50,
            4,  14, 2,  19, 16, 4,  17, 5,  4,  5,  26, 12, 45, 2,  23, 45, 104, 30,  12, 8,  3,  10, 2,  2,  3,  3,   1,   4,  20, 7,  2,  9,  6,  15, 2,  20,  1,  3,  16, 4,  11,  15, 6,  134, 2,  5,  59, 1,   2,  2,   2,  1,  9,  17, 3,   26,  137, 10,  211, 59, 1,  2,   4,  1,   4,   1,  1,  1,  2,
            6,  2,  3,  1,  1,  2,  3,  2,  3,  1,  3,  4,  4,  2,  3,  3,  1,   4,   3,  1,  7,  2,  2,  3,  1,  2,   1,   3,  3,  3,  2,  2,  3,  2,  1,  3,   14, 6,  1,  3,  2,   9,  6,  15,  27, 9,  34, 145, 1,  1,   2,  1,  1,  1,  1,   2,   1,   1,   1,   1,  2,  2,   2,  3,   1,   2,  1,  1,  1,
            2,  3,  5,  8,  3,  5,  2,  4,  1,  3,  2,  2,  2,  12, 4,  1,  1,   1,   10, 4,  5,  1,  20, 4,  16, 1,   15,  9,  5,  12, 2,  9,  2,  5,  4,  2,   26, 19, 7,  1,  26,  4,  30, 12,  15, 42, 1,  6,   8,  172, 1,  1,  4,  2,  1,   1,   11,  2,   2,   4,  2,  1,   2,  1,   10,  8,  1,  2,  1,
            4,  5,  1,  2,  5,  1,  8,  4,  1,  3,  4,  2,  1,  6,  2,  1,  3,   4,   1,  2,  1,  1,  1,  1,  12, 5,   7,   2,  4,  3,  1,  1,  1,  3,  3,  6,   1,  2,  2,  3,  3,   3,  2,  1,   2,  12, 14, 11,  6,  6,   4,  12, 2,  8,  1,   7,   10,  1,   35,  7,  4,  13,  15, 4,   3,   23, 21, 28, 52,
            5,  26, 5,  6,  1,  7,  10, 2,  7,  53, 3,  2,  1,  1,  1,  2,  163, 532, 1,  10, 11, 1,  3,  3,  4,  8,   2,   8,  6,  2,  2,  23, 22, 4,  2,  2,   4,  2,  1,  3,  1,   3,  3,  5,   9,  8,  2,  1,   2,  8,   1,  10, 2,  12, 21,  20,  15,  105, 2,   3,  1,  1,   3,  2,   3,   1,  1,  2,  5,
            1,  4,  15, 11, 19, 1,  1,  1,  1,  5,  4,  5,  1,  1,  2,  5,  3,   5,   12, 1,  2,  5,  1,  11, 1,  1,   15,  9,  1,  4,  5,  3,  26, 8,  2,  1,   3,  1,  1,  15, 19,  2,  12, 1,   2,  5,  2,  7,   2,  19,  2,  20, 6,  26, 7,   5,   2,   2,   7,   34, 21, 13,  70, 2,   128, 1,  1,  2,  1,
            1,  2,  1,  1,  3,  2,  2,  2,  15, 1,  4,  1,  3,  4,  42, 10, 6,   1,   49, 85, 8,  1,  2,  1,  1,  4,   4,   2,  3,  6,  1,  5,  7,  4,  3,  211, 4,  1,  2,  1,  2,   5,  1,  2,   4,  2,  2,  6,   5,  6,   10, 3,  4,  48, 100, 6,   2,   16,  296, 5,  27, 387, 2,  2,   3,   7,  16, 8,  5,
            38, 15, 39, 21, 9,  10, 3,  7,  59, 13, 27, 21, 47, 5,  21, 6,
        },
    );

    pub const lod_japanese = [_][2]u32{
        .{ 0x0020, 0x00FF },
        .{ 0x3041, 0x3096 }, // Hiragana
        .{ 0x30A1, 0x30FF }, // Katakana
        // .{ 0x3400, 0x4DB5 }, // CJK Unified Ideographs Extension A
        // .{ 0x4E00, 0x9FCB }, // CJK Unified Ideographs
        // .{ 0xF900, 0xFA6A }, // CJK Compatibility Ideographs
        // .{ 0x3000, 0x303F }, // CJK Symbols and Punctuations
        .{ 0, 0 },
    };

    pub const japanese = genRanges(
        &[_][2]u32{
            .{ 0x0020, 0x00FF }, // Basic Latin + Latin Supplement
            .{ 0x3000, 0x30FF }, // CJK Symbols and Punctuations, Hiragana, Katakana
            .{ 0x31F0, 0x31FF }, // Katakana Phonetic Extensions
            .{ 0xFF00, 0xFFEF }, // Half-width characters
            .{ 0xFFFD, 0xFFFD }, // Invalid
        },
        0x4E00,
        &[_]u32{
            0,  1,  2,  4,  1,   1,   1,  1,  2,  1,  3,  3,  2,  2,  1,  5,  3,  5,  7,  5,  6,  1,   2,  1,  7,  2,  6,   3,  1,  8,  1,  1,  4,  1,  1,  18, 2,  11, 2,  6,  2,  1,  2,  1,  5,     1,  2,  1,  3,   1,  2,  1,  2,  3,  3,  1,  1,  2,  3,  1,  1,  1,  12, 7,  9,  1,  4,  5,  1,
            1,  2,  1,  10, 1,   1,   9,  2,  2,  4,  5,  6,  9,  3,  1,  1,  1,  1,  9,  3,  18, 5,   2,  2,  2,  2,  1,   6,  3,  7,  1,  1,  1,  1,  2,  2,  4,  2,  1,  23, 2,  10, 4,  3,  5,     2,  4,  10, 2,   4,  13, 1,  6,  1,  9,  3,  1,  1,  6,  6,  7,  6,  3,  1,  2,  11, 3,  2,  2,
            3,  2,  15, 2,  2,   5,   4,  3,  6,  4,  1,  2,  5,  2,  12, 16, 6,  13, 9,  13, 2,  1,   1,  7,  16, 4,  7,   1,  19, 1,  5,  1,  2,  2,  7,  7,  8,  2,  6,  5,  4,  9,  18, 7,  4,     5,  9,  13, 11,  8,  15, 2,  1,  1,  1,  2,  1,  2,  2,  1,  2,  2,  8,  2,  9,  3,  3,  1,  1,
            4,  4,  1,  1,  1,   4,   9,  1,  4,  3,  5,  5,  2,  7,  5,  3,  4,  8,  2,  1,  13, 2,   3,  3,  1,  14, 1,   1,  4,  5,  1,  3,  6,  1,  5,  2,  1,  1,  3,  3,  3,  3,  1,  1,  2,     7,  6,  6,  7,   1,  4,  7,  6,  1,  1,  1,  1,  1,  12, 3,  3,  9,  5,  2,  6,  1,  5,  6,  1,
            2,  3,  18, 2,  4,   14,  4,  1,  3,  6,  1,  1,  6,  3,  5,  5,  3,  2,  2,  2,  2,  12,  3,  1,  4,  2,  3,   2,  3,  11, 1,  7,  4,  1,  2,  1,  3,  17, 1,  9,  1,  24, 1,  1,  4,     2,  2,  4,  1,   2,  7,  1,  1,  1,  3,  1,  2,  2,  4,  15, 1,  1,  2,  1,  1,  2,  1,  5,  2,
            5,  20, 2,  5,  9,   1,   10, 8,  7,  6,  1,  1,  1,  1,  1,  1,  6,  2,  1,  2,  8,  1,   1,  1,  1,  5,  1,   1,  3,  1,  1,  1,  1,  3,  1,  1,  12, 4,  1,  3,  1,  1,  1,  1,  1,     10, 3,  1,  7,   5,  13, 1,  2,  3,  4,  6,  1,  1,  30, 2,  9,  9,  1,  15, 38, 11, 3,  1,  8,
            24, 7,  1,  9,  8,   10,  2,  1,  9,  31, 2,  13, 6,  2,  9,  4,  49, 5,  2,  15, 2,  1,   10, 2,  1,  1,  1,   2,  2,  6,  15, 30, 35, 3,  14, 18, 8,  1,  16, 10, 28, 12, 19, 45, 38,    1,  3,  2,  3,   13, 2,  1,  7,  3,  6,  5,  3,  4,  3,  1,  5,  7,  8,  1,  5,  3,  18, 5,  3,
            6,  1,  21, 4,  24,  9,   24, 40, 3,  14, 3,  21, 3,  2,  1,  2,  4,  2,  3,  1,  15, 15,  6,  5,  1,  1,  3,   1,  5,  6,  1,  9,  7,  3,  3,  2,  1,  4,  3,  8,  21, 5,  16, 4,  5,     2,  10, 11, 11,  3,  6,  3,  2,  9,  3,  6,  13, 1,  2,  1,  1,  1,  1,  11, 12, 6,  6,  1,  4,
            2,  6,  5,  2,  1,   1,   3,  3,  6,  13, 3,  1,  1,  5,  1,  2,  3,  3,  14, 2,  1,  2,   2,  2,  5,  1,  9,   5,  1,  1,  6,  12, 3,  12, 3,  4,  13, 2,  14, 2,  8,  1,  17, 5,  1,     16, 4,  2,  2,   21, 8,  9,  6,  23, 20, 12, 25, 19, 9,  38, 8,  3,  21, 40, 25, 33, 13, 4,  3,
            1,  4,  1,  2,  4,   1,   2,  5,  26, 2,  1,  1,  2,  1,  3,  6,  2,  1,  1,  1,  1,  1,   1,  2,  3,  1,  1,   1,  9,  2,  3,  1,  1,  1,  3,  6,  3,  2,  1,  1,  6,  6,  1,  8,  2,     2,  2,  1,  4,   1,  2,  3,  2,  7,  3,  2,  4,  1,  2,  1,  2,  2,  1,  1,  1,  1,  1,  3,  1,
            2,  5,  4,  10, 9,   4,   9,  1,  1,  1,  1,  1,  1,  5,  3,  2,  1,  6,  4,  9,  6,  1,   10, 2,  31, 17, 8,   3,  7,  5,  40, 1,  7,  7,  1,  6,  5,  2,  10, 7,  8,  4,  15, 39, 25,    6,  28, 47, 18,  10, 7,  1,  3,  1,  1,  2,  1,  1,  1,  3,  3,  3,  1,  1,  1,  3,  4,  2,  1,
            4,  1,  3,  6,  10,  7,   8,  6,  2,  2,  1,  3,  3,  2,  5,  8,  7,  9,  12, 2,  15, 1,   1,  4,  1,  2,  1,   1,  1,  3,  2,  1,  3,  3,  5,  6,  2,  3,  2,  10, 1,  4,  2,  8,  1,     1,  1,  11, 6,   1,  21, 4,  16, 3,  1,  3,  1,  4,  2,  3,  6,  5,  1,  3,  1,  1,  3,  3,  4,
            6,  1,  1,  10, 4,   2,   7,  10, 4,  7,  4,  2,  9,  4,  3,  1,  1,  1,  4,  1,  8,  3,   4,  1,  3,  1,  6,   1,  4,  2,  1,  4,  7,  2,  1,  8,  1,  4,  5,  1,  1,  2,  2,  4,  6,     2,  7,  1,  10,  1,  1,  3,  4,  11, 10, 8,  21, 4,  6,  1,  3,  5,  2,  1,  2,  28, 5,  5,  2,
            3,  13, 1,  2,  3,   1,   4,  2,  1,  5,  20, 3,  8,  11, 1,  3,  3,  3,  1,  8,  10, 9,   2,  10, 9,  2,  3,   1,  1,  2,  4,  1,  8,  3,  6,  1,  7,  8,  6,  11, 1,  4,  29, 8,  4,     3,  1,  2,  7,   13, 1,  4,  1,  6,  2,  6,  12, 12, 2,  20, 3,  2,  3,  6,  4,  8,  9,  2,  7,
            34, 5,  1,  18, 6,   1,   1,  4,  4,  5,  7,  9,  1,  2,  2,  4,  3,  4,  1,  7,  2,  2,   2,  6,  2,  3,  25,  5,  3,  6,  1,  4,  6,  7,  4,  2,  1,  4,  2,  13, 6,  4,  4,  3,  1,     5,  3,  4,  4,   3,  2,  1,  1,  4,  1,  2,  1,  1,  3,  1,  11, 1,  6,  3,  1,  7,  3,  6,  2,
            8,  8,  6,  9,  3,   4,   11, 3,  2,  10, 12, 2,  5,  11, 1,  6,  4,  5,  3,  1,  8,  5,   4,  6,  6,  3,  5,   1,  1,  3,  2,  1,  2,  2,  6,  17, 12, 1,  10, 1,  6,  12, 1,  6,  6,     19, 9,  6,  16,  1,  13, 4,  4,  15, 7,  17, 6,  11, 9,  15, 12, 6,  7,  2,  1,  2,  2,  15, 9,
            3,  21, 4,  6,  49,  18,  7,  3,  2,  3,  1,  6,  8,  2,  2,  6,  2,  9,  1,  3,  6,  4,   4,  1,  2,  16, 2,   5,  2,  1,  6,  2,  3,  5,  3,  1,  2,  5,  1,  2,  1,  9,  3,  1,  8,     6,  4,  8,  11,  3,  1,  1,  1,  1,  3,  1,  13, 8,  4,  1,  3,  2,  2,  1,  4,  1,  11, 1,  5,
            2,  1,  5,  2,  5,   8,   6,  1,  1,  7,  4,  3,  8,  3,  2,  7,  2,  1,  5,  1,  5,  2,   4,  7,  6,  2,  8,   5,  1,  11, 4,  5,  3,  6,  18, 1,  2,  13, 3,  3,  1,  21, 1,  1,  4,     1,  4,  1,  1,   1,  8,  1,  2,  2,  7,  1,  2,  4,  2,  2,  9,  2,  1,  1,  1,  4,  3,  6,  3,
            12, 5,  1,  1,  1,   5,   6,  3,  2,  4,  8,  2,  2,  4,  2,  7,  1,  8,  9,  5,  2,  3,   2,  1,  3,  2,  13,  7,  14, 6,  5,  1,  1,  2,  1,  4,  2,  23, 2,  1,  1,  6,  3,  1,  4,     1,  15, 3,  1,   7,  3,  9,  14, 1,  3,  1,  4,  1,  1,  5,  8,  1,  3,  8,  3,  8,  15, 11, 4,
            14, 4,  4,  2,  5,   5,   1,  7,  1,  6,  14, 7,  7,  8,  5,  15, 4,  8,  6,  5,  6,  2,   1,  13, 1,  20, 15,  11, 9,  2,  5,  6,  2,  11, 2,  6,  2,  5,  1,  5,  8,  4,  13, 19, 25,    4,  1,  1,  11,  1,  34, 2,  5,  9,  14, 6,  2,  2,  6,  1,  1,  14, 1,  3,  14, 13, 1,  6,  12,
            21, 14, 14, 6,  32,  17,  8,  32, 9,  28, 1,  2,  4,  11, 8,  3,  1,  14, 2,  5,  15, 1,   1,  1,  1,  3,  6,   4,  1,  3,  4,  11, 3,  1,  1,  11, 30, 1,  5,  1,  4,  1,  5,  8,  1,     1,  3,  2,  4,   3,  17, 35, 2,  6,  12, 17, 3,  1,  6,  2,  1,  1,  12, 2,  7,  3,  3,  2,  1,
            16, 2,  8,  3,  6,   5,   4,  7,  3,  3,  8,  1,  9,  8,  5,  1,  2,  1,  3,  2,  8,  1,   2,  9,  12, 1,  1,   2,  3,  8,  3,  24, 12, 4,  3,  7,  5,  8,  3,  3,  3,  3,  3,  3,  1,     23, 10, 3,  1,   2,  2,  6,  3,  1,  16, 1,  16, 22, 3,  10, 4,  11, 6,  9,  7,  7,  3,  6,  2,
            2,  2,  4,  10, 2,   1,   1,  2,  8,  7,  1,  6,  4,  1,  3,  3,  3,  5,  10, 12, 12, 2,   3,  12, 8,  15, 1,   1,  16, 6,  6,  1,  5,  9,  11, 4,  11, 4,  2,  6,  12, 1,  17, 5,  13,    1,  4,  9,  5,   1,  11, 2,  1,  8,  1,  5,  7,  28, 8,  3,  5,  10, 2,  17, 3,  38, 22, 1,  2,
            18, 12, 10, 4,  38,  18,  1,  4,  44, 19, 4,  1,  8,  4,  1,  12, 1,  4,  31, 12, 1,  14,  7,  75, 7,  5,  10,  6,  6,  13, 3,  2,  11, 11, 3,  2,  5,  28, 15, 6,  18, 18, 5,  6,  4,     3,  16, 1,  7,   18, 7,  36, 3,  5,  3,  1,  7,  1,  9,  1,  10, 7,  2,  4,  2,  6,  2,  9,  7,
            4,  3,  32, 12, 3,   7,   10, 2,  23, 16, 3,  1,  12, 3,  31, 4,  11, 1,  3,  8,  9,  5,   1,  30, 15, 6,  12,  3,  2,  2,  11, 19, 9,  14, 2,  6,  2,  3,  19, 13, 17, 5,  3,  3,  25,    3,  14, 1,  1,   1,  36, 1,  3,  2,  19, 3,  13, 36, 9,  13, 31, 6,  4,  16, 34, 2,  5,  4,  2,
            3,  3,  5,  1,  1,   1,   4,  3,  1,  17, 3,  2,  3,  5,  3,  1,  3,  2,  3,  5,  6,  3,   12, 11, 1,  3,  1,   2,  26, 7,  12, 7,  2,  14, 3,  3,  7,  7,  11, 25, 25, 28, 16, 4,  36,    1,  2,  1,  6,   2,  1,  9,  3,  27, 17, 4,  3,  4,  13, 4,  1,  3,  2,  2,  1,  10, 4,  2,  4,
            6,  3,  8,  2,  1,   18,  1,  1,  24, 2,  2,  4,  33, 2,  3,  63, 7,  1,  6,  40, 7,  3,   4,  4,  2,  4,  15,  18, 1,  16, 1,  1,  11, 2,  41, 14, 1,  3,  18, 13, 3,  2,  4,  16, 2,     17, 7,  15, 24,  7,  18, 13, 44, 2,  2,  3,  6,  1,  1,  7,  5,  1,  7,  1,  4,  3,  3,  5,  10,
            8,  2,  3,  1,  8,   1,   1,  27, 4,  2,  1,  12, 1,  2,  1,  10, 6,  1,  6,  7,  5,  2,   3,  7,  11, 5,  11,  3,  6,  6,  2,  3,  15, 4,  9,  1,  1,  2,  1,  2,  11, 2,  8,  12, 8,     5,  4,  2,  3,   1,  5,  2,  2,  1,  14, 1,  12, 11, 4,  1,  11, 17, 17, 4,  3,  2,  5,  5,  7,
            3,  1,  5,  9,  9,   8,   2,  5,  6,  6,  13, 13, 2,  1,  2,  6,  1,  2,  2,  49, 4,  9,   1,  2,  10, 16, 7,   8,  4,  3,  2,  23, 4,  58, 3,  29, 1,  14, 19, 19, 11, 11, 2,  7,  5,     1,  3,  4,  6,   2,  18, 5,  12, 12, 17, 17, 3,  3,  2,  4,  1,  6,  2,  3,  4,  3,  1,  1,  1,
            1,  5,  1,  1,  9,   1,   3,  1,  3,  6,  1,  8,  1,  1,  2,  6,  4,  14, 3,  1,  4,  11,  4,  1,  3,  32, 1,   2,  4,  13, 4,  1,  2,  4,  2,  1,  3,  1,  11, 1,  4,  2,  1,  4,  4,     6,  3,  5,  1,   6,  5,  7,  6,  3,  23, 3,  5,  3,  5,  3,  3,  13, 3,  9,  10, 1,  12, 10, 2,
            3,  18, 13, 7,  160, 52,  4,  2,  2,  3,  2,  14, 5,  4,  12, 4,  6,  4,  1,  20, 4,  11,  6,  2,  12, 27, 1,   4,  1,  2,  2,  7,  4,  5,  2,  28, 3,  7,  25, 8,  3,  19, 3,  6,  10,    2,  2,  1,  10,  2,  5,  4,  1,  3,  4,  1,  5,  3,  2,  6,  9,  3,  6,  2,  16, 3,  3,  16, 4,
            5,  5,  3,  2,  1,   2,   16, 15, 8,  2,  6,  21, 2,  4,  1,  22, 5,  8,  1,  1,  21, 11,  2,  1,  11, 11, 19,  13, 12, 4,  2,  3,  2,  3,  6,  1,  8,  11, 1,  4,  2,  9,  5,  2,  1,     11, 2,  9,  1,   1,  2,  14, 31, 9,  3,  4,  21, 14, 4,  8,  1,  7,  2,  2,  2,  5,  1,  4,  20,
            3,  3,  4,  10, 1,   11,  9,  8,  2,  1,  4,  5,  14, 12, 14, 2,  17, 9,  6,  31, 4,  14,  1,  20, 13, 26, 5,   2,  7,  3,  6,  13, 2,  4,  2,  19, 6,  2,  2,  18, 9,  3,  5,  12, 12,    14, 4,  6,  2,   3,  6,  9,  5,  22, 4,  5,  25, 6,  4,  8,  5,  2,  6,  27, 2,  35, 2,  16, 3,
            7,  8,  8,  6,  6,   5,   9,  17, 2,  20, 6,  19, 2,  13, 3,  1,  1,  1,  4,  17, 12, 2,   14, 7,  1,  4,  18,  12, 38, 33, 2,  10, 1,  1,  2,  13, 14, 17, 11, 50, 6,  33, 20, 26, 74,    16, 23, 45, 50,  13, 38, 33, 6,  6,  7,  4,  4,  2,  1,  3,  2,  5,  8,  7,  8,  9,  3,  11, 21,
            9,  13, 1,  3,  10,  6,   7,  1,  2,  2,  18, 5,  5,  1,  9,  9,  2,  68, 9,  19, 13, 2,   5,  1,  4,  4,  7,   4,  13, 3,  9,  10, 21, 17, 3,  26, 2,  1,  5,  2,  4,  5,  4,  1,  7,     4,  7,  3,  4,   2,  1,  6,  1,  1,  20, 4,  1,  9,  2,  2,  1,  3,  3,  2,  3,  2,  1,  1,  1,
            20, 2,  3,  1,  6,   2,   3,  6,  2,  4,  8,  1,  3,  2,  10, 3,  5,  3,  4,  4,  3,  4,   16, 1,  6,  1,  10,  2,  4,  2,  1,  1,  2,  10, 11, 2,  2,  3,  1,  24, 31, 4,  10, 10, 2,     5,  12, 16, 164, 15, 4,  16, 7,  9,  15, 19, 17, 1,  2,  1,  1,  5,  1,  1,  1,  1,  1,  3,  1,
            4,  3,  1,  3,  1,   3,   1,  2,  1,  1,  3,  3,  7,  2,  8,  1,  2,  2,  2,  1,  3,  4,   3,  7,  8,  12, 92,  2,  10, 3,  1,  3,  14, 5,  25, 16, 42, 4,  7,  7,  4,  2,  21, 5,  27,    26, 27, 21, 25,  30, 31, 2,  1,  5,  13, 3,  22, 5,  6,  6,  11, 9,  12, 1,  5,  9,  7,  5,  5,
            22, 60, 3,  5,  13,  1,   1,  8,  1,  1,  3,  3,  2,  1,  9,  3,  3,  18, 4,  1,  2,  3,   7,  6,  3,  1,  2,   3,  9,  1,  3,  1,  3,  2,  1,  3,  1,  1,  1,  2,  1,  11, 3,  1,  6,     9,  1,  3,  2,   3,  1,  2,  1,  5,  1,  1,  4,  3,  4,  1,  2,  2,  4,  4,  1,  7,  2,  1,  2,
            2,  3,  5,  13, 18,  3,   4,  14, 9,  9,  4,  16, 3,  7,  5,  8,  2,  6,  48, 28, 3,  1,   1,  4,  2,  14, 8,   2,  9,  2,  1,  15, 2,  4,  3,  2,  10, 16, 12, 8,  7,  1,  1,  3,  1,     1,  1,  2,  7,   4,  1,  6,  4,  38, 39, 16, 23, 7,  15, 15, 3,  2,  12, 7,  21, 37, 27, 6,  5,
            4,  8,  2,  10, 8,   8,   6,  5,  1,  2,  1,  3,  24, 1,  16, 17, 9,  23, 10, 17, 6,  1,   51, 55, 44, 13, 294, 9,  3,  6,  2,  4,  2,  2,  15, 1,  1,  1,  13, 21, 17, 68, 14, 8,  9,     4,  1,  4,  9,   3,  11, 7,  1,  1,  1,  5,  6,  3,  2,  1,  1,  1,  2,  3,  8,  1,  2,  2,  4,
            1,  5,  5,  2,  1,   4,   3,  7,  13, 4,  1,  4,  1,  3,  1,  1,  1,  5,  5,  10, 1,  6,   1,  5,  2,  1,  5,   2,  4,  1,  4,  5,  7,  3,  18, 2,  9,  11, 32, 4,  3,  3,  2,  4,  7,     11, 16, 9,  11,  8,  13, 38, 32, 8,  4,  2,  1,  1,  2,  1,  2,  4,  4,  1,  1,  1,  4,  1,  21,
            3,  11, 1,  16, 1,   1,   6,  1,  3,  2,  4,  9,  8,  57, 7,  44, 1,  3,  3,  13, 3,  10,  1,  1,  7,  5,  2,   7,  21, 47, 63, 3,  15, 4,  7,  1,  16, 1,  1,  2,  8,  2,  3,  42, 15,    4,  1,  29, 7,   22, 10, 3,  78, 16, 12, 20, 18, 4,  67, 11, 5,  1,  3,  15, 6,  21, 31, 32, 27,
            18, 13, 71, 35, 5,   142, 4,  10, 1,  2,  50, 19, 33, 16, 35, 37, 16, 19, 27, 7,  1,  133, 19, 1,  4,  8,  7,   20, 1,  4,  4,  1,  10, 3,  1,  6,  1,  2,  51, 5,  40, 15, 24, 43, 22928, 11, 1,  13, 154, 70, 3,  1,  1,  7,  4,  10, 1,  2,  1,  1,  2,  1,  2,  1,  2,  2,  1,  1,  2,
            1,  1,  1,  1,  1,   2,   1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  2,  1,  1,   1,  3,  2,  1,  1,   1,  1,  2,  1,  1,
        },
    );

    pub const korean = [_][2]u32{
        .{ 0x0020, 0x00FF }, // Basic Latin + Latin Supplement
        .{ 0x3131, 0x3163 }, // Korean alphabets
        .{ 0xAC00, 0xD7A3 }, // Korean characters
        .{ 0xFFFD, 0xFFFD }, // Invalid
        .{ 0, 0 },
    };

    pub const cp437 = genRanges2(
        &[_]u32{
            0x00,   0x263A, 0x263B, 0x2665, 0x2666, 0x2663, 0x2660, 0x2022,
            0x25D8, 0x25CB, 0x25D9, 0x2642, 0x2640, 0x266A, 0x266B, 0x263C,
            0x25BA, 0x25C4, 0x2195, 0x203C, 0xB6,   0xA7,   0x25AC, 0x21A8,
            0x2191, 0x2193, 0x2192, 0x2190, 0x221F, 0x2194, 0x25B2, 0x25BC,
            0x20,   0x21,   0x22,   0x23,   0x24,   0x25,   0x26,   0x27,
            0x28,   0x29,   0x2A,   0x2B,   0x2C,   0x2D,   0x2E,   0x2F,
            0x30,   0x31,   0x32,   0x33,   0x34,   0x35,   0x36,   0x37,
            0x38,   0x39,   0x3A,   0x3B,   0x3C,   0x3D,   0x3E,   0x3F,
            0x40,   0x41,   0x42,   0x43,   0x44,   0x45,   0x46,   0x47,
            0x48,   0x49,   0x4A,   0x4B,   0x4C,   0x4D,   0x4E,   0x4F,
            0x50,   0x51,   0x52,   0x53,   0x54,   0x55,   0x56,   0x57,
            0x58,   0x59,   0x5A,   0x5B,   0x5C,   0x5D,   0x5E,   0x5F,
            0x60,   0x61,   0x62,   0x63,   0x64,   0x65,   0x66,   0x67,
            0x68,   0x69,   0x6A,   0x6B,   0x6C,   0x6D,   0x6E,   0x6F,
            0x70,   0x71,   0x72,   0x73,   0x74,   0x75,   0x76,   0x77,
            0x78,   0x79,   0x7A,   0x7B,   0x7C,   0x7D,   0x7E,   0x2302,
            0xC7,   0xFC,   0xE9,   0xE2,   0xE4,   0xE0,   0xE5,   0xE7,
            0xEA,   0xEB,   0xE8,   0xEF,   0xEE,   0xEC,   0xC4,   0xC5,
            0xC9,   0xE6,   0xC6,   0xF4,   0xF6,   0xF2,   0xFB,   0xF9,
            0xFF,   0xD6,   0xDC,   0xA2,   0xA3,   0xA5,   0x20A7, 0x0192,
            0xE1,   0xED,   0xF3,   0xFA,   0xF1,   0xD1,   0xAA,   0xBA,
            0xBF,   0x2310, 0xAC,   0xBD,   0xBC,   0xA1,   0xAB,   0xBB,
            0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556,
            0x2555, 0x2563, 0x2551, 0x2557, 0x255D, 0x255C, 0x255B, 0x2510,
            0x2514, 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x255E, 0x255F,
            0x255A, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256C, 0x2567,
            0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256B,
            0x256A, 0x2518, 0x250C, 0x2588, 0x2584, 0x258C, 0x2590, 0x2580,
            0x03B1, 0xDF,   0x0393, 0x03C0, 0x03A3, 0x03C3, 0xB5,   0x03C4,
            0x03A6, 0x0398, 0x03A9, 0x03B4, 0x221E, 0x03C6, 0x03B5, 0x2229,
            0x2261, 0xB1,   0x2265, 0x2264, 0x2320, 0x2321, 0xF7,   0x2248,
            0xB0,   0x2219, 0xB7,   0x221A, 0x207F, 0xB2,   0x25A0, 0xA0,
        },
    );

    pub const braille = [_][2]u32{
        .{ 0x2800, 0x28FF },
        .{ 0, 0 },
    };

    pub fn genRanges(
        comptime base_ranges: []const [2]u32,
        comptime base_codepoint: u32,
        comptime offsets: []const u32,
    ) [base_ranges.len + offsets.len + 1][2]u32 {
        var ranges: [base_ranges.len + offsets.len + 1][2]u32 = undefined;
        @memcpy(ranges[0..base_ranges.len], base_ranges);
        unpackAccumulativeOffsets(
            base_codepoint,
            offsets,
            ranges[base_ranges.len .. ranges.len - 1],
        );
        ranges[ranges.len - 1][0] = 0;
        ranges[ranges.len - 1][1] = 0;
        return ranges;
    }

    pub fn genRanges2(comptime codepoints: []const u32) [codepoints.len + 1][2]u32 {
        var ranges: [codepoints.len + 1][2]u32 = undefined;
        for (codepoints, 0..) |c, i| {
            ranges[i][0] = c;
            ranges[i][1] = c;
        }
        ranges[ranges.len - 1][0] = 0;
        ranges[ranges.len - 1][1] = 0;
        return ranges;
    }

    fn unpackAccumulativeOffsets(
        comptime _base_codepoint: u32,
        comptime offsets: []const u32,
        comptime results: [][2]u32,
    ) void {
        @setEvalBranchQuota(10000);
        std.debug.assert(offsets.len == results.len);
        var base_codepoint = _base_codepoint;
        for (offsets, 0..) |off, i| {
            base_codepoint += off;
            results[i][0] = base_codepoint;
            results[i][1] = base_codepoint;
        }
    }
};
