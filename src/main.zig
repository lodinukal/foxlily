const SCREEN_WIDTH = 640;
const SCREEN_HEIGHT = 480;

const App = struct {
    allocator: std.mem.Allocator,
    is_debug: bool,

    window: fl.Window,
    renderer: Renderer,
    new_resize: ?gpu.Vec2u,

    resources: Resources,
};
const AppError = sdl.SDLAppError || gpu.Error || fl.Window.Error || error{OutOfMemory};

pub const main = sdl.main;
pub const std_options = sdl.std_options;

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
pub fn init(app_state: **App, args: []const [*:0]const u8) AppError!void {
    const gpa, const is_debug = gpa: {
        if (native_os == .wasi) break :gpa .{ std.heap.wasm_allocator, false };
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };

    const app = gpa.create(App) catch @panic("App allocation failed");
    app_state.* = app;
    app.allocator = gpa;
    app.is_debug = is_debug;

    const window = try fl.Window.init("Runoff", 800, 600, .{
        .resizable = true,
    });

    app.renderer = .init(window, .{ .x = 800, .y = 600 }, 3, true);
    try app.renderer.start(app.allocator);
    app.new_resize = null;

    try app.resources.init(&app.renderer);

    for (args) |arg| {
        std.log.info("arg: {s}", .{arg});
    }
}

pub fn tick(app: *App) AppError!void {
    if (app.new_resize) |dim| {
        app.renderer.resize(dim) catch |err| {
            std.log.err("SDL_AppIterate: resize failed: {}", .{err});
        };
        app.new_resize = null;
    }

    const window_vp = app.renderer.viewport();
    const window_rect = app.renderer.rect();

    {
        const cmd = try app.renderer.beginFrame();
        defer app.renderer.endFrame() catch |err| std.debug.panic("renderer.endFrame failed: {}", .{err});

        const b = app.renderer.backbuffer();

        gpu.beginRendering(cmd, .{
            .colors = &.{b},
        });
        defer gpu.endRendering(cmd);

        gpu.setViewports(cmd, &.{window_vp});
        gpu.setScissors(cmd, &.{window_rect});
        gpu.clearAttachment(cmd, .init(.color(.{ 0x00 / 0xFF.0, 0x00 / 0xFF.0, 0x00 / 0xFF.0, 1.0 }), 0), window_rect);
        gpu.setPipelineLayout(cmd, app.resources.pipeline_layout);
        gpu.setPipeline(cmd, app.resources.pipeline);
        gpu.setVertexBuffer(cmd, 0, app.resources.vertex_buffer, 0);
        gpu.setResourceSet(cmd, app.resources.set);
        gpu.draw(cmd, .{
            .vertex_num = 3,
        });
    }
}

pub fn event(app: *App, ev: *sdl.c.SDL_Event) AppError!void {
    if (ev.type == sdl.c.SDL_EVENT_WINDOW_RESIZED) {
        app.new_resize = .{
            .x = @intCast(ev.window.data1),
            .y = @intCast(ev.window.data2),
        };
    }

    if (ev.type == sdl.c.SDL_EVENT_QUIT) {
        return error.SDLAppSuccess;
    }
}

pub fn deinit(app: *App, _: sdl.c.SDL_AppResult) void {
    app.resources.deinit();
    app.renderer.deinit(app.allocator);
    app.window.deinit();

    if (app.is_debug) {
        _ = debug_allocator.deinit();
    }
}

const Vertex = extern struct {
    position: [3]f32,
    color: [3]f32,
};

