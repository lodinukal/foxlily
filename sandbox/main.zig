const sdl = ila.sdl;
const ila = @import("ila");

const std = @import("std");

const builtin = @import("builtin");
const native_os = builtin.os.tag;
const native_abi = builtin.abi;

const SCREEN_WIDTH = 640;
const SCREEN_HEIGHT = 480;

const App = struct {
    allocator: std.mem.Allocator,
    is_debug: bool,

    window: ila.Window,
    context: ila.render.Context,

    resources: Resources,
};
const AppError = sdl.SDLAppError || ila.gpu.Error || ila.Window.Error || error{OutOfMemory};

pub const main = sdl.main;
pub const std_options = sdl.std_options;

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
pub fn init(app_state: **App, args: []const [*:0]const u8) AppError!void {
    const gpa, const is_debug = gpa: {
        if (native_os == .wasi) break :gpa .{ std.heap.wasm_allocator, false };
        if (native_abi.isAndroid()) break :gpa .{ std.heap.c_allocator, false };
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };

    const app = gpa.create(App) catch @panic("App allocation failed");
    app_state.* = app;
    app.allocator = gpa;
    app.is_debug = is_debug;

    try ila.init(gpa);

    const window = try ila.Window.init("Runoff", 800, 600, .{
        .resizable = true,
    });

    app.context = try .fromWindow(app.allocator, window, .{});
    try app.context.start();

    app.resources.allocator = app.allocator;
    try app.resources.init();

    for (args) |arg| {
        std.log.info("arg: {s}", .{arg});
    }
}

pub fn tick(app: *App) AppError!void {
    const window_vp = app.context.viewport();
    const window_rect = app.context.rect();

    {
        // rotate the rect
        const mapped = app.resources.mapped;
        for (mapped) |*vertex| {
            const angle = std.math.pi / 180.0 * 0.01;
            const cos = std.math.cos(angle);
            const sin = std.math.sin(angle);
            const x = vertex.position[0] * cos - vertex.position[1] * sin;
            const y = vertex.position[0] * sin + vertex.position[1] * cos;
            vertex.position[0] = x;
            vertex.position[1] = y;
        }
    }

    {
        const cmd = try app.context.beginFrame();
        defer app.context.endFrame() catch |err| std.debug.panic("context.endFrame failed: {}", .{err});

        const b = app.context.backbuffer();

        cmd.beginRendering(.{
            .attachments = &.{b},
        });
        defer cmd.endRendering();

        cmd.setViewports(&.{window_vp});
        cmd.setScissors(&.{window_rect});
        cmd.clearAttachment(.init(.color(.{ 0x01.0 / 0xFF.0, 0x01.0 / 0xFF.0, 0x01.0 / 0xFF.0, 1.0 }), 0), window_rect);
        cmd.setPipelineLayout(app.resources.pipeline_layout);
        cmd.setPipeline(app.resources.pipeline);
        cmd.setVertexBuffer(0, app.resources.vertex_buffer, 0);
        cmd.setResourceSet(app.resources.set);
        cmd.draw(.{ .vertex_num = 6 });
    }
}

pub fn event(app: *App, ev: *sdl.c.SDL_Event) AppError!void {
    if (ev.type == sdl.c.SDL_EVENT_WINDOW_RESIZED) {
        app.context.resize(.{
            .x = @intCast(ev.window.data1),
            .y = @intCast(ev.window.data2),
        });
    }

    if (ev.type == sdl.c.SDL_EVENT_QUIT) {
        return error.SDLAppSuccess;
    }
}

pub fn deinit(app: *App, _: sdl.c.SDL_AppResult) void {
    app.resources.deinit();
    app.context.deinit();
    app.window.deinit();
    ila.deinit();

    if (app.is_debug) {
        _ = debug_allocator.deinit();
    }
}

const Vertex = extern struct {
    position: [3]f32,
    color: [3]f32,
};

