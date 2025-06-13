const max_cbv_srv_uav_staging = 32 * 1024;
const max_sampler_staging = 2048; // 2k - 1
const max_render_targets = 256;
const max_depth_stencils = 256;

const D3D12Backend = @This();
var s_instance: ?D3D12Backend = null;

fn getInstance() !*D3D12Backend {
    return &(s_instance orelse return error.NotInitialized);
}

allocator: std.mem.Allocator,
desc: gpu.InitDesc,

factory: *dxgi.IFactory5,

adapter: *dxgi.IAdapter1 = undefined,
adapter_desc: gpu.AdapterDesc = undefined,

device: *d3d12.IDevice5 = undefined,
staging_heaps: [@typeInfo(d3d12.DESCRIPTOR_HEAP_TYPE).@"enum".fields.len]D3DDescriptorHeap = undefined,

// only CBV_SRV_UAV and RTV heaps are used
gpu_heaps: [2]D3DDescriptorHeap = undefined,

mem_allocator: *d3d12ma.Allocator = undefined,

primary_queue: *gpu.CommandQueue = undefined,

pub fn init(desc: gpu.InitDesc) gpu.Error!void {
    if (s_instance) |_| {
        return error.AlreadyInitialized;
    }

    if (desc.validation != .none) {
        var debug_controller: ?*d3d12d.IDebug = null;
        const hr = d3d12.GetDebugInterface(&d3d12d.IID_IDebug, @ptrCast(&debug_controller));
        if (hr != windows.S_OK) {
            log.warn("Failed to enable D3D12 API validation: {x}", .{hr});
        } else {
            defer _ = debug_controller.?.Release();
            debug_controller.?.EnableDebugLayer();

            var debug_controller1: ?*d3d12d.IDebug1 = null;
            const hr1 = debug_controller.?.QueryInterface(
                &d3d12d.IID_IDebug1,
                @ptrCast(&debug_controller1),
            );
            if (hr1 != windows.S_OK) {
                log.warn("Failed to enable D3D12 API validation1: {x}", .{hr1});
            } else {
                defer _ = debug_controller1.?.Release();
                if (desc.validation == .full)
                    debug_controller1.?.SetEnableGPUBasedValidation(windows.TRUE);
            }
        }

        // var dred_controller: ?*d3d12.Iremov = null;
        // const hr2 = c.D3D12GetDebugInterface(&c.IID_d3d12.IDeviceRemovedExtendedDataSettings1, @ptrCast(&dred_controller));
        // if (hr2 != c.S_OK) {
        //     log.warn("Failed to enable D3D12 DRED: {x}", .{hr2});
        // } else {
        //     defer _ = dred_controller.?.lpVtbl.*.Release.?(dred_controller);
        //     dred_controller.?.lpVtbl.*.SetAutoBreadcrumbsEnablement.?(dred_controller, c.TRUE);
        //     dred_controller.?.lpVtbl.*.SetPageFaultEnablement.?(dred_controller, c.TRUE);
        //     dred_controller.?.lpVtbl.*.SetWatsonDumpEnablement.?(dred_controller, c.TRUE);
        // }
    }

    var factory: ?*dxgi.IFactory5 = null;
    const hr = dxgi.CreateDXGIFactory2(
        if (desc.validation != .none) dxgi.CREATE_FACTORY_DEBUG else 0,
        &dxgi.IID_IFactory5,
        @ptrCast(&factory),
    );
    if (hr != windows.S_OK) {
        return error.D3D12InternalError;
    }

    s_instance = .{
        .allocator = desc.allocator,
        .desc = desc,
        .factory = factory.?,
    };

    const instance = try getInstance();
    const limits = instance.desc.limits;

    const hr_enumadapters = instance.factory.EnumAdapters1(0, @ptrCast(&instance.adapter));
    if (hr_enumadapters != windows.S_OK) {
        return error.D3D12InternalError;
    }

    var adapter_desc: dxgi.ADAPTER_DESC = undefined;
    _ = instance.adapter.GetDesc(&adapter_desc);

    var buf: [512]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);

    const name = std.unicode.utf16LeToUtf8Alloc(fba.allocator(), adapter_desc.Description[0..]) catch
        return error.OutOfMemory;
    @memcpy(instance.adapter_desc.name[0..name.len], name);
    instance.adapter_desc.luid = @bitCast(adapter_desc.AdapterLuid);
    instance.adapter_desc.video_memory = adapter_desc.DedicatedVideoMemory;
    instance.adapter_desc.system_memory = adapter_desc.DedicatedSystemMemory;
    instance.adapter_desc.device_id = adapter_desc.DeviceId;
    instance.adapter_desc.vendor = .fromId(adapter_desc.VendorId);

    const hr_createdevice = d3d12.CreateDevice(
        @ptrCast(instance.adapter),
        .@"11_1",
        &d3d12.IID_IDevice5,
        @ptrCast(&instance.device),
    );
    if (hr_createdevice != windows.S_OK) {
        return error.D3D12InternalError;
    }

    if (instance.desc.validation != .none) {
        var info_queue: ?*d3d12d.IInfoQueue = null;
        const hr_infopqueue = instance.device.QueryInterface(&d3d12d.IID_IInfoQueue, @ptrCast(&info_queue));
        if (hr_infopqueue == windows.S_OK) {
            defer _ = info_queue.?.Release();
            var disable_ids = [_]d3d12d.MESSAGE_ID{
                .CLEARRENDERTARGETVIEW_MISMATCHINGCLEARVALUE,
            };
            var filter = std.mem.zeroInit(d3d12d.INFO_QUEUE_FILTER, .{ .DenyList = .{
                .NumIDs = disable_ids.len,
                .pIDList = @as([*]d3d12d.MESSAGE_ID, @ptrCast(&disable_ids)),
            } });
            _ = info_queue.?.AddStorageFilterEntries(&filter);
        } else {
            log.warn("Failed to enable D3D12 API validation: {x}", .{hr});
        }
    }

    var staging_heap_nums: [@typeInfo(d3d12.DESCRIPTOR_HEAP_TYPE).@"enum".fields.len]u32 = undefined;
    staging_heap_nums[@intFromEnum(d3d12.DESCRIPTOR_HEAP_TYPE.SAMPLER)] = max_sampler_staging;
    staging_heap_nums[@intFromEnum(d3d12.DESCRIPTOR_HEAP_TYPE.CBV_SRV_UAV)] = max_cbv_srv_uav_staging;
    staging_heap_nums[@intFromEnum(d3d12.DESCRIPTOR_HEAP_TYPE.RTV)] = max_render_targets;
    staging_heap_nums[@intFromEnum(d3d12.DESCRIPTOR_HEAP_TYPE.DSV)] = max_depth_stencils;

    for (staging_heap_nums, 0..) |count, heap_type_int| {
        const heap_type: d3d12.DESCRIPTOR_HEAP_TYPE = @enumFromInt(heap_type_int);
        const heap = &instance.staging_heaps[heap_type_int];
        heap.heap_type = heap_type;
        heap.shader_visible = false;
        try heap.init(count, instance.device, instance.allocator);
    }

    var gpu_heap_nums: [2]u32 = undefined;
    gpu_heap_nums[0] = limits.max_textures + limits.max_buffers;
    gpu_heap_nums[1] = limits.max_samplers;
    for (gpu_heap_nums, 0..) |count, heap_type_int| {
        const heap_type: d3d12.DESCRIPTOR_HEAP_TYPE = @enumFromInt(heap_type_int);
        const heap = &instance.gpu_heaps[heap_type_int];
        heap.heap_type = heap_type;
        heap.shader_visible = true;
        try heap.init(count, instance.device, instance.allocator);
    }

    const allocator_desc: d3d12ma.ALLOCATOR_DESC = .{
        .pDevice = @ptrCast(instance.device),
        .pAdapter = @ptrCast(instance.adapter),
        .pAllocationCallbacks = null,
        .Flags = d3d12ma._ALLOCATOR_FLAG_DEFAULT_POOLS_NOT_ZEROED |
            d3d12ma._ALLOCATOR_FLAG_DONT_PREFER_SMALL_BUFFERS_COMMITTED,
    };
    const hr_createallocator = d3d12ma.Allocator.Create(&allocator_desc, @ptrCast(&instance.mem_allocator));
    if (hr_createallocator != windows.S_OK) {
        return error.D3D12InternalError;
    }

    // command queue (will be primary)
    instance.primary_queue = try initCommandQueue(instance.allocator, .{
        .name = "Primary Queue",
        .kind = .graphics,
    });

    return;
}

pub fn deinit() void {
    if (s_instance) |*i| {
        defer s_instance = null;
        defer log.info("D3D12 backend deinitialized", .{});

        deinitCommandQueue(i.primary_queue);

        i.mem_allocator.Release();

        for (i.staging_heaps[0..]) |*heap| {
            heap.deinit(i.allocator);
        }

        for (i.gpu_heaps[0..]) |*heap| {
            heap.deinit(i.allocator);
        }

        _ = i.device.Release();
        _ = i.adapter.Release();

        _ = i.factory.Release();
    }
}

pub fn getLimits() gpu.Limits {
    return .{
        // D3D12_TEXTURE_DATA_PITCH_ALIGNMENT
        .upload_buffer_texture_row_alignment = 256,
        // D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT
        .upload_buffer_texture_slice_alignment = 512,
    };
}

const D3DDescriptor = struct {
    heap_type: d3d12.DESCRIPTOR_HEAP_TYPE,
    range_type: d3d12.DESCRIPTOR_RANGE_TYPE,
    allocation: Allocation,
};

// need to set heap_type and shader_visible before init
const D3DDescriptorHeap = struct {
    d3d_heap: *d3d12.IDescriptorHeap,
    heap_type: d3d12.DESCRIPTOR_HEAP_TYPE,
    offset_allocator: OffsetAllocator,
    base_cpu: d3d12.CPU_DESCRIPTOR_HANDLE,
    base_gpu: ?d3d12.GPU_DESCRIPTOR_HANDLE,
    descriptor_size: u32,
    shader_visible: bool,

    pub fn init(
        self: *D3DDescriptorHeap,
        count: u32,
        device: *d3d12.IDevice5,
        allocator: std.mem.Allocator,
    ) !void {
        const desc: d3d12.DESCRIPTOR_HEAP_DESC = .{
            .Type = self.heap_type,
            .NumDescriptors = count,
            .Flags = .{
                .SHADER_VISIBLE = self.shader_visible,
            },
            .NodeMask = 0,
        };
        const hr_createheap = device.CreateDescriptorHeap(&desc, &d3d12.IID_IDescriptorHeap, @ptrCast(&self.d3d_heap));
        if (hr_createheap != windows.S_OK) {
            return error.D3D12InternalError;
        }

        self.base_cpu = self.d3d_heap.GetCPUDescriptorHandleForHeapStart();
        if (self.shader_visible) {
            self.base_gpu = self.d3d_heap.GetGPUDescriptorHandleForHeapStart();
        }
        self.descriptor_size = device.GetDescriptorHandleIncrementSize(self.heap_type);

        self.offset_allocator = try .init(allocator, count, count);
    }

    pub fn deinit(self: *D3DDescriptorHeap, _: std.mem.Allocator) void {
        self.offset_allocator.deinit();
        fullyRelease(self.d3d_heap);
    }

    pub fn alloc(self: *D3DDescriptorHeap, tag_range_type: d3d12.DESCRIPTOR_RANGE_TYPE, count: u32) !D3DDescriptor {
        const allocation = try self.offset_allocator.allocate(count);
        return .{
            .heap_type = self.heap_type,
            .range_type = tag_range_type,
            .allocation = allocation,
        };
    }

    pub fn free(self: *D3DDescriptorHeap, desc: D3DDescriptor) void {
        // TODO: handle this
        self.offset_allocator.free(desc.allocation) catch @panic("Failed to free descriptor allocation");
    }
};

fn allocateStagingHeapDescriptor(ty: d3d12.DESCRIPTOR_HEAP_TYPE, range_type: d3d12.DESCRIPTOR_RANGE_TYPE) !D3DDescriptor {
    const instance = try getInstance();
    const heap = &instance.staging_heaps[@intFromEnum(ty)];
    return try heap.alloc(range_type, 1);
}

fn freeStagingHeapDescriptor(desc: D3DDescriptor) void {
    const instance = getInstance() catch return;
    const heap = &instance.staging_heaps[@intFromEnum(desc.heap_type)];
    heap.free(desc);
}

fn getStagingHeapCpuPointer(handle: D3DDescriptor) d3d12.CPU_DESCRIPTOR_HANDLE {
    const instance = getInstance() catch return .{ .ptr = 0 };
    const heap = &instance.staging_heaps[@intFromEnum(handle.heap_type)];
    return .{
        .ptr = heap.base_cpu.ptr + @as(usize, handle.allocation.offset) * @as(usize, heap.descriptor_size),
    };
}

fn allocateGpuHeapDescriptor(ty: d3d12.DESCRIPTOR_HEAP_TYPE, range_type: d3d12.DESCRIPTOR_RANGE_TYPE, count: u32) !D3DDescriptor {
    const instance = try getInstance();
    const heap = &instance.gpu_heaps[@intFromEnum(ty)];
    return try heap.alloc(range_type, count);
}

fn freeGpuHeapDescriptor(desc: D3DDescriptor) void {
    const instance = getInstance() catch return;
    const heap = &instance.gpu_heaps[@intFromEnum(desc.heap_type)];
    heap.free(desc);
}

fn getGpuHeapGpuPointer(handle: D3DDescriptor, offset: usize) d3d12.GPU_DESCRIPTOR_HANDLE {
    const instance = getInstance() catch return .{ .ptr = 0 };
    const heap = &instance.gpu_heaps[@intFromEnum(handle.heap_type)];
    return .{
        .ptr = heap.base_gpu.?.ptr + (@as(usize, handle.allocation.offset) + offset) *
            @as(usize, heap.descriptor_size),
    };
}

fn getGpuHeapCpuPointer(handle: D3DDescriptor, offset: usize) d3d12.CPU_DESCRIPTOR_HANDLE {
    const instance = getInstance() catch return .{ .ptr = 0 };
    const heap = &instance.gpu_heaps[@intFromEnum(handle.heap_type)];
    return .{
        .ptr = heap.base_cpu.ptr +
            (@as(usize, handle.allocation.offset) + offset) * @as(usize, heap.descriptor_size),
    };
}

const D3DResource = struct {
    allocator: std.mem.Allocator,

    resource: *d3d12.IResource,
    buffer_gpu_location: d3d12.GPU_VIRTUAL_ADDRESS,
    cpu_descriptor: d3d12.CPU_DESCRIPTOR_HANDLE,
    cpu_handle: D3DDescriptor,
    heap_type: d3d12.DESCRIPTOR_HEAP_TYPE,
    binding_type: Binding,
    /// used only for buffers
    view_kind: gpu.ViewKind,
    integer_format: bool,

    pub const Binding = enum {
        cbv,
        srv,
        uav,
        rtv,
        dsv,
    };

    fn createSrv(
        resource: *D3DResource,
        desc: d3d12.SHADER_RESOURCE_VIEW_DESC,
    ) gpu.Error!void {
        resource.cpu_handle = try allocateStagingHeapDescriptor(.CBV_SRV_UAV, .SRV);
        resource.cpu_descriptor = getStagingHeapCpuPointer(resource.cpu_handle);
        resource.binding_type = .srv;
        const instance = try getInstance();
        instance.device.CreateShaderResourceView(resource.resource, &desc, resource.cpu_descriptor);
    }

    fn createUav(
        resource: *D3DResource,
        is_integer: bool,
        desc: d3d12.UNORDERED_ACCESS_VIEW_DESC,
    ) gpu.Error!void {
        resource.cpu_handle = try allocateStagingHeapDescriptor(.CBV_SRV_UAV, .UAV);
        resource.cpu_descriptor = getStagingHeapCpuPointer(resource.cpu_handle);
        resource.integer_format = is_integer;
        resource.binding_type = .uav;
        const instance = try getInstance();
        instance.device.CreateUnorderedAccessView(resource.resource, null, &desc, resource.cpu_descriptor);
    }

    fn createRtv(
        resource: *D3DResource,
        desc: d3d12.RENDER_TARGET_VIEW_DESC,
    ) gpu.Error!void {
        // 2nd param wont be used for staging so put something random
        resource.cpu_handle = try allocateStagingHeapDescriptor(.RTV, .SRV);
        resource.cpu_descriptor = getStagingHeapCpuPointer(resource.cpu_handle);
        resource.binding_type = .rtv;
        const instance = try getInstance();
        instance.device.CreateRenderTargetView(resource.resource, &desc, resource.cpu_descriptor);
    }

    fn createDsv(
        resource: *D3DResource,
        desc: d3d12.DEPTH_STENCIL_VIEW_DESC,
    ) gpu.Error!void {
        // 2nd param wont be used for staging so put something random
        resource.cpu_handle = try allocateStagingHeapDescriptor(.DSV, .SRV);
        resource.cpu_descriptor = getStagingHeapCpuPointer(resource.cpu_handle);
        resource.binding_type = .dsv;
        const instance = try getInstance();
        instance.device.CreateDepthStencilView(resource.resource, &desc, resource.cpu_descriptor);
    }

    fn createCbv(
        resource: *D3DResource,
        desc: d3d12.CONSTANT_BUFFER_VIEW_DESC,
    ) gpu.Error!void {
        resource.cpu_handle = try allocateStagingHeapDescriptor(.CBV_SRV_UAV, .CBV);
        resource.cpu_descriptor = getStagingHeapCpuPointer(resource.cpu_handle);
        resource.binding_type = .cbv;
        const instance = try getInstance();
        instance.device.CreateConstantBufferView(&desc, resource.cpu_descriptor);
    }
};