const Resources = struct {
    pipeline_layout: gpu.PipelineLayout = .null,
    pipeline: gpu.Pipeline = .null,

    vertex_buffer: gpu.Buffer = .null,

    sampler: gpu.Resource = .null,

    set: gpu.ResourceSet = .null,

    pub fn init(self: *Resources, _: *Renderer) !void {
        self.* = .{};
        errdefer self.deinit();
        self.pipeline_layout = try gpu.initPipelineLayout(.{
            .name = "graphics pipeline layout",
            .bindings = &.{
                .buffer(.readonly),
                .buffer(.readonly),
                .buffer(.readonly),
                .sampler(),
                .textureArray(4096, .readonly),
            },
            .constant = .sized(u64),
        });

        var graphics_pipeline_desc: gpu.GraphicsPipelineDesc = .{
            .layout = self.pipeline_layout,
            .vertex_input = .{
                .attributes = &.{
                    .init(0, @offsetOf(Vertex, "position"), .vec3, 0),
                    .init(1, @offsetOf(Vertex, "color"), .vec3, 0),
                },
                .streams = &.{
                    .init(@sizeOf(Vertex), .vertex),
                },
            },
            .output_merger = .{
                .colors = &.{
                    .colorAttachment(.RGBA8, .{}, .{}, .{}),
                },
            },
        };
        graphics_pipeline_desc.addShader(.vertex(@embedFile("compiled_shaders/triangle.vert.dxil")));
        graphics_pipeline_desc.addShader(.fragment(@embedFile("compiled_shaders/triangle.frag.dxil")));
        self.pipeline = try gpu.initGraphicsPipeline(graphics_pipeline_desc);

        self.vertex_buffer = try gpu.initBuffer(.{
            .name = "vertex buffer",
            .size = 3 * @sizeOf(Vertex),
            .location = .host_upload,
            .usage = .{ .vertex = true },
            .structure_stride = @sizeOf(Vertex),
        });

        const mapped_raw = try gpu.map(self.vertex_buffer, 0, null);
        const mapped: []align(1) Vertex = @ptrCast(mapped_raw);
        mapped[0] = .{ .position = .{ 0.0, 0.5, 0.0 }, .color = .{ 1.0, 0.0, 0.0 } };
        mapped[1] = .{ .position = .{ -0.5, -0.5, 0.0 }, .color = .{ 0.0, 1.0, 0.0 } };
        mapped[2] = .{ .position = .{ 0.5, -0.5, 0.0 }, .color = .{ 0.0, 0.0, 1.0 } };

        const sampler = try gpu.initSampler(.{});
        self.sampler = sampler;

        self.set = try gpu.initResourceSet(self.pipeline_layout);
        try gpu.setResource(self.set, 3, 0, self.sampler);
    }

    // pub const deinit = ;
    pub fn deinit(self: Resources) void {
        gpu.unmap(self.vertex_buffer);
        gpu.deinitStruct(self);
    }
};

