const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "portable_run",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.strip = optimize != .Debug;
    exe.want_lto = true;
    
    // [QUAN TRỌNG NHẤT]: Ép ứng dụng thành Native Windows GUI (Không bao giờ nháy màn hình đen)
    exe.subsystem = .Windows;

    b.installArtifact(exe);
}