pub fn initTextureResource(
    allocator: std.mem.Allocator,
    desc: gpu.TextureResourceDesc,
) gpu.Error!*gpu.Resource {
    const texture_ptr: *D3DTexture = @ptrCast(@alignCast(desc.texture));

    const remaining_mips = if (desc.mip_num == 0) (texture_ptr.desc.mip_num - desc.mip_start) else desc.mip_num;
    const remaining_layers = if (desc.layer_num == 0) (texture_ptr.desc.layer_num - desc.layer_start) else desc.layer_num;

    const format = desc.format;
    const typeless = conv.formatToTypeless(format);

    var srv_desc = std.mem.zeroes(d3d12.SHADER_RESOURCE_VIEW_DESC);
    srv_desc.Format = typeless;
    srv_desc.ViewDimension = switch (desc.dimension) {
        .d1 => .TEXTURE1D,
        .d2 => .TEXTURE2D,
        .d3 => .TEXTURE3D,
    };
    srv_desc.Shader4ComponentMapping = d3d12.DEFAULT_SHADER_4_COMPONENT_MAPPING;

    var uav_desc = std.mem.zeroes(d3d12.UNORDERED_ACCESS_VIEW_DESC);
    uav_desc.Format = typeless;
    uav_desc.ViewDimension = switch (desc.dimension) {
        .d1 => .TEXTURE1D,
        .d2 => .TEXTURE2D,
        .d3 => .TEXTURE3D,
    };

    var rtv_desc = std.mem.zeroes(d3d12.RENDER_TARGET_VIEW_DESC);
    rtv_desc.Format = typeless;
    rtv_desc.ViewDimension = switch (desc.dimension) {
        .d1 => .TEXTURE1D,
        .d2 => .TEXTURE2D,
        .d3 => .TEXTURE3D,
    };

    var dsv_desc = std.mem.zeroes(d3d12.DEPTH_STENCIL_VIEW_DESC);
    dsv_desc.Format = conv.formatTo(format);
    dsv_desc.ViewDimension = switch (desc.dimension) {
        .d1 => .TEXTURE1D,
        .d2 => .TEXTURE2D,
        .d3 => return error.InvalidResourceKind,
    };
    dsv_desc.Flags = .{};

    const resource_ptr = try allocator.create(D3DResource);
    resource_ptr.allocator = allocator;
    resource_ptr.resource = texture_ptr.d3d_texture;
    resource_ptr.view_kind = desc.kind;
    resource_ptr.heap_type = .CBV_SRV_UAV;
    switch (desc.kind) {
        .srv => {
            switch (desc.dimension) {
                .d1 => {
                    srv_desc.u.Texture1D.MostDetailedMip = desc.mip_start;
                    srv_desc.u.Texture1D.MipLevels = remaining_mips;
                },
                .d2 => {
                    if (texture_ptr.desc.sample_num > 1) {
                        srv_desc.ViewDimension = .TEXTURE2DMS;
                    } else {
                        srv_desc.u.Texture2D.MostDetailedMip = desc.mip_start;
                        srv_desc.u.Texture2D.MipLevels = remaining_mips;
                        srv_desc.u.Texture2D.PlaneSlice = 0;
                    }
                },
                .d3 => {
                    srv_desc.u.Texture3D.MostDetailedMip = desc.mip_start;
                    srv_desc.u.Texture3D.MipLevels = remaining_mips;
                },
            }
            try resource_ptr.createSrv(srv_desc);
        },
        .srv_array => {
            switch (desc.dimension) {
                .d1 => {
                    srv_desc.u.Texture1DArray.MostDetailedMip = desc.mip_start;
                    srv_desc.u.Texture1DArray.MipLevels = remaining_mips;
                    srv_desc.u.Texture1DArray.FirstArraySlice = desc.layer_start;
                    srv_desc.u.Texture1DArray.ArraySize = remaining_layers;
                },
                .d2 => {
                    if (texture_ptr.desc.sample_num > 1) {
                        srv_desc.ViewDimension = .TEXTURE2DMSARRAY;
                        srv_desc.u.Texture2DMSArray.FirstArraySlice = desc.layer_start;
                        srv_desc.u.Texture2DMSArray.ArraySize = remaining_layers;
                    } else {
                        srv_desc.u.Texture2DArray.MostDetailedMip = desc.mip_start;
                        srv_desc.u.Texture2DArray.MipLevels = remaining_mips;
                        srv_desc.u.Texture2DArray.FirstArraySlice = desc.layer_start;
                        srv_desc.u.Texture2DArray.ArraySize = remaining_layers;
                        srv_desc.u.Texture2DArray.PlaneSlice = 0;
                    }
                },
                .d3 => return error.InvalidResourceKind,
            }
            try resource_ptr.createSrv(srv_desc);
        },
        .rtv => {
            switch (desc.dimension) {
                .d1 => {
                    rtv_desc.u.Texture1D.MipSlice = desc.mip_start;
                },
                .d2 => {
                    if (texture_ptr.desc.sample_num > 1) {
                        rtv_desc.ViewDimension = .TEXTURE2DMSARRAY;
                        rtv_desc.u.Texture2DMSArray.FirstArraySlice = desc.layer_start;
                        rtv_desc.u.Texture2DMSArray.ArraySize = remaining_layers;
                    } else {
                        rtv_desc.u.Texture2DArray.MipSlice = desc.mip_start;
                        rtv_desc.u.Texture2DArray.FirstArraySlice = desc.layer_start;
                        rtv_desc.u.Texture2DArray.ArraySize = remaining_layers;
                        rtv_desc.u.Texture2DArray.PlaneSlice = 0;
                    }
                },
                .d3 => {
                    rtv_desc.u.Texture3D.MipSlice = desc.mip_start;
                    rtv_desc.u.Texture3D.FirstWSlice = desc.layer_start;
                    rtv_desc.u.Texture3D.WSize = remaining_layers;
                },
            }
            try resource_ptr.createRtv(rtv_desc);
        },
        .uav => {
            switch (desc.dimension) {
                .d1 => {
                    uav_desc.u.Texture1D.MipSlice = desc.mip_start;
                },
                .d2 => {
                    uav_desc.u.Texture2D.MipSlice = desc.mip_start;
                    uav_desc.u.Texture2D.PlaneSlice = 0;
                },
                .d3 => {
                    uav_desc.u.Texture3D.MipSlice = desc.mip_start;
                    uav_desc.u.Texture3D.FirstWSlice = desc.layer_start;
                    uav_desc.u.Texture3D.WSize = remaining_layers;
                },
            }
            try resource_ptr.createUav(texture_ptr.desc.format.isInteger(), uav_desc);
        },
        .dsv => {
            switch (desc.dimension) {
                .d1 => {
                    dsv_desc.u.Texture1D.MipSlice = desc.mip_start;
                },
                .d2 => {
                    if (texture_ptr.desc.sample_num > 1) {
                        dsv_desc.ViewDimension = .TEXTURE2DMSARRAY;
                        dsv_desc.u.Texture2DMSArray.FirstArraySlice = desc.layer_start;
                        dsv_desc.u.Texture2DMSArray.ArraySize = remaining_layers;
                    } else {
                        dsv_desc.ViewDimension = .TEXTURE2DARRAY;
                        dsv_desc.u.Texture2DArray.MipSlice = desc.mip_start;
                        dsv_desc.u.Texture2DArray.FirstArraySlice = desc.layer_start;
                        dsv_desc.u.Texture2DArray.ArraySize = remaining_layers;
                        // dsv_desc.u.Texture2DArray.PlaneSlice = 0;
                    }
                },
                else => unreachable,
            }
            try resource_ptr.createDsv(dsv_desc);
        },
        else => {
            log.err("not implemented resource kind: {s}", .{@tagName(desc.kind)});
            return error.InvalidResourceKind;
        },
    }

    return @ptrCast(resource_ptr);
}

pub fn initBufferResource(
    allocator: std.mem.Allocator,
    desc: gpu.BufferResourceDesc,
) gpu.Error!*gpu.Resource {
    const buffer_ptr: *D3DBuffer = @ptrCast(@alignCast(desc.buffer));

    const resource_ptr = try allocator.create(D3DResource);
    resource_ptr.allocator = allocator;
    resource_ptr.resource = buffer_ptr.resource;
    resource_ptr.view_kind = desc.kind;
    resource_ptr.heap_type = .CBV_SRV_UAV;

    const format = conv.formatTo(desc.format);
    const size = if (desc.size == gpu.WHOLE_SIZE) buffer_ptr.desc.size else desc.size;
    const element_size = if (buffer_ptr.desc.structure_stride > 0)
        buffer_ptr.desc.structure_stride
    else
        @divTrunc(format.pixelSizeInBits(), 8);
    const element_offset = @divTrunc(desc.offset, @as(u64, @intCast(element_size)));
    const element_num = @divTrunc(size, @as(u64, @intCast(element_size)));

    resource_ptr.buffer_gpu_location = buffer_ptr.resource.GetGPUVirtualAddress() + desc.offset;
    switch (desc.kind) {
        .srv => {
            var srv_desc = std.mem.zeroes(d3d12.SHADER_RESOURCE_VIEW_DESC);
            srv_desc.Format = if (buffer_ptr.desc.structure_stride > 0) .UNKNOWN else format;
            srv_desc.ViewDimension = .BUFFER;
            srv_desc.Shader4ComponentMapping = d3d12.DEFAULT_SHADER_4_COMPONENT_MAPPING;
            srv_desc.u.Buffer.FirstElement = element_offset;
            srv_desc.u.Buffer.NumElements = @intCast(element_num);
            srv_desc.u.Buffer.StructureByteStride = buffer_ptr.desc.structure_stride;
            try resource_ptr.createSrv(srv_desc);
        },
        .uav => {
            var uav_desc = std.mem.zeroes(d3d12.UNORDERED_ACCESS_VIEW_DESC);
            uav_desc.Format = if (buffer_ptr.desc.structure_stride > 0) .UNKNOWN else format;
            uav_desc.ViewDimension = .BUFFER;
            uav_desc.u.Buffer.FirstElement = element_offset;
            uav_desc.u.Buffer.NumElements = @intCast(element_num);
            uav_desc.u.Buffer.StructureByteStride = buffer_ptr.desc.structure_stride;
            try resource_ptr.createUav(desc.format.isInteger(), uav_desc);
        },
        .cbv => {
            var cbv_desc = std.mem.zeroes(d3d12.CONSTANT_BUFFER_VIEW_DESC);
            cbv_desc.BufferLocation = resource_ptr.buffer_gpu_location;
            cbv_desc.SizeInBytes = @intCast(size);
            std.debug.assert(cbv_desc.SizeInBytes % d3d12.CONSTANT_BUFFER_DATA_PLACEMENT_ALIGNMENT == 0);
            try resource_ptr.createCbv(cbv_desc);
        },
        else => return error.InvalidResourceKind,
    }

    return @ptrCast(resource_ptr);
}

pub fn initSampler(allocator: std.mem.Allocator, desc: gpu.SamplerDesc) gpu.Error!*gpu.Resource {
    const instance = try getInstance();

    const resource_ptr = try allocator.create(D3DResource);
    resource_ptr.allocator = allocator;
    resource_ptr.cpu_handle = try allocateStagingHeapDescriptor(.SAMPLER, .SAMPLER);
    resource_ptr.cpu_descriptor = getStagingHeapCpuPointer(resource_ptr.cpu_handle);
    resource_ptr.heap_type = .SAMPLER;

    const use_anisotropy = desc.anisotropy > 1;
    const use_comparison = desc.compare_op != .none;
    const anisotropy_filter: d3d12.FILTER = filter: {
        if (desc.filters.ext == .min) break :filter .MINIMUM_ANISOTROPIC;
        if (desc.filters.ext == .max) break :filter .MAXIMUM_ANISOTROPIC;
        if (use_comparison) break :filter .COMPARISON_ANISOTROPIC;
        break :filter .ANISOTROPIC;
    };
    const isotropy_filter: d3d12.FILTER = filter: {
        var mask: std.os.windows.UINT = 0;
        if (desc.filters.mip == .nearest) mask |= 0x1;
        if (desc.filters.mag == .linear) mask |= 0x4;
        if (desc.filters.min == .linear) mask |= 0x10;

        if (use_comparison)
            mask |= 0x80
        else if (desc.filters.ext == .min)
            mask |= 0x100
        else if (desc.filters.ext == .max)
            mask |= 0x180;

        break :filter @enumFromInt(mask);
    };
    const filter = if (use_anisotropy) anisotropy_filter else isotropy_filter;

    const sampler_desc: d3d12.SAMPLER_DESC = .{
        .Filter = filter,
        .AddressU = conv.addressModeTo(desc.address_modes.u),
        .AddressV = conv.addressModeTo(desc.address_modes.v),
        .AddressW = conv.addressModeTo(desc.address_modes.w),
        .MipLODBias = desc.mip_bias,
        .MaxAnisotropy = desc.anisotropy,
        .ComparisonFunc = conv.compareOpTo(desc.compare_op),
        .BorderColor = if (desc.is_int) @splat(0) else desc.border_color,
        .MinLOD = desc.mip_min,
        .MaxLOD = desc.mip_max,
    };

    instance.device.CreateSampler(&sampler_desc, resource_ptr.cpu_descriptor);

    return @ptrCast(resource_ptr);
}

pub fn deinitResource(resource: *gpu.Resource) void {
    const resource_ptr: *D3DResource = @ptrCast(@alignCast(resource));
    freeStagingHeapDescriptor(resource_ptr.cpu_handle);
    resource_ptr.allocator.destroy(resource_ptr);
}

const D3DResourceSet = struct {
    allocator: std.mem.Allocator,

    bound: std.BoundedArray(D3DDescriptor, gpu.MAX_BINDINGS_PER_SET),
    gpu_addresses: std.BoundedArray(d3d12.GPU_VIRTUAL_ADDRESS, gpu.MAX_BINDINGS_PER_SET),
    is_set: std.BoundedArray(bool, gpu.MAX_BINDINGS_PER_SET),
};

