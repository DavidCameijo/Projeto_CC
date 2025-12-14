#!/bin/sh
set -e

CERT_DIR="/etc/nginx/tls"
CERT_FILE="$CERT_DIR/server.crt"
KEY_FILE="$CERT_DIR/server.key"

mkdir -p "$CERT_DIR"

if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
  echo "[nginx] ERROR: TLS certificate/key missing at $CERT_FILE / $KEY_FILE" >&2
  exit 1
fi

echo "[nginx] Starting nginx with TLS"
exec nginx -g 'daemon off;'
