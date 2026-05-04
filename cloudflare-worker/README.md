# YourPost Cloudflare Email Worker

This Cloudflare Worker forwards incoming emails from Cloudflare Email Routing to your YourPost mail server via the `/incoming` API endpoint.

## Features

- **Email Forwarding** - Forwards emails from Cloudflare to YourPost
- **API Key Authentication** - Secures communication with YourPost server
- **Raw Email Preservation** - Maintains original email format (RFC 822)
- **Error Handling** - Rejects emails if delivery fails

## Setup Instructions

### 1. Prerequisites

- A Cloudflare account
- Wrangler CLI installed (`npm install -g wrangler`)
- YourPost server deployed and accessible via HTTPS

### 2. Configure Secrets

Set the required secrets using Wrangler:

```bash
cd cloudflare-worker

# Set your YourPost server URL
npx wrangler secret put YOURPOST_URL
# Enter: http://yourpost.yourdomain.com

# Set the API key (must match YP_SERVICE_TOKEN on your server)
npx wrangler secret put YOURPOST_SERVICE_TOKEN
# Enter the same key you set in YP_SERVICE_TOKEN environment variable
```

**Note:** The `YOURPOST_SERVICE_TOKEN` must match the `YP_SERVICE_TOKEN` environment variable set on your YourPost server.

### 3. Update wrangler.toml (Optional)

Edit `wrangler.toml` to set a default `YOURPOST_URL` (can be overridden by secret):

```toml
[vars]
YOURPOST_URL = "https://yourpost.yourdomain.com"
```

### 4. Deploy the Worker

```bash
npx wrangler deploy
```

### 5. Configure Cloudflare Email Routing

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Select your domain → **Email** → **Email Routing**
3. Enable Email Routing if not already enabled
4. Add a **Catch-all** rule:
   - Action: **Send to a Worker**
   - Worker: **yourpost** (or whatever you named your worker)
5. Or add specific routes:
   - `*@yourdomain.com` → Send to Worker → yourpost

## How It Works

```
┌─────────────────┐
│  Email Sender   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Cloudflare      │
│ Email Routing   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Cloudflare      │
│ Worker          │
│ (this code)     │
└────────┬────────┘
         │
         │ HTTP POST /incoming
         │ Authorization: Bearer <SERVICE_TOKEN>
         │ Content-Type: message/rfc822
         ▼
┌─────────────────┐
│ YourPost        │
│ HTTP API        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ SQLite          │
│ Mailbox DB      │
└─────────────────┘
```

## API Key Security

When `YOURPOST_SERVICE_TOKEN` is set in the worker secrets:

1. Worker sends `Authorization: Bearer <SERVICE_TOKEN>` header
2. YourPost server validates the key (if `YP_SERVICE_TOKEN` is configured)
3. If valid → email is delivered
4. If invalid → returns `401 Unauthorized`

**Important:** If `YP_SERVICE_TOKEN` is not set on your server, the `/incoming` endpoint accepts requests without authentication (useful for development).

## Testing

### Test the Worker Directly

```bash
# Test health endpoint
curl https://your-worker.your-subdomain.workers.dev/

# Should return: "yourpost email worker is running"
```

### Test Email Delivery

Send an email to an address routed to your worker. Check:

1. Cloudflare Worker logs:
   ```bash
   npx wrangler tail
   ```

2. YourPost server logs for successful delivery

## Configuration Reference

### Secrets (Set via Wrangler)

| Secret | Required | Description |
|--------|----------|-------------|
| `YOURPOST_URL` | Yes | YourPost server URL (e.g., https://yourpost.yourdomain.com) |
| `YOURPOST_SERVICE_TOKEN` | Recommended | API key for authentication (must match server's `YP_SERVICE_TOKEN`) |

### wrangler.toml Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `YOURPOST_URL` | `https://yourpost.privatedata.center` | Fallback URL if secret not set |

## Troubleshooting

### Worker not receiving emails

- Check Email Routing is enabled in Cloudflare Dashboard
- Verify the catch-all or route is set to "Send to Worker"
- Ensure the worker name in the route matches your deployed worker

### 401 Unauthorized errors

- Verify `YOURPOST_SERVICE_TOKEN` secret is set in the worker
- Verify `YP_SERVICE_TOKEN` environment variable is set on your YourPost server
- Ensure both keys match exactly

### Delivery failures

- Check YourPost server is accessible from Cloudflare's network
- Verify SSL/TLS certificate is valid (if using HTTPS)
- Check YourPost server logs for errors

## Files

| File | Description |
|------|-------------|
| `email-worker.js` | The Cloudflare Worker code |
| `wrangler.toml` | Wrangler configuration file |
| `README.md` | This documentation |

## Development

To test locally:

```bash
# Start local development server
npx wrangler dev

# Send test email (in another terminal)
curl -X POST http://localhost:8787/incoming \
  -H "Content-Type: message/rfc822" \
  --data-binary @test-email.eml
```

## License

Part of YourPost - AGPLv3