pub fn initResourceSet(allocator: std.mem.Allocator, desc: gpu.ResourceSetDesc) gpu.Error!*gpu.ResourceSet {
    const resource_set_ptr = try allocator.create(D3DResourceSet);
    resource_set_ptr.allocator = allocator;
    resource_set_ptr.bound = .{};
    resource_set_ptr.is_set = .{};
    resource_set_ptr.gpu_addresses = .{};

    for (desc.bindings) |binding| {
        const range_type: d3d12.DESCRIPTOR_RANGE_TYPE = switch (binding.kind) {
            .sampler => .SAMPLER,
            .constant_buffer => .CBV,
            .srv_texture, .srv_buffer, .srv_structured_buffer => .SRV,
            .uav_texture, .uav_buffer, .uav_structured_buffer => .UAV,
        };
        const is_table = !(binding.resource_num == 1 and range_type != .SAMPLER);
        if (is_table) {
            const descriptor = try allocateGpuHeapDescriptor(
                switch (range_type) {
                    .SRV, .UAV, .CBV => .CBV_SRV_UAV,
                    .SAMPLER => .SAMPLER,
                },
                range_type,
                binding.resource_num,
            );
            try resource_set_ptr.bound.append(descriptor);
        } else {
            const descriptor = try allocateGpuHeapDescriptor(
                .CBV_SRV_UAV,
                range_type,
                1,
            );
            try resource_set_ptr.bound.append(descriptor);
        }
        try resource_set_ptr.is_set.append(false);
        try resource_set_ptr.gpu_addresses.append(0);
    }

    return @ptrCast(resource_set_ptr);
}

pub fn deinitResourceSet(resource_set: *gpu.ResourceSet) void {
    const resource_set_ptr: *D3DResourceSet = @ptrCast(@alignCast(resource_set));

    for (resource_set_ptr.bound.constSlice()) |descriptor| {
        freeGpuHeapDescriptor(descriptor);
    }

    resource_set_ptr.allocator.destroy(resource_set_ptr);
}

pub fn setResource(resource_set: *gpu.ResourceSet, binding: u32, offset: u32, resource: ?*gpu.Resource) gpu.Error!void {
    const instance = try getInstance();
    const resource_set_ptr: *D3DResourceSet = @ptrCast(@alignCast(resource_set));
    const resource_ptr: ?*D3DResource = if (resource) |r| @ptrCast(@alignCast(r)) else null;

    if (binding >= resource_set_ptr.bound.len) {
        return error.InvalidResourceBinding;
    }

    const descriptor = resource_set_ptr.bound.get(binding);
    const heap_type: d3d12.DESCRIPTOR_HEAP_TYPE = descriptor.heap_type;

    if (resource_ptr) |r| if (r.heap_type != heap_type) {
        log.err("resource heap type mismatch: {s} != {s}", .{
            @tagName(r.heap_type),
            @tagName(heap_type),
        });
        return error.InvalidResource;
    };

    const count = descriptor.allocation.size;
    const is_table = !(count == 1 and
        descriptor.heap_type != .SAMPLER);

    const src: d3d12.CPU_DESCRIPTOR_HANDLE = if (resource_ptr) |r|
        getStagingHeapCpuPointer(r.cpu_handle)
    else
        .{ .ptr = 0 };
    // const root_param = resource_set_ptr.pipeline_layout.root_params[binding];
    if (is_table) {
        if (offset >= count) {
            return error.InvalidResourceBinding;
        }
        const dst = getGpuHeapCpuPointer(descriptor, offset);
        instance.device.CopyDescriptorsSimple(1, dst, src, descriptor.heap_type);
        resource_set_ptr.is_set.buffer[binding] = true;
    } else {
        const dst = getGpuHeapCpuPointer(descriptor, 0);
        const matches: bool = if (resource_ptr) |r| @reduce(.Or, @Vector(3, bool){
            descriptor.range_type == .CBV and r.binding_type == .cbv,
            descriptor.range_type == .SRV and r.binding_type == .srv,
            descriptor.range_type == .UAV and r.binding_type == .uav,
        }) else true;
        if (matches) {
            instance.device.CopyDescriptorsSimple(1, dst, src, heap_type);
            resource_set_ptr.is_set.buffer[binding] = true;
            resource_set_ptr.gpu_addresses.buffer[binding] = if (resource_ptr) |r| r.buffer_gpu_location else 0;
        } else {
            return error.InvalidResourceBinding;
        }
    }
}

pub const D3DCommandQueue = struct {
    allocator: std.mem.Allocator,

    d3d_queue: *d3d12.ICommandQueue,
};
pub fn primaryQueue() *gpu.CommandQueue {
    const instance = getInstance() catch unreachable;
    return @ptrCast(instance.primary_queue);
}
pub fn initCommandQueue(allocator: std.mem.Allocator, desc: gpu.CommandQueueDesc) !*gpu.CommandQueue {
    const instance = try getInstance();
    const queue_ptr = try allocator.create(D3DCommandQueue);
    queue_ptr.allocator = allocator;

    const queue_desc: d3d12.COMMAND_QUEUE_DESC = .{
        .Type = switch (desc.kind) {
            .graphics => .DIRECT,
            .compute => .COMPUTE,
            .copy => .COPY,
        },
        .Priority = @intFromEnum(d3d12.COMMAND_QUEUE_PRIORITY.NORMAL),
        .Flags = .{},
        .NodeMask = 0,
    };

    const hr_createqueue = instance.device.CreateCommandQueue(
        &queue_desc,
        &d3d12.IID_ICommandQueue,
        @ptrCast(&queue_ptr.d3d_queue),
    );
    if (hr_createqueue != windows.S_OK) {
        return error.D3D12InternalError;
    }
    setDebugName(@ptrCast(queue_ptr.d3d_queue), desc.name);

    return @ptrCast(queue_ptr);
}

pub fn deinitCommandQueue(queue: *gpu.CommandQueue) void {
    const queue_ptr: *D3DCommandQueue = @ptrCast(@alignCast(queue));
    fullyRelease(queue_ptr.d3d_queue);
    queue_ptr.allocator.destroy(queue_ptr);
}

pub fn signalFence(queue: *gpu.CommandQueue, fence: *gpu.Fence, value: u64) gpu.Error!void {
    const queue_ptr: *D3DCommandQueue = @ptrCast(@alignCast(queue));
    const fence_ptr: *D3DFence = @ptrCast(@alignCast(fence));

    const hr_signal = queue_ptr.d3d_queue.Signal(fence_ptr.d3d_fence, value);
    if (hr_signal != windows.S_OK) {
        return error.D3D12InternalError;
    }

    return;
}

pub fn waitFence(queue: *gpu.CommandQueue, fence: *gpu.Fence, value: u64) gpu.Error!void {
    const queue_ptr: *D3DCommandQueue = @ptrCast(@alignCast(queue));
    const fence_ptr: *D3DFence = @ptrCast(@alignCast(fence));

    const hr_wait = queue_ptr.d3d_queue.Wait(fence_ptr.d3d_fence, value);
    if (hr_wait != windows.S_OK) {
        return error.D3D12InternalError;
    }

    return;
}

pub fn submitQueue(queue: *gpu.CommandQueue, cmd: *gpu.CommandBuffer) gpu.Error!void {
    const queue_ptr: *D3DCommandQueue = @ptrCast(@alignCast(queue));
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));

    const command_lists: [*]const *d3d12.ICommandList = @ptrCast(&cmd_ptr.command_list);
    queue_ptr.d3d_queue.ExecuteCommandLists(1, command_lists);
}

const D3DCommandBuffer = struct {
    allocator: std.mem.Allocator,

    queue: *D3DCommandQueue,
    command_allocator: *d3d12.ICommandAllocator,
    command_list: *d3d12.IGraphicsCommandList4,
    render_targets: [gpu.MAX_ATTACHMENTS]d3d12.CPU_DESCRIPTOR_HANDLE,
    render_target_num: u32,
    depth_stencil: d3d12.CPU_DESCRIPTOR_HANDLE,
    pipeline_layout: ?*D3DPipelineLayout,
    pipeline: ?*D3DPipeline,
    primitive_topology: d3d12.PRIMITIVE_TOPOLOGY,
    resource_sets: [gpu.MAX_RESOURCE_SETS]?*D3DResourceSet = empty_resource_sets,
    /// on d3d12, pipelines must be set so the root params are known, before setting resources
    /// so we need to store the resource sets here
    pending_resource_setting: [gpu.MAX_RESOURCE_SETS]bool = @splat(false),
    is_graphics: bool,

    pub const empty_resource_sets: [gpu.MAX_RESOURCE_SETS]?*D3DResourceSet = @splat(null);
};
pub fn initCommandBuffer(allocator: std.mem.Allocator, queue: *gpu.CommandQueue) gpu.Error!*gpu.CommandBuffer {
    const instance = try getInstance();
    const queue_ptr: *D3DCommandQueue = @ptrCast(@alignCast(queue));
    const cmd_ptr = try allocator.create(D3DCommandBuffer);
    cmd_ptr.allocator = allocator;

    const hr_createallocator = instance.device.CreateCommandAllocator(
        .DIRECT,
        &d3d12.IID_ICommandAllocator,
        @ptrCast(&cmd_ptr.command_allocator),
    );
    if (hr_createallocator != windows.S_OK) {
        return error.D3D12InternalError;
    }

    const hr_createcommandlist = instance.device.CreateCommandList(
        0,
        .DIRECT,
        cmd_ptr.command_allocator,
        null,
        &d3d12.IID_IGraphicsCommandList4,
        @ptrCast(&cmd_ptr.command_list),
    );
    if (hr_createcommandlist != windows.S_OK) {
        return error.D3D12InternalError;
    }

    cmd_ptr.queue = queue_ptr;
    cmd_ptr.depth_stencil = .{ .ptr = 0 };
    cmd_ptr.pipeline_layout = null;
    cmd_ptr.pipeline = null;
    cmd_ptr.render_target_num = 0;
    cmd_ptr.is_graphics = true;
    cmd_ptr.primitive_topology = .TRIANGLELIST;
    cmd_ptr.resource_sets = D3DCommandBuffer.empty_resource_sets;
    cmd_ptr.pending_resource_setting = @splat(false);
    // close before use
    // ignore error here; should not happen
    _ = cmd_ptr.command_list.Close();

    return @ptrCast(cmd_ptr);
}

pub fn deinitCommandBuffer(cmd: *gpu.CommandBuffer) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));

    fullyRelease(cmd_ptr.command_list);
    fullyRelease(cmd_ptr.command_allocator);

    cmd_ptr.allocator.destroy(cmd_ptr);
}

pub fn beginCommandBuffer(cmd: *gpu.CommandBuffer) gpu.Error!void {
    const instance = try getInstance();
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));

    const hr_resetallocator = cmd_ptr.command_allocator.Reset();
    if (hr_resetallocator != windows.S_OK) {
        return error.D3D12InternalError;
    }

    const hr_resetlist = cmd_ptr.command_list.Reset(cmd_ptr.command_allocator, null);
    if (hr_resetlist != windows.S_OK) {
        return error.D3D12InternalError;
    }

    // set the heaps
    const heaps: [2]*d3d12.IDescriptorHeap = .{
        instance.gpu_heaps[0].d3d_heap,
        instance.gpu_heaps[1].d3d_heap,
    };
    cmd_ptr.command_list.SetDescriptorHeaps(2, &heaps);

    cmd_ptr.depth_stencil = .{ .ptr = 0 };
    cmd_ptr.pipeline_layout = null;
    cmd_ptr.pipeline = null;
    cmd_ptr.render_target_num = 0;
    cmd_ptr.is_graphics = true;
    cmd_ptr.primitive_topology = .TRIANGLELIST;
    cmd_ptr.resource_sets = D3DCommandBuffer.empty_resource_sets;
    cmd_ptr.pending_resource_setting = @splat(false);

    return;
}

pub fn endCommandBuffer(cmd: *gpu.CommandBuffer) gpu.Error!void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));

    const hr_close = cmd_ptr.command_list.Close();
    if (hr_close != windows.S_OK) {
        return error.D3D12InternalError;
    }

    return;
}

pub fn setViewports(cmd: *gpu.CommandBuffer, viewports: []const gpu.Viewport) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));

    var d3d_viewports: [gpu.MAX_VIEWPORTS]d3d12.VIEWPORT = undefined;
    for (viewports, 0..) |v, i| {
        d3d_viewports[i] = .{
            .TopLeftX = v.x,
            .TopLeftY = if (v.origin_bottom_left) v.y else v.y + v.height,
            .Width = v.width,
            .Height = if (v.origin_bottom_left) v.height else -v.height,
            .MinDepth = v.min_depth,
            .MaxDepth = v.max_depth,
        };
    }

    cmd_ptr.command_list.RSSetViewports(@intCast(viewports.len), &d3d_viewports);
}

pub fn setScissors(cmd: *gpu.CommandBuffer, scissors: []const gpu.Rect) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));

    var d3d_scissors: [gpu.MAX_SCISSORS]d3d12.RECT = undefined;
    for (scissors, 0..) |s, i| {
        d3d_scissors[i] = .{
            .left = s.x,
            .top = s.y,
            .right = s.x + @as(i32, @intCast(s.width)),
            .bottom = s.y + @as(i32, @intCast(s.height)),
        };
    }

    cmd_ptr.command_list.RSSetScissorRects(@intCast(scissors.len), &d3d_scissors);
}

pub fn setDepthBounds(cmd: *gpu.CommandBuffer, min: f32, max: f32) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));
    cmd_ptr.command_list.OMSetDepthBounds(min, max);
}

pub fn setStencilReference(cmd: *gpu.CommandBuffer, ref: u8) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));
    cmd_ptr.command_list.OMSetStencilRef(ref);
}

pub fn clearAttachment(
    cmd: *gpu.CommandBuffer,
    clear: gpu.Clear,
    rect: gpu.Rect,
) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));

    const d3d_rect: d3d12.RECT = .{
        .left = rect.x,
        .top = rect.y,
        .right = rect.x + @as(i32, @intCast(rect.width)),
        .bottom = rect.y + @as(i32, @intCast(rect.height)),
    };

    switch (clear) {
        ._color => |color| {
            const color_value = color.value;
            if (color.attachment_index >= cmd_ptr.render_target_num) {
                // log.warn("Clearing non-existent render target {}", .{clear.attachment_index});
                return;
            }
            const handle = cmd_ptr.render_targets[color.attachment_index];
            // is null, do nothing
            if (handle.ptr == 0) {
                return;
            }
            cmd_ptr.command_list.ClearRenderTargetView(
                handle,
                &color_value,
                1,
                @ptrCast(&d3d_rect),
            );
        },
        ._depth => |depth| {
            const handle = cmd_ptr.depth_stencil;
            // is null, do nothing
            if (handle.ptr == 0) {
                return;
            }
            const clear_flags: d3d12.CLEAR_FLAGS = .{
                .DEPTH = true,
                .STENCIL = false,
            };
            cmd_ptr.command_list.ClearDepthStencilView(
                handle,
                clear_flags,
                depth,
                0,
                1,
                @ptrCast(&d3d_rect),
            );
        },
        ._stencil => |stencil| {
            const handle = cmd_ptr.depth_stencil;
            // is null, do nothing
            if (handle.ptr == 0) {
                return;
            }
            const clear_flags: d3d12.CLEAR_FLAGS = .{
                .DEPTH = false,
                .STENCIL = true,
            };
            cmd_ptr.command_list.ClearDepthStencilView(
                handle,
                clear_flags,
                0,
                @intCast(stencil),
                1,
                @ptrCast(&d3d_rect),
            );
        },
    }
}

pub fn clearBuffer(cmd: *gpu.CommandBuffer, desc: gpu.ClearBufferDesc) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));

    const resource_set = cmd_ptr.resource_set orelse {
        log.err("Resource set not set", .{});
        return;
    };

    const resource_ptr: *D3DResource = @ptrCast(@alignCast(desc.buffer));

    const set = desc.set_index;
    if (set >= gpu.MAX_RESOURCE_SETS) {
        log.err("Invalid resource set index: {d}", .{set});
        return;
    }

    const binding = desc.binding_index;
    if (binding >= gpu.MAX_BINDINGS_PER_SET) {
        log.err("Invalid binding index: {d}", .{binding});
        return;
    }

    const is_set = resource_set.is_set.get(binding);
    if (!is_set) {
        log.err("Resource not set: {d}", .{binding});
        return;
    }
    const descriptor: D3DDescriptor = resource_set.bound.get(binding);
    const gpu_address = getGpuHeapGpuPointer(descriptor, desc.resource_index);

    const clear_values = [4]u32{
        desc.value,
        desc.value,
        desc.value,
        desc.value,
    };

    cmd_ptr.command_list.ClearUnorderedAccessViewUint(
        gpu_address,
        resource_ptr.cpu_descriptor,
        resource_ptr.resource,
        &clear_values,
        0,
        null,
    );
}

