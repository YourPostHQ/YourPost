# YourPost - Lightweight Mail Server

A lightweight mail server written in Zig, supporting SMTP, POP3, IMAP, and HTTP API with Cloudflare Email Worker integration.

## Features

- **SMTP Server** - Receive emails (port 25 for incoming, port 587 for mail client submission)
- **POP3 Server** - Retrieve emails (port 110)
- **IMAP Server** - Modern email access (port 143)
- **HTTP API** - RESTful API for mailbox management
- **Cloudflare Email Worker** - Forward emails from Cloudflare to your server
- **SQLite Storage** - Per-user mailbox storage with multi-domain support
- **Free/Libre Software** - AGPLv3 licensed

## Quick Start

### 1. Build the Server

```bash
cd /home/devstroop/yourpost
zig build
```

### 2. Run the Server

```bash
# Use non-privileged ports (recommended for development)
YP_SMTP_PORT=2525 YP_SUBMISSION_PORT=2587 YP_POP3_PORT=2110 YP_IMAP_PORT=2143 YP_API_PORT=9000 ./zig-out/bin/yourpost

# Or use default ports (requires root/sudo for ports < 1024)
sudo ./zig-out/bin/yourpost
```

**Note:** The server uses two SMTP ports:
- **Port 25** (or `YP_SMTP_PORT`): Standard SMTP for receiving emails from other mail servers
- **Port 587** (or `YP_SUBMISSION_PORT`): Submission port for mail clients to send outgoing emails

Ports below 1024 are privileged and require root. For development, use non-privileged alternatives (e.g., 2525, 2587).

### 3. Create a User

```bash
# Add domain
sqlite3 data/global.db "INSERT OR IGNORE INTO domains (domain) VALUES ('yourdomain.com');"

# Add user (password will be hashed)
# Use the provided tool or API to create users
```

### 4. Test the API

```bash
# Health check
curl http://localhost:9000/health

# Send email via HTTP API (Cloudflare Worker uses this)
curl -X POST http://localhost:9000/incoming \
  -H "Content-Type: message/rfc822" \
  --data-binary @email.eml
```

## Configuration

### Environment Variables

| Variable | Description | Default | Privileged? |
|----------|-------------|---------|-------------|
| `YP_SMTP_PORT` | SMTP port (incoming from other servers) | 25 | ✅ Yes |
| `YP_SUBMISSION_PORT` | SMTP submission port (mail clients) | 587 | ✅ Yes |
| `YP_POP3_PORT` | POP3 port | 110 | ✅ Yes |
| `YP_IMAP_PORT` | IMAP port | 143 | ✅ Yes |
| `YP_API_PORT` | Public HTTP API port (`/api/v1/*`, `/health`) | 9000 | No |
| `YP_SERVICE_PORT` | Internal service API port (`/api/service/*`) | 9001 | No |
| `YP_SERVICE_TOKEN` | Bearer token for `/api/service/*` endpoints | (disabled) | |
| `YP_HOSTNAME` | Server hostname | localhost | |
| `YP_DATA_DIR` | Data directory | data | |
| `YP_SMTP_RELAY_HOST` | Outgoing SMTP relay host | (disabled) | |
| `YP_SMTP_RELAY_PORT` | Outgoing SMTP relay port | 587 | |
| `YP_SMTP_RELAY_USER` | SMTP relay authentication username | (disabled) | |
| `YP_SMTP_RELAY_PASSWORD` | SMTP relay authentication password/API key | (disabled) | |
| `YP_SMTP_RELAY_USE_TLS` | Use TLS for SMTP relay | true | |
| `YP_SMTP_USE_TLS` | Enable STARTTLS on SMTP ports | false | |
| `YP_SMTP_TLS_CERT` | Path to TLS certificate file for SMTP | (disabled) | |
| `YP_SMTP_TLS_KEY` | Path to TLS key file for SMTP | (disabled) | |
| `YP_SMTPS_PORT` | Implicit TLS SMTP port (SMTPS) | 465 | ✅ Yes |
| `YP_POP3_USE_TLS` | Enable TLS on POP3 port | false | |
| `YP_POP3_TLS_CERT` | Path to TLS certificate file for POP3 | (disabled) | |
| `YP_POP3_TLS_KEY` | Path to TLS key file for POP3 | (disabled) | |
| `YP_POP3S_PORT` | Implicit TLS POP3 port (POP3S) | 995 | ✅ Yes |
| `YP_IMAP_USE_TLS` | Enable STARTTLS on IMAP port | false | |
| `YP_IMAP_TLS_CERT` | Path to TLS certificate file for IMAP | (disabled) | |
| `YP_IMAP_TLS_KEY` | Path to TLS key file for IMAP | (disabled) | |
| `YP_IMAPS_PORT` | Implicit TLS IMAP port (IMAPS) | 993 | ✅ Yes |
| `YP_MAX_CONNECTIONS` | Maximum concurrent connections per server | 1000 | |
| `YP_CONNECTION_TIMEOUT_MS` | Connection idle timeout (ms) | 300000 | |
| `YP_READ_TIMEOUT_MS` | Per-read timeout (ms) | 300000 | |

