const std = @import("std");
const c = @cImport({
    @cInclude("time.h");
    @cInclude("sys/stat.h");
});
const GlobalDb = @import("../storage/global_db.zig").GlobalDb;
const UserDb = @import("../storage/user_db.zig").UserDb;

pub const Deps = struct {
    global_db: *GlobalDb,
    alloc: std.mem.Allocator,
    hostname: []const u8,
    data_dir: []const u8,
    api_port: u16,
    io: std.Io,
};

const ConnCtx = struct {
    stream: std.Io.net.Stream,
    io: std.Io,
    deps: Deps,
};

pub fn listen(io: std.Io, deps: Deps) !void {
    const addr: std.Io.net.IpAddress = .{ .ip4 = std.Io.net.Ip4Address.unspecified(deps.api_port) };
    var server = try std.Io.net.IpAddress.listen(&addr, io, .{ .reuse_address = true });
    defer server.deinit(io);
    std.log.info("HTTP API listening on :{d}", .{deps.api_port});

    while (true) {
        const stream = server.accept(io) catch |err| {
            std.log.warn("API accept error: {}", .{err});
            continue;
        };
        const ctx = try deps.alloc.create(ConnCtx);
        ctx.* = .{ .stream = stream, .io = io, .deps = deps };
        const t = std.Thread.spawn(.{}, handleConn, .{ctx}) catch |err| {
            std.log.warn("API thread spawn: {}", .{err});
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

    var read_buf: [4096]u8 = undefined;
    var write_buf: [4096]u8 = undefined;
    var net_reader = ctx.stream.reader(ctx.io, &read_buf);
    var net_writer = ctx.stream.writer(ctx.io, &write_buf);
    const reader = &net_reader.interface;
    const writer = &net_writer.interface;

    const request_line = reader.takeDelimiterInclusive('\n') catch return;
    const line = std.mem.trimEnd(u8, request_line, "\r\n");
    const method_end = std.mem.indexOfScalar(u8, line, ' ') orelse return;
    const path_end = std.mem.indexOfScalar(u8, line[method_end + 1 ..], ' ') orelse return;
    const method = line[0..method_end];
    const path = line[method_end + 1 .. method_end + 1 + path_end];

    // Read headers and extract Content-Length
    var content_length: ?usize = null;
    while (true) {
        const header = reader.takeDelimiterInclusive('\n') catch return;
        if (header.len <= 2) break;
        const trimmed = std.mem.trim(u8, header, "\r\n");
        if (std.mem.startsWith(u8, trimmed, "Content-Length:")) {
            const value = std.mem.trim(u8, trimmed[15..], " ");
            content_length = std.fmt.parseInt(usize, value, 10) catch null;
        }
    }

    if (std.mem.eql(u8, method, "GET")) {
        if (std.mem.eql(u8, path, "/health")) {
            writeJsonResponse(writer, 200, makeHealthBody()) catch return;
            return;
        }
        if (std.mem.startsWith(u8, path, "/mailboxes/") and endsWith(path, "/folders")) {
            const user = path[11 .. path.len - 8];
            writeUserFolders(writer, ctx, user) catch return;
            return;
        }
    }

    if (std.mem.eql(u8, method, "POST")) {
        if (std.mem.eql(u8, path, "/incoming")) {
            handleIncoming(writer, ctx, reader, content_length) catch return;
            return;
        }
    }

    writeNotFound(writer) catch return;
}

fn handleIncoming(writer: anytype, ctx: *ConnCtx, reader: anytype, content_length: ?usize) !void {
    const alloc = ctx.deps.alloc;
    std.log.info("handleIncoming called, content_length={?}", .{content_length});

    // Read body based on Content-Length, or read until connection closes
    const body_size = content_length orelse 64 * 1024; // Default 64KB if no Content-Length

    if (body_size > 10 * 1024 * 1024) { // 10MB max
        try writer.print("HTTP/1.1 413 Payload Too Large\r\n\r\n", .{});
        return;
    }

    const body = try alloc.alloc(u8, body_size);
    defer alloc.free(body);

    var bytes_read: usize = 0;
    while (bytes_read < body_size) {
        const slice: []u8 = body[bytes_read..];
        var slices: [1][]u8 = .{slice};
        const n = reader.readVec(&slices) catch |err| {
            std.log.info("read error (expected if connection closed): {}", .{err});
            break; // Connection closed or error - use what we have
        };
        if (n == 0) break;
        bytes_read += n;
        if (content_length == null) break; // If no Content-Length, read one chunk then stop
    }

    std.log.info("Read {d} bytes of email body", .{bytes_read});
    if (bytes_read == 0) {
        std.log.err("Empty body", .{});
        try writer.print("HTTP/1.1 400 Bad Request\r\n\r\n", .{});
        return;
    }
    const email_body = body[0..bytes_read];

    // Parse basic email headers to extract recipient
    var recipient: []const u8 = &.{};
    var from: []const u8 = &.{};
    {
        // Search for To: header in entire email body (simple approach)
        if (std.mem.indexOf(u8, email_body, "To:")) |to_pos| {
            // Find end of To: line
            var line_end: usize = to_pos + 3;
            while (line_end < email_body.len and email_body[line_end] != '\r' and email_body[line_end] != '\n') {
                line_end += 1;
            }
            const to_line = email_body[to_pos..line_end];
            recipient = std.mem.trim(u8, to_line[3..], " \t");
            // Remove any <email> wrapping
            if (std.mem.indexOf(u8, recipient, "<")) |start| {
                if (std.mem.indexOf(u8, recipient, ">")) |end| {
                    recipient = recipient[start + 1 .. end];
                }
            }
        }

        // Also try to find From: header
        if (std.mem.indexOf(u8, email_body, "From:")) |from_pos| {
            // Find end of From: line
            var line_end: usize = from_pos + 5;
            while (line_end < email_body.len and email_body[line_end] != '\r' and email_body[line_end] != '\n') {
                line_end += 1;
            }
            const from_line = email_body[from_pos..line_end];
            from = std.mem.trim(u8, from_line[5..], " \t");
        }

        std.log.info("Parsed recipient: {s}, from: {s}", .{ recipient, from });
    }

    if (recipient.len == 0) {
        std.log.err("No recipient found in email", .{});
        try writer.print("HTTP/1.1 400 Bad Request\r\n", .{});
        try writer.writeAll("Content-Length: 0\r\n\r\n");
        return;
    }

    // Extract local part (username) from recipient
    const at_pos = std.mem.indexOfScalar(u8, recipient, '@') orelse {
        std.log.err("No @ in recipient: {s}", .{recipient});
        try writer.print("HTTP/1.1 400 Bad Request\r\n", .{});
        try writer.writeAll("Content-Length: 0\r\n\r\n");
        return;
    };
    const username = recipient[0..at_pos];
    std.log.info("Delivering email to user: {s}", .{username});

    // Ensure mailboxes directory exists
    const mailboxes_dir = try std.fmt.allocPrint(alloc, "{s}/mailboxes", .{ctx.deps.data_dir});
    defer alloc.free(mailboxes_dir);
    _ = c.mkdir(mailboxes_dir.ptr, c.S_IRWXU | c.S_IRWXG | c.S_IRWXO);
    // mkdir returns -1 on error, but we ignore errors (dir may already exist)

    // Deliver to user's INBOX
    const db_path_str = try std.fmt.allocPrint(alloc, "{s}/mailboxes/{s}.db", .{ ctx.deps.data_dir, username });
    defer alloc.free(db_path_str);
    const db_path = try alloc.dupeZ(u8, db_path_str);
    defer alloc.free(db_path);

    std.log.info("Opening/creating user db at: {s}", .{db_path_str});
    var udb = UserDb.open(alloc, db_path) catch |err| {
        std.log.err("Failed to open user db: {}", .{err});
        try writer.print("HTTP/1.1 500 Internal Server Error\r\n", .{});
        try writer.writeAll("Content-Length: 0\r\n\r\n");
        return;
    };
    defer udb.close();

    const folder = udb.getFolderByName("INBOX") catch |err| {
        std.log.err("Failed to get INBOX: {}", .{err});
        try writer.print("HTTP/1.1 500 Internal Server Error\r\n", .{});
        try writer.writeAll("Content-Length: 0\r\n\r\n");
        return;
    } orelse {
        std.log.err("INBOX not found", .{});
        try writer.print("HTTP/1.1 500 Internal Server Error\r\n", .{});
        try writer.writeAll("Content-Length: 0\r\n\r\n");
        return;
    };

    const now: i64 = @intCast(c.time(null));
    std.log.info("Appending message to INBOX, size={d}", .{email_body.len});
    _ = udb.appendMessage(folder.id, email_body, .{ .recent = true }, now) catch |err| {
        std.log.err("Failed to append message: {}", .{err});
        try writer.print("HTTP/1.1 500 Internal Server Error\r\n", .{});
        try writer.writeAll("Content-Length: 0\r\n\r\n");
        return;
    };

    try writer.print("HTTP/1.1 200 OK\r\n", .{});
    try writer.writeAll("Content-Type: application/json\r\n");
    try writer.writeAll("Content-Length: 20\r\n\r\n");
    try writer.writeAll("{\"status\":\"delivered\"}");
    try writer.flush();
    std.log.info("Email delivered successfully to {s}", .{username});
}

fn writeJsonResponse(writer: anytype, status: u16, body: []const u8) !void {
    try writer.print("HTTP/1.1 {d} OK\r\n", .{status});
    try writer.print("Content-Type: application/json; charset=utf-8\r\n", .{});
    try writer.print("Content-Length: {d}\r\n", .{body.len});
    try writer.writeAll("Connection: close\r\n\r\n");
    try writer.writeAll(body);
    try writer.flush();
}

fn writeNotFound(writer: anytype) !void {
    const body = "{\"error\":\"not found\"}";
    try writer.print("HTTP/1.1 404 Not Found\r\n", .{});
    try writer.print("Content-Type: application/json; charset=utf-8\r\n", .{});
    try writer.print("Content-Length: {d}\r\n", .{body.len});
    try writer.writeAll("Connection: close\r\n\r\n");
    try writer.writeAll(body);
    try writer.flush();
}

fn makeHealthBody() []const u8 {
    return "{\"status\":\"ok\",\"service\":\"yourpost\"}";
}

fn writeUserFolders(writer: anytype, ctx: *ConnCtx, user: []const u8) !void {
    const alloc = ctx.deps.alloc;
    const db_path_str = try std.fmt.allocPrint(alloc, "{s}/mailboxes/{s}.db", .{ ctx.deps.data_dir, user });
    defer alloc.free(db_path_str);
    const db_path = try alloc.dupeZ(u8, db_path_str);
    defer alloc.free(db_path);
    var udb = try UserDb.open(alloc, db_path);
    defer udb.close();

    const folders = try udb.listFolders();
    defer for (folders) |folder| alloc.free(folder.name);

    try writer.print("HTTP/1.1 200 OK\r\n", .{});
    try writer.print("Content-Type: application/json; charset=utf-8\r\n", .{});
    try writer.writeAll("Connection: close\r\n");
    try writer.writeAll("\r\n");
    try writer.writeAll("{\"folders\":[");

    var first = true;
    for (folders) |folder| {
        if (!first) try writer.writeAll(",");
        first = false;
        try writer.print("{{\"id\":{d},\"name\":\"{s}\"}}", .{ folder.id, folder.name });
    }

    try writer.writeAll("]}");
    try writer.flush();
}

fn endsWith(value: []const u8, suffix: []const u8) bool {
    return value.len >= suffix.len and std.mem.eql(u8, value[value.len - suffix.len ..], suffix);
}
