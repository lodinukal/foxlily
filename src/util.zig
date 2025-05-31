const std = @import("std");

/// Memory but the lifetime is managed as an invariant to prevent accidental mutation or deallocation.
pub const Buffer = union(enum) {
    allocated: struct {
        allocator: std.mem.Allocator,
        data: []u8,
    },
    mutable: []u8,
    static: []const u8,

    pub const empty: Buffer = .{ .static = &.{} };

    pub fn initStatic(data: []const u8) Buffer {
        return .{ .static = data };
    }

    pub fn initMutable(data: []u8) Buffer {
        return .{ .mutable = data };
    }

    pub fn dupe(
        allocator: std.mem.Allocator,
        data: []const u8,
    ) !Buffer {
        const duped_data = try allocator.dupe(u8, data);
        return .{ .allocated = .{ .allocator = allocator, .data = duped_data } };
    }

    pub fn deinit(self: Buffer) void {
        switch (self) {
            .allocated => |allocated| {
                allocated.allocator.free(allocated.data);
            },
            .static => {},
            .mutable => {},
        }
    }

    pub fn constSlice(self: Buffer) []const u8 {
        return switch (self) {
            .allocated => |allocated| allocated.data,
            .mutable => |mutable| mutable,
            .static => |static| static,
        };
    }

    pub fn slice(self: Buffer) ?[]u8 {
        return switch (self) {
            .allocated => |allocated| allocated.data,
            .mutable => |mutable| mutable,
            else => null,
        };
    }
};
