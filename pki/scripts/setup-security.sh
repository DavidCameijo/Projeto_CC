#!/bin/bash

# Script para configurar políticas de segurança da PKI
# Assignment 2 - PKI Infrastructure
# Política: "Suportar acesso seguro a certificados e chaves privadas da CA"
# Uso: ./scripts/setup-security.sh

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

echo -e "${GREEN}=== Configuração de Segurança da PKI ===${NC}"
echo "Diretório PKI: $PKI_DIR"
echo ""

# Verificar se está a correr como root
IS_ROOT=false
if [ "$EUID" -eq 0 ]; then
    IS_ROOT=true
    echo -e "${BLUE}Executando como root - pode criar utilizador/grupo dedicado${NC}"
else
    echo -e "${YELLOW}Executando como utilizador normal - apenas configura permissões${NC}"
    echo -e "${YELLOW}(Para criar utilizador dedicado, execute como root)${NC}"
fi
echo ""

# Função para definir permissões de um diretório
set_dir_permissions() {
    local dir=$1
    local perms=$2
    
    if [ -d "$dir" ]; then
        chmod "$perms" "$dir"
        echo -e "${GREEN}  ✓ Permissões $perms definidas: $dir${NC}"
    fi
}

# Função para definir permissões de um ficheiro
set_file_permissions() {
    local file=$1
    local perms=$2
    
    if [ -f "$file" ]; then
        chmod "$perms" "$file"
        echo -e "${GREEN}  ✓ Permissões $perms definidas: $file${NC}"
    fi
}

# Passo 1: Criar utilizador/grupo dedicado (apenas se root)
if [ "$IS_ROOT" = true ]; then
    echo -e "${YELLOW}Passo 1: Criar utilizador/grupo dedicado 'ca'...${NC}"
    
    # Verificar se grupo já existe
    if getent group ca > /dev/null 2>&1; then
        echo -e "${BLUE}  Grupo 'ca' já existe${NC}"
    else
        groupadd ca
        echo -e "${GREEN}  ✓ Grupo 'ca' criado${NC}"
    fi
    
    # Verificar se utilizador já existe
    if id -u ca > /dev/null 2>&1; then
        echo -e "${BLUE}  Utilizador 'ca' já existe${NC}"
    else
        useradd -r -g ca -s /bin/false -d "$PKI_DIR" ca
        echo -e "${GREEN}  ✓ Utilizador 'ca' criado (sistema, sem shell de login)${NC}"
    fi
    
    # Adicionar utilizador atual ao grupo ca (se não for root)
    CURRENT_USER=${SUDO_USER:-$USER}
    if [ -n "$CURRENT_USER" ] && [ "$CURRENT_USER" != "root" ]; then
        usermod -a -G ca "$CURRENT_USER"
        echo -e "${GREEN}  ✓ Utilizador '$CURRENT_USER' adicionado ao grupo 'ca'${NC}"
    fi
else
    echo -e "${YELLOW}Passo 1: Criar utilizador/grupo dedicado...${NC}"
    echo -e "${BLUE}  ⚠ Pulado (não executado como root)${NC}"
    echo -e "${BLUE}  Para criar utilizador dedicado, execute: sudo ./scripts/setup-security.sh${NC}"
fi
echo ""

# Passo 2: Configurar permissões dos diretórios privados
echo -e "${YELLOW}Passo 2: Configurar permissões dos diretórios privados...${NC}"

# Diretórios privados - apenas dono pode aceder (700)
set_dir_permissions "$PKI_DIR/root-ca/private" 700
set_dir_permissions "$PKI_DIR/intermediate-ca/private" 700
set_dir_permissions "$PKI_DIR/ssh-ca/private" 700

# Diretório checksums - apenas dono pode escrever (755 para leitura)
set_dir_permissions "$PKI_DIR/checksums" 755

echo ""

# Passo 3: Configurar permissões das chaves privadas
echo -e "${YELLOW}Passo 3: Configurar permissões das chaves privadas...${NC}"

# Chaves privadas - apenas dono pode ler/escrever (600)
set_file_permissions "$PKI_DIR/root-ca/private/root-ca.key" 600
set_file_permissions "$PKI_DIR/intermediate-ca/private/intermediate-ca.key" 600
set_file_permissions "$PKI_DIR/ssh-ca/private/ssh-ca-key" 600

