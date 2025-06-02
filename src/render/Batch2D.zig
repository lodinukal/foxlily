const Batch2D = @This();

const std = @import("std");
const ila = @import("../root.zig");

pub const Error = error{
    InvalidMaxQuadsPerFlush,
};

pub const batch2d_shaders = struct {
    pub const vertex_dxil: ila.gpu.ShaderDesc = .vertex(.dxil, @embedFile("../compiled_shaders/batch2d.vert.dxil"));
    pub const fragment_dxil: ila.gpu.ShaderDesc = .fragment(.dxil, @embedFile("../compiled_shaders/batch2d.frag.dxil"));
    pub const vertex_spirv: ila.gpu.ShaderDesc = .vertex(.spirv, @embedFile("../compiled_shaders/batch2d.vert.spirv"));
    pub const fragment_spirv: ila.gpu.ShaderDesc = .fragment(.spirv, @embedFile("../compiled_shaders/batch2d.frag.spirv"));
    pub const vertex_metal: ila.gpu.ShaderDesc = .vertex(.metal, @embedFile("../compiled_shaders/batch2d.vert.metal"));
    pub const fragment_metal: ila.gpu.ShaderDesc = .fragment(.metal, @embedFile("../compiled_shaders/batch2d.frag.metal"));
};

/// must be set before init
allocator: std.mem.Allocator,
/// must be set before init
context: *ila.render.Context,

vertices: std.ArrayListUnmanaged(ila.render.Buffer) = .empty,
filling_set: u32 = 0,
max_quads_per_flush: u32 = 0,
max_vertices_per_flush: u32 = 0, // max_quads_per_flush * 6

pipeline_layout: *ila.gpu.PipelineLayout = undefined,
pipeline: *ila.gpu.Pipeline = undefined,

cmd: ?*ila.gpu.CommandBuffer = null,

pub const Vertex = extern struct {
    position: [3]f32, // x, y, z, z is zindex for depth sorting
    color: [4]f32, // r, g, b
    texcoord: [2]f32 = .{ 0, 0 }, // u, v
    texture_index: u32 = 0, // index into the texture array, 0 is white texture, 1 is black texture
    corner_radius: [4]f32 = @splat(0), // radius for rounded corners, 0 means no rounded corners
    border_width: f32 = 0, // radius for border, 0 means no border
    border_color: [4]f32 = .{ 0, 0, 0, 0 }, // rgba for border color, 0 means no border
};

pub fn init(self: *Batch2D, max_quads_per_flush: u32) !void {
    if (max_quads_per_flush == 0) {
        return error.InvalidMaxQuadsPerFlush;
    }
    self.* = .{
        .allocator = self.allocator,
        .context = self.context,
        .max_quads_per_flush = max_quads_per_flush,
        .max_vertices_per_flush = @as(u32, max_quads_per_flush * 6),
    };
    try self.addNewVertexBuffer();

    self.pipeline_layout = try .init(self.allocator, .{
        .name = "Batch2D pipeline layout",
        .sets = &.{
            self.context.resources.resource_set_desc,
            self.context.resources.shared_constants_desc,
        },
    });
    errdefer self.pipeline_layout.deinit();

    var graphics_pipeline_desc: ila.gpu.GraphicsPipelineDesc = .init(self.pipeline_layout);
    graphics_pipeline_desc.vertexAttributes(&.{
        .attr(0, @offsetOf(Vertex, "position"), .vec3, 0),
        .attr(1, @offsetOf(Vertex, "color"), .vec4, 0),
        .attr(2, @offsetOf(Vertex, "texcoord"), .vec2, 0),
        .attr(3, @offsetOf(Vertex, "texture_index"), .u32, 0),
        .attr(4, @offsetOf(Vertex, "corner_radius"), .vec4, 0),
        .attr(5, @offsetOf(Vertex, "border_width"), .f32, 0),
        .attr(6, @offsetOf(Vertex, "border_color"), .vec4, 0),
    });
    graphics_pipeline_desc.vertexStreams(&.{
        .stream(@sizeOf(Vertex), .vertex),
    });
    const color_blend: ila.gpu.Blending = .{
        .src = .src_alpha,
        .dst = .one_minus_src_alpha,
        .op = .add,
    };
    const alpha_blend: ila.gpu.Blending = .{
        .src = .src_alpha,
        .dst = .one_minus_src_alpha,
        .op = .add,
    };
    graphics_pipeline_desc.colorAttachments(&.{
        .colorAttachment(.RGBA8, color_blend, alpha_blend, .{}),
    });
    graphics_pipeline_desc.depthAttachment(.{
        .write = true,
        .compare_op = .less,
    });
    graphics_pipeline_desc.depthClamp(true);
    graphics_pipeline_desc.depthStencilFormat(.D32);
    graphics_pipeline_desc.addShader(batch2d_shaders.vertex_dxil);
    graphics_pipeline_desc.addShader(batch2d_shaders.fragment_dxil);
    graphics_pipeline_desc.addShader(batch2d_shaders.vertex_spirv);
    graphics_pipeline_desc.addShader(batch2d_shaders.fragment_spirv);
    graphics_pipeline_desc.addShader(batch2d_shaders.vertex_metal);
    graphics_pipeline_desc.addShader(batch2d_shaders.fragment_metal);
    self.pipeline = try .initGraphics(self.allocator, graphics_pipeline_desc);
    errdefer self.pipeline.deinit();
}

