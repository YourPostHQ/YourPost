# Docker Deployment Guide

This guide covers deploying YourPost using Docker and Docker Compose.

## Table of Contents

- [Quick Start](#quick-start)
- [Docker Compose](#docker-compose)
- [Configuration](#configuration)
- [Volumes](#volumes)
- [Networking](#networking)
- [Production Deployment](#production-deployment)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)

## Quick Start

### Run with Docker

```bash
# Pull and run YourPost
sudo docker run -d \
  --name yourpost \
  -p 25:25 \
  -p 587:587 \
  -p 465:465 \
  -p 110:110 \
  -p 143:143 \
  -p 9000:9000 \
  -p 9001:9001 \
  -v yourpost-data:/var/lib/yourpost \
  -e YP_HOSTNAME=mail.example.com \
  -e YP_SERVICE_TOKEN=your-secure-token \
  yourpost:latest
```

### Build from Source

```bash
# Clone repository
git clone https://github.com/yourpost/yourpost.git
cd yourpost

# Build Docker image
sudo docker build -t yourpost:latest .

# Run container
sudo docker run -d \
  --name yourpost \
  -p 25:25 \
  -p 587:587 \
  -v yourpost-data:/var/lib/yourpost \
  yourpost:latest
```

## Docker Compose

### Basic Setup

Create `docker-compose.yml`:

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
      - YP_SERVICE_TOKEN=your-secure-token-here
    ports:
      - "25:25"
      - "587:587"
      - "465:465"
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

Start the service:

```bash
docker-compose up -d
```

### With SMTP Relay

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
      - YP_SERVICE_TOKEN=your-secure-token
      # SMTP Relay (SendGrid)
      - YP_SMTP_RELAY_HOST=smtp.sendgrid.net
      - YP_SMTP_RELAY_PORT=587
      - YP_SMTP_RELAY_USER=apikey
      - YP_SMTP_RELAY_PASSWORD=${SENDGRID_API_KEY}
      - YP_SMTP_RELAY_USE_TLS=true
    ports:
      - "25:25"
      - "587:587"
      - "9000:9000"
      - "9001:9001"
    volumes:
      - yourpost-data:/var/lib/yourpost
    restart: unless-stopped

volumes:
  yourpost-data:
```

### With Cloudflare Worker

```yaml
version: '3.8'

services:
  yourpost:
    image: yourpost:latest
    container_name: yourpost
    environment:
      - YP_HOSTNAME=mail.example.com
      - YP_DATA_DIR=/var/lib/yourpost
      - YP_SERVICE_TOKEN=your-secure-token
      - YP_SMTP_RELAY_HOST=smtp.sendgrid.net
      - YP_SMTP_RELAY_PORT=587
      - YP_SMTP_RELAY_USER=apikey
      - YP_SMTP_RELAY_PASSWORD=${SENDGRID_API_KEY}
    ports:
      - "9001:9001"  # Only service port exposed
    volumes:
      - yourpost-data:/var/lib/yourpost
    restart: unless-stopped
```

### Development Environment

```yaml
version: '3.8'

services:
  yourpost:
    build: .
    container_name: yourpost-dev
    environment:
      - YP_HOSTNAME=localhost
      - YP_DATA_DIR=/var/lib/yourpost
      - YP_SMTP_PORT=2525
      - YP_SUBMISSION_PORT=2587
      - YP_POP3_PORT=2110
      - YP_IMAP_PORT=2143
      - YP_API_PORT=9000
      - YP_SERVICE_PORT=9001
      # No service token in development
    ports:
      - "2525:2525"
      - "2587:2587"
      - "2110:2110"
      - "2143:2143"
      - "9000:9000"
      - "9001:9001"
    volumes:
      - ./data:/var/lib/yourpost
      - ./config:/etc/yourpost
    restart: unless-stopped
```

## Configuration

### Environment Variables

All configuration is done via environment variables:

```yaml
environment:
  # Server identity
  - YP_HOSTNAME=mail.example.com
  - YP_DATA_DIR=/var/lib/yourpost
  
  # Ports
  - YP_SMTP_PORT=25
  - YP_SUBMISSION_PORT=587
  - YP_POP3_PORT=110
  - YP_IMAP_PORT=143
  - YP_API_PORT=9000
  - YP_SERVICE_PORT=9001
  
  # Security
  - YP_SERVICE_TOKEN=your-token
  - YP_MAX_CONNECTIONS=1000
  
  # TLS
  - YP_SMTP_USE_TLS=true
  - YP_SMTP_TLS_CERT=/certs/fullchain.pem
  - YP_SMTP_TLS_KEY=/certs/privkey.pem
  
  # SMTP Relay
  - YP_SMTP_RELAY_HOST=smtp.sendgrid.net
  - YP_SMTP_RELAY_PORT=587
  - YP_SMTP_RELAY_USER=apikey
  - YP_SMTP_RELAY_PASSWORD=your-password
```

### Using .env File

Create `.env` file:

```bash
YP_HOSTNAME=mail.example.com
YP_SERVICE_TOKEN=your-token
SENDGRID_API_KEY=SG.xxxxxxxxxx
```

Reference in docker-compose:

```yaml
env_file:
  - .env
```

## Volumes

### Data Volume

```yaml
volumes:
  - yourpost-data:/var/lib/yourpost
```

This stores:
- `data/global.db` - Domain database
- `data/mailboxes/` - User mailbox databases

### Certificate Volume

```yaml
volumes:
  - certs:/etc/letsencrypt
```

Mount certificates for TLS:

```yaml
volumes:
  - ./certs:/certs:ro
```

### Configuration Volume

```yaml
volumes:
  - ./config:/etc/yourpost:ro
```

## Networking

### Bridge Network (Default)

```yaml
networks:
  default:
    driver: bridge
```

### Custom Network

```yaml
networks:
  mail-network:
    driver: bridge
    internal: false

services:
  yourpost:
    networks:
      - mail-network
```

### Host Network

```yaml
network_mode: host
```

**Warning**: All ports exposed on host!

### Port Mappings

| Service | Container Port | Host Port | Description |
|---------|---------------|-----------|-------------|
| SMTP | 25 | 25 | Incoming mail |
| Submission | 587 | 587 | Client submission |
| SMTPS | 465 | 465 | Secure SMTP |
| POP3 | 110 | 110 | Mail retrieval |
| POP3S | 995 | 995 | Secure POP3 |
| IMAP | 143 | 143 | Mail access |
| IMAPS | 993 | 993 | Secure IMAP |
| API | 9000 | 9000 | Public API |
| Service | 9001 | 9001 | Internal API |

## Production Deployment

### Reverse Proxy

Use Traefik or Nginx:

```yaml
# Traefik labels
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.yourpost.rule=Host(`mail.example.com`)"
  - "traefik.http.services.yourpost.loadbalancer.server.port=9000"
```

### Resource Limits

```yaml
services:
  yourpost:
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
```

### Health Checks

```yaml
services:
  yourpost:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

### Logging

```yaml
services:
  yourpost:
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

## Monitoring

### Docker Stats

```bash
# Monitor container
docker stats yourpost

# View logs
docker logs -f yourpost
```

### Prometheus Metrics

```yaml
# Add cAdvisor for container metrics
services:
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    ports:
      - "8080:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
```

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker logs yourpost

# Check port conflicts
docker port yourpost
sudo lsof -i :25

# Test without daemon mode
docker run --rm -it yourpost:latest
```

### Permission Denied

```bash
# Check volume permissions
docker exec -it yourpost ls -la /var/lib/yourpost

# Fix permissions
docker exec -it yourpost chown -R yourpost:yourpost /var/lib/yourpost
```

### Port Already in Use

```bash
# Check what's using the port
sudo lsof -i :25

# Stop conflicting service
sudo systemctl stop postfix

# Or use different ports
-p 2525:25
```

### Email Not Delivered

```bash
# Check relay configuration
docker exec -it yourpost env | grep RELAY

# Test connectivity
docker exec -it yourpost nc -zv smtp.sendgrid.net 587

# Check logs
docker logs yourpost | grep -i relay
```

### High Memory Usage

```bash
# Check memory limit
docker stats yourpost

# Reduce connection limit
docker exec -it yourpost env | grep MAX_CONNECTIONS

# Restart with limits
docker update --memory 512m yourpost
```

## Backup and Restore

### Backup

```bash
# Backup data volume
docker run --rm \
  -v yourpost-data:/data \
  -v $(pwd):/backup \
  alpine \
  tar czf /backup/yourpost-backup.tar.gz -C /data .
```

### Restore

```bash
# Stop container
docker stop yourpost

# Restore data
docker run --rm \
  -v yourpost-data:/data \
  -v $(pwd):/backup \
  alpine \
  tar xzf /backup/yourpost-backup.tar.gz -C /data

# Start container
docker start yourpost
```

## Best Practices

1. **Use named volumes** for persistent data
2. **Set resource limits** to prevent resource exhaustion
3. **Enable health checks** for automatic recovery
4. **Use secrets management** for sensitive data
5. **Regular backups** of mail data
6. **Monitor logs** for issues
7. **Keep image updated** with security patches
8. **Use non-root user** (already configured)
9. **Limit exposed ports** to only what's necessary
10. **Use TLS** for all connections

## Next Steps

- [Configuration Guide](CONFIGURATION.md)
- [SMTP Relay Setup](SMTP_RELAY.md)
- [API Documentation](API.md)
- [Cloudflare Integration](CLOUDFLARE.md)
- [Security Guide](SECURITY.md)