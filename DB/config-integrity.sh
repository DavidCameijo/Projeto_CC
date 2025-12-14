#!/bin/sh
set -e

OUT="/var/lib/postgresql/data/config-checksums.txt"
TARGETS="/var/lib/postgresql/data/postgresql.conf /var/lib/postgresql/data/pg_hba.conf /docker-entrypoint-initdb.d/init-users.sql"

echo "# SHA256 checksums for critical DB configs" > "$OUT"
for f in $TARGETS; do
  if [ -f "$f" ]; then
    sha256sum "$f" >> "$OUT"
  fi
done
chmod 640 "$OUT"
