const Context = @This();

const std = @import("std");
const ila = @import("../root.zig");

pub const min_upload_page_size = 64 * 1024 * 1024; // 64 MiB
/// how many bytes worth of upload buffers to retain in the transfer queue, so that they can be reused
pub const upload_buffer_retain_size = 256 * 1024 * 1024; // 256 MiB

pub const Config = struct {
    texture_num: u32 = 2,
    immediate: bool = true,

    max_bound_textures: u32 = 4096, // 4096 textures
    /// texture2d
    max_quads_per_flush: u32 = 1024, // 1024 quads per flush
    clear_color: ila.gpu.Color = .{ 0.0, 0.0, 0.0, 1.0 }, // white
};

allocator: std.mem.Allocator,
frame_arena: std.heap.ArenaAllocator,
limits: ila.gpu.Limits,
config: Config,

window: ila.Window,
queue: *ila.gpu.CommandQueue = undefined,
swapchain_desc: ila.gpu.SwapchainDesc,
swapchain: *ila.gpu.Swapchain = undefined,

/// in nano
frame_start_time: i128 = 0,
frame_index: usize = 0,
frame_fence: *ila.gpu.Fence = undefined,
previous_frame_time: i128 = 0,

backbuffer_index: usize = 0,

cmd_bufs: [ila.gpu.MAX_SWAPCHAIN_IMAGES]*ila.gpu.CommandBuffer = @splat(undefined),

frame_textures: [ila.gpu.MAX_SWAPCHAIN_IMAGES]?*ila.gpu.Texture = @splat(null),
frame_srvs: [ila.gpu.MAX_SWAPCHAIN_IMAGES]?*ila.gpu.Resource = @splat(null),

frame_depth_texture: ?ila.render.Texture = null,

queue_resize: ?ila.gpu.Vec2u = null,

// transfer resources:
transfer: struct {
    free_buffer_mutex: std.Thread.Mutex = .{},
    in_progress: bool = false,
    cmd_queue: *ila.gpu.CommandQueue = undefined,
    cmd_buf: *ila.gpu.CommandBuffer = undefined,
    fence: *ila.gpu.Fence = undefined,
    fence_value: u64 = 0,
    free_buffers: std.ArrayListUnmanaged(ila.render.Buffer) = .empty,
    awaiting_free_buffers: std.ArrayListUnmanaged(FrameTaggedBuffer) = .empty,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.free_buffer_mutex.lock();
        defer self.free_buffer_mutex.unlock();

        self.cmd_buf.deinit();
        self.cmd_queue.deinit();
        self.fence.deinit();
        for (self.awaiting_free_buffers.items) |*buf| {
            buf.buffer.deinit();
        }
        self.awaiting_free_buffers.deinit(allocator);
        self.awaiting_free_buffers = .empty;
        for (self.free_buffers.items) |*buf| {
            buf.deinit();
        }
        self.free_buffers.deinit(allocator);
        self.free_buffers = .empty;
        self.in_progress = false;
    }
} = .{},

resources: ila.render.Shared = undefined,

// maybe have a fromTexture function later?
pub fn fromWindow(allocator: std.mem.Allocator, window: ila.Window, config: Config) !Context {
    return .{
        .allocator = allocator,
        .frame_arena = .init(allocator),
        .limits = ila.gpu.limits(),
        .config = config,
        .window = window,
        .queue = .primary(),
        .swapchain_desc = .{
            .name = "swapchain",
            .window = window,
            .queue = .primary(),
            .size = .{
                .x = window.cached_width,
                .y = window.cached_height,
            },
            .texture_num = config.texture_num,
            .format = .RGBA8,
            .immediate = config.immediate,
        },
    };
}

pub fn start(self: *Context) !void {
    self.swapchain = try .init(self.allocator, self.swapchain_desc);
    self.frame_fence = try .init(self.allocator);

    // transfer resources
    self.transfer.cmd_queue = try .init(self.allocator, .{
        .name = "transfer queue",
        .kind = .graphics,
    });
    self.transfer.cmd_buf = try .init(self.allocator, self.transfer.cmd_queue);
    self.transfer.fence = try .init(self.allocator);

    try self.acquireSwapchainResources();
    for (&self.cmd_bufs) |*cmd| {
        cmd.* = try .init(self.allocator, self.swapchain_desc.queue);
    }

    // resources
    self.resources = .{
        .context = self,
    };
    try self.resources.init(self.config.max_bound_textures);
}

pub fn deinit(self: *Context) void {
    self.waitAllRender() catch |err| {
        self.window.messageBox(._info, "Error", @errorName(err));
    };
    self.frame_fence.deinit();

    for (&self.cmd_bufs) |cmd| {
        cmd.deinit();
    }

    self.cleanupSwapchainResources();
    self.swapchain.deinit();

    self.frame_arena.deinit();

    self.resources.deinit();

    // deinit transfer resources
    self.transfer.deinit(self.allocator);
}

