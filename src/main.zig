const std = @import("std");
const config = @import("config.zig");
const GlobalDb = @import("db/global.zig").GlobalDb;
const user_db = @import("db/user.zig");
const smtp = @import("smtp/server.zig");
const pop3 = @import("pop3/server.zig");
const imap = @import("imap/server.zig");
const api = @import("api/server.zig");

// Global shutdown flag (atomic for thread safety)
var shutdown_flag = std.atomic.Value(bool).init(false);

// Signal handler for graceful shutdown
fn signalHandler(sig: std.posix.SIG) callconv(.c) void {
    _ = sig;
    std.log.info("Received shutdown signal, initiating graceful shutdown...", .{});
    shutdown_flag.store(true, .seq_cst);
}

// Command-line arguments
const Args = struct {
    daemon: bool = false,
    pid_file: ?[]const u8 = null,
    bootstrap_email: ?[]const u8 = null,
    bootstrap_password: ?[]const u8 = null,
};

fn parseArgs(alloc: std.mem.Allocator, proc_args: std.process.Args) !Args {
    var args = Args{};
    var iter = try std.process.Args.Iterator.initAllocator(proc_args, alloc);

    _ = iter.skip(); // skip program name

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--daemon") or std.mem.eql(u8, arg, "-d")) {
            args.daemon = true;
        } else if (std.mem.eql(u8, arg, "--pid-file")) {
            if (iter.next()) |pid_arg| {
                args.pid_file = pid_arg;
            } else {
                std.log.err("Missing argument for --pid-file", .{});
                return error.InvalidArgs;
            }
        } else if (std.mem.eql(u8, arg, "--bootstrap")) {
            if (iter.next()) |email_arg| {
                args.bootstrap_email = email_arg;
            } else {
                std.log.err("--bootstrap requires: --bootstrap <email> <password>", .{});
                return error.InvalidArgs;
            }
            if (iter.next()) |pass_arg| {
                args.bootstrap_password = pass_arg;
            } else {
                std.log.err("--bootstrap requires: --bootstrap <email> <password>", .{});
                return error.InvalidArgs;
            }
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            std.process.exit(0);
        } else {
            std.log.warn("Unknown argument: {s}", .{arg});
        }
    }

    return args;
}

fn printUsage() void {
    const usage =
        \\Usage: yourpost [options]
        \\Options:
        \\  --daemon, -d                   Run as a daemon (background process)
        \\  --pid-file <path>              Write PID to specified file
        \\  --bootstrap <email> <password> Create the initial system user and exit
        \\  --help, -h                     Show this help message
        \\
        \\Environment variables are used for configuration.
        \\See README.md for details.
    ;
    std.debug.print(usage, .{});
}

