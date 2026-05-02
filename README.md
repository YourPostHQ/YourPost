# YourPost - Lightweight Mail Server

A lightweight mail server written in Zig, supporting SMTP, POP3, IMAP, and HTTP API with Cloudflare Email Worker integration.

## Features

- **SMTP Server** - Receive emails (port 25/587)
- **POP3 Server** - Retrieve emails (port 110)
- **IMAP Server** - Modern email access (port 143)
- **HTTP API** - RESTful API for mailbox management
- **Cloudflare Email Worker** - Forward emails from Cloudflare to your server
- **SQLite Storage** - Per-user mailbox storage
- **Free/Libre Software** - AGPLv3 licensed

## Quick Start

### 1. Build the Server

```bash
cd /home/devstroop/yourpost
zig build
```

### 2. Run the Server

```bash
# Use non-privileged ports (recommended)
YP_SMTP_PORT=2525 YP_POP3_PORT=2110 YP_IMAP_PORT=2143 YP_API_PORT=9000 ./zig-out/bin/yourpost

# Or use default ports (requires root)
sudo ./zig-out/bin/yourpost
```

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

| Variable | Description | Default |
|----------|-------------|---------|
| `YP_SMTP_PORT` | SMTP port | 25 |
| `YP_POP3_PORT` | POP3 port | 110 |
| `YP_IMAP_PORT` | IMAP port | 143 |
| `YP_API_PORT` | HTTP API port | 9000 |
| `YP_HOSTNAME` | Server hostname | localhost |
| `YP_DATA_DIR` | Data directory | data |
| `YP_SMTP_RELAY_HOST` | Outgoing SMTP relay host | (disabled) |
| `YP_SMTP_RELAY_PORT` | Outgoing SMTP relay port | 587 |
| `YP_SMTP_RELAY_USER` | SMTP relay authentication username | (disabled) |
| `YP_SMTP_RELAY_PASSWORD` | SMTP relay authentication password/API key | (disabled) |
| `YP_SMTP_RELAY_USE_TLS` | Use TLS for SMTP relay | true |

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

1. **Deploy the Worker:**
   ```bash
   cd cloudflare-worker
   npx wrangler deploy
   ```

2. **Set the secret:**
   ```bash
   npx wrangler secret put YOURPOST_URL https://yourpost.yourdomain.com
   ```

3. **Configure Email Routing:**
   - Go to Cloudflare Dashboard → Email Routing
   - Add route: `*@yourdomain.com` → Send to Worker → (choose your worker)

4. **Set up Cloudflare Tunnel (optional but recommended):**
   ```bash
   cloudflared tunnel login
   cloudflared tunnel create yourpost
   cloudflared tunnel route-dns yourpost yourdomain.com
   cloudflared tunnel ingress http://localhost:9000
   ```

## API Endpoints

### Health Check
```
GET /health
Response: {"status":"ok","service":"yourpost"}
```

### Receive Email (for Cloudflare Worker)
```
POST /incoming
Content-Type: message/rfc822
Body: Raw email content

Response: {"status":"delivered"}
```

### List Mailbox Folders
```
GET /mailboxes/{user}/folders
```

## Mailbox Storage

Each user has a separate SQLite database at:
```
data/mailboxes/{username}.db
```

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
Cloudflare Tunnel (cloudflared)
     ↓
yourpost HTTP API (/incoming)
     ↓
SQLite Mailbox (data/mailboxes/{user}.db)
     ↓
POP3/IMAP Access
```

## Project Structure

```
yourpost/
├── src/
│   ├── main.zig          # Entry point
│   ├── config.zig         # Configuration
│   ├── api/
│   │   └── server.zig     # HTTP API server
│   ├── smtp/
│   │   └── server.zig     # SMTP server
│   ├── pop3/
│   │   └── server.zig     # POP3 server
│   ├── imap/
│   │   └── server.zig     # IMAP server
│   └── storage/
│       ├── global_db.zig   # Global auth database
│       └── user_db.zig     # Per-user mailbox database
├── cloudflare-worker/
│   ├── email-worker.js  # Cloudflare Email Worker
│   └── wrangler.toml     # Wrangler config
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
