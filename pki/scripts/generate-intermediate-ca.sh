#!/bin/bash

# Script para gerar Intermediate CA (chave privada, CSR e certificado assinado pela Root CA)
# Assignment 2 - PKI Infrastructure

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
ROOT_CA_DIR="$PKI_DIR/root-ca"
INTERMEDIATE_CA_DIR="$PKI_DIR/intermediate-ca"

echo -e "${GREEN}=== Geração da Intermediate CA ===${NC}"
echo "Diretório Root CA: $ROOT_CA_DIR"
echo "Diretório Intermediate CA: $INTERMEDIATE_CA_DIR"
echo ""

# Verificar se Root CA existe
if [ ! -f "$ROOT_CA_DIR/private/root-ca.key" ] || [ ! -f "$ROOT_CA_DIR/certs/root-ca.crt" ]; then
    echo -e "${RED}Erro: Root CA não encontrada!${NC}"
    echo "Execute primeiro: ./scripts/generate-root-ca.sh"
    exit 1
fi

# Verificar se o diretório intermediate-ca existe
if [ ! -d "$INTERMEDIATE_CA_DIR" ]; then
    echo -e "${RED}Erro: Diretório $INTERMEDIATE_CA_DIR não existe!${NC}"
    echo "Execute primeiro: ./scripts/init-ca.sh"
    exit 1
fi

# Verificar se já existe chave privada
if [ -f "$INTERMEDIATE_CA_DIR/private/intermediate-ca.key" ]; then
    echo -e "${YELLOW}⚠ Atenção: Chave privada já existe!${NC}"
    echo -e "${YELLOW}  Ficheiro: $INTERMEDIATE_CA_DIR/private/intermediate-ca.key${NC}"
    read -p "Deseja sobrescrever? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo -e "${BLUE}Operação cancelada.${NC}"
        exit 0
    fi
    echo -e "${YELLOW}Removendo ficheiros antigos...${NC}"
    rm -f "$INTERMEDIATE_CA_DIR/private/intermediate-ca.key"
    rm -f "$INTERMEDIATE_CA_DIR/csr/intermediate-ca.csr"
    rm -f "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt"
fi

# Mudar para o diretório intermediate-ca
cd "$INTERMEDIATE_CA_DIR"

echo -e "${YELLOW}Passo 1: Gerar chave privada RSA 4096 bits...${NC}"
openssl genrsa -out private/intermediate-ca.key 4096
chmod 600 private/intermediate-ca.key  # Permissões restritivas
echo -e "${GREEN}  ✓ Chave privada criada: private/intermediate-ca.key${NC}"
echo ""

echo -e "${YELLOW}Passo 2: Criar Certificate Signing Request (CSR)...${NC}"
openssl req -new \
    -config openssl.cnf \
    -key private/intermediate-ca.key \
    -out csr/intermediate-ca.csr \
    -sha256

echo -e "${GREEN}  ✓ CSR criado: csr/intermediate-ca.csr${NC}"
echo ""

echo -e "${YELLOW}Passo 3: Assinar CSR com Root CA...${NC}"
echo -e "${BLUE}  Validade: 5 anos${NC}"
echo -e "${BLUE}  Algoritmo: SHA-256${NC}"
echo -e "${BLUE}  Extensão: v3_intermediate_ca${NC}"
echo ""

# Mudar para root-ca para assinar
cd "$ROOT_CA_DIR"

# Assinar o CSR usando a Root CA
openssl ca -config openssl.cnf \
    -extensions v3_intermediate_ca \
    -days 1825 \
    -md sha256 \
    -in "$INTERMEDIATE_CA_DIR/csr/intermediate-ca.csr" \
    -out "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt" \
    -batch \
    -notext

chmod 644 "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt"
echo -e "${GREEN}  ✓ Certificado criado: intermediate-ca/certs/intermediate-ca.crt${NC}"
echo ""

# Voltar para intermediate-ca
cd "$INTERMEDIATE_CA_DIR"

# Verificar o certificado criado
echo -e "${YELLOW}Passo 4: Verificar certificado gerado...${NC}"
echo ""
openssl x509 -in certs/intermediate-ca.crt -text -noout | head -25
echo ""

# Verificar se foi assinado pela Root CA
ROOT_ISSUER=$(openssl x509 -in "$ROOT_CA_DIR/certs/root-ca.crt" -noout -subject | sed 's/^subject=//')
INTERMEDIATE_ISSUER=$(openssl x509 -in certs/intermediate-ca.crt -noout -issuer | sed 's/^issuer=//')

if [ "$ROOT_ISSUER" = "$INTERMEDIATE_ISSUER" ]; then
    echo -e "${GREEN}  ✓ Certificado foi assinado pela Root CA${NC}"
else
    echo -e "${RED}  ✗ Erro: Certificado não foi assinado pela Root CA!${NC}"
    echo -e "${RED}    Root CA Subject: $ROOT_ISSUER${NC}"
    echo -e "${RED}    Intermediate Issuer: $INTERMEDIATE_ISSUER${NC}"
    exit 1
fi

# Verificar cadeia de certificados
echo ""
echo -e "${YELLOW}Passo 5: Verificar cadeia de certificados...${NC}"
if openssl verify -CAfile "$ROOT_CA_DIR/certs/root-ca.crt" certs/intermediate-ca.crt > /dev/null 2>&1; then
    echo -e "${GREEN}  ✓ Cadeia de certificados válida${NC}"
else
    echo -e "${RED}  ✗ Erro: Cadeia de certificados inválida!${NC}"
    openssl verify -CAfile "$ROOT_CA_DIR/certs/root-ca.crt" certs/intermediate-ca.crt
    exit 1
fi

# Verificar validade
VALIDITY=$(openssl x509 -in certs/intermediate-ca.crt -noout -dates)
echo -e "${GREEN}  ✓ Validade do certificado:${NC}"
echo "$VALIDITY" | sed 's/^/    /'

echo ""
echo -e "${GREEN}=== Intermediate CA gerada com sucesso! ===${NC}"
echo ""
echo "Ficheiros criados:"
echo "  - intermediate-ca/private/intermediate-ca.key (chave privada - guardar em segurança!)"
echo "  - intermediate-ca/csr/intermediate-ca.csr (pedido de assinatura)"
echo "  - intermediate-ca/certs/intermediate-ca.crt (certificado assinado pela Root CA)"
echo ""
echo "Próximo passo:"
echo "  Executar: ./scripts/issue-server-cert.sh (ou scripts específicos para web01, db01, ssh01)"
