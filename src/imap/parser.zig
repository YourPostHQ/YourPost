const std = @import("std");

pub const SeqNum = union(enum) { num: u32, star };
pub const SeqRange = struct { from: SeqNum, to: ?SeqNum };

pub const FetchAtt = union(enum) {
    all,
    fast,
    full,
    flags,
    uid,
    internaldate,
    rfc822,
    rfc822_header,
    rfc822_size,
    rfc822_text,
    envelope,
    body,
    bodystructure,
    body_section: []const u8,  // section spec as raw string
    body_peek: []const u8,
};

pub const StoreOp = enum { replace, add, remove };

pub const SearchKey = union(enum) {
    all,
    answered, unanswered,
    seen, unseen,
    deleted, undeleted,
    flagged, unflagged,
    draft, undraft,
    recent, new, old,
    from: []const u8,
    to: []const u8,
    cc: []const u8,
    bcc: []const u8,
    subject: []const u8,
    body: []const u8,
    text: []const u8,
    header: struct { field: []const u8, value: []const u8 },
    before: []const u8,
    on: []const u8,
    since: []const u8,
    sentbefore: []const u8,
    senton: []const u8,
    sentsince: []const u8,
    larger: u32,
    smaller: u32,
    uid: []SeqRange,
    not: *SearchKey,
    or_: struct { a: *SearchKey, b: *SearchKey },
    seqset: []SeqRange,
};

pub const Command = union(enum) {
    capability,
    noop,
    logout,
    login: struct { user: []const u8, pass: []const u8 },
    select: []const u8,
    examine: []const u8,
    create: []const u8,
    delete: []const u8,
    rename: struct { old: []const u8, new: []const u8 },
    subscribe: []const u8,
    unsubscribe: []const u8,
    list: struct { ref: []const u8, pattern: []const u8 },
    lsub: struct { ref: []const u8, pattern: []const u8 },
    status: struct { mailbox: []const u8, items: []const u8 },
    append: struct { mailbox: []const u8, flags: []const u8, date: []const u8, size: u32 },
    check,
    close,
    expunge,
    search: struct { keys: []SearchKey, uid: bool },
    fetch: struct { seqset: []SeqRange, atts: []FetchAtt, uid: bool },
    store: struct { seqset: []SeqRange, op: StoreOp, silent: bool, flags: []const u8, uid: bool },
    copy: struct { seqset: []SeqRange, mailbox: []const u8, uid: bool },
    idle,
    done,
};

pub const ParsedCommand = struct {
    tag: []const u8,
    cmd: Command,
};

