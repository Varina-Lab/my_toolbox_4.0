const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    const exe = b.addExecutable(.{
        .name = "portable_run_GPT",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.subsystem = .Windows;
    exe.strip = true;

    exe.linkSystemLibrary("kernel32");
    exe.linkSystemLibrary("user32");

    b.installArtifact(exe);
}