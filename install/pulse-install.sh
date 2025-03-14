#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: rcourtman
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/rcourtman/pulse

# Initialize spinner variable for safety
export SPINNER_PID=""

source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Default values
APP="Pulse"
# NSAPP is now derived from APP via the variables function
var_tags="monitoring;proxmox;dashboard"
var_cpu="1"
var_ram="1024"
var_disk="2"
var_os="debian"
var_version="12"
var_unprivileged="1"
PULSE_VERSION="1.6.4"  # Current version to install

# App Output & Base Settings
header_info "$APP"
base_settings

# Core
variables
color
catch_errors

# Define application path
APPPATH="/opt/${NSAPP}"

start
build_container
description

# Set up locale immediately after container is created
setup_locale_environment

# Simplify the installation process with direct commands
msg_info "Setting up Pulse installation in the container"

# Install core dependencies directly
pct exec ${CTID} -- bash -c "apt-get update > /dev/null 2>&1"
pct exec ${CTID} -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y curl git ca-certificates gnupg sudo build-essential > /dev/null 2>&1"
msg_ok "Core dependencies installed"

# Installing Node.js
msg_info "Installing Node.js"
pct exec ${CTID} -- bash -c "curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1"
pct exec ${CTID} -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs > /dev/null 2>&1"
msg_ok "Node.js installed"

# Create application directory
msg_info "Creating application directory"
pct exec ${CTID} -- bash -c "mkdir -p /opt/${NSAPP}"
msg_ok "Application directory created"

# Download and extract pre-built release instead of cloning and build
msg_info "Downloading Pulse v${PULSE_VERSION} release"
pct exec ${CTID} -- bash -c "wget -qO- https://github.com/rcourtman/pulse/releases/download/v${PULSE_VERSION}/pulse-${PULSE_VERSION}.tar.gz | tar xz -C /opt/${NSAPP} --strip-components=1 > /dev/null 2>&1"
msg_ok "Release downloaded and extracted"

# Modify the mock service to use the compiled JavaScript
msg_info "Creating mock server service"
pct exec ${CTID} -- bash -c "cat > /etc/systemd/system/pulse-mock.service << 'EOFSVC'
[Unit]
Description=Pulse Mock Data Server
After=network.target
Before=pulse.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/${NSAPP}
Environment=NODE_ENV=production
Environment=MOCK_SERVER_PORT=7656
ExecStart=/usr/bin/node /opt/${NSAPP}/dist/mock/server.js
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSVC"
msg_ok "Mock server service created"

# Set up environment configuration
msg_info "Setting up environment configuration"
pct exec ${CTID} -- bash -c "cat > /opt/${NSAPP}/.env.example << 'EOFENV'
# Proxmox Node Configuration
# You can add up to 10 nodes by incrementing the number in PROXMOX_NODE_X_* variables

# Node 1 (Required)
PROXMOX_NODE_1_NAME=pve
PROXMOX_NODE_1_HOST=https://your-proxmox-ip:8006
PROXMOX_NODE_1_TOKEN_ID=root@pam!pulse
PROXMOX_NODE_1_TOKEN_SECRET=your-token-secret

# Optional: Node 2
# PROXMOX_NODE_2_NAME=pve2
# PROXMOX_NODE_2_HOST=https://your-second-proxmox-ip:8006
# PROXMOX_NODE_2_TOKEN_ID=root@pam!pulse
# PROXMOX_NODE_2_TOKEN_SECRET=your-second-token-secret

# Optional: Node 3
# PROXMOX_NODE_3_NAME=pve3
# PROXMOX_NODE_3_HOST=https://your-third-proxmox-ip:8006
# PROXMOX_NODE_3_TOKEN_ID=root@pam!pulse
# PROXMOX_NODE_3_TOKEN_SECRET=your-third-token-secret

# Mock Data Configuration
USE_MOCK_DATA=true
MOCK_DATA_ENABLED=true
MOCK_CLUSTER_ENABLED=true
MOCK_CLUSTER_NAME=Demo Cluster

# Server Configuration
PORT=7654
EOFENV"
msg_ok "Environment configuration created"

# Copy example environment file
msg_info "Setting up environment file"
pct exec ${CTID} -- bash -c "cp /opt/${NSAPP}/.env.example /opt/${NSAPP}/.env"
msg_ok "Environment file created"

# Set permissions
msg_info "Setting permissions"
pct exec ${CTID} -- bash -c "chown -R root:root /opt/${NSAPP}"
pct exec ${CTID} -- bash -c "chmod -R 755 /opt/${NSAPP}"
pct exec ${CTID} -- bash -c "chmod 600 /opt/${NSAPP}/.env"
msg_ok "Permissions set"

# Create systemd service
msg_info "Creating systemd service"
pct exec ${CTID} -- bash -c "cat > /etc/systemd/system/${NSAPP}.service << 'EOFSVC'
[Unit]
Description=Pulse Monitoring Dashboard
After=network.target pulse-mock.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/${NSAPP}
Environment=NODE_ENV=production
ExecStart=/usr/bin/node /opt/${NSAPP}/dist/server.js
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSVC"
msg_ok "Systemd service created"

# Enable and start services
msg_info "Starting services"
pct exec ${CTID} -- bash -c "systemctl enable pulse-mock.service"
pct exec ${CTID} -- bash -c "systemctl enable ${NSAPP}.service"
pct exec ${CTID} -- bash -c "systemctl start pulse-mock.service"
pct exec ${CTID} -- bash -c "systemctl start ${NSAPP}.service"
msg_ok "Services started"

# Save version
msg_info "Saving version information"
pct exec ${CTID} -- bash -c "echo '${PULSE_VERSION}' > /opt/${NSAPP}/${NSAPP}_version.txt"
msg_ok "Version information saved"

# Show access information
IP=$(hostname -I | awk '{print $1}')
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:7654${CL}"

# Clean up
msg_info "Cleaning up"
pct exec ${CTID} -- bash -c "apt-get clean > /dev/null 2>&1"
pct exec ${CTID} -- bash -c "rm -rf /var/lib/apt/lists/* > /dev/null 2>&1"
msg_ok "Cleanup completed"

# Final message
msg_ok "Installation completed successfully!"