const Parser = struct {
    buf: []const u8,
    pos: usize,
    alloc: std.mem.Allocator,

    fn peek(p: *Parser) ?u8 {
        return if (p.pos < p.buf.len) p.buf[p.pos] else null;
    }

    fn advance(p: *Parser) void {
        if (p.pos < p.buf.len) p.pos += 1;
    }

    fn eat(p: *Parser, ch: u8) bool {
        if (p.peek() == ch) { p.advance(); return true; }
        return false;
    }

    fn skipSP(p: *Parser) void {
        while (p.peek() == ' ') p.advance();
    }

    fn atom(p: *Parser) []const u8 {
        const start = p.pos;
        while (p.peek()) |ch| {
            if (ch == ' ' or ch == '\r' or ch == '\n' or ch == '(' or ch == ')' or ch == '[' or ch == ']') break;
            p.advance();
        }
        return p.buf[start..p.pos];
    }

    fn astring(p: *Parser) ![]const u8 {
        if (p.peek() == '"') return p.quotedString();
        return p.atom();
    }

    fn quotedString(p: *Parser) ![]const u8 {
        _ = p.eat('"');
        const start = p.pos;
        while (p.peek()) |ch| {
            if (ch == '"') break;
            if (ch == '\\') p.advance();
            p.advance();
        }
        const s = p.buf[start..p.pos];
        _ = p.eat('"');
        return s;
    }

    fn number(p: *Parser) !u32 {
        const start = p.pos;
        while (p.peek()) |ch| {
            if (ch < '0' or ch > '9') break;
            p.advance();
        }
        if (p.pos == start) return error.ExpectedNumber;
        return std.fmt.parseInt(u32, p.buf[start..p.pos], 10) catch error.ExpectedNumber;
    }

    fn seqNum(p: *Parser) !SeqNum {
        if (p.peek() == '*') { p.advance(); return .star; }
        return .{ .num = try p.number() };
    }

    fn seqRange(p: *Parser) !SeqRange {
        const from = try p.seqNum();
        if (p.eat(':')) {
            return .{ .from = from, .to = try p.seqNum() };
        }
        return .{ .from = from, .to = null };
    }

    fn seqSet(p: *Parser) ![]SeqRange {
        var list: std.ArrayList(SeqRange) = .{ .items = &.{}, .capacity = 0 };
        try list.append(p.alloc, try p.seqRange());
        while (p.eat(',')) {
            try list.append(p.alloc, try p.seqRange());
        }
        return list.toOwnedSlice(p.alloc);
    }

    fn flagList(p: *Parser) []const u8 {
        const start = p.pos;
        if (p.peek() == '(') {
            var depth: i32 = 0;
            while (p.pos < p.buf.len) {
                if (p.buf[p.pos] == '(') {
                    depth += 1;
                } else if (p.buf[p.pos] == ')') {
                    depth -= 1;
                    p.advance();
                    if (depth == 0) break;
                    continue;
                }
                p.advance();
            }
        }
        return p.buf[start..p.pos];
    }

    fn fetchAttList(p: *Parser) ![]FetchAtt {
        var list: std.ArrayList(FetchAtt) = .{ .items = &.{}, .capacity = 0 };
        const paren = p.peek() == '(';
        if (paren) p.advance();
        while (true) {
            p.skipSP();
            if (p.peek() == null or (paren and p.peek() == ')')) break;
            const start = p.pos;
            const name = p.atom();
            const upper = try std.ascii.allocUpperString(p.alloc, name);
            defer p.alloc.free(upper);

            if (std.mem.eql(u8, upper, "ALL")) {
                try list.append(p.alloc, .all);
            } else if (std.mem.eql(u8, upper, "FAST")) {
                try list.append(p.alloc, .fast);
            } else if (std.mem.eql(u8, upper, "FULL")) {
                try list.append(p.alloc, .full);
            } else if (std.mem.eql(u8, upper, "FLAGS")) {
                try list.append(p.alloc, .flags);
            } else if (std.mem.eql(u8, upper, "UID")) {
                try list.append(p.alloc, .uid);
            } else if (std.mem.eql(u8, upper, "INTERNALDATE")) {
                try list.append(p.alloc, .internaldate);
            } else if (std.mem.eql(u8, upper, "RFC822")) {
                try list.append(p.alloc, .rfc822);
            } else if (std.mem.eql(u8, upper, "RFC822.HEADER")) {
                try list.append(p.alloc, .rfc822_header);
            } else if (std.mem.eql(u8, upper, "RFC822.SIZE")) {
                try list.append(p.alloc, .rfc822_size);
            } else if (std.mem.eql(u8, upper, "RFC822.TEXT")) {
                try list.append(p.alloc, .rfc822_text);
            } else if (std.mem.eql(u8, upper, "ENVELOPE")) {
                try list.append(p.alloc, .envelope);
            } else if (std.mem.eql(u8, upper, "BODY")) {
                if (p.peek() == '[') {
                    const sect_start = p.pos;
                    p.advance();
                    var depth: i32 = 1;
                    while (p.pos < p.buf.len and depth > 0) {
                        if (p.buf[p.pos] == '[') depth += 1
                        else if (p.buf[p.pos] == ']') depth -= 1;
                        p.advance();
                    }
                    // optional <partial>
                    if (p.peek() == '<') {
                        while (p.peek() != null and p.peek() != '>') p.advance();
                        if (p.peek() == '>') p.advance();
                    }
                    try list.append(p.alloc, .{ .body_section = p.buf[sect_start..p.pos] });
                } else {
                    try list.append(p.alloc, .body);
                }
            } else if (std.mem.eql(u8, upper, "BODY.PEEK")) {
                if (p.peek() == '[') {
                    const sect_start = p.pos;
                    p.advance();
                    var depth: i32 = 1;
                    while (p.pos < p.buf.len and depth > 0) {
                        if (p.buf[p.pos] == '[') depth += 1
                        else if (p.buf[p.pos] == ']') depth -= 1;
                        p.advance();
                    }
                    if (p.peek() == '<') {
                        while (p.peek() != null and p.peek() != '>') p.advance();
                        if (p.peek() == '>') p.advance();
                    }
                    try list.append(p.alloc, .{ .body_peek = p.buf[sect_start..p.pos] });
                } else {
                    try list.append(p.alloc, .body);
                }
            } else if (std.mem.eql(u8, upper, "BODYSTRUCTURE")) {
                try list.append(p.alloc, .bodystructure);
            } else {
                // unknown — skip
                _ = start;
            }

            if (!paren) break;
        }
        if (paren) _ = p.eat(')');
        return list.toOwnedSlice(p.alloc);
    }

    fn searchKeys(p: *Parser) ![]SearchKey {
        var list: std.ArrayList(SearchKey) = .{ .items = &.{}, .capacity = 0 };
        while (p.pos < p.buf.len) {
            p.skipSP();
            if (p.peek() == null or p.peek() == '\r' or p.peek() == '\n') break;
            if (try p.searchKey()) |key| try list.append(p.alloc, key);
        }
        return list.toOwnedSlice(p.alloc);
    }

    fn searchKey(p: *Parser) !?SearchKey {
        const start = p.pos;
        const tok = p.atom();
        if (tok.len == 0) return null;
        const upper = try std.ascii.allocUpperString(p.alloc, tok);
        defer p.alloc.free(upper);

        if (std.mem.eql(u8, upper, "ALL")) return .all;
        if (std.mem.eql(u8, upper, "ANSWERED")) return .answered;
        if (std.mem.eql(u8, upper, "UNANSWERED")) return .unanswered;
        if (std.mem.eql(u8, upper, "SEEN")) return .seen;
        if (std.mem.eql(u8, upper, "UNSEEN")) return .unseen;
        if (std.mem.eql(u8, upper, "DELETED")) return .deleted;
        if (std.mem.eql(u8, upper, "UNDELETED")) return .undeleted;
        if (std.mem.eql(u8, upper, "FLAGGED")) return .flagged;
        if (std.mem.eql(u8, upper, "UNFLAGGED")) return .unflagged;
        if (std.mem.eql(u8, upper, "DRAFT")) return .draft;
        if (std.mem.eql(u8, upper, "UNDRAFT")) return .undraft;
        if (std.mem.eql(u8, upper, "RECENT")) return .recent;
        if (std.mem.eql(u8, upper, "NEW")) return .new;
        if (std.mem.eql(u8, upper, "OLD")) return .old;
        if (std.mem.eql(u8, upper, "FROM")) { p.skipSP(); return .{ .from = try p.astring() }; }
        if (std.mem.eql(u8, upper, "TO")) { p.skipSP(); return .{ .to = try p.astring() }; }
        if (std.mem.eql(u8, upper, "CC")) { p.skipSP(); return .{ .cc = try p.astring() }; }
        if (std.mem.eql(u8, upper, "BCC")) { p.skipSP(); return .{ .bcc = try p.astring() }; }
        if (std.mem.eql(u8, upper, "SUBJECT")) { p.skipSP(); return .{ .subject = try p.astring() }; }
        if (std.mem.eql(u8, upper, "BODY")) { p.skipSP(); return .{ .body = try p.astring() }; }
        if (std.mem.eql(u8, upper, "TEXT")) { p.skipSP(); return .{ .text = try p.astring() }; }
        if (std.mem.eql(u8, upper, "BEFORE")) { p.skipSP(); return .{ .before = p.atom() }; }
        if (std.mem.eql(u8, upper, "ON")) { p.skipSP(); return .{ .on = p.atom() }; }
        if (std.mem.eql(u8, upper, "SINCE")) { p.skipSP(); return .{ .since = p.atom() }; }
        if (std.mem.eql(u8, upper, "SENTBEFORE")) { p.skipSP(); return .{ .sentbefore = p.atom() }; }
        if (std.mem.eql(u8, upper, "SENTON")) { p.skipSP(); return .{ .senton = p.atom() }; }
        if (std.mem.eql(u8, upper, "SENTSINCE")) { p.skipSP(); return .{ .sentsince = p.atom() }; }
        if (std.mem.eql(u8, upper, "LARGER")) { p.skipSP(); return .{ .larger = try p.number() }; }
        if (std.mem.eql(u8, upper, "SMALLER")) { p.skipSP(); return .{ .smaller = try p.number() }; }
        if (std.mem.eql(u8, upper, "UID")) { p.skipSP(); return .{ .uid = try p.seqSet() }; }
        if (std.mem.eql(u8, upper, "NOT")) {
            p.skipSP();
            const inner = try p.alloc.create(SearchKey);
            inner.* = (try p.searchKey()) orelse .all;
            return .{ .not = inner };
        }
        if (std.mem.eql(u8, upper, "OR")) {
            p.skipSP();
            const a = try p.alloc.create(SearchKey);
            a.* = (try p.searchKey()) orelse .all;
            p.skipSP();
            const b = try p.alloc.create(SearchKey);
            b.* = (try p.searchKey()) orelse .all;
            return .{ .or_ = .{ .a = a, .b = b } };
        }
        if (std.mem.eql(u8, upper, "HEADER")) {
            p.skipSP();
            const field = try p.astring();
            p.skipSP();
            const value = try p.astring();
            return .{ .header = .{ .field = field, .value = value } };
        }
        // Treat as sequence set
        p.pos = start;
        const ss = p.seqSet() catch return null;
        return .{ .seqset = ss };
    }
};

