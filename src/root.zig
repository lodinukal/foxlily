const std = @import("std");

pub const Resource = @import("Resource.zig");
pub const gpu = @import("gpu.zig");
pub const sdl = @import("sdl.zig");
pub const media = @import("media.zig");
pub const render = @import("render.zig");
pub const util = @import("util.zig");
pub const math = @import("zmath.zig");

pub const Window = extern struct {
    pub const Error = error{
        WindowCreationFailed,
    };

    impl: *sdl.c.SDL_Window,
    cached_width: u32 = 0,
    cached_height: u32 = 0,

    pub const Flags = extern struct {
        fullscreen: bool = false,
        hidden: bool = false,
        borderless: bool = false,
        resizable: bool = false,
        minimized: bool = false,
        maximized: bool = false,
        high_pixel_density: bool = false,
        always_on_top: bool = false,
        not_focusable: bool = false,

        pub inline fn toBits(self: Flags) u32 {
            var bits: u32 = 0;
            bits |= if (self.fullscreen) sdl.c.SDL_WINDOW_FULLSCREEN else 0;
            bits |= if (self.hidden) sdl.c.SDL_WINDOW_HIDDEN else 0;
            bits |= if (self.borderless) sdl.c.SDL_WINDOW_BORDERLESS else 0;
            bits |= if (self.resizable) sdl.c.SDL_WINDOW_RESIZABLE else 0;
            bits |= if (self.minimized) sdl.c.SDL_WINDOW_MINIMIZED else 0;
            bits |= if (self.maximized) sdl.c.SDL_WINDOW_MAXIMIZED else 0;
            bits |= if (self.high_pixel_density) sdl.c.SDL_WINDOW_HIGH_PIXEL_DENSITY else 0;
            bits |= if (self.always_on_top) sdl.c.SDL_WINDOW_ALWAYS_ON_TOP else 0;
            bits |= if (self.not_focusable) sdl.c.SDL_WINDOW_NOT_FOCUSABLE else 0;
            return bits;
        }
    };

    pub const Event = sdl.c.SDL_Event;

    pub fn init(title: []const u8, width: u32, height: u32, flags: Flags) !Window {
        const created = sdl.c.SDL_CreateWindow(
            title.ptr,
            @intCast(width),
            @intCast(height),
            flags.toBits(),
        );
        if (created == null) {
            return error.WindowCreationFailed;
        }
        return .{
            .impl = created.?,
            .cached_width = width,
            .cached_height = height,
        };
    }

    pub fn deinit(self: *Window) void {
        sdl.c.SDL_DestroyWindow(self.impl);
    }

    pub const MessageBoxFlags = packed struct(u32) {
        returnkey_default: bool = false,
        escapekey_default: bool = false,
        _padding_1: u2 = 0,
        err: bool = false,
        warning: bool = false,
        info: bool = false,
        buttons_left_to_right: bool = false,
        buttons_right_to_left: bool = false,
        _padding_2: u23 = 0,

        pub const _info: MessageBoxFlags = .{
            .info = true,
        };
    };

    pub fn messageBox(self: Window, flags: MessageBoxFlags, title: []const u8, message: []const u8) void {
        const result = sdl.c.SDL_ShowSimpleMessageBox(
            @bitCast(flags),
            title.ptr,
            message.ptr,
            self.impl,
        );
        _ = result;
    }

    pub fn setTitle(self: *Window, title: [:0]const u8) void {
        sdl.c.SDL_SetWindowTitle(self.impl, title.ptr);
    }
};

/// an override for the gpu init, allocator
var gpu_init: ?gpu.InitDesc = null;

pub fn setGpuInitDesc(desc: gpu.InitDesc) void {
    gpu_init = desc;
}

const zstbi = @import("zstbi");
pub fn init(allocator: std.mem.Allocator) !void {
    zstbi.init(allocator);
    try gpu.init(gpu_init orelse .{ .allocator = allocator });
}

pub fn deinit() void {
    gpu.deinit();
    zstbi.deinit();
}

comptime {
    _ = Resource;
    _ = render;
    _ = Window;
    _ = sdl;
    _ = gpu;
    _ = media;
    _ = util;
}
