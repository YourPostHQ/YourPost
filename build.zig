const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // macOS: use Homebrew paths
    if (target.result.os.tag == .macos) {
        root_mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
        root_mod.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
        root_mod.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
        root_mod.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    }

    // Linux: use dynamic linking (ZIG_SYSTEM_LIBRARY_PATH set in CI)
    if (target.result.os.tag == .linux) {
        root_mod.linkSystemLibrary("sqlite3", .{});
        root_mod.linkSystemLibrary("ssl", .{});
        root_mod.linkSystemLibrary("crypto", .{});
    }

    const exe = b.addExecutable(.{ .name = "yourpost", .root_module = root_mod });
    b.installArtifact(exe);

    _ = b.addInstallFile(b.path("yourpost.service"), "systemd/yourpost.service");
    _ = b.addInstallFile(b.path("install.sh"), "scripts/install.sh");

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    _ = b.step("run", "Run yourpost").dependOn(&run_cmd.step);

    // Test module
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    if (target.result.os.tag == .macos) {
        test_mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
        test_mod.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
        test_mod.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
        test_mod.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    }

    if (target.result.os.tag == .linux) {
        test_mod.linkSystemLibrary("sqlite3", .{});
        test_mod.linkSystemLibrary("ssl", .{});
        test_mod.linkSystemLibrary("crypto", .{});
    }

    const tests = b.addTest(.{ .root_module = test_mod });
    _ = b.step("test", "Run tests").dependOn(&tests.step);
}
