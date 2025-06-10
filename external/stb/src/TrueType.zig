const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

const TrueType = @This();
const root = @import("root.zig");
const Rectpack = @import("Rectpack.zig");

const enum_unnamed_1 = c_uint;
pub const _buf = extern struct {
    data: [*c]u8 = null,
    cursor: c_int = 0,
    size: c_int = 0,
};
pub const bakedchar = extern struct {
    x0: c_ushort = 0,
    y0: c_ushort = 0,
    x1: c_ushort = 0,
    y1: c_ushort = 0,
    xoff: f32 = 0.0,
    yoff: f32 = 0.0,
    xadvance: f32 = 0.0,
};
pub const BakeFontBitmap = stbtt_BakeFontBitmap;
extern fn stbtt_BakeFontBitmap(data: [*c]const u8, offset: c_int, pixel_height: f32, pixels: [*c]u8, pw: c_int, ph: c_int, first_char: c_int, num_chars: c_int, chardata: [*c]bakedchar) c_int;
pub const aligned_quad = extern struct {
    x0: f32 = 0.0,
    y0: f32 = 0.0,
    s0: f32 = 0.0,
    t0: f32 = 0.0,
    x1: f32 = 0.0,
    y1: f32 = 0.0,
    s1: f32 = 0.0,
    t1: f32 = 0.0,
};
pub const GetBakedQuad = stbtt_GetBakedQuad;
extern fn stbtt_GetBakedQuad(chardata: [*c]const bakedchar, pw: c_int, ph: c_int, char_index: c_int, xpos: [*c]f32, ypos: [*c]f32, q: [*c]aligned_quad, opengl_fillrule: c_int) void;
pub const GetScaledFontVMetrics = stbtt_GetScaledFontVMetrics;
extern fn stbtt_GetScaledFontVMetrics(fontdata: [*c]const u8, index: c_int, size: f32, ascent: [*c]f32, descent: [*c]f32, lineGap: [*c]f32) void;
pub const packedchar = extern struct {
    x0: c_ushort = 0,
    y0: c_ushort = 0,
    x1: c_ushort = 0,
    y1: c_ushort = 0,
    xoff: f32 = 0,
    yoff: f32 = 0,
    xadvance: f32 = 0,
    xoff2: f32 = 0,
    yoff2: f32 = 0,
};
pub const pack_context = extern struct {
    user_allocator_context: ?*anyopaque = null,
    pack_info: ?*anyopaque = null,
    width: c_int = 0,
    height: c_int = 0,
    stride_in_bytes: c_int = 0,
    padding: c_int = 0,
    skip_missing: c_int = 0,
    h_oversample: c_uint = 0,
    v_oversample: c_uint = 0,
    pixels: [*c]u8 = null,
    nodes: ?*anyopaque = null,
};
pub const fontinfo = extern struct {
    userdata: ?*anyopaque = null,
    data: [*c]u8 = null,
    fontstart: c_int = 0,
    numGlyphs: c_int = 0,
    loca: c_int = 0,
    head: c_int = 0,
    glyf: c_int = 0,
    hhea: c_int = 0,
    hmtx: c_int = 0,
    kern: c_int = 0,
    gpos: c_int = 0,
    svg: c_int = 0,
    index_map: c_int = 0,
    indexToLocFormat: c_int = 0,
    cff: _buf = .{},
    charstrings: _buf = .{},
    gsubrs: _buf = .{},
    subrs: _buf = .{},
    fontdicts: _buf = .{},
    fdselect: _buf = .{},
};
pub const PackBegin = stbtt_PackBegin;
extern fn stbtt_PackBegin(spc: [*c]pack_context, pixels: [*c]u8, width: c_int, height: c_int, stride_in_bytes: c_int, padding: c_int, alloc_context: ?*anyopaque) c_int;
pub const PackEnd = stbtt_PackEnd;
extern fn stbtt_PackEnd(spc: [*c]pack_context) void;
pub const PackFontRange = stbtt_PackFontRange;
extern fn stbtt_PackFontRange(spc: [*c]pack_context, fontdata: [*c]const u8, font_index: c_int, font_size: f32, first_unicode_char_in_range: c_int, num_chars_in_range: c_int, chardata_for_range: [*c]packedchar) c_int;
pub const pack_range = extern struct {
    font_size: f32 = 0.0,
    first_unicode_codepoint_in_range: c_int = 0,
    array_of_unicode_codepoints: [*c]c_int = null,
    num_chars: c_int = 0,
    chardata_for_range: [*c]packedchar = null,
    h_oversample: u8 = 0,
    v_oversample: u8 = 0,
};
pub const PackFontRanges = stbtt_PackFontRanges;
extern fn stbtt_PackFontRanges(spc: [*c]pack_context, fontdata: [*c]const u8, font_index: c_int, ranges: [*c]pack_range, num_ranges: c_int) c_int;
pub const PackSetOversampling = stbtt_PackSetOversampling;
extern fn stbtt_PackSetOversampling(spc: [*c]pack_context, h_oversample: c_uint, v_oversample: c_uint) void;
pub const PackSetSkipMissingCodepoints = stbtt_PackSetSkipMissingCodepoints;
extern fn stbtt_PackSetSkipMissingCodepoints(spc: [*c]pack_context, skip: c_int) void;
pub const GetPackedQuad = stbtt_GetPackedQuad;
extern fn stbtt_GetPackedQuad(chardata: [*c]const packedchar, pw: c_int, ph: c_int, char_index: c_int, xpos: [*c]f32, ypos: [*c]f32, q: [*c]aligned_quad, align_to_integer: c_int) void;
pub const PackFontRangesGatherRects = stbtt_PackFontRangesGatherRects;
extern fn stbtt_PackFontRangesGatherRects(spc: [*c]pack_context, info: [*c]const fontinfo, ranges: [*c]pack_range, num_ranges: c_int, rects: [*c]Rectpack.rect) c_int;
pub const PackFontRangesPackRects = stbtt_PackFontRangesPackRects;
extern fn stbtt_PackFontRangesPackRects(spc: [*c]pack_context, rects: [*c]Rectpack.rect, num_rects: c_int) void;
pub const PackFontRangesRenderIntoRects = stbtt_PackFontRangesRenderIntoRects;
extern fn stbtt_PackFontRangesRenderIntoRects(spc: [*c]pack_context, info: [*c]const fontinfo, ranges: [*c]pack_range, num_ranges: c_int, rects: [*c]Rectpack.rect) c_int;
pub const GetNumberOfFonts = stbtt_GetNumberOfFonts;
extern fn stbtt_GetNumberOfFonts(data: [*c]const u8) c_int;
pub const GetFontOffsetForIndex = stbtt_GetFontOffsetForIndex;
extern fn stbtt_GetFontOffsetForIndex(data: [*c]const u8, index: c_int) c_int;
pub const InitFont = stbtt_InitFont;
extern fn stbtt_InitFont(info: [*c]fontinfo, data: [*c]const u8, offset: c_int) c_int;
pub const FindGlyphIndex = stbtt_FindGlyphIndex;
extern fn stbtt_FindGlyphIndex(info: [*c]const fontinfo, unicode_codepoint: c_int) c_int;
pub const ScaleForPixelHeight = stbtt_ScaleForPixelHeight;
extern fn stbtt_ScaleForPixelHeight(info: [*c]const fontinfo, pixels: f32) f32;
pub const ScaleForMappingEmToPixels = stbtt_ScaleForMappingEmToPixels;
extern fn stbtt_ScaleForMappingEmToPixels(info: [*c]const fontinfo, pixels: f32) f32;
pub const GetFontVMetrics = stbtt_GetFontVMetrics;
extern fn stbtt_GetFontVMetrics(info: [*c]const fontinfo, ascent: [*c]c_int, descent: [*c]c_int, lineGap: [*c]c_int) void;
pub const GetFontVMetricsOS2 = stbtt_GetFontVMetricsOS2;
extern fn stbtt_GetFontVMetricsOS2(info: [*c]const fontinfo, typoAscent: [*c]c_int, typoDescent: [*c]c_int, typoLineGap: [*c]c_int) c_int;
pub const GetFontBoundingBox = stbtt_GetFontBoundingBox;
extern fn stbtt_GetFontBoundingBox(info: [*c]const fontinfo, x0: [*c]c_int, y0: [*c]c_int, x1: [*c]c_int, y1: [*c]c_int) void;
pub const GetCodepointHMetrics = stbtt_GetCodepointHMetrics;
extern fn stbtt_GetCodepointHMetrics(info: [*c]const fontinfo, codepoint: c_int, advanceWidth: [*c]c_int, leftSideBearing: [*c]c_int) void;
pub const GetCodepointKernAdvance = stbtt_GetCodepointKernAdvance;
extern fn stbtt_GetCodepointKernAdvance(info: [*c]const fontinfo, ch1: c_int, ch2: c_int) c_int;
pub const GetCodepointBox = stbtt_GetCodepointBox;
extern fn stbtt_GetCodepointBox(info: [*c]const fontinfo, codepoint: c_int, x0: [*c]c_int, y0: [*c]c_int, x1: [*c]c_int, y1: [*c]c_int) c_int;
pub const GetGlyphHMetrics = stbtt_GetGlyphHMetrics;
extern fn stbtt_GetGlyphHMetrics(info: [*c]const fontinfo, glyph_index: c_int, advanceWidth: [*c]c_int, leftSideBearing: [*c]c_int) void;
pub const GetGlyphKernAdvance = stbtt_GetGlyphKernAdvance;
extern fn stbtt_GetGlyphKernAdvance(info: [*c]const fontinfo, glyph1: c_int, glyph2: c_int) c_int;
pub const GetGlyphBox = stbtt_GetGlyphBox;
extern fn stbtt_GetGlyphBox(info: [*c]const fontinfo, glyph_index: c_int, x0: [*c]c_int, y0: [*c]c_int, x1: [*c]c_int, y1: [*c]c_int) c_int;
pub const kerningentry = extern struct {
    glyph1: c_int = 0,
    glyph2: c_int = 0,
    advance: c_int = 0,
};
pub const GetKerningTableLength = stbtt_GetKerningTableLength;
extern fn stbtt_GetKerningTableLength(info: [*c]const fontinfo) c_int;
pub const GetKerningTable = stbtt_GetKerningTable;
extern fn stbtt_GetKerningTable(info: [*c]const fontinfo, table: [*c]kerningentry, table_length: c_int) c_int;
pub const vertex = extern struct {
    x: c_short = 0,
    y: c_short = 0,
    cx: c_short = 0,
    cy: c_short = 0,
    cx1: c_short = 0,
    cy1: c_short = 0,
    type: vertex_type = undefined,
    padding: u8 = 0,
};
pub const IsGlyphEmpty = stbtt_IsGlyphEmpty;
extern fn stbtt_IsGlyphEmpty(info: [*c]const fontinfo, glyph_index: c_int) c_int;
pub const GetCodepointShape = stbtt_GetCodepointShape;
extern fn stbtt_GetCodepointShape(info: [*c]const fontinfo, unicode_codepoint: c_int, vertices: [*c][*c]vertex) c_int;
pub const GetGlyphShape = stbtt_GetGlyphShape;
extern fn stbtt_GetGlyphShape(info: [*c]const fontinfo, glyph_index: c_int, vertices: [*c][*c]vertex) c_int;
pub const FreeShape = stbtt_FreeShape;
extern fn stbtt_FreeShape(info: [*c]const fontinfo, vertices: [*c]vertex) void;
pub const FindSVGDoc = stbtt_FindSVGDoc;
extern fn stbtt_FindSVGDoc(info: [*c]const fontinfo, gl: c_int) [*c]u8;
pub const GetCodepointSVG = stbtt_GetCodepointSVG;
extern fn stbtt_GetCodepointSVG(info: [*c]const fontinfo, unicode_codepoint: c_int, svg: [*c][*c]const u8) c_int;
pub const GetGlyphSVG = stbtt_GetGlyphSVG;
extern fn stbtt_GetGlyphSVG(info: [*c]const fontinfo, gl: c_int, svg: [*c][*c]const u8) c_int;
pub const FreeBitmap = stbtt_FreeBitmap;
extern fn stbtt_FreeBitmap(bitmap: [*c]u8, userdata: ?*anyopaque) void;
pub const GetCodepointBitmap = stbtt_GetCodepointBitmap;
extern fn stbtt_GetCodepointBitmap(info: [*c]const fontinfo, scale_x: f32, scale_y: f32, codepoint: c_int, width: [*c]c_int, height: [*c]c_int, xoff: [*c]c_int, yoff: [*c]c_int) [*c]u8;
pub const GetCodepointBitmapSubpixel = stbtt_GetCodepointBitmapSubpixel;
extern fn stbtt_GetCodepointBitmapSubpixel(info: [*c]const fontinfo, scale_x: f32, scale_y: f32, shift_x: f32, shift_y: f32, codepoint: c_int, width: [*c]c_int, height: [*c]c_int, xoff: [*c]c_int, yoff: [*c]c_int) [*c]u8;
pub const MakeCodepointBitmap = stbtt_MakeCodepointBitmap;
extern fn stbtt_MakeCodepointBitmap(info: [*c]const fontinfo, output: [*c]u8, out_w: c_int, out_h: c_int, out_stride: c_int, scale_x: f32, scale_y: f32, codepoint: c_int) void;
pub const MakeCodepointBitmapSubpixel = stbtt_MakeCodepointBitmapSubpixel;
extern fn stbtt_MakeCodepointBitmapSubpixel(info: [*c]const fontinfo, output: [*c]u8, out_w: c_int, out_h: c_int, out_stride: c_int, scale_x: f32, scale_y: f32, shift_x: f32, shift_y: f32, codepoint: c_int) void;
pub const MakeCodepointBitmapSubpixelPrefilter = stbtt_MakeCodepointBitmapSubpixelPrefilter;
extern fn stbtt_MakeCodepointBitmapSubpixelPrefilter(info: [*c]const fontinfo, output: [*c]u8, out_w: c_int, out_h: c_int, out_stride: c_int, scale_x: f32, scale_y: f32, shift_x: f32, shift_y: f32, oversample_x: c_int, oversample_y: c_int, sub_x: [*c]f32, sub_y: [*c]f32, codepoint: c_int) void;
pub const GetCodepointBitmapBox = stbtt_GetCodepointBitmapBox;
extern fn stbtt_GetCodepointBitmapBox(font: [*c]const fontinfo, codepoint: c_int, scale_x: f32, scale_y: f32, ix0: [*c]c_int, iy0: [*c]c_int, ix1: [*c]c_int, iy1: [*c]c_int) void;
pub const GetCodepointBitmapBoxSubpixel = stbtt_GetCodepointBitmapBoxSubpixel;
extern fn stbtt_GetCodepointBitmapBoxSubpixel(font: [*c]const fontinfo, codepoint: c_int, scale_x: f32, scale_y: f32, shift_x: f32, shift_y: f32, ix0: [*c]c_int, iy0: [*c]c_int, ix1: [*c]c_int, iy1: [*c]c_int) void;
pub const GetGlyphBitmap = stbtt_GetGlyphBitmap;
extern fn stbtt_GetGlyphBitmap(info: [*c]const fontinfo, scale_x: f32, scale_y: f32, glyph: c_int, width: [*c]c_int, height: [*c]c_int, xoff: [*c]c_int, yoff: [*c]c_int) [*c]u8;
pub const GetGlyphBitmapSubpixel = stbtt_GetGlyphBitmapSubpixel;
extern fn stbtt_GetGlyphBitmapSubpixel(info: [*c]const fontinfo, scale_x: f32, scale_y: f32, shift_x: f32, shift_y: f32, glyph: c_int, width: [*c]c_int, height: [*c]c_int, xoff: [*c]c_int, yoff: [*c]c_int) [*c]u8;
pub const MakeGlyphBitmap = stbtt_MakeGlyphBitmap;
extern fn stbtt_MakeGlyphBitmap(info: [*c]const fontinfo, output: [*c]u8, out_w: c_int, out_h: c_int, out_stride: c_int, scale_x: f32, scale_y: f32, glyph: c_int) void;
pub const MakeGlyphBitmapSubpixel = stbtt_MakeGlyphBitmapSubpixel;
extern fn stbtt_MakeGlyphBitmapSubpixel(info: [*c]const fontinfo, output: [*c]u8, out_w: c_int, out_h: c_int, out_stride: c_int, scale_x: f32, scale_y: f32, shift_x: f32, shift_y: f32, glyph: c_int) void;
pub const MakeGlyphBitmapSubpixelPrefilter = stbtt_MakeGlyphBitmapSubpixelPrefilter;
extern fn stbtt_MakeGlyphBitmapSubpixelPrefilter(info: [*c]const fontinfo, output: [*c]u8, out_w: c_int, out_h: c_int, out_stride: c_int, scale_x: f32, scale_y: f32, shift_x: f32, shift_y: f32, oversample_x: c_int, oversample_y: c_int, sub_x: [*c]f32, sub_y: [*c]f32, glyph: c_int) void;
pub const GetGlyphBitmapBox = stbtt_GetGlyphBitmapBox;
extern fn stbtt_GetGlyphBitmapBox(font: [*c]const fontinfo, glyph: c_int, scale_x: f32, scale_y: f32, ix0: [*c]c_int, iy0: [*c]c_int, ix1: [*c]c_int, iy1: [*c]c_int) void;
pub const GetGlyphBitmapBoxSubpixel = stbtt_GetGlyphBitmapBoxSubpixel;
extern fn stbtt_GetGlyphBitmapBoxSubpixel(font: [*c]const fontinfo, glyph: c_int, scale_x: f32, scale_y: f32, shift_x: f32, shift_y: f32, ix0: [*c]c_int, iy0: [*c]c_int, ix1: [*c]c_int, iy1: [*c]c_int) void;
pub const _bitmap = extern struct {
    w: c_int = 0,
    h: c_int = 0,
    stride: c_int = 0,
    pixels: [*c]u8 = null,
};
pub const Rasterize = stbtt_Rasterize;
extern fn stbtt_Rasterize(result: [*c]_bitmap, flatness_in_pixels: f32, vertices: [*c]vertex, num_verts: c_int, scale_x: f32, scale_y: f32, shift_x: f32, shift_y: f32, x_off: c_int, y_off: c_int, invert: c_int, userdata: ?*anyopaque) void;
pub const FreeSDF = stbtt_FreeSDF;
extern fn stbtt_FreeSDF(bitmap: [*c]u8, userdata: ?*anyopaque) void;
pub const GetGlyphSDF = stbtt_GetGlyphSDF;
extern fn stbtt_GetGlyphSDF(info: [*c]const fontinfo, scale: f32, glyph: c_int, padding: c_int, onedge_value: u8, pixel_dist_scale: f32, width: [*c]c_int, height: [*c]c_int, xoff: [*c]c_int, yoff: [*c]c_int) [*c]u8;
pub const GetCodepointSDF = stbtt_GetCodepointSDF;
extern fn stbtt_GetCodepointSDF(info: [*c]const fontinfo, scale: f32, codepoint: c_int, padding: c_int, onedge_value: u8, pixel_dist_scale: f32, width: [*c]c_int, height: [*c]c_int, xoff: [*c]c_int, yoff: [*c]c_int) [*c]u8;
pub const FindMatchingFont = stbtt_FindMatchingFont;
extern fn stbtt_FindMatchingFont(fontdata: [*c]const u8, name: [*c]const u8, flags: c_int) c_int;
pub const CompareUTF8toUTF16_bigendian = stbtt_CompareUTF8toUTF16_bigendian;
extern fn stbtt_CompareUTF8toUTF16_bigendian(s1: [*c]const u8, len1: c_int, s2: [*c]const u8, len2: c_int) c_int;
pub const GetFontNameString = stbtt_GetFontNameString;
extern fn stbtt_GetFontNameString(font: [*c]const fontinfo, length: [*c]c_int, platformID: c_int, encodingID: c_int, languageID: c_int, nameID: c_int) [*c]const u8;
pub const PLATFORM_ID_UNICODE: c_int = 0;
pub const PLATFORM_ID_MAC: c_int = 1;
pub const PLATFORM_ID_ISO: c_int = 2;
pub const PLATFORM_ID_MICROSOFT: c_int = 3;
const enum_unnamed_3 = c_uint;
pub const UNICODE_EID_UNICODE_1_0: c_int = 0;
pub const UNICODE_EID_UNICODE_1_1: c_int = 1;
pub const UNICODE_EID_ISO_10646: c_int = 2;
pub const UNICODE_EID_UNICODE_2_0_BMP: c_int = 3;
pub const UNICODE_EID_UNICODE_2_0_FULL: c_int = 4;
const enum_unnamed_4 = c_uint;
pub const MS_EID_SYMBOL: c_int = 0;
pub const MS_EID_UNICODE_BMP: c_int = 1;
pub const MS_EID_SHIFTJIS: c_int = 2;
pub const MS_EID_UNICODE_FULL: c_int = 10;
const enum_unnamed_5 = c_uint;
pub const MAC_EID_ROMAN: c_int = 0;
pub const MAC_EID_ARABIC: c_int = 4;
pub const MAC_EID_JAPANESE: c_int = 1;
pub const MAC_EID_HEBREW: c_int = 5;
pub const MAC_EID_CHINESE_TRAD: c_int = 2;
pub const MAC_EID_GREEK: c_int = 6;
pub const MAC_EID_KOREAN: c_int = 3;
pub const MAC_EID_RUSSIAN: c_int = 7;
const enum_unnamed_6 = c_uint;
pub const MS_LANG_ENGLISH: c_int = 1033;
pub const MS_LANG_ITALIAN: c_int = 1040;
pub const MS_LANG_CHINESE: c_int = 2052;
pub const MS_LANG_JAPANESE: c_int = 1041;
pub const MS_LANG_DUTCH: c_int = 1043;
pub const MS_LANG_KOREAN: c_int = 1042;
pub const MS_LANG_FRENCH: c_int = 1036;
pub const MS_LANG_RUSSIAN: c_int = 1049;
pub const MS_LANG_GERMAN: c_int = 1031;
pub const MS_LANG_SPANISH: c_int = 1033;
pub const MS_LANG_HEBREW: c_int = 1037;
pub const MS_LANG_SWEDISH: c_int = 1053;
const enum_unnamed_7 = c_uint;
pub const MAC_LANG_ENGLISH: c_int = 0;
pub const MAC_LANG_JAPANESE: c_int = 11;
pub const MAC_LANG_ARABIC: c_int = 12;
pub const MAC_LANG_KOREAN: c_int = 23;
pub const MAC_LANG_DUTCH: c_int = 4;
pub const MAC_LANG_RUSSIAN: c_int = 32;
pub const MAC_LANG_FRENCH: c_int = 1;
pub const MAC_LANG_SPANISH: c_int = 6;
pub const MAC_LANG_GERMAN: c_int = 2;
pub const MAC_LANG_SWEDISH: c_int = 5;
pub const MAC_LANG_HEBREW: c_int = 10;
pub const MAC_LANG_CHINESE_SIMPLIFIED: c_int = 33;
pub const MAC_LANG_ITALIAN: c_int = 3;
pub const MAC_LANG_CHINESE_TRAD: c_int = 19;
pub const vertex_type = enum(u8) {
    vmove = 1,
    vline = 2,
    vcurve = 3,
    vcubic = 4,
    _,
};
pub const MACSTYLE_DONTCARE = @as(c_int, 0);
pub const MACSTYLE_BOLD = @as(c_int, 1);
pub const MACSTYLE_ITALIC = @as(c_int, 2);
pub const MACSTYLE_UNDERSCORE = @as(c_int, 4);
pub const MACSTYLE_NONE = @as(c_int, 8);
