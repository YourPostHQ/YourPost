# API Documentation

Complete reference for YourPost HTTP API.

## Table of Contents

- [Overview](#overview)
- [Base URLs](#base-urls)
- [Authentication](#authentication)
- [Health Endpoints](#health-endpoints)
- [User Management](#user-management)
- [Mailbox Operations](#mailbox-operations)
- [Email Sending](#email-sending)
- [Service API](#service-api)
- [Error Codes](#error-codes)
- [Examples](#examples)

## Overview

YourPost provides two HTTP APIs:

1. **Public API** (port 9000): User-facing operations
   - User management
   - Authentication
   - Mailbox operations
   - Email sending

2. **Service API** (port 9001): Internal operations
   - Email receiving (from Cloudflare Workers)
   - Protected by bearer token

## Base URLs

### Public API

```
http://localhost:9000/api/v1
```

### Service API

```
http://localhost:9001/api/service
```

## Authentication

### User Authentication

Most user endpoints require authentication via session cookie or bearer token.

#### Login

```bash
curl -X POST http://localhost:9000/api/v1/auth \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "password"
  }'
```

**Response**:

```json
{
  "status": "success",
  "message": "Login successful"
}
```

Sets a session cookie for subsequent requests.

### Service API Authentication

Service API requires bearer token if `YP_SERVICE_TOKEN` is set:

```bash
curl -X POST http://localhost:9001/api/service/incoming \
  -H "Authorization: Bearer your-token-here" \
  -H "Content-Type: message/rfc822" \
  --data-binary @email.eml
```

## Health Endpoints

### Health Check

```
GET /health
```

Returns basic health status.

**Response**:

```json
{
  "status": "ok",
  "service": "yourpost"
}
```

### Readiness Check

```
GET /health/ready
```

Checks if service is ready to accept requests.

**Response** (ready):

```json
{
  "status": "ready"
}
```

**Response** (not ready):

```json
{
  "status": "not ready"
}
```

**HTTP Status**: 200 (ready) or 503 (not ready)

### Liveness Check

```
GET /health/live
```

Checks if service is alive.

**Response**:

```json
{
  "status": "alive",
  "service": "yourpost",
  "uptime": "unknown"
}
```

## User Management

### List Users

```
GET /api/v1/users
```

Returns all users in the system.

**Authentication**: Required

**Response**:

```json
{
  "status": "success",
  "users": [
    {
      "email": "user1@example.com",
      "created_at": "2026-05-04T12:00:00Z",
      "is_active": true
    },
    {
      "email": "user2@example.com",
      "created_at": "2026-05-04T12:00:00Z",
      "is_active": true
    }
  ]
}
```

### Create User

```
POST /api/v1/users
Content-Type: application/json
```

**Request Body**:

```json
{
  "email": "user@example.com",
  "password": "securepassword"
}
```

**Parameters**:

- `email` (string, required): Full email address
- `password` (string, required): User password (min 8 characters)

**Response**:

```json
{
  "status": "success",
  "message": "User created successfully",
  "user": {
    "email": "user@example.com",
    "created_at": "2026-05-04T12:00:00Z",
    "is_active": true
  }
}
```

**Errors**:

- `400 Bad Request`: Invalid email or password
- `409 Conflict`: User already exists
- `500 Internal Server Error`: Database error

### Delete User

```
DELETE /api/v1/users/{email}
```

Deactivates a user (soft delete).

**Authentication**: Required

**Parameters**:

- `email` (path, required): Email address to delete

**Response**:

```json
{
  "status": "success",
  "message": "User deactivated"
}
```

**Errors**:

- `404 Not Found`: User not found
- `500 Internal Server Error`: Database error

### Authenticate User

```
POST /api/v1/auth
Content-Type: application/json
```

**Request Body**:

```json
{
  "email": "user@example.com",
  "password": "password"
}
```

**Response**:

```json
{
  "status": "success",
  "message": "Login successful"
}
```

**Errors**:

- `401 Unauthorized`: Invalid credentials
- `404 Not Found`: User not found

## Mailbox Operations

### List Folders

```
GET /api/v1/mailboxes/{user}/folders
```

Returns all folders for a user.

**Authentication**: Required

**Parameters**:

- `user` (path, required): Email address

**Response**:

```json
{
  "status": "success",
  "folders": [
    {
      "name": "INBOX",
      "total_messages": 42,
      "unseen_messages": 5
    },
    {
      "name": "Sent",
      "total_messages": 120,
      "unseen_messages": 0
    },
    {
      "name": "Trash",
      "total_messages": 3,
      "unseen_messages": 0
    }
  ]
}
```

### List Messages

```
GET /api/v1/mailboxes/{user}/messages?folder=INBOX&limit=50&offset=0
```

Lists messages in a folder.

**Authentication**: Required

**Parameters**:

- `user` (path, required): Email address
- `folder` (query, optional): Folder name (default: INBOX)
- `limit` (query, optional): Max messages (default: 50)
- `offset` (query, optional): Pagination offset (default: 0)

**Response**:

```json
{
  "status": "success",
  "messages": [
    {
      "id": 12345,
      "uid": 12345,
      "from": "sender@example.com",
      "to": ["user@example.com"],
      "subject": "Hello World",
      "date": "2026-05-04T12:00:00Z",
      "size": 1024,
      "flags": ["Seen", "Flagged"],
      "has_attachment": false,
      "snippet": "This is a test email..."
    }
  ],
  "total": 42,
  "limit": 50,
  "offset": 0
}
```

### Get Message

```
GET /api/v1/mailboxes/{user}/messages/{id}
```

Retrieves a single message and marks it as seen.

**Authentication**: Required

**Parameters**:

- `user` (path, required): Email address
- `id` (path, required): Message ID

**Response**:

```json
{
  "status": "success",
  "message": {
    "id": 12345,
    "uid": 12345,
    "from": "sender@example.com",
    "to": ["user@example.com"],
    "cc": [],
    "bcc": [],
    "subject": "Hello World",
    "date": "2026-05-04T12:00:00Z",
    "size": 1024,
    "flags": ["Seen", "Flagged"],
    "headers": {
      "Message-ID": "<abc123@example.com>",
      "Content-Type": "text/plain"
    },
    "body": {
      "text": "This is the plain text body",
      "html": "<p>This is the HTML body</p>"
    },
    "attachments": []
  }
}
```

**Errors**:

- `404 Not Found`: Message not found

### Delete Message

```
DELETE /api/v1/mailboxes/{user}/messages/{id}
```

Marks a message as deleted (soft delete).

**Authentication**: Required

**Parameters**:

- `user` (path, required): Email address
- `id` (path, required): Message ID

**Response**:

```json
{
  "status": "success",
  "message": "Message marked as deleted"
}
```

**Errors**:

- `404 Not Found`: Message not found

### Send Email

```
POST /api/v1/mailboxes/{user}/send
Content-Type: application/json
```

Sends an email on behalf of a user.

**Authentication**: Required

**Parameters**:

- `user` (path, required): Sender email address

**Request Body**:

```json
{
  "to": ["recipient@example.com"],
  "cc": ["cc@example.com"],
  "bcc": ["bcc@example.com"],
  "subject": "Hello World",
  "body": "Email body text",
  "html": "<p>HTML body</p>",
  "in_reply_to": "<parent-message-id>",
  "references": ["<parent-message-id>"]
}
```

**Fields**:

- `to` (array, required): Recipient addresses
- `cc` (array, optional): CC addresses
- `bcc` (array, optional): BCC addresses
- `subject` (string, required): Email subject
- `body` (string, optional): Plain text body
- `html` (string, optional): HTML body
- `in_reply_to` (string, optional): Parent message ID
- `references` (array, optional): Thread references

**Response**:

```json
{
  "status": "success",
  "message": "Email sent successfully",
  "message_id": "<generated-message-id@hostname>"
}
```

**Errors**:

- `400 Bad Request`: Invalid email format
- `401 Unauthorized`: User not authenticated
- `403 Forbidden`: User not authorized to send as this address
- `500 Internal Server Error`: Sending failed

## Service API

### Receive Email

```
POST /api/service/incoming
Content-Type: message/rfc822
Authorization: Bearer <token> (if configured)
```

Receives an email from Cloudflare Worker or other service.

**Authentication**: Bearer token if `YP_SERVICE_TOKEN` is set

**Request Body**: Raw RFC 822 email

**Response**:

```json
{
  "status": "delivered"
}
```

**Errors**:

- `401 Unauthorized`: Invalid or missing token
- `400 Bad Request`: Invalid email format
- `500 Internal Server Error`: Delivery failed

### Example: Cloudflare Worker

```javascript
const response = await fetch('http://localhost:9001/api/service/incoming', {
  method: 'POST',
  headers: {
    'Content-Type': 'message/rfc822',
    'Authorization': 'Bearer your-token'
  },
  body: rawEmail
});
```

## Error Codes

### HTTP Status Codes

| Code | Meaning |
|------|---------|
| 200 | Success |
| 201 | Created |
| 400 | Bad Request (invalid input) |
| 401 | Unauthorized (authentication required) |
| 403 | Forbidden (insufficient permissions) |
| 404 | Not Found |
| 409 | Conflict (resource exists) |
| 429 | Too Many Requests (rate limited) |
| 500 | Internal Server Error |
| 503 | Service Unavailable |

### Error Response Format

```json
{
  "status": "error",
  "message": "Detailed error message",
  "code": "ERROR_CODE"
}
```

### Common Error Codes

| Code | Description |
|------|-------------|
| `INVALID_EMAIL` | Email address format invalid |
| `USER_EXISTS` | User already exists |
| `USER_NOT_FOUND` | User not found |
| `INVALID_CREDENTIALS` | Wrong username/password |
| `MESSAGE_NOT_FOUND` | Message doesn't exist |
| `UNAUTHORIZED` | Authentication required |
| `FORBIDDEN` | Insufficient permissions |
| `RATE_LIMITED` | Too many requests |
| `RELAY_ERROR` | SMTP relay failed |

## Rate Limiting

Rate limiting may be applied to prevent abuse:

- **Public API**: 100 requests/minute per IP
- **Service API**: 1000 requests/minute per token

**Response Headers**:

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1714824000
```

## Pagination

List endpoints support pagination:

```
GET /api/v1/mailboxes/user@example.com/messages?limit=50&offset=100
```

**Response Headers**:

```
X-Total-Count: 1000
X-Limit: 50
X-Offset: 100
```

## Content Types

### Supported Content Types

- `application/json` - JSON requests/responses
- `message/rfc822` - Raw email (Service API)
- `multipart/form-data` - File uploads (future)

### Accept Headers

```
Accept: application/json
```

## Examples

### Complete Workflow

```bash
# 1. Create a user
curl -X POST http://localhost:9000/api/v1/users \
  -H "Content-Type: application/json" \
  -d '{
    "email": "alice@example.com",
    "password": "SecurePass123!"
  }'

# 2. Login
curl -X POST http://localhost:9000/api/v1/auth \
  -H "Content-Type: application/json" \
  -c cookies.txt \
  -d '{
    "email": "alice@example.com",
    "password": "SecurePass123!"
  }'

# 3. List folders
curl http://localhost:9000/api/v1/mailboxes/alice@example.com/folders \
  -b cookies.txt

# 4. Send an email
curl -X POST http://localhost:9000/api/v1/mailboxes/alice@example.com/send \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{
    "to": ["bob@example.com"],
    "subject": "Hello from Alice",
    "body": "Hi Bob!\n\nHow are you?\n\nBest,\nAlice"
  }'

# 5. Check inbox
curl "http://localhost:9000/api/v1/mailboxes/alice@example.com/messages?folder=INBOX" \
  -b cookies.txt

# 6. Health check
curl http://localhost:9000/health
```

### Using with curl and Bearer Token

```bash
# Get token from login
TOKEN=$(curl -s -X POST http://localhost:9000/api/v1/auth \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"pass"}' | jq -r '.token')

# Use bearer token
curl http://localhost:9000/api/v1/users \
  -H "Authorization: Bearer $TOKEN"
```

### Cloudflare Worker Integration

```javascript
// In your Cloudflare Worker
const response = await fetch(
  'http://yourpost.example.com:9001/api/service/incoming',
  {
    method: 'POST',
    headers: {
      'Content-Type': 'message/rfc822',
      'Authorization': `Bearer ${YOURPOST_SERVICE_TOKEN}`
    },
    body: await reconstructEmail(message)
  }
);

if (!response.ok) {
  throw new Error(`Delivery failed: ${response.status}`);
}
```

## Best Practices

### 1. **Always Use HTTPS**

In production, use TLS termination:
- Nginx/Apache reverse proxy
- Cloudflare Tunnel
- Let's Encrypt certificates

### 2. **Handle Rate Limits**

```bash
# Check rate limit headers
curl -i http://localhost:9000/api/v1/users

# Implement exponential backoff
# Retry after X-RateLimit-Reset
```

### 3. **Secure Credentials**

```bash
# Never hardcode tokens
# Use environment variables
# Or secret management systems
```

### 4. **Validate Input**

```bash
# Always validate email addresses
# Sanitize user input
# Use parameterized queries
```

### 5. **Monitor API Usage**

```bash
# Track request rates
# Monitor error rates
# Set up alerts
```

### 6. **Implement Retry Logic**

```bash
# Retry on 5xx errors
# Don't retry on 4xx errors
# Use exponential backoff
```

## Next Steps

- [Configuration Guide](CONFIGURATION.md) - All configuration options
- [SMTP Relay Setup](SMTP_RELAY.md) - Configure outgoing email
- [Cloudflare Integration](CLOUDFLARE.md) - Email routing
- [Security Guide](SECURITY.md) - TLS and hardening