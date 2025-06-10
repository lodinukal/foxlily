pub const ErrorCode = enum(i32) {
    pub fn from(err: Error) ErrorCode {
        switch (err) {
            inline else => |narrowed_err| return @field(ErrorCode, @errorName(narrowed_err)),
        }
    }

    pub fn to(self: ErrorCode) Error {
        return @field(Error, @tagName(self));
    }

    Ok = 0,
    Unknown = -1,
    OutOfMemory = -2,
    NotImplemented = -3,
    AlreadyInitialized = -4,
    NotInitialized = -5,
    NullArgument = -6,
    InvalidArgument = -7,
    NoApi = -8,
    TooManyObjects = -9,
    Overflow = -10,

    // Gpu errors
    /// when a passed in device is invalid
    InvalidDevice = -100,
    InvalidCommandQueue = -101,
    InvalidCommandBuffer = -102,
    InvalidFence = -103,
    InvalidBuffer = -104,
    InvalidTexture = -105,
    InvalidPipelineLayout = -106,
    InvalidSwapchain = -107,
    InvalidResource = -108,
    InvalidResourceSet = -109,
    InvalidShaderStage = -110,

    // Resource errors
    InvalidResourceKind = -200,
    InvalidResourceBinding = -201,

    // Buffer errors
    BufferSizeZero = -300,
    BufferAlreadyMapped = -301,

    // Texture errors
    TextureSizeZero = -400,

    // Pipeline layout erros
    TooManyResourceBindings = -500,
    TooManyConstants = -501,
    TooLargeConstantSize = -502,

    // Swapchain errors
    SwapchainTooFewImages = -600,
    SwapchainTooManyImages = -601,

    // D3D12 errors
    D3D12InternalError = -1000,
};

pub const Error: type = blk: {
    var names: []const std.builtin.Type.Error = &.{};
    for (@typeInfo(ErrorCode).@"enum".fields) |field| {
        if (field.value < 0) {
            names = names ++ &[_]std.builtin.Type.Error{.{ .name = field.name }};
        }
    }
    break :blk @Type(.{ .error_set = names });
};
const gpu = @This();

pub const impl = struct {
    var api: ?Api = null;
    pub inline fn getApiOrPanic() Api {
        return api orelse @panic("gpu not initialized; call gpu.init(desc)");
    }

    pub fn call(fn_name: @TypeOf(.enum_literal), Ret: type, args: anytype) Ret {
        const mod: std.builtin.CallModifier = if (builtin.mode == .ReleaseFast) .always_inline else .auto;
        switch (getApiOrPanic()) {
            .d3d12 => if (comptime config.gpu_d3d12) {
                return @call(mod, @field(d3d12, @tagName(fn_name)), args);
            },
            .vulkan => if (comptime config.gpu_vulkan) {
                // return @call(.always_inline, @field(vulkan, @tagName(name)), args);
            },
            .metal => if (comptime config.gpu_metal) {
                // return @call(.always_inline, @field(metal, @tagName(name)), args);
            },
        }
        std.debug.panic("not implemented: " ++ @tagName(fn_name) ++ " on {s}", .{@tagName(getApiOrPanic())});
    }

    // backends
    const d3d12 = @import("gpu/d3d12.zig");
};

pub fn init(desc: gpu.InitDesc) Error!void {
    if (impl.api) |_| {
        return error.AlreadyInitialized;
    }
    if (comptime config.gpu_d3d12) {
        if (desc.api == .d3d12) {
            try impl.d3d12.init(desc);
            impl.api = .d3d12;
            return;
        }
    }
    if (comptime config.gpu_vulkan) {
        if (desc.api == .vulkan) {}
    }
    if (comptime config.gpu_metal) {
        if (desc.api == .metal) {}
    }
    return error.NoApi;
}

pub fn deinit() void {
    defer impl.api = null;
    switch (impl.getApiOrPanic()) {
        .d3d12 => if (comptime gpu.config.gpu_d3d12) {
            impl.d3d12.deinit();
        },
        .vulkan => {},
        .metal => {},
    }
}

/// maximum number of swapchain images
pub const MAX_SWAPCHAIN_IMAGES = 4;
/// used to specify the whole size of a buffer
pub const WHOLE_SIZE = std.math.maxInt(u64);
pub const WHOLE_SIZE_U32 = std.math.maxInt(u32);
/// maximum number of resource sets bound at once
pub const MAX_RESOURCE_SETS = 4;
/// maximum number of bindings in a resource set
pub const MAX_BINDINGS_PER_SET = 8;
/// maximum size of constants in bytes
pub const MAX_CONSTANT_SIZE = 128;
/// maximum number of viewports in a rasterization
pub const MAX_VIEWPORTS = 16;
/// maximum number of scissors in a rasterization
pub const MAX_SCISSORS = 16;
/// maximum number of attachments in a render pass
pub const MAX_ATTACHMENTS = 8;
/// maximum number of vertex buffers in a draw call
pub const MAX_VERTEX_BUFFERS = 8;
/// maximum number of vertex attributes in an input layout
pub const MAX_VERTEX_ATTRIBUTES = 16;

pub const Limits = struct {
    upload_buffer_texture_slice_alignment: u64 = 256,
    upload_buffer_texture_row_alignment: u64 = 256,
};

pub fn limits() Limits {
    return impl.call(.getLimits, Limits, .{});
}

