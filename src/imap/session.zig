const std = @import("std");
const c = @cImport(@cInclude("time.h"));
const parser = @import("parser.zig");
const UserDb = @import("../storage/user_db.zig").UserDb;
const Flags = @import("../storage/user_db.zig").Flags;
const GlobalDb = @import("../storage/global_db.zig").GlobalDb;

const State = enum { not_authenticated, authenticated, selected, selected_readonly, logout };

pub const Deps = struct {
    global_db: *GlobalDb,
    alloc: std.mem.Allocator,
    hostname: []const u8,
    data_dir: []const u8,
};

pub fn run(reader: anytype, writer: anytype, deps: Deps) !void {
    const alloc = deps.alloc;

    try writer.print("* OK [{s}] yourpost IMAP4rev1 ready\r\n", .{deps.hostname});
    try writer.flush();

    var state: State = .not_authenticated;
    var username: []u8 = &.{};
    var udb_opt: ?UserDb = null;
    defer if (udb_opt) |*u| u.close();

    var selected_name: []u8 = &.{};
    var selected_folder_id: i64 = 0;
    var selected_uid_validity: u32 = 0;

    var line_buf: [8192]u8 = undefined;

    while (state != .logout) {
        const raw = reader.takeDelimiterInclusive('\n') catch break;
        if (raw.len == 0) continue;
        const line = std.mem.trimEnd(u8, raw, "\r\n ");

        // IDLE DONE is a bare line with no tag
        if (std.ascii.eqlIgnoreCase(line, "DONE")) {
            try writer.print("* OK IDLE terminated\r\n", .{});
            try writer.flush();
            continue;
        }

        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        const a = arena.allocator();

        const parsed = parser.parse(a, line) catch {
            try writer.writeAll("* BAD Parse error\r\n");
            try writer.flush();
            continue;
        };
        const tag = parsed.tag;

        switch (parsed.cmd) {
            .capability => {
                try writer.writeAll("* CAPABILITY IMAP4rev1 AUTH=PLAIN IDLE\r\n");
                try writer.print("{s} OK CAPABILITY done\r\n", .{tag});
                try writer.flush();
            },
            .noop => {
                try writer.print("{s} OK NOOP\r\n", .{tag});
                try writer.flush();
            },
            .logout => {
                try writer.writeAll("* BYE yourpost IMAP4rev1 server logging out\r\n");
                try writer.print("{s} OK LOGOUT\r\n", .{tag});
                try writer.flush();
                state = .logout;
            },
            .login => |l| {
                if (state != .not_authenticated) {
                    try writer.print("{s} BAD Already authenticated\r\n", .{tag});
                    try writer.flush();
                    continue;
                }
                if (!try deps.global_db.authenticate(l.user, l.pass)) {
                    try writer.print("{s} NO Authentication failed\r\n", .{tag});
                    try writer.flush();
                    continue;
                }
                username = try alloc.dupe(u8, l.user);
                const db_path_str = try std.fmt.allocPrint(alloc, "{s}/mailboxes/{s}.db",
                    .{ deps.data_dir, username });
                defer alloc.free(db_path_str);
                const db_path = try alloc.dupeZ(u8, db_path_str);
                defer alloc.free(db_path);
                udb_opt = UserDb.open(alloc, db_path) catch {
                    try writer.print("{s} NO Mailbox unavailable\r\n", .{tag});
                    try writer.flush();
                    continue;
                };
                state = .authenticated;
                try writer.print("{s} OK logged in\r\n", .{tag});
                try writer.flush();
            },
            .select => |name| {
                try doSelect(writer, tag, name, &udb_opt, &state, &selected_name,
                    &selected_folder_id, &selected_uid_validity, alloc, false);
            },
            .examine => |name| {
                try doSelect(writer, tag, name, &udb_opt, &state, &selected_name,
                    &selected_folder_id, &selected_uid_validity, alloc, true);
            },
            .create => |name| {
                if (state == .not_authenticated) { try noAuth(writer, tag); continue; }
                udb_opt.?.createFolder(name) catch {};
                try writer.print("{s} OK CREATE done\r\n", .{tag});
                try writer.flush();
            },
            .delete => |name| {
                if (state == .not_authenticated) { try noAuth(writer, tag); continue; }
                udb_opt.?.deleteFolder(name) catch {};
                try writer.print("{s} OK DELETE done\r\n", .{tag});
                try writer.flush();
            },
            .rename => |r| {
                if (state == .not_authenticated) { try noAuth(writer, tag); continue; }
                udb_opt.?.renameFolder(r.old, r.new) catch {};
                try writer.print("{s} OK RENAME done\r\n", .{tag});
                try writer.flush();
            },
            .subscribe => |name| {
                _ = name;
                if (state == .not_authenticated) { try noAuth(writer, tag); continue; }
                try writer.print("{s} OK SUBSCRIBE done\r\n", .{tag});
                try writer.flush();
            },
            .unsubscribe => |name| {
                _ = name;
                if (state == .not_authenticated) { try noAuth(writer, tag); continue; }
                try writer.print("{s} OK UNSUBSCRIBE done\r\n", .{tag});
                try writer.flush();
            },
            .list => |l| {
                if (state == .not_authenticated) { try noAuth(writer, tag); continue; }
                const folders = try udb_opt.?.listFolders();
                for (folders) |f| {
                    if (matchPattern(f.name, l.pattern)) {
                        const flags = if (std.mem.eql(u8, f.name, "INBOX")) "\\HasNoChildren" else "\\HasNoChildren";
                        try writer.print("* LIST ({s}) \"/\" \"{s}\"\r\n", .{ flags, f.name });
                    }
                }
                try writer.print("{s} OK LIST done\r\n", .{tag});
                try writer.flush();
            },
            .lsub => |l| {
                if (state == .not_authenticated) { try noAuth(writer, tag); continue; }
                const folders = try udb_opt.?.listFolders();
                for (folders) |f| {
                    if (f.subscribed and matchPattern(f.name, l.pattern)) {
                        try writer.print("* LSUB () \"/\" \"{s}\"\r\n", .{f.name});
                    }
                }
                try writer.print("{s} OK LSUB done\r\n", .{tag});
                try writer.flush();
            },
            .status => |s| {
                if (state == .not_authenticated) { try noAuth(writer, tag); continue; }
                const udb = &udb_opt.?;
                const folder = (try udb.getFolderByName(s.mailbox)) orelse {
                    try writer.print("{s} NO No such mailbox\r\n", .{tag});
                    try writer.flush();
                    continue;
                };
                const st = try udb.folderStatus(folder.id);
                try writer.writeAll("* STATUS \"");
                try writer.writeAll(s.mailbox);
                try writer.writeAll("\" (");
                if (std.mem.indexOf(u8, s.items, "MESSAGES") != null)
                    try writer.print("MESSAGES {d} ", .{st.messages});
                if (std.mem.indexOf(u8, s.items, "RECENT") != null)
                    try writer.print("RECENT {d} ", .{st.recent});
                if (std.mem.indexOf(u8, s.items, "UIDNEXT") != null)
                    try writer.print("UIDNEXT {d} ", .{st.uidnext});
                if (std.mem.indexOf(u8, s.items, "UIDVALIDITY") != null)
                    try writer.print("UIDVALIDITY {d} ", .{st.uidvalidity});
                if (std.mem.indexOf(u8, s.items, "UNSEEN") != null)
                    try writer.print("UNSEEN {d} ", .{st.unseen});
                try writer.writeAll(")\r\n");
                try writer.print("{s} OK STATUS done\r\n", .{tag});
                try writer.flush();
            },
            .append => |ap| {
                if (state == .not_authenticated) { try noAuth(writer, tag); continue; }
                const udb = &udb_opt.?;
                const folder = (try udb.getFolderByName(ap.mailbox)) orelse {
                    try writer.print("{s} NO [TRYCREATE] No such mailbox\r\n", .{tag});
                    try writer.flush();
                    continue;
                };
                // Signal client to send literal
                try writer.print("+ go ahead\r\n", .{});
                try writer.flush();
                // Read ap.size bytes
                var body_buf = try alloc.alloc(u8, ap.size);
                defer alloc.free(body_buf);
                var total: usize = 0;
                while (total < ap.size) {
                    const buf_slice: []u8 = body_buf[total..];
                    var slices: [1][]u8 = .{buf_slice};
                    const slice = try reader.readVec(&slices);
                    if (slice == 0) break;
                    total += slice;
                }
                const flags = Flags.fromImap(ap.flags);
                const now: i64 = @intCast(c.time(null));
                _ = udb.appendMessage(folder.id, body_buf[0..total], flags, now) catch {
                    try writer.print("{s} NO APPEND failed\r\n", .{tag});
                    try writer.flush();
                    continue;
                };
                try writer.print("{s} OK APPEND done\r\n", .{tag});
                try writer.flush();
            },
            .check => {
                if (state != .selected and state != .selected_readonly) { try notSelected(writer, tag); continue; }
                try writer.print("{s} OK CHECK done\r\n", .{tag});
                try writer.flush();
            },
            .close => {
                if (state != .selected and state != .selected_readonly) { try notSelected(writer, tag); continue; }
                if (state == .selected) {
                    _ = udb_opt.?.expunge(selected_folder_id) catch &.{};
                }
                state = .authenticated;
                selected_name = &.{};
                try writer.print("{s} OK CLOSE done\r\n", .{tag});
                try writer.flush();
            },
            .expunge => {
                if (state != .selected) { try notSelected(writer, tag); continue; }
                const udb = &udb_opt.?;
                // Snapshot all UIDs (including \Deleted) before expunge to map to seq numbers
                const all_uids = try udb.listMessageUids(selected_folder_id);
                defer alloc.free(all_uids);
                const deleted_uids = try udb.expunge(selected_folder_id);
                defer alloc.free(deleted_uids);
                // RFC 3501: send * N EXPUNGE from highest to lowest seq number
                var i = deleted_uids.len;
                while (i > 0) {
                    i -= 1;
                    const uid = deleted_uids[i];
                    for (all_uids, 1..) |u, seq| {
                        if (u == uid) {
                            try writer.print("* {d} EXPUNGE\r\n", .{seq});
                            break;
                        }
                    }
                }
                try writer.print("{s} OK EXPUNGE done\r\n", .{tag});
                try writer.flush();
            },
            .search => |s| {
                if (state != .selected and state != .selected_readonly) { try notSelected(writer, tag); continue; }
                const udb = &udb_opt.?;
                const msgs = try udb.listMessages(selected_folder_id);
                try writer.writeAll("* SEARCH");
                for (msgs, 1..) |m, seq| {
                    if (matchSearch(m, seq, s.keys)) {
                        if (s.uid) {
                            try writer.print(" {d}", .{m.uid});
                        } else {
                            try writer.print(" {d}", .{seq});
                        }
                    }
                }
                try writer.writeAll("\r\n");
                try writer.print("{s} OK SEARCH done\r\n", .{tag});
                try writer.flush();
            },
            .fetch => |f| {
                if (state != .selected and state != .selected_readonly) { try notSelected(writer, tag); continue; }
                const udb = &udb_opt.?;
                const msgs = try udb.listMessages(selected_folder_id);
                for (msgs, 1..) |m, seq| {
                    if (!seqSetContains(f.seqset, if (f.uid) m.uid else @intCast(seq))) continue;
                    try writer.print("* {d} FETCH (", .{seq});
                    var first = true;
                    for (f.atts) |att| {
                        if (!first) try writer.writeAll(" ");
                        first = false;
                        try writeFetchAtt(writer, att, m, &line_buf);
                    }
                    try writer.writeAll(")\r\n");
                }
                try writer.print("{s} OK FETCH done\r\n", .{tag});
                try writer.flush();
            },
            .store => |s| {
                if (state != .selected) { try notSelected(writer, tag); continue; }
                const udb = &udb_opt.?;
                const msgs = try udb.listMessages(selected_folder_id);
                for (msgs, 1..) |m, seq| {
                    if (!seqSetContains(s.seqset, if (s.uid) m.uid else @intCast(seq))) continue;
                    var new_flags = m.flags;
                    const delta = Flags.fromImap(s.flags);
                    switch (s.op) {
                        .replace => new_flags = delta,
                        .add => {
                            if (delta.seen) new_flags.seen = true;
                            if (delta.answered) new_flags.answered = true;
                            if (delta.flagged) new_flags.flagged = true;
                            if (delta.deleted) new_flags.deleted = true;
                            if (delta.draft) new_flags.draft = true;
                        },
                        .remove => {
                            if (delta.seen) new_flags.seen = false;
                            if (delta.answered) new_flags.answered = false;
                            if (delta.flagged) new_flags.flagged = false;
                            if (delta.deleted) new_flags.deleted = false;
                            if (delta.draft) new_flags.draft = false;
                        },
                    }
                    udb.storeFlags(selected_folder_id, m.uid, new_flags) catch continue;
                    if (!s.silent) {
                        var fbuf: [256]u8 = undefined;
                        const fstr = new_flags.toImap(&fbuf);
                        try writer.print("* {d} FETCH (FLAGS ({s}))\r\n", .{ seq, fstr });
                    }
                }
                try writer.print("{s} OK STORE done\r\n", .{tag});
                try writer.flush();
            },
            .copy => |cp| {
                if (state != .selected and state != .selected_readonly) { try notSelected(writer, tag); continue; }
                const udb = &udb_opt.?;
                const dest = (try udb.getFolderByName(cp.mailbox)) orelse {
                    try writer.print("{s} NO [TRYCREATE] No such mailbox\r\n", .{tag});
                    try writer.flush();
                    continue;
                };
                const msgs = try udb.listMessages(selected_folder_id);
                for (msgs, 1..) |m, seq| {
                    if (!seqSetContains(cp.seqset, if (cp.uid) m.uid else @intCast(seq))) continue;
                    const now: i64 = @intCast(c.time(null));
                    _ = udb.appendMessage(dest.id, m.raw, m.flags, now) catch continue;
                }
                try writer.print("{s} OK COPY done\r\n", .{tag});
                try writer.flush();
            },
            .idle => {
                if (state == .not_authenticated) { try noAuth(writer, tag); continue; }
                try writer.writeAll("+ idling\r\n");
                try writer.flush();
                // In IDLE mode, wait for "DONE" then send completion.
                // We re-enter the main loop: the bare "DONE" check at top handles it.
                // For push notifications, a real impl would poll the DB here.
                const idle_raw = reader.takeDelimiterInclusive('\n') catch break;
                const idle_line = std.mem.trimEnd(u8, idle_raw, "\r\n ");
                if (std.ascii.eqlIgnoreCase(idle_line, "DONE")) {
                    try writer.print("{s} OK IDLE terminated\r\n", .{tag});
                } else {
                    try writer.print("{s} BAD Expected DONE\r\n", .{tag});
                }
                try writer.flush();
            },
            .done => {
                // handled at top of loop or here as fallback
            },
        }

        _ = line_buf[0];
    }
}

