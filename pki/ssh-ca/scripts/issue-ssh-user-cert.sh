#!/bin/bash

# Script para emitir certificados SSH de utilizador assinados pela SSH CA
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
USER_CERTS_DIR="$SSH_CA_DIR/user-certs"

# Verificar argumentos
if [ $# -eq 0 ]; then
    echo -e "${RED}Erro: Username não fornecido!${NC}"
    echo ""
    echo "Uso: $0 <username> [validity_days]"
    echo "Exemplo: $0 admin"
    echo "Exemplo: $0 admin 365"
    exit 1
fi

USERNAME=$1
VALIDITY_DAYS=${2:-365}  # Default: 1 ano

# Validar username básico
if [[ ! "$USERNAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo -e "${RED}Erro: Username inválido: $USERNAME${NC}"
    echo "Username deve conter apenas letras, números, underscore e hífen"
    exit 1
fi

echo -e "${GREEN}=== Emissão de Certificado SSH para Utilizador ===${NC}"
echo "Username: $USERNAME"
echo "Validade: $VALIDITY_DAYS dias"
echo "Diretório SSH CA: $SSH_CA_DIR"
echo ""

# Verificar se SSH CA existe
if [ ! -f "$SSH_CA_DIR/private/ssh-ca-key" ]; then
    echo -e "${RED}Erro: SSH CA não encontrada!${NC}"
    echo "Execute primeiro: ./scripts/generate-ssh-ca.sh"
    exit 1
fi

# Verificar se já existe chave de utilizador
USER_KEY="$USER_CERTS_DIR/$USERNAME-key"
USER_PUB="$USER_CERTS_DIR/$USERNAME-key.pub"
USER_CERT="$USER_CERTS_DIR/$USERNAME-cert.pub"

if [ -f "$USER_KEY" ]; then
    echo -e "${YELLOW}⚠ Atenção: Chave de utilizador já existe!${NC}"
    echo -e "${YELLOW}  Ficheiro: $USER_KEY${NC}"
    read -p "Deseja gerar nova chave? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo -e "${BLUE}Usando chave existente...${NC}"
        USE_EXISTING=true
    else
        USE_EXISTING=false
        rm -f "$USER_KEY" "$USER_PUB" "$USER_CERT"
    fi
else
    USE_EXISTING=false
fi

# Mudar para o diretório user-certs
cd "$USER_CERTS_DIR"

if [ "$USE_EXISTING" = false ]; then
    echo -e "${YELLOW}Passo 1: Gerar chave de utilizador Ed25519...${NC}"
    echo -e "${BLUE}  Algoritmo: Ed25519 (per Assignment 1)${NC}"
    echo ""
    
    # Gerar chave de utilizador Ed25519
    ssh-keygen -t ed25519 \
        -f "$USERNAME-key" \
        -N "" \
        -C "$USERNAME@org.local"
    
    chmod 600 "$USERNAME-key"
    chmod 644 "$USERNAME-key.pub"
    
    echo -e "${GREEN}  ✓ Chave de utilizador criada: $USERNAME-key${NC}"
    echo ""
else
    echo -e "${BLUE}Passo 1: Usando chave de utilizador existente...${NC}"
    echo ""
fi

echo -e "${YELLOW}Passo 2: Assinar chave pública com SSH CA...${NC}"
echo -e "${BLUE}  Validade: $VALIDITY_DAYS dias${NC}"
echo -e "${BLUE}  Principals: $USERNAME${NC}"
echo ""

# Calcular timestamp de expiração
EXPIRE_TIME=$(date -d "+$VALIDITY_DAYS days" +%s)

# Assinar chave pública com SSH CA
# -s: chave privada da CA
# -I: ID do certificado (username)
# -n: principals (usernames permitidos)
# -V: validade (from:to)
# -z: número de série (opcional, usar timestamp)
# Extensions para jump host:
#   permit-pty: permite PTY (terminal interativo)
#   permit-port-forwarding: permite port forwarding (necessário para jump host)
#   permit-X11-forwarding: permite X11 forwarding
ssh-keygen -s "$SSH_CA_DIR/private/ssh-ca-key" \
    -I "$USERNAME-cert" \
    -n "$USERNAME" \
    -V "+0d:$VALIDITY_DAYS" \
    -z "$(date +%s)" \
    -O permit-pty \
    -O permit-port-forwarding \
    -O permit-X11-forwarding \
    "$USERNAME-key.pub"

# Renomear certificado gerado (ssh-keygen adiciona -cert.pub ao nome)
mv "$USERNAME-key-cert.pub" "$USERNAME-cert.pub"
chmod 644 "$USERNAME-cert.pub"

echo -e "${GREEN}  ✓ Certificado criado: $USERNAME-cert.pub${NC}"
echo ""

echo -e "${YELLOW}Passo 3: Verificar certificado gerado...${NC}"
echo ""

# Verificar certificado
CERT_INFO=$(ssh-keygen -L -f "$USERNAME-cert.pub")
echo -e "${BLUE}Informações do certificado:${NC}"
echo "$CERT_INFO" | head -20
echo ""

# Verificar validade
VALID_FROM=$(echo "$CERT_INFO" | grep "Valid:" | awk '{print $2}')
VALID_TO=$(echo "$CERT_INFO" | grep "Valid:" | awk '{print $3}')
echo -e "${GREEN}  ✓ Válido de: $VALID_FROM até: $VALID_TO${NC}"

# Verificar principals
PRINCIPALS=$(echo "$CERT_INFO" | grep "Principals:" | awk '{print $2}')
if [[ "$PRINCIPALS" == "$USERNAME" ]]; then
    echo -e "${GREEN}  ✓ Principal correto: $PRINCIPALS${NC}"
else
    echo -e "${RED}  ✗ Erro: Principal incorreto: $PRINCIPALS (esperado: $USERNAME)${NC}"
    exit 1
fi

# Verificar tipo de chave
KEY_TYPE=$(ssh-keygen -l -f "$USERNAME-cert.pub" | awk '{print $4}')
if [[ "$KEY_TYPE" == "ED25519" ]]; then
    echo -e "${GREEN}  ✓ Tipo de chave confirmado: Ed25519${NC}"
else
    echo -e "${YELLOW}  ⚠ Tipo de chave: $KEY_TYPE${NC}"
fi

echo ""
echo -e "${GREEN}=== Certificado SSH gerado com sucesso! ===${NC}"
echo ""
echo "Ficheiros criados:"
echo "  - $USERNAME-key (chave privada - guardar em segurança!)"
echo "  - $USERNAME-key.pub (chave pública)"
echo "  - $USERNAME-cert.pub (certificado SSH - usar para autenticação)"
echo ""
echo "Para conectar usando o certificado:"
echo "  ssh -i $USER_CERTS_DIR/$USERNAME-key -i $USER_CERTS_DIR/$USERNAME-cert.pub $USERNAME@<server-ip>"
echo ""
echo "Ou configurar no ~/.ssh/config:"
echo "  Host ssh01"
echo "    HostName <server-ip>"
echo "    User $USERNAME"
echo "    IdentityFile $USER_CERTS_DIR/$USERNAME-key"
echo "    CertificateFile $USER_CERTS_DIR/$USERNAME-cert.pub"
echo ""
