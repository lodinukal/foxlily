const using_sdl_callbacks = @import("config").use_main_callbacks;

const std = @import("std");
pub const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    if (using_sdl_callbacks)
        @cDefine("SDL_MAIN_USE_CALLBACKS", {})
    else
        @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL_main.h");
});

// SDL utils

fn defaultInit(_: **anyopaque, _: []const [*:0]const u8) !void {}
fn defaultTick(_: ?*anyopaque) !void {}
fn defaultEvent(_: ?*anyopaque, _: *c.SDL_Event) !void {}
fn defaultDeinit(_: ?*anyopaque, _: c.SDL_AppResult) void {}

const root = @import("root");
const init = if (@hasDecl(root, "init")) root.init else defaultInit;
const deinit = if (@hasDecl(root, "deinit")) root.deinit else defaultDeinit;
const tick = if (@hasDecl(root, "tick")) root.tick else defaultTick;
const event = if (@hasDecl(root, "event")) root.event else defaultEvent;

pub const std_options: std.Options = .{
    .logFn = logFn,
};

fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix2 = if (scope == .default) "" else @tagName(scope) ++ " ";

    var buffer: [512]u8 = @splat(0);
    const text = std.fmt.bufPrintZ(&buffer, prefix2 ++ format ++ "\n", args) catch return;
    c.SDL_LogMessage(c.SDL_LOG_CATEGORY_APPLICATION, switch (message_level) {
        .debug => c.SDL_LOG_PRIORITY_DEBUG,
        .info => c.SDL_LOG_PRIORITY_INFO,
        .warn => c.SDL_LOG_PRIORITY_WARN,
        .err => c.SDL_LOG_PRIORITY_ERROR,
    }, text.ptr);
}

pub const SDLAppError = error{
    SDLAppFailure,
    SDLAppSuccess,
};

fn catchError(un: anytype, id: @TypeOf(.enum_literal)) c.SDL_AppResult {
    _ = un catch |err| switch (@as(anyerror, @errorCast(err))) {
        error.SDLAppFailure => return c.SDL_APP_FAILURE,
        error.SDLAppSuccess => return c.SDL_APP_SUCCESS,
        else => {
            var buffer: [512]u8 = @splat(0);
            _ = c.SDL_ShowSimpleMessageBox(
                c.SDL_MESSAGEBOX_ERROR,
                "Error",
                std.fmt.bufPrintZ(
                    &buffer,
                    @tagName(id) ++ ": unexpected error: {s}\nSee logs for more details",
                    .{@errorName(err)},
                ) catch @tagName(id),
                null,
            );
            return c.SDL_APP_FAILURE;
        },
    };
    return c.SDL_APP_CONTINUE;
}

fn SDL_AppInit(app_state: **anyopaque, argc: c_int, argv: [*]const [*:0]const u8) callconv(.c) c.SDL_AppResult {
    const args = argv[0..@intCast(argc)];
    return catchError(init(@ptrCast(@alignCast(app_state)), args), .SDL_AppInit);
}

fn SDL_AppIterate(app: *anyopaque) callconv(.c) c.SDL_AppResult {
    return catchError(tick(@ptrCast(@alignCast(app))), .SDL_AppIterate);
}

fn SDL_AppEvent(app: *anyopaque, ev: *c.SDL_Event) callconv(.c) c.SDL_AppResult {
    return catchError(event(@ptrCast(@alignCast(app)), ev), .SDL_AppEvent);
}

fn SDL_AppQuit(app: *anyopaque, result: c.SDL_AppResult) callconv(.c) void {
    if (result == c.SDL_APP_CONTINUE) return;
    deinit(@ptrCast(@alignCast(app)), result);
}

comptime {
    if (using_sdl_callbacks) {
        @export(&SDL_AppInit, .{ .name = "SDL_AppInit" });
        @export(&SDL_AppIterate, .{ .name = "SDL_AppIterate" });
        @export(&SDL_AppEvent, .{ .name = "SDL_AppEvent" });
        @export(&SDL_AppQuit, .{ .name = "SDL_AppQuit" });
    }
}

pub const main = if (using_sdl_callbacks) c.main else emulatedMain;

fn emulatedMain() !void {
    var buffer: [512]u8 = @splat(0);
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const args = try std.process.argsAlloc(allocator);
    const converted_args = try allocator.alloc([*:0]const u8, args.len);

    for (args, converted_args) |arg, *out| {
        out.* = arg.ptr;
    }

    var state: *allowzero anyopaque = @ptrFromInt(0);
    var result = catchError(init(@alignCast(@ptrCast(&state)), converted_args), .SDL_AppInit);
    if (result != c.SDL_APP_CONTINUE) return;

    loop: while (true) {
        var e: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&e)) {
            result = catchError(event(@alignCast(@ptrCast(state)), &e), .SDL_AppEvent);
            if (result != c.SDL_APP_CONTINUE) break :loop;
        }

        result = catchError(tick(@alignCast(@ptrCast(state))), .SDL_AppIterate);
        if (result != c.SDL_APP_CONTINUE) break :loop;
    }

    deinit(@alignCast(@ptrCast(state)), result);
}