pub fn deinit(self: *Batch2D) void {
    // self.vertices.deinit();
    // self.vertices = undefined;
    for (self.vertices.items) |*buffer| {
        buffer.deinit();
    }
    self.vertices.deinit(self.allocator);

    self.pipeline.deinit();
    self.pipeline = undefined;
    self.pipeline_layout.deinit();
    self.pipeline_layout = undefined;
}

pub fn associateCommandBuffer(self: *Batch2D, cmd: *ila.gpu.CommandBuffer) void {
    self.cmd = cmd;
}

pub fn reset(self: *Batch2D) void {
    self.filling_set = 0;

    for (self.vertices.items) |*buffer| {
        buffer.len = 0;
    }
}

/// cmd should be in a graphics command buffer state
pub fn flush(self: *Batch2D) void {
    if (self.filling_set == 0 and self.vertices.items[0].len == 0) {
        std.log.warn("Batch2D flush called with no vertices", .{});
        return;
    }
    const cmd = self.cmd orelse {
        std.log.err("Batch2D flush called without associated command buffer", .{});
        return;
    };

    cmd.setPipelineLayout(self.pipeline_layout);
    cmd.setPipeline(self.pipeline);
    for (0..self.filling_set + 1) |i| {
        const buffer = self.vertices.items[i];
        cmd.setVertexBuffer(0, buffer.buffer.?, 0);
        const num_vertices: u64 = @divExact(buffer.len, @sizeOf(Vertex));
        cmd.draw(.{ .vertex_num = @intCast(num_vertices) });
    }

    self.reset();
}

pub fn newDraw(self: *Batch2D) !void {
    self.filling_set += 1;
    if (self.filling_set >= self.vertices.items.len) {
        try self.addNewVertexBuffer();
    }
}

fn addNewVertexBuffer(
    self: *Batch2D,
) !void {
    const buffer = try ila.render.Buffer.initCapacity(self.allocator, .{
        .name = "Batch2D-vertices",
        .usage = .{ .vertex = true },
        .size = @sizeOf(Vertex) * @as(u64, self.max_quads_per_flush * 6), // 6 vertices per quad
        .location = .host_upload,
        .structure_stride = @sizeOf(Vertex),
    }, .always_map);
    try self.vertices.append(self.allocator, buffer);
}

pub const QuadDesc = struct {
    position: [3]f32 = .{ 0, 0, 0 }, // x, y, z, z is zindex for depth sorting
    anchor: [2]f32 = .{ 0.5, 0.5 }, // anchor point in the quad, 0.5 means center
    rotation: f32 = 0.0,
    size: [2]f32 = .{ 1, 1 }, // width, height
    color: [4]f32 = .{ 1, 1, 1, 1 }, // default color (white)
    texture_index: u32 = 0,
    corner_radius: f32 = 0.0, // radius for rounded corners, 0 means no rounded corners
    border_width: f32 = 0.0, // radius for border, 0 means no border
    border_color: [4]f32 = .{ 0, 0, 0, 0 }, // rgba for border color, 0 means no border
};