pub const CommandQueue = opaque {
    pub inline fn primary() *CommandQueue {
        return impl.call(.primaryQueue, *CommandQueue, .{});
    }

    pub inline fn init(allocator: std.mem.Allocator, desc: CommandQueueDesc) Error!*CommandQueue {
        return impl.call(.initCommandQueue, Error!*CommandQueue, .{ allocator, desc });
    }
    pub inline fn deinit(queue: *CommandQueue) void {
        impl.call(.deinitCommandQueue, void, .{queue});
    }

    pub inline fn signalFence(queue: *CommandQueue, fence: *Fence, value: u64) Error!void {
        return impl.call(.signalFence, Error!void, .{ queue, fence, value });
    }

    pub inline fn waitFence(queue: *CommandQueue, fence: *Fence, value: u64) Error!void {
        return impl.call(.waitFence, Error!void, .{ queue, fence, value });
    }

    pub inline fn submit(queue: *CommandQueue, cmd: *CommandBuffer) Error!void {
        return impl.call(.submitQueue, Error!void, .{ queue, cmd });
    }
};
pub const CommandBuffer = opaque {
    pub inline fn init(allocator: std.mem.Allocator, queue: *CommandQueue) Error!*CommandBuffer {
        return impl.call(.initCommandBuffer, Error!*CommandBuffer, .{ allocator, queue });
    }
    pub inline fn deinit(cmd: *CommandBuffer) void {
        return impl.call(.deinitCommandBuffer, void, .{cmd});
    }

    pub inline fn begin(cmd: *CommandBuffer) Error!void {
        return impl.call(.beginCommandBuffer, Error!void, .{cmd});
    }
    pub inline fn end(cmd: *CommandBuffer) Error!void {
        return impl.call(.endCommandBuffer, Error!void, .{cmd});
    }
    pub inline fn setViewports(cmd: *CommandBuffer, viewports: []const Viewport) void {
        return impl.call(.setViewports, void, .{ cmd, viewports });
    }
    pub inline fn setScissors(cmd: *CommandBuffer, scissors: []const Rect) void {
        return impl.call(.setScissors, void, .{ cmd, scissors });
    }
    pub inline fn setDepthBounds(cmd: *CommandBuffer, min: f32, max: f32) void {
        return impl.call(.setDepthBounds, void, .{ cmd, min, max });
    }
    pub inline fn setStencilReference(cmd: *CommandBuffer, ref: u8) void {
        return impl.call(.setStencilReference, void, .{ cmd, ref });
    }
    pub inline fn clearAttachment(cmd: *CommandBuffer, clear: Clear, rect: Rect) void {
        return impl.call(.clearAttachment, void, .{ cmd, clear, rect });
    }
    pub inline fn clearBuffer(cmd: *CommandBuffer, desc: ClearBufferDesc) void {
        return impl.call(.clearBuffer, void, .{ cmd, desc });
    }
    pub inline fn clearTexture(cmd: *CommandBuffer, desc: ClearTextureDesc) void {
        return impl.call(.clearTexture, void, .{ cmd, desc });
    }
    pub inline fn setVertexBuffer(cmd: *CommandBuffer, slot: u32, buffer: *Buffer, offset: u64) void {
        return impl.call(.setVertexBuffer, void, .{ cmd, slot, buffer, offset });
    }
    pub inline fn setIndexBuffer(cmd: *CommandBuffer, buffer: *Buffer, offset: u64, kind: IndexKind) void {
        return impl.call(.setIndexBuffer, void, .{ cmd, buffer, offset, kind });
    }
    pub inline fn setPipelineLayout(cmd: *CommandBuffer, layout: *PipelineLayout) void {
        return impl.call(.setPipelineLayout, void, .{ cmd, layout });
    }
    pub inline fn setPipeline(cmd: *CommandBuffer, pipeline: *Pipeline) void {
        return impl.call(.setPipeline, void, .{ cmd, pipeline });
    }
    pub inline fn setResourceSet(cmd: *CommandBuffer, set: *ResourceSet, index: u32) void {
        return impl.call(.setResourceSet, void, .{ cmd, set, index });
    }
    pub inline fn setConstant(cmd: *CommandBuffer, data: []const u8) void {
        return impl.call(.setConstant, void, .{ cmd, data });
    }
    pub inline fn draw(cmd: *CommandBuffer, desc: Draw) void {
        return impl.call(.draw, void, .{ cmd, desc });
    }
    pub inline fn drawIndexed(cmd: *CommandBuffer, desc: DrawIndexed) void {
        return impl.call(.drawIndexed, void, .{ cmd, desc });
    }
    pub inline fn drawIndirect(cmd: *CommandBuffer, desc: DrawIndirect) void {
        return impl.call(.drawIndirect, void, .{ cmd, desc });
    }
    pub inline fn drawIndexedIndirect(cmd: *CommandBuffer, desc: DrawIndirect) void {
        return impl.call(.drawIndexedIndirect, void, .{ cmd, desc });
    }
    pub inline fn dispatch(cmd: *CommandBuffer, desc: Dispatch) void {
        return impl.call(.dispatch, void, .{ cmd, desc });
    }
    pub inline fn dispatchIndirect(cmd: *CommandBuffer, desc: DispatchIndirect) void {
        return impl.call(.dispatchIndirect, void, .{ cmd, desc });
    }
    pub inline fn copyBufferToBuffer(
        cmd: *CommandBuffer,
        dst: *Buffer,
        dst_offset: u64,
        src: *Buffer,
        src_offset: u64,
        size: u64,
    ) void {
        return impl.call(.copyBufferToBuffer, void, .{ cmd, dst, dst_offset, src, src_offset, size });
    }
    pub inline fn copyTextureToTexture(
        cmd: *CommandBuffer,
        dst: *Texture,
        dst_region_opt: ?TextureRegion,
        src: *Texture,
        src_region_opt: ?TextureRegion,
    ) void {
        return impl.call(.copyTextureToTexture, void, .{ cmd, dst, dst_region_opt, src, src_region_opt });
    }
    pub inline fn copyBufferToTexture(
        cmd: *CommandBuffer,
        dst: *Texture,
        dst_region_opt: ?TextureRegion,
        src: *Buffer,
        src_data_layout: TextureDataLayout,
        plane_flags: PlaneFlags,
    ) void {
        return impl.call(.copyBufferToTexture, void, .{ cmd, dst, dst_region_opt, src, src_data_layout, plane_flags });
    }
    pub inline fn copyTextureToBuffer(
        cmd: *CommandBuffer,
        dst: *Buffer,
        dst_data_layout: TextureDataLayout,
        src: *Texture,
        src_region_opt: ?TextureRegion,
    ) void {
        return impl.call(.copyTextureToBuffer, void, .{ cmd, dst, dst_data_layout, src, src_region_opt });
    }
    pub inline fn beginRendering(cmd: *CommandBuffer, attachments: Attachments) void {
        return impl.call(.beginRendering, void, .{ cmd, attachments });
    }
    pub inline fn endRendering(cmd: *CommandBuffer) void {
        return impl.call(.endRendering, void, .{cmd});
    }
    pub inline fn ensureTextureState(cmd: *CommandBuffer, texture: *Texture, state: TextureState) void {
        return impl.call(.ensureTextureState, void, .{ cmd, texture, state });
    }
    pub inline fn ensureBufferState(cmd: *CommandBuffer, b: *Buffer, state: BufferState) void {
        return impl.call(.ensureBufferState, void, .{ cmd, b, state });
    }
};

// how resources are bound to the pipeline
pub const PipelineLayout = opaque {
    pub inline fn init(allocator: std.mem.Allocator, desc: PipelineLayoutDesc) Error!*PipelineLayout {
        return impl.call(.initPipelineLayout, Error!*PipelineLayout, .{ allocator, desc });
    }
    pub inline fn deinit(layout: *PipelineLayout) void {
        impl.call(.deinitPipelineLayout, void, .{layout});
    }
};

