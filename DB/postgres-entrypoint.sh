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

# Enforce TLS (hostssl) + client certificate verification in pg_hba.conf
PG_HBA="/var/lib/postgresql/data/pg_hba.conf"
SSL_RULE_V4="hostssl all all 0.0.0.0/0 scram-sha-256 clientcert=verify-ca"
SSL_RULE_V6="hostssl all all ::0/0 scram-sha-256 clientcert=verify-ca"

if [ -f "$PG_HBA" ]; then
  # Prepend the strict rules so they match before any permissive host entries
  if ! grep -Fx "$SSL_RULE_V4" "$PG_HBA"; then
    TMP_HBA=$(mktemp)
    {
      echo "# Enforce TLS + client cert for all remote connections"
      echo "$SSL_RULE_V4"
      echo "$SSL_RULE_V6"
    } | cat - "$PG_HBA" > "$TMP_HBA"
    mv "$TMP_HBA" "$PG_HBA"
    echo "Updated pg_hba.conf to require TLS and client certificates"
  fi

  # Comment out permissive host lines (including loopback) that bypass SSL
  sed -i 's/^[[:space:]]*host[[:space:]]\+all[[:space:]]\+all[[:space:]]\+all/# &/' "$PG_HBA" || true
  sed -i 's/^[[:space:]]*host[[:space:]]\+all[[:space:]]\+all[[:space:]]\+0\.0\.0\.0\/0/# &/' "$PG_HBA" || true
  sed -i 's/^[[:space:]]*host[[:space:]]\+all[[:space:]]\+all[[:space:]]\+::\/0/# &/' "$PG_HBA" || true
  sed -i 's/^[[:space:]]*host[[:space:]]\+all[[:space:]]\+all[[:space:]]\+127\.0\.0\.1\/32/# &/' "$PG_HBA" || true
  sed -i 's/^[[:space:]]*host[[:space:]]\+all[[:space:]]\+all[[:space:]]\+::1\/128/# &/' "$PG_HBA" || true
fi

echo "Starting PostgreSQL..."
echo "Note: Run integrity check after startup with:"
echo "  docker exec db01 /usr/local/bin/config-integrity.sh verify"
exec docker-entrypoint.sh "$@"
