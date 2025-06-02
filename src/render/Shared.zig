//! Provides shared resources for rendering like the textures, pipeline layout, mesh buffers, etc.
const Shared = @This();

const std = @import("std");
const ila = @import("../root.zig");

context: *ila.render.Context,

resource_set_bindings: [2]ila.gpu.ResourceBinding = undefined,
resource_set_desc: ila.gpu.ResourceSetDesc = undefined,

shared_constants_bindings: [1]ila.gpu.ResourceBinding = undefined,
shared_constants_desc: ila.gpu.ResourceSetDesc = undefined,

/// used for linear filtering, mipmapping, etc.
linear_sampler: *ila.gpu.Resource = undefined,
white_texture: ila.render.Texture = undefined,
black_texture: ila.render.Texture = undefined,
textures: []?*ila.gpu.Resource = &.{},
/// 0 and 1 are reserved for white and black textures
highest_bound_texture: usize = 0,

/// needs enough capacity to fit constants * frame count
cbuffer: ila.render.Buffer = undefined,
mapped_constants: []align(1) Constants = undefined,

/// bound to space0
resource_set: *ila.gpu.ResourceSet = undefined,
/// bound to space1
shared_constants_views: [ila.gpu.MAX_SWAPCHAIN_IMAGES]*ila.gpu.Resource = undefined,
shared_constant_sets: [ila.gpu.MAX_SWAPCHAIN_IMAGES]*ila.gpu.ResourceSet = undefined,

pub const Constants = extern struct {
    projection: ila.math.Mat,
    view: ila.math.Mat,
    model: ila.math.Mat,
    frame_size: [2]f32 = .{ 1, 1 }, // width, height
    padding: [56]u8 = undefined, // padding to ensure 256-byte alignment
};
comptime {
    if (@sizeOf(Constants) % 256 != 0) {
        @compileError(std.fmt.comptimePrint("Constants struct must be 256-byte multiples but are {d}", .{@sizeOf(Constants)}));
    }
}

pub fn init(self: *Shared, max_bound_textures: u32) !void {
    const allocator = self.context.allocator;

    const resource_bindings: [2]ila.gpu.ResourceBinding = .{
        .sampler(),
        .textureArray(max_bound_textures, .readonly),
    };

    const shared_constants_bindings: [1]ila.gpu.ResourceBinding = .{
        .constantBuffer(),
    };

    const default_texture_desc: ila.gpu.TextureDesc = .{
        .name = "default-white-black-texture",
        .width = 1,
        .height = 1,
        .layer_num = 1,
        .mip_num = 1,
        .format = .RGBA8,
        .usage = .{
            .srv = true,
        },
        .location = .device,
        .clear_value = .color(.{ 0, 0, 0, 0 }),
        .depth = 1,
        .sample_num = 1,
    };

    self.* = .{
        // context should be set before calling this
        .context = self.context,
        .resource_set_bindings = resource_bindings,
        .resource_set_desc = .init(&self.resource_set_bindings),
        .shared_constants_bindings = shared_constants_bindings,
        .shared_constants_desc = .init(&self.shared_constants_bindings),
        .linear_sampler = try ila.gpu.Resource.initSampler(allocator, .{
            .filters = .{
                .min = .linear,
                .mag = .linear,
                .mip = .linear,
            },
        }),
        .white_texture = try ila.render.Texture.init(allocator, default_texture_desc),
        .black_texture = try ila.render.Texture.init(allocator, default_texture_desc),
        .resource_set = try ila.gpu.ResourceSet.init(allocator, .init(&self.resource_set_bindings)),
        //
        .cbuffer = try .initCapacity(allocator, .{
            .name = "Shared-cbuffer",
            .location = .host_upload,
            .usage = .{
                .cbv = true,
            },
            .size = @sizeOf(Constants) * ila.gpu.MAX_SWAPCHAIN_IMAGES,
        }, .always_map),
        .mapped_constants = try self.cbuffer.mapSlice(Constants, .whole),
    };

    const textures = try allocator.alloc(?*ila.gpu.Resource, max_bound_textures);
    errdefer allocator.free(textures);
    self.textures = textures;

    const white_data: [4]u8 = .{ 255, 255, 255, 255 };
    const black_data: [4]u8 = .{ 0, 0, 0, 255 };
    const pitch_info = ila.render.Texture.computePitch(.RGBA8, 1, 1);

    var subresource_upload: ila.render.Texture.SubresourceDesc = .{
        .data = white_data[0..],
        .slice_num = 1,
        .row_pitch = pitch_info.row_pitch,
        .slice_pitch = pitch_info.slice_pitch,
    };

    try self.white_texture.upload(.{
        .context = self.context,
        .subresources = &.{subresource_upload},
        .after = .shader_resource,
        .blocks = false,
    });
    subresource_upload.data = black_data[0..];
    try self.black_texture.upload(.{
        .context = self.context,
        .subresources = &.{subresource_upload},
        .after = .shader_resource,
        .blocks = true,
    });
    _ = try self.addTexture(self.white_texture.srv.?);
    _ = try self.addTexture(self.black_texture.srv.?);

    try self.resource_set.setResource(0, 0, self.linear_sampler);

    for (&self.shared_constants_views, &self.shared_constant_sets, 0..) |*view, *set, i| {
        view.* = try ila.gpu.Resource.initBuffer(allocator, .{
            .name = "Shared-constants-view",
            .buffer = self.cbuffer.buffer.?,
            .kind = .cbv,
            .format = .R32UI,
            .offset = @sizeOf(Constants) * i,
            .size = @sizeOf(Constants),
        });
        set.* = try ila.gpu.ResourceSet.init(allocator, .init(&self.shared_constants_bindings));
        try set.*.setResource(0, 0, view.*);
    }

    for (0..self.shared_constant_sets.len) |i| {
        const constants = self.frameConstants(i);
        constants.* = .{
            .projection = ila.math.identity(),
            .view = ila.math.identity(),
            .model = ila.math.identity(),
            .frame_size = .{ 1, 1 }, // default to 1x1
        };
    }
}

pub fn deinit(self: *Shared) void {
    self.context.allocator.free(self.textures);
    self.linear_sampler.deinit();
    self.cbuffer.unmap();
    self.cbuffer.deinit();

    self.white_texture.deinit();
    self.black_texture.deinit();

    for (&self.shared_constants_views, &self.shared_constant_sets) |view, set| {
        view.deinit();
        set.deinit();
    }
    self.resource_set.deinit();
}

pub fn frameConstantsSet(self: *Shared, frame_index: usize) *ila.gpu.ResourceSet {
    return self.shared_constant_sets[frame_index];
}

pub fn frameConstants(self: *Shared, frame_index: usize) *align(1) Constants {
    return &self.mapped_constants[frame_index];
}

pub fn addTexture(self: *Shared, texture: *ila.gpu.Resource) !usize {
    const index = self.highest_bound_texture;
    try self.setTexture(index, texture);
    self.highest_bound_texture += 1;
    return index;
}

pub fn setTexture(self: *Shared, index: usize, texture: ?*ila.gpu.Resource) !void {
    if (index >= self.textures.len) return error.OutOfBounds;
    self.textures[index] = texture;
    try self.resource_set.setResource(1, @intCast(index), texture);
}
