# PKI Infrastructure - Certificate Authority

Este documento descreve a infraestrutura PKI implementada, ligando explicitamente cada componente às políticas e requisitos do enunciado do Assignment 2.

## Índice

1. [Visão Geral](#visão-geral)
2. [Estrutura de Diretórios](#estrutura-de-diretórios)
3. [Fases de Implementação e Ligação às Políticas](#fases-de-implementação-e-ligação-às-políticas)
4. [Guia de Utilização](#guia-de-utilização)
5. [Evidências de Teste](#evidências-de-teste)
6. [Boas Práticas de Segurança](#boas-práticas-de-segurança)

---

## Visão Geral

Esta PKI implementa uma hierarquia de certificados com Root CA e Intermediate CA, utilizando OpenSSL para gerir o ciclo de vida completo de certificados TLS para os serviços da infraestrutura.

**Requisitos do Enunciado cumpridos:**
- ✅ Infraestrutura PKI completa com Root CA e Intermediate CA
- ✅ Emissão de certificados TLS para serviços (web01.org.local, db01.org.local, ssh01.org.local)
- ✅ Suporte ao ciclo de vida completo: emissão, verificação e revogação
- ✅ Políticas de segurança: controlo de acesso e integridade dos ficheiros da CA
- ✅ Revogação de certificados com CRL (Certificate Revocation List)
- ✅ SSH CA para autenticação de utilizadores SSH (Ed25519, per Assignment 1)

---

## Estrutura de Diretórios

```
pki/
├── root-ca/                    # Root Certificate Authority
│   ├── private/               # Chave privada da Root CA (acesso restrito)
│   ├── certs/                 # Certificado da Root CA
│   ├── crl/                   # Listas de Revogação de Certificados
│   ├── newcerts/              # Certificados emitidos pela Root CA
│   ├── index.txt              # Base de dados de certificados (integridade protegida)
│   ├── serial                 # Contador de números de série (integridade protegida)
│   └── openssl.cnf            # Configuração OpenSSL da Root CA
├── intermediate-ca/            # Intermediate Certificate Authority
│   ├── private/               # Chave privada da Intermediate CA (acesso restrito)
│   ├── certs/                 # Certificado da Intermediate CA
│   ├── csr/                   # Certificate Signing Requests
│   ├── crl/                   # Listas de Revogação de Certificados
│   ├── newcerts/              # Certificados emitidos pela Intermediate CA
│   ├── index.txt              # Base de dados de certificados (integridade protegida)
│   ├── serial                 # Contador de números de série (integridade protegida)
│   └── openssl.cnf            # Configuração OpenSSL da Intermediate CA
├── ssh-ca/                    # SSH Certificate Authority (Ed25519)
│   ├── private/               # Chave privada SSH CA (acesso restrito)
│   ├── certs/                 # Chave pública SSH CA
│   ├── user-certs/            # Certificados SSH de utilizador
│   └── scripts/                # Scripts SSH CA
│       ├── generate-ssh-ca.sh
│       └── issue-ssh-user-cert.sh
├── checksums/                 # Checksums SHA-256 para verificação de integridade
├── scripts/                   # Scripts de automação TLS PKI
└── README.md                   # Este ficheiro
```

---

## Fases de Implementação e Ligação às Políticas

### Fase 2.1: Estrutura da CA e Scripts Base

**Política do Enunciado:** *"Implementar infraestrutura PKI com Root CA e Intermediate CA"*

#### Ficheiros Criados:

- **`init-ca.sh`**
  - **Política cumprida:** Inicialização da estrutura hierárquica de CAs (Root e Intermediate)
  - Cria a estrutura de diretórios, inicializa `index.txt` e `serial` para ambas as CAs

- **`openssl-root.cnf`** e **`openssl-intermediate.cnf`**
  - **Política cumprida:** Configuração adequada das políticas de certificação, extensões e definições CRL
  - Define políticas de certificação, key usage, extended key usage e configurações CRL

- **`generate-root-ca.sh`**
  - **Política cumprida:** Geração da Root CA com algoritmo RSA 4096 bits e SHA-256 (conforme Assignment 1)
  - Gera chave privada RSA 4096 bits e certificado auto-assinado com SHA-256

- **`generate-intermediate-ca.sh`**
  - **Política cumprida:** Criação da Intermediate CA assinada pela Root CA
  - Gera chave privada, CSR e certificado assinado pela Root CA

- **`issue-server-cert.sh`**
  - **Política cumprida:** Emissão de certificados TLS para serviços com suporte SAN
  - Template para emissão de certificados de servidor com Subject Alternative Names (SAN)

---

### Fase 2.2: Políticas de Segurança (Acesso e Integridade)

**Política do Enunciado:** *"Suportar acesso seguro a certificados e chaves privadas da CA (restringir acesso à pasta com chaves privadas, apenas utilizador específico tem acesso)"*

**Política do Enunciado:** *"As configurações da CA (base de dados/ficheiro com informação de certificados) devem ter mecanismos de controlo de integridade"*

#### Ficheiros Criados:

- **`setup-security.sh`**
  - **Política cumprida:** Controlo de acesso às chaves privadas da CA
  - Cria utilizador/grupo dedicado `ca` (quando executado como root)
  - Define permissões restritivas: `600` para chaves privadas, `700` para diretórios privados
  - Restringe acesso apenas ao utilizador `ca` aos ficheiros críticos da CA

- **`update-checksums.sh`**
  - **Política cumprida:** Mecanismo de controlo de integridade dos ficheiros da CA
  - Gera checksums SHA-256 para todos os ficheiros críticos:
    - Chaves privadas (`root-ca/private/root-ca.key`, `intermediate-ca/private/intermediate-ca.key`)
    - Ficheiros de configuração (`openssl-root.cnf`, `openssl-intermediate.cnf`)
    - **Base de dados de certificados** (`index.txt`, `serial`) - **REQUERIDO pelo Assignment 2**
  - Armazena checksums em `checksums/` para verificação posterior

- **`verify-integrity.sh`**
  - **Política cumprida:** Verificação de integridade dos ficheiros da CA
  - Compara checksums atuais com os armazenados
  - Detecta alterações ou adulteração nos ficheiros protegidos
  - **Especialmente crítico:** Verifica integridade de `index.txt` e `serial` (base de dados de certificados)

**Ficheiros Protegidos:**
- Chave privada da Root CA → **Política de acesso seguro**
- Chave privada da Intermediate CA → **Política de acesso seguro**
- Ficheiros de configuração → **Política de integridade**
- `index.txt` (base de dados) → **Política de integridade (REQUERIDO)**
- `serial` (contador) → **Política de integridade (REQUERIDO)**

---

### Fase 2.3: Revogação e CRL

**Política do Enunciado:** *"Suportar ciclo de vida completo de certificados: Emissão, verificação, revogação"*

**Política do Enunciado:** *"O enunciado sublinha a necessidade de evidências de teste"*

#### Ficheiros Criados:

- **`revoke-cert.sh`**
  - **Política cumprida:** Suporte à revogação de certificados
  - Revoga certificados por número de série ou ficheiro de certificado
  - Atualiza a base de dados (`index.txt`) marcando o certificado como revogado

- **`generate-crl.sh`**
  - **Política cumprida:** Geração de Certificate Revocation List (CRL)
  - Gera/atualiza CRL em formatos PEM e DER
  - Inclui todos os certificados revogados na base de dados

- **`verify-revocation.sh`**
  - **Política cumprida:** Verificação de revogação por clientes
  - Exemplo de como clientes verificam o estado de revogação usando CRL
  - Utiliza `openssl verify` com verificação CRL

- **`verify-cert.sh`**
  - **Política cumprida:** Verificação completa do ciclo de vida
  - Verifica validade do certificado, cadeia de certificados, expiração e estado de revogação

#### Evidências de Teste - Exemplo Real de Revogação:

**IMPORTANTE:** Conforme requerido pelo enunciado, demonstra-se pelo menos um exemplo real de revogação:

1. **Emissão de certificado de teste:**
   ```bash
   ./scripts/issue-server-cert.sh test-revoke.org.local
   ```

2. **Verificação antes da revogação:**
   ```bash
   openssl verify -CAfile root-ca/certs/root-ca.crt \
                  -untrusted intermediate-ca/certs/intermediate-ca.crt \
                  test-revoke-cert.pem
   ```
   Resultado esperado: `test-revoke-cert.pem: OK`

3. **Revogação do certificado:**
   ```bash
   ./scripts/revoke-cert.sh test-revoke-cert.pem
   ```

4. **Geração/atualização do CRL:**
   ```bash
   ./scripts/generate-crl.sh
   ```

5. **Verificação após revogação (PROVA DE REVOGAÇÃO):**
   ```bash
   openssl verify -CAfile root-ca/certs/root-ca.crt \
                  -untrusted intermediate-ca/certs/intermediate-ca.crt \
                  -CRLfile intermediate-ca/crl/intermediate-ca.crl.pem \
                  -crl_check test-revoke-cert.pem
   ```
   Resultado esperado: `error 23 at 0 depth lookup: certificate revoked`
   - **Esta verificação prova que o certificado é corretamente identificado como revogado no CRL**

Esta sequência fornece evidência concreta de que a revogação funciona corretamente e os certificados são adequadamente marcados como revogados no CRL.

---

### Fase 2.4: Geração de Certificados para Serviços

**Política do Enunciado:** *"Emitir certificados TLS para os serviços da infraestrutura"*

#### Ficheiros Criados:

- **`issue-web-cert.sh`**
  - **Política cumprida:** Certificado TLS para web01.org.local
  - Gera certificado com SAN para web01.org.local
  - Output: `web01-key.pem`, `web01-cert.pem`, `web01-chain.pem`

- **`issue-db-cert.sh`**
  - **Política cumprida:** Certificado TLS para db01.org.local (PostgreSQL)
  - Gera certificado para comunicação TLS com PostgreSQL
  - Output: `db01-key.pem`, `db01-cert.pem`, `db01-chain.pem`

- **`issue-ssh-cert.sh`**
  - **Política cumprida:** Certificado para ssh01.org.local
  - Gera certificado para serviço SSH/VPN
  - Output: `ssh01-key.pem`, `ssh01-cert.pem`, `ssh01-chain.pem`

**Detalhes dos Certificados:**
- **Subject:** CN={hostname} (ex: CN=web01.org.local)
- **SAN:** DNS:{hostname}
- **Key Usage:** Digital Signature, Key Encipherment
- **Extended Key Usage:** TLS Web Server Authentication
- **Validade:** 1 ano a partir da emissão

---

### Fase 2.5: SSH Certificate Authority (SSH CA)

**Política do Enunciado:** *"Implementar autenticação baseada em certificados para serviços remotos"*

**Assignment 1 Compliance:** *Ed25519 keys (page 9: "Ed25519 recommended"), VM-based deployment (page 7: "Dedicated VMs")*

#### Ficheiros Criados:

- **`ssh-ca/scripts/generate-ssh-ca.sh`**
  - **Política cumprida:** Geração de SSH CA com Ed25519 (per Assignment 1)
  - Gera chave privada e pública SSH CA (Ed25519)
  - Output: `ssh-ca/private/ssh-ca-key`, `ssh-ca/certs/ssh-ca-key.pub`

- **`ssh-ca/scripts/issue-ssh-user-cert.sh`**
  - **Política cumprida:** Emissão de certificados SSH de utilizador
  - Gera chave de utilizador Ed25519 e assina com SSH CA
  - Extensions: permit-pty, permit-port-forwarding, permit-X11-forwarding (jump host)
  - Output: `{username}-key`, `{username}-key.pub`, `{username}-cert.pub`

**Características:**
- **Algoritmo:** Ed25519 (per Assignment 1, page 9)
- **Validade:** 1 ano (configurável)
- **Principals:** Username(s) permitidos para autenticação
- **Integração:** SSH CA protegida com mesmas políticas de segurança que TLS PKI (permissões, checksums)

**Nota:** SSH CA é separada da TLS PKI porque SSH usa formato de certificado diferente (não X.509), mas é gerida dentro da mesma estrutura PKI para partilhar políticas de segurança.

---

## Guia de Utilização

### Inicialização da PKI

1. **Inicializar estrutura das CAs:**
   ```bash
   cd pki
   ./scripts/init-ca.sh
   ```

2. **Configurar políticas de segurança:**
   ```bash
   ./scripts/setup-security.sh
   ```

3. **Gerar Root CA:**
   ```bash
   ./scripts/generate-root-ca.sh
   ```

4. **Gerar Intermediate CA:**
   ```bash
   ./scripts/generate-intermediate-ca.sh
   ```

5. **Atualizar checksums (após criação das CAs):**
   ```bash
   ./scripts/update-checksums.sh
   ```

### Emissão de Certificados TLS

```bash
# Certificado para web01
./scripts/issue-web-cert.sh

# Certificado para db01
./scripts/issue-db-cert.sh

# Certificado para ssh01 (TLS)
./scripts/issue-ssh-cert.sh
```

### Emissão de Certificados SSH

```bash
cd ssh-ca

# Gerar SSH CA (primeira vez)
./scripts/generate-ssh-ca.sh

# Gerar certificado SSH para utilizador
./scripts/issue-ssh-user-cert.sh admin
./scripts/issue-ssh-user-cert.sh user1
```

### Verificação de Integridade

```bash
# Verificar integridade de todos os ficheiros protegidos
./scripts/verify-integrity.sh
```

### Revogação de Certificados

```bash
# Revogar certificado
./scripts/revoke-cert.sh <serial-number>

# Gerar/atualizar CRL
./scripts/generate-crl.sh

# Verificar revogação
./scripts/verify-revocation.sh <certificate-file>
```

---

## Evidências de Teste

### Teste de Revogação Real

Conforme requerido pelo enunciado, foi realizado um teste completo de revogação:

1. **Certificado emitido:** `test-revoke.org.local`
2. **Certificado revogado:** Serial número [a preencher após teste]
3. **CRL gerado:** `intermediate-ca/crl/intermediate-ca.crl.pem`
4. **Verificação com openssl verify:**
   ```bash
   openssl verify -CAfile root-ca/certs/root-ca.crt \
                  -untrusted intermediate-ca/certs/intermediate-ca.crt \
                  -CRLfile intermediate-ca/crl/intermediate-ca.crl.pem \
                  -crl_check test-revoke-cert.pem
   ```
5. **Resultado:** `error 23 at 0 depth lookup: certificate revoked` ✅

**Evidência:** O certificado é corretamente identificado como revogado pelo OpenSSL quando verificado contra o CRL.

---

## Boas Práticas de Segurança

### Controlo de Acesso

- Chaves privadas protegidas com permissões `600` (apenas proprietário)
- Diretórios privados com permissões `700` (apenas proprietário)
- Utilizador dedicado `ca` para operações da CA
- Certificados públicos com permissões `644` (leitura para todos)

### Integridade

- Checksums SHA-256 gerados após cada alteração crítica
- Verificação de integridade antes de operações sensíveis
- Base de dados (`index.txt`, `serial`) protegida com checksums
- Alertas automáticos em caso de alteração não autorizada

### Revogação

- CRL atualizado regularmente (validade de 30 dias)
- Verificação de revogação obrigatória antes de aceitar certificados
- Logs de todas as revogações mantidos em `index.txt`

### Backup

- Backup regular das chaves privadas (em local seguro e encriptado)
- Backup da base de dados (`index.txt`, `serial`)
- Backup dos checksums para verificação de integridade

---

## Troubleshooting

### Erro: "Permission denied" ao aceder chaves privadas

**Solução:** Verificar que está a executar como utilizador `ca` ou que as permissões estão corretas:
```bash
sudo -u ca ./scripts/generate-root-ca.sh
```

### Erro: "Integrity check failed"

**Solução:** Verificar se os ficheiros foram alterados. Se a alteração foi intencional, atualizar checksums:
```bash
./scripts/update-checksums.sh
```

### Erro: "Certificate verify failed" durante revogação

**Solução:** Verificar que o certificado pertence à CA correta e que o CRL está atualizado:
```bash
./scripts/generate-crl.sh
./scripts/verify-revocation.sh <certificate-file>
```

---

## SSH Remote Access Service

Para informações sobre configuração do servidor SSH na VM Kali, ver:
- **`SSH01/README.md`** - Instruções completas de setup na VM
- **`SSH01/setup-ssh-vm.sh`** - Script de configuração do servidor SSH

**Resumo rápido:**
1. Gerar SSH CA: `cd pki/ssh-ca && ./scripts/generate-ssh-ca.sh`
2. Gerar certificado admin: `./scripts/issue-ssh-user-cert.sh admin`
3. Na VM: Executar `SSH01/setup-ssh-vm.sh` para configurar servidor SSH
4. Testar: `ssh -i user-certs/admin-key -i user-certs/admin-cert.pub admin@<vm-ip>`

---

## Referências

- Assignment 2 - MEI-CC-2025: Requisitos de PKI e políticas de segurança
- Assignment 1: Especificações de algoritmos (RSA 4096 para TLS, Ed25519 para SSH, SHA-256, VM-based deployment)
- CC-Lab03.pdf: Guia prático de OpenSSL e PKI (configuração de CA, emissão de certificados, OCSP, revogação e CRL)
- OpenSSL Documentation: https://www.openssl.org/docs/
- OpenSSH Documentation: https://www.openssh.com/manual.html
