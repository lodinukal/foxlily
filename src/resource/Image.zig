const std = @import("std");

const Image = @This();

const ila = @import("../root.zig");

const zstbi = @import("zstbi");

data: ila.util.Buffer = .empty,
format: ila.gpu.Format = .RGBA8,
/// The width of the image in pixels
width: u32 = 0,
/// The height of the image in pixels
height: u32 = 0,
/// The number of mip levels in the image
mip_levels: u32 = 1,

// load from bytes you just construct the Image struct, no need for a constructor

fn fromStbImage(
    allocator: std.mem.Allocator,
    stb_image: zstbi.Image,
) !Image {
    return .{
        .data = try .dupe(allocator, stb_image.data),
        .width = stb_image.width,
        .height = stb_image.height,
        .format = switch (stb_image.bytes_per_component) {
            1 => .RGBA8,
            2 => .RGBA16,
            4 => .RGBA32F,
            else => return error.InvalidImageFormat,
        },
    };
}

pub fn loadFromData(allocator: std.mem.Allocator, data: []const u8) !Image {
    var stb_image = try zstbi.Image.loadFromMemory(data, 4);
    defer stb_image.deinit();

    return try .fromStbImage(allocator, stb_image);
}

pub fn loadFromPath(allocator: std.mem.Allocator, path: []const u8) !Image {
    if (path.len >= std.fs.max_path_bytes) {
        return error.PathTooLong;
    }
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0; // Null-terminate the path

    var stb_image = try zstbi.Image.loadFromFile(@ptrCast(path_buf[0..]), 4);
    defer stb_image.deinit();

    return try .fromStbImage(allocator, stb_image);
}

pub fn deinit(self: Image) void {
    self.data.deinit();
}
