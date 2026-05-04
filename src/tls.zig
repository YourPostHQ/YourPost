const std = @import("std");
const c = @cImport({
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/err.h");
    @cInclude("openssl/bio.h");
});

pub const TlsContext = struct {
    ctx: *c.SSL_CTX,

    pub fn init(cert_path: []const u8, key_path: []const u8) !TlsContext {
        // OpenSSL 3+ initializes automatically; no explicit init calls needed.
        const ctx = c.SSL_CTX_new(c.TLS_server_method()) orelse return error.TlsInitFailed;

        // Load certificate
        if (c.SSL_CTX_use_certificate_file(ctx, cert_path.ptr, c.SSL_FILETYPE_PEM) != 1) {
            c.SSL_CTX_free(ctx);
            return error.TlsCertLoadFailed;
        }

        // Load private key
        if (c.SSL_CTX_use_PrivateKey_file(ctx, key_path.ptr, c.SSL_FILETYPE_PEM) != 1) {
            c.SSL_CTX_free(ctx);
            return error.TlsKeyLoadFailed;
        }

        // Verify key matches cert
        if (c.SSL_CTX_check_private_key(ctx) != 1) {
            c.SSL_CTX_free(ctx);
            return error.TlsKeyMismatch;
        }

        return TlsContext{ .ctx = ctx };
    }

    pub fn deinit(self: TlsContext) void {
        c.SSL_CTX_free(self.ctx);
    }

    pub fn createSsl(self: TlsContext, socket_fd: c.int) ?*c.SSL {
        const ssl = c.SSL_new(self.ctx) orelse return null;
        if (c.SSL_set_fd(ssl, socket_fd) != 1) {
            c.SSL_free(ssl);
            return null;
        }
        return ssl;
    }
};

pub fn performHandshake(ssl: *c.SSL) bool {
    const ret = c.SSL_accept(ssl);
    if (ret != 1) {
        const err = c.SSL_get_error(ssl, ret);
        std.log.err("TLS handshake failed: error {d}", .{err});
        return false;
    }
    return true;
}

pub fn readTls(ssl: *c.SSL, buf: []u8) isize {
    const n = c.SSL_read(ssl, buf.ptr, @intCast(buf.len));
    return if (n >= 0) @as(isize, @intCast(n)) else -1;
}

pub fn writeTls(ssl: *c.SSL, buf: []const u8) isize {
    const n = c.SSL_write(ssl, buf.ptr, @intCast(buf.len));
    return if (n >= 0) @as(isize, @intCast(n)) else -1;
}

pub fn closeTls(ssl: *c.SSL) void {
    c.SSL_shutdown(ssl);
    c.SSL_free(ssl);
}
