#!/bin/bash

# Cleanup script for CIS-compliant RHEL AMI preparation
set -e

echo "Starting AMI cleanup process..."

# Remove SSH host keys
rm -f /etc/ssh/ssh_host_*

# Clear audit logs
if [ -f /var/log/audit/audit.log ]; then
    cat /dev/null > /var/log/audit/audit.log
fi

# Clear all logs
find /var/log -type f -exec truncate --size=0 {} \;

# Remove cloud-init data
rm -rf /var/lib/cloud/*

# Remove temporary files
rm -rf /tmp/*
rm -rf /var/tmp/*

# Clear bash history for all users
find /home -type f -name ".bash_history" -exec rm -f {} \;
rm -f /root/.bash_history

# Remove package manager cache
if command -v yum >/dev/null 2>&1; then
    yum clean all
    rm -rf /var/cache/yum
fi
if command -v dnf >/dev/null 2>&1; then
    dnf clean all
    rm -rf /var/cache/dnf
fi

# Remove machine-id
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

# Clear network configuration
rm -f /etc/udev/rules.d/70-persistent-net.rules
rm -f /var/lib/dhclient/*

# Ensure cloud-init will regenerate SSH host keys
cloud-init clean --logs

echo "Cleanup completed successfully" 