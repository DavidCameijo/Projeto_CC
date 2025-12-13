#!/bin/bash

# Script para inicializar a estrutura das CAs (Root e Intermediate)
# Assignment 2 - PKI Infrastructure

set -e  # Parar se houver erro

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Diretório base (onde está este script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKI_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${GREEN}=== Inicialização da PKI ===${NC}"
echo "Diretório PKI: $PKI_DIR"
echo ""

# Função para inicializar uma CA
init_ca() {
    local ca_name=$1
    local ca_dir="$PKI_DIR/$ca_name"
    
    echo -e "${YELLOW}Inicializando $ca_name...${NC}"
    
    # Verificar se o diretório existe
    if [ ! -d "$ca_dir" ]; then
        echo -e "${RED}Erro: Diretório $ca_dir não existe!${NC}"
        return 1
    fi
    
    # Criar index.txt se não existir
    if [ ! -f "$ca_dir/index.txt" ]; then
        touch "$ca_dir/index.txt"
        echo -e "  ✓ Criado $ca_dir/index.txt"
    else
        echo -e "  ⚠ $ca_dir/index.txt já existe (não sobrescrito)"
    fi
    
    # Criar serial se não existir
    if [ ! -f "$ca_dir/serial" ]; then
        echo "1000" > "$ca_dir/serial"
        echo -e "  ✓ Criado $ca_dir/serial (iniciado em 1000)"
    else
        echo -e "  ⚠ $ca_dir/serial já existe (não sobrescrito)"
    fi
    
    # Criar index.txt.attr se não existir (atributos adicionais)
    if [ ! -f "$ca_dir/index.txt.attr" ]; then
        echo "unique_subject = yes" > "$ca_dir/index.txt.attr"
        echo -e "  ✓ Criado $ca_dir/index.txt.attr"
    else
        echo -e "  ⚠ $ca_dir/index.txt.attr já existe (não sobrescrito)"
    fi
    
    echo -e "${GREEN}  ✓ $ca_name inicializada com sucesso${NC}"
    echo ""
}

# Inicializar Root CA
init_ca "root-ca"

# Inicializar Intermediate CA
init_ca "intermediate-ca"

echo -e "${GREEN}=== Inicialização concluída! ===${NC}"
echo ""
echo "Ficheiros criados:"
echo "  - root-ca/index.txt (base de dados de certificados)"
echo "  - root-ca/serial (contador de números de série)"
echo "  - root-ca/index.txt.attr (atributos)"
echo "  - intermediate-ca/index.txt"
echo "  - intermediate-ca/serial"
echo "  - intermediate-ca/index.txt.attr"
echo ""
echo "Próximos passos:"
echo "  1. Executar: ./scripts/generate-root-ca.sh"
echo "  2. Executar: ./scripts/generate-intermediate-ca.sh"
