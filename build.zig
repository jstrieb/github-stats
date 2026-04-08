const std = @import("std");

pub fn build(b: *std.Build) !void {
    const default_target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSafe,
    });
    const version = @import("build.zig.zon").version;
    const options = b.addOptions();
    options.addOption([]const u8, "version", version);

    const exe = b.addExecutable(.{
        .name = "github-stats",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = default_target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("options", options.createModule());
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const tests = b.addTest(.{ .root_module = exe.root_module });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run the tests");
    test_step.dependOn(&run_tests.step);

    const release_step = b.step("release", "Cross-compile release binaries");
    const release_targets: []const std.Target.Query = &.{
        // Zig tier 1 supported compiler targets (manually tested)
        .{ .cpu_arch = .x86_64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .macos },
        // Zig tier 2 supported compiler targets (manually tested)
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .x86_64, .os_tag = .windows },
        // Zig tier 2 supported compiler targets (untested)
        .{ .cpu_arch = .aarch64, .os_tag = .freebsd },
        .{ .cpu_arch = .aarch64, .os_tag = .linux },
        .{ .cpu_arch = .aarch64, .os_tag = .netbsd },
        .{ .cpu_arch = .aarch64, .os_tag = .windows },
        .{ .cpu_arch = .arm, .os_tag = .freebsd },
        .{ .cpu_arch = .arm, .os_tag = .linux },
        .{ .cpu_arch = .arm, .os_tag = .netbsd },
        .{ .cpu_arch = .loongarch64, .os_tag = .linux },
        .{ .cpu_arch = .powerpc, .os_tag = .linux },
        .{ .cpu_arch = .powerpc, .os_tag = .netbsd },
        .{ .cpu_arch = .powerpc64, .os_tag = .freebsd },
        .{ .cpu_arch = .powerpc64, .os_tag = .linux },
        .{ .cpu_arch = .powerpc64le, .os_tag = .freebsd },
        .{ .cpu_arch = .powerpc64le, .os_tag = .linux },
        .{ .cpu_arch = .riscv32, .os_tag = .linux },
        .{ .cpu_arch = .riscv64, .os_tag = .freebsd },
        .{ .cpu_arch = .riscv64, .os_tag = .linux },
        .{ .cpu_arch = .thumb, .os_tag = .windows },
        .{ .cpu_arch = .thumb, .os_tag = .linux },
        // Fails with error due to networking
        // .{ .cpu_arch = .wasm32, .os_tag = .wasi },
        .{ .cpu_arch = .x86, .os_tag = .linux },
        .{ .cpu_arch = .x86, .os_tag = .windows },
        .{ .cpu_arch = .x86_64, .os_tag = .freebsd },
        .{ .cpu_arch = .x86_64, .os_tag = .netbsd },
    };
    for (release_targets) |t| {
        const cross_exe = b.addExecutable(.{
            .name = try std.fmt.allocPrint(
                b.allocator,
                "github-stats_{s}",
                .{try t.zigTriple(b.allocator)},
            ),
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = b.resolveTargetQuery(t),
                .optimize = .ReleaseFast,
            }),
        });
        cross_exe.root_module.addImport("options", options.createModule());
        release_step.dependOn(&b.addInstallArtifact(cross_exe, .{}).step);
    }
}
