# Security Guide

This guide covers security best practices for YourPost deployment.

## Table of Contents

- [Security Overview](#security-overview)
- [TLS/SSL Configuration](#tlsssl-configuration)
- [Authentication](#authentication)
- [Network Security](#network-security)
- [Access Control](#access-control)
- [Data Protection](#data-protection)
- [Audit Logging](#audit-logging)
- [Hardening](#hardening)
- [Monitoring](#monitoring)
- [Incident Response](#incident-response)

## Security Overview

YourPost is designed with security in mind, but proper configuration is essential for a secure deployment. This guide covers:

- Transport encryption (TLS)
- Authentication mechanisms
- Network security
- Access control
- Data protection
- Monitoring and logging

## TLS/SSL Configuration

### Why TLS is Important

TLS (Transport Layer Security) encrypts email communications:
- **Confidentiality**: Prevents eavesdropping
- **Integrity**: Detects tampering
- **Authentication**: Verifies server identity

### Enabling TLS

#### SMTP STARTTLS

```bash
# Enable STARTTLS on SMTP ports
export YP_SMTP_USE_TLS=true
export YP_SMTP_TLS_CERT=/etc/letsencrypt/live/mail.example.com/fullchain.pem
export YP_SMTP_TLS_KEY=/etc/letsencrypt/live/mail.example.com/privkey.pem
```

#### POP3 TLS

```bash
export YP_POP3_USE_TLS=true
export YP_POP3_TLS_CERT=/etc/letsencrypt/live/mail.example.com/fullchain.pem
export YP_POP3_TLS_KEY=/etc/letsencrypt/live/mail.example.com/privkey.pem
```

#### IMAP TLS

```bash
export YP_IMAP_USE_TLS=true
export YP_IMAP_TLS_CERT=/etc/letsencrypt/live/mail.example.com/fullchain.pem
export YP_IMAP_TLS_KEY=/etc/letsencrypt/live/mail.example.com/privkey.pem
```

### Certificate Management

#### Using Let's Encrypt

```bash
# Install certbot
sudo apt install certbot

# Obtain certificate
sudo certbot certonly --standalone -d mail.example.com

# Auto-renewal
sudo certbot renew --dry-run
```

#### Certificate Permissions

```bash
# Restrict access to private key
chmod 600 /etc/letsencrypt/live/mail.example.com/privkey.pem
chown yourpost:yourpost /etc/letsencrypt/live/mail.example.com/privkey.pem
```

### Implicit TLS (SMTPS, POP3S, IMAPS)

For legacy clients that don't support STARTTLS:

```bash
# SMTPS (port 465)
export YP_SMTPS_PORT=465

# POP3S (port 995)
export YP_POP3S_PORT=995

# IMAPS (port 993)
export YP_IMAPS_PORT=993
```

### TLS Best Practices

1. **Use strong ciphers**
2. **Disable SSLv2/SSLv3**
3. **Prefer TLS 1.2 or higher**
4. **Enable HSTS** (for web interfaces)
5. **Use certificates from trusted CAs**
6. **Enable OCSP stapling**
7. **Implement certificate pinning** (for mobile apps)

### Testing TLS Configuration

```bash
# Test with OpenSSL
openssl s_client -connect mail.example.com:587 -starttls smtp

# Check certificate
openssl x509 -in /path/to/cert.pem -text -noout

# Test with SSL Labs
# https://www.ssllabs.com/ssltest/
```

## Authentication

### Service API Authentication

#### Bearer Token

```bash
# Generate secure token
export YP_SERVICE_TOKEN=$(openssl rand -hex 32)
```

#### Token Usage

```bash
# API request with authentication
curl -X POST http://localhost:9001/api/service/incoming \
  -H "Authorization: Bearer your-token-here" \
  -H "Content-Type: message/rfc822" \
  --data-binary @email.eml
```

### User Authentication

#### Password Requirements

- Minimum 8 characters
- Mix of uppercase and lowercase
- Include numbers
- Include special characters
- No common passwords

#### Session Management

- Sessions expire after inactivity
- Secure cookie flags (HttpOnly, Secure, SameSite)
- Session regeneration on login

### Multi-Factor Authentication (MFA)

MFA is not yet implemented but planned. Consider:
- TOTP (Time-based One-Time Password)
- U2F/FIDO2 hardware keys
- SMS/Email verification (less secure)

## Network Security

### Firewall Configuration

```bash
# Allow only necessary ports
sudo ufw allow 25/tcp    # SMTP
sudo ufw allow 587/tcp   # SMTP submission
sudo ufw allow 465/tcp   # SMTPS
sudo ufw allow 110/tcp   # POP3
sudo ufw allow 995/tcp   # POP3S
sudo ufw allow 143/tcp   # IMAP
sudo ufw allow 993/tcp   # IMAPS
sudo ufw allow 9000/tcp  # API
# Port 9001 should NOT be publicly accessible

# Deny all other incoming
sudo ufw default deny incoming
sudo ufw enable
```

### Port 9001 Protection

The service API (port 9001) should NOT be publicly accessible:

```bash
# Restrict to localhost only
sudo iptables -A INPUT -p tcp --dport 9001 -s 127.0.0.1 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 9001 -j DROP
```

### Cloudflare Tunnel

Use Cloudflare Tunnel for secure access:

```bash
cloudflared tunnel create yourpost
cloudflared tunnel route-dns yourpost mail.example.com
```

### VPN Access

For administrative access:

```bash
# Set up WireGuard or OpenVPN
# Restrict admin ports to VPN only
```

### Rate Limiting

```bash
# Limit connection attempts
sudo iptables -A INPUT -p tcp --dport 25 -m connlimit --connlimit-above 10 -j REJECT
sudo iptables -A INPUT -p tcp --dport 587 -m connlimit --connlimit-above 10 -j REJECT
```

## Access Control

### Principle of Least Privilege

```bash
# Run as non-root user
useradd -r -s /usr/sbin/nologin yourpost

# Restrict file permissions
chown -R yourpost:yourpost /var/lib/yourpost
chmod 750 /var/lib/yourpost
chmod 640 /var/lib/yourpost/*.db
```

### Systemd Security Hardening

The provided `yourpost.service` includes:

```ini
# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true

# Capability restriction
AmbientCapabilities=CAP_NET_BIND_SERVICE
```

### File Permissions

```bash
# Configuration files
chmod 640 /etc/yourpost/yourpost.env
chown root:yourpost /etc/yourpost/yourpost.env

# TLS certificates
chmod 640 /etc/letsencrypt/live/mail.example.com/*.pem
chown yourpost:yourpost /etc/letsencrypt/live/mail.example.com/*.pem

# Log files
chmod 640 /var/log/yourpost/*.log
chown yourpost:adm /var/log/yourpost/*.log
```

## Data Protection

### Encryption at Rest

#### Full Disk Encryption

```bash
# Use LUKS for full disk encryption
cryptsetup luksFormat /dev/sda1
cryptsetup luksOpen /dev/sda1 encrypted
```

#### Database Encryption

SQLite databases can be encrypted:

```bash
# Use SQLCipher (not yet implemented in YourPost)
# Consider encrypting sensitive fields
```

### Backup Security

```bash
# Encrypt backups
tar czf - /var/lib/yourpost | openssl enc -aes-256-cbc -out backup.tar.gz.enc

# Store backups securely
# Off-site storage
# Access controls
```

### Data Retention

```bash
# Configure logrotate for automatic cleanup
/var/log/yourpost/*.log {
    daily
    rotate 30  # Keep 30 days
    compress
    delaycompress
    missingok
    notifempty
}
```

## Audit Logging

### Enable Logging

YourPost logs to journald by default:

```bash
# View logs
sudo journalctl -u yourpost -f

# Filter by priority
sudo journalctl -u yourpost -p err

# Export logs
sudo journalctl -u yourpost --no-pager > /var/log/yourpost/audit.log
```

### Log Monitoring

```bash
# Monitor for suspicious activity
sudo journalctl -u yourpost | grep -i "failed\|error\|reject"

# Track authentication attempts
sudo journalctl -u yourpost | grep -i "auth"

# Monitor rate limiting
sudo journalctl -u yourpost | grep -i "rate\|limit"
```

### Centralized Logging

```bash
# Forward to syslog
sudo apt install rsyslog

# Or use log aggregation
# ELK Stack
# Graylog
# Splunk
```

## Hardening

### System Hardening

```bash
# Disable unnecessary services
sudo systemctl disable bluetooth
sudo systemctl disable cups

# Enable automatic security updates
sudo apt install unattended-upgrades
sudo dpkg-reconfigure unattended-upgrades

# Configure fail2ban
sudo apt install fail2ban
```

### Application Hardening

```bash
# Compile with security flags
zig build -Doptimize=ReleaseSafe

# Enable ASLR
echo 2 | sudo tee /proc/sys/kernel/randomize_va_space

# Enable stack protection
echo 1 | sudo tee /proc/sys/kernel/stack-protector
```

### Kernel Hardening

```bash
# Restrict ptrace
sysctl kernel.yama.ptrace_scope=2

# Enable TCP SYN cookies
sysctl net.ipv4.tcp_syncookies=1

# Disable IP forwarding
sysctl net.ipv4.ip_forward=0
```

## Monitoring

### Security Monitoring

```bash
# File integrity monitoring
sudo apt install aide
sudo aideinit

# Intrusion detection
sudo apt install tripwire

# Network monitoring
sudo apt install ntopng
```

### Alerting

```bash
# Set up alerts for:
# - Failed login attempts
# - Unusual traffic patterns
# - Certificate expiration
# - Disk space
# - High CPU/memory usage
```

### Regular Audits

```bash
# Monthly security audit
# - Review access logs
# - Check for unauthorized changes
# - Verify backups
# - Update software
# - Rotate credentials
```

## Incident Response

### Preparation

1. **Document procedures**
2. **Maintain backups**
3. **Test recovery procedures**
4. **Train staff**

### Detection

```bash
# Monitor for indicators
# - Unusual login patterns
# - High failure rates
# - Unexpected traffic
# - System anomalies
```

### Response

```bash
# 1. Isolate affected systems
sudo systemctl stop yourpost

# 2. Preserve evidence
sudo tar czf incident-$(date +%Y%m%d).tar.gz /var/log/yourpost/

# 3. Investigate
sudo journalctl -u yourpost --since "2026-05-01"

# 4. Eradicate
# Remove malware, close vulnerabilities

# 5. Recover
# Restore from clean backups
```

### Recovery

```bash
# Restore from backup
tar xzf backup.tar.gz -C /

# Verify integrity
sha256sum -c checksums.txt

# Resume operations
sudo systemctl start yourpost
```

### Post-Incident

1. **Document lessons learned**
2. **Update procedures**
3. **Improve monitoring**
4. **Communicate with stakeholders**

## Compliance

### GDPR

- Data minimization
- Right to erasure
- Data portability
- Privacy by design

### HIPAA

- Encryption requirements
- Access controls
- Audit logging
- Business Associate Agreement

### PCI DSS

- Network segmentation
- Encryption of cardholder data
- Regular security testing
- Access control measures

## Best Practices Checklist

- [ ] Enable TLS on all ports
- [ ] Use certificates from trusted CA
- [ ] Set strong service token
- [ ] Restrict port 9001 access
- [ ] Run as non-root user
- [ ] Enable firewall
- [ ] Configure fail2ban
- [ ] Enable audit logging
- [ ] Set up monitoring
- [ ] Regular backups
- [ ] Test recovery procedures
- [ ] Keep software updated
- [ ] Review logs regularly
- [ ] Rotate credentials
- [ ] Conduct security audits

## Additional Resources

- [CISA Security Guidelines](https://www.cisa.gov)
- [OWASP Top 10](https://owasp.org)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org)
- [CERT Secure Coding](https://www.securecoding.cert.org)

## Next Steps

- [Configuration Guide](CONFIGURATION.md)
- [SMTP Relay Setup](SMTP_RELAY.md)
- [API Documentation](API.md)
- [Cloudflare Integration](CLOUDFLARE.md)