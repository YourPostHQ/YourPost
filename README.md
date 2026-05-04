# YourPost - Lightweight Mail Server

[![License: AGPLv3](https://img.shields.io/badge/License-AGPLv3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Zig](https://img.shields.io/badge/Zig-0.16.0-orange.svg)](https://ziglang.org)
[![Docker](https://img.shields.io/badge/Docker-Ready-blue.svg)](https://www.docker.com)
[![CI](https://github.com/YourPostHQ/YourPost/actions/workflows/ci.yml/badge.svg)](https://github.com/YourPostHQ/YourPost/actions/workflows/ci.yml)
[![Docker](https://github.com/YourPostHQ/YourPost/actions/workflows/docker.yml/badge.svg)](https://github.com/YourPostHQ/YourPost/actions/workflows/docker.yml)

A lightweight, high-performance mail server written in Zig, supporting SMTP, POP3, IMAP, and HTTP API with Cloudflare Email Worker integration.

## 🌟 Features

- **SMTP Server** - Receive emails (port 25 for incoming, port 587 for mail client submission)
- **POP3 Server** - Retrieve emails (port 110)
- **IMAP Server** - Modern email access (port 143)
- **HTTP API** - RESTful API for mailbox management
- **Cloudflare Email Worker** - Forward emails from Cloudflare to your server
- **SQLite Storage** - Per-user mailbox storage with multi-domain support
- **TLS Support** - STARTTLS on all protocols (SMTP, POP3, IMAP)
- **SMTP Relay** - Outgoing email through external providers (SendGrid, Mailgun, etc.)
- **Multi-Domain** - Support for multiple email domains
- **Free/Libre Software** - AGPLv3 licensed

## 📖 Quick Start

### 1. Build the Server

```bash
cd /root/yourpost-workspace/yourpost
zig build -Doptimize=ReleaseFast
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

# Add user via API
curl -X POST http://localhost:9000/api/v1/users \
  -H "Content-Type: application/json" \
  -d '{"email": "user@yourdomain.com", "password": "securepassword"}'
```

### 4. Test the API

```bash
# Health check
curl http://localhost:9000/health
# Response: {"status":"ok","service":"yourpost"}

# Send email via HTTP API
curl -X POST http://localhost:9000/api/v1/mailboxes/user@yourdomain.com/send \
  -H "Content-Type: application/json" \
  -d '{
    "to": ["recipient@example.com"],
    "subject": "Hello World",
    "body": "This is a test email"
  }'
```

## 📚 Documentation

Comprehensive documentation is available in the [docs/](docs/) directory:

| Document | Description |
|----------|-------------|
| **[INDEX.md](docs/INDEX.md)** | Documentation overview and quick links |
| **[SETUP.md](docs/SETUP.md)** | Complete setup and installation guide |
| **[CONFIGURATION.md](docs/CONFIGURATION.md)** | All configuration options and examples |
| **[SMTP_RELAY.md](docs/SMTP_RELAY.md)** | Configure outgoing email relay (SendGrid, Mailgun, etc.) |
| **[API.md](docs/API.md)** | Complete API reference with examples |
| **[CLOUDFLARE.md](docs/CLOUDFLARE.md)** | Cloudflare Email Worker integration |
| **[SECURITY.md](docs/SECURITY.md)** | TLS, authentication, and hardening guide |
| **[DOCKER.md](docs/DOCKER.md)** | Docker and Docker Compose deployment |

## ⚙️ Configuration

### Environment Variables

All configuration is done through environment variables:

#### Basic Configuration

```bash
# Server identity
export YP_HOSTNAME=mail.example.com
export YP_DATA_DIR=/var/lib/yourpost

# Port configuration
export YP_SMTP_PORT=25
export YP_SUBMISSION_PORT=587
export YP_POP3_PORT=110
export YP_IMAP_PORT=143
export YP_API_PORT=9000
export YP_SERVICE_PORT=9001
```

#### Security Configuration

```bash
# Service API authentication
export YP_SERVICE_TOKEN=your-secure-token-here

# Connection limits
export YP_MAX_CONNECTIONS=1000
export YP_CONNECTION_TIMEOUT_MS=300000
export YP_READ_TIMEOUT_MS=300000
```

#### TLS Configuration

```bash
# Enable STARTTLS on SMTP
export YP_SMTP_USE_TLS=true
export YP_SMTP_TLS_CERT=/etc/letsencrypt/live/mail.example.com/fullchain.pem
export YP_SMTP_TLS_KEY=/etc/letsencrypt/live/mail.example.com/privkey.pem
```

#### SMTP Relay Configuration

```bash
# SendGrid example
export YP_SMTP_RELAY_HOST=smtp.sendgrid.net
export YP_SMTP_RELAY_PORT=587
export YP_SMTP_RELAY_USER=apikey
export YP_SMTP_RELAY_PASSWORD=SG.xxxxxxxxxxxxxxxxxxxxx
export YP_SMTP_RELAY_USE_TLS=true
```

### Full Configuration Reference

| Variable | Description | Default | Privileged? |
|----------|-------------|---------|-------------|
| `YP_HOSTNAME` | Server hostname | `localhost` | No |
| `YP_DATA_DIR` | Data directory | `data` | No |
| `YP_SMTP_PORT` | SMTP port (incoming) | 25 | ✅ Yes |
| `YP_SUBMISSION_PORT` | SMTP submission (clients) | 587 | ✅ Yes |
| `YP_POP3_PORT` | POP3 port | 110 | ✅ Yes |
| `YP_IMAP_PORT` | IMAP port | 143 | ✅ Yes |
| `YP_API_PORT` | Public HTTP API port | 9000 | No |
| `YP_SERVICE_PORT` | Internal service API port | 9001 | No |
| `YP_SERVICE_TOKEN` | Bearer token for service API | (disabled) | |
| `YP_SMTP_RELAY_HOST` | Outgoing SMTP relay host | (disabled) | |
| `YP_SMTP_RELAY_PORT` | Outgoing SMTP relay port | 587 | |
| `YP_SMTP_RELAY_USER` | SMTP relay username | (disabled) | |
| `YP_SMTP_RELAY_PASSWORD` | SMTP relay password | (disabled) | |
| `YP_SMTP_RELAY_USE_TLS` | Use TLS for relay | `true` | |
| `YP_SMTP_USE_TLS` | Enable STARTTLS on SMTP | `false` | |
| `YP_SMTP_TLS_CERT` | TLS certificate for SMTP | (disabled) | |
| `YP_SMTP_TLS_KEY` | TLS key for SMTP | (disabled) | |
| `YP_POP3_USE_TLS` | Enable TLS on POP3 | `false` | |
| `YP_POP3_TLS_CERT` | TLS certificate for POP3 | (disabled) | |
| `YP_POP3_TLS_KEY` | TLS key for POP3 | (disabled) | |
| `YP_IMAP_USE_TLS` | Enable STARTTLS on IMAP | `false` | |
| `YP_IMAP_TLS_CERT` | TLS certificate for IMAP | (disabled) | |
| `YP_IMAP_TLS_KEY` | TLS key for IMAP | (disabled) | |
| `YP_SMTPS_PORT` | Implicit TLS SMTP (SMTPS) | 465 | ✅ Yes |
| `YP_POP3S_PORT` | Implicit TLS POP3 (POP3S) | 995 | ✅ Yes |
| `YP_IMAPS_PORT` | Implicit TLS IMAP (IMAPS) | 993 | ✅ Yes |
| `YP_MAX_CONNECTIONS` | Max concurrent connections | 1000 | |
| `YP_CONNECTION_TIMEOUT_MS` | Connection idle timeout | 300000 | |
| `YP_READ_TIMEOUT_MS` | Per-read timeout | 300000 | |

**Note:** Ports marked as privileged (< 1024) require root privileges.

## 🚀 Deployment Options

### Systemd Service

The installation script sets up systemd automatically:

```bash
sudo systemctl enable yourpost
sudo systemctl start yourpost
sudo systemctl status yourpost
```

### Docker

```bash
# Using docker-compose
docker-compose up -d

# Or run directly
docker run -d \
  --name yourpost \
  -p 25:25 -p 587:587 -p 9000:9000 \
  -v yourpost-data:/var/lib/yourpost \
  -e YP_HOSTNAME=mail.example.com \
  yourpost:latest
```

See [DOCKER.md](docs/DOCKER.md) for detailed Docker deployment guide.

### Cloudflare Integration

Integrate with Cloudflare Email Workers for email routing:

```bash
# Deploy worker
cd cloudflare-worker
npx wrangler deploy

# Configure email routing in Cloudflare Dashboard
```

See [CLOUDFLARE.md](docs/CLOUDFLARE.md) for detailed setup.

## 🔌 API Endpoints

### Health Check

```bash
curl http://localhost:9000/health
# {"status":"ok","service":"yourpost"}
```

### User Management

```bash
# Create user
curl -X POST http://localhost:9000/api/v1/users \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "password"}'

# List users
curl http://localhost:9000/api/v1/users

# Authenticate
curl -X POST http://localhost:9000/api/v1/auth \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "password"}'
```

### Mailbox Operations

```bash
# List folders
curl http://localhost:9000/api/v1/mailboxes/user@example.com/folders

# List messages
curl http://localhost:9000/api/v1/mailboxes/user@example.com/messages?folder=INBOX

# Get message
curl http://localhost:9000/api/v1/mailboxes/user@example.com/messages/123

# Send email
curl -X POST http://localhost:9000/api/v1/mailboxes/user@example.com/send \
  -H "Content-Type: application/json" \
  -d '{
    "to": ["recipient@example.com"],
    "subject": "Hello",
    "body": "Email body"
  }'
```

### Service API (Internal)

```bash
# Receive email (from Cloudflare Worker)
curl -X POST http://localhost:9001/api/service/incoming \
  -H "Content-Type: message/rfc822" \
  -H "Authorization: Bearer your-token" \
  --data-binary @email.eml
```

See [API.md](docs/API.md) for complete API documentation.

## 📦 Project Structure

```
yourpost/
├── src/
│   ├── config.zig          # Configuration management
│   ├── main.zig            # Main application entry point
│   ├── tls.zig             # TLS utilities
│   ├── api/
│   │   └── server.zig      # HTTP API server
│   ├── db/
│   │   ├── global.zig      # Global database (domains)
│   │   └── user.zig        # User database operations
│   ├── imap/
│   │   ├── parser.zig      # IMAP command parser
│   │   └── server.zig      # IMAP server
│   ├── pop3/
│   │   ├── server.zig      # POP3 server
│   │   └── session.zig     # POP3 session handling
│   └── smtp/
│       ├── server.zig      # SMTP server
│       └── session.zig     # SMTP session handling
├── cloudflare-worker/
│   ├── email-worker.js     # Cloudflare Email Worker
│   └── wrangler.toml       # Worker configuration
├── docs/                   # Documentation
│   ├── INDEX.md           # Documentation index
│   ├── SETUP.md           # Setup guide
│   ├── CONFIGURATION.md   # Configuration reference
│   ├── SMTP_RELAY.md      # SMTP relay setup
│   ├── API.md             # API documentation
│   ├── CLOUDFLARE.md      # Cloudflare integration
│   ├── SECURITY.md        # Security guide
│   └── DOCKER.md          # Docker deployment
├── zig-out/
│   └── bin/
│       └── yourpost        # Compiled binary
├── build.zig
├── build.zig.zon
├── Dockerfile
├── install.sh
├── README.md
└── yourpost.service
```

## 🔒 Security

YourPost includes several security features:

- **TLS/SSL Support**: Enable STARTTLS on all protocols
- **Authentication**: Bearer token for service API
- **Connection Limits**: Prevent resource exhaustion
- **Timeouts**: Automatic connection cleanup
- **Non-root Execution**: Runs as unprivileged user
- **Systemd Hardening**: PrivateTmp, ProtectSystem, NoNewPrivileges

See [SECURITY.md](docs/SECURITY.md) for detailed security guide.

## 📈 Architecture

```

                    YourPost Mail Server                      

                                                             
       
    SMTP   POP3   IMAP   HTTP    Service API          
   Port    Port   Port   Port    (Internal)           
    25     110    143    9000       9001               
       
                                                             
                                                             
                  
                   SQLite Database                   
                   Per-User Mailboxes                
                  

```

### With Cloudflare Integration

```
Sender → Cloudflare Email Routing → Email Worker → YourPost
                                              ↓
                                         SQLite Database
                                              ↓
                                    POP3/IMAP/SMTP Access
```

## 🛠️ Development

### Building

```bash
# Release build
zig build -Doptimize=ReleaseFast

# Debug build
zig build -Doptimize=Debug
```

### Testing

```bash
# Run in development mode
YP_SMTP_PORT=2525 YP_API_PORT=9000 ./zig-out/bin/yourpost

# Test health endpoint
curl http://localhost:9000/health

# Test user creation
curl -X POST http://localhost:9000/api/v1/users \
  -H "Content-Type: application/json" \
  -d '{"email": "test@example.com", "password": "test123"}'
```

## 🤝 Contributing

Contributions are welcome! Areas for improvement:

- Additional authentication methods (OAuth, MFA)
- Webmail interface
- Advanced spam filtering
- Email forwarding rules
- Sieve script support
- Better search functionality

Please see the contributing guidelines for details.

## 📄 License

YourPost is free software licensed under the **AGPLv3**. See [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

- [Zig Programming Language](https://ziglang.org/)
- [SQLite](https://sqlite.org/)
- [Cloudflare Workers](https://workers.cloudflare.com/)
- All contributors and users

## 📞 Support

- **Documentation**: [docs/](docs/)
- **Issues**: [GitHub Issues](https://github.com/YourPostHQ/YourPost/issues)
- **Discussions**: [GitHub Discussions](https://github.com/YourPostHQ/YourPost/discussions)

---

**Version**: 1.0.0  
**Last Updated**: May 2026  
**Made with 💚 in Zig**