#!/bin/bash

# Script template para emitir certificados TLS de servidor com suporte SAN
# Assignment 2 - PKI Infrastructure
# Uso: ./scripts/issue-server-cert.sh <hostname>
# Exemplo: ./scripts/issue-server-cert.sh web01.org.local

set -e  # Parar se houver erro

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Diretório base (onde está este script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKI_DIR="$(dirname "$SCRIPT_DIR")"
INTERMEDIATE_CA_DIR="$PKI_DIR/intermediate-ca"

# Verificar argumentos
if [ $# -eq 0 ]; then
    echo -e "${RED}Erro: Hostname não fornecido!${NC}"
    echo ""
    echo "Uso: $0 <hostname>"
    echo "Exemplo: $0 web01.org.local"
    exit 1
fi

HOSTNAME=$1

# Validar hostname básico
if [[ ! "$HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]*[a-zA-Z0-9]$ ]]; then
    echo -e "${RED}Erro: Hostname inválido: $HOSTNAME${NC}"
    exit 1
fi

echo -e "${GREEN}=== Emissão de Certificado TLS para Servidor ===${NC}"
echo "Hostname: $HOSTNAME"
echo "Diretório Intermediate CA: $INTERMEDIATE_CA_DIR"
echo ""

# Verificar se Intermediate CA existe
if [ ! -f "$INTERMEDIATE_CA_DIR/private/intermediate-ca.key" ] || [ ! -f "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt" ]; then
    echo -e "${RED}Erro: Intermediate CA não encontrada!${NC}"
    echo "Execute primeiro: ./scripts/generate-intermediate-ca.sh"
    exit 1
fi

# Nomes dos ficheiros de saída
KEY_FILE="${HOSTNAME}-key.pem"
CERT_FILE="${HOSTNAME}-cert.pem"
CSR_FILE="${HOSTNAME}.csr"
CHAIN_FILE="${HOSTNAME}-chain.pem"

# Verificar se já existem ficheiros
if [ -f "$KEY_FILE" ] || [ -f "$CERT_FILE" ]; then
    echo -e "${YELLOW}⚠ Atenção: Ficheiros já existem para $HOSTNAME!${NC}"
    read -p "Deseja sobrescrever? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo -e "${BLUE}Operação cancelada.${NC}"
        exit 0
    fi
    rm -f "$KEY_FILE" "$CERT_FILE" "$CSR_FILE" "$CHAIN_FILE"
fi

# Mudar para o diretório PKI
cd "$PKI_DIR"

echo -e "${YELLOW}Passo 1: Gerar chave privada RSA 4096 bits...${NC}"
openssl genrsa -out "$KEY_FILE" 4096
chmod 600 "$KEY_FILE"  # Permissões restritivas
echo -e "${GREEN}  ✓ Chave privada criada: $KEY_FILE${NC}"
echo ""

echo -e "${YELLOW}Passo 2: Criar Certificate Signing Request (CSR) com SAN...${NC}"

# Criar ficheiro temporário de configuração com SAN dinâmico
TEMP_CONFIG=$(mktemp)
cat > "$TEMP_CONFIG" << EOF
[ req ]
default_bits = 4096
prompt = no
default_md = sha256
distinguished_name = req_distinguished_name
req_extensions = v3_req
string_mask = utf8only

[ req_distinguished_name ]
CN = $HOSTNAME

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = $HOSTNAME
EOF

openssl req -new \
    -key "$KEY_FILE" \
    -out "$CSR_FILE" \
    -config "$TEMP_CONFIG" \
    -sha256

rm -f "$TEMP_CONFIG"
echo -e "${GREEN}  ✓ CSR criado: $CSR_FILE${NC}"
echo ""

echo -e "${YELLOW}Passo 3: Assinar CSR com Intermediate CA...${NC}"
echo -e "${BLUE}  Validade: 1 ano${NC}"
echo -e "${BLUE}  Algoritmo: SHA-256${NC}"
echo ""

# Mudar para intermediate-ca para assinar
cd "$INTERMEDIATE_CA_DIR"

# Criar ficheiro temporário de configuração com SAN para extensões
TEMP_EXT_CONFIG=$(mktemp)
cat > "$TEMP_EXT_CONFIG" << EOF
[ v3_server ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
crlDistributionPoints = URI:file://../intermediate-ca/crl/intermediate-ca.crl.pem
authorityInfoAccess = OCSP;URI:http://ca01.org.local/ocsp,caIssuers;URI:file://../intermediate-ca/certs/intermediate-ca.crt

[ alt_names ]
DNS.1 = $HOSTNAME
EOF

# Assinar o certificado
openssl ca -config openssl.cnf \
    -extensions v3_server \
    -days 365 \
    -md sha256 \
    -in "$PKI_DIR/$CSR_FILE" \
    -out "$PKI_DIR/$CERT_FILE" \
    -batch \
    -notext \
    -extfile "$TEMP_EXT_CONFIG"

rm -f "$TEMP_EXT_CONFIG"
chmod 644 "$PKI_DIR/$CERT_FILE"
echo -e "${GREEN}  ✓ Certificado criado: $CERT_FILE${NC}"
echo ""

# Voltar para PKI_DIR
cd "$PKI_DIR"

echo -e "${YELLOW}Passo 4: Criar cadeia de certificados...${NC}"
cat "$CERT_FILE" "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt" > "$CHAIN_FILE"
chmod 644 "$CHAIN_FILE"
echo -e "${GREEN}  ✓ Cadeia criada: $CHAIN_FILE${NC}"
echo ""

echo -e "${YELLOW}Passo 5: Verificar certificado gerado...${NC}"
echo ""

# Verificar cadeia de certificados
if openssl verify -CAfile "$INTERMEDIATE_CA_DIR/../root-ca/certs/root-ca.crt" \
                  -untrusted "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt" \
                  "$CERT_FILE" > /dev/null 2>&1; then
    echo -e "${GREEN}  ✓ Cadeia de certificados válida${NC}"
else
    echo -e "${RED}  ✗ Erro: Cadeia de certificados inválida!${NC}"
    openssl verify -CAfile "$INTERMEDIATE_CA_DIR/../root-ca/certs/root-ca.crt" \
                   -untrusted "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt" \
                   "$CERT_FILE"
    exit 1
fi

# Verificar SAN
SAN_CHECK=$(openssl x509 -in "$CERT_FILE" -noout -text | grep -A1 "Subject Alternative Name" | grep "DNS:$HOSTNAME")
if [ -n "$SAN_CHECK" ]; then
    echo -e "${GREEN}  ✓ SAN correto: DNS:$HOSTNAME${NC}"
else
    echo -e "${YELLOW}  ⚠ SAN não encontrado no certificado${NC}"
fi

# Mostrar informações do certificado
echo ""
echo -e "${BLUE}Informações do certificado:${NC}"
openssl x509 -in "$CERT_FILE" -noout -subject -issuer -dates | sed 's/^/  /'

echo ""
echo -e "${GREEN}=== Certificado gerado com sucesso! ===${NC}"
echo ""
echo "Ficheiros criados:"
echo "  - $KEY_FILE (chave privada - guardar em segurança!)"
echo "  - $CERT_FILE (certificado)"
echo "  - $CHAIN_FILE (cadeia: certificado + Intermediate CA)"
echo "  - $CSR_FILE (CSR - pode ser removido)"
echo ""
echo "Para usar no servidor:"
echo "  - Chave: $KEY_FILE"
echo "  - Certificado: $CERT_FILE ou $CHAIN_FILE (recomendado)"
echo ""
echo "Para verificar:"
echo "  openssl verify -CAfile root-ca/certs/root-ca.crt \\"
echo "                 -untrusted intermediate-ca/certs/intermediate-ca.crt \\"
echo "                 $CERT_FILE"

