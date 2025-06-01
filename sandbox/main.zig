const sdl = ila.sdl;
const ila = @import("ila");

const std = @import("std");

const builtin = @import("builtin");
const native_os = builtin.os.tag;
const native_abi = builtin.abi;

const logic_rate = 120;
const logic_time: i128 = @divTrunc(std.time.ns_per_s, logic_rate);
const delta_time: f64 = 1.0 / (logic_rate * 1.0);

const App = struct {
    allocator: std.mem.Allocator,
    is_debug: bool,

    window: ila.Window,
    context: ila.render.Context,

    resources: Resources,

    pukeko_image: ila.Resource.Image = undefined,
    pukeko_texture: ila.render.Texture = undefined,
    accumulated_time: i128 = 0,
};
const AppError = sdl.SDLAppError || ila.gpu.Error || ila.Window.Error || error{ OutOfMemory, OutOfBounds } ||
    error{ InvalidImageFormat, ImageInitFailed } || error{TransferNotInProgress} || error{PathTooLong} ||
    error{NoBuffer};

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
    try ila.init(gpa);
    errdefer ila.deinit();

    const app = gpa.create(App) catch @panic("App allocation failed");
    errdefer gpa.destroy(app);
    app_state.* = app;
    app.* = .{
        .allocator = gpa,
        .is_debug = is_debug,
        .window = try .init("sandbox", 800, 600, .{
            .resizable = true,
        }),
        .context = try .fromWindow(app.allocator, app.window, .{
            .immediate = true,
        }),
        .resources = .{ .allocator = gpa, .context = &app.context },
    };
    try app.context.start();

    // Load an image asset
    app.pukeko_image = ila.Resource.Image.loadFromPath(app.allocator, "assets/images/pukeko.jpg") catch |err| {
        std.log.info("could not load pukeko image: {}", .{err});
        return err;
    };
    app.pukeko_texture = ila.render.Texture.fromImage(app.allocator, .{
        .context = &app.context,
        .image = &app.pukeko_image,
    }) catch |err| {
        std.log.info("could not create pukeko texture: {}", .{err});
        return err;
    };

    try app.resources.init();
    _ = app.context.resources.addTexture(app.pukeko_texture.srv.?) catch |err| {
        std.log.info("could not add pukeko texture in main set: {}", .{err});
        return err;
    };

    for (args) |arg| {
        std.log.info("arg: {s}", .{arg});
    }
}

pub fn deinit(app: *App, _: sdl.c.SDL_AppResult) void {
    app.pukeko_image.deinit();
    app.pukeko_texture.deinit();

    app.resources.deinit();
    app.context.deinit();
    app.window.deinit();
    ila.deinit();

    if (app.is_debug) {
        _ = debug_allocator.deinit();
    }
}

