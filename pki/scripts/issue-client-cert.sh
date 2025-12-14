#!/bin/bash

# Script to issue TLS client certificates for database mTLS authentication
# Assignment 2 - PKI Infrastructure
# Usage: ./scripts/issue-client-cert.sh <client_name>
# Example: ./scripts/issue-client-cert.sh web01-db-client

set -e  # Stop on error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Base directory (where this script is)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKI_DIR="$(dirname "$SCRIPT_DIR")"
INTERMEDIATE_CA_DIR="$PKI_DIR/intermediate-ca"

# Check arguments
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: Client name not provided!${NC}"
    echo ""
    echo "Usage: $0 <client_name>"
    echo "Example: $0 web01-db-client"
    exit 1
fi

CLIENT_NAME=$1

# Validate client name
if [[ ! "$CLIENT_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]*[a-zA-Z0-9]$ ]]; then
    echo -e "${RED}Error: Invalid client name: $CLIENT_NAME${NC}"
    exit 1
fi

echo -e "${GREEN}=== Issuing TLS Client Certificate ===${NC}"
echo "Client name: $CLIENT_NAME"
echo "Certificate purpose: TLS Client Authentication (mTLS)"
echo "Intermediate CA: $INTERMEDIATE_CA_DIR"
echo ""

# Check if Intermediate CA exists
if [ ! -f "$INTERMEDIATE_CA_DIR/private/intermediate-ca.key" ] || [ ! -f "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt" ]; then
    echo -e "${RED}Error: Intermediate CA not found!${NC}"
    echo "Run first: ./scripts/generate-intermediate-ca.sh"
    exit 1
fi

# Output file names
KEY_FILE="${CLIENT_NAME}-key.pem"
CERT_FILE="${CLIENT_NAME}-cert.pem"
CSR_FILE="${CLIENT_NAME}.csr"
CHAIN_FILE="${CLIENT_NAME}-chain.pem"

# Check if files already exist
if [ -f "$PKI_DIR/$KEY_FILE" ] || [ -f "$PKI_DIR/$CERT_FILE" ]; then
    echo -e "${YELLOW}⚠ Warning: Files already exist for $CLIENT_NAME!${NC}"
    read -p "Do you want to overwrite? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Operation cancelled.${NC}"
        exit 0
    fi
    rm -f "$PKI_DIR/$KEY_FILE" "$PKI_DIR/$CERT_FILE" "$PKI_DIR/$CSR_FILE" "$PKI_DIR/$CHAIN_FILE"
fi

# Change to PKI directory
cd "$PKI_DIR"

echo -e "${YELLOW}Step 1: Generating 4096-bit RSA private key...${NC}"
openssl genrsa -out "$KEY_FILE" 4096
chmod 600 "$KEY_FILE"  # Restrictive permissions
echo -e "${GREEN}  ✓ Private key created: $KEY_FILE${NC}"
echo ""

echo -e "${YELLOW}Step 2: Creating Certificate Signing Request (CSR)...${NC}"
# Create CSR with simple CN (no SAN needed for client certs)
openssl req -new \
    -key "$KEY_FILE" \
    -out "$CSR_FILE" \
    -subj "/CN=$CLIENT_NAME" \
    -sha256

echo -e "${GREEN}  ✓ CSR created: $CSR_FILE${NC}"
echo ""

echo -e "${YELLOW}Step 3: Signing CSR with Intermediate CA...${NC}"
echo -e "${BLUE}  Validity: 1 year${NC}"
echo -e "${BLUE}  Algorithm: SHA-256${NC}"
echo -e "${BLUE}  Extended Key Usage: TLS Client Authentication${NC}"
echo ""

# Change to intermediate-ca to sign
cd "$INTERMEDIATE_CA_DIR"

# Create temporary extension config file for client authentication
TEMP_EXT_CONFIG=$(mktemp)
cat > "$TEMP_EXT_CONFIG" << EOF
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

# Sign the certificate
openssl ca -config openssl.cnf \
    -days 365 \
    -md sha256 \
    -in "$PKI_DIR/$CSR_FILE" \
    -out "$PKI_DIR/$CERT_FILE" \
    -extfile "$TEMP_EXT_CONFIG" \
    -batch

rm -f "$TEMP_EXT_CONFIG"
chmod 644 "$PKI_DIR/$CERT_FILE"
echo -e "${GREEN}  ✓ Certificate created: $CERT_FILE${NC}"
echo ""

# Return to PKI directory
cd "$PKI_DIR"

echo -e "${YELLOW}Step 4: Creating certificate chain...${NC}"
cat "$CERT_FILE" "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt" > "$CHAIN_FILE"
chmod 644 "$CHAIN_FILE"
echo -e "${GREEN}  ✓ Chain created: $CHAIN_FILE${NC}"
echo ""

echo -e "${YELLOW}Step 5: Verifying certificate...${NC}"
# Verify the certificate
openssl verify -CAfile "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt" "$CERT_FILE" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}  ✓ Certificate verified successfully${NC}"
else
    echo -e "${RED}  ✗ Certificate verification failed${NC}"
    exit 1
fi
echo ""

echo -e "${GREEN}=== Client Certificate Issued Successfully ===${NC}"
echo ""
echo -e "${BLUE}Generated files:${NC}"
echo "  Private Key:  $KEY_FILE"
echo "  Certificate:  $CERT_FILE"
echo "  Chain:        $CHAIN_FILE"
echo "  CSR:          $CSR_FILE (can be deleted)"
echo ""
echo -e "${YELLOW}Certificate details:${NC}"
openssl x509 -in "$CERT_FILE" -noout -subject -issuer -dates -ext extendedKeyUsage
echo ""
echo -e "${YELLOW}Usage for PostgreSQL mTLS:${NC}"
echo "  Client cert: $CERT_FILE"
echo "  Client key:  $KEY_FILE"
echo "  CA cert:     $INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt"
echo ""
echo -e "${GREEN}Done!${NC}"