pub const Pipeline = opaque {
    pub inline fn initGraphics(
        allocator: std.mem.Allocator,
        desc: GraphicsPipelineDesc,
    ) Error!*Pipeline {
        return impl.call(.initGraphicsPipeline, Error!*Pipeline, .{ allocator, desc });
    }
    pub inline fn initCompute(allocator: std.mem.Allocator, desc: ComputePipelineDesc) Error!*Pipeline {
        return impl.call(.initComputePipeline, Error!*Pipeline, .{ allocator, desc });
    }
    pub inline fn deinit(pipeline: *Pipeline) void {
        impl.call(.deinitPipeline, void, .{pipeline});
    }
};

pub const Buffer = opaque {
    pub const Range = extern struct {
        offset: u64 = 0,
        size: u64 = WHOLE_SIZE,

        pub const whole: Range = .{ .offset = 0, .size = WHOLE_SIZE };

        pub fn offsetRest(offset: u64) Range {
            return .{ .offset = offset, .size = WHOLE_SIZE };
        }

        pub fn offsetSize(offset: u64, size: u64) Range {
            return .{ .offset = offset, .size = size };
        }

        pub fn realSize(self: Range, buffer: *Buffer) u64 {
            if (self.size == WHOLE_SIZE) {
                return buffer.getDesc().size - self.offset;
            }
            return self.size;
        }
    };

    pub inline fn init(allocator: std.mem.Allocator, desc: BufferDesc) Error!*Buffer {
        return impl.call(.initBuffer, Error!*Buffer, .{ allocator, desc });
    }
    pub inline fn deinit(buffer: *Buffer) void {
        return impl.call(.deinitBuffer, void, .{buffer});
    }

    pub inline fn map(buffer: *Buffer, range: Range) ![]u8 {
        return impl.call(.mapBuffer, Error![]u8, .{ buffer, range });
    }
    pub inline fn unmap(buffer: *Buffer) void {
        impl.call(.unmapBuffer, void, .{buffer});
    }
    pub inline fn getDesc(buffer: *Buffer) BufferDesc {
        return impl.call(.getBufferDesc, BufferDesc, .{buffer});
    }
};

pub const Texture = opaque {
    pub inline fn init(allocator: std.mem.Allocator, desc: TextureDesc) Error!*Texture {
        return impl.call(.initTexture, Error!*Texture, .{ allocator, desc });
    }
    pub inline fn deinit(texture: *Texture) void {
        impl.call(.deinitTexture, void, .{texture});
    }
    pub inline fn getDesc(texture: *Texture) TextureDesc {
        return impl.call(.getTextureDesc, TextureDesc, .{texture});
    }
};

pub const Fence = opaque {
    pub inline fn init(allocator: std.mem.Allocator) Error!*Fence {
        return impl.call(.initFence, Error!*Fence, .{allocator});
    }
    pub inline fn deinit(fence: *Fence) void {
        return impl.call(.deinitFence, void, .{fence});
    }

    /// will block the current thread until the fence is signaled
    pub inline fn wait(fence: *Fence, value: u64) Error!void {
        return impl.call(.waitFenceBlocking, Error!void, .{ fence, value });
    }
};

// obtained by creating a view/sampler
pub const Resource = opaque {
    pub inline fn initTexture(allocator: std.mem.Allocator, desc: TextureResourceDesc) Error!*Resource {
        return impl.call(.initTextureResource, Error!*Resource, .{ allocator, desc });
    }
    pub inline fn initBuffer(allocator: std.mem.Allocator, desc: BufferResourceDesc) Error!*Resource {
        return impl.call(.initBufferResource, Error!*Resource, .{ allocator, desc });
    }
    pub inline fn initSampler(allocator: std.mem.Allocator, desc: SamplerDesc) Error!*Resource {
        return impl.call(.initSampler, Error!*Resource, .{ allocator, desc });
    }

    pub inline fn deinit(resource: *Resource) void {
        impl.call(.deinitResource, void, .{resource});
    }
};

/// stores a set of resource bindings which can be bound and unbound
pub const ResourceSet = opaque {
    pub inline fn init(allocator: std.mem.Allocator, desc: ResourceSetDesc) Error!*ResourceSet {
        return impl.call(.initResourceSet, Error!*ResourceSet, .{ allocator, desc });
    }
    pub inline fn deinit(set: *ResourceSet) void {
        impl.call(.deinitResourceSet, void, .{set});
    }

    pub inline fn setResource(set: *ResourceSet, binding: u32, offset: u32, resource: ?*Resource) Error!void {
        return impl.call(.setResource, Error!void, .{ set, binding, offset, resource });
    }
};

pub const Swapchain = opaque {
    pub inline fn init(allocator: std.mem.Allocator, desc: SwapchainDesc) Error!*Swapchain {
        return impl.call(.initSwapchain, Error!*Swapchain, .{ allocator, desc });
    }
    pub inline fn deinit(swapchain: *Swapchain) void {
        impl.call(.deinitSwapchain, void, .{swapchain});
    }

    pub inline fn resize(swapchain: *Swapchain, size: Vec2u) Error!void {
        return impl.call(.resizeSwapchain, Error!void, .{ swapchain, size });
    }
    pub inline fn acquireNextTexture(swapchain: *Swapchain) !u32 {
        return impl.call(.acquireNextSwapchainTexture, Error!u32, .{swapchain});
    }
    /// NOTE: do not store the result as it will be invalidated after the next resize
    ///
    /// memory is owned by the swapchain
    pub inline fn getTexture(swapchain: *Swapchain, index: usize) Error!?*Texture {
        return impl.call(.getSwapchainTexture, Error!?*Texture, .{ swapchain, index });
    }
    pub inline fn present(swapchain: *Swapchain) Error!void {
        return impl.call(.presentSwapchain, Error!void, .{swapchain});
    }
};

pub const ValidationLevel = enum(u32) {
    none,
    // enabled validation layers on vulkan and the debug layer on d3d12
    normal,
    // uses gpu based validation if available (d3d12)
    full,
};

pub const InitDesc = struct {
    allocator: std.mem.Allocator,
    api: Api = .default,
    limits: ResourceLimits = .{},
    validation: ValidationLevel = switch (builtin.mode) {
        .ReleaseFast => .none,
        else => .full,
    },
};

/// gpu level limits (increase this if need more resources)
pub const ResourceLimits = struct {
    max_buffers: u32 = 4096,
    max_textures: u32 = 4096,
    max_samplers: u32 = 4096,
};

pub const Api = enum(u32) {
    d3d12,
    vulkan,
    metal,

    pub const default = switch (builtin.target.os.tag) {
        .windows => .d3d12,
        .macos => .metal,
        else => .vulkan,
    };
};

