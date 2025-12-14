# Infrastructure Architecture - Quick Overview

## What We Built
Secure multi-service infrastructure with full encryption and network segmentation.

## Services Overview

| Service | Container/VM | Network | IP | Purpose |
|---------|-------------|---------|----|---------| 
| **nginx** | Docker | DMZ | 172.18.0.4 | HTTPS entry point (port 443) |
| **web01** | Docker | DMZ + Internal | 172.18.0.3, 172.19.0.5 | Node.js API with 2FA |
| **db01** | Docker | Internal | 172.19.0.3 | PostgreSQL with mTLS |
| **ca01** | Docker | Internal | 172.19.0.2 | PKI Certificate Authority |
| **fw01** | Docker | DMZ + Internal | 172.18.0.2, 172.19.0.4 | nftables firewall |
| **ssh01** | Kali VM | Host | 192.168.232.135 | SSH certificate auth |

## Network Topology

```
                    Internet
                       |
                   [nginx:443]
                       |
        ┌──────────────┴──────────────┐
        |         DMZ Network          |
        |      (172.18.0.0/16)        |
        |                              |
    nginx:172.18.0.4              web01:172.18.0.3
        |                              |
        └──────────────┬───────────────┘
                       |
                   [fw01] ← Firewall enforces rules
                       |
        ┌──────────────┴──────────────┐
        |      Internal Network        |
        |      (172.19.0.0/16)        |
        |                              |
    web01:172.19.0.5              db01:172.19.0.3
                                       
    ca01:172.19.0.2 ← Completely isolated
```

## Data Flow (End-to-End Example)

**User Registration with 2FA:**

1. **Browser → nginx (443)** 
   - Protocol: HTTPS/TLS 1.3
   - Encryption: ✅ (AES-256-GCM)
   
2. **nginx → web01 (3000)**
   - Protocol: HTTPS/TLS 1.3
   - Encryption: ✅ (TLS 1.3)
   - Firewall: ✅ Allowed (172.18.0.4 → 172.18.0.3:3000)
   
3. **web01 → db01 (5432)**
   - Protocol: PostgreSQL + mTLS
   - Encryption: ✅ (TLS + client cert)
   - Firewall: ✅ Allowed (172.19.0.5 → 172.19.0.3:5432)
   
4. **Response flows back** (encrypted)
   - db01 → web01 → nginx → Browser

**Total encryption layers: 3**
**Firewall checks: 2**

## Security Features Summary

### Encryption (Assignment 2 Table 1)
- ✅ **Web Traffic**: TLS 1.3 (Browser ↔ nginx ↔ web01)
- ✅ **Database Traffic**: PostgreSQL TLS + mTLS
- ✅ **SSH Access**: SSH with certificate authentication

### Authentication
- ✅ **Web Users**: Password + 2FA (TOTP)
- ✅ **Database**: SCRAM-SHA-256 + client certificates (mTLS)
- ✅ **SSH**: Certificate-based (Ed25519), no passwords

### Firewall (nftables)
- ✅ **Default Policy**: DENY everything
- ✅ **Allowed Traffic**: 
  - nginx → web01:3000
  - web01 → db01:5432
  - Internal → DNS:53
- ✅ **Blocked Traffic**:
  - DMZ → db01 (no direct database access)
  - ANY → ca01 (CA completely isolated)

### Configuration Integrity (SHA-256)
- ✅ **Firewall**: nftables.conf, entrypoint.sh
- ✅ **SSH**: sshd_config, ca.pub
- ✅ **PKI**: All CA keys and configs
- ⏳ **Web/DB**: Planned

### Session Limits
- ✅ **SSH**: MaxSessions 5 (Assignment 2 requirement)

## Certificate Hierarchy

### TLS Certificates (X.509, RSA 4096-bit)
```
Root CA (self-signed, 10 years)
    └── Intermediate CA (5 years)
            ├── web01.org.local (server cert, 1 year)
            ├── db01.org.local (server cert, 1 year)
            ├── ssh01.org.local (server cert, 1 year)
            └── web01-db-client (client cert, 1 year)
```

### SSH Certificates (Ed25519)
```
SSH CA (Ed25519)
    └── admin-key-cert.pub (user cert, 1 year)
    └── kali-key-cert.pub (user cert, 1 year)
```

