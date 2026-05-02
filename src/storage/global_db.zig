const std = @import("std");
const c = @cImport(@cInclude("sqlite3.h"));
const Sha256 = std.crypto.hash.sha2.Sha256;

// SQLITE_TRANSIENT: SQLite makes a private copy of the data.
const TRANSIENT: c.sqlite3_destructor_type = @ptrFromInt(std.math.maxInt(usize));

pub const GlobalDb = struct {
    db: *c.sqlite3,

    pub fn open(path: [:0]const u8) !GlobalDb {
        var db_ptr: ?*c.sqlite3 = null;
        if (c.sqlite3_open(path.ptr, &db_ptr) != c.SQLITE_OK) return error.DbOpen;
        const db = db_ptr.?;
        errdefer _ = c.sqlite3_close(db);
        try exec(db, "PRAGMA journal_mode=WAL");
        try exec(db, "PRAGMA foreign_keys=ON");
        try exec(db, schema);
        return .{ .db = db };
    }

    pub fn close(self: *GlobalDb) void {
        _ = c.sqlite3_close(self.db);
    }

    pub fn addDomain(self: *GlobalDb, domain: []const u8) !void {
        try bindExec(self.db, "INSERT OR IGNORE INTO domains (domain) VALUES (?)", .{domain});
    }

    pub fn hasDomain(self: *GlobalDb, domain: []const u8) !bool {
        const stmt = try prepare(self.db, "SELECT 1 FROM domains WHERE domain=?");
        defer _ = c.sqlite3_finalize(stmt);
        bindText(stmt, 1, domain);
        return c.sqlite3_step(stmt) == c.SQLITE_ROW;
    }

    pub fn createUser(self: *GlobalDb, email: []const u8, password: []const u8) !void {
        var salt: [16]u8 = undefined;
        std.crypto.random.bytes(&salt);
        const hash = hashPassword(password, &salt);
        var encoded: [2 + 32 + 1 + 64]u8 = undefined;
        const stored = std.fmt.bufPrint(&encoded, "{s}:{}", .{
            std.fmt.fmtSliceHexLower(&salt),
            std.fmt.fmtSliceHexLower(&hash),
        }) catch unreachable;
        try bindExec(self.db,
            "INSERT INTO users (email, password_hash) VALUES (?, ?)",
            .{ email, stored });
    }

    pub fn authenticate(self: *GlobalDb, email: []const u8, password: []const u8) !bool {
        const stmt = try prepare(self.db,
            "SELECT password_hash FROM users WHERE email=? AND active=1");
        defer _ = c.sqlite3_finalize(stmt);
        bindText(stmt, 1, email);
        if (c.sqlite3_step(stmt) != c.SQLITE_ROW) return false;
        const stored = columnText(stmt, 0);
        return verifyPassword(password, stored);
    }

    pub fn userExists(self: *GlobalDb, email: []const u8) !bool {
        const stmt = try prepare(self.db, "SELECT 1 FROM users WHERE email=? AND active=1");
        defer _ = c.sqlite3_finalize(stmt);
        bindText(stmt, 1, email);
        return c.sqlite3_step(stmt) == c.SQLITE_ROW;
    }
};

fn hashPassword(password: []const u8, salt: []const u8) [32]u8 {
    var h = Sha256.init(.{});
    h.update(salt);
    h.update(password);
    var out: [32]u8 = undefined;
    h.final(&out);
    return out;
}

fn verifyPassword(password: []const u8, stored: []const u8) bool {
    // stored = hex_salt(32 chars) : hex_hash(64 chars)
    if (stored.len < 33 + 64 or stored[32] != ':') return false;
    var salt: [16]u8 = undefined;
    _ = std.fmt.hexToBytes(&salt, stored[0..32]) catch return false;
    const computed = hashPassword(password, &salt);
    var hex_buf: [64]u8 = undefined;
    for (computed, 0..) |byte, i| {
        _ = std.fmt.bufPrint(hex_buf[i * 2 ..][0..2], "{x:0>2}", .{byte}) catch return false;
    }
    return std.mem.eql(u8, &hex_buf, stored[33 .. 33 + 64]);
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

const schema =
    \\CREATE TABLE IF NOT EXISTS domains (
    \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
    \\  domain TEXT NOT NULL UNIQUE,
    \\  created_at INTEGER NOT NULL DEFAULT (unixepoch())
    \\);
    \\CREATE TABLE IF NOT EXISTS users (
    \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
    \\  email TEXT NOT NULL UNIQUE,
    \\  password_hash TEXT NOT NULL,
    \\  quota_bytes INTEGER NOT NULL DEFAULT 1073741824,
    \\  active INTEGER NOT NULL DEFAULT 1,
    \\  created_at INTEGER NOT NULL DEFAULT (unixepoch())
    \\);
;
