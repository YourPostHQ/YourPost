const std = @import("std");
const c = @cImport(@cInclude("sqlite3.h"));

const TRANSIENT: c.sqlite3_destructor_type = @ptrFromInt(std.math.maxInt(usize));

pub const Flags = struct {
    seen: bool = false,
    answered: bool = false,
    flagged: bool = false,
    deleted: bool = false,
    draft: bool = false,
    recent: bool = true,

    pub fn fromImap(list: []const u8) Flags {
        var f = Flags{};
        if (std.mem.indexOf(u8, list, "\\Seen") != null) f.seen = true;
        if (std.mem.indexOf(u8, list, "\\Answered") != null) f.answered = true;
        if (std.mem.indexOf(u8, list, "\\Flagged") != null) f.flagged = true;
        if (std.mem.indexOf(u8, list, "\\Deleted") != null) f.deleted = true;
        if (std.mem.indexOf(u8, list, "\\Draft") != null) f.draft = true;
        return f;
    }

    pub fn toImap(self: Flags, buf: []u8) []u8 {
        var pos: usize = 0;
        const write = struct {
            fn write(buf_inner: []u8, p: *usize, data: []const u8) void {
                const end = @min(p.* + data.len, buf_inner.len);
                @memcpy(buf_inner[p.*..end], data[0..@min(data.len, buf_inner.len - p.*)]);
                p.* = end;
            }
        };
        if (self.seen) write.write(buf, &pos, "\\Seen ");
        if (self.answered) write.write(buf, &pos, "\\Answered ");
        if (self.flagged) write.write(buf, &pos, "\\Flagged ");
        if (self.deleted) write.write(buf, &pos, "\\Deleted ");
        if (self.draft) write.write(buf, &pos, "\\Draft ");
        if (self.recent) write.write(buf, &pos, "\\Recent ");
        const s = buf[0..pos];
        return if (s.len > 0 and s[s.len - 1] == ' ') s[0 .. s.len - 1] else s;
    }
};

pub const Message = struct {
    uid: u32,
    flags: Flags,
    internaldate: i64,
    size: u32,
    raw: []const u8,
};

pub const FolderStatus = struct {
    messages: u32,
    recent: u32,
    unseen: u32,
    uidnext: u32,
    uidvalidity: u32,
};

