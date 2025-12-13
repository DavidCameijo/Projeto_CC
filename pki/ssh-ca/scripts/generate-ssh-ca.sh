#!/bin/bash

# Script para gerar SSH CA key pair (Ed25519)
# Assignment 2 - SSH Remote Access Service
# Per Assignment 1, page 9: "Ed25519 recommended"

set -e  # Parar se houver erro

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Diretório base (onde está este script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_CA_DIR="$(dirname "$SCRIPT_DIR")"  # ssh-ca/ (pai de scripts/)

echo -e "${GREEN}=== Geração da SSH CA (Ed25519) ===${NC}"
echo "Diretório SSH CA: $SSH_CA_DIR"
echo ""

# Verificar se o diretório ssh-ca existe
if [ ! -d "$SSH_CA_DIR" ]; then
    echo -e "${RED}Erro: Diretório $SSH_CA_DIR não existe!${NC}"
    echo "Criando estrutura de diretórios..."
    mkdir -p "$SSH_CA_DIR/private" "$SSH_CA_DIR/certs" "$SSH_CA_DIR/user-certs"
fi

# Verificar se já existe chave privada SSH CA
if [ -f "$SSH_CA_DIR/private/ssh-ca-key" ]; then
    echo -e "${YELLOW}⚠ Atenção: SSH CA key já existe!${NC}"
    echo -e "${YELLOW}  Ficheiro: $SSH_CA_DIR/private/ssh-ca-key${NC}"
    read -p "Deseja sobrescrever? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo -e "${BLUE}Operação cancelada.${NC}"
        exit 0
    fi
    echo -e "${YELLOW}Removendo chave antiga...${NC}"
    rm -f "$SSH_CA_DIR/private/ssh-ca-key"
    rm -f "$SSH_CA_DIR/private/ssh-ca-key.pub"
    rm -f "$SSH_CA_DIR/certs/ssh-ca-key.pub"
fi

# Mudar para o diretório ssh-ca
cd "$SSH_CA_DIR"

echo -e "${YELLOW}Passo 1: Gerar SSH CA key pair Ed25519...${NC}"
echo -e "${BLUE}  Algoritmo: Ed25519 (per Assignment 1, page 9: 'Ed25519 recommended')${NC}"
echo ""

# Gerar SSH CA key pair usando ssh-keygen com Ed25519
# -t ed25519: tipo de chave Ed25519
# -f: ficheiro de output
# -N "": sem passphrase (pode ser configurado depois se necessário)
# -C: comentário identificando como SSH CA
ssh-keygen -t ed25519 \
    -f private/ssh-ca-key \
    -N "" \
    -C "SSH CA - Assignment 2"

# Copiar chave pública para certs/ para distribuição
cp private/ssh-ca-key.pub certs/ssh-ca-key.pub

# Configurar permissões
chmod 600 private/ssh-ca-key
chmod 644 private/ssh-ca-key.pub
chmod 644 certs/ssh-ca-key.pub

echo -e "${GREEN}  ✓ SSH CA private key criada: private/ssh-ca-key${NC}"
echo -e "${GREEN}  ✓ SSH CA public key criada: certs/ssh-ca-key.pub${NC}"
echo ""

echo -e "${YELLOW}Passo 2: Verificar SSH CA key gerada...${NC}"
echo ""

# Verificar fingerprint da chave
FINGERPRINT=$(ssh-keygen -l -f private/ssh-ca-key.pub)
echo -e "${BLUE}  Fingerprint: $FINGERPRINT${NC}"

# Verificar tipo de chave
KEY_TYPE=$(ssh-keygen -l -f private/ssh-ca-key.pub | awk '{print $4}')
if [[ "$KEY_TYPE" == "ED25519" ]]; then
    echo -e "${GREEN}  ✓ Tipo de chave confirmado: Ed25519${NC}"
else
    echo -e "${RED}  ✗ Erro: Tipo de chave inesperado: $KEY_TYPE${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}=== SSH CA gerada com sucesso! ===${NC}"
echo ""
echo "Ficheiros criados:"
echo "  - $SSH_CA_DIR/private/ssh-ca-key (chave privada - guardar em segurança!)"
echo "  - $SSH_CA_DIR/certs/ssh-ca-key.pub (chave pública - distribuir para servidores SSH)"
echo ""
echo "Próximos passos:"
echo "  1. Copiar $SSH_CA_DIR/certs/ssh-ca-key.pub para /etc/ssh/ca.pub no servidor SSH"
echo "  2. Configurar sshd_config com: TrustedUserCAKeys /etc/ssh/ca.pub"
echo "  3. Gerar certificados de utilizador: ./scripts/issue-ssh-user-cert.sh <username>"
echo ""
