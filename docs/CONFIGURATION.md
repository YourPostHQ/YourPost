# Configuration Guide

This guide provides detailed information about configuring YourPost for various deployment scenarios.

## Table of Contents

- [Environment Variables](#environment-variables)
- [Port Configuration](#port-configuration)
- [TLS/SSL Configuration](#tlsssl-configuration)
- [SMTP Relay Configuration](#smtp-relay-configuration)
- [Security Configuration](#security-configuration)
- [Connection Limits](#connection-limits)
- [Multi-Domain Support](#multi-domain-support)
- [Configuration Examples](#configuration-examples)

## Environment Variables

All configuration in YourPost is done through environment variables. Below is the complete reference:

### Server Identity

| Variable | Description | Default | Privileged? |
|----------|-------------|---------|-------------|
| `YP_HOSTNAME` | Server hostname (used in greetings) | `localhost` | No |
| `YP_DATA_DIR` | Base directory for data storage | `data` | No |

### Port Configuration

| Variable | Description | Default | Privileged? |
|----------|-------------|---------|-------------|
| `YP_SMTP_PORT` | SMTP port (incoming from other servers) | 25 | ✅ Yes |
| `YP_SUBMISSION_PORT` | SMTP submission port (mail clients) | 587 | ✅ Yes |
| `YP_POP3_PORT` | POP3 port | 110 | ✅ Yes |
| `YP_IMAP_PORT` | IMAP port | 143 | ✅ Yes |
| `YP_API_PORT` | Public HTTP API port | 9000 | No |
| `YP_SERVICE_PORT` | Internal service API port | 9001 | No |
| `YP_SMTPS_PORT` | Implicit TLS SMTP (SMTPS) | 465 | ✅ Yes |
| `YP_POP3S_PORT` | Implicit TLS POP3 (POP3S) | 995 | ✅ Yes |
| `YP_IMAPS_PORT` | Implicit TLS IMAP (IMAPS) | 993 | ✅ Yes |

### TLS/SSL Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `YP_SMTP_USE_TLS` | Enable STARTTLS on SMTP ports | `false` |
| `YP_SMTP_TLS_CERT` | Path to TLS certificate for SMTP | (disabled) |
| `YP_SMTP_TLS_KEY` | Path to TLS key for SMTP | (disabled) |
| `YP_POP3_USE_TLS` | Enable TLS on POP3 port | `false` |
| `YP_POP3_TLS_CERT` | Path to TLS certificate for POP3 | (disabled) |
| `YP_POP3_TLS_KEY` | Path to TLS key for POP3 | (disabled) |
| `YP_IMAP_USE_TLS` | Enable STARTTLS on IMAP port | `false` |
| `YP_IMAP_TLS_CERT` | Path to TLS certificate for IMAP | (disabled) |
| `YP_IMAP_TLS_KEY` | Path to TLS key for IMAP | (disabled) |

### SMTP Relay Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `YP_SMTP_RELAY_HOST` | Outgoing SMTP relay host | (disabled) |
| `YP_SMTP_RELAY_PORT` | Outgoing SMTP relay port | 587 |
| `YP_SMTP_RELAY_USER` | SMTP relay authentication username | (disabled) |
| `YP_SMTP_RELAY_PASSWORD` | SMTP relay authentication password | (disabled) |
| `YP_SMTP_RELAY_USE_TLS` | Use TLS for SMTP relay | `true` |

### Security Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `YP_SERVICE_TOKEN` | Bearer token for service API | (disabled) |
| `YP_MAX_CONNECTIONS` | Maximum concurrent connections | 1000 |
| `YP_CONNECTION_TIMEOUT_MS` | Connection idle timeout (ms) | 300000 |
| `YP_READ_TIMEOUT_MS` | Per-read timeout (ms) | 300000 |

## Port Configuration

### Understanding the Ports

YourPost uses multiple ports for different purposes:

#### SMTP Ports

- **Port 25 (YP_SMTP_PORT)**: Standard SMTP for receiving emails from other mail servers
  - Used for server-to-server communication
  - Required for receiving external email
  - Typically requires privileged access

- **Port 587 (YP_SUBMISSION_PORT)**: SMTP submission for mail clients
  - Used by email clients to send outgoing email
  - Supports authentication (when implemented)
  - Recommended for client submission

- **Port 465 (YP_SMTPS_PORT)**: Implicit TLS SMTP (SMTPS)
  - SMTP with TLS from the start
  - Legacy but still used
  - Requires TLS certificate

#### Retrieval Ports

- **Port 110 (YP_POP3_PORT)**: POP3 for email retrieval
  - Simple email download protocol
  - Emails typically deleted after download

- **Port 143 (YP_IMAP_PORT)**: IMAP for email access
  - Modern email access protocol
  - Keeps emails on server
  - Supports folders and synchronization

- **Port 993 (YP_IMAPS_PORT)**: Implicit TLS IMAP
  - IMAP with TLS from the start

- **Port 995 (YP_POP3S_PORT)**: Implicit TLS POP3
  - POP3 with TLS from the start

#### API Ports

- **Port 9000 (YP_API_PORT)**: Public HTTP API
  - RESTful API for user management
  - Health checks
  - Email sending via API

- **Port 9001 (YP_SERVICE_PORT)**: Internal service API
  - Used by Cloudflare Workers
  - Protected by service token
  - Should not be exposed publicly

### Privileged vs Non-Privileged Ports

Ports below 1024 are considered privileged and require root access:

```bash
# Requires root
export YP_SMTP_PORT=25
sudo ./yourpost

# No root required
export YP_SMTP_PORT=2525
./yourpost
```

### Using Non-Privileged Ports in Production

For production without running as root:

```bash
# Option 1: Use iptables redirect
sudo iptables -t nat -A PREROUTING -p tcp --dport 25 -j REDIRECT --to-port 2525
sudo iptables -t nat -A PREROUTING -p tcp --dport 587 -j REDIRECT --to-port 2587

# Option 2: Use setcap (recommended)
sudo setcap 'cap_net_bind_service=+ep' /usr/local/bin/yourpost

# Option 3: Use a reverse proxy
# nginx/Apache can forward ports
```

## TLS/SSL Configuration

### Generating Self-Signed Certificates

For testing:

```bash
# Generate private key
openssl genrsa -out yourpost.key 2048

# Generate certificate
openssl req -new -x509 -key yourpost.key -out yourpost.crt -days 365 \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=mail.example.com"

# Set permissions
chmod 600 yourpost.key
```

### Using Let's Encrypt

```bash
# Install certbot
sudo apt install certbot

# Obtain certificate
sudo certbot certonly --standalone -d mail.example.com

# Configure YourPost
export YP_SMTP_TLS_CERT=/etc/letsencrypt/live/mail.example.com/fullchain.pem
export YP_SMTP_TLS_KEY=/etc/letsencrypt/live/mail.example.com/privkey.pem
export YP_SMTP_USE_TLS=true
```

### Enabling TLS

```bash
# Enable STARTTLS on SMTP
export YP_SMTP_USE_TLS=true
export YP_SMTP_TLS_CERT=/path/to/cert.pem
export YP_SMTP_TLS_KEY=/path/to/key.pem

# Enable TLS on POP3
export YP_POP3_USE_TLS=true
export YP_POP3_TLS_CERT=/path/to/cert.pem
export YP_POP3_TLS_KEY=/path/to/key.pem

# Enable TLS on IMAP
export YP_IMAP_USE_TLS=true
export YP_IMAP_TLS_CERT=/path/to/cert.pem
export YP_IMAP_TLS_KEY=/path/to/key.pem
```

## SMTP Relay Configuration

SMTP relay allows YourPost to send outgoing emails through an external SMTP server.

### Why Use SMTP Relay?

- **Deliverability**: Major providers (Gmail, Outlook) trust known relays
- **Reputation**: Avoid building your own IP reputation
- **Rate Limits**: Leverage relay provider's sending limits
- **Features**: Use advanced features (DKIM, SPF, DMARC)

### Common SMTP Relays

#### SendGrid

```bash
export YP_SMTP_RELAY_HOST=smtp.sendgrid.net
export YP_SMTP_RELAY_PORT=587
export YP_SMTP_RELAY_USER=apikey
export YP_SMTP_RELAY_PASSWORD=SG.xxxxxxxxxxxxxxxxxxxxx
export YP_SMTP_RELAY_USE_TLS=true
```

#### Mailgun

```bash
export YP_SMTP_RELAY_HOST=smtp.mailgun.org
export YP_SMTP_RELAY_PORT=587
export YP_SMTP_RELAY_USER=postmaster@yourdomain.mailgun.org
export YP_SMTP_RELAY_PASSWORD=your-mailgun-password
export YP_SMTP_RELAY_USE_TLS=true
```

#### AWS SES

```bash
export YP_SMTP_RELAY_HOST=email-smtp.us-east-1.amazonaws.com
export YP_SMTP_RELAY_PORT=587
export YP_SMTP_RELAY_USER=YOUR_SES_SMTP_USERNAME
export YP_SMTP_RELAY_PASSWORD=YOUR_SES_SMTP_PASSWORD
export YP_SMTP_RELAY_USE_TLS=true
```

#### Gmail

```bash
export YP_SMTP_RELAY_HOST=smtp.gmail.com
export YP_SMTP_RELAY_PORT=465
export YP_SMTP_RELAY_USER=your-email@gmail.com
export YP_SMTP_RELAY_PASSWORD=your-app-password
export YP_SMTP_RELAY_USE_TLS=true
```

**Note**: Use an App Password, not your regular Gmail password.

#### Microsoft 365

```bash
export YP_SMTP_RELAY_HOST=smtp.office365.com
export YP_SMTP_RELAY_PORT=587
export YP_SMTP_RELAY_USER=user@yourdomain.com
export YP_SMTP_RELAY_PASSWORD=your-password
export YP_SMTP_RELAY_USE_TLS=true
```

### Disabling Direct Sending

When a relay is configured, all outgoing emails go through the relay:

```bash
# With relay - emails go through SendGrid
export YP_SMTP_RELAY_HOST=smtp.sendgrid.net
# YourPost → SendGrid → Recipient

# Without relay - YourPost sends directly
# YourPost → Recipient's MX
```

## Security Configuration

### Service API Token

The service API (port 9001) can be protected with a bearer token:

```bash
# Generate a secure token
openssl rand -hex 32
# Output: a1b2c3d4e5f6...

# Set the token
export YP_SERVICE_TOKEN=a1b2c3d4e5f6...
```

When set, all requests to `/api/service/*` require:

```http
Authorization: Bearer a1b2c3d4e5f6...
```

### Connection Limits

Prevent resource exhaustion:

```bash
# Maximum concurrent connections
export YP_MAX_CONNECTIONS=1000

# Connection idle timeout (5 minutes)
export YP_CONNECTION_TIMEOUT_MS=300000

# Per-read timeout (5 minutes)
export YP_READ_TIMEOUT_MS=300000
```

### Rate Limiting (Future)

Rate limiting is planned but not yet implemented. Consider using:
- Cloudflare rate limiting
- iptables connection limits
- fail2ban for brute force protection

## Multi-Domain Support

YourPost supports multiple domains automatically:

### How It Works

- Each user is identified by their full email address
- Domains are stored in `global.db`
- User mailboxes are separate SQLite databases

### Adding Domains

Domains are added automatically when users are created:

```bash
# Add a user in domain1.com
curl -X POST http://localhost:9000/api/v1/users \
  -d '{"email": "user@domain1.com", "password": "pass"}'

# Add a user in domain2.com
curl -X POST http://localhost:9000/api/v1/users \
  -d '{"email": "user@domain2.com", "password": "pass"}'

# Both domains work automatically
```

### Manual Domain Management

```bash
# Add domain manually
sqlite3 /var/lib/yourpost/data/global.db \
  "INSERT OR IGNORE INTO domains (domain) VALUES ('example.com');"

# List domains
sqlite3 /var/lib/yourpost/data/global.db \
  "SELECT * FROM domains;"
```

## Configuration Examples

### Development Setup

```bash
# .env.development
YP_HOSTNAME=localhost
YP_DATA_DIR=./data

# Non-privileged ports
YP_SMTP_PORT=2525
YP_SUBMISSION_PORT=2587
YP_POP3_PORT=2110
YP_IMAP_PORT=2143
YP_API_PORT=9000
YP_SERVICE_PORT=9001

# No authentication for development
# YP_SERVICE_TOKEN=

# No relay
# YP_SMTP_RELAY_HOST=
```

### Production Setup (Basic)

```bash
# .env.production
YP_HOSTNAME=mail.example.com
YP_DATA_DIR=/var/lib/yourpost

# Standard ports
YP_SMTP_PORT=25
YP_SUBMISSION_PORT=587
YP_POP3_PORT=110
YP_IMAP_PORT=143
YP_API_PORT=9000
YP_SERVICE_PORT=9001

# Security
YP_SERVICE_TOKEN=your-secure-token
YP_MAX_CONNECTIONS=1000

# TLS enabled
YP_SMTP_USE_TLS=true
YP_SMTP_TLS_CERT=/etc/letsencrypt/live/mail.example.com/fullchain.pem
YP_SMTP_TLS_KEY=/etc/letsencrypt/live/mail.example.com/privkey.pem
```

### Production Setup (With Relay)

```bash
# .env.production.relay
YP_HOSTNAME=mail.example.com
YP_DATA_DIR=/var/lib/yourpost

# Standard ports
YP_SMTP_PORT=25
YP_SUBMISSION_PORT=587
YP_POP3_PORT=110
YP_IMAP_PORT=143
YP_API_PORT=9000
YP_SERVICE_PORT=9001

# Security
YP_SERVICE_TOKEN=your-secure-token

# SMTP Relay (SendGrid)
YP_SMTP_RELAY_HOST=smtp.sendgrid.net
YP_SMTP_RELAY_PORT=587
YP_SMTP_RELAY_USER=apikey
YP_SMTP_RELAY_PASSWORD=SG.xxxxxxxxxxxxxxxxxxxxx
YP_SMTP_RELAY_USE_TLS=true

# TLS
YP_SMTP_USE_TLS=true
YP_SMTP_TLS_CERT=/etc/letsencrypt/live/mail.example.com/fullchain.pem
YP_SMTP_TLS_KEY=/etc/letsencrypt/live/mail.example.com/privkey.pem
```

### Cloudflare Worker Setup

```bash
# .env.cloudflare
YP_HOSTNAME=mail.example.com
YP_DATA_DIR=/var/lib/yourpost

# Standard ports
YP_SMTP_PORT=25
YP_SUBMISSION_PORT=587
YP_POP3_PORT=110
YP_IMAP_PORT=143
YP_API_PORT=9000
YP_SERVICE_PORT=9001

# Required for Cloudflare Worker
YP_SERVICE_TOKEN=your-generated-token

# Optional: SMTP relay for outgoing
YP_SMTP_RELAY_HOST=smtp.sendgrid.net
YP_SMTP_RELAY_PORT=587
YP_SMTP_RELAY_USER=apikey
YP_SMTP_RELAY_PASSWORD=SG.xxxxxxxxxxxxxxxxxxxxx
```

### Docker Compose Example

```yaml
version: '3.8'

services:
  yourpost:
    image: yourpost:latest
    container_name: yourpost
    environment:
      - YP_HOSTNAME=mail.example.com
      - YP_DATA_DIR=/var/lib/yourpost
      - YP_SMTP_PORT=25
      - YP_SUBMISSION_PORT=587
      - YP_POP3_PORT=110
      - YP_IMAP_PORT=143
      - YP_API_PORT=9000
      - YP_SERVICE_PORT=9001
      - YP_SERVICE_TOKEN=your-token
    ports:
      - "25:25"
      - "587:587"
      - "110:110"
      - "143:143"
      - "9000:9000"
      - "9001:9001"
    volumes:
      - yourpost-data:/var/lib/yourpost
    restart: unless-stopped

volumes:
  yourpost-data:
```

## Best Practices

1. **Always use TLS in production**
   - Enable STARTTLS on all ports
   - Use certificates from Let's Encrypt

2. **Use SMTP relay for outgoing mail**
   - Better deliverability
   - Avoid IP reputation issues

3. **Protect your service API**
   - Always set YP_SERVICE_TOKEN
   - Don't expose port 9001 publicly

4. **Monitor and backup**
   - Regular backups of `/var/lib/yourpost`
   - Monitor logs
   - Set up alerts

5. **Keep updated**
   - Watch for YourPost updates
   - Update dependencies regularly

## Troubleshooting Configuration

### Configuration Not Taking Effect

```bash
# Environment variables must be set before starting
export YP_HOSTNAME=mail.example.com
./yourpost

# Not like this:
./yourpost
export YP_HOSTNAME=mail.example.com  # Too late!
```

### Check Active Configuration

```bash
# Check environment
env | grep YP_

# Check running process
ps aux | grep yourpost

# Check systemd environment
sudo systemctl show yourpost --property=Environment
```

### Port Conflicts

```bash
# Check all YourPost ports
for port in 25 587 110 143 9000 9001; do
  echo "Port $port:"
  sudo lsof -i :$port 2>/dev/null || echo "  Free"
done
```

## Next Steps

- [SMTP Relay Setup](SMTP_RELAY.md) - Detailed relay configuration
- [API Documentation](API.md) - Complete API reference
- [Cloudflare Integration](CLOUDFLARE.md) - Email routing setup
- [Security Guide](SECURITY.md) - TLS and hardening