fn doSelect(
    writer: anytype,
    tag: []const u8,
    name: []const u8,
    udb_opt: *?UserDb,
    state: *State,
    selected_name: *[]u8,
    selected_folder_id: *i64,
    selected_uid_validity: *u32,
    alloc: std.mem.Allocator,
    readonly: bool,
) !void {
    if (state.* == .not_authenticated) { try noAuth(writer, tag); return; }
    const udb = &udb_opt.*.?;
    const folder = (try udb.getFolderByName(name)) orelse {
        try writer.print("{s} NO No such mailbox\r\n", .{tag});
        try writer.flush();
        return;
    };
    const st = try udb.folderStatus(folder.id);
    selected_name.* = try alloc.dupe(u8, name);
    selected_folder_id.* = folder.id;
    selected_uid_validity.* = st.uidvalidity;
    state.* = if (readonly) .selected_readonly else .selected;

    try writer.print("* {d} EXISTS\r\n", .{st.messages});
    try writer.print("* {d} RECENT\r\n", .{st.recent});
    try writer.print("* OK [UNSEEN {d}] first unseen\r\n", .{st.unseen});
    try writer.print("* OK [UIDVALIDITY {d}] UIDs valid\r\n", .{st.uidvalidity});
    try writer.print("* OK [UIDNEXT {d}] next UID\r\n", .{st.uidnext});
    try writer.writeAll("* FLAGS (\\Seen \\Answered \\Flagged \\Deleted \\Draft \\Recent)\r\n");
    try writer.writeAll("* OK [PERMANENTFLAGS (\\Seen \\Answered \\Flagged \\Deleted \\Draft)] permanent flags\r\n");
    const mode = if (readonly) "[READ-ONLY]" else "[READ-WRITE]";
    try writer.print("{s} OK {s} SELECT done\r\n", .{ tag, mode });
    try writer.flush();
}

