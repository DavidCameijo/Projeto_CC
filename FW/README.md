# Firewall Service (fw01) - Quick Guide

## What It Does
Network firewall using nftables that enforces network segmentation and access control between DMZ and internal networks.

## Key Features
- **Default DENY Policy**: Everything blocked unless explicitly allowed
- **Network Segmentation**: Separates DMZ (172.18.0.0/16) from Internal (172.19.0.0/16)
- **Specific IP Rules**: Uses exact IPs instead of ranges for precision
- **Stateful Firewall**: Tracks connections (ct state established,related)
- **Config Integrity**: SHA-256 checksums verify configuration files

## Network Interfaces
- **DMZ IP**: 172.18.0.2 (connected to public-facing network)
- **Internal IP**: 172.19.0.4 (connected to backend network)
- **Privileged Mode**: Required for NET_ADMIN capability

## Firewall Rules

### Allowed Traffic (FORWARD chain)
```
nginx01 (172.18.0.4) → web01 (172.18.0.3):3000     # HTTPS API
web01 (172.19.0.5) → db01 (172.19.0.3):5432       # PostgreSQL mTLS
Internal network → ANY:53 (UDP/TCP)                # DNS queries
```

### Blocked Traffic (FORWARD chain)
```
DMZ (172.18.0.0/16) → db01:5432                   # Direct DB access DENIED
ANY → ca01 (172.19.0.2)                           # CA completely isolated
Everything else                                    # Default DENY
```

### Management Access (INPUT chain)
```
ANY → fw01:22                                      # SSH management
Loopback, ICMP                                     # System functions
```

## Files Structure
```
FW/
├── Dockerfile              # Debian 12 + nftables
├── entrypoint.sh          # Startup script (loads rules)
├── nftables.conf          # Firewall rules configuration
├── integrity-check.sh     # SHA-256 verification script
└── rules.d/               # Documentation
    ├── dmz-rules.txt
    └── internal-rules.txt
```

## nftables Configuration Example

### FORWARD Chain (main security rules)
```nftables
chain forward {
    type filter hook forward priority 0; policy drop;
    
    # Allow established connections
    ct state established,related accept
    
    # Rule 1: nginx → web01 API
    ip saddr 172.18.0.4 ip daddr 172.18.0.3 tcp dport 3000 ct state new accept
    
    # Rule 2: web01 → db01 PostgreSQL
    ip saddr 172.19.0.5 ip daddr 172.19.0.3 tcp dport 5432 ct state new accept
    
    # Block DMZ → database
    ip saddr 172.18.0.0/16 ip daddr 172.19.0.3 tcp dport 5432 
        log prefix "[FW-DENY-DMZ-DB] " drop
    
    # Block ALL access to CA
    ip daddr 172.19.0.2 log prefix "[FW-DENY-CA-ACCESS] " drop
    
    # Default deny (log drops)
    log prefix "[FW-DENY-FORWARD] " drop
}
```

## How to Use

### View loaded rules
```bash
docker exec fw01 nft list ruleset
```

### Check integrity
```bash
docker exec fw01 /usr/local/bin/integrity-check.sh verify
```

### View firewall logs
```bash
# Check host kernel logs (container logs isolated)
sudo dmesg | grep "FW-DENY"

# Or check packet counters
docker exec fw01 nft list ruleset -a
```

### Restart firewall
```bash
docker-compose restart fw01
```

## Static IP Requirements

**Critical**: Firewall rules use specific IPs. Containers must have static IPs or rules break on restart.

### Static IP Configuration (docker-compose.yml)
```yaml
networks:
  dmz-net:
    ipam:
      config:
        - subnet: 172.18.0.0/16
  internal-net:
    ipam:
      config:
        - subnet: 172.19.0.0/16

services:
  nginx:
    networks:
      dmz-net:
        ipv4_address: 172.18.0.4
  web01:
    networks:
      dmz-net:
        ipv4_address: 172.18.0.3
      internal-net:
        ipv4_address: 172.19.0.5
  # ... etc
```

## Testing Firewall

### Test allowed traffic (should work)
```bash
# nginx → web01
curl -k https://localhost/health

# web01 → db01 (via registration)
curl -k https://localhost/register -X POST \
  -H "Content-Type: application/json" \
  -d '{"username":"test","password":"Test123!"}'
```

### Test blocked traffic (should fail)
```bash
# Try to access CA from web01
docker exec web01 timeout 2 curl http://172.19.0.2:80
# Result: Connection refused (blocked by firewall)
```

## Configuration Integrity

### How It Works
1. On first run: Generate SHA-256 checksums of `/etc/nftables.conf` and `/entrypoint.sh`
2. Store checksums in `/etc/firewall/config-checksums.sha256`
3. On subsequent runs: Verify files against stored checksums
4. If mismatch: Container startup FAILS

### Manual Integrity Check
```bash
# Verify checksums
docker exec fw01 /usr/local/bin/integrity-check.sh verify

# Regenerate checksums (after legitimate changes)
docker exec fw01 /usr/local/bin/integrity-check.sh generate
```

## Common Issues

### Issue: Rules not loading
**Cause**: Windows line endings (CRLF) in configuration files
**Solution**: Convert to Unix (LF) format
```bash
dos2unix FW/nftables.conf
dos2unix FW/entrypoint.sh
dos2unix FW/integrity-check.sh
```

### Issue: IP forwarding not working
**Cause**: Missing privileged mode or NET_ADMIN capability
**Solution**: Check docker-compose.yml has:
```yaml
fw01:
  privileged: true
  cap_add:
    - NET_ADMIN
    - NET_RAW
```

### Issue: Containers can't communicate after firewall deployment
**Cause**: Static IPs not configured, rules reference wrong IPs
**Solution**: Check all containers have static IPs matching firewall rules

## Security Features (Assignment 2 Requirements)
- ✅ Default DENY policy (policy drop)
- ✅ Allowed exceptions (TCP/443→3000, TCP/5432, TCP/22, UDP/TCP 53)
- ✅ Config integrity checking (SHA-256)
- ✅ Logging (all drops logged with prefixes)

## Why Specific IPs Instead of Ranges?
- **More secure**: Only specific container can access specific service
- **Principle of least privilege**: Minimal access granted
- **Prevents lateral movement**: Unauthorized containers in same network blocked
- **Requires**: Static IP assignments to prevent rules breaking on restart

## CA Isolation Explained
```
ca01 (172.19.0.2) - PKI Certificate Authority

Firewall blocks ALL traffic to ca01:
❌ web01 → ca01 (blocked)
❌ db01 → ca01 (blocked)
❌ DMZ → ca01 (blocked)

Access method: docker exec ca01 bash (out-of-band access)
```

**Why?** CA is trust root of entire infrastructure. Network isolation eliminates remote attack surface.