pub const Format = enum(u32) {
    unknown,
    R8,
    RG8,
    D32,
    D24S8,
    RGBA8,
    RGBA16,
    RGBA16F,
    RGBA32F,
    BGRA8,
    R16F,
    R16,
    R32F,
    R32UI,
    RG32F,
    SRGB,
    SRGBA,
    BC1,
    BC2,
    BC3,
    BC4,
    BC5,
    R11G11B10F,
    RGB32F,
    RG16,
    RG16F,

    pub fn blockWidth(format: Format) u32 {
        return switch (format) {
            .BC1, .BC2, .BC3, .BC4, .BC5 => 4,
            else => 1,
        };
    }

    pub fn blockHeight(format: Format) u32 {
        return switch (format) {
            .BC1, .BC2, .BC3, .BC4, .BC5 => 4,
            else => 1,
        };
    }

    pub fn isInteger(format: Format) bool {
        return switch (format) {
            .R8, .RG8, .RGBA8, .RGBA16, .R32UI, .BC1, .BC2, .BC3, .BC4, .BC5, .R16, .RG16 => true,
            else => false,
        };
    }

    pub fn stride(format: Format) u32 {
        return switch (format) {
            .unknown => 0,
            .R8 => 1,
            .RG8 => 2,
            .D32, .D24S8 => 4,
            .RGBA8, .BGRA8, .SRGB, .SRGBA => 4,
            .RGBA16 => 8,
            .RGBA16F => 8,
            .RG16F => 4,
            .R16F, .R16 => 2,
            .R32F, .R32UI => 4,
            .RG16 => 4,
            .RG32F => 8,
            .RGB32F => 12,
            .RGBA32F => 16,
            .BC1, .BC2, .BC3, .BC4, .BC5 => 8,
            .R11G11B10F => 4,
        };
    }

    pub fn isDepth(format: Format) bool {
        return switch (format) {
            .D32, .D24S8 => true,
            else => false,
        };
    }

    pub fn isStencil(format: Format) bool {
        return switch (format) {
            .D24S8 => true,
            else => false,
        };
    }
};

pub const PlaneFlags = packed struct(u8) {
    color: bool = true,
    depth: bool = true,
    stencil: bool = true,
    _: u5 = 0,
};

/// used only on vulkan backend to specify the stage of the pipeline
pub const Stages = packed struct(u32) {
    index_input: bool = false,
    vertex_shader: bool = false,
    fragment_shader: bool = false,
    depth_stencil: bool = false,
    color_attachment: bool = false,
    compute_shader: bool = false,
    copy: bool = false,
    clear_storage: bool = false,
    resolve: bool = false,
    indirect: bool = false,
    _: u22 = 0,
};

pub const ShaderStage = enum(u32) {
    vertex,
    fragment,
    compute,

    pub const len = @typeInfo(@This()).@"enum".fields.len;
};

pub const Viewport = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    width: f32 = 0.0,
    height: f32 = 0.0,
    min_depth: f32 = 0.0,
    max_depth: f32 = 0.0,
    origin_bottom_left: bool = false,
};

pub const Rect = struct {
    x: i32 = 0,
    y: i32 = 0,
    width: u32 = 0,
    height: u32 = 0,
};

pub const Vec2 = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
};

pub const Vec2i = struct {
    x: i32 = 0,
    y: i32 = 0,
};

pub const Vec2u = struct {
    x: u32 = 0,
    y: u32 = 0,

    pub fn init(x: u32, y: u32) Vec2u {
        return .{ .x = x, .y = y };
    }
};

pub const Color = [4]f32;
pub const DepthStencil = struct {
    depth: f32 = 1.0,
    stencil: u32 = 0,
};

pub const ClearValue = struct {
    kind: enum(u8) { color, depth_stencil },
    _color: Color = .{ 0.0, 0.0, 0.0, 1.0 },
    _depth_stencil: DepthStencil = .{},

    pub inline fn color(c: Color) ClearValue {
        return .{ .kind = .color, ._color = c };
    }

    pub inline fn depth_stencil(ds: DepthStencil) ClearValue {
        return .{ .kind = .depth_stencil, ._depth_stencil = ds };
    }
};

pub const CommandQueueDesc = struct {
    name: []const u8,
    kind: CommandQueueKind,
};

pub const CommandQueueKind = enum(u32) {
    graphics,
    compute,
    copy,
};

pub const MemoryLocation = enum(u32) {
    /// memory is on the device (gpu)
    device,
    /// memory is visible to both the device and the host (cpu)
    /// and is able to be mapped and unmapped to transfer data
    host_upload,
    /// memory is visible to both the device and the host (cpu)
    /// and is able to be mapped and unmapped to transfer data
    host_readback,
};

pub const TextureDimension = enum(u32) {
    d1,
    d2,
    d3,
};

/// specifies how the view is used
pub const ViewKind = enum(u32) {
    /// shader resource view (read only by shaders)
    ///
    /// used for textures and buffers
    srv,
    /// srv but as an array
    ///
    /// used for textures and buffers
    srv_array,
    /// srv but as a cube
    ///
    /// used for 2d textures
    srv_cube,
    /// srv but as a cube array
    ///
    /// used for 2d textures
    srv_cube_array,
    /// unordered access view (read/write by shaders)
    ///
    /// used for textures and buffers
    uav,
    /// a constant buffer view (read only by shaders)
    ///
    /// used for buffers
    cbv,
    /// render target view
    ///
    /// used for textures
    rtv,
    /// writable depth, writable stencil
    ///
    /// used for textures
    dsv,
    /// read only depth, writable stencil
    ///
    /// used for textures
    d_readonly_sv,
    /// writable depth, read only stencil
    ///
    /// used for textures
    ds_readonly_v,
    /// read only depth, read only stencil
    ///
    /// used for textures
    dsv_readonly,

    pub inline fn textureUsable(kind: ViewKind) bool {
        return switch (kind) {
            .srv,
            .srv_array,
            .srv_cube,
            .srv_cube_array,
            .uav,
            .rtv,
            .dsv,
            .d_readonly_sv,
            .ds_readonly_v,
            .dsv_readonly,
            => true,
            .cbv => false,
        };
    }

    pub inline fn bufferUsable(kind: ViewKind) bool {
        return switch (kind) {
            .srv, .uav, .cbv => true,
            .rtv,
            .dsv,
            .d_readonly_sv,
            .ds_readonly_v,
            .dsv_readonly,
            .srv_array,
            .srv_cube,
            .srv_cube_array,
            => false,
        };
    }
};

/// specifies how a texture is used, what views are able to be created
pub const TextureUsage = packed struct(u32) {
    srv: bool = false,
    uav: bool = false,
    rtv: bool = false,
    dsv: bool = false,
    _: u28 = 0,
};

