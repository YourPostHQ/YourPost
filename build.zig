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

    // Add library search paths for macOS with Homebrew
    if (target.result.os.tag == .macos) {
        root_mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
        root_mod.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
        root_mod.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
        root_mod.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    }

    // For Linux targets, explicitly add system library paths so Zig can find them
    if (target.result.os.tag == .linux) {
        // Use ZIG_SYSTEM_LIBRARY_PATH environment variable for system library search
        // This is the most reliable way to make Zig search system paths
        root_mod.addLibraryPath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu" });
        root_mod.addLibraryPath(.{ .cwd_relative = "/usr/lib" });
        root_mod.addIncludePath(.{ .cwd_relative = "/usr/include/x86_64-linux-gnu" });
        root_mod.addIncludePath(.{ .cwd_relative = "/usr/include" });
    }

    // For cross-compilation (aarch64, riscv64), use static linking
    const is_cross_linux = target.result.os.tag == .linux and (target.result.cpu.arch == .aarch64 or target.result.cpu.arch == .riscv64);
    if (is_cross_linux) {
        const arch = switch (target.result.cpu.arch) {
            .aarch64 => "aarch64-linux-gnu",
            .riscv64 => "riscv64-linux-gnu",
            else => "x86_64-linux-gnu",
        };
        root_mod.addIncludePath(.{ .cwd_relative = "/usr/include" });
        root_mod.addIncludePath(.{ .cwd_relative = std.fmt.allocPrint(b.allocator, "/usr/include/{s}", .{arch}) catch unreachable });
        const libc_path = std.fmt.allocPrint(b.allocator, "/usr/lib/{s}/libc.a", .{arch}) catch unreachable;
        const libsqlite3_path = std.fmt.allocPrint(b.allocator, "/usr/lib/{s}/libsqlite3.a", .{arch}) catch unreachable;
        const libssl_path = std.fmt.allocPrint(b.allocator, "/usr/lib/{s}/libssl.a", .{arch}) catch unreachable;
        const libcrypto_path = std.fmt.allocPrint(b.allocator, "/usr/lib/{s}/libcrypto.a", .{arch}) catch unreachable;
        root_mod.addObjectFile(.{ .cwd_relative = libc_path });
        root_mod.addObjectFile(.{ .cwd_relative = libsqlite3_path });
        root_mod.addObjectFile(.{ .cwd_relative = libssl_path });
        root_mod.addObjectFile(.{ .cwd_relative = libcrypto_path });
    } else if (target.result.os.tag == .linux) {
        // Native Linux - use dynamic linking
        root_mod.linkSystemLibrary("sqlite3", .{});
        root_mod.linkSystemLibrary("ssl", .{});
        root_mod.linkSystemLibrary("crypto", .{});
    } else {
        root_mod.linkSystemLibrary("sqlite3", .{});
        root_mod.linkSystemLibrary("ssl", .{});
        root_mod.linkSystemLibrary("crypto", .{});
    }

    const exe = b.addExecutable(.{
        .name = "yourpost",
        .root_module = root_mod,
    });
    b.installArtifact(exe);

    const install_cfg = b.addInstallFile(b.path("yourpost.service"), "systemd/yourpost.service");
    b.getInstallStep().dependOn(&install_cfg.step);

    const install_script = b.addInstallFile(b.path("install.sh"), "scripts/install.sh");
    b.getInstallStep().dependOn(&install_script.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run yourpost").dependOn(&run_cmd.step);

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

    const is_cross_linux_test = target.result.os.tag == .linux and (target.result.cpu.arch == .aarch64 or target.result.cpu.arch == .riscv64);
    if (is_cross_linux_test) {
        const arch = switch (target.result.cpu.arch) {
            .aarch64 => "aarch64-linux-gnu",
            .riscv64 => "riscv64-linux-gnu",
            else => "x86_64-linux-gnu",
        };
        test_mod.addIncludePath(.{ .cwd_relative = "/usr/include" });
        test_mod.addIncludePath(.{ .cwd_relative = std.fmt.allocPrint(b.allocator, "/usr/include/{s}", .{arch}) catch unreachable });
        const libc_path = std.fmt.allocPrint(b.allocator, "/usr/lib/{s}/libc.a", .{arch}) catch unreachable;
        const libsqlite3_path = std.fmt.allocPrint(b.allocator, "/usr/lib/{s}/libsqlite3.a", .{arch}) catch unreachable;
        const libssl_path = std.fmt.allocPrint(b.allocator, "/usr/lib/{s}/libssl.a", .{arch}) catch unreachable;
        const libcrypto_path = std.fmt.allocPrint(b.allocator, "/usr/lib/{s}/libcrypto.a", .{arch}) catch unreachable;
        test_mod.addObjectFile(.{ .cwd_relative = libc_path });
        test_mod.addObjectFile(.{ .cwd_relative = libsqlite3_path });
        test_mod.addObjectFile(.{ .cwd_relative = libssl_path });
        test_mod.addObjectFile(.{ .cwd_relative = libcrypto_path });
    } else if (target.result.os.tag == .linux) {
        // Native Linux - use dynamic linking
        test_mod.linkSystemLibrary("sqlite3", .{});
        test_mod.linkSystemLibrary("ssl", .{});
        test_mod.linkSystemLibrary("crypto", .{});
    } else {
        test_mod.linkSystemLibrary("sqlite3", .{});
        test_mod.linkSystemLibrary("ssl", .{});
        test_mod.linkSystemLibrary("crypto", .{});
    }
    const tests = b.addTest(.{ .root_module = test_mod });
    b.step("test", "Run tests").dependOn(&tests.step);
}
