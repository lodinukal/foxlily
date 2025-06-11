const std = @import("std");

const Image = @This();

const ila = @import("../root.zig");

const stb = @import("stb");

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
    stb_image: stb.Image,
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

fn toStbImage(self: Image) !stb.Image {
    const bytes_per_component: u32 = switch (self.format) {
        .RGBA8 => 1,
        .RGBA16 => 2,
        .RGBA32F => 4,
        else => return error.InvalidImageFormat,
    };
    return .{
        .data = self.data.slice() orelse return error.InvalidImageData,
        .width = self.width,
        .height = self.height,
        .num_components = 4,
        .bytes_per_component = bytes_per_component,
        .bytes_per_row = self.width * bytes_per_component * 4, // 4 components (RGBA)
        .is_hdr = bytes_per_component > 1,
    };
}

pub fn loadFromData(allocator: std.mem.Allocator, data: []const u8) !Image {
    var stb_image = try stb.Image.loadFromMemory(data, 4);
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

    var stb_image = try stb.Image.loadFromFile(@ptrCast(path_buf[0..]), 4);
    defer stb_image.deinit();

    return try .fromStbImage(allocator, stb_image);
}

pub fn initResolution(allocator: std.mem.Allocator, width: u32, height: u32, format: ila.gpu.Format) !Image {
    const data: ila.util.Buffer = .initMutable(try allocator.alloc(u8, width * height * format.stride()));
    return .{
        .data = data,
        .width = width,
        .height = height,
        .format = format,
        .mip_levels = 1,
    };
}

pub fn deinit(self: Image) void {
    self.data.deinit();
}

pub fn writeToFile(
    self: Image,
    filename: []const u8,
    image_format: stb.Image.WriteFormat,
) !void {
    const image = try self.toStbImage();
    if (image.is_hdr and image_format != .hdr) {
        return error.InvalidImageFormat;
    }
    if (filename.len >= std.fs.max_path_bytes) {
        return error.PathTooLong;
    }
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    @memcpy(path_buf[0..filename.len], filename);
    path_buf[filename.len] = 0; // Null-terminate the path
    try image.writeToFile(
        @ptrCast(path_buf[0..]),
        image_format,
    );
}
