pub fn Handle(comptime Of: type) type {
    return enum(u32) {
        const T = Of;
        null = std.math.maxInt(u32),
        _,
    };
}

/// a static pool of objects, makes assumption that never max(u32) objects or more
pub fn Pool(comptime Of: type, comptime Backing: type) type {
    std.debug.assert(@typeInfo(Backing) == .int); // Pool backing must be an integer type
    std.debug.assert(@typeInfo(Backing).int.signedness == .unsigned); // Pool backing must be an unsigned integer type
    const null_value = std.math.maxInt(Backing);
    const Node = union(enum) {
        obj: Of,
        next_free: ?usize,
    };
    return struct {
        nodes: []Node,
        first_free: ?usize = null,
        used: usize = 0,

        pub fn memoryRequirement(size: usize) usize {
            return @sizeOf(Node) * size;
        }

        pub fn init(self: *@This(), allocator: std.mem.Allocator, size: usize) !void {
            std.debug.assert(size < null_value); // Pool size too large
            self.* = .{ .nodes = try allocator.alloc(Node, size) };
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.nodes);
        }

        pub fn alloc(self: *@This()) !struct { usize, *Of } {
            if (self.first_free) |index| {
                const node = &self.nodes[index];
                self.first_free = node.next_free;
                node.* = .{ .obj = undefined };
                return .{ index, &node.obj };
            }
            if (self.used == self.nodes.len) {
                return error.TooManyObjects;
            }
            const index = self.used;
            self.used += 1;
            self.nodes[index] = .{ .obj = undefined };
            return .{ index, &self.nodes[index].obj };
        }

        pub fn free(self: *@This(), index: usize) void {
            if (index == null_value) {
                return;
            }
            self.nodes[index] = .{ .next_free = self.first_free };
            self.first_free = index;
        }

        pub fn get(self: *@This(), index: usize) ?*Of {
            if (index == null_value) {
                return null;
            }
            return &self.nodes[index].obj;
        }
    };
}

const std = @import("std");