pub fn clearTexture(cmd: *gpu.CommandBuffer, desc: gpu.ClearTextureDesc) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));

    const resource_set = cmd_ptr.resource_set orelse {
        log.err("Resource set not set", .{});
        return;
    };

    const resource_ptr: *D3DResource = @ptrCast(@alignCast(desc.texture));

    const binding = desc.binding_index;
    if (binding >= gpu.MAX_BINDINGS) {
        log.err("Invalid binding index: {d}", .{binding});
        return;
    }

    const is_set = resource_set.is_set.get(binding);
    if (!is_set) {
        log.err("Resource not set: {d}", .{binding});
        return;
    }
    const descriptor: D3DDescriptor = resource_set.bound.get(binding);
    const gpu_address = getGpuHeapGpuPointer(descriptor, desc.resource_index);
    if (resource_set.pipeline_layout.root_params[binding].ParameterType != .UAV) {
        log.err("Invalid resource type: {s}", .{@tagName(resource_set.pipeline_layout.root_params[binding].ParameterType)});
        return;
    }

    const clear_value = desc.value._color;
    if (resource_ptr.integer_format) {
        const clear_values = [4]u32{
            @intFromFloat(clear_value[0]),
            @intFromFloat(clear_value[1]),
            @intFromFloat(clear_value[2]),
            @intFromFloat(clear_value[3]),
        };
        cmd_ptr.command_list.ClearUnorderedAccessViewUint(
            gpu_address,
            resource_ptr.cpu_descriptor,
            resource_ptr.resource,
            &clear_values,
            0,
            null,
        );
    } else {
        cmd_ptr.command_list.ClearUnorderedAccessViewFloat(
            gpu_address,
            resource_ptr.cpu_descriptor,
            resource_ptr.resource,
            &clear_value,
            0,
            null,
        );
    }
}

pub fn setVertexBuffer(
    cmd: *gpu.CommandBuffer,
    slot: u32,
    buffer: *gpu.Buffer,
    offset: u64,
) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));

    const buffer_ptr: *D3DBuffer = @ptrCast(@alignCast(buffer));

    // ensure vertex buffer
    ensureBufferState(cmd, buffer, .vertex);

    const vertex_buffer_view: d3d12.VERTEX_BUFFER_VIEW = .{
        .BufferLocation = buffer_ptr.resource.GetGPUVirtualAddress() + offset,
        .SizeInBytes = @intCast(buffer_ptr.desc.size - offset),
        .StrideInBytes = @intCast(buffer_ptr.desc.structure_stride),
    };
    cmd_ptr.command_list.IASetVertexBuffers(
        @intCast(slot),
        1,
        @ptrCast(&vertex_buffer_view),
    );
}

pub fn setIndexBuffer(
    cmd: *gpu.CommandBuffer,
    buffer: *gpu.Buffer,
    offset: u64,
    kind: gpu.IndexKind,
) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));

    const buffer_ptr: *D3DBuffer = @ptrCast(@alignCast(buffer));

    ensureBufferState(cmd, buffer, .index);

    const index_buffer_view: d3d12.INDEX_BUFFER_VIEW = .{
        .BufferLocation = buffer_ptr.resource.GetGPUVirtualAddress() + offset,
        .SizeInBytes = @intCast(buffer_ptr.desc.size - offset),
        .Format = switch (kind) {
            .u16 => .R16_UINT,
            .u32 => .R32_UINT,
        },
    };
    cmd_ptr.command_list.IASetIndexBuffer(&index_buffer_view);
}

pub fn setPipelineLayout(
    cmd: *gpu.CommandBuffer,
    pipeline_layout: *gpu.PipelineLayout,
) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));
    const pipeline_layout_ptr: *D3DPipelineLayout = @ptrCast(@alignCast(pipeline_layout));

    cmd_ptr.pipeline_layout = pipeline_layout_ptr;
    cmd_ptr.pipeline = null;

    if (cmd_ptr.is_graphics) {
        cmd_ptr.command_list.SetGraphicsRootSignature(pipeline_layout_ptr.d3d_root_signature);
    } else {
        cmd_ptr.command_list.SetComputeRootSignature(pipeline_layout_ptr.d3d_root_signature);
    }

    // set the resource sets that are pending
    for (cmd_ptr.pending_resource_setting, 0..) |pending, i| {
        if (pending) {
            const resource_set = cmd_ptr.resource_sets[i] orelse continue;
            setResourceSet(cmd, @ptrCast(resource_set), @intCast(i));
            cmd_ptr.pending_resource_setting[i] = false;
        }
    }
}

pub fn setPipeline(
    cmd: *gpu.CommandBuffer,
    pipeline: *gpu.Pipeline,
) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));
    const pipeline_ptr: *D3DPipeline = @ptrCast(@alignCast(pipeline));

    cmd_ptr.pipeline = pipeline_ptr;

    if (cmd_ptr.is_graphics) {
        cmd_ptr.command_list.SetPipelineState(pipeline_ptr.pipeline);
        cmd_ptr.command_list.IASetPrimitiveTopology(cmd_ptr.primitive_topology);
        cmd_ptr.primitive_topology = cmd_ptr.primitive_topology;
    } else {
        cmd_ptr.command_list.SetPipelineState(pipeline_ptr.pipeline);
    }
}

pub fn setResourceSet(
    cmd: *gpu.CommandBuffer,
    resource_set: *gpu.ResourceSet,
    index: u32,
) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));
    const resource_set_ptr: *D3DResourceSet = @ptrCast(@alignCast(resource_set));

    if (index >= gpu.MAX_RESOURCE_SETS) {
        log.err("Invalid resource set index: {d}", .{index});
        return;
    }
    cmd_ptr.resource_sets[index] = resource_set_ptr;
    const pipeline_layout = cmd_ptr.pipeline_layout orelse {
        cmd_ptr.pending_resource_setting[index] = true;
        return;
    };
    const root_param_offset = pipeline_layout.set_indices[index];

    for (resource_set_ptr.bound.constSlice(), 0..) |descriptor, i| {
        const root_param_i = root_param_offset + i;
        const root_param = cmd_ptr.pipeline_layout.?.root_params[root_param_i];
        const gpu_descriptor = if (resource_set_ptr.is_set.get(i)) getGpuHeapGpuPointer(descriptor, 0) else continue;
        if (root_param.ParameterType != .DESCRIPTOR_TABLE) {
            switch (root_param.ParameterType) {
                .SRV => {
                    const gpu_address = gpu_descriptor.ptr;
                    if (cmd_ptr.is_graphics)
                        cmd_ptr.command_list.SetGraphicsRootShaderResourceView(
                            @intCast(root_param_i),
                            gpu_address,
                        )
                    else
                        cmd_ptr.command_list.SetComputeRootShaderResourceView(
                            @intCast(root_param_i),
                            gpu_address,
                        );
                },
                .UAV => {
                    const gpu_address = gpu_descriptor.ptr;
                    if (cmd_ptr.is_graphics)
                        cmd_ptr.command_list.SetGraphicsRootUnorderedAccessView(
                            @intCast(root_param_i),
                            gpu_address,
                        )
                    else
                        cmd_ptr.command_list.SetComputeRootUnorderedAccessView(
                            @intCast(root_param_i),
                            gpu_address,
                        );
                },
                .CBV => {
                    const gpu_address = resource_set_ptr.gpu_addresses.get(i);
                    if (cmd_ptr.is_graphics)
                        cmd_ptr.command_list.SetGraphicsRootConstantBufferView(
                            @intCast(root_param_i),
                            gpu_address,
                        )
                    else
                        cmd_ptr.command_list.SetComputeRootConstantBufferView(
                            @intCast(root_param_i),
                            gpu_address,
                        );
                },
                else => unreachable,
            }
        } else {
            if (cmd_ptr.is_graphics)
                cmd_ptr.command_list.SetGraphicsRootDescriptorTable(
                    @intCast(root_param_i),
                    gpu_descriptor,
                )
            else
                cmd_ptr.command_list.SetComputeRootDescriptorTable(
                    @intCast(root_param_i),
                    gpu_descriptor,
                );
        }
    }
}

pub fn setConstant(cmd: *gpu.CommandBuffer, data: []const u8) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));

    if (cmd_ptr.pipeline_layout == null) {
        log.err("Pipeline layout not set", .{});
        return;
    }
    const pipeline_layout_ptr: *D3DPipelineLayout = cmd_ptr.pipeline_layout orelse return;
    const data_slice = data;
    if (pipeline_layout_ptr.constant) |constant| {
        if (constant.size != data_slice.len) {
            log.err("Constant size mismatch: expected {d} but got {d}", .{ constant.size, data_slice.len });
            return;
        }
    } else {
        log.err("Pipeline layout does not have constant", .{});
        return;
    }

    const root_index = pipeline_layout_ptr.root_param_num - 1;
    if (cmd_ptr.is_graphics)
        cmd_ptr.command_list.SetGraphicsRoot32BitConstants(
            root_index,
            @intCast(@divTrunc(data_slice.len, 4)),
            @ptrCast(data_slice.ptr),
            0,
        )
    else
        cmd_ptr.command_list.SetComputeRoot32BitConstants(
            root_index,
            @intCast(@divTrunc(data_slice.len, 4)),
            @ptrCast(data_slice.ptr),
            0,
        );
}

pub fn draw(cmd: *gpu.CommandBuffer, desc: gpu.Draw) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));

    if (cmd_ptr.is_graphics) {
        cmd_ptr.command_list.DrawInstanced(
            desc.vertex_num,
            desc.instance_num,
            desc.first_vertex,
            desc.first_instance,
        );
    } else {
        log.err("Command buffer is not graphics", .{});
    }
}

pub fn drawIndexed(cmd: *gpu.CommandBuffer, desc: gpu.DrawIndexed) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));

    if (cmd_ptr.is_graphics) {
        cmd_ptr.command_list.DrawIndexedInstanced(
            desc.index_num,
            desc.instance_num,
            desc.first_index,
            desc.vertex_offset,
            desc.first_instance,
        );
    } else {
        log.err("Command buffer is not graphics", .{});
    }
}

pub fn drawIndirect(cmd: *gpu.CommandBuffer, desc: gpu.DrawIndirect) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));

    const pipeline_layout = cmd_ptr.pipeline_layout orelse {
        log.err("Pipeline layout not set", .{});
        return;
    };

    const buffer_ptr: *D3DBuffer = @ptrCast(@alignCast(desc.buffer));
    const count_buffer_ptr: ?*D3DBuffer = @ptrCast(@alignCast(desc.count_buffer));

    if (cmd_ptr.is_graphics) {
        cmd_ptr.command_list.ExecuteIndirect(
            pipeline_layout.d3d_indirect_signature,
            desc.count,
            buffer_ptr.resource,
            desc.offset,
            if (count_buffer_ptr) |count_buffer|
                count_buffer.resource
            else
                null,
            if (count_buffer_ptr) |_| desc.count_offset else 0,
        );
    } else {
        log.err("Command buffer is not graphics", .{});
    }
}

pub fn drawIndexedIndirect(cmd: *gpu.CommandBuffer, desc: gpu.DrawIndirect) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));

    const pipeline_layout = cmd_ptr.pipeline_layout orelse {
        log.err("Pipeline layout not set", .{});
        return;
    };

    const buffer_ptr: *D3DBuffer = @ptrCast(@alignCast(desc.buffer));
    const count_buffer_ptr: ?*D3DBuffer = @ptrCast(@alignCast(desc.count_buffer));

    if (cmd_ptr.is_graphics) {
        cmd_ptr.command_list.ExecuteIndirect(
            pipeline_layout.d3d_indirect_indexed_signature,
            desc.count,
            buffer_ptr.resource,
            desc.offset,
            if (count_buffer_ptr) |count_buffer|
                count_buffer.resource
            else
                null,
            if (count_buffer_ptr) |_| desc.count_offset else 0,
        );
    } else {
        log.err("Command buffer is not graphics", .{});
    }
}

pub fn dispatch(cmd: *gpu.CommandBuffer, desc: gpu.Dispatch) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));

    if (!cmd_ptr.is_graphics) {
        cmd_ptr.command_list.Dispatch(
            desc.x,
            desc.y,
            desc.z,
        );
    } else {
        log.err("Command buffer is not compute", .{});
    }
}

pub fn dispatchIndirect(cmd: *gpu.CommandBuffer, desc: gpu.DispatchIndirect) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));

    const pipeline_layout = cmd_ptr.pipeline_layout orelse {
        log.err("Pipeline layout not set", .{});
        return;
    };

    const buffer_ptr: *D3DBuffer = @ptrCast(@alignCast(desc.buffer));

    if (!cmd_ptr.is_graphics) {
        cmd_ptr.command_list.ExecuteIndirect(
            pipeline_layout.d3d_indirect_signature,
            1,
            buffer_ptr.resource,
            desc.offset,
            null,
            0,
        );
    } else {
        log.err("Command buffer is not compute", .{});
    }
}

pub fn copyBufferToBuffer(cmd: *gpu.CommandBuffer, dst: *gpu.Buffer, dst_offset: u64, src: *gpu.Buffer, src_offset: u64, size: u64) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));
    const dst_ptr: *D3DBuffer = @ptrCast(@alignCast(dst));
    const src_ptr: *D3DBuffer = @ptrCast(@alignCast(src));

    // ensure resource state
    ensureBufferState(cmd, dst, .copy_dest);
    ensureBufferState(cmd, src, .copy_source);

    cmd_ptr.command_list.CopyBufferRegion(
        dst_ptr.resource,
        dst_offset,
        src_ptr.resource,
        src_offset,
        size,
    );
}

pub fn copyTextureToTexture(
    cmd: *gpu.CommandBuffer,
    dst: *gpu.Texture,
    dst_region_opt: ?gpu.TextureRegion,
    src: *gpu.Texture,
    src_region_opt: ?gpu.TextureRegion,
) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));
    const dst_ptr: *D3DTexture = @ptrCast(@alignCast(dst));
    const src_ptr: *D3DTexture = @ptrCast(@alignCast(src));

    // ensure resource state
    ensureTextureState(cmd, dst, .copy_dest);
    ensureTextureState(cmd, src, .copy_source);

    if (dst_region_opt == null and src_region_opt == null) {
        cmd_ptr.command_list.CopyResource(
            dst_ptr.d3d_texture,
            src_ptr.d3d_texture,
        );
        return;
    }

    const whole_resource: gpu.TextureRegion = .{};
    const dst_region = dst_region_opt orelse whole_resource;
    const src_region = src_region_opt orelse whole_resource;

    const dst_texture_copy_location: d3d12.TEXTURE_COPY_LOCATION = .{
        .pResource = dst_ptr.d3d_texture,
        .Type = .SUBRESOURCE_INDEX,
        .u = .{ .SubresourceIndex = getTextureSubResourceIndex(
            dst_ptr.desc,
            dst_region.layer,
            dst_region.mip,
        ) },
    };

    const src_texture_copy_location: d3d12.TEXTURE_COPY_LOCATION = .{
        .pResource = src_ptr.d3d_texture,
        .Type = .SUBRESOURCE_INDEX,
        .u = .{ .SubresourceIndex = getTextureSubResourceIndex(
            src_ptr.desc,
            src_region.layer,
            src_region.mip,
        ) },
    };

    const size: [3]u32 = .{
        if (src_region.width == gpu.WHOLE_SIZE_U32) gpu.getDimensionMipAdjusted(src_ptr.desc, 0, src_region.mip) else src_region.width,
        if (src_region.height == gpu.WHOLE_SIZE_U32) gpu.getDimensionMipAdjusted(src_ptr.desc, 1, src_region.mip) else src_region.height,
        if (src_region.depth == gpu.WHOLE_SIZE_U32) gpu.getDimensionMipAdjusted(src_ptr.desc, 2, src_region.mip) else src_region.depth,
    };

    const box: d3d12.BOX = .{
        .left = src_region.x,
        .top = src_region.y,
        .front = src_region.z,
        .right = src_region.x + size[0],
        .bottom = src_region.y + size[1],
        .back = src_region.z + size[2],
    };

    cmd_ptr.command_list.CopyTextureRegion(
        &dst_texture_copy_location,
        dst_region.x,
        dst_region.y,
        dst_region.z,
        &src_texture_copy_location,
        &box,
    );
}

