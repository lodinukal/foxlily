const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        .preferred_link_mode = .dynamic,
        //.preferred_link_mode = .static, // or .dynamic
    });
    const sdl_lib = sdl_dep.artifact("SDL3");
    b.installArtifact(sdl_lib);

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
    });
    lib_mod.addOptions("config", options);
    lib_mod.linkLibrary(sdl_lib);

    if (d3d12_option) {
        const d3d12ma = b.lazyDependency("d3d12ma", .{}) orelse return;
        const d3d12ma_lib = b.addLibrary(.{
            .name = "d3d12ma",
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
            .linkage = .static,
        });
        d3d12ma_lib.root_module.sanitize_c = false;
        d3d12ma_lib.linkLibCpp();
        d3d12ma_lib.addCSourceFile(.{
            .file = d3d12ma.path("src/build.cpp"),
            .flags = &.{
                "-Wno-address-of-temporary",
            },
        });
        d3d12ma_lib.addIncludePath(d3d12ma.path("include"));
        lib_mod.linkLibrary(d3d12ma_lib);

        lib_mod.linkSystemLibrary("d3d12", .{});
        lib_mod.linkSystemLibrary("dxgi", .{});
    }

    if (tag == .windows) {
        const zwindows = b.lazyDependency("zwindows", .{}) orelse return;
        lib_mod.addImport("zwindows", zwindows.module("zwindows"));
    }

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("foxlily", lib_mod);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "foxlily",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "runoff",
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