const Renderer = struct {
    memory: []u8 = &.{},
    limits: gpu.ResourceLimits = .{},

    window: fl.Window,
    swapchain_desc: gpu.SwapchainDesc,
    swapchain: gpu.Swapchain = .null,

    frame_index: usize = 0,
    frame_fence: gpu.Fence = .null,

    backbuffer_index: usize = 0,

    cmd_bufs: [gpu.MAX_SWAPCHAIN_IMAGES]gpu.CommandBuffer = @splat(.null),

    frame_textures: [gpu.MAX_SWAPCHAIN_IMAGES]gpu.Texture = @splat(.null),
    frame_srvs: [gpu.MAX_SWAPCHAIN_IMAGES]gpu.Resource = @splat(.null),

    pub fn init(window: fl.Window, initial_size: gpu.Vec2u, texture_num: u32, immediate: bool) Renderer {
        return .{
            .window = window,
            .swapchain_desc = .{
                .name = "Runoff Swapchain",
                .window = window,
                .queue = .primary,
                .size = initial_size,
                .texture_num = texture_num,
                .format = .RGBA8,
                .immediate = immediate,
            },
        };
    }

    pub fn start(self: *Renderer, allocator: std.mem.Allocator) !void {
        // const needed_mem = gpu.memoryRequirement(.default, self.limits, .{});
        // 200 kb
        const needed_mem = 1024 * 1024;
        const memory = try allocator.alloc(u8, needed_mem);
        errdefer allocator.free(memory);

        self.memory = memory;

        try gpu.init(.{
            .name = "runoff device",
            .memory = memory,
            .api = .default,
            .limits = blk: {
                var limits: gpu.ResourceLimits = .{};
                limits.max_textures = 4096;
                break :blk limits;
            },
            // .validation = .none,
        });

        self.swapchain = try gpu.initSwapchain(self.swapchain_desc);
        self.frame_fence = try gpu.initFence();

        try self.acquireSwapchainResources();
        for (&self.cmd_bufs) |*buf| {
            buf.* = try gpu.initCommandBuffer(self.swapchain_desc.queue);
        }
    }

    pub fn deinit(self: *Renderer, allocator: std.mem.Allocator) void {
        self.waitAllRender() catch |err| {
            _ = sdl.c.SDL_ShowSimpleMessageBox(
                sdl.c.SDL_MESSAGEBOX_ERROR,
                "Error",
                @errorName(err),
                self.window.impl,
            );
        };
        gpu.deinitFence(self.frame_fence);

        for (&self.cmd_bufs) |buf| {
            gpu.deinitCommandBuffer(buf);
        }

        gpu.deinitSwapchain(self.swapchain);

        gpu.deinit();
        allocator.free(self.memory);
    }

    fn cleanupSwapchainResources(self: *Renderer) void {
        for (self.frame_srvs[0..self.swapchain_desc.texture_num]) |*srv| {
            gpu.deinitResource(srv.*);
            srv.* = .null;
        }
    }

    fn acquireSwapchainResources(self: *Renderer) !void {
        self.cleanupSwapchainResources();

        const textures = try gpu.getSwapchainTextures(self.swapchain);
        std.mem.copyForwards(gpu.Texture, self.frame_textures[0..], textures);

        for (self.frame_srvs[0..self.swapchain_desc.texture_num], 0..) |*srv, i| {
            srv.* = try gpu.initTextureResource(.{
                .name = "swapchain texture",
                .texture = textures[i],
                .dimension = .d2,
                .kind = .rtv,
                .format = self.swapchain_desc.format,
                .layer_num = 1,
            });
        }
    }

    pub fn resize(self: *Renderer, size: gpu.Vec2u) !void {
        try self.waitAllRender();
        self.swapchain_desc.size = size;
        try gpu.resizeSwapchain(self.swapchain, size);
        try self.acquireSwapchainResources();
    }

    /// gets the current backbuffer rtv
    pub inline fn backbuffer(self: *Renderer) gpu.Resource {
        return self.frame_srvs[self.backbuffer_index];
    }

    /// gets the rectangle for the current window size
    pub inline fn rect(self: *Renderer) gpu.Rect {
        return .{
            .x = 0,
            .y = 0,
            .width = @intCast(self.swapchain_desc.size.x),
            .height = @intCast(self.swapchain_desc.size.y),
        };
    }

    pub inline fn viewport(self: *Renderer) gpu.Viewport {
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
    pub fn waitReadyRender(self: *Renderer) !void {
        if (self.frame_index >= self.swapchain_desc.texture_num) {
            try gpu.waitFenceBlocking(self.frame_fence, 1 + self.frame_index - self.swapchain_desc.texture_num);
        }
    }

    /// waits until every single frame in the swapchain is rendered
    pub fn waitAllRender(self: *Renderer) !void {
        try gpu.waitFenceBlocking(self.frame_fence, self.frame_index);
    }

    pub fn beginFrame(self: *Renderer) !gpu.CommandBuffer {
        try self.waitReadyRender();

        const buf = self.cmd_bufs[self.frame_index % self.swapchain_desc.texture_num];
        try gpu.beginCommandBuffer(buf);
        self.backbuffer_index = try gpu.acquireNextSwapchainTexture(self.swapchain);
        gpu.ensureTextureState(buf, self.frame_textures[self.backbuffer_index], .render_target);
        return buf;
    }

    pub fn endFrame(self: *Renderer) !void {
        const buf = self.cmd_bufs[self.frame_index % self.swapchain_desc.texture_num];
        gpu.ensureTextureState(buf, self.frame_textures[self.backbuffer_index], .present);
        try gpu.endCommandBuffer(buf);
        try gpu.submitQueue(self.swapchain_desc.queue, buf);

        try gpu.presentSwapchain(self.swapchain);
        self.frame_index += 1;
        try gpu.signalFence(self.swapchain_desc.queue, self.frame_fence, self.frame_index);
    }
};

const fl = @import("foxlily");
const gpu = fl.gpu;
const sdl = fl.sdl;

const std = @import("std");

const builtin = @import("builtin");
const native_os = builtin.os.tag;
