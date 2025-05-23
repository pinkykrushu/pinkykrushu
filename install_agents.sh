#!/bin/bash

# Set error handling
set -e
set -o pipefail

# Function for logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if a package is installed
is_package_installed() {
    rpm -q "$1" >/dev/null 2>&1
}

# Function to safely remove a package if it exists
remove_package() {
    local package=$1
    if is_package_installed "$package"; then
        log "Removing existing package: $package"
        rpm -e --nodeps "$package" || {
            log "Failed to remove package: $package"
            return 1
        }
    else
        log "Package not found: $package"
    fi
}

# Clean up existing installations and logs
log "Cleaning up existing installations..."

# Remove Tanium Client
if [ -d "/opt/Tanium" ]; then
    systemctl stop taniumclient >/dev/null 2>&1 || true
    systemctl disable taniumclient >/dev/null 2>&1 || true
    remove_package "taniumclient"
    rm -rf /opt/Tanium
    rm -f /etc/systemd/system/taniumclient.service
    rm -f /etc/init.d/taniumclient
fi

# Remove CrowdStrike Falcon
if [ -d "/opt/CrowdStrike" ]; then
    systemctl stop falcon-sensor >/dev/null 2>&1 || true
    systemctl disable falcon-sensor >/dev/null 2>&1 || true
    /opt/CrowdStrike/falconctl -d >/dev/null 2>&1 || true
    remove_package "falcon-sensor"
    rm -rf /opt/CrowdStrike
    rm -f /etc/systemd/system/falcon-sensor.service
fi

# Remove Qualys Cloud Agent
if [ -d "/usr/local/qualys" ]; then
    systemctl stop qualys-cloud-agent >/dev/null 2>&1 || true
    systemctl disable qualys-cloud-agent >/dev/null 2>&1 || true
    /usr/local/qualys/cloud-agent/bin/qualys-cloud-agent.sh deactivate >/dev/null 2>&1 || true
    remove_package "qualys-cloud-agent"
    rm -rf /usr/local/qualys
    rm -f /etc/systemd/system/qualys-cloud-agent.service
fi

# Clean up logs
log "Cleaning up log files..."
rm -f /var/log/agent_installation.log
rm -f /var/log/tanium/*
rm -f /var/log/crowdstrike/*
rm -f /var/log/qualys/*

# Reload systemd to recognize removed services
systemctl daemon-reload

# Set up new log file
LOGFILE="/var/log/agent_installation.log"
exec 1> >(tee -a "$LOGFILE") 2>&1

echo "Starting fresh security agents installation at $(date)"

# Install dependencies
log "Installing dependencies..."
dnf install -y curl wget dmidecode

# Tanium Client Installation
log "Installing Tanium Client..."
TANIUM_VERSION="7.4.7.1094"

mkdir -p /opt/Tanium/TaniumClient
wget -q "https://your-repository/tanium/TaniumClient-${TANIUM_VERSION}-1.rhe8.x86_64.rpm" -O /tmp/taniumclient.rpm
rpm -Uvh /tmp/taniumclient.rpm

# Reset Tanium Client settings
log "Resetting Tanium Client settings..."
rm -f /opt/Tanium/TaniumClient/TaniumClient.ini
rm -rf /opt/Tanium/TaniumClient/Downloads/*
rm -rf /opt/Tanium/TaniumClient/Tools/*
rm -f /opt/Tanium/TaniumClient/*.bak
systemctl disable taniumclient

# CrowdStrike Falcon Installation
log "Installing CrowdStrike Falcon..."
FALCON_VERSION="6.45.0-14104"

wget -q "https://your-repository/crowdstrike/falcon-sensor-${FALCON_VERSION}.el8.x86_64.rpm" -O /tmp/falcon-sensor.rpm
rpm -Uvh /tmp/falcon-sensor.rpm

# Reset CrowdStrike settings
log "Resetting CrowdStrike settings..."
/opt/CrowdStrike/falconctl -d
rm -f /opt/CrowdStrike/falconctl.db
systemctl disable falcon-sensor

# Qualys Cloud Agent Installation
log "Installing Qualys Cloud Agent..."
QUALYS_VERSION="4.7.0.88"

wget -q "https://your-repository/qualys/QualysCloudAgent-${QUALYS_VERSION}.x86_64.rpm" -O /tmp/qualys-agent.rpm
rpm -Uvh /tmp/qualys-agent.rpm

# Reset Qualys settings
log "Resetting Qualys settings..."
/usr/local/qualys/cloud-agent/bin/qualys-cloud-agent.sh deactivate
rm -f /usr/local/qualys/cloud-agent/configuration/qualys-cloud-agent.conf
systemctl disable qualys-cloud-agent

# Cleanup installation files
log "Cleaning up installation files..."
rm -f /tmp/taniumclient.rpm
rm -f /tmp/falcon-sensor.rpm
rm -f /tmp/qualys-agent.rpm

log "Security agents installation completed at $(date)"

# Create marker file to indicate installation
touch /opt/security_agents_installed 