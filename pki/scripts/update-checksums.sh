#!/bin/bash

# Script para gerar/atualizar checksums SHA-256 dos ficheiros críticos da PKI
# Assignment 2 - PKI Infrastructure
# Política: "As configurações da CA (base de dados/ficheiro com informação de certificados) 
#            devem ter mecanismos de controlo de integridade"
# Uso: ./scripts/update-checksums.sh

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
CHECKSUMS_DIR="$PKI_DIR/checksums"

echo -e "${GREEN}=== Atualização de Checksums SHA-256 ===${NC}"
echo "Diretório PKI: $PKI_DIR"
echo "Diretório Checksums: $CHECKSUMS_DIR"
echo ""

# Criar diretório checksums se não existir
if [ ! -d "$CHECKSUMS_DIR" ]; then
    mkdir -p "$CHECKSUMS_DIR"
    echo -e "${GREEN}  ✓ Diretório checksums criado${NC}"
fi
echo ""

# Função para gerar checksum de um ficheiro
generate_checksum() {
    local file=$1
    local relative_path=${file#$PKI_DIR/}
    
    if [ -f "$file" ]; then
        # Gerar checksum SHA-256
        local checksum=$(sha256sum "$file" | awk '{print $1}')
        
        # Guardar checksum com path relativo
        echo "$checksum  $relative_path" >> "$CHECKSUMS_DIR/checksums.sha256"
        
        echo -e "${GREEN}  ✓ Checksum gerado: $relative_path${NC}"
        return 0
    else
        echo -e "${YELLOW}  ⚠ Ficheiro não encontrado: $relative_path${NC}"
        return 1
    fi
}

# Limpar checksums antigos
if [ -f "$CHECKSUMS_DIR/checksums.sha256" ]; then
    echo -e "${YELLOW}Removendo checksums antigos...${NC}"
    rm -f "$CHECKSUMS_DIR/checksums.sha256"
    echo -e "${GREEN}  ✓ Checksums antigos removidos${NC}"
    echo ""
fi

echo -e "${YELLOW}Gerando checksums SHA-256 para ficheiros críticos...${NC}"
echo ""

# Ficheiros críticos da Root CA
echo -e "${BLUE}Root CA:${NC}"
generate_checksum "$PKI_DIR/root-ca/private/root-ca.key"
generate_checksum "$PKI_DIR/root-ca/certs/root-ca.crt"
generate_checksum "$PKI_DIR/root-ca/index.txt"
generate_checksum "$PKI_DIR/root-ca/serial"
generate_checksum "$PKI_DIR/root-ca/index.txt.attr"
generate_checksum "$PKI_DIR/root-ca/openssl.cnf"
echo ""

# Ficheiros críticos da Intermediate CA
echo -e "${BLUE}Intermediate CA:${NC}"
generate_checksum "$PKI_DIR/intermediate-ca/private/intermediate-ca.key"
generate_checksum "$PKI_DIR/intermediate-ca/certs/intermediate-ca.crt"
generate_checksum "$PKI_DIR/intermediate-ca/index.txt"
generate_checksum "$PKI_DIR/intermediate-ca/serial"
generate_checksum "$PKI_DIR/intermediate-ca/index.txt.attr"
generate_checksum "$PKI_DIR/intermediate-ca/openssl.cnf"
echo ""

# Chaves privadas de servidor (se existirem)
echo -e "${BLUE}Certificados de Servidor:${NC}"
found_keys=false
for key_file in "$PKI_DIR"/*-key.pem; do
    if [ -f "$key_file" ]; then
        generate_checksum "$key_file"
        found_keys=true
    fi
done

if [ "$found_keys" = false ]; then
    echo -e "${BLUE}  (nenhuma chave de servidor encontrada)${NC}"
fi
echo ""

# Ficheiros críticos da SSH CA
echo -e "${BLUE}SSH CA:${NC}"
generate_checksum "$PKI_DIR/ssh-ca/private/ssh-ca-key" 2>/dev/null || echo -e "${BLUE}  (SSH CA ainda não gerada)${NC}"
generate_checksum "$PKI_DIR/ssh-ca/certs/ssh-ca-key.pub" 2>/dev/null || echo -e "${BLUE}  (SSH CA public key ainda não gerada)${NC}"
echo ""

# Verificar se algum checksum foi gerado
if [ ! -f "$CHECKSUMS_DIR/checksums.sha256" ]; then
    echo -e "${RED}Erro: Nenhum checksum foi gerado!${NC}"
    exit 1
fi

# Ordenar checksums por path para facilitar comparação
sort -k2 "$CHECKSUMS_DIR/checksums.sha256" > "$CHECKSUMS_DIR/checksums.sha256.tmp"
mv "$CHECKSUMS_DIR/checksums.sha256.tmp" "$CHECKSUMS_DIR/checksums.sha256"

# Contar ficheiros protegidos
file_count=$(wc -l < "$CHECKSUMS_DIR/checksums.sha256")
echo -e "${GREEN}=== Checksums Atualizados ===${NC}"
echo ""
echo "Ficheiros protegidos: $file_count"
echo "Ficheiro de checksums: $CHECKSUMS_DIR/checksums.sha256"
echo ""
echo -e "${BLUE}Para verificar integridade, execute:${NC}"
echo -e "${BLUE}  ./scripts/verify-integrity.sh${NC}"
echo ""
