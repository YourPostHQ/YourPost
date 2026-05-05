const std = @import("std");
const c = @cImport(@cInclude("sqlite3.h"));
const argon2 = std.crypto.pwhash.argon2;
const Sha256 = std.crypto.hash.sha2.Sha256;

// SQLITE_TRANSIENT: SQLite makes a private copy of the data.
const TRANSIENT: c.sqlite3_destructor_type = @ptrFromInt(std.math.maxInt(usize));

pub const GlobalDb = struct {
    db: *c.sqlite3,
    alloc: std.mem.Allocator,
    io: std.Io,

    pub fn open(alloc: std.mem.Allocator, io: std.Io, path: [:0]const u8) !GlobalDb {
        var db_ptr: ?*c.sqlite3 = null;
        if (c.sqlite3_open(path.ptr, &db_ptr) != c.SQLITE_OK) return error.DbOpen;
        const db = db_ptr.?;
        errdefer _ = c.sqlite3_close(db);
        try exec(db, "PRAGMA journal_mode=WAL");
        try exec(db, "PRAGMA foreign_keys=ON");
        try exec(db, schema);
        // Migrations for existing databases - add columns if they don't exist
        if (!hasColumn(db, "users", "quota_bytes")) {
            try exec(db, "ALTER TABLE users ADD COLUMN quota_bytes INTEGER NOT NULL DEFAULT 1073741824");
        }
        if (!hasColumn(db, "users", "active")) {
            try exec(db, "ALTER TABLE users ADD COLUMN active INTEGER NOT NULL DEFAULT 1");
        }
        if (!hasColumn(db, "users", "role")) {
            try exec(db, "ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'user'");
        }
        return .{ .db = db, .alloc = alloc, .io = io };
    }

    fn hasColumn(db: *c.sqlite3, table: []const u8, column: []const u8) bool {
        const sql = std.fmt.allocPrint(std.heap.page_allocator, "PRAGMA table_info({s})", .{table}) catch return false;
        defer std.heap.page_allocator.free(sql);
        const stmt = prepare(db, sql) catch return false;
        defer _ = c.sqlite3_finalize(stmt);
        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const col_name = columnText(stmt, 1);
            if (std.mem.eql(u8, col_name, column)) return true;
        }
        return false;
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

    pub fn createUser(self: *GlobalDb, email: []const u8, password: []const u8, role: []const u8) !void {
        var hash_buf: [256]u8 = undefined;
        const stored = try argon2.strHash(password, .{
            .allocator = self.alloc,
            .params = argon2.Params.owasp_2id,
            .mode = .argon2id,
        }, &hash_buf, self.io);
        bindExec(self.db,
            "INSERT INTO users (email, password_hash, role) VALUES (?, ?, ?)",
            .{ email, stored, role }) catch |err| {
            std.log.err("createUser error: {}", .{err});
            return error.UserAlreadyExists;
        };
    }

    pub fn authenticate(self: *GlobalDb, email: []const u8, password: []const u8) !bool {
        const stmt = try prepare(self.db,
            "SELECT password_hash FROM users WHERE email=? AND active=1");
        defer _ = c.sqlite3_finalize(stmt);
        bindText(stmt, 1, email);
        if (c.sqlite3_step(stmt) != c.SQLITE_ROW) return false;
        const stored = columnText(stmt, 0);
        if (std.mem.startsWith(u8, stored, "$argon2")) {
            argon2.strVerify(stored, password, .{ .allocator = self.alloc }, self.io) catch return false;
            return true;
        }
        // Legacy SHA-256 format: hex_salt(32):hex_hash(64)
        return verifyPasswordSha256(password, stored);
    }

    pub fn userExists(self: *GlobalDb, email: []const u8) !bool {
        const stmt = try prepare(self.db, "SELECT 1 FROM users WHERE email=? AND active=1");
        defer _ = c.sqlite3_finalize(stmt);
        bindText(stmt, 1, email);
        return c.sqlite3_step(stmt) == c.SQLITE_ROW;
    }

    pub fn getUserCount(self: *GlobalDb) usize {
        const stmt = prepare(self.db, "SELECT COUNT(*) FROM users") catch return 0;
        defer _ = c.sqlite3_finalize(stmt);
        if (c.sqlite3_step(stmt) != c.SQLITE_ROW) return 0;
        const count: i64 = c.sqlite3_column_int64(stmt, 0);
        return @intCast(count);
    }

    pub fn getUserQuota(self: *GlobalDb, email: []const u8) !i64 {
        const stmt = try prepare(self.db, "SELECT quota_bytes FROM users WHERE email=? AND active=1");
        defer _ = c.sqlite3_finalize(stmt);
        bindText(stmt, 1, email);
        if (c.sqlite3_step(stmt) != c.SQLITE_ROW) return error.UserNotFound;
        return c.sqlite3_column_int64(stmt, 0);
    }

    pub fn deactivateUser(self: *GlobalDb, email: []const u8) !void {
        try bindExec(self.db, "UPDATE users SET active=0 WHERE email=?", .{email});
    }

    pub const UserInfo = struct { email: []u8, role: []u8, active: bool, quota_bytes: i64 };

    pub fn listUsers(self: *GlobalDb) ![]UserInfo {
        const stmt = try prepare(self.db,
            "SELECT email, role, active, quota_bytes FROM users ORDER BY email");
        defer _ = c.sqlite3_finalize(stmt);
        var list: std.ArrayList(UserInfo) = .{ .items = &.{}, .capacity = 0 };
        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const email = try self.alloc.dupe(u8, columnText(stmt, 0));
            const role = try self.alloc.dupe(u8, columnText(stmt, 1));
            try list.append(self.alloc, .{
                .email = email,
                .role = role,
                .active = c.sqlite3_column_int(stmt, 2) != 0,
                .quota_bytes = c.sqlite3_column_int64(stmt, 3),
            });
        }
        return list.toOwnedSlice(self.alloc);
    }

    pub fn getUserRole(self: *GlobalDb, email: []const u8) ![]const u8 {
        const stmt = try prepare(self.db, "SELECT role FROM users WHERE email=? AND active=1");
        defer _ = c.sqlite3_finalize(stmt);
        bindText(stmt, 1, email);
        if (c.sqlite3_step(stmt) != c.SQLITE_ROW) return error.UserNotFound;
        return self.alloc.dupe(u8, columnText(stmt, 0));
    }

    pub fn updateUser(self: *GlobalDb, email: []const u8, role: ?[]const u8, quota_bytes: ?i64, active: ?bool) !void {
        if (role) |r| {
            try bindExec(self.db, "UPDATE users SET role=? WHERE email=?", .{ r, email });
        }
        if (quota_bytes) |q| {
            const sql = try std.fmt.allocPrint(self.alloc, "UPDATE users SET quota_bytes={d} WHERE email=?", .{q});
            defer self.alloc.free(sql);
            try bindExec(self.db, sql, .{email});
        }
        if (active) |a| {
            const val: i64 = if (a) 1 else 0;
            const sql = try std.fmt.allocPrint(self.alloc, "UPDATE users SET active={d} WHERE email=?", .{val});
            defer self.alloc.free(sql);
            try bindExec(self.db, sql, .{email});
        }
    }
};

fn verifyPasswordSha256(password: []const u8, stored: []const u8) bool {
    if (stored.len < 33 + 64 or stored[32] != ':') return false;
    var salt: [16]u8 = undefined;
    _ = std.fmt.hexToBytes(&salt, stored[0..32]) catch return false;
    var h = Sha256.init(.{});
    h.update(&salt);
    h.update(password);
    var computed: [32]u8 = undefined;
    h.final(&computed);
    var hex_buf: [64]u8 = undefined;
    for (computed, 0..) |byte, i|
        _ = std.fmt.bufPrint(hex_buf[i * 2 ..][0..2], "{x:0>2}", .{byte}) catch return false;
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
    \\  created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
    \\);
    \\CREATE TABLE IF NOT EXISTS users (
    \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
    \\  email TEXT NOT NULL UNIQUE,
    \\  password_hash TEXT NOT NULL,
    \\  role TEXT NOT NULL DEFAULT 'user',
    \\  quota_bytes INTEGER NOT NULL DEFAULT 1073741824,
    \\  active INTEGER NOT NULL DEFAULT 1,
    \\  created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
    \\);
;
