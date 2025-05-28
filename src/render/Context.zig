const Context = @This();

const std = @import("std");
const ila = @import("../root.zig");

pub const Config = struct {
    texture_num: u32 = 2,
    immediate: bool = true,
};

allocator: std.mem.Allocator,
frame_arena: std.heap.ArenaAllocator,

window: ila.Window,
swapchain_desc: ila.gpu.SwapchainDesc,
swapchain: *ila.gpu.Swapchain = undefined,

frame_index: usize = 0,
frame_fence: *ila.gpu.Fence = undefined,

backbuffer_index: usize = 0,

cmd_bufs: [ila.gpu.MAX_SWAPCHAIN_IMAGES]*ila.gpu.CommandBuffer = @splat(undefined),

frame_textures: [ila.gpu.MAX_SWAPCHAIN_IMAGES]?*ila.gpu.Texture = @splat(null),
frame_srvs: [ila.gpu.MAX_SWAPCHAIN_IMAGES]?*ila.gpu.Resource = @splat(null),

queue_resize: ?ila.gpu.Vec2u = null,

// maybe have a fromTexture function later?
pub fn fromWindow(allocator: std.mem.Allocator, window: ila.Window, config: Config) !Context {
    return .{
        .allocator = allocator,
        .frame_arena = .init(allocator),
        .window = window,
        .swapchain_desc = .{
            .name = "Runoff Swapchain",
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
