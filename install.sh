#!/bin/bash
# yourpost installation script
# Usage: sudo ./install.sh [prefix]
# Default prefix is /usr/local

set -e

PREFIX="${1:-/usr/local}"
BINARY_NAME="yourpost"
SERVICE_NAME="yourpost"
DATA_DIR="/var/lib/yourpost"
CONFIG_DIR="/etc/yourpost"
LOG_DIR="/var/log/yourpost"

echo "Installing yourpost to ${PREFIX}..."

# Build the project first
echo "Building yourpost..."
zig build -Doptimize=ReleaseFast

# Create directories
echo "Creating directories..."
mkdir -p "${PREFIX}/bin"
mkdir -p "${DATA_DIR}/data"
mkdir -p "${DATA_DIR}/mailboxes"
mkdir -p "${CONFIG_DIR}"
mkdir -p "${LOG_DIR}"
mkdir -p "${PREFIX}/lib/systemd/system"

# Install binary
echo "Installing binary..."
cp zig-out/bin/yourpost "${PREFIX}/bin/${BINARY_NAME}"
chmod +x "${PREFIX}/bin/${BINARY_NAME}"

# Install systemd service file
echo "Installing systemd service..."
if [ -f "yourpost.service" ]; then
    cp yourpost.service "${PREFIX}/lib/systemd/system/${SERVICE_NAME}.service"
    # Update paths in service file
    sed -i "s|/usr/local/bin/yourpost|${PREFIX}/bin/yourpost|g" "${PREFIX}/lib/systemd/system/${SERVICE_NAME}.service"
    sed -i "s|WorkingDirectory=/var/lib/yourpost|WorkingDirectory=${DATA_DIR}|g" "${PREFIX}/lib/systemd/system/${SERVICE_NAME}.service"
fi

# Install logrotate configuration
echo "Installing logrotate configuration..."
if [ -d "logrotate.d" ] && [ -f "logrotate.d/yourpost" ]; then
    mkdir -p /etc/logrotate.d
    cp logrotate.d/yourpost /etc/logrotate.d/${BINARY_NAME}
    sed -i "s|/var/log/yourpost|${LOG_DIR}|g" /etc/logrotate.d/${BINARY_NAME}
fi

# Create yourpost user if it doesn't exist
if ! id -u yourpost >/dev/null 2>&1; then
    echo "Creating yourpost user..."
    useradd -r -s /usr/sbin/nologin -d "${DATA_DIR}" yourpost
fi

# Set ownership
echo "Setting ownership..."
chown -R yourpost:yourpost "${DATA_DIR}"
chown -R yourpost:yourpost "${LOG_DIR}"
chown -R yourpost:yourpost "${CONFIG_DIR}"

# Reload systemd and enable service
if command -v systemctl >/dev/null 2>&1; then
    echo "Reloading systemd..."
    systemctl daemon-reload
    echo "To enable and start the service, run:"
    echo "  sudo systemctl enable ${SERVICE_NAME}"
    echo "  sudo systemctl start ${SERVICE_NAME}"
fi

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "1. Edit configuration in ${CONFIG_DIR} or set environment variables"
echo "2. Enable and start the service:"
echo "     sudo systemctl enable ${SERVICE_NAME}"
echo "     sudo systemctl start ${SERVICE_NAME}"
echo "3. Check status:"
echo "     sudo systemctl status ${SERVICE_NAME}"
echo ""
echo "Or run directly:"
echo "     ${PREFIX}/bin/yourpost"
