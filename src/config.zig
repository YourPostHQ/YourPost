const std = @import("std");
const c = @cImport(@cInclude("stdlib.h"));

pub const Config = struct {
    hostname: []const u8,
    data_dir: []const u8,

    smtp_port: u16,
    smtp_submission_port: u16,
    smtp_max_size: usize,

    pop3_port: u16,
    imap_port: u16,

    api_port: u16,

    // Outgoing SMTP relay configuration
    smtp_relay_host: ?[]const u8,
    smtp_relay_port: u16,
    smtp_relay_user: ?[]const u8,
    smtp_relay_password: ?[]const u8,
    smtp_relay_use_tls: bool,

    pub fn fromEnv(alloc: std.mem.Allocator) !Config {
        return .{
            .hostname = envOr(alloc, "YP_HOSTNAME", "localhost"),
            .data_dir = envOr(alloc, "YP_DATA_DIR", "data"),
            .smtp_port = envPortOr("YP_SMTP_PORT", 25),
            .smtp_submission_port = envPortOr("YP_SUBMISSION_PORT", 587),
            .smtp_max_size = 25 * 1024 * 1024,
            .pop3_port = envPortOr("YP_POP3_PORT", 110),
            .imap_port = envPortOr("YP_IMAP_PORT", 143),
            .api_port = envPortOr("YP_API_PORT", 8080),
            .smtp_relay_host = envOrNull(alloc, "YP_SMTP_RELAY_HOST"),
            .smtp_relay_port = envPortOr("YP_SMTP_RELAY_PORT", 587),
            .smtp_relay_user = envOrNull(alloc, "YP_SMTP_RELAY_USER"),
            .smtp_relay_password = envOrNull(alloc, "YP_SMTP_RELAY_PASSWORD"),
            .smtp_relay_use_tls = envBoolOr("YP_SMTP_RELAY_USE_TLS", true),
        };
    }
};

fn envOr(alloc: std.mem.Allocator, key: []const u8, default: []const u8) []const u8 {
    const raw = c.getenv(key.ptr) orelse return default;
    const span = std.mem.span(raw);
    if (span.len == 0) return default;
    return alloc.dupe(u8, span) catch default;
}

fn envOrNull(alloc: std.mem.Allocator, key: []const u8) ?[]const u8 {
    const raw = c.getenv(key.ptr) orelse return null;
    const span = std.mem.span(raw);
    if (span.len == 0) return null;
    return alloc.dupe(u8, span) catch null;
}

fn envPortOr(key: [*:0]const u8, default: u16) u16 {
    const raw = c.getenv(key) orelse return default;
    return std.fmt.parseInt(u16, std.mem.span(raw), 10) catch default;
}

fn envBoolOr(key: []const u8, default: bool) bool {
    const raw = c.getenv(key.ptr) orelse return default;
    const span = std.mem.span(raw);
    return std.mem.eql(u8, span, "true") or std.mem.eql(u8, span, "1");
}
