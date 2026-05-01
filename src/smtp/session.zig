const std = @import("std");
const UserDb = @import("../storage/user_db.zig").UserDb;
const GlobalDb = @import("../storage/global_db.zig").GlobalDb;

const State = enum { greeting, ehlo, auth, mail_from, rcpt_to, data, done };

const MAX_RECIPIENTS = 100;
const MAX_LINE = 4096;

pub const Deps = struct {
    global_db: *GlobalDb,
    alloc: std.mem.Allocator,
    hostname: []const u8,
    data_dir: []const u8,
    max_size: usize,

    // Outgoing SMTP relay configuration
    relay_host: ?[]const u8,
    relay_port: u16,
    relay_user: ?[]const u8,
    relay_password: ?[]const u8,
    relay_use_tls: bool,
};

pub fn run(
    reader: anytype,
    writer: anytype,
    deps: Deps,
) !void {
    const alloc = deps.alloc;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    try writer.print("220 {s} ESMTP yourpost\r\n", .{deps.hostname});
    try writer.flush();

    var state: State = .greeting;
    var authenticated = false;
    var mail_from: []u8 = &.{};
    var recipients = std.ArrayList([]const u8){ .items = &.{}, .capacity = 0 };
    var body = std.ArrayList(u8){ .items = &.{}, .capacity = 0 };

    const line_buf: [MAX_LINE]u8 = undefined;

    while (state != .done) {
        const raw = reader.takeDelimiterInclusive('\n') catch break;
        const line = std.mem.trimEnd(u8, raw, "\r\n");
        // Don't skip empty lines - they are important in DATA state (blank line separator)

        const verb_end = std.mem.indexOfScalar(u8, line, ' ') orelse line.len;
        var verb_buf: [12]u8 = undefined;
        const verb = toUpperBuf(line[0..@min(verb_end, verb_buf.len)], &verb_buf);

        if (state == .data) {
            if (std.mem.eql(u8, line, ".")) {
                std.log.info("DATA complete, body length: {d} bytes", .{body.items.len});
                std.log.info("Body preview: '{s}'", .{body.items[0..@min(200, body.items.len)]});
                try deliverMessage(a, deps, mail_from, recipients.items, body.items);
                try writer.writeAll("250 OK\r\n");
                try writer.flush();
                state = .ehlo;
                _ = arena.reset(.retain_capacity);
                recipients.clearRetainingCapacity();
                body.clearRetainingCapacity();
            } else {
                // Handle dot-stuffing: if line starts with '.', remove the first dot
                const content = if (line.len > 0 and line[0] == '.') line[1..] else line;

                std.log.info("DATA line: len={d}, content='{s}'", .{ content.len, content });

                // Append the content (empty for blank line)
                try body.appendSlice(a, content);

                // Append CRLF - for blank line, this creates proper \r\n\r\n separator
                try body.appendSlice(a, "\r\n");

                if (body.items.len > deps.max_size) {
                    try writer.writeAll("552 Message too large\r\n");
                    try writer.flush();
                    state = .ehlo;
                    _ = arena.reset(.retain_capacity);
                }
            }
            continue;
        }

        // AUTH LOGIN two-step
        if (std.mem.eql(u8, verb, "AUTH")) {
            const args = if (verb_end < line.len) line[verb_end + 1 ..] else "";
            const mech_end = std.mem.indexOfScalar(u8, args, ' ') orelse args.len;
            const mech = args[0..mech_end];

            if (std.ascii.eqlIgnoreCase(mech, "PLAIN")) {
                const encoded = if (mech_end < args.len) args[mech_end + 1 ..] else blk: {
                    try writer.writeAll("334 \r\n");
                    try writer.flush();
                    const r = reader.takeDelimiterInclusive('\n') catch break;
                    break :blk std.mem.trimEnd(u8, r, "\r\n");
                };
                if (try authPlain(deps.global_db, encoded)) {
                    authenticated = true;
                    try writer.writeAll("235 Authentication successful\r\n");
                } else {
                    try writer.writeAll("535 Authentication failed\r\n");
                }
                try writer.flush();
            } else {
                try writer.writeAll("504 AUTH mechanism not supported\r\n");
                try writer.flush();
            }
            continue;
        }

        if (std.mem.eql(u8, verb, "EHLO") or std.mem.eql(u8, verb, "HELO")) {
            _ = line_buf[0]; // silence unused
            try writer.print("250-{s}\r\n", .{deps.hostname});
            try writer.writeAll("250-SIZE 26214400\r\n");
            try writer.writeAll("250-AUTH PLAIN LOGIN\r\n");
            try writer.writeAll("250-STARTTLS\r\n");
            try writer.writeAll("250 8BITMIME\r\n");
            try writer.flush();
            state = .ehlo;
        } else if (std.mem.eql(u8, verb, "MAIL")) {
            const addr = extractAddr(line) orelse {
                try writer.writeAll("501 Syntax error\r\n");
                try writer.flush();
                continue;
            };
            mail_from = try a.dupe(u8, addr);
            try writer.writeAll("250 OK\r\n");
            try writer.flush();
            state = .mail_from;
        } else if (std.mem.eql(u8, verb, "RCPT")) {
            if (state != .mail_from and state != .rcpt_to) {
                try writer.writeAll("503 Bad sequence\r\n");
                try writer.flush();
                continue;
            }
            const addr = extractAddr(line) orelse {
                try writer.writeAll("501 Syntax error\r\n");
                try writer.flush();
                continue;
            };
            // Accept all recipients - routing will happen at delivery time
            // This allows both local and external recipients
            try recipients.append(a, try a.dupe(u8, addr));
            try writer.writeAll("250 OK\r\n");
            try writer.flush();
            state = .rcpt_to;
            try recipients.append(a, try a.dupe(u8, addr));
            try writer.writeAll("250 OK\r\n");
            try writer.flush();
            state = .rcpt_to;
        } else if (std.mem.eql(u8, verb, "DATA")) {
            if (state != .rcpt_to) {
                try writer.writeAll("503 Bad sequence\r\n");
                try writer.flush();
                continue;
            }
            try writer.writeAll("354 Start input; end with <CRLF>.<CRLF>\r\n");
            try writer.flush();
            state = .data;
        } else if (std.mem.eql(u8, verb, "RSET")) {
            state = .ehlo;
            mail_from = &.{};
            recipients.clearRetainingCapacity();
            body.clearRetainingCapacity();
            try writer.writeAll("250 OK\r\n");
            try writer.flush();
        } else if (std.mem.eql(u8, verb, "NOOP")) {
            try writer.writeAll("250 OK\r\n");
            try writer.flush();
        } else if (std.mem.eql(u8, verb, "STARTTLS")) {
            try writer.writeAll("454 TLS not available\r\n");
            try writer.flush();
        } else if (std.mem.eql(u8, verb, "QUIT")) {
            try writer.print("221 {s} closing\r\n", .{deps.hostname});
            try writer.flush();
            state = .done;
        } else if (std.mem.eql(u8, verb, "VRFY") or std.mem.eql(u8, verb, "EXPN")) {
            try writer.writeAll("252 Cannot verify\r\n");
            try writer.flush();
        } else {
            try writer.writeAll("500 Unknown command\r\n");
            try writer.flush();
        }
    }
}