fn cleanupSwapchainResources(self: *Context) void {
    for (self.frame_srvs[0..self.swapchain_desc.texture_num]) |*srv| {
        if (srv.*) |got_srv| got_srv.deinit();
        srv.* = null;
    }

    if (self.frame_depth_texture) |*tex| {
        tex.deinit();
        self.frame_depth_texture = null;
    }
    _ = self.frame_arena.reset(.retain_capacity);
}

fn acquireSwapchainResources(self: *Context) !void {
    self.cleanupSwapchainResources();

    for (self.frame_srvs[0..self.swapchain_desc.texture_num], 0..) |*srv, i| {
        self.frame_textures[i] = (try self.swapchain.getTexture(i)) orelse {
            std.debug.panic("Failed to get swapchain texture", .{});
        };

        srv.* = try .initTexture(self.frame_arena.allocator(), .{
            .name = "swapchain texture",
            .texture = self.frame_textures[i].?,
            .dimension = .d2,
            .kind = .rtv,
            .format = self.swapchain_desc.format,
            .layer_num = 1,
        });
    }
    self.frame_depth_texture = try ila.render.Texture.init(self.frame_arena.allocator(), .{
        .name = "depth texture",
        .kind = .d2,
        .usage = .{
            .dsv = true,
            .srv = true,
        },
        .location = .device,
        .format = .D32,
        .clear_value = .depth_stencil(.{}),
        .width = self.swapchain_desc.size.x,
        .height = self.swapchain_desc.size.y,
        .depth = 1,
        .mip_num = 1,
        .layer_num = 1,
        .sample_num = 1,
    });

    const cmd = try self.transferCommandBuffer();
    cmd.ensureTextureState(self.frame_depth_texture.?.texture, .depth_stencil_write);
    try self.waitTransfer(try self.flushTransfer());
}

/// resize will be performed on next beginFrame call
pub inline fn resize(self: *Context, size: ila.gpu.Vec2u) void {
    self.queue_resize = size;
}

/// gets the current backbuffer rtv
pub inline fn backbuffer(self: *Context) *ila.gpu.Resource {
    return self.frame_srvs[self.backbuffer_index].?;
}

/// gets the depth texture
pub inline fn depthTexture(self: *Context) ila.render.Texture {
    return self.frame_depth_texture.?; // FIXME: self.backbuffer_index
}

/// gets the rectangle for the current window size
pub inline fn rect(self: *Context) ila.gpu.Rect {
    return .{
        .x = 0,
        .y = 0,
        .width = @intCast(self.swapchain_desc.size.x),
        .height = @intCast(self.swapchain_desc.size.y),
    };
}

pub inline fn viewport(self: *Context) ila.gpu.Viewport {
    // const is_origin_bottom_left = self.limits.viewport_origin_bottom_left;
    return .{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(self.swapchain_desc.size.x),
        .height = @floatFromInt(self.swapchain_desc.size.y),
        .min_depth = 0.0,
        .max_depth = 1.0,
        .origin_bottom_left = true,
    };
}

/// processes any frame operations that need to be done before rendering
pub fn processOperations(self: *Context) !void {
    {
        // process any pending transfer buffers
        self.transfer.free_buffer_mutex.lock();
        defer self.transfer.free_buffer_mutex.unlock();

        var available_capacity: u64 = 0;
        for (self.transfer.free_buffers.items) |buf| {
            available_capacity += buf.unusedCapacity();
        }

        // free any transfer buffers that are no longer in use
        for (self.transfer.awaiting_free_buffers.items) |*tagged_buf| {
            if (tagged_buf.frame > self.frame_index) continue;

            const capacity = tagged_buf.buffer.unusedCapacity();
            if (available_capacity + capacity > upload_buffer_retain_size) {
                // we have enough free buffers, deinit this one
                tagged_buf.buffer.deinit();
                continue;
            }
            available_capacity += capacity;

            // otherwise, add it to the free list
            self.transfer.free_buffers.append(self.allocator, tagged_buf.buffer) catch {
                std.debug.panic("Failed to append transfer buffer to free list", .{});
            };
        }
        self.transfer.awaiting_free_buffers.clearRetainingCapacity();
    }
}

/// waits until the current frame is able to be rendered
pub fn waitReadyRender(self: *Context) !void {
    if (self.frame_index >= self.swapchain_desc.texture_num) {
        try self.frame_fence.wait(1 + self.frame_index - self.swapchain_desc.texture_num);
    }
}

/// waits until every single frame in the swapchain is rendered
pub fn waitAllRender(self: *Context) !void {
    try self.frame_fence.wait(self.frame_index);
}

pub fn beginFrame(self: *Context) !*ila.gpu.CommandBuffer {
    if (self.queue_resize) |size| {
        try self.waitAllRender();
        self.swapchain_desc.size = size;
        try self.swapchain.resize(size);
        try self.acquireSwapchainResources();
        self.queue_resize = null;
    } else try self.waitReadyRender();

    try self.processOperations();

    const cmd = self.cmd_bufs[self.frame_index % self.swapchain_desc.texture_num];
    try cmd.begin();
    self.previous_frame_time = if (self.frame_start_time != 0) (std.time.nanoTimestamp() - self.frame_start_time) else 0;
    self.frame_start_time = std.time.nanoTimestamp();
    self.backbuffer_index = try self.swapchain.acquireNextTexture();
    cmd.ensureTextureState(self.frame_textures[self.backbuffer_index].?, .render_target);
    return cmd;
}