/// specifies how a buffer is used, what views are able to be created
pub const BufferUsage = packed struct(u32) {
    srv: bool = false,
    uav: bool = false,
    cbv: bool = false,
    index: bool = false,
    vertex: bool = false,
    indirect: bool = false,
    _: u26 = 0,
};

/// describes a texture resource, like what size it has, what usage it has, and
/// what format it has
pub const TextureDesc = struct {
    name: []const u8,

    kind: TextureDimension = TextureDimension.d2,
    usage: TextureUsage,
    location: MemoryLocation,
    format: Format,
    clear_value: ClearValue,
    width: u32,
    height: u32,
    depth: u32,
    mip_num: u32,
    layer_num: u32,
    sample_num: u32,

    pub inline fn fix(desc: TextureDesc) TextureDesc {
        var copy = desc;
        if (copy.height == 0) copy.height = 1;
        if (copy.depth == 0) copy.depth = 1;
        if (copy.mip_num == 0) copy.mip_num = 1;
        if (copy.layer_num == 0) copy.layer_num = 1;
        if (copy.sample_num == 0) copy.sample_num = 1;
        return copy;
    }
};

pub const TextureState = enum(u32) {
    undefined,
    present,
    render_target,
    depth_stencil_write,
    depth_stencil_read,
    shader_resource,
    unordered_access,
    copy_source,
    copy_dest,
};

/// describes a buffer resource, like what size it has, what heap it is on, and
/// structure stride
pub const BufferDesc = struct {
    name: []const u8,
    usage: BufferUsage,
    location: MemoryLocation,
    size: u64,
    /// setting this will result the buffer being a ssbo on vulkan
    structure_stride: u32 = 0,
};

pub const BufferState = enum(u32) {
    undefined,
    copy_dest,
    copy_source,
    vertex,
    index,
    indirect,
    constant,
    shader_resource,
    unordered_access,
};

/// describes how to create a view of a texture
pub const TextureResourceDesc = struct {
    name: []const u8,

    texture: *Texture,
    dimension: TextureDimension,
    kind: ViewKind,
    format: Format,
    mip_start: u32 = 0,
    /// default is the whole texture
    mip_num: u32 = 0,
    layer_start: u32 = 0,
    /// for 3D textures, its the slice num, default is the whole texture
    layer_num: u32 = 0,
};

/// describes how to create a view of a buffer
pub const BufferResourceDesc = struct {
    name: []const u8,

    buffer: *Buffer,
    kind: ViewKind,
    format: Format,
    size: u64 = WHOLE_SIZE,
    offset: u64 = 0,
};

/// the binding model of ila's gpu abstraction is composed of sets with bindings.
/// a shader can have multiple sets, each set can have multiple bindings, and each binding can have multiple resources.
///
/// for example:
/// ```hlsl
/// Texture2D textures[4] : register(t0, space0);
/// RWBuffer<uint> buffers[2] : register(t4, space0);
///
/// SamplerState samplers[2] : register(s0, space1);
/// Buffer<float> constants : register(b2, space1);
/// ```
/// In this case, there are two sets, one with textures and buffers, and another with samplers and constants.
/// The first set has 2 bindings consisting of 4 textures and 2 buffers, and the second set has 2 bindings
/// consisting of 2 samplers and a constant buffer.
///
/// On d3d12: sets are described by the spaces, and bindings are described by the registers ignoring the s t u b prefixes.
/// On vulkan: sets are described by the descriptor sets, and bindings are described by the descriptor bindings.
///
/// describes a single binding
pub const ResourceBinding = struct {
    resource_num: u32,
    kind: Kind,

    /// describes how a binding is to be used
    pub const Kind = enum(u32) {
        sampler,
        constant_buffer,
        srv_texture,
        uav_texture,
        srv_buffer,
        uav_buffer,
        srv_structured_buffer,
        uav_structured_buffer,
    };

    /// just a config value to make decl literal inits more readable
    pub const Writable = enum(u8) {
        /// the resource is writable
        writable,
        /// the resource is read only
        readonly,
    };

    /// a single sampler
    pub inline fn sampler() ResourceBinding {
        return .{
            .resource_num = 1,
            .kind = .sampler,
        };
    }

    /// a range of samplers
    pub inline fn samplerArray(num: u32) ResourceBinding {
        return .{
            .resource_num = num,
            .kind = .sampler,
        };
    }

    /// a single constant buffer
    pub inline fn constantBuffer() ResourceBinding {
        return .{
            .resource_num = 1,
            .kind = .constant_buffer,
        };
    }

    /// a single texture
    pub inline fn texture(writable: Writable) ResourceBinding {
        return .{
            .resource_num = 1,
            .kind = if (writable == .writable) .uav_texture else .srv_texture,
        };
    }

    /// a range of textures
    pub inline fn textureArray(num: u32, writable: Writable) ResourceBinding {
        return .{
            .resource_num = num,
            .kind = if (writable == .writable) .uav_texture else .srv_texture,
        };
    }

    /// a single buffer
    pub inline fn buffer(writable: Writable) ResourceBinding {
        return .{
            .resource_num = 1,
            .kind = if (writable == .writable) .uav_buffer else .srv_buffer,
        };
    }

    /// a range of buffers
    pub inline fn bufferArray(num: u32, writable: Writable) ResourceBinding {
        return .{
            .resource_num = num,
            .kind = if (writable == .writable) .uav_buffer else .srv_buffer,
        };
    }

    /// a single structured buffer
    pub inline fn structuredBuffer(writable: Writable) ResourceBinding {
        return .{
            .resource_num = 1,
            .kind = if (writable == .writable) .uav_structured_buffer else .srv_structured_buffer,
        };
    }

    /// a range of structured buffers
    pub inline fn structuredBufferArray(num: u32, writable: Writable) ResourceBinding {
        return .{
            .resource_num = num,
            .kind = if (writable == .writable) .uav_structured_buffer else .srv_structured_buffer,
        };
    }
};

/// A set of resources that can be bound to a pipeline
pub const ResourceSetDesc = struct {
    bindings: []const ResourceBinding = &.{},

    pub fn init(bindings: []const ResourceBinding) ResourceSetDesc {
        return .{ .bindings = bindings };
    }
};

/// specifies an in pipeline constant (root constants on d3d12 and push constants on vulkan)
pub const Constant = struct {
    /// size in bytes, must be a multiple of 4, max size is 128 bytes for all constants
    size: u32,

    pub fn sized(comptime T: type) Constant {
        return .{ .size = @sizeOf(T) };
    }
};

// Input Layout

pub const VertexStreamStepRate = enum(u32) {
    vertex,
    instance,
};

pub const IndexKind = enum(u32) {
    u16,
    u32,
};