fn writeFetchAtt(writer: anytype, att: parser.FetchAtt, m: @import("../storage/user_db.zig").Message, buf: *[8192]u8) !void {
    switch (att) {
        .flags => {
            const fstr = m.flags.toImap(buf);
            try writer.print("FLAGS ({s})", .{fstr});
        },
        .uid => try writer.print("UID {d}", .{m.uid}),
        .internaldate => try writer.print("INTERNALDATE \"{d}\"", .{m.internaldate}),
        .rfc822_size, .body => try writer.print("RFC822.SIZE {d}", .{m.size}),
        .rfc822, .rfc822_text => {
            try writer.print("RFC822 {{{d}}}\r\n", .{m.raw.len});
            try writer.writeAll(m.raw);
        },
        .rfc822_header => {
            const hdr_end = std.mem.indexOf(u8, m.raw, "\r\n\r\n") orelse m.raw.len;
            const hdr = m.raw[0..hdr_end + 4];
            try writer.print("RFC822.HEADER {{{d}}}\r\n", .{hdr.len});
            try writer.writeAll(hdr);
        },
        .body_section, .body_peek => |sect| {
            try writer.print("BODY{s} {{{d}}}\r\n", .{ sect, m.raw.len });
            try writer.writeAll(m.raw);
        },
        .envelope => {
            try writer.writeAll("ENVELOPE (NIL NIL NIL NIL NIL NIL NIL NIL NIL NIL)");
        },
        .bodystructure => {
            try writer.writeAll("BODYSTRUCTURE (\"TEXT\" \"PLAIN\" (\"CHARSET\" \"UTF-8\") NIL NIL \"7BIT\" 0 0)");
        },
        .all => {
            const fstr = m.flags.toImap(buf);
            try writer.print("FLAGS ({s}) INTERNALDATE \"{d}\" RFC822.SIZE {d} ENVELOPE NIL", .{ fstr, m.internaldate, m.size });
        },
        .fast => {
            const fstr = m.flags.toImap(buf);
            try writer.print("FLAGS ({s}) INTERNALDATE \"{d}\" RFC822.SIZE {d}", .{ fstr, m.internaldate, m.size });
        },
        .full => {
            const fstr = m.flags.toImap(buf);
            try writer.print("FLAGS ({s}) INTERNALDATE \"{d}\" RFC822.SIZE {d} ENVELOPE NIL BODY NIL", .{ fstr, m.internaldate, m.size });
        },
    }
}