pub const UserDb = struct {
    db: *c.sqlite3,
    alloc: std.mem.Allocator,

    pub fn open(alloc: std.mem.Allocator, mailbox_path: [:0]const u8) !UserDb {
        var db_ptr: ?*c.sqlite3 = null;
        if (c.sqlite3_open(mailbox_path.ptr, &db_ptr) != c.SQLITE_OK) return error.DbOpen;
        const db = db_ptr.?;
        errdefer _ = c.sqlite3_close(db);
        try exec(db, "PRAGMA journal_mode=WAL");
        try exec(db, "PRAGMA foreign_keys=ON");
        try exec(db, schema);
        try ensureInbox(db);
        return .{ .db = db, .alloc = alloc };
    }

    pub fn close(self: *UserDb) void {
        _ = c.sqlite3_close(self.db);
    }

    // ----- Folders -----

    pub fn createFolder(self: *UserDb, name: []const u8) !void {
        try bindExec(self.db,
            "INSERT OR IGNORE INTO folders (name) VALUES (?)", .{name});
    }

    pub fn deleteFolder(self: *UserDb, name: []const u8) !void {
        try bindExec(self.db,
            "DELETE FROM folders WHERE name=? AND name!='INBOX'", .{name});
    }

    pub fn renameFolder(self: *UserDb, old: []const u8, new: []const u8) !void {
        try bindExec2(self.db,
            "UPDATE folders SET name=? WHERE name=?", new, old);
    }

    pub const FolderInfo = struct { id: i64, name: []u8, uidvalidity: u32, uidnext: u32, subscribed: bool };

    pub fn listFolders(self: *UserDb) ![]FolderInfo {
        const stmt = try prepare(self.db, "SELECT id,name,uidvalidity,uidnext,subscribed FROM folders ORDER BY id");
        defer _ = c.sqlite3_finalize(stmt);
        var list: std.ArrayList(FolderInfo) = .{ .items = &.{}, .capacity = 0 };
        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const name_raw = columnText(stmt, 1);
            const name = try self.alloc.dupe(u8, name_raw);
            try list.append(self.alloc, .{
                .id = c.sqlite3_column_int64(stmt, 0),
                .name = name,
                .uidvalidity = @intCast(c.sqlite3_column_int(stmt, 2)),
                .uidnext = @intCast(c.sqlite3_column_int(stmt, 3)),
                .subscribed = c.sqlite3_column_int(stmt, 4) != 0,
            });
        }
        return list.toOwnedSlice(self.alloc);
    }

    pub fn getFolderByName(self: *UserDb, name: []const u8) !?FolderInfo {
        const stmt = try prepare(self.db,
            "SELECT id,name,uidvalidity,uidnext,subscribed FROM folders WHERE name=?");
        defer _ = c.sqlite3_finalize(stmt);
        bindText(stmt, 1, name);
        if (c.sqlite3_step(stmt) != c.SQLITE_ROW) return null;
        const name_raw = columnText(stmt, 1);
        return .{
            .id = c.sqlite3_column_int64(stmt, 0),
            .name = try self.alloc.dupe(u8, name_raw),
            .uidvalidity = @intCast(c.sqlite3_column_int(stmt, 2)),
            .uidnext = @intCast(c.sqlite3_column_int(stmt, 3)),
            .subscribed = c.sqlite3_column_int(stmt, 4) != 0,
        };
    }

    pub fn folderStatus(self: *UserDb, folder_id: i64) !FolderStatus {
        const stmt = try prepare(self.db,
            \\SELECT
            \\  COUNT(*),
            \\  SUM(CASE WHEN recent=1 THEN 1 ELSE 0 END),
            \\  SUM(CASE WHEN seen=0 THEN 1 ELSE 0 END)
            \\FROM messages WHERE folder_id=? AND deleted=0
        );
        defer _ = c.sqlite3_finalize(stmt);
        _ = c.sqlite3_bind_int64(stmt, 1, folder_id);
        _ = c.sqlite3_step(stmt);
        const messages: u32 = @intCast(@max(0, c.sqlite3_column_int(stmt, 0)));
        const recent: u32 = @intCast(@max(0, c.sqlite3_column_int(stmt, 1)));
        const unseen: u32 = @intCast(@max(0, c.sqlite3_column_int(stmt, 2)));

        const s2 = try prepare(self.db,
            "SELECT uidnext,uidvalidity FROM folders WHERE id=?");
        defer _ = c.sqlite3_finalize(s2);
        _ = c.sqlite3_bind_int64(s2, 1, folder_id);
        _ = c.sqlite3_step(s2);
        return .{
            .messages = messages,
            .recent = recent,
            .unseen = unseen,
            .uidnext = @intCast(@max(1, c.sqlite3_column_int(s2, 0))),
            .uidvalidity = @intCast(@max(1, c.sqlite3_column_int(s2, 1))),
        };
    }

    // ----- Messages -----

    pub fn appendMessage(self: *UserDb, folder_id: i64, raw: []const u8, flags: Flags, internaldate: i64) !u32 {
        // Allocate next UID atomically
        try exec(self.db, "BEGIN IMMEDIATE");
        errdefer _ = c.sqlite3_exec(self.db, "ROLLBACK", null, null, null);

        const s1 = try prepare(self.db, "SELECT uidnext FROM folders WHERE id=?");
        _ = c.sqlite3_bind_int64(s1, 1, folder_id);
        if (c.sqlite3_step(s1) != c.SQLITE_ROW) {
            _ = c.sqlite3_finalize(s1);
            return error.FolderNotFound;
        }
        const uid: u32 = @intCast(c.sqlite3_column_int(s1, 0));
        _ = c.sqlite3_finalize(s1);

        const ins = try prepare(self.db,
            \\INSERT INTO messages
            \\  (folder_id,uid,seen,answered,flagged,deleted,draft,recent,internaldate,size,raw)
            \\VALUES (?,?,?,?,?,?,?,?,?,?,?)
        );
        _ = c.sqlite3_bind_int64(ins, 1, folder_id);
        _ = c.sqlite3_bind_int(ins, 2, @intCast(uid));
        _ = c.sqlite3_bind_int(ins, 3, if (flags.seen) 1 else 0);
        _ = c.sqlite3_bind_int(ins, 4, if (flags.answered) 1 else 0);
        _ = c.sqlite3_bind_int(ins, 5, if (flags.flagged) 1 else 0);
        _ = c.sqlite3_bind_int(ins, 6, if (flags.deleted) 1 else 0);
        _ = c.sqlite3_bind_int(ins, 7, if (flags.draft) 1 else 0);
        _ = c.sqlite3_bind_int(ins, 8, if (flags.recent) 1 else 0);
        _ = c.sqlite3_bind_int64(ins, 9, internaldate);
        _ = c.sqlite3_bind_int(ins, 10, @intCast(raw.len));
        _ = c.sqlite3_bind_blob(ins, 11, raw.ptr, @intCast(raw.len), TRANSIENT);
        if (c.sqlite3_step(ins) != c.SQLITE_DONE) {
            _ = c.sqlite3_finalize(ins);
            return error.DbInsert;
        }
        _ = c.sqlite3_finalize(ins);

        try bindExec(self.db,
            "UPDATE folders SET uidnext=uidnext+1 WHERE id=?",
            .{std.fmt.comptimePrint("{}", .{0})}); // workaround: use int bind below
        const upd = try prepare(self.db, "UPDATE folders SET uidnext=uidnext+1 WHERE id=?");
        _ = c.sqlite3_bind_int64(upd, 1, folder_id);
        if (c.sqlite3_step(upd) != c.SQLITE_DONE) {
            _ = c.sqlite3_finalize(upd);
            return error.DbUpdate;
        }
        _ = c.sqlite3_finalize(upd);

        try exec(self.db, "COMMIT");
        return uid;
    }

    pub fn fetchMessage(self: *UserDb, folder_id: i64, uid: u32) !?Message {
        const stmt = try prepare(self.db,
            \\SELECT uid,seen,answered,flagged,deleted,draft,recent,internaldate,size,raw
            \\FROM messages WHERE folder_id=? AND uid=?
        );
        defer _ = c.sqlite3_finalize(stmt);
        _ = c.sqlite3_bind_int64(stmt, 1, folder_id);
        _ = c.sqlite3_bind_int(stmt, 2, @intCast(uid));
        if (c.sqlite3_step(stmt) != c.SQLITE_ROW) return null;
        return messageFromRow(self.alloc, stmt);
    }

    pub fn listMessages(self: *UserDb, folder_id: i64) ![]Message {
        const stmt = try prepare(self.db,
            \\SELECT uid,seen,answered,flagged,deleted,draft,recent,internaldate,size,raw
            \\FROM messages WHERE folder_id=? AND deleted=0 ORDER BY uid
        );
        defer _ = c.sqlite3_finalize(stmt);
        _ = c.sqlite3_bind_int64(stmt, 1, folder_id);
        var list: std.ArrayList(Message) = .{ .items = &.{}, .capacity = 0 };
        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            try list.append(self.alloc, try messageFromRow(self.alloc, stmt));
        }
        return list.toOwnedSlice(self.alloc);
    }

    pub fn countMessages(self: *UserDb, folder_id: i64) !u32 {
        const stmt = try prepare(self.db,
            "SELECT COUNT(*) FROM messages WHERE folder_id=? AND deleted=0");
        defer _ = c.sqlite3_finalize(stmt);
        _ = c.sqlite3_bind_int64(stmt, 1, folder_id);
        _ = c.sqlite3_step(stmt);
        return @intCast(@max(0, c.sqlite3_column_int(stmt, 0)));
    }

    pub fn storeFlags(self: *UserDb, folder_id: i64, uid: u32, flags: Flags) !void {
        const stmt = try prepare(self.db,
            \\UPDATE messages SET seen=?,answered=?,flagged=?,deleted=?,draft=?
            \\WHERE folder_id=? AND uid=?
        );
        defer _ = c.sqlite3_finalize(stmt);
        _ = c.sqlite3_bind_int(stmt, 1, if (flags.seen) 1 else 0);
        _ = c.sqlite3_bind_int(stmt, 2, if (flags.answered) 1 else 0);
        _ = c.sqlite3_bind_int(stmt, 3, if (flags.flagged) 1 else 0);
        _ = c.sqlite3_bind_int(stmt, 4, if (flags.deleted) 1 else 0);
        _ = c.sqlite3_bind_int(stmt, 5, if (flags.draft) 1 else 0);
        _ = c.sqlite3_bind_int64(stmt, 6, folder_id);
        _ = c.sqlite3_bind_int(stmt, 7, @intCast(uid));
        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) return error.DbUpdate;
    }

    pub fn expunge(self: *UserDb, folder_id: i64) ![]u32 {
        // Return UIDs of deleted messages, then hard-delete them
        const sel = try prepare(self.db,
            "SELECT uid FROM messages WHERE folder_id=? AND deleted=1 ORDER BY uid");
        defer _ = c.sqlite3_finalize(sel);
        _ = c.sqlite3_bind_int64(sel, 1, folder_id);
        var uids: std.ArrayList(u32) = .{ .items = &.{}, .capacity = 0 };
        while (c.sqlite3_step(sel) == c.SQLITE_ROW) {
            try uids.append(self.alloc, @intCast(c.sqlite3_column_int(sel, 0)));
        }
        const del = try prepare(self.db,
            "DELETE FROM messages WHERE folder_id=? AND deleted=1");
        defer _ = c.sqlite3_finalize(del);
        _ = c.sqlite3_bind_int64(del, 1, folder_id);
        _ = c.sqlite3_step(del);
        return uids.toOwnedSlice(self.alloc);
    }

    // All UIDs in folder order (including \Deleted), used for EXPUNGE seq-num mapping
    pub fn listMessageUids(self: *UserDb, folder_id: i64) ![]u32 {
        const stmt = try prepare(self.db,
            "SELECT uid FROM messages WHERE folder_id=? ORDER BY uid");
        defer _ = c.sqlite3_finalize(stmt);
        _ = c.sqlite3_bind_int64(stmt, 1, folder_id);
        var uids: std.ArrayList(u32) = .{ .items = &.{}, .capacity = 0 };
        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            try uids.append(self.alloc, @intCast(c.sqlite3_column_int(stmt, 0)));
        }
        return uids.toOwnedSlice(self.alloc);
    }

    // Simple text search across from/subject/body headers
    pub fn search(self: *UserDb, folder_id: i64, query: []const u8) ![]u32 {
        const stmt = try prepare(self.db,
            "SELECT uid FROM messages WHERE folder_id=? AND deleted=0 AND CAST(raw AS TEXT) LIKE ? ORDER BY uid");
        defer _ = c.sqlite3_finalize(stmt);
        _ = c.sqlite3_bind_int64(stmt, 1, folder_id);
        const pattern = try std.fmt.allocPrint(self.alloc, "%{s}%", .{query});
        defer self.alloc.free(pattern);
        bindText(stmt, 2, pattern);
        var uids: std.ArrayList(u32) = .{ .items = &.{}, .capacity = 0 };
        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            try uids.append(self.alloc, @intCast(c.sqlite3_column_int(stmt, 0)));
        }
        return uids.toOwnedSlice(self.alloc);
    }
};

