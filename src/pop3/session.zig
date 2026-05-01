const std = @import("std");
const UserDb = @import("../storage/user_db.zig").UserDb;
const GlobalDb = @import("../storage/global_db.zig").GlobalDb;

const State = enum { authorization, transaction, update };

pub const Deps = struct {
    global_db: *GlobalDb,
    alloc: std.mem.Allocator,
    hostname: []const u8,
    data_dir: []const u8,
};

pub fn run(reader: anytype, writer: anytype, deps: Deps) !void {
    const alloc = deps.alloc;

    try writer.print("+OK {s} POP3 yourpost\r\n", .{deps.hostname});
    try writer.flush();

    var state: State = .authorization;
    var username: []u8 = &.{};
    var udb_opt: ?UserDb = null;
    defer if (udb_opt) |*u| u.close();

    var deleted = std.AutoHashMap(u32, void).init(alloc);
    defer deleted.deinit();

    const line_buf: [2048]u8 = undefined;

    while (true) {
        const raw = reader.takeDelimiterInclusive('\n') catch break;
        const line = std.mem.trimEnd(u8, raw, "\r\n");
        if (line.len == 0) continue;

        const sp = std.mem.indexOfScalar(u8, line, ' ');
        var vbuf: [8]u8 = undefined;
        const vlen = @min(sp orelse line.len, vbuf.len);
        for (line[0..vlen], 0..) |ch, i| vbuf[i] = std.ascii.toUpper(ch);
        const verb = vbuf[0..vlen];
        const arg = if (sp) |s| std.mem.trimStart(u8, line[s + 1 ..], " ") else "";

        _ = line_buf[0];

        switch (state) {
            .authorization => {
                if (std.mem.eql(u8, verb, "USER")) {
                    username = try alloc.dupe(u8, arg);
                    try writer.writeAll("+OK\r\n");
                    try writer.flush();
                } else if (std.mem.eql(u8, verb, "PASS")) {
                    if (username.len == 0) {
                        try writer.writeAll("-ERR No username\r\n");
                        try writer.flush();
                        continue;
                    }
                    if (!try deps.global_db.authenticate(username, arg)) {
                        try writer.writeAll("-ERR Invalid credentials\r\n");
                        try writer.flush();
                        continue;
                    }
                    const db_path_str = try std.fmt.allocPrint(alloc, "{s}/mailboxes/{s}.db",
                        .{ deps.data_dir, username });
                    defer alloc.free(db_path_str);
                    const db_path = try alloc.dupeZ(u8, db_path_str);
                    defer alloc.free(db_path);
                    udb_opt = UserDb.open(alloc, db_path) catch {
                        try writer.writeAll("-ERR Mailbox unavailable\r\n");
                        try writer.flush();
                        continue;
                    };
                    try writer.writeAll("+OK Maildrop ready\r\n");
                    try writer.flush();
                    state = .transaction;
                } else if (std.mem.eql(u8, verb, "QUIT")) {
                    try writer.writeAll("+OK\r\n");
                    try writer.flush();
                    return;
                } else {
                    try writer.writeAll("-ERR Unknown command\r\n");
                    try writer.flush();
                }
            },

            .transaction => {
                const udb = &udb_opt.?;
                if (std.mem.eql(u8, verb, "STAT")) {
                    const folder = (try udb.getFolderByName("INBOX")) orelse {
                        try writer.writeAll("-ERR No INBOX\r\n");
                        try writer.flush();
                        continue;
                    };
                    const msgs = try udb.listMessages(folder.id);
                    var total_size: usize = 0;
                    var count: u32 = 0;
                    for (msgs) |m| {
                        if (!deleted.contains(m.uid)) {
                            count += 1;
                            total_size += m.size;
                        }
                    }
                    try writer.print("+OK {d} {d}\r\n", .{ count, total_size });
                    try writer.flush();
                } else if (std.mem.eql(u8, verb, "LIST")) {
                    const folder = (try udb.getFolderByName("INBOX")) orelse {
                        try writer.writeAll("-ERR No INBOX\r\n");
                        try writer.flush();
                        continue;
                    };
                    const msgs = try udb.listMessages(folder.id);
                    if (arg.len > 0) {
                        const n = std.fmt.parseInt(u32, arg, 10) catch {
                            try writer.writeAll("-ERR Invalid number\r\n");
                            try writer.flush();
                            continue;
                        };
                        for (msgs, 1..) |m, i| {
                            if (i == n and !deleted.contains(m.uid)) {
                                try writer.print("+OK {d} {d}\r\n", .{ n, m.size });
                                try writer.flush();
                                break;
                            }
                        } else {
                            try writer.writeAll("-ERR No such message\r\n");
                            try writer.flush();
                        }
                    } else {
                        try writer.writeAll("+OK\r\n");
                        for (msgs, 1..) |m, i| {
                            if (!deleted.contains(m.uid)) {
                                try writer.print("{d} {d}\r\n", .{ i, m.size });
                            }
                        }
                        try writer.writeAll(".\r\n");
                        try writer.flush();
                    }
                } else if (std.mem.eql(u8, verb, "RETR")) {
                    const n = std.fmt.parseInt(usize, arg, 10) catch 0;
                    const folder = (try udb.getFolderByName("INBOX")) orelse {
                        try writer.writeAll("-ERR No INBOX\r\n");
                        try writer.flush();
                        continue;
                    };
                    const msgs = try udb.listMessages(folder.id);
                    if (n == 0 or n > msgs.len or deleted.contains(msgs[n - 1].uid)) {
                        try writer.writeAll("-ERR No such message\r\n");
                        try writer.flush();
                        continue;
                    }
                    const msg = msgs[n - 1];
                    try writer.print("+OK {d} octets\r\n", .{msg.size});
                    try writer.writeAll(msg.raw);
                    try writer.writeAll("\r\n.\r\n");
                    try writer.flush();
                } else if (std.mem.eql(u8, verb, "DELE")) {
                    const n = std.fmt.parseInt(usize, arg, 10) catch 0;
                    const folder = (try udb.getFolderByName("INBOX")) orelse {
                        try writer.writeAll("-ERR No INBOX\r\n");
                        try writer.flush();
                        continue;
                    };
                    const msgs = try udb.listMessages(folder.id);
                    if (n == 0 or n > msgs.len) {
                        try writer.writeAll("-ERR No such message\r\n");
                        try writer.flush();
                        continue;
                    }
                    try deleted.put(msgs[n - 1].uid, {});
                    try writer.writeAll("+OK\r\n");
                    try writer.flush();
                } else if (std.mem.eql(u8, verb, "UIDL")) {
                    const folder = (try udb.getFolderByName("INBOX")) orelse {
                        try writer.writeAll("-ERR No INBOX\r\n");
                        try writer.flush();
                        continue;
                    };
                    const msgs = try udb.listMessages(folder.id);
                    if (arg.len > 0) {
                        const n = std.fmt.parseInt(usize, arg, 10) catch 0;
                        if (n == 0 or n > msgs.len or deleted.contains(msgs[n - 1].uid)) {
                            try writer.writeAll("-ERR No such message\r\n");
                            try writer.flush();
                            continue;
                        }
                        try writer.print("+OK {d} {d}\r\n", .{ n, msgs[n - 1].uid });
                        try writer.flush();
                    } else {
                        try writer.writeAll("+OK\r\n");
                        for (msgs, 1..) |m, i| {
                            if (!deleted.contains(m.uid)) {
                                try writer.print("{d} {d}\r\n", .{ i, m.uid });
                            }
                        }
                        try writer.writeAll(".\r\n");
                        try writer.flush();
                    }
                } else if (std.mem.eql(u8, verb, "TOP")) {
                    // TOP msg n: headers + blank line + n body lines
                    var it = std.mem.tokenizeScalar(u8, arg, ' ');
                    const msg_s = it.next() orelse "0";
                    const n_s = it.next() orelse "0";
                    const msg_n = std.fmt.parseInt(usize, msg_s, 10) catch 0;
                    const n_lines = std.fmt.parseInt(usize, n_s, 10) catch 0;
                    const folder = (try udb.getFolderByName("INBOX")) orelse {
                        try writer.writeAll("-ERR No INBOX\r\n");
                        try writer.flush();
                        continue;
                    };
                    const msgs = try udb.listMessages(folder.id);
                    if (msg_n == 0 or msg_n > msgs.len or deleted.contains(msgs[msg_n - 1].uid)) {
                        try writer.writeAll("-ERR No such message\r\n");
                        try writer.flush();
                        continue;
                    }
                    const msg_raw = msgs[msg_n - 1].raw;
                    try writer.writeAll("+OK\r\n");
                    // find end of headers
                    const hdr_end = std.mem.indexOf(u8, msg_raw, "\r\n\r\n") orelse msg_raw.len;
                    try writer.writeAll(msg_raw[0..hdr_end]);
                    try writer.writeAll("\r\n\r\n");
                    if (n_lines > 0 and hdr_end + 4 < msg_raw.len) {
                        var body_it = std.mem.splitSequence(u8, msg_raw[hdr_end + 4 ..], "\r\n");
                        var count: usize = 0;
                        while (body_it.next()) |body_line| {
                            if (count >= n_lines) break;
                            try writer.writeAll(body_line);
                            try writer.writeAll("\r\n");
                            count += 1;
                        }
                    }
                    try writer.writeAll(".\r\n");
                    try writer.flush();
                } else if (std.mem.eql(u8, verb, "NOOP")) {
                    try writer.writeAll("+OK\r\n");
                    try writer.flush();
                } else if (std.mem.eql(u8, verb, "RSET")) {
                    deleted.clearRetainingCapacity();
                    try writer.writeAll("+OK\r\n");
                    try writer.flush();
                } else if (std.mem.eql(u8, verb, "QUIT")) {
                    state = .update;
                    break;
                } else {
                    try writer.writeAll("-ERR Unknown command\r\n");
                    try writer.flush();
                }
            },

            .update => break,
        }
    }

    // UPDATE: hard-delete marked messages
    if (udb_opt) |*udb| {
        if (deleted.count() > 0) {
            if (try udb.getFolderByName("INBOX")) |folder| {
                const msgs = try udb.listMessages(folder.id);
                for (msgs) |m| {
                    if (deleted.contains(m.uid)) {
                        var flags = m.flags;
                        flags.deleted = true;
                        udb.storeFlags(folder.id, m.uid, flags) catch {};
                    }
                }
                _ = udb.expunge(folder.id) catch &.{};
            }
        }
    }
    try writer.writeAll("+OK yourpost POP3 server signing off\r\n");
    try writer.flush();
}
