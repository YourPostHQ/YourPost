# YourPost Quick Start Guide

This guide gets you up and running with YourPost in 5 minutes.

## Prerequisites

- Linux server (or VM)
- Root/sudo access (for privileged ports)
- Domain name (optional, for production)

## Step 1: Build YourPost

```bash
cd /root/yourpost-workspace/yourpost
zig build -Doptimize=ReleaseFast
```

✅ Done when you see: `zig-out/bin/yourpost` exists

## Step 2: Configure Basic Settings

For **development/testing** (non-privileged ports):

```bash
export YP_HOSTNAME=localhost
export YP_SMTP_PORT=2525
export YP_SUBMISSION_PORT=2587
export YP_POP3_PORT=2110
export YP_IMAP_PORT=2143
export YP_API_PORT=9000
export YP_SERVICE_PORT=9001
```

For **production** (standard ports, requires root):

```bash
export YP_HOSTNAME=mail.yourdomain.com
export YP_SMTP_PORT=25
export YP_SUBMISSION_PORT=587
export YP_POP3_PORT=110
export YP_IMAP_PORT=143
export YP_API_PORT=9000
export YP_SERVICE_PORT=9001
```

## Step 3: Start the Server

```bash
./zig-out/bin/yourpost
```

You should see:
```
info: SMTP listening on :2525
info: HTTP API listening on :9000
info: HTTP Service API listening on :9001
```

## Step 4: Create Your First User

```bash
# Add domain
sqlite3 data/global.db "INSERT OR IGNORE INTO domains (domain) VALUES ('example.com');"

# Create user via API
curl -X POST http://localhost:9000/api/v1/users \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@example.com",
    "password": "SecurePass123!"
  }'
```

✅ Response: `{"status":"success","message":"User created successfully"}`

## Step 5: Test Everything

### Test Health Check

```bash
curl http://localhost:9000/health
```

✅ Expected: `{"status":"ok","service":"yourpost"}`

### Test Login

```bash
curl -X POST http://localhost:9000/api/v1/auth \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@example.com",
    "password": "SecurePass123!"
  }'
```

✅ Expected: `{"status":"success","message":"Login successful"}`

### Test Send Email

```bash
curl -X POST http://localhost:9000/api/v1/mailboxes/admin@example.com/send \
  -H "Content-Type: application/json" \
  -d '{
    "to": ["admin@example.com"],
    "subject": "Welcome to YourPost!",
    "body": "Your mail server is working!"
  }'
```

✅ Expected: `{"status":"success","message":"Email sent successfully"}`

### Test Retrieve Emails

```bash
curl http://localhost:9000/api/v1/mailboxes/admin@example.com/messages?folder=INBOX
```

✅ Expected: List of messages including the one you just sent

## Step 6: Connect Email Client (Optional)

Configure your email client:

**Server**: `localhost` (or your server IP)
**Username**: `admin@example.com`
**Password**: `SecurePass123!`

**Ports**:
- IMAP: 2143 (or 143 in production)
- POP3: 2110 (or 110 in production)
- SMTP: 2587 (or 587 in production)

## 🎉 You're Done!

YourPost is now running and ready to use!

## Next Steps

### Add More Users

```bash
curl -X POST http://localhost:9000/api/v1/users \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user2@example.com",
    "password": "AnotherSecurePass!"
  }'
```

### Enable TLS (Production)

```bash
# Get certificate (Let's Encrypt)
sudo certbot certonly --standalone -d mail.yourdomain.com

# Configure YourPost
export YP_SMTP_USE_TLS=true
export YP_SMTP_TLS_CERT=/etc/letsencrypt/live/mail.yourdomain.com/fullchain.pem
export YP_SMTP_TLS_KEY=/etc/letsencrypt/live/mail.yourdomain.com/privkey.pem
```

### Set Up SMTP Relay (For Better Deliverability)

```bash
# Using SendGrid
export YP_SMTP_RELAY_HOST=smtp.sendgrid.net
export YP_SMTP_RELAY_PORT=587
export YP_SMTP_RELAY_USER=apikey
export YP_SMTP_RELAY_PASSWORD=SG.your-api-key
```

### Add Cloudflare Email Routing

```bash
# Generate API token
export YP_SERVICE_TOKEN=$(openssl rand -hex 32)

# Deploy Cloudflare Worker
cd cloudflare-worker
npx wrangler secret put YOURPOST_SERVICE_TOKEN
npx wrangler deploy
```

### Run as a Service

```bash
# Install systemd service
sudo ./install.sh

# Enable and start
sudo systemctl enable yourpost
sudo systemctl start yourpost

# Check status
sudo systemctl status yourpost
```

## 🚨 Troubleshooting

### Port Already in Use

```bash
# Check what's using the port
sudo lsof -i :25

# Solution: Use different ports
export YP_SMTP_PORT=2525
```

### Permission Denied

```bash
# For privileged ports (< 1024)
# Either use sudo or non-privileged ports
export YP_SMTP_PORT=2525  # Instead of 25
```

### Can't Connect

```bash
# Check if server is running
ps aux | grep yourpost

# Check logs
sudo journalctl -u yourpost -f
```

### User Can't Login

```bash
# Verify user exists
curl http://localhost:9000/api/v1/users

# Check password
# Reset by creating new user with same email
```

## 📚 Learn More

- **[Configuration Guide](CONFIGURATION.md)** - All configuration options
- **[API Documentation](API.md)** - Complete API reference
- **[SMTP Relay](SMTP_RELAY.md)** - Configure outgoing email
- **[Cloudflare Integration](CLOUDFLARE.md)** - Email routing
- **[Security Guide](SECURITY.md)** - TLS and hardening
- **[Docker Deployment](DOCKER.md)** - Container deployment

## 💡 Quick Commands Reference

```bash
# Start server
./zig-out/bin/yourpost

# Health check
curl http://localhost:9000/health

# List users
curl http://localhost:9000/api/v1/users

# Create user
curl -X POST http://localhost:9000/api/v1/users \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"pass"}'

# Send email
curl -X POST http://localhost:9000/api/v1/mailboxes/user@example.com/send \
  -H "Content-Type: application/json" \
  -d '{"to":["to@example.com"],"subject":"Hi","body":"Hello"}'

# View logs
sudo journalctl -u yourpost -f

# Stop service
sudo systemctl stop yourpost
```

## 🎓 Tips

1. **Always use TLS in production** - Enable STARTTLS
2. **Use SMTP relay** - Better deliverability (SendGrid, Mailgun)
3. **Set service token** - Protect your service API
4. **Monitor logs** - Check for issues regularly
5. **Backup regularly** - `/var/lib/yourpost/data/`
6. **Keep updated** - Watch for new releases

## 🆘 Need Help?

- Check [Troubleshooting](SETUP.md#troubleshooting) section
- Review [Configuration](CONFIGURATION.md) options
- Check logs: `journalctl -u yourpost -f`
- Test endpoints: `curl http://localhost:9000/health`