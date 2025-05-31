const Context = @This();

const std = @import("std");
const ila = @import("../root.zig");

pub const min_upload_page_size = 64 * 1024 * 1024; // 64 MiB
/// how many bytes worth of upload buffers to retain in the transfer queue, so that they can be reused
pub const upload_buffer_retain_size = 256 * 1024 * 1024; // 256 MiB

pub const Config = struct {
    texture_num: u32 = 2,
    immediate: bool = true,
};

allocator: std.mem.Allocator,
frame_arena: std.heap.ArenaAllocator,
limits: ila.gpu.Limits,

window: ila.Window,
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

queue_resize: ?ila.gpu.Vec2u = null,

// transfer resources:
transfer_free_buffer_mutex: std.Thread.Mutex = .{},
transfer_in_progress: bool = false,
transfer_cmd_queue: *ila.gpu.CommandQueue = undefined,
transfer_cmd_buf: *ila.gpu.CommandBuffer = undefined,
transfer_fence: *ila.gpu.Fence = undefined,
transfer_fence_value: u64 = 0,
transfer_free_buffers: std.ArrayListUnmanaged(ila.render.Buffer) = .empty,

// maybe have a fromTexture function later?
pub fn fromWindow(allocator: std.mem.Allocator, window: ila.Window, config: Config) !Context {
    return .{
        .allocator = allocator,
        .frame_arena = .init(allocator),
        .limits = ila.gpu.limits(),
        .window = window,
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

    try self.acquireSwapchainResources();
    for (&self.cmd_bufs) |*cmd| {
        cmd.* = try .init(self.allocator, self.swapchain_desc.queue);
    }

    // transfer resources
    self.transfer_cmd_queue = try .init(self.allocator, .{
        .name = "transfer queue",
        .kind = .graphics,
    });
    self.transfer_cmd_buf = try .init(self.allocator, self.transfer_cmd_queue);
    self.transfer_fence = try .init(self.allocator);
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

    // deinit transfer resources
    self.transfer_free_buffer_mutex.lock();
    defer self.transfer_free_buffer_mutex.unlock();

    self.transfer_cmd_buf.deinit();
    self.transfer_cmd_queue.deinit();
    self.transfer_fence.deinit();
    for (self.transfer_free_buffers.items) |*buf| {
        buf.deinit();
    }
    self.transfer_free_buffers.deinit(self.allocator);
    self.transfer_free_buffers = .empty;
    self.transfer_in_progress = false;
}

fn cleanupSwapchainResources(self: *Context) void {
    for (self.frame_srvs[0..self.swapchain_desc.texture_num]) |*srv| {
        if (srv.*) |got_srv| got_srv.deinit();
        srv.* = null;
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
}

/// resize will be performed on next beginFrame call
pub inline fn resize(self: *Context, size: ila.gpu.Vec2u) void {
    self.queue_resize = size;
}

/// gets the current backbuffer rtv
pub inline fn backbuffer(self: *Context) *ila.gpu.Resource {
    return self.frame_srvs[self.backbuffer_index].?;
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
    return .{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(self.swapchain_desc.size.x),
        .height = @floatFromInt(self.swapchain_desc.size.y),
        .min_depth = 0.0,
        .max_depth = 1.0,
        .origin_bottom_left = false,
    };
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

// transfer ops
pub fn acquireTransferBuffer(self: *Context, size: u64) !ila.render.Buffer {
    self.transfer_free_buffer_mutex.lock();
    defer self.transfer_free_buffer_mutex.unlock();
    {
        for (self.transfer_free_buffers.items, 0..) |buf, i| {
            if (buf.unusedCapacity() < size) continue;
            // found a buffer that is large enough, remove it from the free list
            return self.transfer_free_buffers.swapRemove(i);
        }
    }

    if (self.transfer_free_buffers.items.len == 0 or size > min_upload_page_size) {
        // no free buffers or the size is larger than the minimum upload page size
        // create a new buffer
        const desc: ila.gpu.BufferDesc = .{
            .name = "transfer buffer",
            .size = size,
            .location = .host_upload,
            .usage = .{},
            .structure_stride = 0, // no structure stride for transfer buffers
        };
        const new_buffer: ila.render.Buffer = try .initCapacity(self.allocator, desc);
        return new_buffer;
    }

    // use the last buffer in the list
    return self.transfer_free_buffers.pop() orelse {
        std.debug.panic("No transfer buffer available, this should not happen", .{});
    };
}

pub fn releaseTransferBuffer(self: *Context, to_release_buffer: ila.render.Buffer) void {
    var buffer = to_release_buffer;
    // TODO: do frame tracking to avoid resetting the buffer if it is still in use for a few frames
    buffer.len = 0; // reset the length to 0, so that it can be reused
    self.transfer_free_buffer_mutex.lock();
    defer self.transfer_free_buffer_mutex.unlock();

    var available_capacity = buffer.unusedCapacity();
    for (self.transfer_free_buffers.items) |buf| {
        available_capacity += buf.unusedCapacity();
    }

    if (available_capacity > upload_buffer_retain_size) {
        // we have enough free buffers, deinit this one
        buffer.deinit();
        return;
    }

    self.transfer_free_buffers.append(self.allocator, buffer) catch {
        std.debug.panic("Failed to append transfer buffer to free list", .{});
    };
}

pub fn transferCommandBuffer(self: *Context) !*ila.gpu.CommandBuffer {
    if (self.transfer_in_progress) {
        return self.transfer_cmd_buf;
    }

    try self.transfer_cmd_buf.begin();
    self.transfer_in_progress = true;
    return self.transfer_cmd_buf;
}

/// does not wait for the transfer to finish, but returns the fence value
pub fn flushTransfer(self: *Context) !u64 {
    if (!self.transfer_in_progress) return self.transfer_fence_value;

    try self.transfer_cmd_buf.end();
    try self.transfer_cmd_queue.submit(self.transfer_cmd_buf);
    self.transfer_fence_value += 1;
    try self.transfer_cmd_queue.signalFence(self.transfer_fence, self.transfer_fence_value);
    self.transfer_in_progress = false;

    return self.transfer_fence_value;
}

pub fn waitTransfer(self: *Context, fence_value: u64) !void {
    try self.transfer_fence.wait(fence_value);
}