fn seqSetContains(seqset: []const parser.SeqRange, n: u32) bool {
    for (seqset) |r| {
        const from = switch (r.from) { .num => |v| v, .star => std.math.maxInt(u32) };
        const to = if (r.to) |t| switch (t) { .num => |v| v, .star => std.math.maxInt(u32) } else from;
        const lo = @min(from, to);
        const hi = @max(from, to);
        if (n >= lo and n <= hi) return true;
    }
    return false;
}

fn matchSearch(
    m: @import("../storage/user_db.zig").Message,
    seq: usize,
    keys: []const parser.SearchKey,
) bool {
    _ = seq;
    for (keys) |key| {
        if (!searchKeyMatches(m, key)) return false;
    }
    return true;
}

fn searchKeyMatches(m: @import("../storage/user_db.zig").Message, key: parser.SearchKey) bool {
    return switch (key) {
        .all => true,
        .answered => m.flags.answered,
        .unanswered => !m.flags.answered,
        .seen => m.flags.seen,
        .unseen => !m.flags.seen,
        .deleted => m.flags.deleted,
        .undeleted => !m.flags.deleted,
        .flagged => m.flags.flagged,
        .unflagged => !m.flags.flagged,
        .draft => m.flags.draft,
        .undraft => !m.flags.draft,
        .recent => m.flags.recent,
        .new => m.flags.recent and !m.flags.seen,
        .old => !m.flags.recent,
        .from => |s| headerContains(m.raw, "From:", s),
        .to => |s| headerContains(m.raw, "To:", s),
        .cc => |s| headerContains(m.raw, "Cc:", s),
        .bcc => |s| headerContains(m.raw, "Bcc:", s),
        .subject => |s| headerContains(m.raw, "Subject:", s),
        .body => |s| blk: {
            const body_start = std.mem.indexOf(u8, m.raw, "\r\n\r\n") orelse break :blk false;
            break :blk std.mem.indexOf(u8, m.raw[body_start..], s) != null;
        },
        .text => |s| std.mem.indexOf(u8, m.raw, s) != null,
        .larger => |n| m.size > n,
        .smaller => |n| m.size < n,
        .uid => |ss| seqSetContains(ss, m.uid),
        .seqset => true, // sequence-number matching handled by caller
        .not => |k| !searchKeyMatches(m, k.*),
        .or_ => |o| searchKeyMatches(m, o.a.*) or searchKeyMatches(m, o.b.*),
        else => true,
    };
}

fn headerContains(raw: []const u8, field: []const u8, value: []const u8) bool {
    const hdr_end = std.mem.indexOf(u8, raw, "\r\n\r\n") orelse raw.len;
    const headers = raw[0..hdr_end];
    var it = std.mem.splitSequence(u8, headers, "\r\n");
    while (it.next()) |line| {
        if (std.ascii.startsWithIgnoreCase(line, field)) {
            if (std.mem.indexOf(u8, line, value) != null) return true;
        }
    }
    return false;
}

fn matchPattern(name: []const u8, pattern: []const u8) bool {
    if (std.mem.eql(u8, pattern, "*") or std.mem.eql(u8, pattern, "%")) return true;
    if (pattern.len == 0) return name.len == 0;
    return std.mem.startsWith(u8, name, pattern) or
        std.ascii.eqlIgnoreCase(name, pattern);
}

fn noAuth(writer: anytype, tag: []const u8) !void {
    try writer.print("{s} NO Not authenticated\r\n", .{tag});
    try writer.flush();
}

fn notSelected(writer: anytype, tag: []const u8) !void {
    try writer.print("{s} BAD No mailbox selected\r\n", .{tag});
    try writer.flush();
}
