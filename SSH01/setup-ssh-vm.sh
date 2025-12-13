#!/bin/bash

# Script para configurar OpenSSH server na VM Kali Linux
# Assignment 2 - SSH Remote Access Service
# Per Assignment 1: Ed25519 keys, VM-based deployment

set -e  # Parar se houver erro

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Configuração do Servidor SSH na VM Kali ===${NC}"
echo ""

# Verificar se está a executar como root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Erro: Este script deve ser executado como root (use sudo)${NC}"
    exit 1
fi

# Caminho para SSH CA public key (via shared folder)
# Ajustar este caminho conforme a localização do shared folder na VM
SHARED_FOLDER_PATH="${SHARED_FOLDER_PATH:-/mnt/shared}"
PKI_SSH_CA_PUB="$SHARED_FOLDER_PATH/Projeto_CC/pki/ssh-ca/certs/ssh-ca-key.pub"
SSH_CA_PUB_DEST="/etc/ssh/ca.pub"

echo -e "${YELLOW}Passo 1: Verificar/Instalar OpenSSH Server...${NC}"
if ! command -v sshd &> /dev/null; then
    echo -e "${BLUE}  OpenSSH server não encontrado. A instalar...${NC}"
    apt-get update
    apt-get install -y openssh-server
    echo -e "${GREEN}  ✓ OpenSSH server instalado${NC}"
else
    echo -e "${GREEN}  ✓ OpenSSH server já instalado${NC}"
fi
echo ""

echo -e "${YELLOW}Passo 2: Gerar chaves host SSH (Ed25519)...${NC}"
SSH_DIR="/etc/ssh"

# Gerar chave host Ed25519 se não existir (prioritária, per Assignment 1)
if [ ! -f "$SSH_DIR/ssh_host_ed25519_key" ]; then
    echo -e "${BLUE}  Gerando chave host Ed25519...${NC}"
    ssh-keygen -t ed25519 -f "$SSH_DIR/ssh_host_ed25519_key" -N "" -C "ssh01.org.local"
    chmod 600 "$SSH_DIR/ssh_host_ed25519_key"
    chmod 644 "$SSH_DIR/ssh_host_ed25519_key.pub"
    echo -e "${GREEN}  ✓ Chave host Ed25519 criada${NC}"
else
    echo -e "${GREEN}  ✓ Chave host Ed25519 já existe${NC}"
fi

# Gerar outras chaves host se não existirem (RSA, ECDSA para compatibilidade)
if [ ! -f "$SSH_DIR/ssh_host_rsa_key" ]; then
    echo -e "${BLUE}  Gerando chave host RSA...${NC}"
    ssh-keygen -t rsa -b 4096 -f "$SSH_DIR/ssh_host_rsa_key" -N "" -C "ssh01.org.local"
    chmod 600 "$SSH_DIR/ssh_host_rsa_key"
    chmod 644 "$SSH_DIR/ssh_host_rsa_key.pub"
    echo -e "${GREEN}  ✓ Chave host RSA criada${NC}"
fi

if [ ! -f "$SSH_DIR/ssh_host_ecdsa_key" ]; then
    echo -e "${BLUE}  Gerando chave host ECDSA...${NC}"
    ssh-keygen -t ecdsa -f "$SSH_DIR/ssh_host_ecdsa_key" -N "" -C "ssh01.org.local"
    chmod 600 "$SSH_DIR/ssh_host_ecdsa_key"
    chmod 644 "$SSH_DIR/ssh_host_ecdsa_key.pub"
    echo -e "${GREEN}  ✓ Chave host ECDSA criada${NC}"
fi
echo ""

echo -e "${YELLOW}Passo 3: Copiar SSH CA public key...${NC}"
if [ -f "$PKI_SSH_CA_PUB" ]; then
    cp "$PKI_SSH_CA_PUB" "$SSH_CA_PUB_DEST"
    chmod 644 "$SSH_CA_PUB_DEST"
    echo -e "${GREEN}  ✓ SSH CA public key copiada para $SSH_CA_PUB_DEST${NC}"
else
    echo -e "${YELLOW}  ⚠ SSH CA public key não encontrada em: $PKI_SSH_CA_PUB${NC}"
    echo -e "${YELLOW}  Por favor, copie manualmente:${NC}"
    echo -e "${BLUE}    cp <caminho-para>/pki/ssh-ca/certs/ssh-ca-key.pub $SSH_CA_PUB_DEST${NC}"
    echo -e "${YELLOW}  Ou defina SHARED_FOLDER_PATH antes de executar:${NC}"
    echo -e "${BLUE}    export SHARED_FOLDER_PATH=/caminho/para/shared/folder${NC}"
    echo -e "${BLUE}    sudo ./setup-ssh-vm.sh${NC}"
    read -p "Continuar sem SSH CA key? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo -e "${BLUE}Operação cancelada. Configure a SSH CA key primeiro.${NC}"
        exit 1
    fi
fi
echo ""

echo -e "${YELLOW}Passo 4: Configurar sshd_config...${NC}"
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_BACKUP="$SSHD_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"

