const std = @import("std");
const c = @cImport({
    @cInclude("time.h");
    @cInclude("sys/stat.h");
});
const GlobalDb = @import("../db/global.zig").GlobalDb;
const user_db = @import("../db/user.zig");
const UserDb = user_db.UserDb;

pub const Deps = struct {
    global_db: *GlobalDb,
    alloc: std.mem.Allocator,
    hostname: []const u8,
    data_dir: []const u8,
    api_port: u16,
    service_port: u16,
    service_token: ?[]const u8,
    jwt_secret: []const u8,
    io: std.Io,
};

const JwtClaims = struct {
    email: []const u8,
    role: []const u8,
};

const base64url = std.base64.Base64Encoder.init(std.base64.url_safe_alphabet_chars, null);

fn base64urlEncode(alloc: std.mem.Allocator, data: []const u8) ![]u8 {
    const len = std.base64.Base64Encoder.calcSize(data.len);
    const buf = try alloc.alloc(u8, len);
    const result = base64url.encode(buf, data);
    return buf[0..result.len];
}

fn base64urlDecode(alloc: std.mem.Allocator, encoded: []const u8) ![]u8 {
    // Add padding if needed
    const pad = (4 - encoded.len % 4) % 4;
    const padded = try alloc.alloc(u8, encoded.len + pad);
    defer alloc.free(padded);
    @memcpy(padded[0..encoded.len], encoded);
    for (0..pad) |i| padded[encoded.len + i] = '=';
    // Replace url-safe chars with standard base64
    for (padded) |*ch| {
        if (ch.* == '-') ch.* = '+';
        if (ch.* == '_') ch.* = '/';
    }
    const decoder = std.base64.standard.Decoder;
    const decoded_len = try decoder.calcSizeForSlice(padded);
    const decoded = try alloc.alloc(u8, decoded_len);
    try decoder.decode(decoded, padded);
    return decoded;
}

fn signJwt(alloc: std.mem.Allocator, email: []const u8, role: []const u8, secret: []const u8, exp: i64) ![]u8 {
    const header_json = "{\"alg\":\"HS256\",\"typ\":\"JWT\"}";
    const header_enc = try base64urlEncode(alloc, header_json);
    defer alloc.free(header_enc);

    const payload_json = try std.fmt.allocPrint(alloc,
        "{{\"email\":\"{s}\",\"role\":\"{s}\",\"exp\":{d}}}", .{ email, role, exp });
    defer alloc.free(payload_json);
    const payload_enc = try base64urlEncode(alloc, payload_json);
    defer alloc.free(payload_enc);

    const signing_input = try std.fmt.allocPrint(alloc, "{s}.{s}", .{ header_enc, payload_enc });
    defer alloc.free(signing_input);

    var mac: [32]u8 = undefined;
    std.crypto.auth.hmac.sha2.HmacSha256.create(&mac, signing_input, secret);
    const sig_enc = try base64urlEncode(alloc, &mac);
    defer alloc.free(sig_enc);

    return std.fmt.allocPrint(alloc, "{s}.{s}.{s}", .{ header_enc, payload_enc, sig_enc });
}

fn verifyJwt(alloc: std.mem.Allocator, token: []const u8, secret: []const u8) !JwtClaims {
    // Split token into 3 parts
    var parts: [3][]const u8 = undefined;
    var count: usize = 0;
    var start: usize = 0;
    for (token, 0..) |ch, i| {
        if (ch == '.') {
            if (count >= 2) return error.InvalidToken;
            parts[count] = token[start..i];
            count += 1;
            start = i + 1;
        }
    }
    if (count != 2) return error.InvalidToken;
    parts[2] = token[start..];

    // Verify signature
    const signing_input = token[0 .. parts[0].len + 1 + parts[1].len];
    var mac: [32]u8 = undefined;
    std.crypto.auth.hmac.sha2.HmacSha256.create(&mac, signing_input, secret);
    const expected_sig = try base64urlEncode(alloc, &mac);
    defer alloc.free(expected_sig);
    if (!std.mem.eql(u8, expected_sig, parts[2])) return error.InvalidSignature;

    // Decode payload
    const payload_json = try base64urlDecode(alloc, parts[1]);
    defer alloc.free(payload_json);

    // Parse email and role from payload JSON (simple extraction, no full JSON parser needed)
    const email = extractJsonString(alloc, payload_json, "email") orelse return error.MissingClaims;
    errdefer alloc.free(email);
    const role = extractJsonString(alloc, payload_json, "role") orelse {
        alloc.free(email);
        return error.MissingClaims;
    };

    // Check expiry
    if (extractJsonInt(payload_json, "exp")) |exp| {
        const now = std.time.timestamp();
        if (now > exp) {
            alloc.free(email);
            alloc.free(role);
            return error.TokenExpired;
        }
    }

    return .{ .email = email, .role = role };
}

fn extractJsonString(alloc: std.mem.Allocator, json: []const u8, key: []const u8) ?[]u8 {
    const needle = std.fmt.allocPrint(alloc, "\"{s}\":\"", .{key}) catch return null;
    defer alloc.free(needle);
    const start_pos = std.mem.indexOf(u8, json, needle) orelse return null;
    const val_start = start_pos + needle.len;
    const val_end = std.mem.indexOfScalarPos(u8, json, val_start, '"') orelse return null;
    return alloc.dupe(u8, json[val_start..val_end]) catch null;
}

