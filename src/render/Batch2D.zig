const Batch = @This();

const std = @import("std");
const ila = @import("../root.zig");

pub const Error = error{
    InvalidMaxQuadsPerFlush,
};

pub const batch_shaders = struct {
    pub const vertex_dxil: ila.gpu.ShaderDesc = .vertex(.dxil, @embedFile("../compiled_shaders/batch2d.vert.dxil"));
    pub const fragment_dxil: ila.gpu.ShaderDesc = .fragment(.dxil, @embedFile("../compiled_shaders/batch2d.frag.dxil"));
    pub const vertex_spirv: ila.gpu.ShaderDesc = .vertex(.spirv, @embedFile("../compiled_shaders/batch2d.vert.spirv"));
    pub const fragment_spirv: ila.gpu.ShaderDesc = .fragment(.spirv, @embedFile("../compiled_shaders/batch2d.frag.spirv"));
    pub const vertex_metal: ila.gpu.ShaderDesc = .vertex(.metal, @embedFile("../compiled_shaders/batch2d.vert.metal"));
    pub const fragment_metal: ila.gpu.ShaderDesc = .fragment(.metal, @embedFile("../compiled_shaders/batch2d.frag.metal"));
};

/// determines which projection will be used for the batch
pub const Layer = enum {
    world,
    ui,
};

/// must be set before init
allocator: std.mem.Allocator,
/// must be set before init
context: *ila.render.Context,

layer_vertices: [@typeInfo(Layer).@"enum".fields.len]std.ArrayListUnmanaged(ila.render.Buffer) = @splat(.empty),
layers_sets: [@typeInfo(Layer).@"enum".fields.len]u32 = @splat(0),
max_quads_per_flush: u32 = 0,
max_vertices_per_flush: u32 = 0, // max_quads_per_flush * 6

pipeline_layout: *ila.gpu.PipelineLayout = undefined,
pipeline: *ila.gpu.Pipeline = undefined,

pub const VertexFlags = packed struct(u32) {
    is_sdf: bool = false, // if true, the texture is an SDF texture (dont use the square texture)
    _: u31 = 0, // padding to 32 bits
};

pub const Vertex = extern struct {
    position: [3]f32, // x, y, z, z is zindex for depth sorting
    color: [4]f32, // r, g, b
    texcoord: [2]f32 = .{ 0, 0 }, // u, v
    texture_texcoord: [2]f32 = .{ 0, 0 }, // u, v
    texture_index: u32 = 0, // index into the texture array, 0 is white texture, 1 is black texture
    corner_radius: [4]f32 = @splat(0), // radius for rounded corners, 0 means no rounded corners
    border_width: f32 = 0, // radius for border, 0 means no border
    border_color: [4]f32 = .{ 0, 0, 0, 0 }, // rgba for border color, 0 means no border
    flags: VertexFlags = .{},
};

