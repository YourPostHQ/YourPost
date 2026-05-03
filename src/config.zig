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
    service_port: u16,

    // API security
    service_token: ?[]const u8,

    // Outgoing SMTP relay configuration
    smtp_relay_host: ?[]const u8,
    smtp_relay_port: u16,
    smtp_relay_user: ?[]const u8,
    smtp_relay_password: ?[]const u8,
    smtp_relay_use_tls: bool,

    // TLS configuration for server ports
    smtp_use_tls: bool,
    smtp_tls_cert: ?[]const u8,
    smtp_tls_key: ?[]const u8,
    pop3_use_tls: bool,
    pop3_tls_cert: ?[]const u8,
    pop3_tls_key: ?[]const u8,
    imap_use_tls: bool,
    imap_tls_cert: ?[]const u8,
    imap_tls_key: ?[]const u8,
    // Implicit TLS ports (SMTPS, POP3S, IMAPS)
    smtps_port: u16,
    pop3s_port: u16,
    imaps_port: u16,

    // Connection limits and timeouts
    max_connections: usize,
    connection_timeout_ms: u32,
    read_timeout_ms: u32,

    pub fn fromEnv(alloc: std.mem.Allocator) !Config {
        return .{
            .hostname = envOr(alloc, "YP_HOSTNAME", "localhost"),
            .data_dir = envOr(alloc, "YP_DATA_DIR", "data"),
            .smtp_port = envPortOr("YP_SMTP_PORT", 25),
            .smtp_submission_port = envPortOr("YP_SUBMISSION_PORT", 587),
            .smtp_max_size = 25 * 1024 * 1024,
            .pop3_port = envPortOr("YP_POP3_PORT", 110),
            .imap_port = envPortOr("YP_IMAP_PORT", 143),
            .api_port = envPortOr("YP_API_PORT", 9000),
            .service_port = envPortOr("YP_SERVICE_PORT", 9001),
            .service_token = envOrNull(alloc, "YP_SERVICE_TOKEN"),
            .smtp_relay_host = envOrNull(alloc, "YP_SMTP_RELAY_HOST"),
            .smtp_relay_port = envPortOr("YP_SMTP_RELAY_PORT", 587),
            .smtp_relay_user = envOrNull(alloc, "YP_SMTP_RELAY_USER"),
            .smtp_relay_password = envOrNull(alloc, "YP_SMTP_RELAY_PASSWORD"),
            .smtp_relay_use_tls = envBoolOr("YP_SMTP_RELAY_USE_TLS", true),
            // TLS configuration
            .smtp_use_tls = envBoolOr("YP_SMTP_USE_TLS", false),
            .smtp_tls_cert = envOrNull(alloc, "YP_SMTP_TLS_CERT"),
            .smtp_tls_key = envOrNull(alloc, "YP_SMTP_TLS_KEY"),
            .pop3_use_tls = envBoolOr("YP_POP3_USE_TLS", false),
            .pop3_tls_cert = envOrNull(alloc, "YP_POP3_TLS_CERT"),
            .pop3_tls_key = envOrNull(alloc, "YP_POP3_TLS_KEY"),
            .imap_use_tls = envBoolOr("YP_IMAP_USE_TLS", false),
            .imap_tls_cert = envOrNull(alloc, "YP_IMAP_TLS_CERT"),
            .imap_tls_key = envOrNull(alloc, "YP_IMAP_TLS_KEY"),
            // Implicit TLS ports
            .smtps_port = envPortOr("YP_SMTPS_PORT", 465),
            .pop3s_port = envPortOr("YP_POP3S_PORT", 995),
            .imaps_port = envPortOr("YP_IMAPS_PORT", 993),
            // Connection limits and timeouts
            .max_connections = envPortOr("YP_MAX_CONNECTIONS", 1000),
            .connection_timeout_ms = envU32Or("YP_CONNECTION_TIMEOUT_MS", 300000), // 5 minutes
            .read_timeout_ms = envU32Or("YP_READ_TIMEOUT_MS", 300000), // 5 minutes
        };
    }
};

fn envOr(alloc: std.mem.Allocator, key: []const u8, default: []const u8) []const u8 {
    const raw = c.getenv(key.ptr) orelse return default;
    const span = std.mem.span(raw);
    if (span.len == 0) return default;
    return alloc.dupe(u8, span) catch default;
}

pub fn envOrNull(alloc: std.mem.Allocator, key: []const u8) ?[]const u8 {
    const raw = c.getenv(key.ptr) orelse return null;
    const span = std.mem.span(raw);
    if (span.len == 0) return null;
    return alloc.dupe(u8, span) catch null;
}

fn envPortOr(key: [*:0]const u8, default: u16) u16 {
    const raw = c.getenv(key) orelse return default;
    return std.fmt.parseInt(u16, std.mem.span(raw), 10) catch default;
}

fn envU32Or(key: [*:0]const u8, default: u32) u32 {
    const raw = c.getenv(key) orelse return default;
    return std.fmt.parseInt(u32, std.mem.span(raw), 10) catch default;
}

fn envBoolOr(key: []const u8, default: bool) bool {
    const raw = c.getenv(key.ptr) orelse return default;
    const span = std.mem.span(raw);
    return std.mem.eql(u8, span, "true") or std.mem.eql(u8, span, "1");
}