pub const Topology = enum(u32) {
    point_list,
    line_list,
    line_strip,
    triangle_list,
    triangle_strip,
};

/// describes what primitive will be drawn
pub const InputAssembly = struct {
    topology: Topology = .triangle_list,
};

/// a single vertex attribute, describes how to read a vertex buffer
pub const VertexAttribute = struct {
    /// the location of the attribute in the vertex shader
    location: u32,
    /// offset in bytes from the start of the vertex at the stream
    offset: u32,
    /// the kind of the attribute, specifies the size
    kind: Kind,
    /// which stream the attribute is in
    stream: u32 = 0,

    pub fn attr(location: u32, offset: u32, kind: Kind, stream: u32) VertexAttribute {
        return .{
            .location = location,
            .offset = offset,
            .kind = kind,
            .stream = stream,
        };
    }

    pub const Kind = enum(u32) {
        u8,
        u8_normalized,
        i8,
        i8_normalized,
        u16,
        u16_normalized,
        i16,
        i16_normalized,
        u32,
        i32,
        f32,

        // all are float types
        vec2,
        vec3,
        vec4,
    };
};

/// a vertex stream; contiguous memory that contains vertex data that attributes can point to to read
///
/// will be bound depending on the index in the array of vertex streams
pub const VertexStream = struct {
    /// the stride of the stream in bytes
    stride: u32,
    /// the rate at which the stream advances
    step_rate: VertexStreamStepRate,

    pub fn stream(stride: u32, step_rate: VertexStreamStepRate) VertexStream {
        return .{
            .stride = stride,
            .step_rate = step_rate,
        };
    }
};

/// describes how vertices are read from vertex buffers
pub const VertexInput = struct {
    attributes: []const VertexAttribute = &.{},
    streams: []const VertexStream = &.{},
};

// Pipelines

/// describes how to create a pipeline layout
///
/// on d3d12, it will place 8 bytes of constants at set 999, binding 0 for
/// indirect args
///
/// the constants will be placed in space MAX_RESOURCE_SETS
pub const PipelineLayoutDesc = struct {
    name: []const u8 = &.{},
    constant: ?Constant = null,
    sets: []const ResourceSetDesc = &.{},
};

/// describes how pixels are filled in primitives
pub const FillMode = enum(u32) {
    wireframe,
    solid,
};

/// describes how to cull faces before they reach the rasterizer
pub const CullMode = enum(u32) {
    none,
    front,
    back,
};

/// describes how to compare depth values
pub const DepthBias = struct {
    constant: f32 = 0.0,
    slope: f32 = 0.0,
    clamp: f32 = 0.0,
};

/// describes how to rasterize primitives
pub const Rasterization = struct {
    depth_bias: DepthBias = .{},
    fill_mode: FillMode = .solid,
    cull_mode: CullMode = .none,
    front_counter_clockwise: bool = false,
    depth_clamp: bool = false,
    line_smoothing: bool = false,
    conservative: bool = false,
};

/// describes how to sample (msaa)
pub const Multisample = struct {
    enabled: bool = false,
    sample_mask: u32 = 0,
    sample_num: u32 = 0,
    alpha_to_coverage: bool = false,
};

/// S - source color 0
///
/// D - destination color
pub const LogicOp = enum(u32) {
    none,
    /// 0
    clear,
    /// S & D
    @"and",
    /// S & ~D
    and_reverse,
    /// S
    copy,
    /// ~S & D
    and_inverted,
    /// S ^ D
    xor,
    /// S | D
    @"or",
    /// ~(S | D)
    nor,
    /// ~(S ^ D)
    equivalent,
    /// ~D
    invert,
    /// S | ~D
    or_reverse,
    /// ~S
    copy_inverted,
    /// ~S | D
    or_inverted,
    /// ~(S & D)
    nand,
    /// 1
    set,
};

/// R - reference, set by "CmdSetStencilReference"
///
/// D - stencil buffer
pub const CompareOp = enum(u32) {
    /// test is disabled
    none,
    /// true
    always,
    /// false
    never,
    /// R == D
    equal,
    /// R != D
    not_equal,
    /// R < D
    less,
    /// R <= D
    less_equal,
    /// R > D
    greater,
    /// R >= D
    greater_equal,
};

/// R - reference, set by "CmdSetStencilReference"
///
/// D - stencil buffer
pub const StencilOp = enum(u32) {
    /// D = D
    keep,
    /// D = 0
    zero,
    /// D = R
    replace,
    /// D = min(D++, 255)
    increment_clamp,
    /// D = max(D--, 0)
    decrement_clamp,
    /// D = ~D
    invert,
    /// D++
    increment_wrap,
    /// D--
    decrement_wrap,
};

/// S0 - source color 0
/// S1 - source color 1
/// D - destination color
/// C - blend constants, set by "CmdSetBlendConstants"
pub const BlendFactor = enum(u32) {
    /// 0
    zero,
    /// 1
    one,
    /// S0.r, S0.g, S0.b
    src_color,
    /// 1 - S0.r, 1 - S0.g, 1 - S0.b
    one_minus_src_color,
    /// D.r, D.g, D.b
    dst_color,
    /// 1 - D.r, 1 - D.g, 1 - D.b
    one_minus_dst_color,
    /// S0.a
    src_alpha,
    /// 1 - S0.a
    one_minus_src_alpha,
    /// D.a
    dst_alpha,
    /// 1 - D.a
    one_minus_dst_alpha,
    /// C.r, C.g, C.b
    constant_color,
    /// 1 - C.r, 1 - C.g, 1 - C.b
    one_minus_constant_color,
    /// C.a
    constant_alpha,
    /// 1 - C.a
    one_minus_constant_alpha,
    /// min(S0.a, 1 - D.a)
    src_alpha_saturate,
    /// S1.r, S1.g, S1.b
    src1_color,
    /// 1 - S1.r, 1 - S1.g, 1 - S1.b
    one_minus_src1_color,
    /// S1.a
    src1_alpha,
    /// 1 - S1.a
    one_minus_src1_alpha,
};

/// S - source color
/// D - destination color
/// Sf - source factor, produced by "BlendFactor"
/// Df - destination factor, produced by "BlendFactor"
pub const BlendOp = enum(u32) {
    /// S * Sf + D * Df
    add,
    /// S * Sf - D * Df
    subtract,
    /// D * Df - S * Sf
    reverse_subtract,
    /// min(S, D)
    min,
    /// max(S, D)
    max,
};

pub const ColorWrite = packed struct(u8) {
    red: bool = true,
    green: bool = true,
    blue: bool = true,
    alpha: bool = true,
    _: u4 = 0,

    pub const rgba = .{};
    pub const rgb = .{ .red = true, .green = true, .blue = true, .alpha = false };
};

