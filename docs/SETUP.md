# YourPost Setup Guide

This guide covers the complete setup process for YourPost, a lightweight mail server written in Zig.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Building from Source](#building-from-source)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Running as a Service](#running-as-a-service)
- [Docker Deployment](#docker-deployment)
- [User Management](#user-management)
- [Testing Your Installation](#testing-your-installation)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### System Requirements

- **Operating System**: Linux (recommended) or any POSIX-compliant system
- **Architecture**: x86_64 (other architectures may work)
- **RAM**: Minimum 256MB (512MB recommended)
- **Disk Space**: Minimum 500MB (depends on email volume)
- **Ports**: See [Port Configuration](#port-configuration)

### Required Software

- **Zig 0.16.0** (for building from source)
- **SQLite3** (runtime dependency)
- **OpenSSL** (for TLS support, optional)
- **Root/sudo access** (if using privileged ports < 1024)

### Optional Software

- **systemd** (for service management)
- **Docker** (for containerized deployment)
- **Cloudflare Account** (for email routing via workers)

## Building from Source

### Step 1: Install Zig

```bash
# Download Zig
wget -q https://ziglang.org/download/0.16.0/zig-linux-x86_64-0.16.0.tar.xz

# Extract
tar -xf zig-linux-x86_64-0.16.0.tar.xz

# Move to /usr/local (optional)
sudo mv zig-linux-x86_64-0.16.0 /usr/local/zig
sudo ln -s /usr/local/zig/zig /usr/local/bin/zig

# Verify installation
zig version
```

### Step 2: Clone and Build

```bash
# Navigate to project directory
cd /root/yourpost-workspace/yourpost

# Build the project
zig build -Doptimize=ReleaseFast

# Verify binary exists
ls -la zig-out/bin/yourpost
```

### Step 3: Install (Optional)

Use the provided installation script:

```bash
# Default installation to /usr/local
sudo ./install.sh

# Or specify a custom prefix
sudo ./install.sh /opt/yourpost
```

## Quick Start

### Development Mode (Non-Privileged Ports)

For testing and development, use non-privileged ports:

```bash
# Set environment variables
export YP_SMTP_PORT=2525
export YP_SUBMISSION_PORT=2587
export YP_POP3_PORT=2110
export YP_IMAP_PORT=2143
export YP_API_PORT=9000
export YP_SERVICE_PORT=9001

# Run the server
./zig-out/bin/yourpost
```

### Production Mode (Standard Ports)

For production use with standard ports:

```bash
# Run with sudo for privileged ports
sudo ./zig-out/bin/yourpost
```

Or configure via environment variables:

```bash
export YP_HOSTNAME=mail.yourdomain.com
export YP_SMTP_PORT=25
export YP_SUBMISSION_PORT=587
export YP_POP3_PORT=110
export YP_IMAP_PORT=143
export YP_API_PORT=9000
export YP_SERVICE_PORT=9001

./zig-out/bin/yourpost
```

## Configuration

### Environment Variables

YourPost uses environment variables for all configuration. See [CONFIGURATION.md](CONFIGURATION.md) for complete details.

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

### Configuration File

While YourPost uses environment variables, you can create a configuration file:

```bash
# Create config file
sudo mkdir -p /etc/yourpost
sudo nano /etc/yourpost/yourpost.env
```

Add your configuration:

```bash
# /etc/yourpost/yourpost.env
YP_HOSTNAME=mail.example.com
YP_SMTP_PORT=25
YP_SUBMISSION_PORT=587
YP_SERVICE_TOKEN=your-token
```

Then source it before running:

```bash
source /etc/yourpost/yourpost.env
./zig-out/bin/yourpost
```

## Running as a Service

### Using systemd (Recommended)

The installation script automatically sets up systemd:

```bash
# Enable and start the service
sudo systemctl enable yourpost
sudo systemctl start yourpost

# Check status
sudo systemctl status yourpost

# View logs
sudo journalctl -u yourpost -f
```

### Manual Service Setup

If not using the install script:

```bash
# Copy service file
sudo cp yourpost.service /etc/systemd/system/yourpost.service

# Edit configuration
sudo nano /etc/systemd/system/yourpost.service

# Reload systemd
sudo systemctl daemon-reload

# Enable and start
sudo systemctl enable yourpost
sudo systemctl start yourpost
```

### Docker Deployment

See [DOCKER.md](DOCKER.md) for detailed Docker instructions.

```bash
# Quick start with Docker
sudo docker run -d \
  --name yourpost \
  -p 25:25 \
  -p 587:587 \
  -p 9000:9000 \
  -v /var/lib/yourpost:/var/lib/yourpost \
  -e YP_HOSTNAME=mail.example.com \
  yourpost:latest
```

## User Management

### Creating Users

Users can be created via the API or directly in SQLite:

#### Via API

```bash
curl -X POST http://localhost:9000/api/v1/users \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "securepassword"}'
```

#### Via SQLite

```bash
# Add domain
sqlite3 /var/lib/yourpost/data/global.db \
  "INSERT OR IGNORE INTO domains (domain) VALUES ('example.com');"

# Create user (password will be hashed by the API)
# Use the API method above instead
```

### Managing Users

```bash
# List all users
curl http://localhost:9000/api/v1/users

# Delete a user
curl -X DELETE http://localhost:9000/api/v1/users/user@example.com
```

## Testing Your Installation

### Health Check

```bash
curl http://localhost:9000/health
# Expected: {"status":"ok","service":"yourpost"}
```

### Test SMTP Connection

```bash
# Using telnet
telnet localhost 2525

# Expected response:
# 220 mail.example.com ESMTP YourPost

# Test submission port
telnet localhost 2587
```

### Test POP3 Connection

```bash
telnet localhost 2110
# Expected: +OK YourPost POP3 Server Ready
```

### Test IMAP Connection

```bash
telnet localhost 2143
# Expected: * OK YourPost IMAP Server Ready
```

### Test API Authentication

```bash
# Login
curl -X POST http://localhost:9000/api/v1/auth \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "password"}'
```

### Send Test Email

```bash
# Create a test email
cat > test.eml << 'EOF'
From: sender@example.com
To: user@example.com
Subject: Test Email
Date: Mon, 4 May 2026 12:00:00 +0000
Message-ID: <test@example.com>

This is a test email.
EOF

# Send via HTTP API
curl -X POST http://localhost:9000/api/v1/mailboxes/user@example.com/send \
  -H "Content-Type: application/json" \
  -d '{
    "to": "recipient@example.com",
    "subject": "Test Email",
    "body": "This is a test email body"
  }'
```

## Troubleshooting

### Port Already in Use

```bash
# Check which process is using the port
sudo lsof -i :25

# Or use netstat
sudo netstat -tulpn | grep :25

# Solution: Stop the conflicting service or use different ports
export YP_SMTP_PORT=2525
```

### Permission Denied (Privileged Ports)

```bash
# Error: Cannot bind to privileged port

# Solution 1: Use non-privileged ports
export YP_SMTP_PORT=2525
export YP_SUBMISSION_PORT=2587

# Solution 2: Run with sudo
sudo ./zig-out/bin/yourpost

# Solution 3: Use setcap (recommended for production)
sudo setcap 'cap_net_bind_service=+ep' /usr/local/bin/yourpost
```

### Data Directory Not Writable

```bash
# Ensure proper permissions
sudo chown -R yourpost:yourpost /var/lib/yourpost
sudo chmod -R 750 /var/lib/yourpost
```

### Service Won't Start

```bash
# Check logs
sudo journalctl -u yourpost -n 50 --no-pager

# Check configuration
sudo systemctl cat yourpost

# Test manually
sudo -u yourpost /usr/local/bin/yourpost
```

### Email Delivery Issues

```bash
# Check if SMTP relay is configured
env | grep YP_SMTP_RELAY

# Test SMTP relay connection
openssl s_client -connect smtp.gmail.com:587 -starttls smtp

# Check Cloudflare Worker logs (if using)
npx wrangler tail your-worker
```

### High Memory Usage

```bash
# Reduce connection limit
export YP_MAX_CONNECTIONS=500

# Reduce timeouts
export YP_CONNECTION_TIMEOUT_MS=60000
export YP_READ_TIMEOUT_MS=60000
```

## Next Steps

- [Configuration Guide](CONFIGURATION.md) - Detailed configuration options
- [SMTP Relay Setup](SMTP_RELAY.md) - Configure outgoing email relay
- [API Documentation](API.md) - Complete API reference
- [Cloudflare Integration](CLOUDFLARE.md) - Email routing via Cloudflare
- [Security Guide](SECURITY.md) - TLS, authentication, and hardening
