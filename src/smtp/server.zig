const std = @import("std");
const session = @import("session.zig");

pub const Deps = session.Deps;

const ConnCtx = struct {
    stream: std.Io.net.Stream,
    io: std.Io,
    deps: Deps,
};

pub fn listen(io: std.Io, port: u16, deps: Deps) void {
    if (port < 1024 and std.os.linux.geteuid() != 0) {
        std.log.err("SMTP: Cannot bind to privileged port {d} (ports < 1024 require root). Use port > 1024 or run with sudo.", .{port});
        return;
    }
    const addr: std.Io.net.IpAddress = .{ .ip4 = std.Io.net.Ip4Address.unspecified(port) };
    var server = std.Io.net.IpAddress.listen(&addr, io, .{ .reuse_address = true }) catch |err| {
        if (err == error.AddressInUse) {
            std.log.err("SMTP: Port {d} already in use.", .{port});
        } else {
            std.log.err("SMTP: Failed to bind to port {d}: {}", .{ port, err });
        }
        return;
    };
    defer server.deinit(io);
    std.log.info("SMTP listening on :{d}", .{port});

    while (true) {
        const stream = server.accept(io) catch |err| {
            std.log.warn("SMTP accept error: {}", .{err});
            continue;
        };
        const ctx = deps.alloc.create(ConnCtx) catch |err| {
            std.log.warn("SMTP alloc error: {}", .{err});
            stream.socket.close(io);
            continue;
        };
        ctx.* = .{ .stream = stream, .io = io, .deps = deps };
        const t = std.Thread.spawn(.{}, handleConn, .{ctx}) catch |err| {
            std.log.warn("SMTP thread spawn: {}", .{err});
            stream.socket.close(io);
            deps.alloc.destroy(ctx);
            continue;
        };
        t.detach();
    }
}

fn handleConn(ctx: *ConnCtx) void {
    defer {
        ctx.stream.socket.close(ctx.io);
        ctx.deps.alloc.destroy(ctx);
    }
    var read_buf: [8192]u8 = undefined;
    var write_buf: [4096]u8 = undefined;
    var net_reader = ctx.stream.reader(ctx.io, &read_buf);
    var net_writer = ctx.stream.writer(ctx.io, &write_buf);
    session.run(
        &net_reader.interface,
        &net_writer.interface,
        ctx.deps,
    ) catch |err| std.log.warn("SMTP session: {}", .{err});
}
