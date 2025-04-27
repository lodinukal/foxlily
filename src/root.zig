const std = @import("std");

pub const gpu = @import("gpu.zig");
pub const sdl = @import("sdl.zig");

pub const Window = extern struct {
    pub const Error = error{
        WindowCreationFailed,
    };

    impl: *sdl.c.SDL_Window,

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
        return Window{ .impl = created.? };
    }

    pub fn deinit(self: *Window) void {
        sdl.c.SDL_DestroyWindow(self.impl);
    }
};

pub fn Optional(comptime T: type) type {
    return extern struct {
        has_value: bool = false,
        value: T = undefined,

        pub const none: @This() = .{ .has_value = false };

        pub inline fn some(value: T) @This() {
            return .{ .has_value = true, .value = value };
        }

        pub inline fn to(self: @This()) ?T {
            return if (self.has_value) self.value else null;
        }

        pub inline fn toRef(self: @This()) ?*T {
            return if (self.has_value) @ptrCast(&self.value) else null;
        }
    };
}

/// external constant slice
pub fn Slice(comptime T: type) type {
    return extern struct {
        pub const Ptr = ?[*]const T;
        pub const ZigSlice = []const T;

        ptr: Ptr = null,
        len: usize = 0,

        pub inline fn one(ptr: *const T) @This() {
            return .{ .ptr = @ptrCast(ptr), .len = 1 };
        }

        pub inline fn from(slice: ZigSlice) @This() {
            return .{ .ptr = slice.ptr, .len = slice.len };
        }

        pub inline fn to(self: @This()) ZigSlice {
            return if (self.ptr) |ptr| ptr[0..self.len] else &.{};
        }
    };
}

/// external mutable slice
pub fn MutableSlice(comptime T: type) type {
    return extern struct {
        pub const Ptr = ?[*]T;
        pub const ZigSlice = []T;

        ptr: Ptr = null,
        len: usize = 0,

        pub inline fn one(ptr: *const T) @This() {
            return .{ .ptr = @ptrCast(ptr), .len = 1 };
        }

        pub inline fn from(slice: ZigSlice) @This() {
            return .{ .ptr = slice.ptr, .len = slice.len };
        }

        pub inline fn to(self: @This()) ZigSlice {
            return if (self.ptr) |ptr| ptr[0..self.len] else &.{};
        }
    };
}