**Note:** Ports marked as privileged (< 1024) require root privileges. For development, use non-privileged ports:
```bash
export YP_SMTP_PORT=2525
export YP_SUBMISSION_PORT=2587
export YP_POP3_PORT=2110
export YP_IMAP_PORT=2143
```

### Outgoing SMTP Relay Configuration

To enable outgoing email delivery through an external SMTP server (e.g., SendGrid, AWS SES), configure these variables:

```bash
# Example: SendGrid configuration
export YP_SMTP_RELAY_HOST=smtp.sendgrid.net
export YP_SMTP_RELAY_PORT=587
export YP_SMTP_RELAY_USER=apikey
export YP_SMTP_RELAY_PASSWORD=SG.xxxxxxxxxxxxxxxxxxxxx
export YP_SMTP_RELAY_USE_TLS=true

# Example: Gmail configuration
export YP_SMTP_RELAY_HOST=smtp.gmail.com
export YP_SMTP_RELAY_PORT=465
export YP_SMTP_RELAY_USER=your-email@gmail.com
export YP_SMTP_RELAY_PASSWORD=your-app-password
export YP_SMTP_RELAY_USE_TLS=true

# Run the server with relay configuration
./zig-out/bin/yourpost
```

**Note:** When a relay host is configured, outgoing emails will be forwarded through the specified SMTP server instead of being sent directly.

### Cloudflare Email Worker Setup

1. **Generate an API key:**
   ```bash
   # Generate a secure random API key
   openssl rand -hex 32
   ```

2. **Set the API key on your server:**
   ```bash
   export YP_SERVICE_TOKEN=your-generated-api-key-here
   ./zig-out/bin/yourpost
   ```

3. **Deploy the Worker with the API key:**
   ```bash
   cd cloudflare-worker
   npx wrangler secret put YOURPOST_SERVICE_URL https://yourpost.yourdomain.com:9001
   npx wrangler secret put YOURPOST_SERVICE_TOKEN your-generated-api-key-here
   npx wrangler deploy
   ```

4. **Configure Email Routing:**
   - Go to Cloudflare Dashboard → Email Routing
   - Add route: `*@yourdomain.com` → Send to Worker → (choose your worker)

**Security Note:** When `YP_SERVICE_TOKEN` is set, all `/api/service/*` endpoints on the service port require an `Authorization: Bearer <SERVICE_TOKEN>` header. If not set, the service port accepts requests without authentication (useful for development). The Cloudflare Tunnel should point to the service port (9001), not the public API port.

4. **Set up Cloudflare Tunnel (optional but recommended):**
   ```bash
   cloudflared tunnel login
   cloudflared tunnel create yourpost
   cloudflared tunnel route-dns yourpost yourdomain.com
   cloudflared tunnel ingress http://localhost:9001
   ```

## API Endpoints

### Health Check
```
GET /health
Response: {"status":"ok","service":"yourpost"}
```

### Service API (port 9001 — internal, Cloudflare Worker)

These endpoints live on `YP_SERVICE_PORT` (default 9001) and are protected by `YP_SERVICE_TOKEN`.

