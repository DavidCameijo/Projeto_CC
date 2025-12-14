# Database Service (db01) - Quick Guide

## What It Does
PostgreSQL 15 database with TLS encryption and mutual TLS (mTLS) client authentication.

## Key Features
- **TLS Encryption**: All connections must use SSL/TLS
- **mTLS Authentication**: Clients must present valid certificates (not just passwords)
- **Network Isolation**: Only accessible from internal network (172.19.0.0/16)
- **Password Security**: Uses SCRAM-SHA-256 (not MD5)

## Certificates Used
1. **Server Certificate**: `db01.org.local-cert.pem` (database presents this)
2. **CA Certificate**: `ca.crt` (verifies client certificates)
3. **Client Certificates**: Each client (like web01) needs their own with `extendedKeyUsage = clientAuth`

## Network Configuration
- **Internal IP**: 172.19.0.3 (NOT accessible from DMZ)
- **Port**: 5432 (PostgreSQL default)
- **Firewall Rule**: Only web01 (172.19.0.5) can connect

## Database Schema
```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    totp_secret VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

## Files Structure
```
DB/
├── init-users.sql              # Database initialization script
├── postgres-entrypoint.sh      # Fixes certificate permissions
└── README.md                   # This file

postgres/                       # Mounted as volume
└── tls/
    ├── server.crt             # db01.org.local certificate
    ├── server.key             # Private key
    └── ca.crt                 # CA certificate
```

## Configuration Files

### postgresql.conf (via docker command)
```bash
postgres -c ssl=on \
         -c ssl_cert_file=/var/lib/postgresql/tls-fixed/server.crt \
         -c ssl_key_file=/var/lib/postgresql/tls-fixed/server.key \
         -c ssl_ca_file=/var/lib/postgresql/tls-fixed/ca.crt
```

### pg_hba.conf (client authentication)
```
# Require SSL + client certificate verification
hostssl all all 0.0.0.0/0 scram-sha-256 clientcert=verify-ca
```

## How to Test

### Check SSL is enabled
```bash
docker exec db01 psql -U admin -d securedb -c "SHOW ssl;"
# Should show: ssl | on
```

### Test connection from web01 (should work)
```bash
docker exec web01 node -e "require('./server.js')"
# Check logs for "PostgreSQL client certificate authentication enabled"
```

### Test connection without client cert (should fail)
```bash
psql "host=172.19.0.3 port=5432 dbname=securedb user=admin sslmode=require"
# Should fail: "certificate verify failed"
```

## Common Issues

### Issue: "certificate verify failed"
**Cause**: Client certificate missing or wrong extendedKeyUsage
**Solution**: 
1. Check certificate has `extendedKeyUsage = clientAuth`
2. Use `PKI/scripts/issue-client-cert.sh` to generate correct cert

### Issue: "could not accept SSL connection"
**Cause**: pg_hba.conf not configured for client certificates
**Solution**: 
```bash
docker exec db01 psql -U admin -c "SELECT pg_reload_conf();"
```

### Issue: "permission denied for table users"
**Cause**: User doesn't have proper privileges
**Solution**: Grant permissions:
```bash
docker exec db01 psql -U admin -d securedb \
  -c "GRANT ALL PRIVILEGES ON TABLE users TO admin;"
```

## Security Features (Assignment 2 Requirements)
- ✅ Encrypted traffic (TLS for all connections)
- ✅ Authentication (SCRAM-SHA-256 passwords + client certificates)
- ✅ Network isolation (internal network only)
- ⏳ RBAC (basic implementation, extended planned)
- ⏳ Config integrity checking (planned)

## RBAC (Role-Based Access Control)

### Current Implementation
```sql
-- Admin user with full privileges
CREATE USER admin WITH PASSWORD 'securepassword';
GRANT ALL PRIVILEGES ON DATABASE securedb TO admin;
```

### Planned Extended RBAC
```sql
-- Create roles
CREATE ROLE readonly_user;
CREATE ROLE app_user;

-- Grant specific privileges
GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly_user;
GRANT SELECT, INSERT, UPDATE ON TABLE users TO app_user;

-- Create users with roles
CREATE USER reader WITH PASSWORD 'pass1' IN ROLE readonly_user;
CREATE USER webapp WITH PASSWORD 'pass2' IN ROLE app_user;
```

## How It Fits in Architecture
```
web01 (172.19.0.5) → db01 (172.19.0.3):5432
[mTLS connection with client certificate]
```

Blocked connections:
- ❌ DMZ → db01 (firewall blocks direct access)
- ❌ Any container without valid client certificate
- ✅ Only web01 with proper certificate can connect
