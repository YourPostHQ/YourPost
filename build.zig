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
    root_mod.linkSystemLibrary("sqlite3", .{});
    root_mod.linkSystemLibrary("ssl", .{});
    root_mod.linkSystemLibrary("crypto", .{});

    const exe = b.addExecutable(.{
        .name = "yourpost",
        .root_module = root_mod,
    });
    b.installArtifact(exe);

    // Install configuration and service files
    const install_cfg = b.addInstallFile(b.path("yourpost.service"), "systemd/yourpost.service");
    b.getInstallStep().dependOn(&install_cfg.step);

    // Install the install script
    const install_script = b.addInstallFile(b.path("install.sh"), "scripts/install.sh");
    b.getInstallStep().dependOn(&install_script.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run yourpost").dependOn(&run_cmd.step);
    
    // Add test step
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.linkSystemLibrary("sqlite3", .{});
    test_mod.linkSystemLibrary("ssl", .{});
    test_mod.linkSystemLibrary("crypto", .{});
    const tests = b.addTest(.{ .root_module = test_mod });
    b.step("test", "Run tests").dependOn(&tests.step);
}
