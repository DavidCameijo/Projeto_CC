#!/bin/bash
# Database Configuration Integrity Check Script
# Assignment 2 - Configuration file integrity control

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

CHECKSUM_FILE="/var/lib/postgresql/config-checksums.sha256"
CONFIG_FILES=(
    "/var/lib/postgresql/data/postgresql.conf"
    "/var/lib/postgresql/data/pg_hba.conf"
    "/docker-entrypoint-initdb.d/init-users.sql"
)

echo -e "${YELLOW}[DB-INTEGRITY]${NC} Configuration integrity check..."

generate_checksums() {
    echo -e "${YELLOW}[DB-INTEGRITY]${NC} Generating checksums for database configuration files..."
    > "$CHECKSUM_FILE"
    
    for file in "${CONFIG_FILES[@]}"; do
        if [ -f "$file" ]; then
            sha256sum "$file" >> "$CHECKSUM_FILE"
            echo -e "${GREEN}[DB-INTEGRITY]${NC} ✓ Generated checksum for: $file"
        else
            echo -e "${YELLOW}[DB-INTEGRITY]${NC} ⚠ File not found: $file"
        fi
    done
    
    chmod 600 "$CHECKSUM_FILE"
    echo -e "${GREEN}[DB-INTEGRITY]${NC} Checksums saved to: $CHECKSUM_FILE"
}

verify_checksums() {
    if [ ! -f "$CHECKSUM_FILE" ]; then
        echo -e "${YELLOW}[DB-INTEGRITY]${NC} No checksum file found. Generating initial checksums..."
        generate_checksums
        return 0
    fi
    
    echo -e "${YELLOW}[DB-INTEGRITY]${NC} Verifying database configuration integrity..."
    
    if sha256sum -c "$CHECKSUM_FILE" --quiet 2>/dev/null; then
        echo -e "${GREEN}[DB-INTEGRITY]${NC} ✓ All configuration files verified successfully"
        return 0
    else
        echo -e "${RED}[DB-INTEGRITY]${NC} ✗ INTEGRITY CHECK FAILED!"
        echo -e "${RED}[DB-INTEGRITY]${NC} One or more configuration files have been modified"
        echo -e "${YELLOW}[DB-INTEGRITY]${NC} Expected checksums:"
        cat "$CHECKSUM_FILE"
        echo -e "${YELLOW}[DB-INTEGRITY]${NC} Current checksums:"
        for file in "${CONFIG_FILES[@]}"; do
            if [ -f "$file" ]; then
                sha256sum "$file"
            fi
        done
        echo -e "${YELLOW}[DB-INTEGRITY]${NC} Note: To regenerate checksums after legitimate changes, run:"
        echo -e "${YELLOW}[DB-INTEGRITY]${NC}   docker exec db01 /usr/local/bin/config-integrity.sh generate"
        exit 1
    fi
}

case "$1" in
    generate)
        generate_checksums
        ;;
    verify)
        verify_checksums
        ;;
    *)
        echo "Usage: $0 {generate|verify}"
        exit 1
        ;;
esac