pub fn resolveTexture(
    cmd: *gpu.CommandBuffer,
    dst: *gpu.Texture,
    dst_region_opt: ?gpu.TextureRegion,
    src: *gpu.Texture,
    src_region_opt: ?gpu.TextureRegion,
) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));
    const dst_ptr: *D3DTexture = @ptrCast(@alignCast(dst));
    const src_ptr: *D3DTexture = @ptrCast(@alignCast(src));

    ensureTextureState(cmd, dst, .resolve_dest);
    ensureTextureState(cmd, src, .resolve_source);

    const dst_region: gpu.TextureRegion = dst_region_opt orelse .{};
    const src_region: gpu.TextureRegion = src_region_opt orelse .{};

    const dst_subresource = getTextureSubResourceIndex(
        dst_ptr.desc,
        dst_region.layer,
        dst_region.mip,
        dst_region.planes,
    );
    const src_subresource = getTextureSubResourceIndex(
        src_ptr.desc,
        src_region.layer,
        src_region.mip,
        src_region.planes,
    );

    var src_rect: d3d12.RECT = .{
        .left = @intCast(src_region.x),
        .top = @intCast(src_region.y),
        .right = @intCast(gpu.getDimensionMipAdjusted(src_ptr.desc, 0, src_region.mip)),
        .bottom = @intCast(gpu.getDimensionMipAdjusted(src_ptr.desc, 1, src_region.mip)),
    };

    cmd_ptr.command_list.ResolveSubresourceRegion(
        dst_ptr.d3d_texture,
        dst_subresource,
        dst_region.x,
        dst_region.y,
        src_ptr.d3d_texture,
        src_subresource,
        &src_rect,
        conv.formatTo(dst_ptr.desc.format),
        .AVERAGE,
    );
}

pub fn copyBufferToTexture(
    cmd: *gpu.CommandBuffer,
    dst: *gpu.Texture,
    dst_region_opt: ?gpu.TextureRegion,
    src: *gpu.Buffer,
    src_data_layout: gpu.TextureDataLayout,
    plane_flags: gpu.PlaneFlags,
) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));
    const dst_ptr: *D3DTexture = @ptrCast(@alignCast(dst));
    const src_ptr: *D3DBuffer = @ptrCast(@alignCast(src));

    const dst_region: gpu.TextureRegion = dst_region_opt orelse .{};

    // ensure resource state
    ensureTextureState(cmd, dst, .copy_dest);
    ensureBufferState(cmd, src, .copy_source);

    const dst_texture_copy_location: d3d12.TEXTURE_COPY_LOCATION = .{
        .pResource = dst_ptr.d3d_texture,
        .Type = .SUBRESOURCE_INDEX,
        .u = .{ .SubresourceIndex = getTextureSubResourceIndex(
            dst_ptr.desc,
            dst_region.layer,
            dst_region.mip,
            plane_flags,
        ) },
    };

    const size: [3]u32 = .{
        if (dst_region.width == gpu.WHOLE_SIZE_U32) gpu.getDimensionMipAdjusted(dst_ptr.desc, 0, dst_region.mip) else dst_region.width,
        if (dst_region.height == gpu.WHOLE_SIZE_U32) gpu.getDimensionMipAdjusted(dst_ptr.desc, 1, dst_region.mip) else dst_region.height,
        if (dst_region.depth == gpu.WHOLE_SIZE_U32) gpu.getDimensionMipAdjusted(dst_ptr.desc, 2, dst_region.mip) else dst_region.depth,
    };

    const src_texture_copy_location: d3d12.TEXTURE_COPY_LOCATION = .{
        .pResource = src_ptr.resource,
        .Type = .PLACED_FOOTPRINT,
        .u = .{ .PlacedFootprint = .{
            .Offset = src_data_layout.offset,
            .Footprint = .{
                .Format = conv.formatTo(dst_ptr.desc.format),
                .Width = size[0],
                .Height = size[1],
                .Depth = size[2],
                .RowPitch = src_data_layout.row_pitch,
            },
        } },
    };

    const box: d3d12.BOX = .{
        .left = dst_region.x,
        .top = dst_region.y,
        .front = dst_region.z,
        .right = dst_region.x + size[0],
        .bottom = dst_region.y + size[1],
        .back = dst_region.z + size[2],
    };

    cmd_ptr.command_list.CopyTextureRegion(
        &dst_texture_copy_location,
        dst_region.x,
        dst_region.y,
        dst_region.z,
        &src_texture_copy_location,
        &box,
    );
}

pub fn copyTextureToBuffer(
    cmd: *gpu.CommandBuffer,
    dst: *gpu.Buffer,
    dst_data_layout: gpu.TextureDataLayout,
    src: *gpu.Texture,
    src_region_opt: ?gpu.TextureRegion,
) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));
    const dst_ptr: *D3DBuffer = @ptrCast(@alignCast(dst));
    const src_ptr: *D3DTexture = @ptrCast(@alignCast(src));

    const src_region = src_region_opt orelse .{};

    // ensure resource state
    ensureTextureState(cmd, src, .copy_source);
    ensureBufferState(cmd, dst, .copy_dest);

    const dst_texture_copy_location: d3d12.TEXTURE_COPY_LOCATION = .{
        .pResource = dst_ptr.resource,
        .Type = .PLACED_FOOTPRINT,
        .u = .{ .PlacedFootprint = .{
            .Offset = dst_data_layout.offset,
            .Footprint = .{
                .Format = conv.formatTo(src_ptr.desc.format),
                .Width = src_region.width,
                .Height = src_region.height,
                .Depth = src_region.depth,
                .RowPitch = dst_data_layout.row_pitch,
            },
        } },
    };

    const size: [3]u32 = .{
        if (src_region.width == gpu.WHOLE_SIZE_U32) gpu.getDimensionMipAdjusted(src_ptr.desc, 0, src_region.mip) else src_region.width,
        if (src_region.height == gpu.WHOLE_SIZE_U32) gpu.getDimensionMipAdjusted(src_ptr.desc, 1, src_region.mip) else src_region.height,
        if (src_region.depth == gpu.WHOLE_SIZE_U32) gpu.getDimensionMipAdjusted(src_ptr.desc, 2, src_region.mip) else src_region.depth,
    };

    const src_texture_copy_location: d3d12.TEXTURE_COPY_LOCATION = .{
        .pResource = src_ptr.d3d_texture,
        .Type = .SUBRESOURCE_INDEX,
        .u = .{ .SubresourceIndex = getTextureSubResourceIndex(
            src_ptr.desc,
            src_region.layer,
            src_region.mip,
        ) },
    };
    const box: d3d12.BOX = .{
        .left = src_region.x,
        .top = src_region.y,
        .front = src_region.z,
        .right = src_region.x + size[0],
        .bottom = src_region.y + size[1],
        .back = src_region.z + size[2],
    };

    cmd_ptr.command_list.CopyTextureRegion(
        &dst_texture_copy_location,
        0,
        0,
        0,
        &src_texture_copy_location,
        &box,
    );
}

pub fn beginRendering(cmd: *gpu.CommandBuffer, attachments: gpu.Attachments) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));

    for (attachments.attachments, 0..) |color, i| {
        const resource_ptr: *D3DResource = @ptrCast(@alignCast(color));
        cmd_ptr.render_targets[i] = resource_ptr.cpu_descriptor;
    }
    cmd_ptr.render_target_num = @intCast(attachments.attachments.len);

    cmd_ptr.depth_stencil = if (attachments.depth_stencil) |ds| ds: {
        const resource_ptr: *D3DResource = @ptrCast(@alignCast(ds));
        break :ds resource_ptr.cpu_descriptor;
    } else .{ .ptr = 0 };

    cmd_ptr.command_list.OMSetRenderTargets(
        @intCast(cmd_ptr.render_target_num),
        &cmd_ptr.render_targets,
        windows.FALSE,
        if (cmd_ptr.depth_stencil.ptr != 0) &cmd_ptr.depth_stencil else null,
    );
}

pub fn endRendering(cmd: *gpu.CommandBuffer) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));

    cmd_ptr.render_target_num = 0;
    cmd_ptr.depth_stencil = .{ .ptr = 0 };
    cmd_ptr.render_targets = undefined;
    cmd_ptr.resource_sets = D3DCommandBuffer.empty_resource_sets;
    cmd_ptr.pipeline = null;
    cmd_ptr.pipeline_layout = null;
    cmd_ptr.primitive_topology = .UNDEFINED;
    cmd_ptr.is_graphics = false;
}

pub fn ensureTextureState(
    cmd: *gpu.CommandBuffer,
    texture: *gpu.Texture,
    state: gpu.TextureState,
) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));
    const texture_ptr: *D3DTexture = @ptrCast(@alignCast(texture));

    const d3d_state = conv.textureStateTo(state);
    if (texture_ptr.state == d3d_state) {
        return;
    }
    const barrier: d3d12.RESOURCE_BARRIER = .{
        .Type = .TRANSITION,
        .Flags = .{},
        .u = .{ .Transition = .{
            .pResource = texture_ptr.d3d_texture,
            .Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
            .StateBefore = texture_ptr.state,
            .StateAfter = d3d_state,
        } },
    };
    texture_ptr.state = d3d_state;

    cmd_ptr.command_list.ResourceBarrier(1, @ptrCast(&barrier));
}

pub fn ensureBufferState(
    cmd: *gpu.CommandBuffer,
    buffer: *gpu.Buffer,
    state: gpu.BufferState,
) void {
    const cmd_ptr: *D3DCommandBuffer = @ptrCast(@alignCast(cmd));
    const buffer_ptr: *D3DBuffer = @ptrCast(@alignCast(buffer));

    const d3d_state = conv.bufferStateTo(state);
    if (buffer_ptr.state == d3d_state) {
        return;
    }
    // std.debug.print("Ensuring buffer state: {} -> {} for {*}", .{ (buffer_ptr.state), (d3d_state), buffer_ptr.resource });
    const barrier: d3d12.RESOURCE_BARRIER = .{
        .Type = .TRANSITION,
        .Flags = .{},
        .u = .{ .Transition = .{
            .pResource = buffer_ptr.resource,
            .Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
            .StateBefore = buffer_ptr.state,
            .StateAfter = d3d_state,
        } },
    };
    buffer_ptr.state = d3d_state;

    cmd_ptr.command_list.ResourceBarrier(1, @ptrCast(&barrier));
}

const D3DFence = struct {
    allocator: std.mem.Allocator,
    d3d_fence: *d3d12.IFence,
    value: u64,
    event: windows.HANDLE,
};
pub fn initFence(allocator: std.mem.Allocator) !*gpu.Fence {
    const instance = try getInstance();
    const fence_ptr = try allocator.create(D3DFence);
    fence_ptr.allocator = allocator;

    const hr_createfence = instance.device.CreateFence(
        0,
        .{},
        &d3d12.IID_IFence,
        @ptrCast(&fence_ptr.d3d_fence),
    );
    if (hr_createfence != windows.S_OK) {
        return error.D3D12InternalError;
    }
    fence_ptr.value = 0;

    fence_ptr.event = windows.CreateEventExA(null, "Fence Event", 0, windows.EVENT_ALL_ACCESS) orelse
        return error.D3D12InternalError;

    return @ptrCast(fence_ptr);
}

pub fn deinitFence(fence: *gpu.Fence) void {
    const fence_ptr: *D3DFence = @ptrCast(@alignCast(fence));

    fullyRelease(fence_ptr.d3d_fence);
    _ = windows.CloseHandle(fence_ptr.event);

    fence_ptr.allocator.destroy(fence_ptr);
}

pub fn waitFenceBlocking(fence: *gpu.Fence, value: u64) gpu.Error!void {
    const fence_ptr: *D3DFence = @ptrCast(@alignCast(fence));

    if (fence_ptr.d3d_fence.GetCompletedValue() >= value) {
        return;
    }

    const hr_wait = fence_ptr.d3d_fence.SetEventOnCompletion(value, fence_ptr.event);
    if (hr_wait != windows.S_OK) {
        log.err("Failed to set event on completion: {}", .{hr_wait});
        return error.D3D12InternalError;
    }

    windows.WaitForSingleObject(fence_ptr.event, windows.INFINITE) catch
        return error.D3D12InternalError;

    return;
}

const D3DBuffer = struct {
    allocator: std.mem.Allocator,

    resource: *d3d12.IResource,
    allocation: *d3d12ma.Allocation,
    state: d3d12.RESOURCE_STATES,
    desc: gpu.BufferDesc,
    is_mapped: bool,
};
pub fn initBuffer(allocator: std.mem.Allocator, desc: gpu.BufferDesc) gpu.Error!*gpu.Buffer {
    const instance = try getInstance();

    const buffer_ptr = try allocator.create(D3DBuffer);
    buffer_ptr.allocator = allocator;
    buffer_ptr.desc = desc;
    buffer_ptr.is_mapped = false;

    if (desc.size == 0) {
        return error.BufferSizeZero;
    }

    const buffer_desc: d3d12.RESOURCE_DESC = .{
        .Dimension = .BUFFER,
        .Alignment = 0,
        .Width = desc.size,
        .Height = 1,
        .DepthOrArraySize = 1,
        .MipLevels = 1,
        .Format = .UNKNOWN,
        .SampleDesc = .{ .Count = 1, .Quality = 0 },
        .Layout = .ROW_MAJOR,
        .Flags = .{
            .ALLOW_UNORDERED_ACCESS = desc.usage.uav,
        },
    };

    const initial_state: d3d12.RESOURCE_STATES = switch (desc.location) {
        .host_upload => .GENERIC_READ,
        .host_readback => .{ .COPY_DEST = true },
        .device => .{},
    };
    buffer_ptr.state = initial_state;

    const alloc_info: d3d12ma.ALLOCATION_DESC = .{
        .HeapType = switch (desc.location) {
            .host_upload => .UPLOAD,
            .host_readback => .READBACK,
            .device => .DEFAULT,
        },
        .Flags = d3d12ma._ALLOCATION_FLAG_STRATEGY_MIN_MEMORY,
        .ExtraHeapFlags = .{ .CREATE_NOT_ZEROED = true },
    };

    const hr_createbuffer = instance.mem_allocator.CreateResource(
        &alloc_info,
        &buffer_desc,
        initial_state,
        null,
        @ptrCast(&buffer_ptr.allocation),
        &d3d12.IID_IResource,
        @ptrCast(&buffer_ptr.resource),
    );
    if (hr_createbuffer != windows.S_OK) {
        return error.D3D12InternalError;
    }

    setDebugName(@ptrCast(buffer_ptr.resource), desc.name);

    return @ptrCast(buffer_ptr);
}

pub fn deinitBuffer(buffer: *gpu.Buffer) void {
    const buffer_ptr: *D3DBuffer = @ptrCast(@alignCast(buffer));

    fullyRelease(buffer_ptr.resource);
    buffer_ptr.allocation.Release();

    buffer_ptr.allocator.destroy(buffer_ptr);
}

pub fn mapBuffer(buffer: *gpu.Buffer, range: gpu.Buffer.Range) ![]u8 {
    const buffer_ptr: *D3DBuffer = @ptrCast(@alignCast(buffer));

    if (buffer_ptr.is_mapped) {
        return error.BufferAlreadyMapped;
    }

    const offset = range.offset;
    const size = range.size;
    const real_size = if (size == gpu.WHOLE_SIZE) buffer_ptr.desc.size - offset else size;

    const d3d12_range: d3d12.RANGE = .{
        .Begin = offset,
        .End = offset + real_size,
    };

    var ptr_data: ?[*]u8 = null;
    const hr_map = buffer_ptr.resource.Map(0, if (size == gpu.WHOLE_SIZE) null else &d3d12_range, @ptrCast(&ptr_data));
    if (hr_map != windows.S_OK) {
        return error.D3D12InternalError;
    }
    buffer_ptr.is_mapped = true;

    return ptr_data.?[offset..][0..real_size];
}

