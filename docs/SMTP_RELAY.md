# SMTP Relay Configuration Guide

This guide explains how to configure YourPost to send outgoing emails through an SMTP relay service.

## Table of Contents

- [Why Use SMTP Relay?](#why-use-smtp-relay)
- [How It Works](#how-it-works)
- [Configuration](#configuration)
- [Popular SMTP Relay Services](#popular-smtp-relay-services)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## Why Use SMTP Relay?

### 1. **Email Deliverability**
Direct email sending from your server faces challenges:
- IP reputation requirements
- SPF, DKIM, DMARC configuration
- Blacklist monitoring
- Reverse DNS setup

SMTP relays handle these for you.

### 2. **Rate Limiting**
- Gmail/Yahoo: ~100-500 emails/day from new IPs
- SMTP relays: Thousands per day
- No warm-up period needed

### 3. **Reputation Management**
- Shared IP pools with good reputation
- Automatic complaint handling
- Bounce processing

### 4. **Features**
- Built-in analytics
- Template support
- Automatic DKIM signing
- Link tracking

## How It Works

```
Without Relay:
YourPost → Recipient's MX Server → Inbox
    ↓
  Direct delivery
  (Your IP reputation matters)

With Relay:
YourPost → SMTP Relay → Recipient's MX → Inbox
    ↓              ↓
  Local delivery  Relay handles
                  reputation, DKIM, etc.
```

## Configuration

### Basic Setup

Set these environment variables:

```bash
# SMTP Relay Configuration
export YP_SMTP_RELAY_HOST=smtp.sendgrid.net
export YP_SMTP_RELAY_PORT=587
export YP_SMTP_RELAY_USER=apikey
export YP_SMTP_RELAY_PASSWORD=SG.xxxxxxxxxxxxxxxxxxxxx
export YP_SMTP_RELAY_USE_TLS=true
```

### How YourPost Uses Relay

When configured, YourPost will:

1. **Accept incoming email** normally (SMTP port 25, submission port 587)
2. **Store email** in user mailboxes
3. **Send outgoing email** through the relay instead of directly

### Authentication Methods

#### API Key (SendGrid, Mailgun)

```bash
export YP_SMTP_RELAY_USER=apikey
export YP_SMTP_RELAY_PASSWORD=SG.xxxxxxxxxxxxxxxxxxxxx
```

#### Username/Password (Gmail, Microsoft 365)

```bash
export YP_SMTP_RELAY_USER=user@example.com
export YP_SMTP_RELAY_PASSWORD=your-password
```

#### No Authentication (Local Relay)

```bash
export YP_SMTP_RELAY_HOST=localhost
export YP_SMTP_RELAY_PORT=25
# Leave USER and PASSWORD empty
```

### TLS Configuration

```bash
# Use TLS (recommended)
export YP_SMTP_RELAY_USE_TLS=true

# Disable TLS (not recommended)
export YP_SMTP_RELAY_USE_TLS=false
```

## Popular SMTP Relay Services

### SendGrid

**Best for**: General purpose, high volume

**Free Tier**: 100 emails/day

**Setup**:

1. Sign up at [sendgrid.com](https://sendgrid.com)
2. Create API Key
3. Configure:

```bash
export YP_SMTP_RELAY_HOST=smtp.sendgrid.net
export YP_SMTP_RELAY_PORT=587
export YP_SMTP_RELAY_USER=apikey
export YP_SMTP_RELAY_PASSWORD=SG.your-api-key-here
export YP_SMTP_RELAY_USE_TLS=true
```

**Pros**:
- Excellent deliverability
- Good free tier
- Easy setup

**Cons**:
- Can be expensive at scale

---

### Mailgun

**Best for**: Developers, transactional email

**Free Tier**: 5,000 emails/month

**Setup**:

1. Sign up at [mailgun.com](https://mailgun.com)
2. Get SMTP credentials
3. Configure:

```bash
export YP_SMTP_RELAY_HOST=smtp.mailgun.org
export YP_SMTP_RELAY_PORT=587
export YP_SMTP_RELAY_USER=postmaster@yourdomain.mailgun.org
export YP_SMTP_RELAY_PASSWORD=your-mailgun-password
export YP_SMTP_RELAY_USE_TLS=true
```

**Pros**:
- Good free tier
- Excellent API
- Detailed logs

**Cons**:
- Requires domain verification

---

### AWS SES (Simple Email Service)

**Best for**: AWS users, high volume

**Free Tier**: 62,000 emails/month (EC2 users)

**Setup**:

1. Open AWS SES console
2. Verify domain
3. Get SMTP credentials
4. Configure:

```bash
export YP_SMTP_RELAY_HOST=email-smtp.us-east-1.amazonaws.com
export YP_SMTP_RELAY_PORT=587
export YP_SMTP_RELAY_USER=YOUR_SES_SMTP_USERNAME
export YP_SMTP_RELAY_PASSWORD=YOUR_SES_SMTP_PASSWORD
export YP_SMTP_RELAY_USE_TLS=true
```

**Pros**:
- Very cheap at scale
- High reputation
- AWS integration

**Cons**:
- Complex setup
- Requires domain verification
- Sandbox mode initially

---

### Gmail / Google Workspace

**Best for**: Personal use, small businesses

**Free Tier**: 500 emails/day

**Setup**:

1. Enable 2FA on Google account
2. Create App Password
3. Configure:

```bash
export YP_SMTP_RELAY_HOST=smtp.gmail.com
export YP_SMTP_RELAY_PORT=465
export YP_SMTP_RELAY_USER=your-email@gmail.com
export YP_SMTP_RELAY_PASSWORD=your-app-password
export YP_SMTP_RELAY_USE_TLS=true
```

**Important**: Use App Password, not regular password!

**Pros**:
- Free
- Reliable
- No setup beyond Google account

**Cons**:
- Low daily limit
- Can be flagged as suspicious

---

### Microsoft 365

**Best for**: Microsoft ecosystem users

**Setup**:

```bash
export YP_SMTP_RELAY_HOST=smtp.office365.com
export YP_SMTP_RELAY_PORT=587
export YP_SMTP_RELAY_USER=user@yourdomain.com
export YP_SMTP_RELAY_PASSWORD=your-password
export YP_SMTP_RELAY_USE_TLS=true
```

**Pros**:
- Integrated with Microsoft
- Good reputation

**Cons**:
- Requires Microsoft 365 subscription

---

### Mailjet

**Best for**: European businesses

**Free Tier**: 6,000 emails/month

**Setup**:

```bash
export YP_SMTP_RELAY_HOST=in-v3.mailjet.com
export YP_SMTP_RELAY_PORT=587
export YP_SMTP_RELAY_USER=your-mailjet-api-key
export YP_SMTP_RELAY_PASSWORD=your-mailjet-secret-key
export YP_SMTP_RELAY_USE_TLS=true
```

---

### Postmark

**Best for**: Transactional email

**Free Tier**: 100 emails/month

**Setup**:

```bash
export YP_SMTP_RELAY_HOST=smtp.postmarkapp.com
export YP_SMTP_RELAY_PORT=587
export YP_SMTP_RELAY_USER=your-server-api-token
export YP_SMTP_RELAY_PASSWORD=your-server-api-token
export YP_SMTP_RELAY_USE_TLS=true
```

---

### SparkPost

**Best for**: Enterprise

**Free Tier**: 100 emails/day

**Setup**:

```bash
export YP_SMTP_RELAY_HOST=smtp.sparkpostmail.com
export YP_SMTP_RELAY_PORT=587
export YP_SMTP_RELAY_USER=SMTP_Injection
export YP_SMTP_RELAY_PASSWORD=your-api-key
export YP_SMTP_RELAY_USE_TLS=true
```

---

### Brevo (formerly Sendinblue)

**Best for**: Marketing + transactional

**Free Tier**: 300 emails/day

**Setup**:

```bash
export YP_SMTP_RELAY_HOST=smtp-relay.sendinblue.com
export YP_SMTP_RELAY_PORT=587
export YP_SMTP_RELAY_USER=your-brevo-username
export YP_SMTP_RELAY_PASSWORD=your-brevo-password
export YP_SMTP_RELAY_USE_TLS=true
```

---

### Zoho Mail

**Best for**: Small businesses

**Free Tier**: 5 users, 50,000 emails/month

**Setup**:

```bash
export YP_SMTP_RELAY_HOST=smtp.zoho.com
export YP_SMTP_RELAY_PORT=587
export YP_SMTP_RELAY_USER=user@yourdomain.com
export YP_SMTP_RELAY_PASSWORD=your-password
export YP_SMTP_RELAY_USE_TLS=true
```

---

### Pepipost

**Best for**: High volume

**Free Tier**: 100 emails/day

**Setup**:

```bash
export YP_SMTP_RELAY_HOST=smtp.pepipost.com
export YP_SMTP_RELAY_PORT=587
export YP_SMTP_RELAY_USER=your-username
export YP_SMTP_RELAY_PASSWORD=your-password
export YP_SMTP_RELAY_USE_TLS=true
```

---

### Elastic Email

**Best for**: Marketing campaigns

**Free Tier**: 100 emails/day

**Setup**:

```bash
export YP_SMTP_RELAY_HOST=smtp.elasticemail.com
export YP_SMTP_RELAY_PORT=2525
export YP_SMTP_RELAY_USER=your-username
export YP_SMTP_RELAY_PASSWORD=your-password
export YP_SMTP_RELAY_USE_TLS=true
```

---

### Comparison Table

| Service | Free Tier | Best For | Setup Difficulty |
|---------|-----------|----------|------------------|
| SendGrid | 100/day | General purpose | Easy |
| Mailgun | 5,000/mo | Developers | Easy |
| AWS SES | 62,000/mo | High volume | Hard |
| Gmail | 500/day | Personal | Very Easy |
| Mailjet | 6,000/mo | European | Easy |
| Postmark | 100/mo | Transactional | Easy |
| Brevo | 300/day | Marketing | Easy |
| Zoho | 50k/mo | Small business | Easy |

## Troubleshooting

### Authentication Failed

```bash
# Error: 535 Authentication failed

# Solutions:
# 1. Check credentials
env | grep YP_SMTP_RELAY

# 2. For Gmail, use App Password
# Not your regular password!

# 3. Check username format
# Some services need full email
# Others need API key as username

# 4. Test connection
openssl s_client -connect smtp.sendgrid.net:587 -starttls smtp
```

### Connection Timeout

```bash
# Error: Connection timed out

# Solutions:
# 1. Check firewall
sudo ufw status

# 2. Test connectivity
nc -zv smtp.sendgrid.net 587

# 3. Check DNS
nslookup smtp.sendgrid.net

# 4. Try different port
# 587 (submission) or 465 (SMTPS)
```

### TLS/SSL Errors

```bash
# Error: certificate verify failed

# Solutions:
# 1. Update CA certificates
sudo apt update && sudo apt install ca-certificates

# 2. Check certificate
openssl s_client -connect smtp.sendgrid.net:587 -starttls smtp

# 3. Temporarily disable TLS (not recommended)
export YP_SMTP_RELAY_USE_TLS=false
```

### Relay Refused

```bash
# Error: 550 Relay not permitted

# Solutions:
# 1. Authenticate first
# Check YP_SMTP_RELAY_USER and PASSWORD

# 2. Verify sender domain
# Some relays require verified domains

# 3. Check relay limits
# Free tiers often have daily limits
```

### Emails Going to Spam

```bash
# Solutions:
# 1. Configure DKIM (via relay provider)
# 2. Set up SPF record
# 3. Configure DMARC
# 4. Warm up IP (if using dedicated IP)
# 5. Check sender reputation
```

### Rate Limiting

```bash
# Error: 421 Too many connections
# Error: 451 Temporary local problem

# Solutions:
# 1. Reduce sending rate
export YP_MAX_CONNECTIONS=100

# 2. Implement queuing
# Add delays between sends

# 3. Upgrade relay plan
# Higher tiers = higher limits
```

## Testing SMTP Relay

### Test Connection

```bash
# Test with openssl
openssl s_client -connect smtp.sendgrid.net:587 -starttls smtp

# Expected:
# 220 smtp.sendgrid.net ESMTP ready
```

### Test Authentication

```bash
# Manual SMTP test
telnet smtp.sendgrid.net 587

# Then type:
EHLO example.com
STARTTLS
# (After TLS negotiation)
EHLO example.com
AUTH LOGIN
# (Base64 encoded username)
# (Base64 encoded password)
```

### Test Through YourPost

```bash
# Send test email
curl -X POST http://localhost:9000/api/v1/mailboxes/test@example.com/send \
  -H "Content-Type: application/json" \
  -d '{
    "to": "your-email@gmail.com",
    "subject": "Test Relay",
    "body": "If you receive this, relay works!"
  }'

# Check logs
sudo journalctl -u yourpost -f
```

## Best Practices

### 1. **Always Use TLS**

```bash
export YP_SMTP_RELAY_USE_TLS=true
```

### 2. **Secure Credentials**

```bash
# Don't hardcode in scripts
# Use environment files with restricted permissions
chmod 600 /etc/yourpost/yourpost.env

# Or use secrets management
# systemd: LoadCredential=
# Docker: docker secrets
# Kubernetes: secrets
```

### 3. **Monitor Usage**

```bash
# Check relay provider dashboard
# Monitor YourPost logs
sudo journalctl -u yourpost | grep -i relay

# Set up alerts for:
# - Authentication failures
# - Rate limiting
# - Connection errors
```

### 4. **Implement Retry Logic**

YourPost handles retries automatically, but:
- Monitor for persistent failures
- Set up alerts
- Have backup relay ready

### 5. **Warm Up New IPs**

If not using relay:
- Start with low volume
- Gradually increase
- Maintain consistent volume

### 6. **Keep Records**

```bash
# Document your relay configuration
# Keep API keys secure
# Rotate credentials regularly
# Monitor billing
```

### 7. **Have Backup**

```bash
# Consider multiple relays
# Or fallback to direct sending
# Test failover regularly
```

## Advanced Configuration

### Multiple Relays (Failover)

YourPost supports single relay. For failover:

```bash
# Option 1: Use relay provider with multiple SMTP endpoints
# Option 2: Implement at network level (load balancer)
# Option 3: Monitor and switch manually
```

### Custom Ports

```bash
# Non-standard ports
export YP_SMTP_RELAY_PORT=2525
export YP_SMTP_RELAY_PORT=25025
```

### No Authentication

```bash
# For local relays
export YP_SMTP_RELAY_HOST=localhost
export YP_SMTP_RELAY_PORT=25
# Leave USER and PASSWORD empty
```

### Internal Relays

```bash
# Company internal relay
export YP_SMTP_RELAY_HOST=mail.internal.company.com
export YP_SMTP_RELAY_PORT=25
export YP_SMTP_RELAY_USE_TLS=false
```

## Integration Examples

### With Cloudflare Worker

```bash
# YourPost receives via Cloudflare
# Sends via SMTP relay
# Full email flow:
# Internet → Cloudflare → YourPost → SMTP Relay → Internet
```

### With Docker

```yaml
# docker-compose.yml
services:
  yourpost:
    environment:
      - YP_SMTP_RELAY_HOST=smtp.sendgrid.net
      - YP_SMTP_RELAY_PORT=587
      - YP_SMTP_RELAY_USER=apikey
      - YP_SMTP_RELAY_PASSWORD=${SENDGRID_API_KEY}
```

### With Kubernetes

```yaml
# kubernetes/deployment.yaml
env:
  - name: YP_SMTP_RELAY_HOST
    value: "smtp.sendgrid.net"
  - name: YP_SMTP_RELAY_PASSWORD
    valueFrom:
      secretKeyRef:
        name: yourpost-secrets
        key: smtp-password
```

## Next Steps

- [Configuration Guide](CONFIGURATION.md) - All configuration options
- [Cloudflare Integration](CLOUDFLARE.md) - Email routing setup
- [API Documentation](API.md) - Complete API reference
- [Security Guide](SECURITY.md) - TLS and authentication