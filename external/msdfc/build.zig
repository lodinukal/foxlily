const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const stb_dep = b.dependency("stb", .{
        .target = target,
        .optimize = optimize,
    });

    const msdfc = b.addModule("msdfc", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "stb", .module = stb_dep.module("zstb") },
        },
    });
    msdfc.linkLibrary(stb_dep.artifact("stb"));
    msdfc.addCSourceFile(.{
        .file = b.path("src/msdf.c"),
        .language = .c,
        .flags = &.{
            "-std=c99",
            "-fno-sanitize=undefined",
        },
    });
}
