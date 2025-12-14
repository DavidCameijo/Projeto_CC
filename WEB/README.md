# Web Service (web01) - Quick Guide

## What It Does
Node.js/Express web application with HTTPS and 2FA authentication.

## Key Features
- **HTTPS Server**: Runs on port 3000 with TLS 1.3
- **2FA Registration**: Users register with username/password + TOTP (Google Authenticator)
- **Database Connection**: Connects to PostgreSQL with mTLS (mutual TLS)
- **Dual Network**: Connected to DMZ (receives from nginx) and Internal (talks to database)

## Certificates Used
1. **Server Certificate**: `web01.org.local-cert.pem` (for HTTPS server)
2. **Client Certificate**: `web01-db-client-cert.pem` (for database authentication)
   - **Important**: Must have `extendedKeyUsage = clientAuth`

## Network Configuration
- **DMZ IP**: 172.18.0.3 (receives requests from nginx)
- **Internal IP**: 172.19.0.5 (connects to database)
- **Port**: 3000 (internal HTTPS)

## API Endpoints
- `GET /health` - Health check (no auth)
- `POST /register` - User registration with 2FA setup
- `POST /login` - User login with TOTP verification

## Files Structure
```
WEB/
├── Dockerfile              # Container image definition
├── app/
│   ├── server.js          # Main application code
│   ├── package.json       # Dependencies
│   └── certs/             # TLS certificates (mounted as volume)
│       ├── web01-cert.pem         # Server cert
│       ├── web01-key.pem          # Server key
│       ├── ca-chain.pem           # CA chain for verification
│       ├── web01-db-client.crt    # DB client cert
│       ├── web01-db-client.key    # DB client key
│       └── ca.crt                 # CA for DB verification
```

## How to Test
```bash
# Health check
curl -k https://localhost/health

# Register user (via nginx on port 443)
curl -k https://localhost/register -X POST \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","password":"Test123!"}'

# Response includes QR code for Google Authenticator setup
```

## Common Issues

### Issue: "certificate verify failed" when connecting to database
**Solution**: Client certificate must have `extendedKeyUsage = clientAuth`, not `serverAuth`

### Issue: Container can't find certificates
**Solution**: Check volume mount in docker-compose.yml: `./WEB/app/certs:/app/certs:ro`

### Issue: Database connection refused
**Solution**: Ensure database is running and firewall allows web01 (172.19.0.5) → db01 (172.19.0.3):5432

## Security Features (Assignment 2 Requirements)
- ✅ HTTPS encryption (TLS 1.3)
- ✅ 2FA authentication (TOTP)
- ✅ Encrypted database communication (mTLS)
- ⏳ Config integrity checking (planned)

## How It Fits in Architecture
```
Browser → nginx:443 (HTTPS) → web01:3000 (HTTPS) → db01:5432 (PostgreSQL mTLS)
          [DMZ Network]         [DMZ + Internal]      [Internal Network]
```

Firewall allows:
- nginx (172.18.0.4) → web01 (172.18.0.3):3000
- web01 (172.19.0.5) → db01 (172.19.0.3):5432
