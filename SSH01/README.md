# SSH Remote Access Service - Setup na VM Kali

Este documento descreve como configurar o servidor SSH na VM Kali Linux para usar autenticação baseada em certificados PKI.

## Requisitos

- VM Kali Linux (já criada)
- Shared folder configurado entre host e VM
- Acesso root/sudo na VM
- SSH CA já gerada (ver `pki/ssh-ca/scripts/generate-ssh-ca.sh`)

## Estrutura

```
SSH01/
├── setup-ssh-vm.sh         # Script de configuração (executar na VM)
├── verify-ssh-integrity.sh # Script de verificação de integridade (executar na VM)
├── sshd_config              # Template de configuração (referência)
└── README.md                # Este ficheiro
```

## Passos de Configuração

### 1. No HOST (Linux)

Primeiro, gerar a SSH CA e certificado de administrador:

```bash
cd Projeto_CC/pki/ssh-ca

# Gerar SSH CA (se ainda não foi feito)
./scripts/generate-ssh-ca.sh

# Gerar certificado para utilizador admin
./scripts/issue-ssh-user-cert.sh admin
```

### 2. Na VM (Kali Linux)

#### 2.1. Aceder à VM e localizar shared folder

```bash
# Na VM, encontrar o caminho do shared folder
# Exemplo comum: /mnt/shared ou /media/sf_shared
ls /mnt/  # ou ls /media/
```

#### 2.2. Configurar caminho do shared folder (se necessário)

Se o caminho do shared folder for diferente de `/mnt/shared`, defina a variável:

```bash
export SHARED_FOLDER_PATH=/caminho/para/shared/folder
```

#### 2.3. Executar script de configuração

```bash
# Na VM, navegar para o diretório SSH01 via shared folder
cd /caminho/para/shared/folder/Projeto_CC/SSH01

# Executar script de configuração (requer sudo)
sudo ./setup-ssh-vm.sh
```

O script irá:
- Instalar OpenSSH server (se necessário)
- Gerar chaves host SSH (Ed25519 prioritária, per Assignment 1)
- Copiar SSH CA public key para `/etc/ssh/ca.pub`
- Configurar `sshd_config` para autenticação por certificados
- Habilitar funcionalidades de jump host
- Iniciar serviço SSH

### 3. Verificar Configuração

Na VM:

```bash
# Verificar se SSH está a correr
sudo systemctl status ssh

# Verificar configuração
sudo sshd -t

# Verificar se SSH CA key está presente
ls -l /etc/ssh/ca.pub

# Verificar integridade dos ficheiros de configuração (per Assignment 2)
sudo /caminho/para/shared/folder/Projeto_CC/SSH01/verify-ssh-integrity.sh
```

### 4. Testar Conexão (do HOST)

Do HOST Linux:

```bash
cd Projeto_CC/pki/ssh-ca

# Conectar usando certificado
ssh -i user-certs/admin-key \
    -i user-certs/admin-cert.pub \
    admin@<ip-da-vm>
```

Ou configurar `~/.ssh/config` no HOST:

```
Host ssh01
    HostName <ip-da-vm>
    User admin
    IdentityFile /caminho/para/Projeto_CC/pki/ssh-ca/user-certs/admin-key
    CertificateFile /caminho/para/Projeto_CC/pki/ssh-ca/user-certs/admin-cert.pub
```

Depois conectar simplesmente com:
```bash
ssh ssh01
```

## Funcionalidades Configuradas

### Autenticação por Certificados

- Apenas utilizadores com certificados SSH válidos podem autenticar
- Password authentication desabilitada
- Root login desabilitado

### Jump Host

- Port forwarding habilitado (`AllowTcpForwarding yes`)
- Tunneling habilitado (`PermitTunnel yes`)
- Permite usar ssh01 como bastion/jump host para aceder à rede interna

### Segurança

- Host keys: Ed25519 (prioritária), RSA, ECDSA
- Logging verboso para auditoria
- Limites de tentativas de autenticação
- Timeout de conexões inativas
- **Integridade de configuração**: Checksums SHA-256 para `sshd_config` e `ca.pub` (per Assignment 2)
- **Limite de sessões**: Máximo 5 sessões simultâneas (per Assignment 2)

## Troubleshooting

### Erro: "SSH CA public key não encontrada"

**Causa:** O caminho do shared folder não está correto.

**Solução:**
1. Verificar caminho do shared folder na VM
2. Definir `SHARED_FOLDER_PATH` antes de executar o script:
   ```bash
   export SHARED_FOLDER_PATH=/caminho/correto
   sudo ./setup-ssh-vm.sh
   ```
3. Ou copiar manualmente:
   ```bash
   sudo cp /caminho/para/shared/folder/Projeto_CC/pki/ssh-ca/certs/ssh-ca-key.pub /etc/ssh/ca.pub
   ```

### Erro: "sshd_config inválido"

**Causa:** Erro de sintaxe na configuração.

**Solução:**
- O script faz backup automático: `/etc/ssh/sshd_config.backup.*`
- Restaurar backup se necessário:
  ```bash
  sudo cp /etc/ssh/sshd_config.backup.* /etc/ssh/sshd_config
  sudo systemctl restart ssh
  ```

### Erro: "Permission denied" ao conectar

**Causa:** Certificado inválido ou utilizador não existe.

**Solução:**
1. Verificar que o certificado foi gerado corretamente
2. Verificar que o utilizador existe na VM:
   ```bash
   sudo useradd -m -s /bin/bash admin  # se necessário
   ```
3. Verificar que a SSH CA key está em `/etc/ssh/ca.pub` na VM

### Serviço SSH não inicia

**Causa:** Erro na configuração ou porta já em uso.

**Solução:**
```bash
# Ver logs
sudo journalctl -u ssh -n 50

# Verificar se porta 22 está em uso
sudo netstat -tlnp | grep :22

# Testar configuração
sudo sshd -t
```

## Segurança

- **Chaves privadas:** Nunca copiar chaves privadas para a VM
- **SSH CA:** Apenas a chave pública da SSH CA deve estar na VM
- **Permissões:** O script configura permissões corretas automaticamente
- **Backup:** Backup automático de `sshd_config` antes de modificar

## Referências

- Assignment 1: Ed25519 keys, VM-based deployment
- Assignment 2: PKI-based authentication, jump host functionality
- OpenSSH Documentation: https://www.openssh.com/manual.html