# Fazer backup da configuração existente
cp "$SSHD_CONFIG" "$SSHD_CONFIG_BACKUP"
echo -e "${BLUE}  Backup criado: $SSHD_CONFIG_BACKUP${NC}"

# Configurações a adicionar/modificar
cat >> "$SSHD_CONFIG" << 'EOF'

# ============================================
# SSH Certificate Authentication Configuration
# Assignment 2 - SSH Remote Access Service
# ============================================

# Certificate authentication
TrustedUserCAKeys /etc/ssh/ca.pub

# Jump host features (port forwarding, tunneling)
AllowTcpForwarding yes
GatewayPorts no
PermitTunnel yes

# Security hardening
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey

# Host key algorithms (prioritize Ed25519 per Assignment 1)
HostKeyAlgorithms +ssh-ed25519,ssh-rsa,ecdsa-sha2-nistp256

# Additional security
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2

# Limit simultaneous sessions (per Assignment 2 requirement)
MaxSessions 5
MaxStartups 5:50:10

# Logging
SyslogFacility AUTH
LogLevel VERBOSE
EOF

echo -e "${GREEN}  ✓ sshd_config configurado${NC}"
echo ""

echo -e "${YELLOW}Passo 5: Verificar configuração...${NC}"
if sshd -t; then
    echo -e "${GREEN}  ✓ Configuração sshd_config válida${NC}"
else
    echo -e "${RED}  ✗ Erro na configuração sshd_config!${NC}"
    echo -e "${YELLOW}  Restaurando backup...${NC}"
    cp "$SSHD_CONFIG_BACKUP" "$SSHD_CONFIG"
    exit 1
fi
echo ""

echo -e "${YELLOW}Passo 6: Configurar permissões...${NC}"
chmod 600 /etc/ssh/ssh_host_*_key
chmod 644 /etc/ssh/ssh_host_*_key.pub
chmod 644 /etc/ssh/ca.pub 2>/dev/null || true
chmod 644 "$SSHD_CONFIG"
echo -e "${GREEN}  ✓ Permissões configuradas${NC}"
echo ""

echo -e "${YELLOW}Passo 6.5: Gerar checksum SHA-256 para ficheiros de configuração SSH...${NC}"
# Gerar checksums para ficheiros de configuração SSH (per Assignment 2: integrity control)
SSH_CHECKSUMS_DIR="/etc/ssh/.checksums"
mkdir -p "$SSH_CHECKSUMS_DIR"
chmod 700 "$SSH_CHECKSUMS_DIR"

# Gerar checksum do sshd_config
if [ -f "$SSHD_CONFIG" ]; then
    sha256sum "$SSHD_CONFIG" > "$SSH_CHECKSUMS_DIR/sshd_config.sha256"
    chmod 600 "$SSH_CHECKSUMS_DIR/sshd_config.sha256"
    echo -e "${GREEN}  ✓ Checksum SHA-256 gerado para sshd_config${NC}"
    echo -e "${BLUE}    Ficheiro: $SSH_CHECKSUMS_DIR/sshd_config.sha256${NC}"
fi

# Gerar checksum da SSH CA public key
if [ -f "$SSH_CA_PUB_DEST" ]; then
    sha256sum "$SSH_CA_PUB_DEST" > "$SSH_CHECKSUMS_DIR/ca.pub.sha256"
    chmod 600 "$SSH_CHECKSUMS_DIR/ca.pub.sha256"
    echo -e "${GREEN}  ✓ Checksum SHA-256 gerado para ca.pub${NC}"
    echo -e "${BLUE}    Ficheiro: $SSH_CHECKSUMS_DIR/ca.pub.sha256${NC}"
fi

echo -e "${BLUE}  Nota: Para verificar integridade, execute:${NC}"
echo -e "${BLUE}    sha256sum -c $SSH_CHECKSUMS_DIR/sshd_config.sha256${NC}"
echo ""

echo -e "${YELLOW}Passo 7: Habilitar e iniciar serviço SSH...${NC}"
systemctl enable ssh
systemctl restart ssh
if systemctl is-active --quiet ssh; then
    echo -e "${GREEN}  ✓ Serviço SSH iniciado e habilitado${NC}"
else
    echo -e "${RED}  ✗ Erro ao iniciar serviço SSH${NC}"
    systemctl status ssh
    exit 1
fi
echo ""

echo -e "${GREEN}=== Configuração SSH concluída com sucesso! ===${NC}"
echo ""
echo "Resumo:"
echo "  - OpenSSH server: Instalado e configurado"
echo "  - Host keys: Ed25519, RSA, ECDSA geradas"
echo "  - SSH CA: $SSH_CA_PUB_DEST"
echo "  - Autenticação: Apenas certificados SSH (sem password)"
echo "  - Jump host: Habilitado (port forwarding, tunneling)"
echo ""
echo "Próximos passos:"
echo "  1. Gerar certificado de utilizador no HOST:"
echo "     cd pki/ssh-ca && ./scripts/issue-ssh-user-cert.sh admin"
echo "  2. Testar conexão do HOST:"
echo "     ssh -i pki/ssh-ca/user-certs/admin-key -i pki/ssh-ca/user-certs/admin-cert.pub admin@<vm-ip>"
echo ""
