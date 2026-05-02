const std = @import("std");
const config = @import("config.zig");
const GlobalDb = @import("storage/global_db.zig").GlobalDb;
const smtp = @import("smtp/server.zig");
const pop3 = @import("pop3/server.zig");
const imap = @import("imap/server.zig");
const api = @import("api/server.zig");

pub fn main(init: std.process.Init) !void {
    const alloc = std.heap.page_allocator;
    const cfg = try config.Config.fromEnv(alloc);

    const cwd = std.Io.Dir.cwd();
    _ = try std.Io.Dir.createDirPathStatus(cwd, init.io, cfg.data_dir, .default_dir);
    const mailbox_dir = try std.fmt.allocPrint(alloc, "{s}/mailboxes", .{cfg.data_dir});
    defer alloc.free(mailbox_dir);
    _ = try std.Io.Dir.createDirPathStatus(cwd, init.io, mailbox_dir, .default_dir);

    const global_db_path_str = try std.fmt.allocPrint(alloc, "{s}/global.db", .{cfg.data_dir});
    defer alloc.free(global_db_path_str);
    const global_db_path = try alloc.dupeZ(u8, global_db_path_str);
    defer alloc.free(global_db_path);
    var global_db = try GlobalDb.open(global_db_path);
    defer global_db.close();

    const smtp_deps = smtp.Deps{
        .global_db = &global_db,
        .alloc = alloc,
        .hostname = cfg.hostname,
        .data_dir = cfg.data_dir,
        .max_size = cfg.smtp_max_size,
        .io = init.io,
        .relay_host = cfg.smtp_relay_host,
        .relay_port = cfg.smtp_relay_port,
        .relay_user = cfg.smtp_relay_user,
        .relay_password = cfg.smtp_relay_password,
        .relay_use_tls = cfg.smtp_relay_use_tls,
    };
    const pop3_deps = pop3.Deps{
        .global_db = &global_db,
        .alloc = alloc,
        .hostname = cfg.hostname,
        .data_dir = cfg.data_dir,
    };
    const imap_deps = imap.Deps{
        .global_db = &global_db,
        .alloc = alloc,
        .hostname = cfg.hostname,
        .data_dir = cfg.data_dir,
    };
    const api_deps = api.Deps{
        .global_db = &global_db,
        .alloc = alloc,
        .hostname = cfg.hostname,
        .data_dir = cfg.data_dir,
        .api_port = cfg.api_port,
        .io = init.io,
    };

    (try std.Thread.spawn(.{}, smtp.listen, .{ init.io, cfg.smtp_port, smtp_deps })).detach();
    (try std.Thread.spawn(.{}, pop3.listen, .{ init.io, cfg.pop3_port, pop3_deps })).detach();
    (try std.Thread.spawn(.{}, imap.listen, .{ init.io, cfg.imap_port, imap_deps })).detach();
    (try std.Thread.spawn(.{}, api.listen, .{ init.io, api_deps })).detach();

    std.log.info("yourpost started on SMTP :{d}, POP3 :{d}, IMAP :{d}, API :{d}", .{
        cfg.smtp_port,
        cfg.pop3_port,
        cfg.imap_port,
        cfg.api_port,
    });

    while (true) {
        std.Io.sleep(init.io, std.Io.Duration.fromSeconds(1), .awake) catch {};
    }
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    try std.testing.fuzz({}, testOne, .{});
}

fn testOne(context: void, smith: *std.testing.Smith) !void {
    _ = context;
    // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!

    const gpa = std.testing.allocator;
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(gpa);
    while (!smith.eos()) switch (smith.value(enum { add_data, dup_data })) {
        .add_data => {
            const slice = try list.addManyAsSlice(gpa, smith.value(u4));
            smith.bytes(slice);
        },
        .dup_data => {
            if (list.items.len == 0) continue;
            if (list.items.len > std.math.maxInt(u32)) return error.SkipZigTest;
            const len = smith.valueRangeAtMost(u32, 1, @min(32, list.items.len));
            const off = smith.valueRangeAtMost(u32, 0, @intCast(list.items.len - len));
            try list.appendSlice(gpa, list.items[off..][0..len]);
            try std.testing.expectEqualSlices(
                u8,
                list.items[off..][0..len],
                list.items[list.items.len - len ..],
            );
        },
    };
}
