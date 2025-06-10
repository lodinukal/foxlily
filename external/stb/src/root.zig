const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

pub const Image = @import("Image.zig");
pub const TrueType = @import("TrueType.zig");
pub const Rectpack = @import("Rectpack.zig");

pub fn init(allocator: std.mem.Allocator) void {
    assert(mem_allocator == null);
    mem_allocator = allocator;
    mem_allocations = std.AutoHashMap(usize, usize).init(allocator);

    zstbMallocPtr = @ptrCast(&zstbMalloc);
    zstbReallocPtr = @ptrCast(&zstbRealloc);
    zstbFreePtr = @ptrCast(&zstbFree);
}

pub fn deinit() void {
    assert(mem_allocator != null);
    assert(mem_allocations.?.count() == 0);

    Image.setFlipVerticallyOnLoad(false);
    Image.setFlipVerticallyOnWrite(false);

    mem_allocations.?.deinit();
    mem_allocations = null;
    mem_allocator = null;
}

pub fn isInitialized() bool {
    return mem_allocator != null;
}

var mem_allocator: ?std.mem.Allocator = null;
var mem_allocations: ?std.AutoHashMap(usize, usize) = null;
var mem_mutex: std.Thread.Mutex = .{};
const mem_alignment = 16;

extern var zstbMallocPtr: ?*const fn (size: usize) callconv(.C) ?*anyopaque;

pub fn zstbMalloc(size: usize) callconv(.C) ?*anyopaque {
    mem_mutex.lock();
    defer mem_mutex.unlock();

    const mem = mem_allocator.?.alignedAlloc(
        u8,
        .fromByteUnits(mem_alignment),
        size,
    ) catch @panic("zstb: out of memory");

    mem_allocations.?.put(@intFromPtr(mem.ptr), size) catch @panic("zstb: out of memory");

    return mem.ptr;
}

extern var zstbReallocPtr: ?*const fn (ptr: ?*anyopaque, size: usize) callconv(.C) ?*anyopaque;

pub fn zstbRealloc(ptr: ?*anyopaque, size: usize) callconv(.C) ?*anyopaque {
    mem_mutex.lock();
    defer mem_mutex.unlock();

    const old_size = if (ptr != null) mem_allocations.?.get(@intFromPtr(ptr.?)).? else 0;
    const old_mem = if (old_size > 0)
        @as([*]align(mem_alignment) u8, @ptrCast(@alignCast(ptr)))[0..old_size]
    else
        @as([*]align(mem_alignment) u8, undefined)[0..0];

    const new_mem = mem_allocator.?.realloc(old_mem, size) catch @panic("zstb: out of memory");

    if (ptr != null) {
        const removed = mem_allocations.?.remove(@intFromPtr(ptr.?));
        std.debug.assert(removed);
    }

    mem_allocations.?.put(@intFromPtr(new_mem.ptr), size) catch @panic("zstb: out of memory");

    return new_mem.ptr;
}

extern var zstbFreePtr: ?*const fn (maybe_ptr: ?*anyopaque) callconv(.C) void;

pub fn zstbFree(maybe_ptr: ?*anyopaque) callconv(.C) void {
    if (maybe_ptr) |ptr| {
        mem_mutex.lock();
        defer mem_mutex.unlock();

        const size = mem_allocations.?.fetchRemove(@intFromPtr(ptr)).?.value;
        const mem = @as([*]align(mem_alignment) u8, @ptrCast(@alignCast(ptr)))[0..size];
        mem_allocator.?.free(mem);
    }
}

comptime {
    _ = Image;
    _ = TrueType;
}
