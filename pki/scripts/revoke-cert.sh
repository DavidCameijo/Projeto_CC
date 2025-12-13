#!/bin/bash

# Script para revogar certificados
# Assignment 2 - PKI Infrastructure
# Política: "Suporte ao ciclo de vida completo: emissão, verificação, revogação"
# Uso: ./scripts/revoke-cert.sh <serial_number|certificate_file> [reason]
# Exemplo: ./scripts/revoke-cert.sh 1000
# Exemplo: ./scripts/revoke-cert.sh web01.org.local-cert.pem

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

echo -e "${GREEN}=== Revogação de Certificado ===${NC}"
echo ""

# Verificar argumentos
if [ $# -eq 0 ]; then
    echo -e "${RED}Erro: Número de série ou ficheiro de certificado não fornecido!${NC}"
    echo ""
    echo "Uso: $0 <serial_number|certificate_file> [reason]"
    echo ""
    echo "Exemplos:"
    echo "  $0 1000                    # Revogar por número de série"
    echo "  $0 web01.org.local-cert.pem # Revogar por ficheiro de certificado"
    echo "  $0 1000 unspecified        # Revogar com razão específica"
    echo ""
    echo "Razões disponíveis:"
    echo "  unspecified, keyCompromise, CACompromise, affiliationChanged,"
    echo "  superseded, cessationOfOperation, certificateHold, removeFromCRL"
    exit 1
fi

INPUT=$1
REASON=${2:-unspecified}

# Verificar se Intermediate CA existe
if [ ! -f "$INTERMEDIATE_CA_DIR/private/intermediate-ca.key" ] || [ ! -f "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt" ]; then
    echo -e "${RED}Erro: Intermediate CA não encontrada!${NC}"
    echo "Execute primeiro: ./scripts/generate-intermediate-ca.sh"
    exit 1
fi

# Determinar se é número de série ou ficheiro
if [[ "$INPUT" =~ ^[0-9]+$ ]]; then
    # É um número de série
    SERIAL=$INPUT
    CERT_FILE=""
    echo -e "${BLUE}Modo: Revogação por número de série${NC}"
    echo "Número de série: $SERIAL"
else
    # É um ficheiro de certificado
    if [ -f "$INPUT" ]; then
        CERT_FILE="$INPUT"
    elif [ -f "$PKI_DIR/$INPUT" ]; then
        CERT_FILE="$PKI_DIR/$INPUT"
    else
        echo -e "${RED}Erro: Ficheiro de certificado não encontrado: $INPUT${NC}"
        exit 1
    fi
    
    # Converter para path absoluto
    if [[ "$CERT_FILE" != /* ]]; then
        CERT_FILE="$(cd "$(dirname "$CERT_FILE")" && pwd)/$(basename "$CERT_FILE")"
    fi
    
    # Extrair número de série do certificado
    SERIAL=$(openssl x509 -in "$CERT_FILE" -noout -serial | cut -d= -f2 | sed 's/^0*//')
    if [ -z "$SERIAL" ]; then
        echo -e "${RED}Erro: Não foi possível extrair número de série do certificado!${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Modo: Revogação por ficheiro de certificado${NC}"
    echo "Ficheiro: $CERT_FILE"
    echo "Número de série extraído: $SERIAL"
fi

echo "Razão de revogação: $REASON"
echo ""

# Verificar se certificado já está revogado
if grep -q "^R.*$SERIAL" "$INTERMEDIATE_CA_DIR/index.txt" 2>/dev/null; then
    echo -e "${YELLOW}⚠ Atenção: Certificado com número de série $SERIAL já está revogado!${NC}"
    grep "^R.*$SERIAL" "$INTERMEDIATE_CA_DIR/index.txt"
    echo ""
    read -p "Deseja continuar mesmo assim? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo -e "${BLUE}Operação cancelada.${NC}"
        exit 0
    fi
fi

# Verificar se certificado existe na base de dados
if ! grep -q "^V.*$SERIAL\|^R.*$SERIAL" "$INTERMEDIATE_CA_DIR/index.txt" 2>/dev/null; then
    echo -e "${RED}Erro: Certificado com número de série $SERIAL não encontrado na base de dados!${NC}"
    echo ""
    echo "Certificados disponíveis na base de dados:"
    cat "$INTERMEDIATE_CA_DIR/index.txt" | grep -v "^$" | head -5
    exit 1
fi

echo -e "${YELLOW}Revogando certificado...${NC}"
echo ""

# Mudar para intermediate-ca para revogar
cd "$INTERMEDIATE_CA_DIR"

# Revogar certificado
if [ -n "$CERT_FILE" ]; then
    # CERT_FILE já está em path absoluto (convertido acima)
    # Verificar se ficheiro existe
    if [ ! -f "$CERT_FILE" ]; then
        echo -e "${RED}Erro: Ficheiro de certificado não encontrado: $CERT_FILE${NC}"
        exit 1
    fi
    
    # Revogar usando ficheiro de certificado (path absoluto)
    openssl ca -config openssl.cnf \
        -revoke "$CERT_FILE" \
        -crl_reason "$REASON" \
        -batch
else
    # Revogar usando número de série (precisa encontrar o certificado em newcerts/)
    CERT_IN_NEWCERTS="$INTERMEDIATE_CA_DIR/newcerts/${SERIAL}.pem"
    
    if [ -f "$CERT_IN_NEWCERTS" ]; then
        openssl ca -config openssl.cnf \
            -revoke "$CERT_IN_NEWCERTS" \
            -crl_reason "$REASON" \
            -batch
    else
        echo -e "${YELLOW}⚠ Certificado não encontrado em newcerts/${SERIAL}.pem${NC}"
        echo -e "${YELLOW}  Tentando revogar diretamente pelo número de série...${NC}"
        echo ""
        echo -e "${BLUE}Nota: Para revogar por número de série, o certificado deve estar em newcerts/${NC}"
        echo -e "${BLUE}      Ou forneça o ficheiro de certificado diretamente.${NC}"
        exit 1
    fi
fi

echo ""

# Verificar se revogação foi bem-sucedida
if grep -q "^R.*$SERIAL" "$INTERMEDIATE_CA_DIR/index.txt" 2>/dev/null; then
    echo -e "${GREEN}✓ Certificado revogado com sucesso!${NC}"
    echo ""
    echo -e "${BLUE}Estado na base de dados:${NC}"
    grep "^R.*$SERIAL" "$INTERMEDIATE_CA_DIR/index.txt"
    echo ""
    echo -e "${YELLOW}Próximos passos:${NC}"
    echo -e "${YELLOW}  1. Gerar/atualizar CRL: ./scripts/generate-crl.sh${NC}"
    echo -e "${YELLOW}  2. Verificar revogação: ./scripts/verify-revocation.sh $SERIAL${NC}"
else
    echo -e "${RED}✗ Erro: Revogação pode ter falhado!${NC}"
    echo "Verifique a base de dados manualmente."
    exit 1
fi
