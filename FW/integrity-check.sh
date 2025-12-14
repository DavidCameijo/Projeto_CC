#!/bin/bash

# Firewall Configuration Integrity Check Script
# Verifies configuration files haven't been tampered with

set -e

CHECKSUM_FILE="/etc/firewall/config-checksums.sha256"
CONFIG_FILES=(
    "/etc/nftables.conf"
    "/entrypoint.sh"
)

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

generate_checksums() {
    echo -e "${YELLOW}[INTEGRITY] Generating checksums for firewall configuration files...${NC}"
    
    # Create checksum file
    > "$CHECKSUM_FILE"
    
    for file in "${CONFIG_FILES[@]}"; do
        if [ -f "$file" ]; then
            sha256sum "$file" >> "$CHECKSUM_FILE"
            echo -e "${GREEN}[INTEGRITY] ✓ Generated checksum for: $file${NC}"
        else
            echo -e "${RED}[INTEGRITY] ✗ File not found: $file${NC}"
        fi
    done
    
    chmod 600 "$CHECKSUM_FILE"
    echo -e "${GREEN}[INTEGRITY] Checksums saved to: $CHECKSUM_FILE${NC}"
}

verify_checksums() {
    echo -e "${YELLOW}[INTEGRITY] Verifying firewall configuration integrity...${NC}"
    
    if [ ! -f "$CHECKSUM_FILE" ]; then
        echo -e "${YELLOW}[INTEGRITY] No checksum file found. Generating initial checksums...${NC}"
        generate_checksums
        return 0
    fi
    
    # Verify checksums
    if sha256sum -c "$CHECKSUM_FILE" --quiet 2>/dev/null; then
        echo -e "${GREEN}[INTEGRITY] ✓ All configuration files verified successfully${NC}"
        return 0
    else
        echo -e "${RED}[INTEGRITY] ✗ INTEGRITY CHECK FAILED!${NC}"
        echo -e "${RED}[INTEGRITY] Configuration files have been modified!${NC}"
        
        # Show which files failed
        sha256sum -c "$CHECKSUM_FILE" 2>&1 | grep FAILED || true
        
        return 1
    fi
}

case "${1:-verify}" in
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