## Assignment 2 Table 1 Compliance

| Service | Policy | Status |
|---------|--------|--------|
| **Web Server** | 2FA authentication | ✅ TOTP implemented |
| | Config integrity | ⏳ Planned |
| | Traffic encryption | ✅ TLS 1.3 |
| **Firewall** | Default deny + exceptions | ✅ nftables |
| | Config integrity | ✅ SHA-256 |
| **Database** | Authentication + authorization | ✅ mTLS + RBAC |
| | Config integrity | ⏳ Planned |
| | Traffic encryption | ✅ PostgreSQL TLS |
| **SSH** | Certificate authentication | ✅ Ed25519 certs |
| | Session limits | ✅ MaxSessions 5 |
| | Config integrity | ✅ SHA-256 |
| **PKI** | Secure access to certs | ✅ CA network isolated |
| | Config integrity | ✅ SHA-256 |
| | Certificate lifecycle | ✅ Issue + revoke |

## Quick Commands

### Check All Services Running
```bash
cd ~/Desktop/Projeto_CC
sudo docker-compose ps
```

### Test Complete Flow
```bash
# Health check
curl -k https://localhost/health

# User registration (tests full chain)
curl -k https://localhost/register -X POST \
  -H "Content-Type: application/json" \
  -d '{"username":"test","password":"Test123!"}'
```

### SSH Access from Windows
```powershell
cd "C:\Users\david\Desktop\PROJETO_CC\chaves ssh windows"
ssh -i admin-key -o CertificateFile=admin-key-cert.pub admin@192.168.232.135
```

### View Firewall Rules
```bash
sudo docker exec fw01 nft list ruleset
```

### Check Database Connection
```bash
sudo docker logs db01 | grep -i ssl
sudo docker logs web01 | grep -i "PostgreSQL"
```

## Important Implementation Details

### Static IPs Required
All containers have static IPs because firewall rules reference specific addresses. Without static IPs, rules break on container restart.

### Client Certificate Requirements
Database client certificates MUST have `extendedKeyUsage = clientAuth`, not `serverAuth`. PostgreSQL strictly enforces this.

### CA Network Isolation
ca01 has ALL network traffic blocked by firewall. Access only via `docker exec ca01 bash`. This prevents any remote attacks on the PKI.

### Line Ending Issues
Files created on Windows need Unix line endings (LF, not CRLF) for scripts to work in Linux containers. Use `dos2unix` to convert.

## File Locations

### Certificates
- TLS certs: `PKI/intermediate-ca/certs/`
- SSH certs: `PKI/ssh-ca/user-certs/`
- Windows SSH keys: `chaves ssh windows/`

### Configuration
- Web app: `WEB/app/server.js`
- Database: `DB/init-users.sql`, `postgres-entrypoint.sh`
- Firewall: `FW/nftables.conf`, `FW/entrypoint.sh`
- SSH: `SSH01/sshd_config`, `/etc/ssh/sshd_config` (on Kali)

### Documentation
- Web service: `WEB/README.md`
- Database: `DB/README.md`
- Firewall: `FW/README.md`
- SSH: `SSH01/README.md`
- This file: `README-ARCHITECTURE.md`

## Troubleshooting

### Service Won't Start
```bash
# Check logs
sudo docker logs <container_name>

# Check if ports are in use
sudo netstat -tulpn | grep <port>
```

### Certificate Issues
```bash
# Verify certificate
openssl x509 -in cert.pem -noout -text

# Check key usage
openssl x509 -in cert.pem -noout -ext extendedKeyUsage
```

### Firewall Blocking Traffic
```bash
# Check rules
sudo docker exec fw01 nft list ruleset

# Check container IPs match rules
sudo docker inspect <container_name> | grep IPAddress
```

### Can't SSH
```bash
# Check SSH config
grep -E "PasswordAuthentication|TrustedUserCAKeys" /etc/ssh/sshd_config

# Verify certificate
ssh-keygen -L -f admin-key-cert.pub

# Test with verbose
ssh -v -i admin-key admin@192.168.232.135
```

## What's Next (To Do)

- [ ] Implement config integrity for web01 and db01
- [ ] Extend RBAC in PostgreSQL (readonly vs app user)
- [ ] Add fail2ban/SIEM for login monitoring
- [ ] Performance measurements
- [ ] Create architecture diagram
