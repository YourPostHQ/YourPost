# Cloudflare Integration Guide

This guide explains how to integrate YourPost with Cloudflare Email Workers for email routing and delivery.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Setup Steps](#setup-steps)
- [Worker Configuration](#worker-configuration)
- [Email Routing](#email-routing)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [Advanced Configuration](#advanced-configuration)

## Overview

Cloudflare Email Workers can route incoming emails to YourPost, providing:
- **Custom routing rules** - Route emails based on content, headers, or recipients
- **Spam filtering** - Integrate with third-party services
- **Email transformation** - Modify emails before delivery
- **Reliability** - Cloudflare's global network
- **No server management** - Fully managed service

## Architecture

```
Sender → Cloudflare Email Routing → Email Worker → YourPost (port 9001)
                                              ↓
                                         SQLite Database
                                              ↓
                                    POP3/IMAP/SMTP Access
```

### Data Flow

1. **Email Received**: External sender sends email to `user@yourdomain.com`
2. **Cloudflare Routing**: Cloudflare Email Routing receives the email
3. **Worker Processing**: Email Worker processes and forwards to YourPost
4. **Delivery**: YourPost stores email in user's mailbox database
5. **Access**: User retrieves email via POP3/IMAP or web interface

## Prerequisites

### Required

- [ ] Cloudflare account with Email Routing enabled
- [ ] Domain managed by Cloudflare
- [ ] YourPost server running and accessible
- [ ] YourPost Service API configured (port 9001)
- [ ] Service token generated (if using authentication)

### Domain Requirements

- Domain must use Cloudflare nameservers
- MX records must point to Cloudflare
- Email Routing must be enabled for the domain

## Setup Steps

### Step 1: Configure YourPost Service API

#### 1.1 Set Service Port and Token

```bash
# In your environment or systemd service file
export YP_SERVICE_PORT=9001
export YP_SERVICE_TOKEN=your-secure-token-here
```

Generate a secure token:

```bash
openssl rand -hex 32
# Example: a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456
```

#### 1.2 Configure systemd Service (if using)

Edit `/etc/systemd/system/yourpost.service`:

```ini
[Service]
Environment=YP_SERVICE_PORT=9001
Environment=YP_SERVICE_TOKEN=your-secure-token-here
```

Reload and restart:

```bash
sudo systemctl daemon-reload
sudo systemctl restart yourpost
```

#### 1.3 Verify Service API is Running

```bash
# Check if port is listening
ss -tlnp | grep 9001

# Test health endpoint
curl http://localhost:9001/health

# Expected response:
# {"status":"ok","service":"yourpost"}
```

### Step 2: Create Cloudflare Worker

#### 2.1 Install Wrangler

```bash
npm install -g wrangler
# or
npm install -g wrangler@latest
```

#### 2.2 Create Worker Project

```bash
mkdir yourpost-worker
cd yourpost-worker
wrangler init yourpost-email-worker
```

#### 2.3 Configure Worker

Edit `wrangler.toml`:

```toml
name = "yourpost-email-worker"
main = "src/index.js"
compatibility_date = "2024-01-01"

[env.production]
name = "yourpost-email-worker-production"
```

#### 2.4 Copy Worker Code

Use the provided worker from `cloudflare-worker/email-worker.js`:

```bash
cp /root/yourpost-workspace/yourpost/cloudflare-worker/email-worker.js src/index.js
```

Or create a new file `src/index.js`:

```javascript
/**
 * Cloudflare Email Worker for YourPost
 * Forwards emails to YourPost Service API
 */

export default {
  async fetch(request, env) {
    return new Response('YourPost Email Worker is running', { status: 200 });
  },
  
  async email(message, env) {
    console.log(`Received email: ${message.from} → ${message.to}`);

    try {
      // Get configuration from secrets
      const serviceUrl = env.YOURPOST_SERVICE_URL || 'http://localhost:9001';
      const serviceToken = env.YOURPOST_SERVICE_TOKEN;

      // Build URL
      const incomingUrl = `${serviceUrl}/api/service/incoming`;

      // Reconstruct raw email
      const rawEmail = await reconstructEmail(message);

      // Prepare headers
      const headers = {
        'Content-Type': 'message/rfc822',
      };

      // Add authentication if token is configured
      if (serviceToken) {
        headers['Authorization'] = `Bearer ${serviceToken}`;
      }

      // Forward to YourPost
      const response = await fetch(incomingUrl, {
        method: 'POST',
        headers: headers,
        body: rawEmail
      });

      if (response.ok) {
        console.log(`Email delivered: ${message.from} → ${message.to}`);
      } else {
        console.error(`Delivery failed: ${response.status} ${response.statusText}`);
        message.setReject(`Delivery failed: ${response.status}`);
      }

    } catch (error) {
      console.error(`Error: ${error.message}`);
      message.setReject('Temporary error processing email');
    }
  }
};

/**
 * Reconstruct raw email from Cloudflare Message object
 */
async function reconstructEmail(message) {
  const parts = [];

  // Add required headers
  parts.push(`From: ${message.from}`);
  parts.push(`To: ${message.to}`);
  
  // Add other headers
  for (const [key, value] of message.headers.entries()) {
    if (!['from', 'to'].includes(key.toLowerCase())) {
      parts.push(`${key}: ${value}`);
    }
  }
  
  // Add date if not present
  if (!message.headers.has('date')) {
    parts.push(`Date: ${new Date().toUTCString()}`);
  }
  
  // Add Message-ID if not present
  if (!message.headers.has('message-id')) {
    const messageId = `<${Date.now()}.${Math.random().toString(36).substr(2)}@${message.to.split('@')[1]}>`;
    parts.push(`Message-ID: ${messageId}`);
  }
  
  parts.push(''); // Empty line between headers and body

  // Add body
  if (message.text) {
    const text = await message.text();
    parts.push(text);
  } else if (message.html) {
    const html = await message.html();
    parts.push('Content-Type: text/html; charset=utf-8');
    parts.push('');
    parts.push(html);
  }

  return parts.join('\r\n');
}
```

### Step 3: Configure Worker Secrets

Set your YourPost service URL and token as secrets:

```bash
# Navigate to worker directory
cd yourpost-worker

# Set service URL (use internal IP or tunnel)
wrangler secret put YOURPOST_SERVICE_URL
# Enter: http://yourpost-server:9001

# Set service token
wrangler secret put YOURPOST_SERVICE_TOKEN
# Enter: your-secure-token-here
```

### Step 4: Deploy Worker

```bash
# Deploy to Cloudflare
wrangler deploy

# Expected output:
# ✨ Successfully deployed yourpost-email-worker
#   https://yourpost-email-worker.your-account.workers.dev
```

### Step 5: Configure Email Routing

#### 5.1 Enable Email Routing

1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Select your domain
3. Go to **Email** → **Email Routing**
4. Enable Email Routing

#### 5.2 Configure MX Records

Cloudflare will provide MX records. Add them to your DNS:

```
Type: MX
Name: @
Mail server: mx1.cloudflare.net
Priority: 10

Type: MX
Name: @
Mail server: mx2.cloudflare.net
Priority: 10
```

#### 5.3 Create Catch-all Route

1. Go to **Email Routing** → **Routes**
2. Click **Create Route**
3. Configure:
   - **Name**: Forward to YourPost
   - **Expression**: `true` (catch-all) or specific like `email.addr eq "*@yourdomain.com"`
   - **Action**: Send to a Worker
   - **Worker**: Select your deployed worker

#### 5.4 Verify Domain (Optional but Recommended)

1. Go to **Email Routing** → **Address Management**
2. Add addresses that can receive email
3. Verify ownership

## Worker Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `YOURPOST_SERVICE_URL` | YourPost Service API URL | Yes |
| `YOURPOST_SERVICE_TOKEN` | Bearer token for authentication | No (but recommended) |

### Local Development

Create `wrangler.toml` with local development settings:

```toml
name = "yourpost-email-worker"
main = "src/index.js"
compatibility_date = "2024-01-01"

[env.production]
name = "yourpost-email-worker-production"

[env.local]
name = "yourpost-email-worker-local"
```

Run locally:

```bash
wrangler dev --env local
```

### Testing Worker

```bash
# Test with curl
curl -X POST http://localhost:8787/

# Test email handling (requires wrangler)
wrangler dev --test
```

## Email Routing

### Route Examples

#### Catch-all Route

Route all emails to YourPost:

```
Expression: true
Action: Send to Worker
```

#### Specific Address

Route only specific addresses:

```
Expression: email.addr eq "support@yourdomain.com"
Action: Send to Worker
```

#### Multiple Addresses

```
Expression: email.addr eq "support@yourdomain.com" or email.addr eq "info@yourdomain.com"
Action: Send to Worker
```

#### Domain-based Routing

```
Expression: email.addr matches "*@domain1.com"
Action: Send to Worker
```

### Advanced Routing

#### Route Based on Content

```javascript
// In your worker
if (message.headers.get('x-spam-score') > '5') {
  // Send to spam folder
  await forwardToSpam(message);
} else {
  // Normal delivery
  await forwardToYourPost(message);
}
```

#### Forward to Multiple Destinations

```javascript
// Forward to YourPost and archive
await Promise.all([
  forwardToYourPost(message),
  forwardToArchive(message)
]);
```

## Security

### Authentication

#### Service Token

Always set `YP_SERVICE_TOKEN` in YourPost:

```bash
export YP_SERVICE_TOKEN=$(openssl rand -hex 32)
```

Worker will automatically include it:

```javascript
headers['Authorization'] = `Bearer ${serviceToken}`;
```

#### Verify Token in Requests

YourPost automatically verifies the token if configured.

### Network Security

#### Use Cloudflare Tunnel

For additional security, use Cloudflare Tunnel:

```bash
# Install cloudflared
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create yourpost

# Configure ingress
cloudflared tunnel ingress http://localhost:9001
```

#### Firewall Rules

Restrict access to port 9001:

```bash
# Only allow localhost
sudo ufw allow from 127.0.0.1 to any port 9001

# Or allow Cloudflare IPs only
# See: https://www.cloudflare.com/ips/
```

### Rate Limiting

Cloudflare provides built-in rate limiting:

1. Go to **Security** → **WAF** → **Rate limiting rules**
2. Create rule for your worker
3. Limit requests per IP

## Troubleshooting

### Worker Not Receiving Emails

```bash
# 1. Check worker is deployed
wrangler tail

# 2. Verify email routing is enabled
# Cloudflare Dashboard → Email → Email Routing

# 3. Check MX records
nslookup -type=MX yourdomain.com

# 4. Test with manual email
curl -X POST "https://api.cloudflare.com/client/v4/accounts/{account_id}/email/routing"
```

### Delivery Failures

```bash
# 1. Check YourPost logs
sudo journalctl -u yourpost -f

# 2. Test Service API
curl http://localhost:9001/health

# 3. Check worker logs
wrangler tail

# 4. Verify token
env | grep YOURPOST_SERVICE_TOKEN
```

### Authentication Errors

```bash
# Error: 401 Unauthorized

# 1. Check token matches
# Worker: YOURPOST_SERVICE_TOKEN
# YourPost: YP_SERVICE_TOKEN

# 2. Verify token is set
curl -H "Authorization: Bearer wrong-token" \
  http://localhost:9001/api/service/incoming

# 3. Check header format
# Should be: "Authorization: Bearer token"
```

### Email Not Stored

```bash
# 1. Check mailbox directory
ls -la /var/lib/yourpost/mailboxes/

# 2. Verify user exists
curl http://localhost:9000/api/v1/users

# 3. Check permissions
sudo chown -R yourpost:yourpost /var/lib/yourpost
```

### Worker Timeouts

```bash
# Error: Worker timeout

# 1. Increase timeout in worker
// Default is 30 seconds

# 2. Check YourPost performance
sudo journalctl -u yourpost | grep -i error

# 3. Optimize database
sqlite3 /var/lib/yourpost/data/mailboxes/*.db "VACUUM;"
```

## Monitoring

### Worker Metrics

Cloudflare provides built-in metrics:

1. Go to **Workers & Pages** → **Your Worker** → **Metrics**
2. Monitor:
   - Requests per minute
   - Error rate
   - Duration
   - CPU time

### Logs

```bash
# Tail worker logs
wrangler tail

# Filter by severity
wrangler tail --format pretty --level error

# Filter by time
wrangler tail --since 1h
```

### Alerts

Set up Cloudflare alerts:

1. Go to **Alerts** → **Create Alert**
2. Configure:
   - Condition: Error rate > 5%
   - Notify: Email/Slack/PagerDuty
   - Frequency: Every 5 minutes

## Advanced Configuration

### Custom Email Processing

```javascript
// Add custom headers
async function processEmail(message) {
  // Add custom header
  const headers = {
    'X-Processed-By': 'YourPost-Worker',
    'X-Received-At': new Date().toISOString()
  };
  
  // Check for spam
  const spamScore = await checkSpam(message);
  if (spamScore > 5) {
    await quarantineEmail(message);
    return;
  }
  
  // Forward to YourPost
  await forwardToYourPost(message, headers);
}
```

### Multiple Workers

```javascript
// Route different domains to different workers
if (message.to.endsWith('@domain1.com')) {
  await forwardToWorker1(message);
} else if (message.to.endsWith('@domain2.com')) {
  await forwardToWorker2(message);
}
```

### Email Transformation

```javascript
// Modify email content
async function transformEmail(message) {
  let html = await message.html();
  
  // Add footer
  html += '<hr><p>Sent via YourPost</p>';
  
  // Remove tracking pixels
  html = html.replace(/<img[^>]*tracking[^>]*>/gi, '');
  
  return html;
}
```

### DKIM Signing

```javascript
// Sign emails with DKIM
import { sign } from 'dkim';

async function signEmail(rawEmail) {
  const signature = sign({
    privateKey: process.env.DKIM_PRIVATE_KEY,
    domainName: 'yourdomain.com',
    selector: 'default',
    headers: ['from', 'to', 'subject', 'date']
  }, rawEmail);
  
  return signature + rawEmail;
}
```

## Best Practices

### 1. **Always Use Authentication**

```bash
# Set service token
export YP_SERVICE_TOKEN=$(openssl rand -hex 32)
```

### 2. **Monitor Worker Performance**

```bash
# Check worker metrics regularly
wrangler tail --format metrics
```

### 3. **Implement Retry Logic**

```javascript
// Retry failed deliveries
const maxRetries = 3;
for (let i = 0; i < maxRetries; i++) {
  try {
    await forwardToYourPost(message);
    break;
  } catch (error) {
    if (i === maxRetries - 1) throw error;
    await new Promise(r => setTimeout(r, 1000 * Math.pow(2, i)));
  }
}
```

### 4. **Set Up Alerts**

```bash
# Monitor error rates
# Set up Cloudflare alerts
# Check logs regularly
```

### 5. **Keep Worker Updated**

```bash
# Update wrangler
npm update -g wrangler

# Update dependencies
npm update
```

### 6. **Test Regularly**

```bash
# Test email delivery
curl -X POST http://localhost:9001/api/service/incoming \
  -H "Content-Type: message/rfc822" \
  --data-binary @test.eml
```

## Cost Optimization

### Free Tier

- Cloudflare Email Routing: Free
- Workers: 100,000 requests/day free
- YourPost: Free and open source

### Cost Factors

- Email volume (beyond free tier)
- Worker execution time
- Additional Cloudflare services

### Optimization Tips

1. **Filter spam before delivery**
2. **Batch processing** (if applicable)
3. **Cache frequently accessed data**
4. **Optimize worker code**

## Next Steps

- [Configuration Guide](CONFIGURATION.md) - All configuration options
- [SMTP Relay Setup](SMTP_RELAY.md) - Configure outgoing email
- [API Documentation](API.md) - Complete API reference
- [Security Guide](SECURITY.md) - TLS and hardening