const Resources = struct {
    allocator: std.mem.Allocator,

    pipeline_layout: *ila.gpu.PipelineLayout = undefined,
    pipeline: *ila.gpu.Pipeline = undefined,

    vertex_buffer: *ila.gpu.Buffer = undefined,
    mapped: []align(1) Vertex = undefined,

    sampler: *ila.gpu.Resource = undefined,

    set: *ila.gpu.ResourceSet = undefined,

    pub fn init(self: *Resources) !void {
        const allocator = self.allocator;
        self.* = .{ .allocator = allocator };
        errdefer self.deinit();
        self.pipeline_layout = try .init(allocator, .{
            .name = "graphics pipeline layout",
            .bindings = &.{
                .buffer(.readonly), // 0: mesh instance buffer
                .buffer(.readonly), // 1: instance buffer
                .buffer(.readonly), // 2:
                .sampler(), // 3: sampler
                .textureArray(4096, .readonly), // 4: textures
            },
            .constant = .sized(u64),
        });

        var graphics_pipeline_desc: ila.gpu.GraphicsPipelineDesc = .init(self.pipeline_layout);
        graphics_pipeline_desc.vertexAttributes(&.{
            .attr(0, @offsetOf(Vertex, "position"), .vec3, 0),
            .attr(1, @offsetOf(Vertex, "color"), .vec3, 0),
        });
        graphics_pipeline_desc.vertexStreams(&.{
            .stream(@sizeOf(Vertex), .vertex),
        });
        graphics_pipeline_desc.colorAttachments(&.{
            .colorAttachment(.RGBA8, .{}, .{}, .{}),
        });
        graphics_pipeline_desc.addShader(.vertex(.dxil, @embedFile("compiled_shaders/triangle.vert.dxil")));
        graphics_pipeline_desc.addShader(.fragment(.dxil, @embedFile("compiled_shaders/triangle.frag.dxil")));
        graphics_pipeline_desc.addShader(.vertex(.spirv, @embedFile("compiled_shaders/triangle.vert.spv")));
        graphics_pipeline_desc.addShader(.fragment(.spirv, @embedFile("compiled_shaders/triangle.frag.spv")));
        graphics_pipeline_desc.addShader(.vertex(.metal, @embedFile("compiled_shaders/triangle.vert.msl")));
        graphics_pipeline_desc.addShader(.fragment(.metal, @embedFile("compiled_shaders/triangle.frag.msl")));
        self.pipeline = try .initGraphics(allocator, graphics_pipeline_desc);

        self.vertex_buffer = try .init(allocator, .{
            .name = "vertex buffer",
            .size = 6 * @sizeOf(Vertex),
            .location = .host_upload,
            .usage = .{ .vertex = true },
            .structure_stride = @sizeOf(Vertex),
        });

        const mapped_raw = try self.vertex_buffer.map(0, null);
        const mapped: []align(1) Vertex = @ptrCast(mapped_raw);
        // make a rect with 6 vertices
        mapped[0] = .{ .position = .{ -0.5, -0.5, 0 }, .color = .{ 1, 0, 0 } };
        mapped[1] = .{ .position = .{ 0.5, -0.5, 0 }, .color = .{ 0, 1, 0 } };
        mapped[2] = .{ .position = .{ -0.5, 0.5, 0 }, .color = .{ 0, 0, 1 } };
        mapped[3] = .{ .position = .{ 0.5, -0.5, 0 }, .color = .{ 0, 1, 0 } };
        mapped[4] = .{ .position = .{ 0.5, 0.5, 0 }, .color = .{ 1, 1, 0 } };
        mapped[5] = .{ .position = .{ -0.5, 0.5, 0 }, .color = .{ 0, 0, 1 } };
        self.mapped = mapped;

        self.sampler = try .initSampler(allocator, .{});

        self.set = try .init(allocator, self.pipeline_layout);
        try self.set.setResource(3, 0, self.sampler);
    }

    // pub const deinit = ;
    pub fn deinit(self: Resources) void {
        self.pipeline_layout.deinit();
        self.pipeline.deinit();
        self.vertex_buffer.unmap();
        self.vertex_buffer.deinit();
        self.sampler.deinit();
        self.set.deinit();
    }
};
