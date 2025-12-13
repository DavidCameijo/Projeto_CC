#!/bin/bash

# Script para gerar/atualizar Certificate Revocation List (CRL)
# Assignment 2 - PKI Infrastructure
# Política: "Suporte ao ciclo de vida completo: emissão, verificação, revogação"
# Uso: ./scripts/generate-crl.sh [days]
# Exemplo: ./scripts/generate-crl.sh 30

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
CRL_DIR="$INTERMEDIATE_CA_DIR/crl"
CRL_FILE_PEM="$CRL_DIR/intermediate-ca.crl.pem"
CRL_FILE_DER="$CRL_DIR/intermediate-ca.crl"

echo -e "${GREEN}=== Geração de Certificate Revocation List (CRL) ===${NC}"
echo "Diretório Intermediate CA: $INTERMEDIATE_CA_DIR"
echo ""

# Verificar se Intermediate CA existe
if [ ! -f "$INTERMEDIATE_CA_DIR/private/intermediate-ca.key" ] || [ ! -f "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt" ]; then
    echo -e "${RED}Erro: Intermediate CA não encontrada!${NC}"
    echo "Execute primeiro: ./scripts/generate-intermediate-ca.sh"
    exit 1
fi

# Validade da CRL (padrão: 30 dias)
CRL_DAYS=${1:-30}

if ! [[ "$CRL_DAYS" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Erro: Número de dias inválido: $CRL_DAYS${NC}"
    echo "Uso: $0 [days]"
    echo "Exemplo: $0 30"
    exit 1
fi

echo -e "${BLUE}Validade da CRL: $CRL_DAYS dias${NC}"
echo ""

# Criar diretório CRL se não existir
if [ ! -d "$CRL_DIR" ]; then
    mkdir -p "$CRL_DIR"
    echo -e "${GREEN}  ✓ Diretório CRL criado: $CRL_DIR${NC}"
fi
echo ""

# Verificar quantos certificados estão revogados
REVOKED_COUNT=$(grep -c "^R" "$INTERMEDIATE_CA_DIR/index.txt" 2>/dev/null || echo "0")

if [ "$REVOKED_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠ Nenhum certificado revogado encontrado na base de dados.${NC}"
    echo -e "${YELLOW}  A CRL será gerada vazia (sem certificados revogados).${NC}"
    echo ""
else
    echo -e "${BLUE}Certificados revogados encontrados: $REVOKED_COUNT${NC}"
    echo ""
fi

# Mudar para intermediate-ca para gerar CRL
cd "$INTERMEDIATE_CA_DIR"

echo -e "${YELLOW}Gerando CRL...${NC}"

# Gerar CRL em formato PEM
openssl ca -config openssl.cnf \
    -gencrl \
    -out "$CRL_FILE_PEM" \
    -crldays "$CRL_DAYS" \
    -batch

# Converter para DER (opcional, mas útil)
openssl crl -in "$CRL_FILE_PEM" -outform DER -out "$CRL_FILE_DER"

# Definir permissões
chmod 644 "$CRL_FILE_PEM"
chmod 644 "$CRL_FILE_DER"

echo -e "${GREEN}  ✓ CRL gerada: $CRL_FILE_PEM${NC}"
echo -e "${GREEN}  ✓ CRL gerada (DER): $CRL_FILE_DER${NC}"
echo ""

# Mostrar informações da CRL
echo -e "${BLUE}Informações da CRL:${NC}"
openssl crl -in "$CRL_FILE_PEM" -noout -text | head -20
echo ""

# Contar certificados revogados na CRL
CRL_REVOKED_COUNT=$(openssl crl -in "$CRL_FILE_PEM" -noout -text 2>/dev/null | grep -c "Serial Number:" || echo "0")

if [ "$CRL_REVOKED_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ CRL contém $CRL_REVOKED_COUNT certificado(s) revogado(s)${NC}"
    echo ""
    echo -e "${BLUE}Certificados revogados na CRL:${NC}"
    openssl crl -in "$CRL_FILE_PEM" -noout -text | grep -A2 "Serial Number:"
else
    echo -e "${BLUE}CRL vazia (nenhum certificado revogado)${NC}"
fi

echo ""
echo -e "${GREEN}=== CRL Gerada com Sucesso ===${NC}"
echo ""
echo "Ficheiros criados:"
echo "  - $CRL_FILE_PEM (formato PEM)"
echo "  - $CRL_FILE_DER (formato DER)"
echo ""
echo -e "${BLUE}Para verificar revogação de um certificado:${NC}"
echo -e "${BLUE}  ./scripts/verify-revocation.sh <serial_number|certificate_file>${NC}"
echo ""