fn deliverMessage(alloc: std.mem.Allocator, deps: Deps, from: []const u8, rcpts: [][]const u8, body: []const u8) !void {
    // Separate local and external recipients
    var local_rcpts = std.ArrayList([]const u8){ .items = &.{}, .capacity = 0 };
    defer local_rcpts.deinit(alloc);
    var external_rcpts = std.ArrayList([]const u8){ .items = &.{}, .capacity = 0 };
    defer external_rcpts.deinit(alloc);

    for (rcpts) |rcpt| {
        if (try deps.global_db.userExists(rcpt)) {
            try local_rcpts.append(alloc, rcpt);
        } else {
            try external_rcpts.append(alloc, rcpt);
        }
    }

    // Deliver to local recipients
    const now: i64 = 0; // TODO: get actual timestamp
    for (local_rcpts.items) |rcpt| {
        const db_path_str = try std.fmt.allocPrint(alloc, "{s}/mailboxes/{s}.db", .{ deps.data_dir, rcpt });
        defer alloc.free(db_path_str);
        const db_path = try alloc.dupeZ(u8, db_path_str);
        defer alloc.free(db_path);
        var udb = UserDb.open(alloc, db_path) catch continue;
        defer udb.close();
        const folder = (try udb.getFolderByName("INBOX")) orelse continue;
        _ = udb.appendMessage(folder.id, body, .{ .recent = true }, now) catch continue;
    }

    // Send to external recipients via relay if configured
    if (external_rcpts.items.len > 0) {
        if (deps.relay_host != null) {
            try sendViaRelay(deps, from, external_rcpts.items, body);
        } else {
            std.log.warn("No relay configured for external recipients", .{});
        }
    }
}

// SMTP relay not fully implemented yet
fn sendViaRelay(
    deps: Deps,
    from: []const u8,
    rcpts: [][]const u8,
    body: []const u8,
) !void {
    _ = from;
    _ = rcpts;
    _ = body;
    const relay_host = deps.relay_host orelse return;
    std.log.info("Sending via relay {s}:{d}", .{ relay_host, deps.relay_port });
}

fn authPlain(gdb: *GlobalDb, encoded: []const u8) !bool {
    var decoded_buf: [512]u8 = undefined;
    std.base64.standard.Decoder.decode(&decoded_buf, encoded) catch return false;
    const decoded_len = @as(usize, 512); // actual decoded length unknown, use buffer size
    const decoded: []u8 = decoded_buf[0..decoded_len];
    // format: \0username\0password  or  authzid\0username\0password
    const sep1 = std.mem.indexOfScalar(u8, decoded, 0) orelse return false;
    const rest = decoded[sep1 + 1 ..];
    const sep2 = std.mem.indexOfScalar(u8, rest, 0) orelse return false;
    const username = rest[0..sep2];
    const password = rest[sep2 + 1 ..];
    return gdb.authenticate(username, password);
}

fn extractAddr(line: []const u8) ?[]const u8 {
    const lt = std.mem.indexOfScalar(u8, line, '<') orelse return null;
    const gt = std.mem.indexOfScalarPos(u8, line, lt, '>') orelse return null;
    return line[lt + 1 .. gt];
}

fn toUpperBuf(src: []const u8, buf: []u8) []const u8 {
    const n = @min(src.len, buf.len);
    for (src[0..n], 0..) |ch, i| buf[i] = std.ascii.toUpper(ch);
    return buf[0..n];
}
