const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zstb = b.addModule("zstb", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    zstb.addCSourceFile(.{
        .file = b.path("src/stb.c"),
        .language = .c,
        .flags = &.{
            "-std=c99",
            "-fno-sanitize=undefined",
        },
    });

    switch (target.result.os.tag) {
        .emscripten => zstb.addIncludePath(.{
            .cwd_relative = b.pathJoin(&.{ b.sysroot orelse @panic("emscripten sysroot not set"), "/include" }),
        }),
        else => zstb.link_libc = true,
    }

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
