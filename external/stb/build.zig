const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const stb = b.addLibrary(.{
        .name = "stb",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .sanitize_c = .off,
        }),
    });
    stb.root_module.addCSourceFile(.{
        .file = b.path("src/stb.c"),
        .language = .c,
        .flags = &.{
            "-std=c99",
            "-fno-sanitize=undefined",
        },
    });
    stb.installHeadersDirectory(b.path("src/"), "", .{});
    b.installArtifact(stb);
    switch (target.result.os.tag) {
        .emscripten => stb.addIncludePath(.{
            .cwd_relative = b.pathJoin(&.{ b.sysroot orelse @panic("emscripten sysroot not set"), "/include" }),
        }),
        else => stb.root_module.link_libc = true,
    }

    const zstb = b.addModule("zstb", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    zstb.linkLibrary(stb);

    const test_step = b.step("test", "Run stb tests");
    const tests = b.addTest(.{
        .name = "stb-tests",
        .root_source_file = b.path("src/stb.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(tests);
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
