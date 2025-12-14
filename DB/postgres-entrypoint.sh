#!/bin/bash
set -e

echo "Setting up TLS files (workaround for HGFS permission issues)..."

# Copy TLS files from HGFS mount to a writable location inside the container
# (NOT back to the HGFS mount, which re-applies permissions)
mkdir -p /var/lib/postgresql/tls-fixed
cp /var/lib/postgresql/tls/server.key /var/lib/postgresql/tls-fixed/server.key
cp /var/lib/postgresql/tls/server.crt /var/lib/postgresql/tls-fixed/server.crt
cp /var/lib/postgresql/tls/ca.crt /var/lib/postgresql/tls-fixed/ca.crt

# Set correct ownership (postgres user) and permissions
chown postgres:postgres /var/lib/postgresql/tls-fixed/server.key
chown postgres:postgres /var/lib/postgresql/tls-fixed/server.crt
chown postgres:postgres /var/lib/postgresql/tls-fixed/ca.crt

chmod 600 /var/lib/postgresql/tls-fixed/server.key
chmod 644 /var/lib/postgresql/tls-fixed/server.crt
chmod 644 /var/lib/postgresql/tls-fixed/ca.crt

echo "TLS files prepared. Permissions:"
ls -la /var/lib/postgresql/tls-fixed/

# Create pg_hba.conf entry for client certificate authentication if not already present
PG_HBA="/var/lib/postgresql/data/pg_hba.conf"
if [ -f "$PG_HBA" ] && ! grep -q "cert" "$PG_HBA"; then
  echo "hostssl all web01-client.org.local samenet cert" >> "$PG_HBA"
  echo "Updated pg_hba.conf with mTLS requirements"
fi

echo "Starting PostgreSQL..."
echo "Note: Run integrity check after startup with:"
echo "  docker exec db01 /usr/local/bin/config-integrity.sh verify"
exec docker-entrypoint.sh "$@"
