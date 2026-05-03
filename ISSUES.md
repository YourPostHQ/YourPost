# YourPost Issues Tracker

This file tracks known bugs, issues, and improvement opportunities in the YourPost mail server project.

---

## Issue #1: HTTP API Multi-Domain Data Isolation Bug

**Status:** 🟢 Closed  
**Severity:** Critical  
**Discovered:** 2026-05-02  
**Fixed:** 2026-05-02  
**Affected Component:** `src/api/server.zig` (HTTP API `/incoming` endpoint)

### Description

The HTTP API endpoint for receiving emails (used by Cloudflare Email Worker integration) incorrectly extracts only the local part of the recipient's email address when determining the user database file path. This breaks multi-domain support and causes data isolation failures.

### Technical Details

**Location:** `src/api/server.zig:186`

**Buggy Code:**
```zig
const at_pos = std.mem.indexOfScalar(u8, recipient, '@') orelse {
    std.log.err("No @ in recipient: {s}", .{recipient});
    // ...
};
const username = recipient[0..at_pos];  // ← BUG: Only extracts "sameuser"
```

**Impact:**
- Emails for `sameuser@example.com` and `sameuser@demo.com` both route to `mailboxes/sameuser.db`
- Complete loss of data isolation between domains
- Emails delivered via HTTP API are inaccessible via IMAP/POP3 (which correctly use full email addresses)

**Correct Behavior (reference implementations):**
- SMTP (`src/smtp/session.zig:215`): ✓ Uses full email for DB path
- IMAP (`src/imap/session.zig:82`): ✓ Uses full email for DB path  
- POP3 (`src/pop3/session.zig:63`): ✓ Uses full email for DB path

### Fix Applied

**Change in `src/api/server.zig`:**
```zig
// FROM (buggy):
const at_pos = std.mem.indexOfScalar(u8, recipient, '@') orelse { ... };
const username = recipient[0..at_pos];

// TO (correct):
const username = recipient;  // Use full email address
```

The fix removes the `@` extraction logic and now uses the full email address as the username, consistent with SMTP, IMAP, and POP3 implementations.

### Verification Steps

1. Set up two domains (e.g., `example.com` and `demo.com`)
2. Create `sameuser` on both domains
3. Send email via Cloudflare Worker → HTTP API to both addresses
4. Verify separate DB files: `mailboxes/sameuser@example.com.db` and `mailboxes/sameuser@demo.com.db`

### Related Files
- `src/api/server.zig` - HTTP API endpoint (bug location)
- `src/smtp/session.zig` - SMTP delivery (correct implementation reference)
- `src/imap/session.zig` - IMAP auth (correct implementation reference)
- `src/pop3/session.zig` - POP3 auth (correct implementation reference)
- `src/db/global.zig` - User storage (uses full email as unique key ✓)

---

## Issue #2: Noisy Stack Trace on Privileged Port Bind Failure

**Status:** 🟢 Fixed  
**Severity:** Medium  
**Discovered:** 2026-05-02  
**Fixed:** 2026-05-02  
**Affected Component:** `src/smtp/server.zig`, `src/pop3/server.zig`, `src/imap/server.zig`, `src/api/server.zig`

### Description

When attempting to bind to privileged ports (< 1024) without root privileges, the server produced a noisy stack trace from the Zig standard library instead of a clear error message.

### Technical Details

**Original Error Output:**
```
unexpected errno: 13
/home/devstroop/.vscode-server-insiders/.../std/posix.zig:1672:40: 0x114d1f0 in unexpectedErrno (std.zig)
        std.debug.dumpCurrentStackTrace(.{});
                                       ^
... (10+ lines of stack trace)
```

The error occurred because:
1. Zig's `std.Io.net.IpAddress.listen()` calls `posix.unexpectedErrno(err)` which prints debug info
2. The stack trace appeared before our error handler could catch it

**Fix Applied:**

Added proactive check for privileged ports (< 1024) before attempting to bind:

```zig
pub fn listen(io: std.Io, port: u16, deps: Deps) void {
    // Check for privileged port before attempting to bind (prevents noisy stack trace)
    if (port < 1024) {
        std.log.err("SMTP: Cannot bind to privileged port {d} (ports < 1024 require root). Use port > 1024 or run with sudo.", .{port});
        return;
    }
    // ... rest of the function
}
```

Also changed `listen` functions to return `void` instead of `!void` to prevent thread panic on errors.

**Result:** Clean error message without stack trace:
```
error: SMTP: Cannot bind to privileged port 587 (ports < 1024 require root). Use port > 1024 or run with sudo.
```

### Files Modified
- `src/smtp/server.zig` - Added privileged port check, changed return type to `void`
- `src/pop3/server.zig` - Added privileged port check, changed return type to `void`
- `src/imap/server.zig` - Added privileged port check, changed return type to `void`
- `src/api/server.zig` - Added privileged port check, changed return type to `void`
- `src/main.zig` - Updated thread spawning (removed `try` since listen now returns `void`)

---

## Issue #3: SMTP Submission Port Documentation & Default

**Status:** 🟢 Closed  
**Severity:** Medium  
**Discovered:** 2026-05-02  
**Fixed:** 2026-05-02  
**Affected Component:** `README.md`, `src/config.zig`, `src/main.zig`

### Description

The SMTP submission port (587) is now started alongside the standard SMTP port (25), but this change lacks:
1. Clear documentation in README or setup instructions
2. The default port 587 is privileged (< 1024), causing permission errors for non-root users
3. No clear guidance on setting `YP_SUBMISSION_PORT` environment variable

### Technical Details

**Location:** `src/main.zig:61`
```zig
(try std.Thread.spawn(.{}, smtp.listen, .{ init.io, cfg.smtp_submission_port, smtp_deps })).detach();
```

**Default Configuration:** `src/config.zig:23`
```zig
.smtp_submission_port = envPortOr("YP_SUBMISSION_PORT", 587),
```

**Issue:** Port 587 is privileged (requires root or capabilities), causing `errno: 13` (EACCES) for regular users.

### Fix Applied

Updated `README.md` with:
1. Clear explanation of two SMTP ports (25 for incoming, 587 for submission)
2. Added `YP_SUBMISSION_PORT` to environment variables table with privileged port warning
3. Provided non-privileged port examples for development (2525, 2587, 2110, 2143)
4. Updated mailbox storage documentation to clarify full email addresses are used (multi-domain support)
5. Updated architecture diagram to show `{email}.db` instead of `{user}.db`

### Files Modified
- `README.md` - Complete documentation update

### Verification Steps

1. Start server without setting `YP_SUBMISSION_PORT` - should fail with errno 13 on port 587
2. Start with `YP_SUBMISSION_PORT=2587` - should work
3. Check documentation clearly explains both ports

### Related Files
- `src/config.zig` - Default port configuration
- `src/main.zig` - Server startup
- `README.md` - Documentation (needs update)

---

## Issue Template

```markdown
## Issue #N: [Title]

**Status:** 🟢 Closed / 🟡 In Progress / 🔴 Open  
**Severity:** Critical / High / Medium / Low  
**Discovered:** YYYY-MM-DD  
**Fixed:** YYYY-MM-DD (if applicable)  
**Affected Component:** [file path]

### Description
[Detailed description of the issue]

### Technical Details
[Code snippets, error messages, etc.]

### Fix Required
[Description of fix or link to commit/PR]

### Verification Steps
[Steps to verify the fix works]
```

---

## Notes

- Keep issues sorted by status (Open → In Progress → Closed)
- Update the "Fixed" date when resolving issues
- Reference commits/PRs when linking to fixes
- Use severity levels to prioritize work