pub fn unmapBuffer(buffer: *gpu.Buffer) void {
    const buffer_ptr: *D3DBuffer = @ptrCast(@alignCast(buffer));
    defer buffer_ptr.is_mapped = false;

    buffer_ptr.resource.Unmap(0, null);
}

pub fn getBufferDesc(buffer: *gpu.Buffer) gpu.BufferDesc {
    const buffer_ptr: *D3DBuffer = @ptrCast(@alignCast(buffer));
    return buffer_ptr.desc;
}

const D3DTexture = struct {
    allocator: ?std.mem.Allocator = null,
    d3d_texture: *d3d12.IResource,
    allocation: ?*d3d12ma.Allocation = null,
    state: d3d12.RESOURCE_STATES = .{},
    desc: gpu.TextureDesc,
};
pub fn initTexture(allocator: std.mem.Allocator, raw_desc: gpu.TextureDesc) gpu.Error!*gpu.Texture {
    const instance = try getInstance();

    const texture_ptr = try allocator.create(D3DTexture);
    const desc = raw_desc.fix();
    texture_ptr.allocator = allocator;
    texture_ptr.desc = desc;

    if (desc.width == 0 or desc.height == 0) {
        return error.TextureSizeZero;
    }

    const flags: d3d12.RESOURCE_FLAGS = .{
        .ALLOW_RENDER_TARGET = desc.usage.rtv,
        .ALLOW_DEPTH_STENCIL = desc.usage.dsv,
        .ALLOW_UNORDERED_ACCESS = desc.usage.uav,
        .DENY_SHADER_RESOURCE = desc.usage.dsv and !desc.usage.srv,
    };

    const block_width = desc.format.blockWidth();
    const block_height = desc.format.blockHeight();

    const texture_desc: d3d12.RESOURCE_DESC = .{
        .Dimension = switch (desc.kind) {
            .d1 => .TEXTURE1D,
            .d2 => .TEXTURE2D,
            .d3 => .TEXTURE3D,
        },
        .Alignment = 0,
        .Width = std.mem.alignForward(u32, desc.width, block_width),
        .Height = std.mem.alignForward(u32, desc.height, block_height),
        .DepthOrArraySize = @truncate(if (desc.kind == .d3) desc.depth else desc.layer_num),
        .MipLevels = @truncate(desc.mip_num),
        .Format = conv.formatToTypeless(desc.format),
        .SampleDesc = .{ .Count = desc.sample_num, .Quality = 0 },
        .Layout = .UNKNOWN,
        .Flags = flags,
    };
    texture_ptr.state = .{};

    const alloc_info: d3d12ma.ALLOCATION_DESC = .{
        .HeapType = switch (desc.location) {
            .host_upload => .UPLOAD,
            .host_readback => .READBACK,
            .device => .DEFAULT,
        },
        .Flags = d3d12ma._ALLOCATION_FLAG_STRATEGY_MIN_MEMORY,
        .ExtraHeapFlags = .{ .CREATE_NOT_ZEROED = true },
    };

    const optimised_clear_value: d3d12.CLEAR_VALUE, const set_clear_value: bool = cv: {
        if (desc.usage.dsv) {
            break :cv .{ .{
                .Format = conv.formatTo(desc.format),
                .u = .{
                    .DepthStencil = .{
                        .Depth = desc.clear_value._depth_stencil.depth,
                        .Stencil = @truncate(desc.clear_value._depth_stencil.stencil),
                    },
                },
            }, true };
        }
        if (desc.usage.rtv) {
            break :cv .{ .{
                .Format = conv.formatTo(desc.format),
                .u = .{
                    .Color = desc.clear_value._color,
                },
            }, true };
        }
        break :cv .{ undefined, false };
    };

    const hr_createtexture = instance.mem_allocator.CreateResource(
        &alloc_info,
        &texture_desc,
        .{},
        if (set_clear_value) &optimised_clear_value else null,
        @ptrCast(&texture_ptr.allocation),
        &d3d12.IID_IResource,
        @ptrCast(&texture_ptr.d3d_texture),
    );
    if (hr_createtexture != windows.S_OK) {
        return error.D3D12InternalError;
    }

    setDebugName(@ptrCast(texture_ptr.d3d_texture), desc.name);

    return @ptrCast(texture_ptr);
}

pub fn deinitTexture(texture: *gpu.Texture) void {
    const texture_ptr: *D3DTexture = @ptrCast(@alignCast(texture));

    if (texture_ptr.allocation) |a|
        a.Release();
    fullyRelease(texture_ptr.d3d_texture);

    if (texture_ptr.allocator) |allocator| allocator.destroy(texture_ptr);
}

pub fn getTextureDesc(texture: *gpu.Texture) gpu.TextureDesc {
    const texture_ptr: *D3DTexture = @ptrCast(@alignCast(texture));
    return texture_ptr.desc;
}

fn textureDescFromResource(resource: *d3d12.IResource) gpu.TextureDesc {
    var result = std.mem.zeroes(gpu.TextureDesc);
    result.kind = switch (resource.GetDesc().Dimension) {
        .TEXTURE1D => .d1,
        .TEXTURE2D => .d2,
        .TEXTURE3D => .d3,
        else => @panic("textureDescFromResource: called with a buffer resource"),
    };
    const desc = resource.GetDesc();
    result.format = conv.formatFrom(desc.Format);
    result.width = @intCast(desc.Width);
    result.height = @intCast(desc.Height);
    result.depth = if (result.kind == .d3) desc.DepthOrArraySize else 1;
    result.mip_num = desc.MipLevels;
    result.layer_num = if (result.kind == .d3) 1 else desc.DepthOrArraySize;
    result.sample_num = desc.SampleDesc.Count;
    result.usage = .{
        .rtv = desc.Flags.ALLOW_RENDER_TARGET,
        .dsv = desc.Flags.ALLOW_DEPTH_STENCIL,
        .uav = desc.Flags.ALLOW_UNORDERED_ACCESS,
        .srv = !desc.Flags.DENY_SHADER_RESOURCE,
    };

    return result;
}

fn textureBarrier(
    texture_ptr: *const D3DTexture,
    state_before: d3d12.RESOURCE_STATES,
    state_after: d3d12.RESOURCE_STATES,
) d3d12.RESOURCE_BARRIER {
    return .{
        .Type = .TRANSITION,
        .Flags = .{},
        .u = .{
            .Transition = .{
                .pResource = texture_ptr.d3d_texture,
                .Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
                .StateBefore = state_before,
                .StateAfter = state_after,
            },
        },
    };
}

const D3DPipelineLayout = struct {
    allocator: std.mem.Allocator,

    d3d_root_signature: *d3d12.IRootSignature,
    d3d_indirect_signature: *d3d12.ICommandSignature,
    d3d_indirect_indexed_signature: *d3d12.ICommandSignature,
    desc: gpu.PipelineLayoutDesc,
    ranges: [64]d3d12.DESCRIPTOR_RANGE1,
    range_num: u8,
    root_params: [64]d3d12.ROOT_PARAMETER1,
    root_param_num: u8,
    binding_count: u32,
    /// points to the index of the root parameter
    set_indices: [gpu.MAX_RESOURCE_SETS]usize,
    set_num: u8,
    constant: ?gpu.Constant,

    pub fn addDescriptorRange(self: *@This(), range: d3d12.DESCRIPTOR_RANGE1) usize {
        if (self.range_num == self.ranges.len) @panic("D3DPipelineLayout: too many descriptor ranges");
        defer self.range_num += 1;

        self.ranges[self.range_num] = range;
        return self.range_num;
    }

    // returns the index
    pub fn addRootParam(self: *@This(), param: d3d12.ROOT_PARAMETER1) usize {
        if (self.root_param_num == self.root_params.len) @panic("D3DPipelineLayout: too many root parameters");
        defer self.root_param_num += 1;

        self.root_params[self.root_param_num] = param;
        return self.root_param_num;
    }

    // returns the index
    pub fn addSetIndex(self: *@This()) usize {
        if (self.set_num == self.set_indices.len) @panic("D3DPipelineLayout: too many resource sets");
        defer self.set_num += 1;

        self.set_indices[self.set_num] = @intCast(self.root_param_num);
        return self.set_num;
    }

    pub fn rootParams(self: *@This()) []d3d12.ROOT_PARAMETER1 {
        return self.root_params[0..self.root_param_num];
    }
};

fn createCommandSignature(
    d3d_device: *d3d12.IDevice,
    ty: d3d12.INDIRECT_ARGUMENT_TYPE,
    root_sig: ?*d3d12.IRootSignature,
    stride: u32,
    enable_draw_params: bool,
    binding_count: u32,
) !*d3d12.ICommandSignature {
    const is_draw_arg = enable_draw_params and (ty == .DRAW or ty == .DRAW_INDEXED);
    var arg_descs = std.mem.zeroes([2]d3d12.INDIRECT_ARGUMENT_DESC);
    if (is_draw_arg) {
        arg_descs[0] = .{
            .Type = .CONSTANT,
            .u = .{ .Constant = .{
                .RootParameterIndex = binding_count,
                .DestOffsetIn32BitValues = 0,
                .Num32BitValuesToSet = 2,
            } },
        };

        arg_descs[1].Type = ty;
    } else {
        arg_descs[0].Type = ty;
    }

    const sig_desc: d3d12.COMMAND_SIGNATURE_DESC = .{
        .NodeMask = 0,
        .ByteStride = stride,
        .NumArgumentDescs = if (is_draw_arg) 2 else 1,
        .pArgumentDescs = &arg_descs[0],
    };

    var sig: ?*d3d12.ICommandSignature = null;
    const hr_create = d3d_device.CreateCommandSignature(
        &sig_desc,
        root_sig,
        &IID_ICommandSignature,
        @ptrCast(&sig),
    );
    if (hr_create != windows.S_OK) {
        return error.D3D12InternalError;
    }

    return sig.?;
}
const IID_ICommandSignature = windows.GUID.parse("{c36a797c-ec80-4f0a-8985-a7b2475082d1}");

pub fn initPipelineLayout(allocator: std.mem.Allocator, desc: gpu.PipelineLayoutDesc) gpu.Error!*gpu.PipelineLayout {
    const instance = try getInstance();
    const pipeline_layout_ptr = try allocator.create(D3DPipelineLayout);
    pipeline_layout_ptr.allocator = allocator;
    pipeline_layout_ptr.desc = desc;
    pipeline_layout_ptr.root_param_num = 0;
    pipeline_layout_ptr.range_num = 0;
    pipeline_layout_ptr.binding_count = 0;
    pipeline_layout_ptr.set_num = 0;
    pipeline_layout_ptr.constant = null;

    const sets = desc.sets;
    pipeline_layout_ptr.binding_count = 0;
    for (sets) |set| {
        if (set.bindings.len > gpu.MAX_BINDINGS_PER_SET) {
            return error.TooManyResourceBindings;
        }
        pipeline_layout_ptr.binding_count += @intCast(set.bindings.len);
    }
    if (sets.len > gpu.MAX_RESOURCE_SETS)
        return error.TooManyResourceBindings;
    for (sets, 0..) |set, set_i| {
        _ = pipeline_layout_ptr.addSetIndex();
        var set_binding_count: u32 = 0;
        for (set.bindings, 0..) |binding, binding_i| {
            _ = binding_i;
            const range_type: d3d12.DESCRIPTOR_RANGE_TYPE = switch (binding.kind) {
                .sampler => .SAMPLER,
                .constant_buffer => .CBV,
                .srv_texture, .srv_buffer, .srv_structured_buffer => .SRV,
                .uav_texture, .uav_buffer, .uav_structured_buffer => .UAV,
            };
            if (binding.resource_num == 1 and range_type != .SAMPLER) {
                _ = pipeline_layout_ptr.addRootParam(.{
                    .ParameterType = switch (range_type) {
                        .SRV => .SRV,
                        .UAV => .UAV,
                        .CBV => .CBV,
                        else => unreachable,
                    },
                    .ShaderVisibility = .ALL,
                    .u = .{ .Descriptor = .{
                        .ShaderRegister = set_binding_count,
                        .RegisterSpace = @intCast(set_i),
                        .Flags = .{},
                    } },
                });
                set_binding_count += 1;
            } else {
                const range_index = pipeline_layout_ptr.addDescriptorRange(.{
                    .RangeType = switch (binding.kind) {
                        .sampler => .SAMPLER,
                        .constant_buffer => .CBV,
                        .srv_texture, .srv_buffer, .srv_structured_buffer => .SRV,
                        .uav_texture, .uav_buffer, .uav_structured_buffer => .UAV,
                    },
                    .NumDescriptors = binding.resource_num,
                    .BaseShaderRegister = set_binding_count,
                    .RegisterSpace = @intCast(set_i),
                    .OffsetInDescriptorsFromTableStart = d3d12.DESCRIPTOR_RANGE_OFFSET_APPEND,
                    .Flags = .{
                        .DESCRIPTORS_VOLATILE = binding.resource_num > 1,
                        .DATA_VOLATILE = binding.resource_num > 1 and binding.kind != .sampler,
                    },
                });

                _ = pipeline_layout_ptr.addRootParam(.{
                    .ParameterType = .DESCRIPTOR_TABLE,
                    .ShaderVisibility = .ALL,
                    .u = .{ .DescriptorTable = .{
                        .NumDescriptorRanges = 1,
                        .pDescriptorRanges = pipeline_layout_ptr.ranges[range_index..][0..1].ptr,
                    } },
                });

                set_binding_count += binding.resource_num;
            }
        }
    }

    _ = pipeline_layout_ptr.addRootParam(.{
        .ParameterType = .@"32BIT_CONSTANTS",
        .ShaderVisibility = .VERTEX,
        .u = .{ .Constants = .{
            .ShaderRegister = 0,
            .RegisterSpace = 999,
            .Num32BitValues = 2,
        } },
    });

    if (desc.constant) |constant| {
        pipeline_layout_ptr.constant = constant;
        if (constant.size > gpu.MAX_CONSTANT_SIZE) {
            return error.TooLargeConstantSize;
        }
        _ = pipeline_layout_ptr.addRootParam(.{
            .ParameterType = .@"32BIT_CONSTANTS",
            .ShaderVisibility = .ALL,
            .u = .{
                .Constants = .{
                    .ShaderRegister = 0,
                    .RegisterSpace = gpu.MAX_RESOURCE_SETS,
                    .Num32BitValues = @divFloor(constant.size, 4) + @as(u32, if (@mod(constant.size, 4) == 0) 0 else 1),
                },
            },
        });
    }

    const root_sig_desc: d3d12.VERSIONED_ROOT_SIGNATURE_DESC = .initVersion1_1(
        .init(pipeline_layout_ptr.rootParams(), &.{}, .{
            .ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT = true,
        }),
    );

    var root_sig_blob: ?*d3d.IBlob = null;
    var error_blob: ?*d3d.IBlob = null;
    const hr_root_sig = d3d12.SerializeVersionedRootSignature(
        &root_sig_desc,
        @ptrCast(&root_sig_blob),
        @ptrCast(&error_blob),
    );
    if (hr_root_sig != windows.S_OK) {
        log.err("Failed to serialize root signature: {}: {s}", .{
            hr_root_sig,
            @as([*:0]const u8, @ptrCast(error_blob.?.GetBufferPointer())),
        });
        return error.D3D12InternalError;
    }

    const hr_create_root_sig = instance.device.CreateRootSignature(
        0,
        root_sig_blob.?.GetBufferPointer(),
        root_sig_blob.?.GetBufferSize(),
        &d3d12.IID_IRootSignature,
        @ptrCast(&pipeline_layout_ptr.d3d_root_signature),
    );
    if (hr_create_root_sig != windows.S_OK) {
        log.err("Failed to create root signature: {}", .{hr_create_root_sig});
        return error.D3D12InternalError;
    }

    setDebugName(@ptrCast(pipeline_layout_ptr.d3d_root_signature), desc.name);

    pipeline_layout_ptr.d3d_indirect_signature = try createCommandSignature(
        @ptrCast(instance.device),
        .DRAW,
        pipeline_layout_ptr.d3d_root_signature,
        @sizeOf(gpu.DrawEmulated),
        true,
        @intCast(pipeline_layout_ptr.binding_count),
    );
    pipeline_layout_ptr.d3d_indirect_indexed_signature = try createCommandSignature(
        @ptrCast(instance.device),
        .DRAW_INDEXED,
        pipeline_layout_ptr.d3d_root_signature,
        @sizeOf(gpu.DrawIndexedEmulated),
        true,
        @intCast(pipeline_layout_ptr.binding_count),
    );

    // print root signature
    for (pipeline_layout_ptr.rootParams(), 0..) |param, i| {
        log.info("[{}]: {s}", .{ i, @tagName(param.ParameterType) });
        switch (param.ParameterType) {
            .DESCRIPTOR_TABLE => {
                const ranges = if (param.u.DescriptorTable.pDescriptorRanges) |range|
                    range[0..param.u.DescriptorTable.NumDescriptorRanges]
                else
                    &.{};

                for (ranges, 0..) |range, j| {
                    log.info("  [{}]: {}x{s}", .{ j, range.NumDescriptors, @tagName(range.RangeType) });
                }
            },
            .@"32BIT_CONSTANTS" => {
                log.info("  [{}]: {} {}", .{
                    param.u.Constants.Num32BitValues,
                    param.u.Constants.ShaderRegister,
                    param.u.Constants.RegisterSpace,
                });
            },
            .SRV, .UAV, .CBV => {
                log.info("  [{s}]: {} {}", .{
                    @tagName(param.ParameterType),
                    param.u.Descriptor.ShaderRegister,
                    param.u.Descriptor.RegisterSpace,
                });
            },
        }
    }

    return @ptrCast(pipeline_layout_ptr);
}

