#!/bin/bash

# Script para verificação completa de certificado (cadeia, expiração, revogação)
# Assignment 2 - PKI Infrastructure
# Política: "Suporte ao ciclo de vida completo: emissão, verificação, revogação"
# Uso: ./scripts/verify-cert.sh <certificate_file>
# Exemplo: ./scripts/verify-cert.sh web01.org.local-cert.pem

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

echo -e "${GREEN}=== Verificação Completa de Certificado ===${NC}"
echo ""

# Verificar argumentos
if [ $# -eq 0 ]; then
    echo -e "${RED}Erro: Ficheiro de certificado não fornecido!${NC}"
    echo ""
    echo "Uso: $0 <certificate_file>"
    echo ""
    echo "Exemplo:"
    echo "  $0 web01.org.local-cert.pem"
    exit 1
fi

CERT_FILE=$1

# Resolver path do certificado
if [ -f "$CERT_FILE" ]; then
    CERT_PATH="$CERT_FILE"
elif [ -f "$PKI_DIR/$CERT_FILE" ]; then
    CERT_PATH="$PKI_DIR/$CERT_FILE"
else
    echo -e "${RED}Erro: Ficheiro de certificado não encontrado: $CERT_FILE${NC}"
    exit 1
fi

echo "Certificado: $CERT_PATH"
echo ""

# Verificar se certificado existe
if [ ! -f "$CERT_PATH" ]; then
    echo -e "${RED}Erro: Ficheiro não encontrado!${NC}"
    exit 1
fi

# Verificar se Root CA e Intermediate CA existem
if [ ! -f "$ROOT_CA_DIR/certs/root-ca.crt" ] || [ ! -f "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt" ]; then
    echo -e "${RED}Erro: Certificados CA não encontrados!${NC}"
    exit 1
fi

# Contadores de verificação
CHECKS_PASSED=0
CHECKS_FAILED=0

echo -e "${BLUE}=== 1. Informações do Certificado ===${NC}"
echo ""

# Mostrar informações básicas
echo -e "${BLUE}Subject:${NC}"
openssl x509 -in "$CERT_PATH" -noout -subject | sed 's/^/  /'
echo ""

echo -e "${BLUE}Issuer:${NC}"
openssl x509 -in "$CERT_PATH" -noout -issuer | sed 's/^/  /'
echo ""

echo -e "${BLUE}Número de Série:${NC}"
SERIAL=$(openssl x509 -in "$CERT_PATH" -noout -serial | cut -d= -f2 | sed 's/^0*//')
echo "  $SERIAL"
echo ""

echo -e "${BLUE}Datas de Validade:${NC}"
openssl x509 -in "$CERT_PATH" -noout -dates | sed 's/^/  /'
echo ""

# Verificar validade (não expirado)
echo -e "${BLUE}=== 2. Verificação de Validade ===${NC}"
echo ""

NOT_AFTER=$(openssl x509 -in "$CERT_PATH" -noout -enddate | cut -d= -f2)
NOT_AFTER_EPOCH=$(date -d "$NOT_AFTER" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$NOT_AFTER" +%s 2>/dev/null || echo "0")
CURRENT_EPOCH=$(date +%s)

if [ "$NOT_AFTER_EPOCH" -gt "$CURRENT_EPOCH" ]; then
    DAYS_LEFT=$(( (NOT_AFTER_EPOCH - CURRENT_EPOCH) / 86400 ))
    echo -e "${GREEN}✓ Certificado VÁLIDO (não expirado)${NC}"
    echo "  Expira em: $NOT_AFTER"
    echo "  Dias restantes: $DAYS_LEFT"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    echo -e "${RED}✗ Certificado EXPIRADO${NC}"
    echo "  Data de expiração: $NOT_AFTER"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi
echo ""

# Verificar cadeia de certificados
echo -e "${BLUE}=== 3. Verificação de Cadeia de Certificados ===${NC}"
echo ""

if openssl verify -CAfile "$ROOT_CA_DIR/certs/root-ca.crt" \
                  -untrusted "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt" \
                  "$CERT_PATH" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Cadeia de certificados VÁLIDA${NC}"
    echo ""
    echo -e "${BLUE}Detalhes da verificação:${NC}"
    openssl verify -CAfile "$ROOT_CA_DIR/certs/root-ca.crt" \
                   -untrusted "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt" \
                   "$CERT_PATH"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    echo -e "${RED}✗ Cadeia de certificados INVÁLIDA${NC}"
    echo ""
    echo -e "${BLUE}Detalhes do erro:${NC}"
    openssl verify -CAfile "$ROOT_CA_DIR/certs/root-ca.crt" \
                   -untrusted "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt" \
                   "$CERT_PATH"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi
echo ""

# Verificar revogação
echo -e "${BLUE}=== 4. Verificação de Revogação ===${NC}"
echo ""

if [ ! -f "$CRL_FILE" ]; then
    echo -e "${YELLOW}⚠ CRL não encontrada - pulando verificação de revogação${NC}"
    echo "  Execute: ./scripts/generate-crl.sh"
    echo ""
else
    # Verificar se está revogado na CRL
    CRL_TEXT=$(openssl crl -in "$CRL_FILE" -noout -text 2>/dev/null)
    SERIAL_HEX=$(printf "%X" "$SERIAL" | tr '[:lower:]' '[:upper:]')
    
    if echo "$CRL_TEXT" | grep -q "Serial Number:.*$SERIAL_HEX\|Serial Number:.*$SERIAL"; then
        echo -e "${RED}✗ Certificado REVOGADO${NC}"
        echo ""
        echo -e "${BLUE}Detalhes da revogação:${NC}"
        echo "$CRL_TEXT" | grep -A5 "Serial Number:.*$SERIAL_HEX\|Serial Number:.*$SERIAL"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    else
        # Verificação completa com openssl verify -crl_check
        if openssl verify -CAfile "$ROOT_CA_DIR/certs/root-ca.crt" \
                          -untrusted "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt" \
                          -CRLfile "$CRL_FILE" \
                          -crl_check \
                          "$CERT_PATH" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Certificado NÃO REVOGADO${NC}"
            CHECKS_PASSED=$((CHECKS_PASSED + 1))
        else
            VERIFY_OUTPUT=$(openssl verify -CAfile "$ROOT_CA_DIR/certs/root-ca.crt" \
                                           -untrusted "$INTERMEDIATE_CA_DIR/certs/intermediate-ca.crt" \
                                           -CRLfile "$CRL_FILE" \
                                           -crl_check \
                                           "$CERT_PATH" 2>&1)
            
            if echo "$VERIFY_OUTPUT" | grep -qi "revoked\|revocation"; then
                echo -e "${RED}✗ Certificado REVOGADO (verificação com CRL)${NC}"
                echo ""
                echo -e "${BLUE}Detalhes:${NC}"
                echo "$VERIFY_OUTPUT"
                CHECKS_FAILED=$((CHECKS_FAILED + 1))
            else
                echo -e "${YELLOW}⚠ Verificação de revogação falhou por outro motivo${NC}"
                echo ""
                echo -e "${BLUE}Detalhes:${NC}"
                echo "$VERIFY_OUTPUT"
            fi
        fi
    fi
    echo ""
fi

# Verificar SAN (se existir)
echo -e "${BLUE}=== 5. Subject Alternative Names (SAN) ===${NC}"
echo ""

SAN_COUNT=$(openssl x509 -in "$CERT_PATH" -noout -text | grep -c "DNS:" || echo "0")
if [ "$SAN_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ SAN encontrado:${NC}"
    openssl x509 -in "$CERT_PATH" -noout -text | grep "DNS:" | sed 's/^[[:space:]]*/  /'
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    echo -e "${YELLOW}⚠ Nenhum SAN encontrado${NC}"
fi
echo ""

# Resumo final
echo -e "${BLUE}=== Resumo da Verificação ===${NC}"
echo ""
echo "Verificações passadas: $CHECKS_PASSED"
if [ $CHECKS_FAILED -gt 0 ]; then
    echo -e "${RED}Verificações falhadas: $CHECKS_FAILED${NC}"
fi
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ Certificado VÁLIDO e APROVADO para uso${NC}"
    exit 0
else
    echo -e "${RED}✗ Certificado NÃO APROVADO para uso${NC}"
    echo -e "${RED}  Verifique os erros acima antes de usar este certificado.${NC}"
    exit 1
fi
