const std = @import("std");
const session = @import("session.zig");

pub const Deps = session.Deps;

const ConnCtx = struct { stream: std.Io.net.Stream, io: std.Io, deps: Deps };

pub fn listen(io: std.Io, port: u16, deps: Deps) !void {
    const addr: std.Io.net.IpAddress = .{ .ip4 = std.Io.net.Ip4Address.unspecified(port) };
    var server = try std.Io.net.IpAddress.listen(&addr, io, .{ .reuse_address = true });
    defer server.deinit(io);
    std.log.info("POP3 listening on :{d}", .{port});

    while (true) {
        const stream = server.accept(io) catch |err| {
            std.log.warn("POP3 accept: {}", .{err});
            continue;
        };
        const ctx = try deps.alloc.create(ConnCtx);
        ctx.* = .{ .stream = stream, .io = io, .deps = deps };
        const t = std.Thread.spawn(.{}, handleConn, .{ctx}) catch |err| {
            std.log.warn("POP3 thread: {}", .{err});
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
    var rb: [8192]u8 = undefined;
    var wb: [4096]u8 = undefined;
    var nr = ctx.stream.reader(ctx.io, &rb);
    var nw = ctx.stream.writer(ctx.io, &wb);
    session.run(&nr.interface, &nw.interface, ctx.deps) catch |err|
        std.log.warn("POP3 session: {}", .{err});
}