pub fn deinitPipelineLayout(pipeline_layout: *gpu.PipelineLayout) void {
    const pipeline_layout_ptr: *D3DPipelineLayout = @ptrCast(@alignCast(pipeline_layout));

    fullyRelease(pipeline_layout_ptr.d3d_indirect_signature);
    fullyRelease(pipeline_layout_ptr.d3d_indirect_indexed_signature);

    fullyRelease(pipeline_layout_ptr.d3d_root_signature);
    pipeline_layout_ptr.allocator.destroy(pipeline_layout_ptr);
}

const D3DPipeline = struct {
    allocator: std.mem.Allocator,

    layout: *D3DPipelineLayout,
    pipeline: *d3d12.IPipelineState,
    ia_strides: [gpu.MAX_VERTEX_BUFFERS]u32,
    topology: d3d12.PRIMITIVE_TOPOLOGY,
    desc: union {
        graphics: gpu.GraphicsPipelineDesc,
        compute: gpu.ComputePipelineDesc,
    },
};

pub fn initGraphicsPipeline(
    allocator: std.mem.Allocator,
    desc: gpu.GraphicsPipelineDesc,
) gpu.Error!*gpu.Pipeline {
    const instance = try getInstance();

    const pipeline_layout_ptr: *D3DPipelineLayout = @ptrCast(@alignCast(desc.layout));

    const pipeline_ptr = try allocator.create(D3DPipeline);
    pipeline_ptr.allocator = allocator;
    pipeline_ptr.layout = pipeline_layout_ptr;
    pipeline_ptr.desc = .{ .graphics = desc };

    var pso_desc: d3d12.GRAPHICS_PIPELINE_STATE_DESC = .{};
    pso_desc.pRootSignature = pipeline_layout_ptr.d3d_root_signature;

    var it = desc.shaders.iterator();
    while (it.next(.{ .target = .dxil })) |shader| {
        switch (shader.stage) {
            .vertex => {
                pso_desc.VS = .init(shader.bytecode);
            },
            .fragment => {
                pso_desc.PS = .init(shader.bytecode);
            },
            else => {
                log.err("Unsupported shader stage: {}", .{shader.stage});
                return error.InvalidShaderStage;
            },
        }
    }

    const attributes = desc.vertex_input.attributes;
    const streams: []const gpu.VertexStream = desc.vertex_input.streams;
    var elements: std.BoundedArray(d3d12.INPUT_ELEMENT_DESC, gpu.MAX_VERTEX_ATTRIBUTES) = .{};
    pso_desc.InputLayout.pInputElementDescs = &elements.buffer;
    pso_desc.InputLayout.NumElements = @intCast(attributes.len);
    for (attributes) |attr| {
        const stream = streams[attr.stream];
        const is_per_vertex = stream.step_rate == .vertex;
        elements.appendAssumeCapacity(.{
            .SemanticName = "TEXCOORD",
            .SemanticIndex = attr.location,
            .Format = switch (attr.kind) {
                .u8 => .R8_UINT,
                .u8_normalized => .R8_UNORM,
                .i8 => .R8_SINT,
                .i8_normalized => .R8_SNORM,
                .u16 => .R16_UINT,
                .u16_normalized => .R16_UNORM,
                .i16 => .R16_SINT,
                .i16_normalized => .R16_SNORM,
                .u32 => .R32_UINT,
                .i32 => .R32_SINT,
                .f32 => .R32_FLOAT,

                .vec2 => .R32G32_FLOAT,
                .vec3 => .R32G32B32_FLOAT,
                .vec4 => .R32G32B32A32_FLOAT,
            },
            .InputSlot = @intCast(attr.stream),
            .AlignedByteOffset = @intCast(attr.offset),
            .InputSlotClass = switch (stream.step_rate) {
                .vertex => .PER_VERTEX_DATA,
                .instance => .PER_INSTANCE_DATA,
            },
            .InstanceDataStepRate = if (is_per_vertex) 0 else 1,
        });
    }

    std.debug.assert(desc.vertex_input.streams.len <= gpu.MAX_VERTEX_BUFFERS);
    pso_desc.PrimitiveTopologyType = switch (desc.input_assembly.topology) {
        .point_list => .POINT,
        .line_list => .LINE,
        .line_strip => .LINE,
        .triangle_list => .TRIANGLE,
        .triangle_strip => .TRIANGLE,
    };
    if (desc.multisample.enabled) {
        pso_desc.SampleDesc.Count = desc.multisample.sample_num;
        pso_desc.SampleDesc.Quality = 0;
        pso_desc.SampleMask = if (desc.multisample.sample_mask != 0) desc.multisample.sample_mask else 0xFFFFFFFF;
    } else {
        pso_desc.SampleDesc.Count = 1;
        pso_desc.SampleMask = 0xFFFFFFFF;
    }

    pso_desc.RasterizerState.FillMode = switch (desc.rasterization.fill_mode) {
        .solid => .SOLID,
        .wireframe => .WIREFRAME,
    };
    pso_desc.RasterizerState.CullMode = switch (desc.rasterization.cull_mode) {
        .none => .NONE,
        .back => .BACK,
        .front => .FRONT,
    };
    pso_desc.RasterizerState.FrontCounterClockwise = @intFromBool(desc.rasterization.front_counter_clockwise);
    pso_desc.RasterizerState.DepthBias = @intFromFloat(desc.rasterization.depth_bias.constant);
    pso_desc.RasterizerState.DepthBiasClamp = desc.rasterization.depth_bias.clamp;
    pso_desc.RasterizerState.SlopeScaledDepthBias = desc.rasterization.depth_bias.slope;
    pso_desc.RasterizerState.DepthClipEnable = @intFromBool(desc.rasterization.depth_clamp);
    pso_desc.RasterizerState.AntialiasedLineEnable = @intFromBool(desc.rasterization.line_smoothing);
    pso_desc.RasterizerState.ConservativeRaster = if (desc.rasterization.conservative) .ON else .OFF;

    if (desc.multisample.enabled) {
        pso_desc.RasterizerState.MultisampleEnable = @intFromBool(desc.multisample.sample_num > 1);
        // pso_desc.RasterizerState.ForcedSampleCount = if (desc.multisample.sample_num > 1) desc.multisample.sample_num else 0;
    }

    pso_desc.DepthStencilState.DepthEnable = @intFromBool(desc.output_merger.depth.compare_op != .none);
    pso_desc.DepthStencilState.DepthWriteMask = if (desc.output_merger.depth.write) .ALL else .ZERO;
    pso_desc.DepthStencilState.DepthFunc = conv.compareOpTo(desc.output_merger.depth.compare_op);
    pso_desc.DepthStencilState.StencilEnable = @intFromBool(desc.output_merger.stencil.front.compare_op != .none);
    pso_desc.DepthStencilState.StencilReadMask = desc.output_merger.stencil.front.compare_mask;
    pso_desc.DepthStencilState.StencilWriteMask = desc.output_merger.stencil.front.write_mask;
    pso_desc.DepthStencilState.FrontFace.StencilFailOp = conv.stencilOpTo(desc.output_merger.stencil.front.fail_op);
    pso_desc.DepthStencilState.FrontFace.StencilDepthFailOp = conv.stencilOpTo(desc.output_merger.stencil.front.depth_fail_op);
    pso_desc.DepthStencilState.FrontFace.StencilPassOp = conv.stencilOpTo(desc.output_merger.stencil.front.pass_op);
    pso_desc.DepthStencilState.FrontFace.StencilFunc = conv.compareOpTo(desc.output_merger.stencil.front.compare_op);
    pso_desc.DepthStencilState.BackFace.StencilFailOp = conv.stencilOpTo(desc.output_merger.stencil.back.fail_op);
    pso_desc.DepthStencilState.BackFace.StencilDepthFailOp = conv.stencilOpTo(desc.output_merger.stencil.back.depth_fail_op);
    pso_desc.DepthStencilState.BackFace.StencilPassOp = conv.stencilOpTo(desc.output_merger.stencil.back.pass_op);
    pso_desc.DepthStencilState.BackFace.StencilFunc = conv.compareOpTo(desc.output_merger.stencil.back.compare_op);
    pso_desc.DSVFormat = conv.formatTo(desc.output_merger.depth_stencil_format);

    pso_desc.BlendState.AlphaToCoverageEnable = @intFromBool(desc.multisample.enabled and desc.multisample.alpha_to_coverage);
    pso_desc.BlendState.IndependentBlendEnable = windows.TRUE;

    for (desc.output_merger.attachments, pso_desc.BlendState.RenderTarget[0..desc.output_merger.attachments.len]) |color, *target| {
        target.BlendEnable = @intFromBool(color.blend_enabled);
        target.RenderTargetWriteMask = .{
            .RED = color.write_mask.red,
            .GREEN = color.write_mask.green,
            .BLUE = color.write_mask.blue,
            .ALPHA = color.write_mask.alpha,
        };

        if (color.blend_enabled) {
            target.LogicOpEnable = @intFromBool(desc.output_merger.logic_op != .none);
            if (desc.output_merger.logic_op != .none)
                target.LogicOp = conv.logicOpTo(desc.output_merger.logic_op);
            target.SrcBlend = conv.blendFactorTo(color.color_blend.src);
            target.DestBlend = conv.blendFactorTo(color.color_blend.dst);
            target.BlendOp = conv.blendOpTo(color.color_blend.op);
            target.SrcBlendAlpha = conv.blendFactorTo(color.alpha_blend.src);
            target.DestBlendAlpha = conv.blendFactorTo(color.alpha_blend.dst);
            target.BlendOpAlpha = conv.blendOpTo(color.alpha_blend.op);
        }
    }

    pso_desc.NumRenderTargets = @intCast(desc.output_merger.attachments.len);
    for (desc.output_merger.attachments, pso_desc.RTVFormats[0..desc.output_merger.attachments.len]) |color, *format| {
        format.* = conv.formatTo(color.format);
    }

    const hr_create_pso = instance.device.CreateGraphicsPipelineState(
        &pso_desc,
        &d3d12.IID_IPipelineState,
        @ptrCast(&pipeline_ptr.pipeline),
    );
    if (hr_create_pso != windows.S_OK) {
        log.err("CreateGraphicsPipelineState failed: {}", .{hr_create_pso});
        return error.D3D12InternalError;
    }

    return @ptrCast(pipeline_ptr);
}

pub fn initComputePipeline(
    allocator: std.mem.Allocator,
    desc: gpu.ComputePipelineDesc,
) gpu.Error!*gpu.Pipeline {
    const instance = try getInstance();

    const pipeline_layout_ptr: *D3DPipelineLayout = @ptrCast(@alignCast(desc.layout));

    const pipeline_ptr = try allocator.create(D3DPipeline);
    pipeline_ptr.allocator = allocator;
    pipeline_ptr.layout = pipeline_layout_ptr;
    pipeline_ptr.desc = .{ .compute = desc };

    var pso_desc: d3d12.COMPUTE_PIPELINE_STATE_DESC = .{
        .pRootSignature = pipeline_layout_ptr.d3d_root_signature,
        .NodeMask = 0,
        .Flags = d3d12.PIPELINE_STATE_FLAG_NONE,
    };

    var it = desc.shaders.iterator();
    while (it.next(.{ .target = .dxil, .stage = .compute })) |shader| {
        pso_desc.CS = .init(shader.bytecode);
    }

    const hr_create_pso = instance.device.CreateComputePipelineState(
        &pso_desc,
        &d3d12.IID_IPipelineState,
        @ptrCast(&pipeline_ptr.pipeline),
    );
    if (hr_create_pso != windows.S_OK) {
        log.err("CreateComputePipelineState failed: {}", .{hr_create_pso});
        return error.D3D12InternalError;
    }

    return @ptrCast(pipeline_ptr);
}

pub fn deinitPipeline(pipeline: *gpu.Pipeline) void {
    const pipeline_ptr: *D3DPipeline = @ptrCast(@alignCast(pipeline));

    fullyRelease(pipeline_ptr.pipeline);

    pipeline_ptr.allocator.destroy(pipeline_ptr);
}

const D3DSwapchain = struct {
    allocator: std.mem.Allocator,

    d3d_swapchain: *dxgi.ISwapChain3,
    d3d_queue: *d3d12.ICommandQueue,
    create_flags: dxgi.SWAP_CHAIN_FLAG,
    desc: gpu.SwapchainDesc,
    sync_interval: u32,
    present_flags: dxgi.PRESENT_FLAG,
    textures: [gpu.MAX_SWAPCHAIN_IMAGES]?D3DTexture,
};
pub fn initSwapchain(allocator: std.mem.Allocator, desc: gpu.SwapchainDesc) gpu.Error!*gpu.Swapchain {
    const instance = try getInstance();

    const queue_ptr: *D3DCommandQueue = @ptrCast(@alignCast(desc.queue));

    if (desc.texture_num == 0) return error.SwapchainTooFewImages;
    if (desc.texture_num > gpu.MAX_SWAPCHAIN_IMAGES) return error.SwapchainTooManyImages;

    const swapchain_ptr = try allocator.create(D3DSwapchain);
    swapchain_ptr.allocator = allocator;
    swapchain_ptr.desc = desc;

    var tearing_support_winbool: windows.BOOL = 0;
    const hr_checktearing = instance.factory.CheckFeatureSupport(
        .PRESENT_ALLOW_TEARING,
        @ptrCast(&tearing_support_winbool),
        @sizeOf(windows.BOOL),
    );
    if (hr_checktearing != windows.S_OK) {
        tearing_support_winbool = 0;
    }
    const tearing_support = tearing_support_winbool != 0;

    const swapchain_desc: dxgi.SWAP_CHAIN_DESC1 = .{
        .Width = desc.size.x,
        .Height = desc.size.y,
        .Format = conv.formatTo(desc.format),
        .Stereo = windows.FALSE,
        .SampleDesc = .{
            .Count = 1,
            .Quality = 0,
        },
        .BufferUsage = .{ .RENDER_TARGET_OUTPUT = true },
        .BufferCount = desc.texture_num,
        .Scaling = .NONE,
        .SwapEffect = .FLIP_DISCARD,
        .AlphaMode = .IGNORE,
        .Flags = .{
            .ALLOW_TEARING = tearing_support,
        },
    };
    swapchain_ptr.sync_interval = if (desc.immediate) 0 else 1;
    swapchain_ptr.present_flags = .{
        .ALLOW_TEARING = desc.immediate and tearing_support,
    };
    swapchain_ptr.create_flags = swapchain_desc.Flags;

    for (&swapchain_ptr.textures) |*tex| {
        tex.* = null;
    }

    const create_swapchain_for_hwnd_ptr: *const fn (
        this: *dxgi.IFactory5,
        queue: *windows.IUnknown,
        hwnd: std.os.windows.HWND,
        desc: *const dxgi.SWAP_CHAIN_DESC1,
        fullscreen_desc: ?*dxgi.SWAP_CHAIN_FULLSCREEN_DESC,
        output: ?*dxgi.IOutput,
        swapchain: *?*dxgi.ISwapChain1,
    ) callconv(.c) windows.HRESULT = @ptrCast(instance.factory.__v.base.base.base.CreateSwapChainForHwnd);

    const window_props = sdl.c.SDL_GetWindowProperties(desc.window.impl);
    const hwnd: windows.HWND = @ptrCast(sdl.c.SDL_GetPointerProperty(
        window_props,
        sdl.c.SDL_PROP_WINDOW_WIN32_HWND_POINTER,
        null,
    ).?);

    const hr_createswapchain = create_swapchain_for_hwnd_ptr(
        instance.factory,
        @ptrCast(queue_ptr.d3d_queue),
        hwnd,
        &swapchain_desc,
        null,
        null,
        @ptrCast(&swapchain_ptr.d3d_swapchain),
    );
    if (hr_createswapchain != windows.S_OK) {
        log.err("CreateSwapChainForHwnd failed: {}", .{hr_createswapchain});
        return error.D3D12InternalError;
    }

    setDebugName(@ptrCast(swapchain_ptr.d3d_swapchain), desc.name);

    try acquireSwapchainTextures(@ptrCast(swapchain_ptr));

    return @ptrCast(swapchain_ptr);
}