pub fn init(self: *Batch, max_quads_per_flush: u32) !void {
    if (max_quads_per_flush == 0) {
        return error.InvalidMaxQuadsPerFlush;
    }
    self.* = .{
        .allocator = self.allocator,
        .context = self.context,
        .max_quads_per_flush = max_quads_per_flush,
        .max_vertices_per_flush = @as(u32, max_quads_per_flush * 6),
    };
    try self.addNewVertexBuffer(.ui);

    self.pipeline_layout = try .init(self.allocator, .{
        .name = "Batch pipeline layout",
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
        .attr(3, @offsetOf(Vertex, "texture_texcoord"), .vec2, 0),
        .attr(4, @offsetOf(Vertex, "texture_index"), .u32, 0),
        .attr(5, @offsetOf(Vertex, "corner_radius"), .vec4, 0),
        .attr(6, @offsetOf(Vertex, "border_width"), .f32, 0),
        .attr(7, @offsetOf(Vertex, "border_color"), .vec4, 0),
        .attr(8, @offsetOf(Vertex, "flags"), .u32, 0),
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
        .src = .zero,
        .dst = .zero,
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
    graphics_pipeline_desc.addShader(batch_shaders.vertex_dxil);
    graphics_pipeline_desc.addShader(batch_shaders.fragment_dxil);
    graphics_pipeline_desc.addShader(batch_shaders.vertex_spirv);
    graphics_pipeline_desc.addShader(batch_shaders.fragment_spirv);
    graphics_pipeline_desc.addShader(batch_shaders.vertex_metal);
    graphics_pipeline_desc.addShader(batch_shaders.fragment_metal);
    self.pipeline = try .initGraphics(self.allocator, graphics_pipeline_desc);
    errdefer self.pipeline.deinit();
}

pub fn deinit(self: *Batch) void {
    for (&self.layer_vertices) |*layer| {
        for (layer.items) |*buffer| {
            buffer.deinit();
        }
        layer.deinit(self.allocator);
    }

    self.pipeline.deinit();
    self.pipeline = undefined;
    self.pipeline_layout.deinit();
    self.pipeline_layout = undefined;
}

pub fn reset(self: *Batch) void {
    self.layers_sets = @splat(0);

    for (&self.layer_vertices) |layer| {
        for (layer.items) |*buffer| {
            buffer.len = 0;
        }
    }
}

/// cmd should be in a graphics command buffer state
pub fn flush(self: *Batch, cmd: *ila.gpu.CommandBuffer, layer: Layer) void {
    self.draw(cmd, layer);
    self.reset();
}

/// cmd should be in a graphics command buffer state
/// should be using `flush` if this is the last in a frame
pub fn draw(self: *Batch, cmd: *ila.gpu.CommandBuffer, layer: Layer) void {
    const layer_index: usize = @intFromEnum(layer);
    const vertices = &self.layer_vertices[layer_index];
    const filling_set: u32 = self.layers_sets[layer_index];
    if (filling_set == 0 and vertices.items[0].len == 0) {
        return;
    }
    switch (layer) {
        .ui => {
            const frame_constants = self.context.resources.currentFrameConstants();
            frame_constants.projection = ila.math.orthographicOffCenterLh(
                0,
                frame_constants.frame_size[0],
                frame_constants.frame_size[1],
                0,
                0.0,
                10000,
            );
        },
        else => @panic("TODO WORLD LAYER PROJECTION"),
    }

    cmd.setPipelineLayout(self.pipeline_layout);
    cmd.setPipeline(self.pipeline);
    for (0..filling_set + 1) |i| {
        const buffer = vertices.items[i];
        cmd.setVertexBuffer(0, buffer.buffer.?, 0);
        const num_vertices: u64 = @divExact(buffer.len, @sizeOf(Vertex));
        cmd.draw(.{ .vertex_num = @intCast(num_vertices) });
    }
}

pub fn newDraw(self: *Batch, layer: Layer) !void {
    const layer_index: usize = @intFromEnum(layer);
    self.layers_sets[layer_index] += 1;
    if (self.layers_sets[layer_index] >= self.layer_vertices[layer_index].items.len) {
        try self.addNewVertexBuffer(layer);
    }
}

fn addNewVertexBuffer(self: *Batch, layer: Layer) !void {
    const layer_index: usize = @intFromEnum(layer);
    const buffer = try ila.render.Buffer.initCapacity(self.allocator, .{
        .name = "Batch-vertices",
        .usage = .{ .vertex = true },
        .size = @sizeOf(Vertex) * @as(u64, self.max_quads_per_flush * 6), // 6 vertices per quad
        .location = .host_upload,
        .structure_stride = @sizeOf(Vertex),
    }, .always_map);
    try self.layer_vertices[layer_index].append(self.allocator, buffer);
}

pub const UITextDesc = struct {
    font_atlas: *const ila.Resource.FontAtlas, // the font atlas to use for rendering text
    font_image_index: u32 = 0, // index into the font atlas texture array
    string: []const u8,

    x: ?*f32 = null,
    y: ?*f32 = null,
    scale: f32 = 1.0,
    position: [3]f32 = .{ 0, 0, 0 },
    color: [4]f32 = .{ 1, 1, 1, 1 }, // default white color
    stroke_width: f32 = 0.0, // width of the stroke, 0 means no stroke
    stroke_color: [4]f32 = .{ 0, 0, 0, 1 }, // color of the stroke, default is black
    line_height_modifier: f32 = 1.0, // multiplier for line height, 1.0 means no change
    kerning: f32 = 0.0, // additional space between characters, 0 means no additional space
};

pub fn drawText(self: *Batch, desc: UITextDesc) void {
    var temp_x: f32 = 0;
    var temp_y: f32 = 0;

    const x: *f32 = if (desc.x) |x| x else &temp_x;
    const y: *f32 = if (desc.y) |y| y else &temp_y;

    const origin_x: f32 = x.*;
    for (desc.string) |char| {
        if (char == '\n') {
            x.* = origin_x; // reset x to origin on newline
            y.* += desc.font_atlas.font_size * desc.line_height_modifier; // move y down by scale
            continue;
        }

        const quad = desc.font_atlas.getCharQuadMoving(char, x, y);
        const position_top_left = quad.topLeft();
        // const aspect_ratio: f32 = quad.width() / quad.height();
        self.drawQuad(.{
            .position = .{
                desc.position[0] + position_top_left[0],
                desc.position[1] + position_top_left[1],
                desc.position[2],
            }, // use the center of the quad for position
            .anchor = .{ 0, 0 },
            .rotation = 0.0,
            .size = .{ quad.width() * desc.scale, quad.height() * desc.scale }, // use the quad size
            .color = desc.color,
            .flags = .{ .is_sdf = true }, // use SDF texture
            .texture_index = desc.font_image_index, // use the font atlas texture
            .uv_top_left = quad.uv_top_left,
            .uv_bottom_right = quad.uv_bottom_right,
            .border_width = desc.stroke_width,
            .border_color = desc.stroke_color,
        });

        x.* += desc.kerning;
    }
    x.* = origin_x;
    y.* += desc.scale * desc.line_height_modifier;

    if (desc.x) |passed_x| passed_x.* = x.*;
    if (desc.y) |passed_y| passed_y.* = y.*;
}

pub const UIQuadDesc = struct {
    position: [3]f32 = .{ 0, 0, 0 }, // x, y, z, z is zindex for depth sorting
    anchor: [2]f32 = .{ 0.5, 0.5 }, // anchor point in the quad, 0.5 means center
    rotation: f32 = 0.0,
    size: [2]f32 = .{ 1, 1 }, // width, height
    color: [4]f32 = .{ 1, 1, 1, 1 }, // default color (white)
    texture_index: u32 = 0,
    corner_radius: f32 = 0.0, // radius for rounded corners, 0 means no rounded corners
    border_width: f32 = 0.0, // radius for border, 0 means no border
    border_color: [4]f32 = .{ 0, 0, 0, 0 }, // rgba for border color, 0 means no border

    uv_top_left: [2]f32 = .{ 0, 0 }, // offset for texture coordinates, default is (0, 0)
    uv_bottom_right: [2]f32 = .{ 1, 1 }, // offset for texture coordinates, default is (1, 1)

    flags: VertexFlags = .{},
};

pub fn drawQuad(
    self: *Batch,
    desc: UIQuadDesc,
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

    const position: math.Vec = math.loadArr3(desc.position);
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
        .texture_texcoord = desc.uv_top_left, // default texture coordinates
        .texture_index = desc.texture_index,
        .corner_radius = @splat(desc.corner_radius),
        .border_width = desc.border_width,
        .border_color = desc.border_color,
        .flags = desc.flags,
    };

    const top_left_vertex: Vertex = tl: {
        var tl: Vertex = vertex_base;
        tl.position = math.vecToArr3(top_left);
        tl.texcoord = .{ 0, 0 }; // 0, 0
        tl.texture_texcoord = desc.uv_top_left;
        break :tl tl;
    };
    const top_right_vertex: Vertex = tr: {
        var tr: Vertex = vertex_base;
        tr.position = math.vecToArr3(top_right);
        tr.texcoord = .{ 1, 0 };
        tr.texture_texcoord = .{ desc.uv_bottom_right[0], desc.uv_top_left[1] }; // 1, 0
        break :tr tr;
    };
    const bottom_left_vertex: Vertex = bl: {
        var bl: Vertex = vertex_base;
        bl.position = math.vecToArr3(bottom_left);
        bl.texcoord = .{ 0, 1 };
        bl.texture_texcoord = .{ desc.uv_top_left[0], desc.uv_bottom_right[1] }; // 0, 1
        break :bl bl;
    };
    const bottom_right_vertex: Vertex = br: {
        var br: Vertex = vertex_base;
        br.position = math.vecToArr3(bottom_right);
        br.texcoord = .{ 1, 1 };
        br.texture_texcoord = .{ desc.uv_bottom_right[0], desc.uv_bottom_right[1] }; // 1, 1
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

    self.addVertices(vertices[0..], .ui);
}

pub fn addVertices(self: *Batch, vertices: []const Vertex, layer: Layer) void {
    const layer_index: usize = @intFromEnum(layer);
    const filling_set: u32 = self.layers_sets[layer_index];
    const set = &self.layer_vertices[layer_index].items[filling_set];
    if (set.len + vertices.len * @sizeOf(Vertex) > self.max_vertices_per_flush * @sizeOf(Vertex)) {
        self.newDraw(layer) catch |err| {
            std.log.err("Failed to add new vertex buffer to Batch: {s}", .{@errorName(err)});
            return;
        };
    }
    self.addVerticesAssumedCapacity(vertices, layer) catch |err| {
        std.log.err("Failed to add vertices to Batch: {s}", .{@errorName(err)});
    };
}

pub fn addVerticesAssumedCapacity(self: *Batch, vertices: []const Vertex, layer: Layer) !void {
    const layer_index: usize = @intFromEnum(layer);
    const filling_set: u32 = self.layers_sets[layer_index];
    const set = &self.layer_vertices[layer_index].items[filling_set];
    try set.append(.{
        .context = self.context,
        .data = std.mem.sliceAsBytes(vertices),
        // redundant but for clarity, as its a host upload buffer
        .after = .vertex,
    });
}