pub fn endFrame(self: *Context) !void {
    const cmd = self.cmd_bufs[self.frame_index % self.swapchain_desc.texture_num];
    cmd.ensureTextureState(self.frame_textures[self.backbuffer_index].?, .present);
    try cmd.end();
    try self.swapchain_desc.queue.submit(cmd);

    try self.swapchain.present();
    self.frame_index += 1;
    try self.swapchain_desc.queue.signalFence(self.frame_fence, self.frame_index);
}

pub fn beginRendering(self: *Context) void {
    const b = self.backbuffer();
    self.beginRenderingToAttachments(&.{b});
}

pub fn beginRenderingToAttachments(self: *Context, attachments: []const *ila.gpu.Resource) void {
    const cmd = self.cmd_bufs[self.frame_index % self.swapchain_desc.texture_num];

    const window_vp = self.viewport();
    const window_rect = self.rect();

    const depth_texture = self.depthTexture();
    cmd.beginRendering(.{
        .attachments = attachments,
        .depth_stencil = depth_texture.dsv.?,
    });

    cmd.setViewports(&.{window_vp});
    cmd.setScissors(&.{window_rect});
    cmd.clearAttachment(.color(self.config.clear_color, 0), window_rect);
    cmd.clearAttachment(.depth(1.0), window_rect);
    // cmd.setDepthBounds(0.0, 1.0);
    cmd.setResourceSet(self.resources.resource_set, 0);
    cmd.setResourceSet(self.resources.currentFrameConstantsSet(), 1);

    const current_frame_constants = self.resources.frameConstants(self.backbuffer_index);
    current_frame_constants.frame_size = .{
        @floatFromInt(window_rect.width),
        @floatFromInt(window_rect.height),
    };
}

pub fn endRendering(self: *Context) void {
    const cmd = self.cmd_bufs[self.frame_index % self.swapchain_desc.texture_num];
    cmd.endRendering();
}

// transfer ops
pub fn acquireTransferBuffer(self: *Context, size: u64) !ila.render.Buffer {
    self.transfer.free_buffer_mutex.lock();
    defer self.transfer.free_buffer_mutex.unlock();
    {
        for (self.transfer.free_buffers.items, 0..) |buf, i| {
            if (buf.unusedCapacity() < size) continue;
            // found a buffer that is large enough, remove it from the free list
            return self.transfer.free_buffers.swapRemove(i);
        }
    }

    if (self.transfer.free_buffers.items.len == 0 or size > min_upload_page_size) {
        // no free buffers or the size is larger than the minimum upload page size
        // create a new buffer
        const desc: ila.gpu.BufferDesc = .{
            .name = "transfer buffer",
            .size = size,
            .location = .host_upload,
            .usage = .{},
            .structure_stride = 0, // no structure stride for transfer buffers
        };
        const new_buffer: ila.render.Buffer = try .initCapacity(self.allocator, desc, .map_when_needed);
        return new_buffer;
    }

    // use the last buffer in the list
    return self.transfer.free_buffers.pop() orelse {
        std.debug.panic("No transfer buffer available, this should not happen", .{});
    };
}

pub fn releaseTransferBuffer(self: *Context, buffer: ila.render.Buffer) void {
    self.transfer.free_buffer_mutex.lock();
    defer self.transfer.free_buffer_mutex.unlock();

    self.transfer.awaiting_free_buffers.append(self.allocator, .{
        .buffer = buffer,
        .frame = self.frame_index + ila.gpu.MAX_SWAPCHAIN_IMAGES,
    }) catch {
        std.debug.panic("Failed to append transfer buffer to free list", .{});
    };
}

pub fn transferCommandBuffer(self: *Context) !*ila.gpu.CommandBuffer {
    if (self.transfer.in_progress) {
        return self.transfer.cmd_buf;
    }

    try self.transfer.cmd_buf.begin();
    self.transfer.in_progress = true;
    return self.transfer.cmd_buf;
}

/// does not wait for the transfer to finish, but returns the fence value
pub fn flushTransfer(self: *Context) !u64 {
    if (!self.transfer.in_progress) return self.transfer.fence_value;

    try self.transfer.cmd_buf.end();
    try self.transfer.cmd_queue.submit(self.transfer.cmd_buf);
    try self.transfer.cmd_queue.signalFence(self.transfer.fence, self.transfer.fence_value);
    self.transfer.in_progress = false;
    defer self.transfer.fence_value += 1;

    return self.transfer.fence_value;
}

pub fn waitTransfer(self: *Context, fence_value: u64) !void {
    try self.transfer.fence.wait(fence_value);
}

pub fn graphicsWaitTransfer(self: *Context, fence_value: u64) !void {
    // wait for the transfer to finish before continuing
    try self.swapchain_desc.queue.waitFence(self.transfer.fence, fence_value);
}

/// tagged with a frame index to know when the buffer is ok to return to the transfer pool
pub const FrameTaggedBuffer = struct {
    buffer: ila.render.Buffer,
    frame: u64,
};