/// describes how to clear a render target or depth stencil
pub const Clear = union(enum) {
    _color: struct {
        /// the value to clear the render target to
        value: Color = .{ 0.0, 0.0, 0.0, 1.0 },
        /// the index of the attachment to clear
        attachment_index: u32 = 0,
    },
    _depth: f32,
    _stencil: u32,

    pub fn color(value: Color, attachment: u32) Clear {
        return .{ ._color = .{
            .value = value,
            .attachment_index = attachment,
        } };
    }

    pub fn depth(value: f32) Clear {
        return .{ ._depth = value };
    }

    pub fn stencil(value: u32) Clear {
        return .{ ._stencil = value };
    }
};

/// describes how to create write to a stencil
pub const Stencil = struct {
    compare_op: CompareOp = .none,
    fail_op: StencilOp = .keep,
    depth_fail_op: StencilOp = .keep,
    pass_op: StencilOp = .keep,
    write_mask: u8 = 0,
    compare_mask: u8 = 0,

    pub const enabled_default: Stencil = .{
        .compare_op = .always,
        .fail_op = .keep,
        .depth_fail_op = .keep,
        .pass_op = .keep,
        .write_mask = 0xFF,
        .compare_mask = 0xFF,
    };
};

/// describes how to blend colors when in the output merger
pub const Blending = struct {
    src: BlendFactor = .one,
    dst: BlendFactor = .zero,
    op: BlendOp = .add,
};

/// describes a color attachment
pub const ColorAttachment = struct {
    format: Format = .unknown,
    color_blend: Blending = .{},
    alpha_blend: Blending = .{},
    write_mask: ColorWrite = .{},
    blend_enabled: bool = true,

    pub fn colorAttachment(
        format: Format,
        color_blend: Blending,
        alpha_blend: Blending,
        write_mask: ColorWrite,
    ) ColorAttachment {
        return .{
            .format = format,
            .color_blend = color_blend,
            .alpha_blend = alpha_blend,
            .write_mask = write_mask,
            .blend_enabled = true,
        };
    }
};

/// describes a depth attachment
pub const DepthAttachment = struct {
    compare_op: CompareOp = .none,
    write: bool = false,
    bounds_test: bool = false,
};

/// describes a stencil attachment
pub const StencilAttachment = struct {
    front: Stencil = .{},
    back: Stencil = .{},
};

/// describes how to merge to create the final pixel color
pub const OutputMerger = struct {
    attachments: []const ColorAttachment = &.{},
    depth: DepthAttachment = .{},
    stencil: StencilAttachment = .{},
    depth_stencil_format: Format = .unknown,
    logic_op: LogicOp = .none,
};

pub const Attachments = struct {
    depth_stencil: ?*Resource = null,
    attachments: []const *Resource = &.{},
};

pub const Filter = enum(u32) {
    nearest,
    linear,
};

pub const FilterExt = enum(u32) {
    none,
    min,
    max,
};

pub const AddressMode = enum(u32) {
    repeat,
    mirror,
    clamp,
    border,
    mirror_once,
};

pub const AddressModes = struct {
    u: AddressMode = .repeat,
    v: AddressMode = .repeat,
    w: AddressMode = .repeat,
};

pub const Filters = struct {
    min: Filter = .nearest,
    mag: Filter = .nearest,
    mip: Filter = .nearest,
    ext: FilterExt = .none,
};

pub const SamplerDesc = struct {
    filters: Filters = .{},
    anisotropy: u32 = 1,
    mip_bias: f32 = 0.0,
    mip_min: f32 = 0.0,
    mip_max: f32 = 0.0,
    address_modes: AddressModes = .{},
    compare_op: CompareOp = .none,
    border_color: Color = @splat(0.0),
    is_int: bool = false,
};

pub const ShaderTarget = enum(u32) {
    dxil,
    spirv,
    metal,

    pub const len = @typeInfo(@This()).@"enum".fields.len;
};

pub const ShaderDesc = struct {
    enabled: bool = false,
    stage: ShaderStage = .vertex,
    target: ShaderTarget = .dxil,
    bytecode: []const u8 = &.{},

    pub fn vertex(target: ShaderTarget, bytecode: []const u8) ShaderDesc {
        return .{
            .enabled = true,
            .stage = .vertex,
            .target = target,
            .bytecode = bytecode,
        };
    }

    pub fn fragment(target: ShaderTarget, bytecode: []const u8) ShaderDesc {
        return .{
            .enabled = true,
            .stage = .fragment,
            .target = target,
            .bytecode = bytecode,
        };
    }

    pub fn compute(target: ShaderTarget, bytecode: []const u8) ShaderDesc {
        return .{
            .enabled = true,
            .stage = .compute,
            .target = target,
            .bytecode = bytecode,
        };
    }
};

pub const ShaderContainer = struct {
    count: u32 = 0,
    shaders: [ShaderStage.len * ShaderTarget.len]ShaderDesc = undefined,

    pub const Iterator = struct {
        index: u32 = 0,
        container: *const ShaderContainer,

        pub const Filter = struct {
            stage: ?ShaderStage = null,
            target: ?ShaderTarget = null,
        };

        pub fn next(self: *Iterator, filter: @This().Filter) ?ShaderDesc {
            while (self.index < self.container.count) {
                const shader = self.container.shaders[self.index];
                self.index += 1;

                if (filter.stage) |stage| if (shader.stage != stage) continue;
                if (filter.target) |target| if (shader.target != target) continue;

                return shader;
            }
            return null;
        }
    };

    pub fn iterator(self: *const ShaderContainer) Iterator {
        return .{ .container = self };
    }

    pub fn add(self: *ShaderContainer, shader: ShaderDesc) void {
        self.shaders[self.count] = shader;
        self.count += 1;
    }
};

