const Texture = @This();

const std = @import("std");

const ila = @import("../root.zig");
const Context = ila.render.Context;

allocator: std.mem.Allocator,
texture: *ila.gpu.Texture,
srv: ?*ila.gpu.Resource,
rtv: ?*ila.gpu.Resource,
uav: ?*ila.gpu.Resource,
dsv: ?*ila.gpu.Resource,
desc: ila.gpu.TextureDesc,

pub fn init(allocator: std.mem.Allocator, desc: ila.gpu.TextureDesc) !Texture {
    var self: Texture = .{
        .allocator = allocator,
        .texture = undefined,
        .srv = null,
        .rtv = null,
        .uav = null,
        .dsv = null,
        .desc = desc,
    };
    self.texture = try ila.gpu.Texture.init(allocator, desc);
    if (desc.usage.srv) {
        // TODO: cubes?
        self.srv = try ila.gpu.Resource.initTexture(allocator, .{
            .name = "Texture-srv",
            .texture = self.texture,
            .dimension = desc.kind,
            .kind = .srv,
            .format = desc.format,
            .layer_num = desc.layer_num,
            .mip_num = desc.mip_num,
        });
    }
    if (desc.usage.rtv) {
        self.rtv = try ila.gpu.Resource.initTexture(allocator, .{
            .name = "Texture-rtv",
            .texture = self.texture,
            .dimension = desc.kind,
            .kind = .rtv,
            .format = desc.format,
            .layer_num = desc.layer_num,
            .mip_num = desc.mip_num,
        });
    }
    if (desc.usage.uav) {
        self.uav = try ila.gpu.Resource.initTexture(allocator, .{
            .name = "Texture-uav",
            .texture = self.texture,
            .dimension = desc.kind,
            .kind = .uav,
            .format = desc.format,
            .layer_num = desc.layer_num,
            .mip_num = desc.mip_num,
        });
    }
    if (desc.usage.dsv) {
        self.dsv = try ila.gpu.Resource.initTexture(allocator, .{
            .name = "Texture-dsv",
            .texture = self.texture,
            .dimension = desc.kind,
            .kind = .dsv,
            .format = desc.format,
            .layer_num = desc.layer_num,
            .mip_num = desc.mip_num,
        });
    }
    return self;
}

pub const FromImageDesc = struct {
    context: *Context,
    dimension: ila.gpu.TextureDimension = .d2,
    image: *const ila.Resource.Image,
    srv: bool = true,
    uav: bool = false,
    after: ila.gpu.TextureState = .shader_resource,
    blocks: bool = true,
};

pub fn fromImage(allocator: std.mem.Allocator, desc: FromImageDesc) !Texture {
    const init_desc: ila.gpu.TextureDesc = .{
        .name = "Texture-from-image",
        .kind = .d2,
        .location = .device,
        .format = desc.image.format,
        .width = desc.image.width,
        .height = desc.image.height,
        .layer_num = 1,
        .mip_num = desc.image.mip_levels,
        .usage = .{
            .srv = desc.srv,
            .uav = desc.uav,
        },
        .clear_value = .color(.{ 0, 0, 0, 0 }),
        .sample_num = 1,
        .depth = 1,
    };
    var self = try Texture.init(allocator, init_desc);
    const computed_pitch = computePitch(
        desc.image.format,
        desc.image.width,
        desc.image.height,
    );
    const upload_desc: UploadDesc = .{
        .context = desc.context,
        .subresources = &.{.{
            .data = desc.image.data.constSlice(),
            .slice_num = 1,
            .row_pitch = computed_pitch.row_pitch,
            .slice_pitch = computed_pitch.slice_pitch,
        }},
        .after = desc.after,
        .blocks = desc.blocks,
    };
    try self.upload(upload_desc);
    return self;
}

pub fn deinit(self: *Texture) void {
    if (self.srv) |srv| srv.deinit();
    if (self.rtv) |rtv| rtv.deinit();
    if (self.uav) |uav| uav.deinit();
    if (self.dsv) |dsv| dsv.deinit();
    self.texture.deinit();
    self.texture = undefined;
    self.srv = null;
    self.rtv = null;
    self.uav = null;
    self.dsv = null;
}

pub const SubresourceDesc = struct {
    data: []const u8,
    slice_num: u32 = 0,
    row_pitch: u32 = 0,
    slice_pitch: u32 = 0,
};