pub fn deinitSwapchain(swapchain: *gpu.Swapchain) void {
    const swapchain_ptr: *D3DSwapchain = @ptrCast(@alignCast(swapchain));

    releaseSwapchainTextures(swapchain);
    fullyRelease(swapchain_ptr.d3d_swapchain);
    swapchain_ptr.allocator.destroy(swapchain_ptr);
}

pub fn resizeSwapchain(swapchain: *gpu.Swapchain, size: gpu.Vec2u) gpu.Error!void {
    const swapchain_ptr: *D3DSwapchain = @ptrCast(@alignCast(swapchain));

    releaseSwapchainTextures(swapchain);

    const hr_resizeswapchain = swapchain_ptr.d3d_swapchain.ResizeBuffers(
        swapchain_ptr.desc.texture_num,
        size.x,
        size.y,
        conv.formatTo(swapchain_ptr.desc.format),
        swapchain_ptr.create_flags,
    );
    if (hr_resizeswapchain != windows.S_OK) {
        log.err("ResizeBuffers failed: {}", .{hr_resizeswapchain});
        return error.D3D12InternalError;
    }
    swapchain_ptr.desc.size = size;

    try acquireSwapchainTextures(swapchain);
}

pub fn acquireNextSwapchainTexture(swapchain: *gpu.Swapchain) !u32 {
    const swapchain_ptr: *D3DSwapchain = @ptrCast(@alignCast(swapchain));

    const texture_idx = swapchain_ptr.d3d_swapchain.GetCurrentBackBufferIndex();
    return texture_idx;
}

/// memory is owned by the swapchain
///
/// do not store result
pub fn getSwapchainTexture(swapchain: *gpu.Swapchain, index: usize) !?*gpu.Texture {
    const swapchain_ptr: *D3DSwapchain = @ptrCast(@alignCast(swapchain));
    if (index >= swapchain_ptr.desc.texture_num) {
        return null;
    }
    return @ptrCast(&swapchain_ptr.textures[index].?);
}

pub fn presentSwapchain(swapchain: *gpu.Swapchain) gpu.Error!void {
    const swapchain_ptr: *D3DSwapchain = @ptrCast(@alignCast(swapchain));

    const hr_present = swapchain_ptr.d3d_swapchain.Present(swapchain_ptr.sync_interval, swapchain_ptr.present_flags);
    if (hr_present != windows.S_OK) {
        return error.D3D12InternalError;
    }
}

fn acquireSwapchainTextures(swapchain: *gpu.Swapchain) !void {
    const swapchain_ptr: *D3DSwapchain = @ptrCast(@alignCast(swapchain));

    for (&swapchain_ptr.textures, 0..) |*tex, texture_index| {
        if (texture_index >= swapchain_ptr.desc.texture_num) {
            tex.* = null;
            continue;
        }

        var resource: ?*d3d12.IResource = null;
        const hr_getbuffer = swapchain_ptr.d3d_swapchain.GetBuffer(
            @intCast(texture_index),
            &d3d12.IID_IResource,
            @ptrCast(&resource),
        );
        if (hr_getbuffer != windows.S_OK) {
            return error.D3D12InternalError;
        }
        _ = resource.?.AddRef();

        tex.* = .{
            .d3d_texture = resource.?,
            .allocation = null,
            .state = .{},
            .desc = textureDescFromResource(resource.?),
        };
    }

    return;
}

fn releaseSwapchainTextures(swapchain: *gpu.Swapchain) void {
    const swapchain_ptr: *D3DSwapchain = @ptrCast(@alignCast(swapchain));

    for (&swapchain_ptr.textures) |*tex| {
        if (tex.*) |*tex_ptr| {
            deinitTexture(@ptrCast(tex_ptr));
        }
        tex.* = null;
    }
}

fn setDebugName(object: *d3d12.IObject, name: []const u8) void {
    if (@import("builtin").mode != .Debug) {
        return;
    }
    var buf: [256]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buf);

    const wide_name = std.unicode.utf8ToUtf16LeAllocZ(fba.allocator(), name) catch return;
    _ = object.SetName(wide_name.ptr);
}

const conv = struct {
    fn formatTo(format: gpu.Format) dxgi.FORMAT {
        return switch (format) {
            .unknown => .UNKNOWN,
            .R8 => .R8_UNORM,
            .RG8 => .R8G8_UNORM,
            .D32 => .D32_FLOAT,
            .D24S8 => .D24_UNORM_S8_UINT,
            .RGBA8 => .R8G8B8A8_UNORM,
            .RGBA16 => .R16G16B16A16_UNORM,
            .RGBA16F => .R16G16B16A16_FLOAT,
            .RGBA32F => .R32G32B32A32_FLOAT,
            .BGRA8 => .B8G8R8A8_UNORM,
            .R16F => .R16_FLOAT,
            .R16 => .R16_UNORM,
            .R32F => .R32_FLOAT,
            .R32UI => .R32_UINT,
            .RG32F => .R32G32_FLOAT,
            .SRGB => .R8G8B8A8_UNORM_SRGB,
            .SRGBA => .R8G8B8A8_UNORM_SRGB,
            .BC1 => .BC1_UNORM,
            .BC2 => .BC2_UNORM,
            .BC3 => .BC3_UNORM,
            .BC4 => .BC4_UNORM,
            .BC5 => .BC5_UNORM,
            .R11G11B10F => .R11G11B10_FLOAT,
            .RGB32F => .R32G32B32_FLOAT,
            .RG16 => .R16G16_UNORM,
            .RG16F => .R16G16_FLOAT,
        };
    }

    fn formatToTypeless(format: gpu.Format) dxgi.FORMAT {
        return switch (format) {
            .D32, .D24S8 => .R32_TYPELESS,
            else => conv.formatTo(format),
        };
    }

    fn formatFrom(format: dxgi.FORMAT) gpu.Format {
        return switch (format) {
            .UNKNOWN => .unknown,
            .R8_UNORM => .R8,
            .R8G8_UNORM => .RG8,
            .D32_FLOAT => .D32,
            .D24_UNORM_S8_UINT => .D24S8,
            .R8G8B8A8_UNORM => .RGBA8,
            .R16G16B16A16_UNORM => .RGBA16,
            .R16G16B16A16_FLOAT => .RGBA16F,
            .R32G32B32A32_FLOAT => .RGBA32F,
            .B8G8R8A8_UNORM => .BGRA8,
            .R16_FLOAT => .R16F,
            .R16_UNORM => .R16,
            .R32_FLOAT => .R32F,
            .R32_UINT => .R32UI,
            .R32G32_FLOAT => .RG32F,
            .R8G8B8A8_UNORM_SRGB => .SRGBA,
            .BC1_UNORM => .BC1,
            .BC2_UNORM => .BC2,
            .BC3_UNORM => .BC3,
            .BC4_UNORM => .BC4,
            .BC5_UNORM => .BC5,
            .R11G11B10_FLOAT => .R11G11B10F,
            .R32G32B32_FLOAT => .RGB32F,
            .R16G16_UNORM => .RG16,
            .R16G16_FLOAT => .RG16F,
            else => .unknown,
        };
    }

    fn addressModeTo(mode: gpu.AddressMode) d3d12.TEXTURE_ADDRESS_MODE {
        return switch (mode) {
            .repeat => .WRAP,
            .mirror => .MIRROR,
            .clamp => .CLAMP,
            .border => .BORDER,
            .mirror_once => .MIRROR_ONCE,
        };
    }

    fn textureStateTo(state: gpu.TextureState) d3d12.RESOURCE_STATES {
        switch (state) {
            .undefined => return .COMMON,
            .present => return .PRESENT,
            .render_target => return .{
                .RENDER_TARGET = true,
            },
            .depth_stencil_write => return .{
                .DEPTH_WRITE = true,
            },
            .depth_stencil_read => return .{
                .DEPTH_READ = true,
            },
            .shader_resource => return .{
                .NON_PIXEL_SHADER_RESOURCE = true,
                .PIXEL_SHADER_RESOURCE = true,
            },
            .unordered_access => return .{
                .UNORDERED_ACCESS = true,
            },
            .copy_source => return .{
                .COPY_SOURCE = true,
            },
            .copy_dest => return .{
                .COPY_DEST = true,
            },
            .resolve_source => return .{
                .RESOLVE_SOURCE = true,
            },
            .resolve_dest => return .{
                .RESOLVE_DEST = true,
            },
        }
    }

    fn bufferStateTo(state: gpu.BufferState) d3d12.RESOURCE_STATES {
        switch (state) {
            .undefined => return .COMMON,
            .copy_dest => return .{ .COPY_DEST = true },
            .copy_source => return .{ .COPY_SOURCE = true },
            .index => return .{ .INDEX_BUFFER = true },
            .vertex => return .{ .VERTEX_AND_CONSTANT_BUFFER = true },
            .constant => return .{ .VERTEX_AND_CONSTANT_BUFFER = true },
            .indirect => return .{ .INDIRECT_ARGUMENT_OR_PREDICATION = true },
            .shader_resource => return .{
                .NON_PIXEL_SHADER_RESOURCE = true,
                .PIXEL_SHADER_RESOURCE = true,
            },
            .unordered_access => return .{
                .UNORDERED_ACCESS = true,
            },
        }
    }

    fn logicOpTo(op: gpu.LogicOp) d3d12.LOGIC_OP {
        return switch (op) {
            .clear => .CLEAR,
            .@"and" => .AND,
            .and_reverse => .AND_REVERSE,
            .copy => .COPY,
            .copy_inverted => .COPY_INVERTED,
            .and_inverted => .AND_INVERTED,
            .xor => .XOR,
            .@"or" => .OR,
            .nor => .NOR,
            .equivalent => .EQUIV,
            .invert => .INVERT,
            .or_reverse => .OR_REVERSE,
            .or_inverted => .OR_INVERTED,
            .nand => .NAND,
            .set => .SET,
            .none => unreachable,
        };
    }

    fn compareOpTo(op: gpu.CompareOp) d3d12.COMPARISON_FUNC {
        return switch (op) {
            .none => .NEVER,
            .always => .ALWAYS,
            .never => .NEVER,
            .equal => .EQUAL,
            .not_equal => .NOT_EQUAL,
            .less => .LESS,
            .less_equal => .LESS_EQUAL,
            .greater => .GREATER,
            .greater_equal => .GREATER_EQUAL,
        };
    }

    fn stencilOpTo(op: gpu.StencilOp) d3d12.STENCIL_OP {
        return switch (op) {
            .keep => .KEEP,
            .zero => .ZERO,
            .replace => .REPLACE,
            .increment_clamp => .INCR_SAT,
            .decrement_clamp => .DECR_SAT,
            .invert => .INVERT,
            .increment_wrap => .INCR,
            .decrement_wrap => .DECR,
        };
    }

    fn blendFactorTo(factor: gpu.BlendFactor) d3d12.BLEND {
        return switch (factor) {
            .zero => .ZERO,
            .one => .ONE,
            .src_color => .SRC_COLOR,
            .one_minus_src_color => .INV_SRC_COLOR,
            .src_alpha => .SRC_ALPHA,
            .one_minus_src_alpha => .INV_SRC_ALPHA,
            .dst_color => .DEST_COLOR,
            .one_minus_dst_color => .INV_DEST_COLOR,
            .dst_alpha => .DEST_ALPHA,
            .one_minus_dst_alpha => .INV_DEST_ALPHA,
            .constant_color => .BLEND_FACTOR,
            .one_minus_constant_color => .INV_BLEND_FACTOR,
            .src_alpha_saturate => .SRC_ALPHA_SAT,
            .src1_color => .SRC1_COLOR,
            .one_minus_src1_color => .INV_SRC1_COLOR,
            .src1_alpha => .SRC1_ALPHA,
            .one_minus_src1_alpha => .INV_SRC1_ALPHA,
            .constant_alpha => .BLEND_FACTOR,
            .one_minus_constant_alpha => .INV_BLEND_FACTOR,
        };
    }

    fn blendOpTo(op: gpu.BlendOp) d3d12.BLEND_OP {
        return switch (op) {
            .add => .ADD,
            .subtract => .SUBTRACT,
            .reverse_subtract => .REV_SUBTRACT,
            .min => .MIN,
            .max => .MAX,
        };
    }
};

fn getTextureSubResourceIndex(
    desc: gpu.TextureDesc,
    layer_offset: u32,
    mip_offset: u32,
    plane_flags: gpu.PlaneFlags,
) u32 {
    var plane_index: u32 = 0;
    const is_all_planes = plane_flags.color and plane_flags.depth and plane_flags.stencil;
    if (!is_all_planes) {
        // Ensure at least one plane is specified
        if (!plane_flags.depth and !plane_flags.stencil) {
            @panic("Invalid plane flags: at least depth or stencil must be set");
        }
        // For depth/stencil formats, color flag should not be set individually
        if (plane_flags.color and (plane_flags.depth or plane_flags.stencil)) {
            @panic("Invalid plane flags: color cannot be combined with depth/stencil individually");
        }
        if (plane_flags.depth) {
            plane_index = 0;
        } else if (plane_flags.stencil) {
            plane_index = 1;
        }
    }
    return mip_offset + (layer_offset + plane_index * desc.layer_num) * desc.mip_num;
}

fn fullyRelease(maybe_opt_c: anytype) void {
    if (@typeInfo(@TypeOf(maybe_opt_c)) == .optional) {
        const c = maybe_opt_c.?;

        var ref_count: u32 = c.AddRef();
        while (ref_count > 0) {
            ref_count = c.Release();
        }
    } else {
        const c = maybe_opt_c;
        var ref_count: u32 = c.AddRef();
        while (ref_count > 0) {
            ref_count = c.Release();
        }
    }
}

const log = std.log.scoped(.@"gpu d3d12");

const d3d12ma = @import("d3d12ma.zig");

const zwindows = @import("zwindows");
const d3d12d = zwindows.d3d12d;
const d3d12 = zwindows.d3d12;
const d3d = zwindows.d3d;
const dxgi = zwindows.dxgi;
const windows = zwindows.windows;

const gpu = @import("../gpu.zig");
const std = @import("std");

const sdl = @import("../sdl.zig");

const OffsetAllocator = @import("OffsetAllocator.zig");
const Allocation = OffsetAllocator.Allocation;