pub const GraphicsPipelineDesc = struct {
    layout: *PipelineLayout,
    vertex_input: VertexInput = .{},
    input_assembly: InputAssembly = .{},
    rasterization: Rasterization = .{},
    multisample: Multisample = .{},
    output_merger: OutputMerger = .{},
    // allow multiple shaders to be added
    shaders: ShaderContainer = .{},

    pub fn init(layout: *PipelineLayout) GraphicsPipelineDesc {
        return .{ .layout = layout };
    }

    // vertex input
    pub fn vertexAttributes(self: *GraphicsPipelineDesc, attributes: []const VertexAttribute) void {
        self.vertex_input.attributes = attributes;
    }
    pub fn vertexStreams(self: *GraphicsPipelineDesc, streams: []const VertexStream) void {
        self.vertex_input.streams = streams;
    }

    // input assembly
    pub fn inputTopology(self: *GraphicsPipelineDesc, topology: Topology) void {
        self.input_assembly.topology = topology;
    }

    pub fn depthBias(self: *GraphicsPipelineDesc, bias: DepthBias) void {
        self.rasterization.depth_bias = bias;
    }
    pub fn fillMode(self: *GraphicsPipelineDesc, mode: FillMode) void {
        self.rasterization.fill_mode = mode;
    }
    pub fn cullMode(self: *GraphicsPipelineDesc, mode: CullMode) void {
        self.rasterization.cull_mode = mode;
    }
    pub fn frontCCW(self: *GraphicsPipelineDesc, ccw: bool) void {
        self.rasterization.front_counter_clockwise = ccw;
    }
    pub fn depthClamp(self: *GraphicsPipelineDesc, clamp: bool) void {
        self.rasterization.depth_clamp = clamp;
    }
    pub fn lineSmoothing(self: *GraphicsPipelineDesc, smoothing: bool) void {
        self.rasterization.line_smoothing = smoothing;
    }
    pub fn conservativeRasterization(self: *GraphicsPipelineDesc, conservative: bool) void {
        self.rasterization.conservative = conservative;
    }

    // multisample
    /// only usable when rendering to a texture
    /// and not a swapchain
    pub fn multiSampleMask(self: *GraphicsPipelineDesc, mask: u32) void {
        self.multisample.enabled = true;
        self.multisample.sample_mask = mask;
    }
    /// only usable when rendering to a texture
    /// and not a swapchain
    pub fn multiSampleNum(self: *GraphicsPipelineDesc, num: u32) void {
        self.multisample.enabled = true;
        self.multisample.sample_num = num;
    }
    /// only usable when rendering to a texture
    /// and not a swapchain
    pub fn multiSampleAlphaToCoverage(self: *GraphicsPipelineDesc, alpha: bool) void {
        self.multisample.enabled = true;
        self.multisample.alpha_to_coverage = alpha;
    }

    // output merger
    pub fn colorAttachments(
        self: *GraphicsPipelineDesc,
        attachments: []const ColorAttachment,
    ) void {
        self.output_merger.attachments = attachments;
    }
    pub fn depthAttachment(self: *GraphicsPipelineDesc, attachment: DepthAttachment) void {
        self.output_merger.depth = attachment;
    }
    pub fn stencilAttachment(self: *GraphicsPipelineDesc, attachment: StencilAttachment) void {
        self.output_merger.stencil = attachment;
    }
    pub fn depthStencilFormat(self: *GraphicsPipelineDesc, format: Format) void {
        self.output_merger.depth_stencil_format = format;
    }
    pub fn outputMergeOp(self: *GraphicsPipelineDesc, op: LogicOp) void {
        self.output_merger.logic_op = op;
    }

    pub fn addShader(self: *GraphicsPipelineDesc, shader: ShaderDesc) void {
        self.shaders.add(shader);
    }
};

pub const ComputePipelineDesc = struct {
    layout: *PipelineLayout,
    shaders: ShaderContainer = .{},

    pub fn init(layout: *PipelineLayout) ComputePipelineDesc {
        return .{ .layout = layout };
    }

    pub fn addShader(self: *ComputePipelineDesc, sh: ShaderDesc) void {
        self.shaders.add(sh);
    }
};

pub const TextureRegion = struct {
    x: u32 = 0,
    y: u32 = 0,
    z: u32 = 0,
    width: u32 = WHOLE_SIZE_U32,
    height: u32 = WHOLE_SIZE_U32,
    depth: u32 = WHOLE_SIZE_U32,
    mip: u32 = 0,
    layer: u32 = 0,
};

/// extents of a texture
pub const TextureDataLayout = struct {
    offset: u64,
    row_pitch: u32,
    slice_pitch: u32,
};

pub const ClearBufferDesc = struct {
    buffer: *Resource,
    value: u32 = 0,
    set_index: u32,
    binding_index: u32,
    resource_index: u32 = 0,
};

pub const ClearTextureDesc = struct {
    texture: *Resource,
    value: ClearValue,
    set_index: u32,
    binding_index: u32,
    resource_index: u32 = 0,
};

pub const Draw = struct {
    vertex_num: u32 = 0,
    instance_num: u32 = 1,
    first_vertex: u32 = 0,
    first_instance: u32 = 0,
};

pub const DrawIndexed = struct {
    index_num: u32 = 0,
    instance_num: u32 = 1,
    first_index: u32 = 0,
    vertex_offset: i32 = 0,
    first_instance: u32 = 0,
};

pub const DrawIndirect = struct {
    buffer: *Buffer,
    offset: u64,
    count: u32,
    stride: u32,
    count_buffer: ?*Buffer = null,
    count_offset: u64 = 0,
};

pub const Dispatch = struct {
    x: u32,
    y: u32,
    z: u32,
};

pub const DispatchIndirect = struct {
    buffer: *Buffer,
    offset: u64,
};

pub const DrawEmulated = struct {
    base_vertex: u32,
    base_instance: u32,
    inner: Draw,
};

pub const DrawIndexedEmulated = struct {
    base_vertex: u32,
    base_instance: u32,
    inner: DrawIndexed,
};

pub const Vendor = enum(u32) {
    unknown,
    nvidia,
    amd,
    intel,

    pub inline fn fromId(id: u32) Vendor {
        return switch (id) {
            0x10DE => .nvidia,
            0x1002 => .amd,
            0x8086 => .intel,
            else => .unknown,
        };
    }
};

pub const AdapterDesc = struct {
    name: [256:0]u8,
    luid: u64,
    video_memory: u64,
    system_memory: u64,
    device_id: u32,
    vendor: Vendor,
};

pub const SwapchainDesc = struct {
    name: []const u8 = &.{},

    window: ila.Window,
    queue: *CommandQueue,
    size: Vec2u,
    texture_num: u32 = 2,
    format: Format,
    immediate: bool = false,
};

pub fn getDimensionMipAdjusted(
    desc: TextureDesc,
    dimension_index: u8,
    mip: u32,
) u32 {
    var dimension: u32 = 0;
    switch (dimension_index) {
        0 => dimension = desc.width,
        1 => dimension = desc.height,
        2 => dimension = desc.depth,
        else => unreachable,
    }

    dimension = @max(1, dimension >> @as(u5, @intCast(mip)));

    if (dimension_index < 2) {
        const block_width = Format.blockWidth(desc.format);
        dimension = std.mem.alignForward(u32, dimension, block_width);
    }

    return dimension;
}

comptime {
    std.testing.refAllDeclsRecursive(@This());
}

const std = @import("std");
const builtin = @import("builtin");

pub const config = @import("config");

const ila = @import("root.zig");