fn messageFromRow(alloc: std.mem.Allocator, stmt: *c.sqlite3_stmt) !Message {
    const blob = c.sqlite3_column_blob(stmt, 9);
    const blob_len: usize = @intCast(c.sqlite3_column_bytes(stmt, 9));
    const raw_slice = if (blob != null)
        @as([*]const u8, @ptrCast(blob))[0..blob_len]
    else
        &[_]u8{};
    const raw = try alloc.dupe(u8, raw_slice);
    return .{
        .uid = @intCast(c.sqlite3_column_int(stmt, 0)),
        .flags = .{
            .seen = c.sqlite3_column_int(stmt, 1) != 0,
            .answered = c.sqlite3_column_int(stmt, 2) != 0,
            .flagged = c.sqlite3_column_int(stmt, 3) != 0,
            .deleted = c.sqlite3_column_int(stmt, 4) != 0,
            .draft = c.sqlite3_column_int(stmt, 5) != 0,
            .recent = c.sqlite3_column_int(stmt, 6) != 0,
        },
        .internaldate = c.sqlite3_column_int64(stmt, 7),
        .size = @intCast(c.sqlite3_column_int(stmt, 8)),
        .raw = raw,
    };
}

fn ensureInbox(db: *c.sqlite3) !void {
    try exec(db, "INSERT OR IGNORE INTO folders (name) VALUES ('INBOX')");
}

