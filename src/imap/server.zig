const std = @import("std");
const session = @import("session.zig");

pub const Deps = session.Deps;

const ConnCtx = struct {
    stream: std.Io.net.Stream,
    io: std.Io,
    deps: Deps,
};

// Global connection counter (atomic for thread safety)
var connection_count = std.atomic.Value(usize).init(0);

pub fn listen(io: std.Io, port: u16, deps: Deps, shutdown_flag: ?*std.atomic.Value(bool)) void {
    if (port < 1024 and std.os.linux.geteuid() != 0) {
        std.log.err("IMAP: Cannot bind to privileged port {d} (ports < 1024 require root). Use port > 1024 or run with sudo.", .{port});
        return;
    }
    const addr: std.Io.net.IpAddress = .{ .ip4 = std.Io.net.Ip4Address.unspecified(port) };
    var server = std.Io.net.IpAddress.listen(&addr, io, .{ .reuse_address = true }) catch |err| {
        if (err == error.AddressInUse) {
            std.log.err("IMAP: Port {d} already in use.", .{port});
        } else {
            std.log.err("IMAP: Failed to bind to port {d}: {}", .{ port, err });
        }
        return;
    };
    defer server.deinit(io);
    std.log.info("IMAP listening on :{d}", .{port});

    while (true) {
        // Check shutdown flag
        if (shutdown_flag) |flag| {
            if (flag.load(.seq_cst)) {
                std.log.info("IMAP: Stopping accept loop (shutdown requested)", .{});
                return;
            }
        }

        // Check connection limit
        const current = connection_count.load(.seq_cst);
        if (current >= deps.max_connections) {
            std.log.warn("IMAP: Connection limit reached ({d}/{d}), rejecting connection", .{ current, deps.max_connections });
            const stream = server.accept(io) catch |err| {
                if (shutdown_flag) |flag| {
                    if (flag.load(.seq_cst)) return;
                }
                std.log.warn("IMAP accept error: {}", .{err});
                continue;
            };
            var reject_buf: [4096]u8 = undefined;
            var rw = stream.writer(io, &reject_buf);
            rw.interface.writeAll("* BYE Too many connections, try again later\r\n") catch {};
            rw.interface.flush() catch {};
            stream.socket.close(io);
            continue;
        }

        const stream = server.accept(io) catch |err| {
            // Check if this is a shutdown-related error
            if (shutdown_flag) |flag| {
                if (flag.load(.seq_cst)) return;
            }
            std.log.warn("IMAP accept error: {}", .{err});
            continue;
        };

        // Increment connection count
        _ = connection_count.fetchAdd(1, .seq_cst);

        const ctx = deps.alloc.create(ConnCtx) catch |err| {
            std.log.warn("IMAP alloc: {}", .{err});
            stream.socket.close(io);
            _ = connection_count.fetchSub(1, .seq_cst);
            continue;
        };
        ctx.* = .{ .stream = stream, .io = io, .deps = deps };
        const t = std.Thread.spawn(.{}, handleConn, .{ctx}) catch |err| {
            std.log.warn("IMAP thread spawn: {}", .{err});
            stream.socket.close(io);
            deps.alloc.destroy(ctx);
            _ = connection_count.fetchSub(1, .seq_cst);
            continue;
        };
        t.detach();
    }
}

fn handleConn(ctx: *ConnCtx) void {
    defer {
        ctx.stream.socket.close(ctx.io);
        ctx.deps.alloc.destroy(ctx);
        // Decrement connection count
        _ = connection_count.fetchSub(1, .seq_cst);
    }

    var read_buf: [8192]u8 = undefined;
    var write_buf: [4096]u8 = undefined;
    var reader = ctx.stream.reader(ctx.io, &read_buf);
    var writer = ctx.stream.writer(ctx.io, &write_buf);
    session.run(&reader.interface, &writer.interface, ctx.deps) catch |err| {
        std.log.warn("IMAP session: {}", .{err});
    };
}