/// Parse a full IMAP command line (already stripped of \r\n).
/// Caller must read literal continuations separately and concatenate before calling.
pub fn parse(alloc: std.mem.Allocator, line: []const u8) !ParsedCommand {
    var p = Parser{ .buf = line, .pos = 0, .alloc = alloc };

    // tag
    const tag = p.atom();
    p.skipSP();

    // special: "DONE" has no tag in real IDLE termination but clients send it as a bare line
    if (std.ascii.eqlIgnoreCase(tag, "DONE")) {
        return .{ .tag = tag, .cmd = .done };
    }

    const cmd_raw = p.atom();
    const cmd_upper = try std.ascii.allocUpperString(alloc, cmd_raw);
    defer alloc.free(cmd_upper);
    p.skipSP();

    const cmd: Command = blk: {
        if (std.mem.eql(u8, cmd_upper, "CAPABILITY")) break :blk .capability;
        if (std.mem.eql(u8, cmd_upper, "NOOP")) break :blk .noop;
        if (std.mem.eql(u8, cmd_upper, "LOGOUT")) break :blk .logout;
        if (std.mem.eql(u8, cmd_upper, "IDLE")) break :blk .idle;

        if (std.mem.eql(u8, cmd_upper, "LOGIN")) {
            const user = try p.astring(); p.skipSP();
            const pass = try p.astring();
            break :blk .{ .login = .{ .user = user, .pass = pass } };
        }
        if (std.mem.eql(u8, cmd_upper, "SELECT")) break :blk .{ .select = try p.astring() };
        if (std.mem.eql(u8, cmd_upper, "EXAMINE")) break :blk .{ .examine = try p.astring() };
        if (std.mem.eql(u8, cmd_upper, "CREATE")) break :blk .{ .create = try p.astring() };
        if (std.mem.eql(u8, cmd_upper, "DELETE")) break :blk .{ .delete = try p.astring() };
        if (std.mem.eql(u8, cmd_upper, "SUBSCRIBE")) break :blk .{ .subscribe = try p.astring() };
        if (std.mem.eql(u8, cmd_upper, "UNSUBSCRIBE")) break :blk .{ .unsubscribe = try p.astring() };

        if (std.mem.eql(u8, cmd_upper, "RENAME")) {
            const old = try p.astring(); p.skipSP();
            const new = try p.astring();
            break :blk .{ .rename = .{ .old = old, .new = new } };
        }
        if (std.mem.eql(u8, cmd_upper, "LIST") or std.mem.eql(u8, cmd_upper, "LSUB")) {
            const ref = try p.astring(); p.skipSP();
            const pat = try p.astring();
            if (std.mem.eql(u8, cmd_upper, "LSUB"))
                break :blk .{ .lsub = .{ .ref = ref, .pattern = pat } }
            else
                break :blk .{ .list = .{ .ref = ref, .pattern = pat } };
        }
        if (std.mem.eql(u8, cmd_upper, "STATUS")) {
            const mailbox = try p.astring(); p.skipSP();
            const items_start = p.pos;
            var depth: i32 = 0;
            while (p.pos < p.buf.len) {
                if (p.buf[p.pos] == '(') {
                    depth += 1;
                } else if (p.buf[p.pos] == ')') {
                    depth -= 1;
                    p.pos += 1;
                    if (depth == 0) break;
                    continue;
                }
                p.pos += 1;
            }
            break :blk .{ .status = .{ .mailbox = mailbox, .items = p.buf[items_start..p.pos] } };
        }
        if (std.mem.eql(u8, cmd_upper, "APPEND")) {
            const mailbox = try p.astring(); p.skipSP();
            var flags: []const u8 = "";
            var date: []const u8 = "";
            if (p.peek() == '(') { flags = p.flagList(); p.skipSP(); }
            if (p.peek() == '"') { date = try p.quotedString(); p.skipSP(); }
            const size = if (p.eat('{')) blk2: {
                const n = try p.number();
                _ = p.eat('}');
                break :blk2 n;
            } else 0;
            break :blk .{ .append = .{ .mailbox = mailbox, .flags = flags, .date = date, .size = size } };
        }
        if (std.mem.eql(u8, cmd_upper, "CHECK")) break :blk .check;
        if (std.mem.eql(u8, cmd_upper, "CLOSE")) break :blk .close;
        if (std.mem.eql(u8, cmd_upper, "EXPUNGE")) break :blk .expunge;

        const is_uid = std.mem.eql(u8, cmd_upper, "UID");
        var real_cmd = cmd_upper;
        if (is_uid) {
            const sub_raw = p.atom(); p.skipSP();
            real_cmd = try std.ascii.allocUpperString(alloc, sub_raw);
        }

        if (std.mem.eql(u8, real_cmd, "SEARCH")) {
            // skip optional CHARSET
            if (std.mem.startsWith(u8, p.buf[p.pos..], "CHARSET")) {
                _ = p.atom(); p.skipSP(); _ = p.atom(); p.skipSP();
            }
            const keys = try p.searchKeys();
            break :blk .{ .search = .{ .keys = keys, .uid = is_uid } };
        }
        if (std.mem.eql(u8, real_cmd, "FETCH")) {
            const ss = try p.seqSet(); p.skipSP();
            const atts = try p.fetchAttList();
            break :blk .{ .fetch = .{ .seqset = ss, .atts = atts, .uid = is_uid } };
        }
        if (std.mem.eql(u8, real_cmd, "STORE")) {
            const ss = try p.seqSet(); p.skipSP();
            const op_tok = p.atom();
            const op_u = try std.ascii.allocUpperString(alloc, op_tok);
            defer alloc.free(op_u);
            const silent = std.mem.endsWith(u8, op_u, ".SILENT");
            const op: StoreOp = if (std.mem.startsWith(u8, op_u, "+")) .add
                else if (std.mem.startsWith(u8, op_u, "-")) .remove
                else .replace;
            p.skipSP();
            const flags = p.flagList();
            break :blk .{ .store = .{ .seqset = ss, .op = op, .silent = silent, .flags = flags, .uid = is_uid } };
        }
        if (std.mem.eql(u8, real_cmd, "COPY")) {
            const ss = try p.seqSet(); p.skipSP();
            const mailbox = try p.astring();
            break :blk .{ .copy = .{ .seqset = ss, .mailbox = mailbox, .uid = is_uid } };
        }

        // Unknown command — treat as noop
        break :blk .noop;
    };

    return .{ .tag = tag, .cmd = cmd };
}