pub const UploadDesc = struct {
    context: *Context,
    subresources: []const SubresourceDesc,
    after: ila.gpu.TextureState,
    layer_offset: u32 = 0,
    mip_offset: u32 = 0,
    /// whether this will wait for the GPU to finish before continuing
    blocks: bool = false,
};

pub fn upload(self: *Texture, desc: UploadDesc) !void {
    const texture_desc = self.texture.getDesc();
    const upload_buffer_texture_row_alignment = desc.context.limits.upload_buffer_texture_row_alignment;
    const upload_buffer_texture_slice_alignment = desc.context.limits.upload_buffer_texture_slice_alignment;

    const cmd: *ila.gpu.CommandBuffer = try desc.context.transferCommandBuffer();
    cmd.ensureTextureState(self.texture, .copy_dest);
    for (desc.layer_offset..texture_desc.layer_num) |layer| {
        for (desc.mip_offset..texture_desc.mip_num) |mip| {
            const subresource = &desc.subresources[layer * texture_desc.mip_num + mip];

            const slice_row_num: usize = @divTrunc(subresource.slice_pitch, subresource.row_pitch);
            const aligned_row_pitch = std.mem.alignForward(
                usize,
                subresource.row_pitch,
                upload_buffer_texture_row_alignment,
            );
            const aligned_slice_pitch = std.mem.alignForward(
                usize,
                slice_row_num * aligned_row_pitch,
                upload_buffer_texture_slice_alignment,
            );

            const content_size: usize = aligned_slice_pitch * subresource.slice_num;

            var eph_buffer = try desc.context.acquireTransferBuffer(content_size);
            defer desc.context.releaseTransferBuffer(eph_buffer);
            eph_buffer.len += content_size;

            const buffer_len_before = eph_buffer.len;
            const mapped = try eph_buffer.buffer.?.map(buffer_len_before, content_size);
            defer eph_buffer.buffer.?.unmap();

            var offset: usize = 0;
            for (0..subresource.slice_num) |slice| {
                for (0..slice_row_num) |slice_row| {
                    // const offset = slice * aligned_slice_pitch + slice_row * aligned_row_pitch;
                    const data = subresource.data[slice * subresource.slice_pitch +
                        slice_row * subresource.row_pitch ..][0..subresource.row_pitch];
                    @memcpy(mapped[offset..][0..data.len], data);
                    // @memset(mapped[offset..][0..subresource.row_pitch], 255);
                    offset += aligned_row_pitch;
                }
            }

            const layout: ila.gpu.TextureDataLayout = .{
                .offset = buffer_len_before,
                .row_pitch = @intCast(aligned_row_pitch),
                .slice_pitch = @intCast(aligned_slice_pitch),
            };

            const dst_region: ila.gpu.TextureRegion = .{
                .layer = @intCast(layer),
                .mip = @intCast(mip),
            };

            cmd.copyBufferToTexture(
                self.texture,
                dst_region,
                eph_buffer.buffer.?,
                layout,
                .{},
            );
        }
    }
    cmd.ensureTextureState(self.texture, desc.after);

    const wait = try desc.context.flushTransfer();
    if (desc.blocks) {
        try desc.context.waitTransfer(wait);
    }
}

pub fn computePitch(format: ila.gpu.Format, width: u32, height: u32) struct {
    row_pitch: u32,
    slice_pitch: u32,
} {
    return switch (format) {
        .BC1, .BC4 => {
            const width_in_blocks: u32 = @max(1, @divFloor(width + 3, 4));
            const height_in_blocks: u32 = @max(1, @divFloor(height + 3, 4));
            return .{
                .row_pitch = width_in_blocks * 8,
                .slice_pitch = width_in_blocks * 8 * height_in_blocks,
            };
        },
        .BC2, .BC3, .BC5 => {
            const width_in_blocks: u32 = @max(1, @divFloor(width + 3, 4));
            const height_in_blocks: u32 = @max(1, @divFloor(height + 3, 4));
            return .{
                .row_pitch = width_in_blocks * 16,
                .slice_pitch = width_in_blocks * 16 * height_in_blocks,
            };
        },
        else => {
            // bits per pixel
            const bpp: u32 = format.stride() * 8;
            const row_pitch: u32 = @divFloor(width * bpp + 7, 8);
            return .{
                .row_pitch = row_pitch,
                .slice_pitch = row_pitch * height,
            };
        },
    };
}
