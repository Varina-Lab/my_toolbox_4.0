const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // Mặc định ép ReleaseSmall hoặc ReleaseFast từ CLI
    const optimize = b.standardOptimizeOption(.{}); 

    const exe = b.addExecutable(.{
        .name = "zig-tool",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);
}
