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
    batch2d: ila.render.Batch2D,

    roboto_font_atlas: ila.Resource.FontAtlas = undefined,
    roboto_font_atlas_texture: ila.render.Texture = undefined,
    roboto_font_atlas_id: u32 = undefined,
    pukeko_image: ila.Resource.Image = undefined,
    pukeko_texture: ila.render.Texture = undefined,
    accumulated_time: i128 = 0,
    running_time: f32 = 0.0,
};
const AppError = sdl.SDLAppError || ila.gpu.Error || ila.Window.Error || error{ OutOfMemory, OutOfBounds } ||
    error{ InvalidImageFormat, ImageInitFailed } || error{TransferNotInProgress} || error{PathTooLong} ||
    error{NoBuffer} || ila.render.Batch2D.Error;

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
            .clear_color = .{ 1.0, 1.0, 1.0, 1.0 },
        }),
        .batch2d = .{
            .context = &app.context,
            .allocator = app.allocator,
        },
        // .resources = .{ .allocator = gpa, .context = &app.context },
    };
    try app.context.start();
    errdefer app.context.deinit();

    try app.batch2d.init(8192); // 8192 quads
    errdefer app.batch2d.deinit();

    // Load a font atlas
    app.roboto_font_atlas = ila.Resource.FontAtlas.loadTTFFromPath(
        app.allocator,
        "assets/fonts/Roboto.ttf",
        1024,
        1024,
    ) catch |err| {
        std.log.info("could not load roboto font atlas: {}", .{err});
        return error.Unknown;
    };

    app.roboto_font_atlas.image.writeToFile("roboto_font_atlas.hdr", .hdr) catch |err| {
        std.log.info("could not write roboto font atlas to file: {}", .{err});
        return error.Unknown;
    };

    app.roboto_font_atlas_texture = ila.render.Texture.fromImage(app.allocator, .{
        .context = &app.context,
        .image = &app.roboto_font_atlas.image,
    }) catch |err| {
        std.log.info("could not create roboto font atlas texture: {}", .{err});
        return err;
    };

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

    // try app.resources.init();
    _ = app.context.resources.addTexture(app.pukeko_texture.srv.?) catch |err| {
        std.log.info("could not add pukeko texture in main set: {}", .{err});
        return err;
    };

    app.roboto_font_atlas_id = app.context.resources.addTexture(app.roboto_font_atlas_texture.srv.?) catch |err| {
        std.log.info("could not add roboto font atlas in main set: {}", .{err});
        return err;
    };

    for (args) |arg| {
        std.log.info("arg: {s}", .{arg});
    }
}

pub fn deinit(app: *App, _: sdl.c.SDL_AppResult) void {
    app.pukeko_image.deinit();
    app.pukeko_texture.deinit();
    app.roboto_font_atlas.deinit();
    app.roboto_font_atlas_texture.deinit();

    app.batch2d.deinit();
    app.context.deinit();
    app.window.deinit();
    ila.deinit();

    if (app.is_debug) {
        _ = debug_allocator.deinit();
    }
}

pub fn tick(app: *App) AppError!void {
    // const window_vp = app.context.viewport();
    // const window_rect = app.context.rect();

    const this_delta = if (app.context.previous_frame_time < std.time.ns_per_s / 2)
        @as(f64, @floatFromInt(app.context.previous_frame_time)) / (std.time.ns_per_s * 1.0)
    else
        delta_time;

    app.accumulated_time += app.context.previous_frame_time;
    app.running_time += @floatCast(this_delta);

    while (app.accumulated_time >= logic_time) : (app.accumulated_time -= logic_time) {
        // logic tick
    }

    {
        const cmd = try app.context.beginFrame();
        defer app.context.endFrame() catch |err| std.debug.panic("context.endFrame failed: {}", .{err});

        // const b = app.context.backbuffer();

        app.context.beginRendering();
        defer app.context.endRendering();

        defer app.batch2d.flush(cmd, .ui);

        const swaying_x = std.math.sin(app.running_time);

        // const hsl color calculation

        app.batch2d.drawText(.{
            .font_atlas = &app.roboto_font_atlas,
            .font_image_index = app.roboto_font_atlas_id,
            .string = "gurt: yo",
            .position = .{ 50, 50, 1 }, // center of the screen
            .color = .{ 1, 1, 1, 1 }, // white color
            .stroke_width = 2,
            .stroke_color = .{ 0.2, 0.2, 0.6, 1 }, // red stroke
            .scale = 1,
        });
        // try app.batch2d.newDraw(.ui);

        // app.batch2d.drawQuad(.{
        //     .position = .{ 500, 250, 10 },
        //     .anchor = .{ 0.5, 0.5 },
        //     .rotation = swaying_x * std.math.pi * 0.5,
        //     .size = .{ 400, 400 },
        //     .color = .{ 1, 1, 1, 1 }, // white color
        //     .texture_index = 2, // use the third texture in the resource set
        //     .border_width = 0.1,
        //     .border_color = .{ 0.2, 0.2, 0.6, 1 }, // red border
        //     .corner_radius = 0.2, // rounded corners
        // });

        app.batch2d.drawQuad(.{
            .position = .{ 150, 0, 30 }, // slightly behind the first quad
            .anchor = .{ 0.5, 1 },
            .rotation = 0,
            .size = .{ 300, 300 },
            .color = .{ 1, 1, 1, 1 }, // white color
            .texture_index = 2, // use the third texture in the resource set
            .border_color = .{ 0.2, 0.6, 0.2, 1 }, // green border
            .border_width = 0.1,
            .corner_radius = 1,
        });
        // try app.batch2d.newDraw(.ui);

        // draw a grid of them
        for (0..30) |r| {
            for (0..10) |g| {
                const r_f: f32 = @floatFromInt(r);
                const g_f: f32 = @floatFromInt(g);
                app.batch2d.drawQuad(.{
                    .position = .{ 100 + r_f * 50.0, 100 + g_f * 50.0, 25 },
                    .anchor = .{ 0.5, 0.5 },
                    .rotation = swaying_x * std.math.pi * 0.5,
                    .size = .{ 40, 40 },
                    .color = .{ r_f / 30, g_f / 10, 0, 1 }, // white color
                    .texture_index = 2, // use the third texture in the resource set
                    .corner_radius = 0.2, // rounded corners
                });
            }
        }
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
