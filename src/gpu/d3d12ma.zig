pub const struct_Pool = opaque {};
pub const Pool = struct_Pool;
pub const AllocHandle = u64;
pub const _AllocateFunctionType = ?*const fn (usize, usize, ?*anyopaque) callconv(.c) ?*anyopaque;
pub const _FreeFunctionType = ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) void;
pub const struct__ALLOCATION_CALLBACKS = extern struct {
    pAllocate: [*c]_AllocateFunctionType = @import("std").mem.zeroes([*c]_AllocateFunctionType),
    pFree: [*c]_FreeFunctionType = @import("std").mem.zeroes([*c]_FreeFunctionType),
    pPrivateData: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
};
pub const _ALLOCATION_CALLBACKS = struct__ALLOCATION_CALLBACKS;
pub const _ALLOCATION_FLAG_NONE: c_int = 0;
pub const _ALLOCATION_FLAG_COMMITTED: c_int = 1;
pub const _ALLOCATION_FLAG_NEVER_ALLOCATE: c_int = 2;
pub const _ALLOCATION_FLAG_WITHIN_BUDGET: c_int = 4;
pub const _ALLOCATION_FLAG_UPPER_ADDRESS: c_int = 8;
pub const _ALLOCATION_FLAG_CAN_ALIAS: c_int = 16;
pub const _ALLOCATION_FLAG_STRATEGY_MIN_MEMORY: c_int = 65536;
pub const _ALLOCATION_FLAG_STRATEGY_MIN_TIME: c_int = 131072;
pub const _ALLOCATION_FLAG_STRATEGY_MIN_OFFSET: c_int = 262144;
pub const _ALLOCATION_FLAG_STRATEGY_BEST_FIT: c_int = 65536;
pub const _ALLOCATION_FLAG_STRATEGY_FIRST_FIT: c_int = 131072;
pub const _ALLOCATION_FLAG_STRATEGY_MASK: c_int = 458752;
pub const enum__ALLOCATION_FLAGS = c_uint;
pub const _ALLOCATION_FLAGS = enum__ALLOCATION_FLAGS;
pub const ALLOCATION_DESC = extern struct {
    Flags: _ALLOCATION_FLAGS = @import("std").mem.zeroes(_ALLOCATION_FLAGS),
    HeapType: d3d12.HEAP_TYPE = .DEFAULT,
    ExtraHeapFlags: d3d12.HEAP_FLAGS = @import("std").mem.zeroes(d3d12.HEAP_FLAGS),
    CustomPool: ?*Pool = @import("std").mem.zeroes(?*Pool),
    pPrivateData: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
};
pub const struct_Statistics = extern struct {
    BlockCount: u32 = @import("std").mem.zeroes(u32),
    AllocationCount: u32 = @import("std").mem.zeroes(u32),
    BlockBytes: u64 = @import("std").mem.zeroes(u64),
    AllocationBytes: u64 = @import("std").mem.zeroes(u64),
};
pub const Statistics = struct_Statistics;
pub const struct_DetailedStatistics = extern struct {
    Stats: Statistics = @import("std").mem.zeroes(Statistics),
    UnusedRangeCount: u32 = @import("std").mem.zeroes(u32),
    AllocationSizeMin: u64 = @import("std").mem.zeroes(u64),
    AllocationSizeMax: u64 = @import("std").mem.zeroes(u64),
    UnusedRangeSizeMin: u64 = @import("std").mem.zeroes(u64),
    UnusedRangeSizeMax: u64 = @import("std").mem.zeroes(u64),
};
pub const DetailedStatistics = struct_DetailedStatistics;
pub const struct_TotalStatistics = extern struct {
    HeapType: [5]DetailedStatistics = @import("std").mem.zeroes([5]DetailedStatistics),
    MemorySegmentGroup: [2]DetailedStatistics = @import("std").mem.zeroes([2]DetailedStatistics),
    Total: DetailedStatistics = @import("std").mem.zeroes(DetailedStatistics),
};
pub const TotalStatistics = struct_TotalStatistics;
pub const struct_Budget = extern struct {
    Stats: Statistics = @import("std").mem.zeroes(Statistics),
    UsageBytes: u64 = @import("std").mem.zeroes(u64),
    BudgetBytes: u64 = @import("std").mem.zeroes(u64),
};
pub const Budget = struct_Budget;
pub const struct_VirtualAllocation = extern struct {
    AllocHandle: AllocHandle = @import("std").mem.zeroes(AllocHandle),
};
pub const VirtualAllocation = struct_VirtualAllocation;
pub const _DEFRAGMENTATION_FLAG_ALGORITHM_FAST: c_int = 1;
pub const _DEFRAGMENTATION_FLAG_ALGORITHM_BALANCED: c_int = 2;
pub const _DEFRAGMENTATION_FLAG_ALGORITHM_FULL: c_int = 4;
pub const DEFRAGMENTATION_FLAG_ALGORITHM_MASK: c_int = 7;
pub const enum__DEFRAGMENTATION_FLAGS = c_uint;
pub const _DEFRAGMENTATION_FLAGS = enum__DEFRAGMENTATION_FLAGS;
pub const struct__DEFRAGMENTATION_DESC = extern struct {
    Flags: _DEFRAGMENTATION_FLAGS = @import("std").mem.zeroes(_DEFRAGMENTATION_FLAGS),
    MaxBytesPerPass: u64 = @import("std").mem.zeroes(u64),
    MaxAllocationsPerPass: u3232 = @import("std").mem.zeroes(u3232),
};
pub const _DEFRAGMENTATION_DESC = struct__DEFRAGMENTATION_DESC;
pub const _DEFRAGMENTATION_MOVE_OPERATION_COPY: c_int = 0;
pub const _DEFRAGMENTATION_MOVE_OPERATION_IGNORE: c_int = 1;
pub const _DEFRAGMENTATION_MOVE_OPERATION_DESTROY: c_int = 2;
pub const enum__DEFRAGMENTATION_MOVE_OPERATION = c_uint;
pub const _DEFRAGMENTATION_MOVE_OPERATION = enum__DEFRAGMENTATION_MOVE_OPERATION;
pub const struct__DEFRAGMENTATION_MOVE = extern struct {
    Operation: _DEFRAGMENTATION_MOVE_OPERATION = @import("std").mem.zeroes(_DEFRAGMENTATION_MOVE_OPERATION),
    pSrcAllocation: ?*Allocation = @import("std").mem.zeroes(?*Allocation),
    pDstTmpAllocation: ?*Allocation = @import("std").mem.zeroes(?*Allocation),
};
pub const _DEFRAGMENTATION_MOVE = struct__DEFRAGMENTATION_MOVE;
pub const struct__DEFRAGMENTATION_PASS_MOVE_INFO = extern struct {
    MoveCount: u3232 = @import("std").mem.zeroes(u3232),
    pMoves: [*c]_DEFRAGMENTATION_MOVE = @import("std").mem.zeroes([*c]_DEFRAGMENTATION_MOVE),
};
pub const _DEFRAGMENTATION_PASS_MOVE_INFO = struct__DEFRAGMENTATION_PASS_MOVE_INFO;
pub const struct__DEFRAGMENTATION_STATS = extern struct {
    BytesMoved: u64 = @import("std").mem.zeroes(u64),
    BytesFreed: u64 = @import("std").mem.zeroes(u64),
    AllocationsMoved: u3232 = @import("std").mem.zeroes(u3232),
    HeapsFreed: u3232 = @import("std").mem.zeroes(u3232),
};
pub const _DEFRAGMENTATION_STATS = struct__DEFRAGMENTATION_STATS;
pub const struct_DefragmentationContext = opaque {};
pub const DefragmentationContext = struct_DefragmentationContext;
pub const _POOL_FLAG_NONE: c_int = 0;
pub const _POOL_FLAG_ALGORITHM_LINEAR: c_int = 1;
pub const _POOL_FLAG_MSAA_TEXTURES_ALWAYS_COMMITTED: c_int = 2;
pub const _POOL_FLAG_ALGORITHM_MASK: c_int = 1;
pub const enum__POOL_FLAGS = c_uint;
pub const _POOL_FLAGS = enum__POOL_FLAGS;
pub const struct__POOL_DESC = extern struct {
    Flags: _POOL_FLAGS = @import("std").mem.zeroes(_POOL_FLAGS),
    HeapProperties: d3d12.HEAP_PROPERTIES = @import("std").mem.zeroes(d3d12.HEAP_PROPERTIES),
    HeapFlags: d3d12.HEAP_FLAGS = @import("std").mem.zeroes(d3d12.HEAP_FLAGS),
    BlockSize: u64 = @import("std").mem.zeroes(u64),
    MinBlockCount: u32 = @import("std").mem.zeroes(u32),
    MaxBlockCount: u32 = @import("std").mem.zeroes(u32),
    MinAllocationAlignment: u64 = @import("std").mem.zeroes(u64),
    pProtectedSession: [*c]d3d12.IProtectedResourceSession = @import("std").mem.zeroes([*c]d3d12.IProtectedResourceSession),
    ResidencyPriority: d3d12.RESIDENCY_PRIORITY = @import("std").mem.zeroes(d3d12.RESIDENCY_PRIORITY),
};
pub const _POOL_DESC = struct__POOL_DESC;
pub const _ALLOCATOR_FLAG_NONE: c_int = 0;
pub const _ALLOCATOR_FLAG_SINGLETHREADED: c_int = 1;
pub const _ALLOCATOR_FLAG_ALWAYS_COMMITTED: c_int = 2;
pub const _ALLOCATOR_FLAG_DEFAULT_POOLS_NOT_ZEROED: c_int = 4;
pub const _ALLOCATOR_FLAG_MSAA_TEXTURES_ALWAYS_COMMITTED: c_int = 8;
pub const _ALLOCATOR_FLAG_DONT_PREFER_SMALL_BUFFERS_COMMITTED: c_int = 16;
pub const enum__ALLOCATOR_FLAGS = c_uint;
pub const _ALLOCATOR_FLAGS = enum__ALLOCATOR_FLAGS;
pub const ALLOCATOR_DESC = extern struct {
    Flags: _ALLOCATOR_FLAGS = @import("std").mem.zeroes(_ALLOCATOR_FLAGS),
    pDevice: [*c]d3d12.IDevice = @import("std").mem.zeroes([*c]d3d12.IDevice),
    PreferredBlockSize: u64 = @import("std").mem.zeroes(u64),
    pAllocationCallbacks: [*c]const _ALLOCATION_CALLBACKS = @import("std").mem.zeroes([*c]const _ALLOCATION_CALLBACKS),
    pAdapter: [*c]dxgi.IAdapter = @import("std").mem.zeroes([*c]dxgi.IAdapter),
};
pub const _VIRTUAL_BLOCK_FLAG_NONE: c_int = 0;
pub const _VIRTUAL_BLOCK_FLAG_ALGORITHM_LINEAR: c_int = 1;
pub const _VIRTUAL_BLOCK_FLAG_ALGORITHM_MASK: c_int = 1;
pub const enum__VIRTUAL_BLOCK_FLAGS = c_uint;
pub const _VIRTUAL_BLOCK_FLAGS = enum__VIRTUAL_BLOCK_FLAGS;
pub const struct__VIRTUAL_BLOCK_DESC = extern struct {
    Flags: _VIRTUAL_BLOCK_FLAGS = @import("std").mem.zeroes(_VIRTUAL_BLOCK_FLAGS),
    Size: u64 = @import("std").mem.zeroes(u64),
    pAllocationCallbacks: [*c]const _ALLOCATION_CALLBACKS = @import("std").mem.zeroes([*c]const _ALLOCATION_CALLBACKS),
};
pub const _VIRTUAL_BLOCK_DESC = struct__VIRTUAL_BLOCK_DESC;
pub const _VIRTUAL_ALLOCATION_FLAG_NONE: c_int = 0;
pub const _VIRTUAL_ALLOCATION_FLAG_UPPER_ADDRESS: c_int = 8;
pub const _VIRTUAL_ALLOCATION_FLAG_STRATEGY_MIN_MEMORY: c_int = 65536;
pub const _VIRTUAL_ALLOCATION_FLAG_STRATEGY_MIN_TIME: c_int = 131072;
pub const _VIRTUAL_ALLOCATION_FLAG_STRATEGY_MIN_OFFSET: c_int = 262144;
pub const _VIRTUAL_ALLOCATION_FLAG_STRATEGY_MASK: c_int = 458752;
pub const enum__VIRTUAL_ALLOCATION_FLAGS = c_uint;
pub const _VIRTUAL_ALLOCATION_FLAGS = enum__VIRTUAL_ALLOCATION_FLAGS;
pub const struct__VIRTUAL_ALLOCATION_DESC = extern struct {
    Flags: _VIRTUAL_ALLOCATION_FLAGS = @import("std").mem.zeroes(_VIRTUAL_ALLOCATION_FLAGS),
    Size: u64 = @import("std").mem.zeroes(u64),
    Alignment: u64 = @import("std").mem.zeroes(u64),
    pPrivateData: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
};
pub const _VIRTUAL_ALLOCATION_DESC = struct__VIRTUAL_ALLOCATION_DESC;
pub const struct__VIRTUAL_ALLOCATION_INFO = extern struct {
    Offset: u64 = @import("std").mem.zeroes(u64),
    Size: u64 = @import("std").mem.zeroes(u64),
    pPrivateData: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
};
pub const _VIRTUAL_ALLOCATION_INFO = struct__VIRTUAL_ALLOCATION_INFO;
pub const struct_VirtualBlock = opaque {};
pub const VirtualBlock = struct_VirtualBlock;
extern fn D3D12MAAllocation_GetOffset(pSelf: ?*anyopaque) u64;
extern fn D3D12MAAllocation_GetAlignment(pSelf: ?*anyopaque) u64;
extern fn D3D12MAAllocation_GetSize(pSelf: ?*anyopaque) u64;
extern fn D3D12MAAllocation_GetResource(pSelf: ?*anyopaque) [*c]d3d12.IResource;
extern fn D3D12MAAllocation_SetResource(pSelf: ?*anyopaque, pResource: [*c]d3d12.IResource) void;
extern fn D3D12MAAllocation_GetHeap(pSelf: ?*anyopaque) [*c]d3d12.IHeap;
extern fn D3D12MAAllocation_SetPrivateData(pSelf: ?*anyopaque, pPrivateData: ?*anyopaque) void;
extern fn D3D12MAAllocation_GetPrivateData(pSelf: ?*anyopaque) ?*anyopaque;
extern fn D3D12MAAllocation_SetName(pSelf: ?*anyopaque, Name: windows.LPCWSTR) void;
extern fn D3D12MAAllocation_GetName(pSelf: ?*anyopaque) windows.LPCWSTR;
extern fn D3D12MADefragmentationContext_BeginPass(pSelf: ?*anyopaque, pPassInfo: [*c]_DEFRAGMENTATION_PASS_MOVE_INFO) windows.HRESULT;
extern fn D3D12MADefragmentationContext_EndPass(pSelf: ?*anyopaque, pPassInfo: [*c]_DEFRAGMENTATION_PASS_MOVE_INFO) windows.HRESULT;
extern fn D3D12MADefragmentationContext_GetStats(pSelf: ?*anyopaque, pStats: [*c]_DEFRAGMENTATION_STATS) void;
extern fn D3D12MAPool_GetDesc(pSelf: ?*anyopaque) _POOL_DESC;
extern fn D3D12MAPool_GetStatistics(pSelf: ?*anyopaque, pStats: [*c]Statistics) void;
extern fn D3D12MAPool_CalculateStatistics(pSelf: ?*anyopaque, pStats: [*c]DetailedStatistics) void;
extern fn D3D12MAPool_SetName(pSelf: ?*anyopaque, Name: windows.LPCWSTR) void;
extern fn D3D12MAPool_GetName(pSelf: ?*anyopaque) windows.LPCWSTR;
extern fn D3D12MAPool_BeginDefragmentation(pSelf: ?*anyopaque, pDesc: [*c]const _DEFRAGMENTATION_DESC, ppContext: [*c]?*DefragmentationContext) windows.HRESULT;

