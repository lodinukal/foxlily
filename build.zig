const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = .ReleaseFast,
        .preferred_link_mode = .dynamic,
        //.preferred_link_mode = .static, // or .dynamic
    });
    const sdl_lib = sdl_dep.artifact("SDL3");
    const sdl_dll_install_step = b.addInstallArtifact(sdl_lib, .{ .h_dir = .disabled });
    b.getInstallStep().dependOn(&sdl_dll_install_step.step);

    const zstbi_dep = b.dependency("zstbi", .{
        .target = target,
        .optimize = .ReleaseFast,
    });

    const tag = target.result.os.tag;
    const d3d12_option = b.option(bool, "d3d12", "enables d3d12 backend in gpu module") orelse
        (tag == .windows);
    const vulkan_option = b.option(bool, "vulkan", "enables vulkan backend in gpu module") orelse
        (tag == .linux or tag == .windows);
    const metal_option = b.option(bool, "metal", "enables metal backend in gpu module") orelse
        (tag == .macos);

    const use_main_callbacks = b.option(bool, "use_main_callbacks", "use SDL main callbacks") orelse
        false;

    const options = b.addOptions();
    options.addOption(bool, "gpu_d3d12", d3d12_option);
    options.addOption(bool, "gpu_vulkan", vulkan_option);
    options.addOption(bool, "gpu_metal", metal_option);
    options.addOption(bool, "use_main_callbacks", use_main_callbacks);

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zstbi", .module = zstbi_dep.module("root") },
        },
    });
    lib_mod.addOptions("config", options);
    lib_mod.linkLibrary(sdl_lib);

    if (d3d12_option) {
        const d3d12ma = b.lazyDependency("d3d12ma", .{}) orelse return;
        const d3d12ma_lib = b.addLibrary(.{
            .name = "d3d12ma",
            .root_module = b.createModule(.{
                .target = target,
                .optimize = .ReleaseFast,
                .link_libc = true,
            }),
            .linkage = .static,
        });
        d3d12ma_lib.root_module.sanitize_c = .off;
        d3d12ma_lib.linkLibCpp();
        d3d12ma_lib.addCSourceFile(.{
            .file = d3d12ma.path("src/build.cpp"),
            .flags = &.{
                "-Wno-address-of-temporary",
                "-Wno-tautological-undefined-compare",
            },
        });
        d3d12ma_lib.addIncludePath(d3d12ma.path("include"));
        lib_mod.linkLibrary(d3d12ma_lib);

        lib_mod.linkSystemLibrary("d3d12", .{});
        lib_mod.linkSystemLibrary("dxgi", .{});
    }

    switch (tag) {
        .windows => {
            const zwindows = b.lazyDependency("zwindows", .{}) orelse return;
            lib_mod.addImport("zwindows", zwindows.module("zwindows"));
            // shader compiler
            // lib_mod.linkSystemLibrary("dxcompiler", .{});
        },
        .linux => {
            // shader compiler
            // lib_mod.addSystemIncludePath(b.path("vendor/bin"));
            // lib_mod.linkSystemLibrary("dxcompiler", .{});
        },
        else => {},
    }

    const spirv_cross = b.dependency("spirv_cross", .{
        .target = target,
        .optimize = .ReleaseFast,
        .want_hlsl = true,
        .want_msl = true,
    });

    const spirv_cross_c = spirv_cross.artifact("spirv-cross-c");
    lib_mod.linkLibrary(spirv_cross_c);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "ila",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("sandbox/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ila", .module = lib_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "sandbox",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
