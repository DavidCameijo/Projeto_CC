#!/bin/bash

# Script para verificar integridade dos ficheiros de configuração SSH
# Assignment 2 - SSH Remote Access Service
# Política: "The configuration files of the SSH service should have mechanisms to check integrity control"

set -e  # Parar se houver erro

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Verificação de Integridade dos Ficheiros SSH ===${NC}"
echo ""

# Verificar se está a executar como root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Erro: Este script deve ser executado como root (use sudo)${NC}"
    exit 1
fi

SSH_CHECKSUMS_DIR="/etc/ssh/.checksums"
SSHD_CONFIG="/etc/ssh/sshd_config"
SSH_CA_PUB="/etc/ssh/ca.pub"

# Verificar se diretório de checksums existe
if [ ! -d "$SSH_CHECKSUMS_DIR" ]; then
    echo -e "${RED}Erro: Diretório de checksums não encontrado!${NC}"
    echo -e "${YELLOW}Execute primeiro o script setup-ssh-vm.sh${NC}"
    exit 1
fi

echo -e "${YELLOW}Verificando integridade dos ficheiros de configuração SSH...${NC}"
echo ""

# Verificar sshd_config
if [ -f "$SSH_CHECKSUMS_DIR/sshd_config.sha256" ]; then
    echo -e "${BLUE}Verificando sshd_config...${NC}"
    if sha256sum -c "$SSH_CHECKSUMS_DIR/sshd_config.sha256" > /dev/null 2>&1; then
        echo -e "${GREEN}  ✓ sshd_config: OK (íntegro)${NC}"
    else
        echo -e "${RED}  ✗ sshd_config: ALTERADO (integridade comprometida!)${NC}"
        echo -e "${YELLOW}  ⚠ ATENÇÃO: O ficheiro sshd_config foi modificado!${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}  ⚠ Checksum de sshd_config não encontrado${NC}"
fi

# Verificar SSH CA public key
if [ -f "$SSH_CHECKSUMS_DIR/ca.pub.sha256" ]; then
    echo -e "${BLUE}Verificando ca.pub...${NC}"
    if sha256sum -c "$SSH_CHECKSUMS_DIR/ca.pub.sha256" > /dev/null 2>&1; then
        echo -e "${GREEN}  ✓ ca.pub: OK (íntegro)${NC}"
    else
        echo -e "${RED}  ✗ ca.pub: ALTERADO (integridade comprometida!)${NC}"
        echo -e "${YELLOW}  ⚠ ATENÇÃO: O ficheiro ca.pub foi modificado!${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}  ⚠ Checksum de ca.pub não encontrado${NC}"
fi

echo ""
echo -e "${GREEN}=== Verificação de Integridade Concluída ===${NC}"
echo -e "${GREEN}✓ Todos os ficheiros de configuração SSH estão íntegros!${NC}"
echo ""
echo -e "${BLUE}Para atualizar checksums após alterações legítimas:${NC}"
echo -e "${BLUE}  sudo sha256sum /etc/ssh/sshd_config > /etc/ssh/.checksums/sshd_config.sha256${NC}"
echo ""
