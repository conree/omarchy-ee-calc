const std = @import("std");

// `zig build` installs the engine into ../bin/, where the plugin's QML runs
// it from. `zig build test` runs every unit test.
pub fn build(b: *std.Build) void {
    // Baseline CPU by default: the binary committed to bin/ is the one
    // users run, so it must not use instructions only this machine has.
    const target = b.standardTargetOptions(.{ .default_target = .{ .cpu_model = .baseline } });
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const exe = b.addExecutable(.{
        .name = "ee-calc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = optimize != .Debug,
        }),
    });

    const install = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = "../../bin" } },
    });
    b.getInstallStep().dependOn(&install.step);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the engine").dependOn(&run_cmd.step);

    const tests = b.addTest(.{ .root_module = exe.root_module });
    b.step("test", "Run unit tests").dependOn(&b.addRunArtifact(tests).step);
}
