const std = @import("std");
const session = @import("session.zig");

pub const Deps = session.Deps;

const ConnCtx = struct {
    stream: std.Io.net.Stream,
    io: std.Io,
    deps: Deps,
};

pub fn listen(io: std.Io, port: u16, deps: Deps) !void {
    const addr: std.Io.net.IpAddress = .{ .ip4 = std.Io.net.Ip4Address.unspecified(port) };
    var server = try std.Io.net.IpAddress.listen(&addr, io, .{ .reuse_address = true });
    defer server.deinit(io);
    std.log.info("IMAP listening on :{d}", .{port});

    while (true) {
        const stream = server.accept(io) catch |err| {
            std.log.warn("IMAP accept error: {}", .{err});
            continue;
        };
        const ctx = try deps.alloc.create(ConnCtx);
        ctx.* = .{ .stream = stream, .io = io, .deps = deps };
        const t = std.Thread.spawn(.{}, handleConn, .{ctx}) catch |err| {
            std.log.warn("IMAP thread spawn: {}", .{err});
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
    var reader = ctx.stream.reader(ctx.io, &read_buf);
    var writer = ctx.stream.writer(ctx.io, &write_buf);
    session.run(&reader.interface, &writer.interface, ctx.deps) catch |err| {
        std.log.warn("IMAP session: {}", .{err});
    };
}
