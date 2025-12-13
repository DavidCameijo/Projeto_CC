#!/bin/bash

# Script para gerar Root CA (chave privada e certificado auto-assinado)
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

echo -e "${GREEN}=== Geração da Root CA ===${NC}"
echo "Diretório Root CA: $ROOT_CA_DIR"
echo ""

# Verificar se o diretório root-ca existe
if [ ! -d "$ROOT_CA_DIR" ]; then
    echo -e "${RED}Erro: Diretório $ROOT_CA_DIR não existe!${NC}"
    echo "Execute primeiro: ./scripts/init-ca.sh"
    exit 1
fi

# Verificar se já existe chave privada
if [ -f "$ROOT_CA_DIR/private/root-ca.key" ]; then
    echo -e "${YELLOW}⚠ Atenção: Chave privada já existe!${NC}"
    echo -e "${YELLOW}  Ficheiro: $ROOT_CA_DIR/private/root-ca.key${NC}"
    read -p "Deseja sobrescrever? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo -e "${BLUE}Operação cancelada.${NC}"
        exit 0
    fi
    echo -e "${YELLOW}Removendo chave antiga...${NC}"
    rm -f "$ROOT_CA_DIR/private/root-ca.key"
fi

# Verificar se já existe certificado
if [ -f "$ROOT_CA_DIR/certs/root-ca.crt" ]; then
    echo -e "${YELLOW}⚠ Atenção: Certificado já existe!${NC}"
    echo -e "${YELLOW}  Ficheiro: $ROOT_CA_DIR/certs/root-ca.crt${NC}"
    read -p "Deseja sobrescrever? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo -e "${BLUE}Operação cancelada.${NC}"
        exit 0
    fi
    echo -e "${YELLOW}Removendo certificado antigo...${NC}"
    rm -f "$ROOT_CA_DIR/certs/root-ca.crt"
fi

# Mudar para o diretório root-ca (importante para paths relativos)
cd "$ROOT_CA_DIR"

echo -e "${YELLOW}Passo 1: Gerar chave privada RSA 4096 bits...${NC}"
openssl genrsa -out private/root-ca.key 4096
chmod 600 private/root-ca.key  # Permissões restritivas
echo -e "${GREEN}  ✓ Chave privada criada: private/root-ca.key${NC}"
echo ""

echo -e "${YELLOW}Passo 2: Gerar certificado auto-assinado (Root CA)...${NC}"
echo -e "${BLUE}  Validade: 10 anos${NC}"
echo -e "${BLUE}  Algoritmo: SHA-256${NC}"
echo -e "${BLUE}  Tamanho da chave: RSA 4096 bits${NC}"
echo ""

# Gerar certificado auto-assinado usando openssl req com -x509
# -x509: gera certificado auto-assinado (não precisa de assinar depois)
openssl req -new -x509 \
    -config openssl.cnf \
    -key private/root-ca.key \
    -out certs/root-ca.crt \
    -days 3650 \
    -sha256 \
    -extensions v3_ca

chmod 644 certs/root-ca.crt  # Permissões de leitura para todos
echo -e "${GREEN}  ✓ Certificado criado: certs/root-ca.crt${NC}"
echo ""

# Verificar o certificado criado
echo -e "${YELLOW}Passo 3: Verificar certificado gerado...${NC}"
echo ""
openssl x509 -in certs/root-ca.crt -text -noout | head -20
echo ""

# Verificar se é auto-assinado
ISSUER=$(openssl x509 -in certs/root-ca.crt -noout -issuer | sed 's/^issuer=//')
SUBJECT=$(openssl x509 -in certs/root-ca.crt -noout -subject | sed 's/^subject=//')

if [ "$ISSUER" = "$SUBJECT" ]; then
    echo -e "${GREEN}  ✓ Certificado é auto-assinado (Root CA)${NC}"
else
    echo -e "${RED}  ✗ Erro: Certificado não é auto-assinado!${NC}"
    echo -e "${RED}    Issuer: $ISSUER${NC}"
    echo -e "${RED}    Subject: $SUBJECT${NC}"
    exit 1
fi

# Verificar validade
VALIDITY=$(openssl x509 -in certs/root-ca.crt -noout -dates)
echo -e "${GREEN}  ✓ Validade do certificado:${NC}"
echo "$VALIDITY" | sed 's/^/    /'

echo ""
echo -e "${GREEN}=== Root CA gerada com sucesso! ===${NC}"
echo ""
echo "Ficheiros criados:"
echo "  - root-ca/private/root-ca.key (chave privada - guardar em segurança!)"
echo "  - root-ca/certs/root-ca.crt (certificado público)"
echo ""
echo "Próximo passo:"
echo "  Executar: ./scripts/generate-intermediate-ca.sh"