pub fn main(init: std.process.Init) !void {
    const alloc = std.heap.page_allocator;

    // Parse command-line arguments
    const args = parseArgs(alloc, init.minimal.args) catch {
        std.process.exit(1);
        return;
    };

    const cfg = try config.Config.fromEnv(alloc);

    // Install signal handlers for graceful shutdown
    const sa = std.posix.Sigaction{
        .handler = .{ .handler = signalHandler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.TERM, &sa, null);
    std.posix.sigaction(std.posix.SIG.INT, &sa, null);
    std.posix.sigaction(std.posix.SIG.QUIT, &sa, null);

    const cwd = std.Io.Dir.cwd();

    // Startup validation
    std.log.info("Validating startup configuration...", .{});

    // Check if data_dir is writable
    _ = try std.Io.Dir.createDirPathStatus(cwd, init.io, cfg.data_dir, .default_dir);
    cwd.access(init.io, cfg.data_dir, .{ .read = true, .write = true }) catch |err| {
        std.log.err("Data directory '{s}' is not accessible: {}", .{ cfg.data_dir, err });
        return;
    };

    const mailbox_dir = try std.fmt.allocPrint(alloc, "{s}/mailboxes", .{cfg.data_dir});
    defer alloc.free(mailbox_dir);
    _ = try std.Io.Dir.createDirPathStatus(cwd, init.io, mailbox_dir, .default_dir);

    const global_db_path_str = try std.fmt.allocPrint(alloc, "{s}/global.db", .{cfg.data_dir});
    defer alloc.free(global_db_path_str);
    const global_db_path = try alloc.dupeZ(u8, global_db_path_str);
    defer alloc.free(global_db_path);
    var global_db = try GlobalDb.open(alloc, init.io, global_db_path);
    defer global_db.close();

    // Bootstrap: create the initial system user then exit
    if (args.bootstrap_email) |email| {
        const password = args.bootstrap_password.?;
        const at = std.mem.indexOf(u8, email, "@") orelse {
            std.log.err("Bootstrap email must be a valid address", .{});
            return error.InvalidArgs;
        };
        const domain = email[at + 1 ..];
        global_db.addDomain(domain) catch {};
        global_db.createUser(email, password, "system", domain) catch |err| {
            if (err == error.UserAlreadyExists) {
                std.log.err("System user {s} already exists", .{email});
            } else {
                std.log.err("Failed to create system user: {}", .{err});
            }
            return err;
        };
        std.log.info("System user {s} created successfully", .{email});

        // Create per-user mailbox database
        const db_path_str = std.fmt.allocPrint(alloc, "{s}/mailboxes/{s}.db", .{ cfg.data_dir, email }) catch |err| {
            std.log.err("Failed to allocate path for mailbox: {}", .{err});
            return;
        };
        defer alloc.free(db_path_str);
        const db_path = alloc.dupeZ(u8, db_path_str) catch |err| {
            std.log.err("Failed to allocate Z string for mailbox path: {}", .{err});
            return;
        };
        defer alloc.free(db_path);
        var udb = user_db.UserDb.open(alloc, db_path) catch |err| {
            std.log.err("Failed to create mailbox for {s}: {}", .{ email, err });
            return;
        };
        udb.close();
        std.log.info("Mailbox database created for {s}", .{email});
        return;
    }

    std.log.info("Startup validation complete.", .{});

    const smtp_deps = smtp.Deps{
        .global_db = &global_db,
        .alloc = alloc,
        .hostname = cfg.hostname,
        .data_dir = cfg.data_dir,
        .max_size = cfg.smtp_max_size,
        .io = init.io,
        .relay_host = cfg.smtp_relay_host,
        .relay_port = cfg.smtp_relay_port,
        .relay_user = cfg.smtp_relay_user,
        .relay_password = cfg.smtp_relay_password,
        .relay_use_tls = cfg.smtp_relay_use_tls,
        .use_tls = cfg.smtp_use_tls,
        .tls_cert = cfg.smtp_tls_cert,
        .tls_key = cfg.smtp_tls_key,
        .max_connections = cfg.max_connections,
        .connection_timeout_ms = cfg.connection_timeout_ms,
        .read_timeout_ms = cfg.read_timeout_ms,
    };
    const pop3_deps = pop3.Deps{
        .global_db = &global_db,
        .alloc = alloc,
        .hostname = cfg.hostname,
        .data_dir = cfg.data_dir,
        .use_tls = cfg.pop3_use_tls,
        .tls_cert = cfg.pop3_tls_cert,
        .tls_key = cfg.pop3_tls_key,
        .max_connections = cfg.max_connections,
        .connection_timeout_ms = cfg.connection_timeout_ms,
        .read_timeout_ms = cfg.read_timeout_ms,
    };
    const imap_deps = imap.Deps{
        .global_db = &global_db,
        .alloc = alloc,
        .hostname = cfg.hostname,
        .data_dir = cfg.data_dir,
        .use_tls = cfg.imap_use_tls,
        .tls_cert = cfg.imap_tls_cert,
        .tls_key = cfg.imap_tls_key,
        .max_connections = cfg.max_connections,
        .connection_timeout_ms = cfg.connection_timeout_ms,
        .read_timeout_ms = cfg.read_timeout_ms,
    };
    const api_deps = api.Deps{
        .global_db = &global_db,
        .alloc = alloc,
        .hostname = cfg.hostname,
        .data_dir = cfg.data_dir,
        .api_port = cfg.api_port,
        .service_port = cfg.service_port,
        .service_token = cfg.service_token,
        .jwt_secret = cfg.jwt_secret,
        .io = init.io,
    };

    // Handle daemon mode (fork and exit parent)
    if (args.daemon) {
        const pid = std.c.fork();
        if (pid < 0) {
            std.log.err("Failed to fork for daemon mode", .{});
            return error.ForkFailed;
        }
        if (pid > 0) {
            // Parent process - exit
            std.process.exit(0);
            return;
        }
        // Child process continues
        // Create new session (detach from terminal)
        _ = std.c.setsid();
    }

    // Write PID file if requested
    if (args.pid_file) |pid_path| {
        const pid_file = cwd.createFile(init.io, pid_path, .{}) catch |err| {
            std.log.err("Failed to create PID file '{s}': {}", .{ pid_path, err });
            return err;
        };
        defer pid_file.close(init.io);

        const pid_str = std.fmt.allocPrint(alloc, "{d}", .{std.c.getpid()}) catch |err| {
            std.log.err("Failed to format PID: {}", .{err});
            return err;
        };
        defer alloc.free(pid_str);

        pid_file.writeStreamingAll(init.io, pid_str) catch |err| {
            std.log.err("Failed to write PID file: {}", .{err});
            return err;
        };

        std.log.info("PID written to {s}", .{pid_path});
    }

    std.log.info("yourpost starting on SMTP :{d}/{d}, POP3 :{d}, IMAP :{d}, API :{d}, Service API :{d}", .{
        cfg.smtp_port,
        cfg.smtp_submission_port,
        cfg.pop3_port,
        cfg.imap_port,
        cfg.api_port,
        cfg.service_port,
    });

    // Spawn server threads (errors will be logged by each server)
    // Pass shutdown flag to enable graceful shutdown
    _ = std.Thread.spawn(.{}, smtp.listen, .{ init.io, cfg.smtp_port, smtp_deps, &shutdown_flag }) catch |err| {
        std.log.err("Failed to spawn SMTP thread: {}", .{err});
        return;
    };
    _ = std.Thread.spawn(.{}, smtp.listen, .{ init.io, cfg.smtp_submission_port, smtp_deps, &shutdown_flag }) catch |err| {
        std.log.err("Failed to spawn SMTP submission thread: {}", .{err});
        return;
    };
    _ = std.Thread.spawn(.{}, pop3.listen, .{ init.io, cfg.pop3_port, pop3_deps, &shutdown_flag }) catch |err| {
        std.log.err("Failed to spawn POP3 thread: {}", .{err});
        return;
    };
    _ = std.Thread.spawn(.{}, imap.listen, .{ init.io, cfg.imap_port, imap_deps, &shutdown_flag }) catch |err| {
        std.log.err("Failed to spawn IMAP thread: {}", .{err});
        return;
    };
    _ = std.Thread.spawn(.{}, api.listen, .{ init.io, api_deps, &shutdown_flag }) catch |err| {
        std.log.err("Failed to spawn API thread: {}", .{err});
        return;
    };
    _ = std.Thread.spawn(.{}, api.listenService, .{ init.io, api_deps, &shutdown_flag }) catch |err| {
        std.log.err("Failed to spawn Service API thread: {}", .{err});
        return;
    };

    std.log.info("yourpost is ready (send SIGTERM or SIGINT to stop)", .{});

    // Main loop - check shutdown flag periodically
    while (!shutdown_flag.load(.seq_cst)) {
        std.Io.sleep(init.io, std.Io.Duration.fromSeconds(1), .awake) catch {};
    }

    // Graceful shutdown sequence
    std.log.info("Shutting down yourpost...", .{});

    // Give active connections time to finish (with timeout)
    var shutdown_timeout: i32 = 30; // 30 second timeout
    while (shutdown_timeout > 0) {
        std.Io.sleep(init.io, std.Io.Duration.fromSeconds(1), .awake) catch {};
        shutdown_timeout -= 1;
    }

    std.log.info("Closing global database...", .{});
    global_db.close();

    std.log.info("yourpost shutdown complete.", .{});
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    try std.testing.fuzz({}, testOne, .{});
}

fn testOne(context: void, smith: *std.testing.Smith) !void {
    _ = context;
    // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!

    const gpa = std.testing.allocator;
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(gpa);
    while (!smith.eos()) switch (smith.value(enum { add_data, dup_data })) {
        .add_data => {
            const slice = try list.addManyAsSlice(gpa, smith.value(u4));
            smith.bytes(slice);
        },
        .dup_data => {
            if (list.items.len == 0) continue;
            if (list.items.len > std.math.maxInt(u32)) return error.SkipZigTest;
            const len = smith.valueRangeAtMost(u32, 1, @min(32, list.items.len));
            const off = smith.valueRangeAtMost(u32, 0, @intCast(list.items.len - len));
            try list.appendSlice(gpa, list.items[off..][0..len]);
            try std.testing.expectEqualSlices(
                u8,
                list.items[off..][0..len],
                list.items[list.items.len - len ..],
            );
        },
    };
}