fn exec(db: *c.sqlite3, sql: []const u8) !void {
    if (c.sqlite3_exec(db, sql.ptr, null, null, null) != c.SQLITE_OK) return error.DbExec;
}

fn prepare(db: *c.sqlite3, sql: []const u8) !*c.sqlite3_stmt {
    var stmt: ?*c.sqlite3_stmt = null;
    if (c.sqlite3_prepare_v2(db, sql.ptr, @intCast(sql.len), &stmt, null) != c.SQLITE_OK)
        return error.DbPrepare;
    return stmt.?;
}

fn bindText(stmt: *c.sqlite3_stmt, idx: c_int, val: []const u8) void {
    _ = c.sqlite3_bind_text(stmt, idx, val.ptr, @intCast(val.len), TRANSIENT);
}

fn columnText(stmt: *c.sqlite3_stmt, col: c_int) []const u8 {
    const ptr = c.sqlite3_column_text(stmt, col) orelse return "";
    const len: usize = @intCast(c.sqlite3_column_bytes(stmt, col));
    return @as([*]const u8, @ptrCast(ptr))[0..len];
}

fn bindExec(db: *c.sqlite3, sql: []const u8, args: anytype) !void {
    const stmt = try prepare(db, sql);
    defer _ = c.sqlite3_finalize(stmt);
    inline for (args, 1..) |arg, i| {
        bindText(stmt, @intCast(i), arg);
    }
    if (c.sqlite3_step(stmt) != c.SQLITE_DONE) return error.DbStep;
}