# Procurar outras chaves privadas de servidor
for key_file in "$PKI_DIR"/*-key.pem; do
    if [ -f "$key_file" ]; then
        set_file_permissions "$key_file" 600
    fi
done

# Procurar chaves privadas SSH de utilizador
for key_file in "$PKI_DIR/ssh-ca/user-certs"/*-key; do
    if [ -f "$key_file" ]; then
        set_file_permissions "$key_file" 600
    fi
done

echo ""

# Passo 4: Configurar permissões dos ficheiros da base de dados
echo -e "${YELLOW}Passo 4: Configurar permissões dos ficheiros da base de dados...${NC}"

# Base de dados - apenas dono pode escrever (644 para leitura)
set_file_permissions "$PKI_DIR/root-ca/index.txt" 644
set_file_permissions "$PKI_DIR/intermediate-ca/index.txt" 644
set_file_permissions "$PKI_DIR/root-ca/serial" 644
set_file_permissions "$PKI_DIR/intermediate-ca/serial" 644
set_file_permissions "$PKI_DIR/root-ca/index.txt.attr" 644
set_file_permissions "$PKI_DIR/intermediate-ca/index.txt.attr" 644

echo ""

# Passo 5: Configurar permissões dos certificados públicos
echo -e "${YELLOW}Passo 5: Configurar permissões dos certificados públicos...${NC}"

# Certificados públicos - leitura para todos (644)
set_file_permissions "$PKI_DIR/root-ca/certs/root-ca.crt" 644
set_file_permissions "$PKI_DIR/intermediate-ca/certs/intermediate-ca.crt" 644

# Procurar outros certificados
for cert_file in "$PKI_DIR"/*-cert.pem "$PKI_DIR"/*-chain.pem; do
    if [ -f "$cert_file" ]; then
        set_file_permissions "$cert_file" 644
    fi
done

echo ""

# Passo 6: Configurar ownership (apenas se root)
if [ "$IS_ROOT" = true ]; then
    echo -e "${YELLOW}Passo 6: Configurar ownership dos ficheiros...${NC}"
    
    # Alterar dono dos diretórios e ficheiros críticos para utilizador ca
    chown -R ca:ca "$PKI_DIR/root-ca/private"
    chown -R ca:ca "$PKI_DIR/intermediate-ca/private"
    chown -R ca:ca "$PKI_DIR/ssh-ca/private" 2>/dev/null || true
    chown ca:ca "$PKI_DIR/root-ca/index.txt" "$PKI_DIR/root-ca/serial" "$PKI_DIR/root-ca/index.txt.attr" 2>/dev/null || true
    chown ca:ca "$PKI_DIR/intermediate-ca/index.txt" "$PKI_DIR/intermediate-ca/serial" "$PKI_DIR/intermediate-ca/index.txt.attr" 2>/dev/null || true
    
    echo -e "${GREEN}  ✓ Ownership configurado para utilizador 'ca'${NC}"
    echo -e "${BLUE}  Nota: Apenas utilizador 'ca' e membros do grupo 'ca' podem aceder aos ficheiros privados${NC}"
else
    echo -e "${YELLOW}Passo 6: Configurar ownership...${NC}"
    echo -e "${BLUE}  ⚠ Pulado (não executado como root)${NC}"
    echo -e "${BLUE}  Para configurar ownership, execute: sudo ./scripts/setup-security.sh${NC}"
fi
echo ""

# Resumo
echo -e "${GREEN}=== Configuração de Segurança Concluída ===${NC}"
echo ""
echo "Resumo das permissões configuradas:"
echo "  - Diretórios privados: 700 (apenas dono)"
echo "  - Chaves privadas: 600 (apenas dono pode ler/escrever)"
echo "  - Base de dados (index.txt, serial): 644 (leitura para todos, escrita apenas dono)"
echo "  - Certificados públicos: 644 (leitura para todos)"
echo ""

if [ "$IS_ROOT" = true ]; then
    echo -e "${BLUE}Utilizador dedicado 'ca' criado e configurado.${NC}"
    echo -e "${BLUE}Para usar a PKI como utilizador 'ca':${NC}"
    echo -e "${BLUE}  sudo -u ca ./scripts/issue-server-cert.sh <hostname>${NC}"
else
    echo -e "${YELLOW}Nota: Para configuração completa com utilizador dedicado, execute como root:${NC}"
    echo -e "${YELLOW}  sudo ./scripts/setup-security.sh${NC}"
fi
echo ""
