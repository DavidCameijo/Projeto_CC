#!/bin/bash

# Script para verificar estado de revogação de um certificado usando CRL
# Assignment 2 - PKI Infrastructure
# Política: "Suporte ao ciclo de vida completo: emissão, verificação, revogação"
# Uso: ./scripts/verify-revocation.sh <serial_number|certificate_file>
# Exemplo: ./scripts/verify-revocation.sh 1000
# Exemplo: ./scripts/verify-revocation.sh web01.org.local-cert.pem

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
ROOT_CA_DIR="$PKI_DIR/root-ca"
CRL_FILE="$INTERMEDIATE_CA_DIR/crl/intermediate-ca.crl.pem"

echo -e "${GREEN}=== Verificação de Revogação de Certificado ===${NC}"
echo ""

# Verificar argumentos
if [ $# -eq 0 ]; then
    echo -e "${RED}Erro: Número de série ou ficheiro de certificado não fornecido!${NC}"
    echo ""
    echo "Uso: $0 <serial_number|certificate_file>"
    echo ""
    echo "Exemplos:"
    echo "  $0 1000                    # Verificar por número de série"
    echo "  $0 web01.org.local-cert.pem # Verificar por ficheiro de certificado"
    exit 1
fi

INPUT=$1

# Verificar se CRL existe
if [ ! -f "$CRL_FILE" ]; then
    echo -e "${RED}Erro: CRL não encontrada!${NC}"
    echo "Execute primeiro: ./scripts/generate-crl.sh"
    exit 1
fi

# Verificar se Root CA e Intermediate CA existem
if [ ! -f "$ROOT_CA_DIR/certs/root-ca.crt" ] || [ ! -f "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt" ]; then
    echo -e "${RED}Erro: Certificados CA não encontrados!${NC}"
    exit 1
fi

# Determinar número de série
if [[ "$INPUT" =~ ^[0-9]+$ ]]; then
    # É um número de série
    SERIAL=$INPUT
    CERT_FILE=""
    echo -e "${BLUE}Modo: Verificação por número de série${NC}"
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
    
    # Extrair número de série do certificado
    SERIAL=$(openssl x509 -in "$CERT_FILE" -noout -serial | cut -d= -f2 | sed 's/^0*//')
    if [ -z "$SERIAL" ]; then
        echo -e "${RED}Erro: Não foi possível extrair número de série do certificado!${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Modo: Verificação por ficheiro de certificado${NC}"
    echo "Ficheiro: $CERT_FILE"
    echo "Número de série: $SERIAL"
fi

echo ""

# Converter número de série para formato hexadecimal (com zeros à esquerda se necessário)
# OpenSSL armazena números de série em hexadecimal na CRL
SERIAL_HEX=$(printf "%X" "$SERIAL" | tr '[:lower:]' '[:upper:]')

echo -e "${YELLOW}Verificando estado de revogação...${NC}"
echo ""

# Verificar na base de dados primeiro
DB_STATUS=$(grep "^[VR].*$SERIAL" "$INTERMEDIATE_CA_DIR/index.txt" 2>/dev/null | head -1 | cut -f1 || echo "")

if [ -z "$DB_STATUS" ]; then
    echo -e "${YELLOW}⚠ Certificado não encontrado na base de dados${NC}"
elif [ "$DB_STATUS" = "R" ]; then
    echo -e "${RED}✗ Certificado está marcado como REVOGADO na base de dados${NC}"
    grep "^R.*$SERIAL" "$INTERMEDIATE_CA_DIR/index.txt"
elif [ "$DB_STATUS" = "V" ]; then
    echo -e "${GREEN}✓ Certificado está marcado como VÁLIDO na base de dados${NC}"
fi
echo ""

# Verificar na CRL
echo -e "${BLUE}Verificando na CRL...${NC}"
CRL_TEXT=$(openssl crl -in "$CRL_FILE" -noout -text 2>/dev/null)

if echo "$CRL_TEXT" | grep -q "Serial Number:.*$SERIAL_HEX\|Serial Number:.*$SERIAL"; then
    echo -e "${RED}✗ Certificado ENCONTRADO na CRL (REVOGADO)${NC}"
    echo ""
    echo -e "${BLUE}Detalhes da revogação:${NC}"
    echo "$CRL_TEXT" | grep -A5 "Serial Number:.*$SERIAL_HEX\|Serial Number:.*$SERIAL"
    REVOKED=true
else
    echo -e "${GREEN}✓ Certificado NÃO encontrado na CRL (NÃO REVOGADO)${NC}"
    REVOKED=false
fi
echo ""

# Se temos ficheiro de certificado, fazer verificação completa com openssl verify
if [ -n "$CERT_FILE" ]; then
    echo -e "${BLUE}Verificação completa com openssl verify -crl_check...${NC}"
    echo ""
    
    # Verificar cadeia e revogação
    if openssl verify -CAfile "$ROOT_CA_DIR/certs/root-ca.crt" \
                      -untrusted "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt" \
                      -CRLfile "$CRL_FILE" \
                      -crl_check \
                      "$CERT_FILE" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Certificado VÁLIDO e NÃO REVOGADO${NC}"
        echo ""
        echo -e "${BLUE}Resultado da verificação:${NC}"
        openssl verify -CAfile "$ROOT_CA_DIR/certs/root-ca.crt" \
                       -untrusted "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt" \
                       -CRLfile "$CRL_FILE" \
                       -crl_check \
                       "$CERT_FILE"
    else
        VERIFY_OUTPUT=$(openssl verify -CAfile "$ROOT_CA_DIR/certs/root-ca.crt" \
                                       -untrusted "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt" \
                                       -CRLfile "$CRL_FILE" \
                                       -crl_check \
                                       "$CERT_FILE" 2>&1)
        
        if echo "$VERIFY_OUTPUT" | grep -qi "revoked\|revocation"; then
            echo -e "${RED}✗ Certificado REVOGADO (verificação falhou)${NC}"
            echo ""
            echo -e "${BLUE}Resultado da verificação:${NC}"
            echo "$VERIFY_OUTPUT"
        else
            echo -e "${YELLOW}⚠ Verificação falhou por outro motivo${NC}"
            echo ""
            echo -e "${BLUE}Resultado da verificação:${NC}"
            echo "$VERIFY_OUTPUT"
        fi
    fi
else
    echo -e "${BLUE}Nota: Para verificação completa com openssl verify, forneça o ficheiro de certificado${NC}"
fi

echo ""
echo -e "${BLUE}=== Resumo ===${NC}"
if [ "$REVOKED" = true ]; then
    echo -e "${RED}Estado: REVOGADO${NC}"
    echo -e "${RED}O certificado não deve ser usado!${NC}"
    exit 1
else
    echo -e "${GREEN}Estado: NÃO REVOGADO${NC}"
    echo -e "${GREEN}O certificado pode ser usado.${NC}"
    exit 0
fi