fn bindExec2(db: *c.sqlite3, sql: []const u8, a: []const u8, b_val: []const u8) !void {
    const stmt = try prepare(db, sql);
    defer _ = c.sqlite3_finalize(stmt);
    bindText(stmt, 1, a);
    bindText(stmt, 2, b_val);
    if (c.sqlite3_step(stmt) != c.SQLITE_DONE) return error.DbStep;
}

const schema =
    \\CREATE TABLE IF NOT EXISTS folders (
    \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
    \\  name TEXT NOT NULL UNIQUE,
    \\  uidvalidity INTEGER NOT NULL DEFAULT (unixepoch()),
    \\  uidnext INTEGER NOT NULL DEFAULT 1,
    \\  subscribed INTEGER NOT NULL DEFAULT 1
    \\);
    \\CREATE TABLE IF NOT EXISTS messages (
    \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
    \\  folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
    \\  uid INTEGER NOT NULL,
    \\  seen INTEGER NOT NULL DEFAULT 0,
    \\  answered INTEGER NOT NULL DEFAULT 0,
    \\  flagged INTEGER NOT NULL DEFAULT 0,
    \\  deleted INTEGER NOT NULL DEFAULT 0,
    \\  draft INTEGER NOT NULL DEFAULT 0,
    \\  recent INTEGER NOT NULL DEFAULT 1,
    \\  internaldate INTEGER NOT NULL DEFAULT (unixepoch()),
    \\  size INTEGER NOT NULL DEFAULT 0,
    \\  raw BLOB NOT NULL,
    \\  UNIQUE(folder_id, uid)
    \\);
    \\CREATE INDEX IF NOT EXISTS idx_msg_folder_uid ON messages(folder_id, uid);
    \\CREATE INDEX IF NOT EXISTS idx_msg_flags ON messages(folder_id, deleted, seen);
;