pub fn tick(app: *App) AppError!void {
    const window_vp = app.context.viewport();
    const window_rect = app.context.rect();

    app.accumulated_time += app.context.previous_frame_time;

    while (app.accumulated_time >= logic_time) : (app.accumulated_time -= logic_time) {
        // rotate the rect
        const mapped = app.resources.mapped;
        for (mapped) |*vertex| {
            const angle = std.math.pi / 180.0 * 30 * delta_time; // rotate 30 degrees per second
            const cos = std.math.cos(angle);
            const sin = std.math.sin(angle);
            const x = vertex.position[0] * cos - vertex.position[1] * sin;
            const y = vertex.position[0] * sin + vertex.position[1] * cos;
            vertex.position[0] = @floatCast(x);
            vertex.position[1] = @floatCast(y);
        }
    }

    {
        const frame_constants = app.context.resources.frameConstants(app.context.backbuffer_index);
        frame_constants.frame_size = .{
            @floatFromInt(window_rect.width),
            @floatFromInt(window_rect.height),
        };
        // frame_constants.projection = ila.math.orthographicRh(800, 600, 0.01, 1000);
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
        cmd.setResourceSet(app.context.resources.resource_set, 0);
        cmd.setResourceSet(app.context.resources.frameConstantsSet(app.context.backbuffer_index), 1);
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

const Vertex = extern struct {
    position: [3]f32,
    color: [3]f32,
    texcoord: [2]f32 = .{ 0, 0 },
    texture_index: u32 = 0,
};

const Resources = struct {
    allocator: std.mem.Allocator,
    context: *ila.render.Context,

    pipeline_layout: *ila.gpu.PipelineLayout = undefined,
    pipeline: *ila.gpu.Pipeline = undefined,

    vertex_buffer: *ila.gpu.Buffer = undefined,
    mapped: []align(1) Vertex = undefined,

    pub fn init(self: *Resources) !void {
        const allocator = self.allocator;
        self.* = .{ .allocator = allocator, .context = self.context };
        errdefer self.deinit();

        self.pipeline_layout = try .init(allocator, .{
            .name = "graphics pipeline layout",
            .sets = &.{
                self.context.resources.resource_set_desc,
                self.context.resources.shared_constants_desc,
            },
            .constant = .sized(u64),
        });

        var graphics_pipeline_desc: ila.gpu.GraphicsPipelineDesc = .init(self.pipeline_layout);
        graphics_pipeline_desc.vertexAttributes(&.{
            .attr(0, @offsetOf(Vertex, "position"), .vec3, 0),
            .attr(1, @offsetOf(Vertex, "color"), .vec3, 0),
            .attr(2, @offsetOf(Vertex, "texcoord"), .vec2, 0),
            .attr(3, @offsetOf(Vertex, "texture_index"), .u32, 0),
        });
        graphics_pipeline_desc.vertexStreams(&.{
            .stream(@sizeOf(Vertex), .vertex),
        });
        const color_blend: ila.gpu.Blending = .{
            .dst = .one,
            .src = .src_alpha,
            .op = .add,
        };
        const alpha_blend: ila.gpu.Blending = .{
            .src = .one,
            .dst = .one,
            .op = .add,
        };
        graphics_pipeline_desc.colorAttachments(&.{
            .colorAttachment(.RGBA8, color_blend, alpha_blend, .{}),
        });
        graphics_pipeline_desc.addShader(.vertex(.dxil, @embedFile("compiled_shaders/batch2d.vert.dxil")));
        graphics_pipeline_desc.addShader(.fragment(.dxil, @embedFile("compiled_shaders/batch2d.frag.dxil")));
        graphics_pipeline_desc.addShader(.vertex(.spirv, @embedFile("compiled_shaders/batch2d.vert.spirv")));
        graphics_pipeline_desc.addShader(.fragment(.spirv, @embedFile("compiled_shaders/batch2d.frag.spirv")));
        graphics_pipeline_desc.addShader(.vertex(.metal, @embedFile("compiled_shaders/batch2d.vert.metal")));
        graphics_pipeline_desc.addShader(.fragment(.metal, @embedFile("compiled_shaders/batch2d.frag.metal")));
        self.pipeline = try .initGraphics(allocator, graphics_pipeline_desc);

        self.vertex_buffer = try .init(allocator, .{
            .name = "vertex buffer",
            .size = 6 * @sizeOf(Vertex),
            .location = .host_upload,
            .usage = .{ .vertex = true },
            .structure_stride = @sizeOf(Vertex),
        });

        const mapped_raw = try self.vertex_buffer.map(.whole);
        const mapped: []align(1) Vertex = @ptrCast(mapped_raw);
        // make a rect with 6 vertices
        const texture_index: u32 = 2; // use the third texture in the resource set
        mapped[0] = .{ .position = .{ -0.5, -0.5, 0 }, .color = .{ 1, 0, 0 }, .texcoord = .{ 0, 0 }, .texture_index = texture_index };
        mapped[1] = .{ .position = .{ 0.5, -0.5, 0 }, .color = .{ 0, 1, 0 }, .texcoord = .{ 1, 0 }, .texture_index = texture_index };
        mapped[2] = .{ .position = .{ -0.5, 0.5, 0 }, .color = .{ 0, 0, 1 }, .texcoord = .{ 0, 1 }, .texture_index = texture_index };
        mapped[3] = .{ .position = .{ 0.5, -0.5, 0 }, .color = .{ 0, 1, 0 }, .texcoord = .{ 1, 0 }, .texture_index = texture_index };
        mapped[4] = .{ .position = .{ 0.5, 0.5, 0 }, .color = .{ 1, 1, 0 }, .texcoord = .{ 1, 1 }, .texture_index = texture_index };
        mapped[5] = .{ .position = .{ -0.5, 0.5, 0 }, .color = .{ 0, 0, 1 }, .texcoord = .{ 0, 1 }, .texture_index = texture_index };
        self.mapped = mapped;
    }

    // pub const deinit = ;
    pub fn deinit(self: Resources) void {
        self.pipeline_layout.deinit();
        self.pipeline.deinit();
        self.vertex_buffer.unmap();
        self.vertex_buffer.deinit();
    }
};
