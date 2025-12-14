#!/bin/bash

set -e

echo "[FIREWALL] Starting firewall service..."

# Enable IP forwarding at runtime
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1

echo "[FIREWALL] IP forwarding enabled"

# Run integrity check on configuration files
echo "[FIREWALL] Running integrity check..."
/usr/local/bin/integrity-check.sh verify || {
    echo "[FIREWALL] ERROR: Integrity check failed!"
    exit 1
}

# Load nftables rules
echo "[FIREWALL] Loading nftables rules..."
if nft -f /etc/nftables.conf; then
    echo "[FIREWALL] ✓ nftables rules loaded successfully"
else
    echo "[FIREWALL] ERROR: Failed to load nftables rules"
    exit 1
fi

# Display loaded rules
echo "[FIREWALL] Current ruleset:"
nft list ruleset

echo "[FIREWALL] Firewall initialized successfully"
echo "[FIREWALL] Policy: Default DENY, explicit ALLOW"

# Execute the main command
exec "$@"