pub fn drawQuad(
    self: *Batch2D,
    desc: QuadDesc,
) void {
    // add 6 vertices for a quad
    const math = ila.math;

    const top_left_not_rotated: math.Vec = .{
        -desc.size[0] * desc.anchor[0],
        desc.size[1] * desc.anchor[1],
        0.0,
        0.0,
    };
    const top_right_not_rotated: math.Vec = .{
        desc.size[0] * (1 - desc.anchor[0]),
        desc.size[1] * desc.anchor[1],
        0.0,
        0.0,
    };
    const bottom_left_not_rotated: math.Vec = .{
        -desc.size[0] * desc.anchor[0],
        -desc.size[1] * (1 - desc.anchor[1]),
        0.0,
        0.0,
    };
    const bottom_right_not_rotated: math.Vec = .{
        desc.size[0] * (1 - desc.anchor[0]),
        -desc.size[1] * (1 - desc.anchor[1]),
        0.0,
        0.0,
    };
    const viewport = self.context.viewport();
    const position: math.Vec = .{
        desc.position[0] - viewport.width / 2,
        desc.position[1] - viewport.height / 2,
        1000 - desc.position[2], // z-index
        0.0, // w-component, not used in 2D
    };
    var top_left: math.Vec = undefined;
    var top_right: math.Vec = undefined;
    var bottom_left: math.Vec = undefined;
    var bottom_right: math.Vec = undefined;
    // apply rotation if needed
    if (desc.rotation != 0) {
        const rotation_matrix = math.rotationZ(desc.rotation);
        top_left = math.mul(top_left_not_rotated, rotation_matrix) + position;
        top_right = math.mul(top_right_not_rotated, rotation_matrix) + position;
        bottom_left = math.mul(bottom_left_not_rotated, rotation_matrix) + position;
        bottom_right = math.mul(bottom_right_not_rotated, rotation_matrix) + position;
    } else {
        // no rotation, just use the position
        top_left = top_left_not_rotated + position;
        top_right = top_right_not_rotated + position;
        bottom_left = bottom_left_not_rotated + position;
        bottom_right = bottom_right_not_rotated + position;
    }
    const vertex_base: Vertex = .{
        .position = undefined,
        .color = desc.color,
        .texcoord = .{ 0, 0 },
        .texture_index = desc.texture_index,
        .corner_radius = @splat(desc.corner_radius),
        .border_width = desc.border_width,
        .border_color = desc.border_color,
    };

    const top_left_vertex: Vertex = tl: {
        var tl: Vertex = vertex_base;
        tl.position = math.vecToArr3(top_left);
        tl.texcoord = .{ 0, 0 };
        break :tl tl;
    };
    const top_right_vertex: Vertex = tr: {
        var tr: Vertex = vertex_base;
        tr.position = math.vecToArr3(top_right);
        tr.texcoord = .{ 1, 0 };
        break :tr tr;
    };
    const bottom_left_vertex: Vertex = bl: {
        var bl: Vertex = vertex_base;
        bl.position = math.vecToArr3(bottom_left);
        bl.texcoord = .{ 0, 1 };
        break :bl bl;
    };
    const bottom_right_vertex: Vertex = br: {
        var br: Vertex = vertex_base;
        br.position = math.vecToArr3(bottom_right);
        br.texcoord = .{ 1, 1 };
        break :br br;
    };

    // create the vertices for the quad
    const vertices: [6]Vertex = .{
        top_left_vertex, // 0
        bottom_left_vertex, // 1
        top_right_vertex, // 2
        bottom_right_vertex, // 3
        bottom_left_vertex, // 4
        top_right_vertex, // 5
    };

    self.addVertices(vertices[0..]);
}

pub fn addVertices(self: *Batch2D, vertices: []const Vertex) void {
    const set = &self.vertices.items[self.filling_set];
    if (set.len + vertices.len * @sizeOf(Vertex) > self.max_vertices_per_flush * @sizeOf(Vertex)) {
        self.newDraw() catch |err| {
            std.log.err("Failed to add new vertex buffer to Batch2D: {s}", .{@errorName(err)});
            return;
        };
    }
    self.addVerticesAssumedCapacity(vertices) catch |err| {
        std.log.err("Failed to add vertices to Batch2D: {s}", .{@errorName(err)});
    };
}

pub fn addVerticesAssumedCapacity(
    self: *Batch2D,
    vertices: []const Vertex,
) !void {
    const set = &self.vertices.items[self.filling_set];
    try set.append(.{
        .context = self.context,
        .data = std.mem.sliceAsBytes(vertices),
        // redundant but for clarity, as its a host upload buffer
        .after = .vertex,
    });
}