fn extractJsonInt(json: []const u8, key: []const u8) ?i64 {
    // Find "key": followed by digits
    var buf: [64]u8 = undefined;
    const needle = std.fmt.bufPrint(&buf, "\"{s}\":", .{key}) catch return null;
    const start_pos = std.mem.indexOf(u8, json, needle) orelse return null;
    var val_start = start_pos + needle.len;
    while (val_start < json.len and json[val_start] == ' ') val_start += 1;
    var val_end = val_start;
    while (val_end < json.len and json[val_end] >= '0' and json[val_end] <= '9') val_end += 1;
    return std.fmt.parseInt(i64, json[val_start..val_end], 10) catch null;
}

const ConnCtx = struct {
    stream: std.Io.net.Stream,
    io: std.Io,
    deps: Deps,
};

pub fn listen(io: std.Io, deps: Deps, shutdown_flag: ?*std.atomic.Value(bool)) void {
    if (deps.api_port < 1024 and std.os.linux.geteuid() != 0) {
        std.log.err("API: Cannot bind to privileged port {d} (ports < 1024 require root). Use port > 1024 or run with sudo.", .{deps.api_port});
        return;
    }
    const addr: std.Io.net.IpAddress = .{ .ip4 = std.Io.net.Ip4Address.unspecified(deps.api_port) };
    var server = std.Io.net.IpAddress.listen(&addr, io, .{ .reuse_address = true }) catch |err| {
        if (err == error.AddressInUse) {
            std.log.err("API: Port {d} already in use.", .{deps.api_port});
        } else {
            std.log.err("API: Failed to bind to port {d}: {}", .{ deps.api_port, err });
        }
        return;
    };
    defer server.deinit(io);
    std.log.info("HTTP API listening on :{d}", .{deps.api_port});

    while (true) {
        // Check shutdown flag
        if (shutdown_flag) |flag| {
            if (flag.load(.seq_cst)) {
                std.log.info("API: Stopping accept loop (shutdown requested)", .{});
                return;
            }
        }

        const stream = server.accept(io) catch |err| {
            // Check if this is a shutdown-related error
            if (shutdown_flag) |flag| {
                if (flag.load(.seq_cst)) return;
            }
            std.log.warn("API accept error: {}", .{err});
            continue;
        };
        const ctx = deps.alloc.create(ConnCtx) catch |err| {
            std.log.warn("API alloc: {}", .{err});
            stream.socket.close(io);
            continue;
        };
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

pub fn listenService(io: std.Io, deps: Deps, shutdown_flag: ?*std.atomic.Value(bool)) void {
    if (deps.service_port < 1024 and std.os.linux.geteuid() != 0) {
        std.log.err("Service API: Cannot bind to privileged port {d} (ports < 1024 require root). Use port > 1024 or run with sudo.", .{deps.service_port});
        return;
    }
    const addr: std.Io.net.IpAddress = .{ .ip4 = std.Io.net.Ip4Address.unspecified(deps.service_port) };
    var server = std.Io.net.IpAddress.listen(&addr, io, .{ .reuse_address = true }) catch |err| {
        if (err == error.AddressInUse) {
            std.log.err("Service API: Port {d} already in use.", .{deps.service_port});
        } else {
            std.log.err("Service API: Failed to bind to port {d}: {}", .{ deps.service_port, err });
        }
        return;
    };
    defer server.deinit(io);
    std.log.info("HTTP Service API listening on :{d}", .{deps.service_port});

    while (true) {
        // Check shutdown flag
        if (shutdown_flag) |flag| {
            if (flag.load(.seq_cst)) {
                std.log.info("Service API: Stopping accept loop (shutdown requested)", .{});
                return;
            }
        }

        const stream = server.accept(io) catch |err| {
            // Check if this is a shutdown-related error
            if (shutdown_flag) |flag| {
                if (flag.load(.seq_cst)) return;
            }
            std.log.warn("Service API accept error: {}", .{err});
            continue;
        };
        const ctx = deps.alloc.create(ConnCtx) catch |err| {
            std.log.warn("Service API alloc: {}", .{err});
            stream.socket.close(io);
            continue;
        };
        ctx.* = .{ .stream = stream, .io = io, .deps = deps };
        const t = std.Thread.spawn(.{}, handleServiceConn, .{ctx}) catch |err| {
            std.log.warn("Service API thread spawn: {}", .{err});
            stream.socket.close(io);
            deps.alloc.destroy(ctx);
            continue;
        };
        t.detach();
    }
}

fn handleServiceConn(ctx: *ConnCtx) void {
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

    var content_length: ?usize = null;
    var auth_header: ?[]const u8 = null;
    while (true) {
        const header = reader.takeDelimiterInclusive('\n') catch return;
        if (header.len <= 2) break;
        const trimmed = std.mem.trim(u8, header, "\r\n");
        if (std.mem.startsWith(u8, trimmed, "Content-Length:")) {
            const value = std.mem.trim(u8, trimmed[15..], " ");
            content_length = std.fmt.parseInt(usize, value, 10) catch null;
        }
        if (std.mem.startsWith(u8, trimmed, "Authorization:")) {
            auth_header = std.mem.trim(u8, trimmed[14..], " ");
        }
    }

    if (std.mem.eql(u8, method, "GET") and std.mem.eql(u8, path, "/health")) {
        writeJsonResponse(writer, 200, makeHealthBody()) catch return;
        return;
    }
    if (std.mem.eql(u8, method, "GET") and std.mem.eql(u8, path, "/health/ready")) {
        const body = makeReadyBody();
        const status: u16 = if (std.mem.indexOf(u8, body, "not_ready") != null) 503 else 200;
        writeJsonResponse(writer, status, body) catch return;
        return;
    }
    if (std.mem.eql(u8, method, "GET") and std.mem.eql(u8, path, "/health/live")) {
        writeJsonResponse(writer, 200, makeLiveBody()) catch return;
        return;
    }

    if (std.mem.startsWith(u8, path, "/api/service/")) {
        if (ctx.deps.service_token) |key| {
            const expected = std.fmt.allocPrint(ctx.deps.alloc, "Bearer {s}", .{key}) catch return;
            defer ctx.deps.alloc.free(expected);
            if (auth_header == null or !std.mem.eql(u8, auth_header.?, expected)) {
                std.log.warn("Unauthorized service API request to {s}", .{path});
                writer.print("HTTP/1.1 401 Unauthorized\r\n", .{}) catch return;
                writer.writeAll("Content-Length: 0\r\n\r\n") catch return;
                return;
            }
        }
        const service_path = path[13..];
        if (std.mem.eql(u8, method, "POST") and std.mem.eql(u8, service_path, "/incoming")) {
            handleIncoming(writer, ctx, reader, content_length) catch return;
            return;
        }
        writeNotFound(writer) catch return;
        return;
    }

    writeNotFound(writer) catch return;
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

    var content_length: ?usize = null;
    var auth_header: ?[]const u8 = null;
    while (true) {
        const header = reader.takeDelimiterInclusive('\n') catch return;
        if (header.len <= 2) break;
        const trimmed = std.mem.trim(u8, header, "\r\n");
        if (std.mem.startsWith(u8, trimmed, "Content-Length:")) {
            const value = std.mem.trim(u8, trimmed[15..], " ");
            content_length = std.fmt.parseInt(usize, value, 10) catch null;
        }
        if (std.mem.startsWith(u8, trimmed, "Authorization:")) {
            auth_header = std.mem.trim(u8, trimmed[14..], " ");
        }
    }

    if (std.mem.eql(u8, method, "GET") and std.mem.eql(u8, path, "/health")) {
        writeJsonResponse(writer, 200, makeHealthBody()) catch return;
        return;
    }

    // ── Public: POST /api/v1/auth ─────────────────────────────────────────────
    if (std.mem.eql(u8, method, "POST") and std.mem.eql(u8, path, "/api/v1/auth")) {
        handleAuth(writer, ctx, reader, content_length) catch return;
        return;
    }

    // All other /api/v1/* require a valid JWT — extract and verify once.
    if (std.mem.startsWith(u8, path, "/api/v1/")) {
        const bearer_prefix = "Bearer ";
        const raw_token = if (auth_header) |ah| blk: {
            if (!std.mem.startsWith(u8, ah, bearer_prefix)) break :blk null;
            break :blk ah[bearer_prefix.len..];
        } else null;

        const claims: ?JwtClaims = if (raw_token) |tok|
            verifyJwt(ctx.deps.alloc, tok, ctx.deps.jwt_secret) catch null
        else
            null;

        if (claims == null) {
            writeJsonResponse(writer, 401, "{\"error\":\"unauthorized\"}") catch return;
            return;
        }
        const c_claims = claims.?;
        defer {
            ctx.deps.alloc.free(c_claims.email);
            ctx.deps.alloc.free(c_claims.role);
        }
        const is_admin = std.mem.eql(u8, c_claims.role, "admin");

        // ── Admin layer: /api/v1/admin/* ─────────────────────────────────────
        if (std.mem.startsWith(u8, path, "/api/v1/admin/")) {
            if (!is_admin) {
                writeJsonResponse(writer, 403, "{\"error\":\"forbidden\"}") catch return;
                return;
            }
            // path[14..] strips "/api/v1/admin" keeping the leading slash → "/users", "/users/{email}"
            const admin_path = path[13..];

            if (std.mem.eql(u8, method, "GET") and std.mem.eql(u8, admin_path, "/users")) {
                handleListUsers(writer, ctx) catch return;
                return;
            }
            if (std.mem.eql(u8, method, "POST") and std.mem.eql(u8, admin_path, "/users")) {
                handleCreateUser(writer, ctx, reader, content_length) catch return;
                return;
            }
            if (std.mem.eql(u8, method, "PUT") and std.mem.startsWith(u8, admin_path, "/users/")) {
                const email = admin_path[7..];
                handleUpdateUser(writer, ctx, reader, content_length, email) catch return;
                return;
            }
            if (std.mem.eql(u8, method, "DELETE") and std.mem.startsWith(u8, admin_path, "/users/")) {
                const email = admin_path[7..];
                handleDeactivateUser(writer, ctx, email) catch return;
                return;
            }
            writeNotFound(writer) catch return;
            return;
        }

        // ── User layer: /api/v1/mailboxes/{user}/* ────────────────────────────
        if (std.mem.startsWith(u8, path, "/api/v1/mailboxes/")) {
            // api_path strips "/api/v1" keeping leading slash → "/mailboxes/..."
            const api_path = path[7..];

            if (std.mem.eql(u8, method, "GET")) {
                // GET /api/v1/mailboxes/{user}/folders
                if (std.mem.startsWith(u8, api_path, "/mailboxes/") and endsWith(api_path, "/folders")) {
                    const user = api_path[12 .. api_path.len - 8];
                    if (!is_admin and !std.mem.eql(u8, c_claims.email, user)) {
                        writeJsonResponse(writer, 403, "{\"error\":\"forbidden\"}") catch return;
                        return;
                    }
                    writeUserFolders(writer, ctx, user) catch return;
                    return;
                }
                // GET /api/v1/mailboxes/{user}/messages/{id}  (must precede list check)
                if (std.mem.startsWith(u8, api_path, "/mailboxes/")) {
                    const pattern = "/messages/";
                    if (std.mem.indexOf(u8, api_path, pattern)) |msg_pos| {
                        const user = api_path[12..msg_pos];
                        if (!is_admin and !std.mem.eql(u8, c_claims.email, user)) {
                            writeJsonResponse(writer, 403, "{\"error\":\"forbidden\"}") catch return;
                            return;
                        }
                        const id_str = api_path[msg_pos + pattern.len ..];
                        const msg_id = std.fmt.parseInt(u32, id_str, 10) catch {
                            writeNotFound(writer) catch return;
                            return;
                        };
                        handleGetMessage(writer, ctx, user, msg_id) catch return;
                        return;
                    }
                }
                // GET /api/v1/mailboxes/{user}/messages?folder=...
                if (std.mem.startsWith(u8, api_path, "/mailboxes/") and std.mem.indexOf(u8, api_path, "/messages") != null) {
                    const user_end = std.mem.indexOf(u8, api_path, "/messages") orelse return;
                    const user = api_path[12..user_end];
                    if (!is_admin and !std.mem.eql(u8, c_claims.email, user)) {
                        writeJsonResponse(writer, 403, "{\"error\":\"forbidden\"}") catch return;
                        return;
                    }
                    const folder = if (std.mem.indexOf(u8, path, "folder=")) |pos| blk: {
                        const start = pos + 7;
                        const end = if (std.mem.indexOfPos(u8, path, start, "&")) |e| e else path.len;
                        break :blk path[start..end];
                    } else "INBOX";
                    handleListMessages(writer, ctx, user, folder) catch return;
                    return;
                }
            }

            if (std.mem.eql(u8, method, "POST")) {
                // POST /api/v1/mailboxes/{user}/send
                if (std.mem.startsWith(u8, api_path, "/mailboxes/") and std.mem.endsWith(u8, api_path, "/send")) {
                    const user = api_path[12 .. api_path.len - 5];
                    if (!is_admin and !std.mem.eql(u8, c_claims.email, user)) {
                        writeJsonResponse(writer, 403, "{\"error\":\"forbidden\"}") catch return;
                        return;
                    }
                    handleSendMessage(writer, ctx, reader, content_length, user) catch return;
                    return;
                }
            }

            if (std.mem.eql(u8, method, "DELETE")) {
                // DELETE /api/v1/mailboxes/{user}/messages/{id}
                if (std.mem.startsWith(u8, api_path, "/mailboxes/")) {
                    const pattern = "/messages/";
                    if (std.mem.indexOf(u8, api_path, pattern)) |msg_pos| {
                        const user = api_path[12..msg_pos];
                        if (!is_admin and !std.mem.eql(u8, c_claims.email, user)) {
                            writeJsonResponse(writer, 403, "{\"error\":\"forbidden\"}") catch return;
                            return;
                        }
                        const id_str = api_path[msg_pos + pattern.len ..];
                        handleDeleteMessage(writer, ctx, user, id_str) catch return;
                        return;
                    }
                }
            }
        }

        writeNotFound(writer) catch return;
        return;
    }

    // Root path - show API info
    if (std.mem.eql(u8, path, "/")) {
        writeApiInfo(writer) catch return;
        return;
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

    // Use full email address as username for multi-domain support
    const username = recipient;
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

    const quota = ctx.deps.global_db.getUserQuota(recipient) catch 0;
    if (quota > 0) {
        const used = udb.totalMailboxSize() catch 0;
        if (used >= quota) {
            std.log.warn("Quota exceeded for {s}: {d}/{d} bytes", .{ recipient, used, quota });
            try writer.print("HTTP/1.1 452 Requested action not taken: insufficient mailbox storage\r\n", .{});
            try writer.writeAll("Content-Length: 0\r\n\r\n");
            return;
        }
    }

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

fn handleListUsers(writer: anytype, ctx: *ConnCtx) !void {
    const alloc = ctx.deps.alloc;
    const users = try ctx.deps.global_db.listUsers();
    defer {
        for (users) |u| {
            alloc.free(u.email);
            alloc.free(u.role);
        }
        alloc.free(users);
    }
    var buf = std.ArrayList(u8){ .items = &.{}, .capacity = 0 };
    defer buf.deinit(alloc);
    try buf.appendSlice(alloc, "{\"users\":[");
    for (users, 0..) |u, i| {
        if (i > 0) try buf.append(alloc, ',');
        const item = try std.fmt.allocPrint(alloc, "{{\"email\":\"{s}\",\"role\":\"{s}\",\"active\":{s},\"quota_bytes\":{d}}}", .{
            u.email,
            u.role,
            if (u.active) "true" else "false",
            u.quota_bytes,
        });
        defer alloc.free(item);
        try buf.appendSlice(alloc, item);
    }
    try buf.appendSlice(alloc, "]}");
    try writeJsonResponse(writer, 200, buf.items);
}

fn handleCreateUser(writer: anytype, ctx: *ConnCtx, reader: anytype, content_length: ?usize) !void {
    const alloc = ctx.deps.alloc;
    const body_size = content_length orelse 4096;
    if (body_size > 1024 * 1024) {
        try writer.print("HTTP/1.1 413 Payload Too Large\r\nContent-Length: 0\r\n\r\n", .{});
        return;
    }
    const body = try alloc.alloc(u8, body_size);
    defer alloc.free(body);
    var bytes_read: usize = 0;
    while (bytes_read < body_size) {
        const slice: []u8 = body[bytes_read..];
        var slices: [1][]u8 = .{slice};
        const n = reader.readVec(&slices) catch break;
        if (n == 0) break;
        bytes_read += n;
    }
    const CreateUserReq = struct { email: []const u8, password: []const u8, role: ?[]const u8 };
    const parsed = std.json.parseFromSlice(CreateUserReq, alloc, body[0..bytes_read], .{}) catch {
        try writeJsonResponse(writer, 400, "{\"error\":\"invalid json\"}");
        return;
    };
    defer parsed.deinit();
    const role = if (parsed.value.role) |r| r else "user";
    ctx.deps.global_db.createUser(parsed.value.email, parsed.value.password, role) catch {
        try writeJsonResponse(writer, 409, "{\"error\":\"user already exists\"}");
        return;
    };
    try writeJsonResponse(writer, 201, "{\"status\":\"created\"}");
}

fn handleUpdateUser(writer: anytype, ctx: *ConnCtx, reader: anytype, content_length: ?usize, email: []const u8) !void {
    const alloc = ctx.deps.alloc;
    const body_size = content_length orelse 4096;
    if (body_size > 1024 * 1024) {
        try writer.print("HTTP/1.1 413 Payload Too Large\r\nContent-Length: 0\r\n\r\n", .{});
        return;
    }
    const body = try alloc.alloc(u8, body_size);
    defer alloc.free(body);
    var bytes_read: usize = 0;
    while (bytes_read < body_size) {
        const slice: []u8 = body[bytes_read..];
        var slices: [1][]u8 = .{slice};
        const n = reader.readVec(&slices) catch break;
        if (n == 0) break;
        bytes_read += n;
    }
    const UpdateReq = struct { role: ?[]const u8, quota_bytes: ?i64, active: ?bool };
    const parsed = std.json.parseFromSlice(UpdateReq, alloc, body[0..bytes_read], .{}) catch {
        try writeJsonResponse(writer, 400, "{\"error\":\"invalid json\"}");
        return;
    };
    defer parsed.deinit();
    ctx.deps.global_db.updateUser(email, parsed.value.role, parsed.value.quota_bytes, parsed.value.active) catch {
        try writeJsonResponse(writer, 500, "{\"error\":\"internal error\"}");
        return;
    };
    try writeJsonResponse(writer, 200, "{\"status\":\"updated\"}");
}

fn handleDeactivateUser(writer: anytype, ctx: *ConnCtx, email: []const u8) !void {
    ctx.deps.global_db.deactivateUser(email) catch {
        try writeJsonResponse(writer, 500, "{\"error\":\"internal error\"}");
        return;
    };
    try writeJsonResponse(writer, 200, "{\"status\":\"deactivated\"}");
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

fn writeApiInfo(writer: anytype) !void {
    const body = "{\"service\":\"yourpost\",\"version\":\"1.0.0\",\"endpoints\":{\"health\":\"/health\",\"service\":\"/api/service/*\",\"api\":\"/api/v1/*\"}}";
    try writer.print("HTTP/1.1 200 OK\r\n", .{});
    try writer.print("Content-Type: application/json; charset=utf-8\r\n", .{});
    try writer.print("Content-Length: {d}\r\n", .{body.len});
    try writer.writeAll("Connection: close\r\n\r\n");
    try writer.writeAll(body);
    try writer.flush();
}

fn makeHealthBody() []const u8 {
    // TODO: Add real health checks:
    // - Check database connectivity
    // - Check disk space
    // - Verify server threads are running
    return "{\"status\":\"ok\",\"service\":\"yourpost\",\"version\":\"1.0.0\"}";
}

fn makeReadyBody() []const u8 {
    return "{\"status\":\"ready\",\"service\":\"yourpost\"}";
}

fn makeLiveBody() []const u8 {
    // Liveness check - is the service alive?
    // Basic check that the process is running
    return "{\"status\":\"alive\",\"service\":\"yourpost\",\"uptime\":\"unknown\"}";
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

// Handle user authentication and return JWT token
fn handleAuth(writer: anytype, ctx: *ConnCtx, reader: anytype, content_length: ?usize) !void {
    const alloc = ctx.deps.alloc;
    const body_size = content_length orelse 4096;
    if (body_size > 1024 * 1024) {
        try writer.print("HTTP/1.1 413 Payload Too Large\r\nContent-Length: 0\r\n\r\n", .{});
        return;
    }
    const body = try alloc.alloc(u8, body_size);
    defer alloc.free(body);
    var bytes_read: usize = 0;
    while (bytes_read < body_size) {
        const slice: []u8 = body[bytes_read..];
        var slices: [1][]u8 = .{slice};
        const n = reader.readVec(&slices) catch break;
        if (n == 0) break;
        bytes_read += n;
    }
    const AuthReq = struct { email: []const u8, password: []const u8 };
    const parsed = std.json.parseFromSlice(AuthReq, alloc, body[0..bytes_read], .{}) catch {
        try writeJsonResponse(writer, 400, "{\"error\":\"invalid json\"}");
        return;
    };
    defer parsed.deinit();
    const authenticated = ctx.deps.global_db.authenticate(parsed.value.email, parsed.value.password) catch false;
    if (!authenticated) {
        try writeJsonResponse(writer, 401, "{\"error\":\"invalid credentials\"}");
        return;
    }
    const role = ctx.deps.global_db.getUserRole(parsed.value.email) catch "user";
    defer alloc.free(role);
    const exp = std.time.timestamp() + 86400; // 24h
    const jwt = try signJwt(alloc, parsed.value.email, role, ctx.deps.jwt_secret, exp);
    defer alloc.free(jwt);
    const body = try std.fmt.allocPrint(alloc,
        "{{\"token\":\"{s}\",\"email\":\"{s}\",\"role\":\"{s}\"}}", .{ jwt, parsed.value.email, role });
    defer alloc.free(body);
    try writeJsonResponse(writer, 200, body);
}

// Handle listing messages in a folder
fn handleListMessages(writer: anytype, ctx: *ConnCtx, user: []const u8, folder_name: []const u8) !void {
    const alloc = ctx.deps.alloc;

    // Open user database
    const db_path_str = try std.fmt.allocPrint(alloc, "{s}/mailboxes/{s}.db", .{ ctx.deps.data_dir, user });
    defer alloc.free(db_path_str);
    const db_path = try alloc.dupeZ(u8, db_path_str);
    defer alloc.free(db_path);

    var udb = UserDb.open(alloc, db_path) catch |err| {
        std.log.err("Failed to open user db: {}", .{err});
        try writeJsonResponse(writer, 500, "{\"error\":\"database error\"}");
        return;
    };
    defer udb.close();

    // Get folder
    const folder = udb.getFolderByName(folder_name) catch |err| {
        std.log.err("Failed to get folder: {}", .{err});
        try writeJsonResponse(writer, 404, "{\"error\":\"folder not found\"}");
        return;
    } orelse {
        try writeJsonResponse(writer, 404, "{\"error\":\"folder not found\"}");
        return;
    };

    // List messages in folder
    const messages = udb.listMessages(folder.id) catch |err| {
        std.log.err("Failed to list messages: {}", .{err});
        try writeJsonResponse(writer, 500, "{\"error\":\"database error\"}");
        return;
    };
    defer {
        for (messages) |msg| {
            alloc.free(msg.raw);
        }
        alloc.free(messages);
    }

    // Build JSON response
    var buf = std.ArrayList(u8){ .items = &.{}, .capacity = 0 };
    defer buf.deinit(alloc);
    try buf.appendSlice(alloc, "{\"messages\":[");

    for (messages, 0..) |msg, i| {
        if (i > 0) try buf.append(alloc, ',');

        // Parse basic headers from raw email
        const from = extractHeader(msg.raw, "From:") orelse "Unknown";
        const subject = extractHeader(msg.raw, "Subject:") orelse "(no subject)";
        const date = extractHeader(msg.raw, "Date:") orelse "";

        const item = std.fmt.allocPrint(alloc, "{{\"id\":{d},\"uid\":{d},\"from\":\"{s}\",\"subject\":\"{s}\",\"date\":\"{s}\",\"seen\":{s}}}", .{ msg.uid, msg.uid, from, subject, date, if (msg.flags.seen) "true" else "false" }) catch |err| {
            std.log.err("Failed to format message: {}", .{err});
            continue;
        };
        defer alloc.free(item);
        try buf.appendSlice(alloc, item);
    }

    try buf.appendSlice(alloc, "]}");
    try writeJsonResponse(writer, 200, buf.items);
}

// Handle getting a single message
fn handleGetMessage(writer: anytype, ctx: *ConnCtx, user: []const u8, msg_id: u32) !void {
    const alloc = ctx.deps.alloc;

    // Open user database
    const db_path_str = try std.fmt.allocPrint(alloc, "{s}/mailboxes/{s}.db", .{ ctx.deps.data_dir, user });
    defer alloc.free(db_path_str);
    const db_path = try alloc.dupeZ(u8, db_path_str);
    defer alloc.free(db_path);

    var udb = UserDb.open(alloc, db_path) catch |err| {
        std.log.err("Failed to open user db: {}", .{err});
        try writeJsonResponse(writer, 500, "{\"error\":\"database error\"}");
        return;
    };
    defer udb.close();

    // Get all folders and search for the message
    const folders = udb.listFolders() catch |err| {
        std.log.err("Failed to list folders: {}", .{err});
        try writeJsonResponse(writer, 500, "{\"error\":\"database error\"}");
        return;
    };
    defer for (folders) |f| alloc.free(f.name);

    var message: ?user_db.Message = null;
    for (folders) |folder| {
        if (udb.fetchMessage(folder.id, msg_id)) |msg| {
            message = msg;
            break;
        } else |_| {}
    }

    if (message == null) {
        try writeJsonResponse(writer, 404, "{\"error\":\"message not found\"}");
        return;
    }

    const msg = message.?;
    defer alloc.free(msg.raw);

    // Parse headers
    const from = extractHeader(msg.raw, "From:") orelse "Unknown";
    const to = extractHeader(msg.raw, "To:") orelse "";
    const subject = extractHeader(msg.raw, "Subject:") orelse "(no subject)";
    const date = extractHeader(msg.raw, "Date:") orelse "";
    const content_type = extractHeader(msg.raw, "Content-Type:") orelse "text/plain";

    // Mark as seen
    var flags = msg.flags;
    flags.seen = true;
    udb.storeFlags(0, msg.uid, flags) catch |err| {
        std.log.warn("Failed to mark message as seen: {}", .{err});
    };

    // Build JSON response - escape quotes in raw body
    var body_buf = try std.ArrayList(u8).initCapacity(std.heap.page_allocator, 0);
    defer body_buf.deinit(std.heap.page_allocator);
    try body_buf.appendSlice(std.heap.page_allocator, "{\"id\":");
    const id_str = std.fmt.allocPrint(alloc, "{}", .{msg.uid}) catch |err| {
        std.log.err("OOM: {}", .{err});
        return;
    };
    defer alloc.free(id_str);
    try body_buf.appendSlice(std.heap.page_allocator, id_str);
    try body_buf.appendSlice(std.heap.page_allocator, ",\"uid\":");
    try body_buf.appendSlice(std.heap.page_allocator, id_str);
    try body_buf.appendSlice(std.heap.page_allocator, ",\"from\":\"");
    try appendJsonEscaped(&body_buf, from);
    try body_buf.appendSlice(std.heap.page_allocator, ",\"to\":\"");
    try appendJsonEscaped(&body_buf, to);
    try body_buf.appendSlice(std.heap.page_allocator, ",\"subject\":\"");
    try appendJsonEscaped(&body_buf, subject);
    try body_buf.appendSlice(std.heap.page_allocator, ",\"date\":\"");
    try appendJsonEscaped(&body_buf, date);
    try body_buf.appendSlice(std.heap.page_allocator, ",\"body\":\"");
    try appendJsonEscaped(&body_buf, msg.raw);
    try body_buf.appendSlice(std.heap.page_allocator, ",\"content_type\":\"");
    try appendJsonEscaped(&body_buf, content_type);
    try body_buf.appendSlice(std.heap.page_allocator, ",\"seen\":true}");

    try writeJsonResponse(writer, 200, body_buf.items);
}

// Helper: Append JSON-escaped string to ArrayList
fn appendJsonEscaped(list: *std.ArrayList(u8), str: []const u8) !void {
    for (str) |ch| {
        switch (ch) {
            '\\' => try list.appendSlice(std.heap.page_allocator, "\\\\"),
            '"' => try list.appendSlice(std.heap.page_allocator, "\\\""),
            '\n' => try list.appendSlice(std.heap.page_allocator, "\\n"),
            '\r' => try list.appendSlice(std.heap.page_allocator, "\\r"),
            '\t' => try list.appendSlice(std.heap.page_allocator, "\\t"),
            else => try list.append(std.heap.page_allocator, ch),
        }
    }
}

// Handle sending a message (via SMTP relay or local delivery)
fn handleSendMessage(writer: anytype, ctx: *ConnCtx, reader: anytype, content_length: ?usize, user: []const u8) !void {
    const alloc = ctx.deps.alloc;
    const body_size = content_length orelse 1024 * 1024; // Default 1MB
    if (body_size > 10 * 1024 * 1024) { // 10MB max
        try writeJsonResponse(writer, 413, "{\"error\":\"message too large\"}");
        return;
    }

    const body = try alloc.alloc(u8, body_size);
    defer alloc.free(body);
    var bytes_read: usize = 0;
    while (bytes_read < body_size) {
        const slice: []u8 = body[bytes_read..];
        var slices: [1][]u8 = .{slice};
        const n = reader.readVec(&slices) catch break;
        if (n == 0) break;
        bytes_read += n;
    }

    const SendReq = struct { to: []const u8, subject: []const u8, body: []const u8 };
    const parsed = std.json.parseFromSlice(SendReq, alloc, body[0..bytes_read], .{}) catch {
        try writeJsonResponse(writer, 400, "{\"error\":\"invalid json\"}");
        return;
    };
    defer parsed.deinit();

    // Open user's database to verify user exists
    const db_path_str = try std.fmt.allocPrint(alloc, "{s}/mailboxes/{s}.db", .{ ctx.deps.data_dir, user });
    defer alloc.free(db_path_str);
    const db_path = try alloc.dupeZ(u8, db_path_str);
    defer alloc.free(db_path);

    var udb = UserDb.open(alloc, db_path) catch |err| {
        std.log.err("Failed to open user db: {}", .{err});
        try writeJsonResponse(writer, 500, "{\"error\":\"database error\"}");
        return;
    };
    defer udb.close();

    // TODO: Implement actual email sending via SMTP relay or local delivery
    std.log.info("Send email from {s} to {s}: {s}", .{ user, parsed.value.to, parsed.value.subject });

    // If sending to local user, deliver locally
    if (parsed.value.to[parsed.value.to.len - 1] == 'm' and std.mem.indexOf(u8, parsed.value.to, "@") != null) {
        // Simple check if it's a local domain - in production, check against configured domains
        const recipient = parsed.value.to;
        const recipient_db_path_str = try std.fmt.allocPrint(alloc, "{s}/mailboxes/{s}.db", .{ ctx.deps.data_dir, recipient });
        defer alloc.free(recipient_db_path_str);
        const recipient_db_path = try alloc.dupeZ(u8, recipient_db_path_str);
        defer alloc.free(recipient_db_path);

        var recipient_udb = UserDb.open(alloc, recipient_db_path) catch |err| {
            std.log.warn("Recipient db not found: {}", .{err});
            try writeJsonResponse(writer, 200, "{\"status\":\"queued\"}");
            return;
        };
        defer recipient_udb.close();

        const now: i64 = @intCast(c.time(null));
        const email_content = try std.fmt.allocPrint(alloc,
            \\From: {s}
            \\To: {s}
            \\Subject: {s}
            \\Date: {d}
            \\
            \\{s}
        , .{ user, parsed.value.to, parsed.value.subject, now, parsed.value.body });
        defer alloc.free(email_content);

        const folder = recipient_udb.getFolderByName("INBOX") catch |err| {
            std.log.err("Failed to get INBOX: {}", .{err});
            try writeJsonResponse(writer, 500, "{\"error\":\"delivery failed\"}");
            return;
        } orelse {
            try writeJsonResponse(writer, 500, "{\"error\":\"inbox not found\"}");
            return;
        };

        _ = recipient_udb.appendMessage(folder.id, email_content, .{ .recent = true }, now) catch |err| {
            std.log.err("Failed to deliver message: {}", .{err});
            try writeJsonResponse(writer, 500, "{\"error\":\"delivery failed\"}");
            return;
        };
    }

    try writeJsonResponse(writer, 200, "{\"status\":\"sent\"}");
}

// Helper: Extract header value from raw email
fn extractHeader(raw: []const u8, header: []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, raw, header)) |pos| {
        const start = pos + header.len;
        var end = start;
        while (end < raw.len and raw[end] != '\r' and raw[end] != '\n') {
            end += 1;
        }
        return std.mem.trim(u8, raw[start..end], " \t");
    }
    return null;
}

// Handle deleting a message (mark as deleted)
fn handleDeleteMessage(writer: anytype, ctx: *ConnCtx, user: []const u8, msg_id_str: []const u8) !void {
    const alloc = ctx.deps.alloc;
    const msg_id = std.fmt.parseInt(u32, msg_id_str, 10) catch {
        try writeJsonResponse(writer, 400, "{\"error\":\"invalid message id\"}");
        return;
    };

    const db_path_str = try std.fmt.allocPrint(alloc, "{s}/mailboxes/{s}.db", .{ ctx.deps.data_dir, user });
    defer alloc.free(db_path_str);
    const db_path = try alloc.dupeZ(u8, db_path_str);
    defer alloc.free(db_path);

    var udb = UserDb.open(alloc, db_path) catch |err| {
        std.log.err("Failed to open user db: {}", .{err});
        try writeJsonResponse(writer, 500, "{\"error\":\"database error\"}");
        return;
    };
    defer udb.close();

    // Get all folders and search for the message
    const folders = udb.listFolders() catch |err| {
        std.log.err("Failed to list folders: {}", .{err});
        try writeJsonResponse(writer, 500, "{\"error\":\"database error\"}");
        return;
    };
    defer for (folders) |f| alloc.free(f.name);

    var message_found = false;
    for (folders) |folder| {
        if (udb.fetchMessage(folder.id, msg_id) catch null) |msg| {
            defer alloc.free(msg.raw);
            var flags = msg.flags;
            flags.deleted = true;
            udb.storeFlags(folder.id, msg_id, flags) catch |err| {
                std.log.err("Failed to mark message as deleted: {}", .{err});
                try writeJsonResponse(writer, 500, "{\"error\":\"delete failed\"}");
                return;
            };
            message_found = true;
            break;
        }
    }

    if (!message_found) {
        try writeJsonResponse(writer, 404, "{\"error\":\"message not found\"}");
        return;
    }

    try writeJsonResponse(writer, 200, "{\"status\":\"deleted\"}");
}