#### Receive Email
```
POST /api/service/incoming
Content-Type: message/rfc822
Authorization: Bearer <SERVICE_TOKEN>  (required if YP_SERVICE_TOKEN is set)
Body: Raw email content

Response: {"status":"delivered"}
```

### Public API (port 9000)

#### Health Checks
```
GET /health          → {"status":"ok","service":"yourpost","version":"1.0.0"}
GET /health/ready    → 200 or 503 depending on readiness
GET /health/live     → {"status":"alive","service":"yourpost","uptime":"unknown"}
```

#### Users
```
GET    /api/v1/users              → list all users
POST   /api/v1/users              → create user  body: {"email":"...","password":"..."}
DELETE /api/v1/users/{email}      → deactivate user
POST   /api/v1/auth               → authenticate  body: {"email":"...","password":"..."}
```

#### Mailboxes
```
GET /api/v1/mailboxes/{user}/folders              → list folders
GET /api/v1/mailboxes/{user}/messages?folder=INBOX → list messages in folder
GET /api/v1/mailboxes/{user}/messages/{id}        → get single message (marks as seen)
DELETE /api/v1/mailboxes/{user}/messages/{id}     → delete message (marks \Deleted)
POST /api/v1/mailboxes/{user}/send                → send email  body: {"to":"...","subject":"...","body":"..."}
```

## Mailbox Storage

Each user has a separate SQLite database at:
```
data/mailboxes/{email}.db
```

**Note:** The filename uses the **full email address** (e.g., `user@example.com.db`), not just the username. This enables multi-domain support where the same username can exist on different domains.

The database contains:
- `folders` table - IMAP folders (INBOX, Sent, Trash, etc.)
- `messages` table - Email messages with flags, internal date, and raw content

## Architecture

```
Gmail/External
     ↓
Cloudflare Email Routing
     ↓
Cloudflare Worker (email-worker.js)
     ↓
Cloudflare Tunnel (cloudflared → localhost:9001)
     ↓
yourpost Service API (POST /api/service/incoming)
     ↓
SQLite Mailbox (data/mailboxes/{email}.db)
     ↓
POP3/IMAP Access (multi-domain support)
```

## Project Structure

```
yourpost/
├── src/
│   ├── main.zig          # Entry point, graceful shutdown, daemon mode
│   ├── config.zig         # Configuration (env vars)
│   ├── api/
│   │   └── server.zig     # Public API (port 9000) + Service API (port 9001)
│   ├── smtp/
│   │   ├── server.zig     # SMTP listener
│   │   └── session.zig    # SMTP session + relay
│   ├── pop3/
│   │   ├── server.zig     # POP3 listener
│   │   └── session.zig    # POP3 session
│   ├── imap/
│   │   ├── server.zig     # IMAP listener
│   │   ├── session.zig    # IMAP session
│   │   └── parser.zig     # IMAP command parser
│   ├── db/
│   │   ├── global.zig     # Global auth database (users, domains)
│   │   └── user.zig       # Per-user mailbox database
│   └── tls.zig            # TLS helpers
├── cloudflare-worker/
│   ├── email-worker.js  # Cloudflare Email Worker
│   └── wrangler.toml     # Wrangler config
├── logrotate.d/
│   └── yourpost          # logrotate config (deploy to /etc/logrotate.d/)
└── data/
    ├── global.db          # Global database (users, domains)
    └── mailboxes/         # Per-user mailbox databases
```

## License

AGPLv3 - See LICENSE file for details.

## Troubleshooting

### Email not received?
1. Check Cloudflare Worker logs: `npx wrangler tail`
2. Check yourpost server logs
3. Verify Cloudflare Tunnel is running: `cloudflared tunnel list`
4. Test locally: `curl -X POST http://localhost:9000/incoming -H "Content-Type: message/rfc822" --data-binary @test.eml`

### Build errors?
- Make sure you're using Zig 0.16.0 or later
- Check that sqlite3 development files are installed: `apt-get install libsqlite3-dev`

### Permission denied?
- Use non-privileged ports (2525, 2110, 2143, 9000)
- Or run with sudo for standard ports (25, 110, 143, 80)