pub const Allocator = opaque {
    pub inline fn Create(pDesc: *const ALLOCATOR_DESC, ppAllocator: *?*Allocator) windows.HRESULT {
        return D3D12MACreateAllocator(pDesc, ppAllocator);
    }

    pub inline fn Release(self: *Allocator) void {
        _ = D3D12MAAllocator_Release(self);
    }

    pub inline fn CreateResource(
        self: *Allocator,
        pAllocDesc: *const ALLOCATION_DESC,
        pResourceDesc: *const d3d12.RESOURCE_DESC,
        InitialResourceState: d3d12.RESOURCE_STATES,
        pOptimizedClearValue: ?*const d3d12.CLEAR_VALUE,
        ppAllocation: *?*Allocation,
        riidResource: *const windows.GUID,
        ppvResource: *?*anyopaque,
    ) windows.HRESULT {
        return D3D12MAAllocator_CreateResource(
            self,
            pAllocDesc,
            pResourceDesc,
            InitialResourceState,
            pOptimizedClearValue,
            ppAllocation,
            riidResource,
            ppvResource,
        );
    }

    extern fn D3D12MAAllocator_GetD3D12Options(pSelf: ?*anyopaque) [*c]const d3d12.FEATURE_DATA_D3D12_OPTIONS;
    extern fn D3D12MAAllocator_IsUMA(pSelf: ?*anyopaque) windows.BOOL;
    extern fn D3D12MAAllocator_IsCacheCoherentUMA(pSelf: ?*anyopaque) windows.BOOL;
    extern fn D3D12MAAllocator_IsGPUUploadHeapSupported(pSelf: ?*anyopaque) windows.BOOL;
    extern fn D3D12MAAllocator_GetMemoryCapacity(pSelf: ?*anyopaque, MemorySegmentGroup: u32) u64;
    extern fn D3D12MAAllocator_CreateResource(pSelf: ?*anyopaque, pAllocDesc: [*c]const ALLOCATION_DESC, pResourceDesc: [*c]const d3d12.RESOURCE_DESC, InitialResourceState: d3d12.RESOURCE_STATES, pOptimizedClearValue: [*c]const d3d12.CLEAR_VALUE, ppAllocation: [*c]?*Allocation, riidResource: [*c]const windows.GUID, ppvResource: [*c]?*anyopaque) windows.HRESULT;
    extern fn D3D12MAAllocator_CreateResource2(pSelf: ?*anyopaque, pAllocDesc: [*c]const ALLOCATION_DESC, pResourceDesc: [*c]const d3d12.RESOURCE_DESC1, InitialResourceState: d3d12.RESOURCE_STATES, pOptimizedClearValue: [*c]const d3d12.CLEAR_VALUE, ppAllocation: [*c]?*Allocation, riidResource: [*c]const windows.GUID, ppvResource: [*c]?*anyopaque) windows.HRESULT;
    extern fn D3D12MAAllocator_CreateResource3(pSelf: ?*anyopaque, pAllocDesc: [*c]const ALLOCATION_DESC, pResourceDesc: [*c]const d3d12.RESOURCE_DESC1, InitialLayout: d3d12.BARRIER_LAYOUT, pOptimizedClearValue: [*c]const d3d12.CLEAR_VALUE, NumCastableFormats: u3232, pCastableFormats: [*c]dxgi.FORMAT, ppAllocation: [*c]?*Allocation, riidResource: [*c]const windows.GUID, ppvResource: [*c]?*anyopaque) windows.HRESULT;
    extern fn D3D12MAAllocator_AllocateMemory(pSelf: ?*anyopaque, pAllocDesc: [*c]const ALLOCATION_DESC, pAllocInfo: [*c]const d3d12.RESOURCE_ALLOCATION_INFO, ppAllocation: [*c]?*Allocation) windows.HRESULT;
    extern fn D3D12MAAllocator_CreateAliasingResource(pSelf: ?*anyopaque, pAllocation: ?*Allocation, AllocationLocalOffset: u64, pResourceDesc: [*c]const d3d12.RESOURCE_DESC, InitialResourceState: d3d12.RESOURCE_STATES, pOptimizedClearValue: [*c]const d3d12.CLEAR_VALUE, riidResource: [*c]const windows.GUID, ppvResource: [*c]?*anyopaque) windows.HRESULT;
    extern fn D3D12MAAllocator_CreateAliasingResource1(pSelf: ?*anyopaque, pAllocation: ?*Allocation, AllocationLocalOffset: u64, pResourceDesc: [*c]const d3d12.RESOURCE_DESC1, InitialResourceState: d3d12.RESOURCE_STATES, pOptimizedClearValue: [*c]const d3d12.CLEAR_VALUE, riidResource: [*c]const windows.GUID, ppvResource: [*c]?*anyopaque) windows.HRESULT;
    extern fn D3D12MAAllocator_CreateAliasingResource2(pSelf: ?*anyopaque, pAllocation: ?*Allocation, AllocationLocalOffset: u64, pResourceDesc: [*c]const d3d12.RESOURCE_DESC1, InitialLayout: d3d12.BARRIER_LAYOUT, pOptimizedClearValue: [*c]const d3d12.CLEAR_VALUE, NumCastableFormats: u3232, pCastableFormats: [*c]dxgi.FORMAT, riidResource: [*c]const windows.GUID, ppvResource: [*c]?*anyopaque) windows.HRESULT;
    extern fn D3D12MAAllocator_CreatePool(pSelf: ?*anyopaque, pPoolDesc: [*c]const _POOL_DESC, ppPool: [*c]?*Pool) windows.HRESULT;
    extern fn D3D12MAAllocator_SetCurrentFrameIndex(pSelf: ?*anyopaque, FrameIndex: u32) void;
    extern fn D3D12MAAllocator_GetBudget(pSelf: ?*anyopaque, pLocalBudget: [*c]Budget, pNonLocalBudget: [*c]Budget) void;
    extern fn D3D12MAAllocator_CalculateStatistics(pSelf: ?*anyopaque, pStats: [*c]TotalStatistics) void;
    extern fn D3D12MAAllocator_BuildStatsString(pSelf: ?*anyopaque, ppStatsString: [*c][*c]windows.WCHAR, DetailedMap: windows.BOOL) void;
    extern fn D3D12MAAllocator_FreeStatsString(pSelf: ?*anyopaque, pStatsString: [*c]windows.WCHAR) void;
    extern fn D3D12MAAllocator_BeginDefragmentation(pSelf: ?*anyopaque, pDesc: [*c]const _DEFRAGMENTATION_DESC, ppContext: [*c]?*DefragmentationContext) void;
};
extern fn D3D12MAVirtualBlock_IsEmpty(pSelf: ?*anyopaque) windows.BOOL;
extern fn D3D12MAVirtualBlock_GetAllocationInfo(pSelf: ?*anyopaque, Allocation: VirtualAllocation, pInfo: [*c]_VIRTUAL_ALLOCATION_INFO) void;
extern fn D3D12MAVirtualBlock_Allocate(pSelf: ?*anyopaque, pDesc: [*c]const _VIRTUAL_ALLOCATION_DESC, pAllocation: [*c]VirtualAllocation, pOffset: [*c]u64) windows.HRESULT;
extern fn D3D12MAVirtualBlock_FreeAllocation(pSelf: ?*anyopaque, Allocation: VirtualAllocation) void;
extern fn D3D12MAVirtualBlock_Clear(pSelf: ?*anyopaque) void;
extern fn D3D12MAVirtualBlock_SetAllocationPrivateData(pSelf: ?*anyopaque, Allocation: VirtualAllocation, pPrivateData: ?*anyopaque) void;
extern fn D3D12MAVirtualBlock_GetStatistics(pSelf: ?*anyopaque, pStats: [*c]Statistics) void;
extern fn D3D12MAVirtualBlock_CalculateStatistics(pSelf: ?*anyopaque, pStats: [*c]DetailedStatistics) void;
extern fn D3D12MAVirtualBlock_BuildStatsString(pSelf: ?*anyopaque, ppStatsString: [*c][*c]windows.WCHAR) void;
extern fn D3D12MAVirtualBlock_FreeStatsString(pSelf: ?*anyopaque, pStatsString: [*c]windows.WCHAR) void;
extern fn D3D12MACreateAllocator(pDesc: [*c]const ALLOCATOR_DESC, ppAllocator: [*c]?*Allocator) windows.HRESULT;
extern fn D3D12MACreateVirtualBlock(pDesc: [*c]const _VIRTUAL_BLOCK_DESC, ppVirtualBlock: [*c]?*VirtualBlock) windows.HRESULT;
pub const Allocation = opaque {
    pub inline fn Release(self: *Allocation) void {
        _ = D3D12MAAllocation_Release(self);
    }
    extern fn D3D12MAAllocation_QueryInterface(pSelf: ?*anyopaque, riid: [*c]const windows.GUID, ppvObject: [*c]?*anyopaque) windows.HRESULT;
    extern fn D3D12MAAllocation_AddRef(pSelf: ?*anyopaque) windows.ULONG;
    extern fn D3D12MAAllocation_Release(pSelf: ?*anyopaque) windows.ULONG;
};
extern fn D3D12MADefragmentationContext_QueryInterface(pSelf: ?*anyopaque, riid: [*c]const windows.GUID, ppvObject: [*c]?*anyopaque) windows.HRESULT;
extern fn D3D12MADefragmentationContext_AddRef(pSelf: ?*anyopaque) windows.ULONG;
extern fn D3D12MADefragmentationContext_Release(pSelf: ?*anyopaque) windows.ULONG;
extern fn D3D12MAPool_QueryInterface(pSelf: ?*anyopaque, riid: [*c]const windows.GUID, ppvObject: [*c]?*anyopaque) windows.HRESULT;
extern fn D3D12MAPool_AddRef(pSelf: ?*anyopaque) windows.ULONG;
extern fn D3D12MAPool_Release(pSelf: ?*anyopaque) windows.ULONG;
extern fn D3D12MAAllocator_QueryInterface(pSelf: ?*anyopaque, riid: [*c]const windows.GUID, ppvObject: [*c]?*anyopaque) windows.HRESULT;
extern fn D3D12MAAllocator_AddRef(pSelf: ?*anyopaque) windows.ULONG;
extern fn D3D12MAAllocator_Release(pSelf: ?*anyopaque) windows.ULONG;
extern fn D3D12MAVirtualBlock_QueryInterface(pSelf: ?*anyopaque, riid: [*c]const windows.GUID, ppvObject: [*c]?*anyopaque) windows.HRESULT;
extern fn D3D12MAVirtualBlock_AddRef(pSelf: ?*anyopaque) windows.ULONG;
extern fn D3D12MAVirtualBlock_Release(pSelf: ?*anyopaque) windows.ULONG;

const zwindows = @import("zwindows");
const d3d12 = zwindows.d3d12;
const dxgi = zwindows.dxgi;
const windows = zwindows.windows;

const std = @import("std");
