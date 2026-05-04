# YourPost Documentation

Welcome to the YourPost documentation. This mail server provides SMTP, POP3, IMAP, and HTTP API services in a lightweight Zig implementation.

## Quick Links

- [📖 Setup Guide](SETUP.md) - Get started quickly
- [⚙️ Configuration](CONFIGURATION.md) - All configuration options
- [📧 SMTP Relay](SMTP_RELAY.md) - Configure outgoing email relay
- [🔌 API Reference](API.md) - Complete API documentation
- [☁️ Cloudflare Integration](CLOUDFLARE.md) - Email routing setup
- [🛡️ Security Guide](SECURITY.md) - TLS, authentication, hardening
- [🐳 Docker Deployment](DOCKER.md) - Container deployment guide

## Documentation Structure

### Getting Started

1. **[Setup Guide](SETUP.md)**
   - Building from source
   - Quick start examples
   - User management
   - Testing your installation

2. **[Configuration Guide](CONFIGURATION.md)**
   - Environment variables reference
   - Port configuration
   - TLS/SSL setup
   - Multi-domain support

### Deployment

3. **[Docker Deployment](DOCKER.md)**
   - Docker Compose examples
   - Production deployment
   - Monitoring and logging

4. **[Security Guide](SECURITY.md)**
   - TLS configuration
   - Authentication
   - Network security
   - Hardening checklist

### Features

5. **[SMTP Relay Setup](SMTP_RELAY.md)**
   - Why use SMTP relay
   - Popular relay services
   - Configuration examples
   - Troubleshooting

6. **[Cloudflare Integration](CLOUDFLARE.md)**
   - Email Worker setup
   - Email routing configuration
   - Security considerations

7. **[API Reference](API.md)**
   - Health endpoints
   - User management
   - Mailbox operations
   - Email sending
   - Service API

## Architecture Overview

```

                    YourPost Mail Server                      

                                                             
       
    SMTP   POP3   IMAP   HTTP    Service API          
   Port    Port   Port   Port    (Internal)           
    25     110    143    9000       9001               
       
                                                             
                                                             
                  
                   SQLite Database                   
                   Per-User Mailboxes                
                  

```

## Key Features

- **Lightweight**: Written in Zig for performance and efficiency
- **Multi-protocol**: SMTP, POP3, IMAP support
- **HTTP API**: RESTful API for management and integration
- **Multi-domain**: Support for multiple email domains
- **Cloudflare Integration**: Email routing via Workers
- **SMTP Relay**: Outgoing email through external services
- **TLS Support**: Secure communication with STARTTLS
- **SQLite Storage**: Per-user mailbox databases

## Quick Start

### Build and Run

```bash
# Build
zig build -Doptimize=ReleaseFast

# Run with default settings
./zig-out/bin/yourpost

# Run with custom configuration
YP_HOSTNAME=mail.example.com \
YP_SMTP_PORT=25 \
./zig-out/bin/yourpost
```

### Create a User

```bash
curl -X POST http://localhost:9000/api/v1/users \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "securepassword"
  }'
```

### Send an Email

```bash
curl -X POST http://localhost:9000/api/v1/mailboxes/user@example.com/send \
  -H "Content-Type: application/json" \
  -d '{
    "to": ["recipient@example.com"],
    "subject": "Hello",
    "body": "Test email"
  }'
```

## Configuration Example

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

# Security
export YP_SERVICE_TOKEN=your-secure-token
export YP_MAX_CONNECTIONS=1000

# TLS
export YP_SMTP_USE_TLS=true
export YP_SMTP_TLS_CERT=/etc/letsencrypt/live/mail.example.com/fullchain.pem
export YP_SMTP_TLS_KEY=/etc/letsencrypt/live/mail.example.com/privkey.pem

# SMTP Relay (optional)
export YP_SMTP_RELAY_HOST=smtp.sendgrid.net
export YP_SMTP_RELAY_PORT=587
export YP_SMTP_RELAY_USER=apikey
export YP_SMTP_RELAY_PASSWORD=SG.xxxxxxxxxxxxxxxxxxxxx
```

## Use Cases

### Personal Mail Server

- Host your own email
- Full control over data
- Custom domain support

### Application Email

- Transactional emails
- User notifications
- System alerts

### Development Testing

- Local email testing
- Integration testing
- SMTP/POP3/IMAP testing

### Enterprise Deployment

- Internal mail server
- Department-specific domains
- Custom routing rules

## Support

For issues and questions:

1. Check the [Troubleshooting](SETUP.md#troubleshooting) section
2. Review [Configuration](CONFIGURATION.md) options
3. Check logs: `journalctl -u yourpost -f`
4. Test endpoints: `curl http://localhost:9000/health`

## Contributing

YourPost is open source and welcomes contributions:

- Bug reports and feature requests
- Documentation improvements
- Code contributions
- Translation help

## License

YourPost is licensed under AGPLv3 - see [LICENSE](../LICENSE) for details.

## Additional Resources

- [GitHub Repository](https://github.com/YourPostHQ/YourPost)
- [Issue Tracker](https://github.com/YourPostHQ/YourPost/issues)
- [Changelog](../CHANGELOG.md)
- [Examples](../examples/)

---

**Last Updated**: May 2026  
**Version**: 1.0.0