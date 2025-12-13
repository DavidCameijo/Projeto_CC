---
name: Plano de Implementação PKI
overview: Implementar uma infraestrutura PKI completa usando OpenSSL com Root CA, Intermediate CA, emissão de certificados, revogação (CRL), políticas de segurança e proteção de integridade. A PKI emitirá certificados TLS para os serviços web01.org.local, db01.org.local e ssh01.org.local.
todos:
  - id: phase1-structure
    content: Criar estrutura de diretórios para Root CA e Intermediate CA (root-ca/, intermediate-ca/, scripts/, checksums/)
    status: completed
  - id: phase1-openssl-configs
    content: Criar ficheiros de configuração OpenSSL (openssl-root.cnf, openssl-intermediate.cnf) com políticas adequadas, extensões e configurações CRL
    status: completed
  - id: phase1-init-script
    content: Criar script init-ca.sh para inicializar diretórios da CA, ficheiros index.txt, serial e estrutura base
    status: completed
  - id: phase1-root-ca
    content: Criar script generate-root-ca.sh para gerar chave Root CA RSA 4096 bits e certificado auto-assinado com SHA-256
    status: completed
  - id: phase1-intermediate-ca
    content: Criar script generate-intermediate-ca.sh para gerar chave Intermediate CA, CSR e assinar com Root CA
    status: completed
  - id: phase1-server-cert
    content: Criar script template issue-server-cert.sh para emitir certificados TLS de servidor com suporte SAN
    status: completed
  - id: phase2-security-setup
    content: Criar script setup-security.sh para configurar permissões, criar utilizador/grupo ca e proteger chaves privadas
    status: pending
  - id: phase2-integrity
    content: Criar scripts update-checksums.sh e verify-integrity.sh para proteção de integridade SHA-256 dos ficheiros da CA
    status: pending
  - id: phase3-revocation
    content: Criar script revoke-cert.sh para revogar certificados por número de série e atualizar base de dados de certificados
    status: pending
  - id: phase3-crl
    content: Criar script generate-crl.sh para gerar Certificate Revocation List em formatos PEM e DER
    status: pending
  - id: phase3-verify-revocation
    content: Criar script exemplo verify-revocation.sh mostrando como clientes verificam revogação de certificados usando CRL
    status: completed
  - id: phase3-revocation-test
    content: "Realizar teste de revogação real: Emitir certificado de teste (test-revoke.org.local), revogá-lo, gerar CRL e verificar com openssl verify -crl_check que é corretamente identificado como revogado (fornece evidência para o assignment)"
    status: pending
  - id: phase4-web-cert
    content: Criar script issue-web-cert.sh para emitir certificado para web01.org.local com SAN e extensões adequadas
    status: pending
  - id: phase4-db-cert
    content: Criar script issue-db-cert.sh para emitir certificado para db01.org.local para TLS PostgreSQL
    status: pending
  - id: phase4-ssh-cert
    content: Criar script issue-ssh-cert.sh para emitir certificado para ssh01.org.local (ou vpn01.org.local)
    status: pending
  - id: documentation
    content: Criar README.md com instruções de utilização, práticas de segurança, guia de troubleshooting e ligações explícitas às políticas do assignment
    status: pending
---

# Plano de Implementação PKI

## Visão Geral

Implementar uma infraestrutura PKI completa na pasta `pki/` usando OpenSSL. A PKI suportará Root CA, Intermediate CA, emissão de certificados para serviços, revogação baseada em CRL e políticas de segurança com proteção de integridade.

## Decisões de Arquitetura

- **Localização**: Scripts e configuração na pasta `pki/` na raiz do projeto (para controlo de versão e acesso fácil)
- **Algoritmo de Chave**: RSA 4096 bits (conforme especificado no Assignment 1)
- **Algoritmo de Hash**: SHA-256
- **Validade dos Certificados**: Root CA (10 anos), Intermediate CA (5 anos), Certificados de servidor (1 ano)
- **Hostnames**: Seguindo o esquema do Assignment 1: `serviceXX.org.local` (web01.org.local, db01.org.local, ssh01.org.local)

## Estrutura de Diretórios

```
pki/
├── root-ca/
│   ├── private/          # Chave privada da Root CA (acesso restrito)
│   ├── certs/            # Certificado da Root CA
│   ├── crl/              # Listas de Revogação de Certificados
│   ├── newcerts/         # Certificados emitidos
│   ├── index.txt         # Base de dados de certificados
│   ├── serial            # Contador de números de série
│   └── openssl.cnf       # Configuração Root CA
├── intermediate-ca/
│   ├── private/          # Chave privada da Intermediate CA (acesso restrito)
│   ├── certs/            # Certificado da Intermediate CA
│   ├── csr/              # Certificate Signing Requests
│   ├── crl/              # Listas de Revogação de Certificados
│   ├── newcerts/         # Certificados emitidos
│   ├── index.txt         # Base de dados de certificados
│   ├── serial            # Contador de números de série
│   └── openssl.cnf       # Configuração Intermediate CA
├── checksums/            # Checksums SHA-256 para verificação de integridade
├── scripts/              # Todos os scripts bash
└── README.md             # Documentação
```

## Fase 2.1: Estrutura da CA + Scripts Base

**Ficheiros a Criar:**

- `pki/init-ca.sh` - Inicializar estrutura Root CA e Intermediate CA
- `pki/openssl-root.cnf` - Configuração OpenSSL para Root CA
- `pki/openssl-intermediate.cnf` - Configuração OpenSSL para Intermediate CA
- `pki/generate-root-ca.sh` - Gerar chave Root CA e certificado auto-assinado
- `pki/generate-intermediate-ca.sh` - Gerar chave Intermediate CA, CSR e assinar com Root CA
- `pki/issue-server-cert.sh` - Script template para emitir certificados TLS de servidor com suporte SAN

**Características Principais:**

- Inicializar ficheiros `index.txt` e `serial` para ambas as CAs
- Configurar OpenSSL com políticas adequadas, key usage e extensões
- Gerar chaves RSA 4096 bits com assinaturas SHA-256
- Suporte para certificados TLS de servidor com SAN (Subject Alternative Names)

## Fase 2.2: Políticas de Segurança (Acesso e Integridade)

**Requisitos do Assignment 2:**

- Suportar acesso seguro a certificados e chaves privadas da CA (restringir acesso à pasta com chaves privadas, apenas utilizador específico tem acesso)
- As configurações da CA (base de dados/ficheiro com informação de certificados) devem ter mecanismos de controlo de integridade

**Ficheiros a Criar:**

- `pki/setup-security.sh` - Configurar políticas de segurança (permissões, criação de utilizador)
- `pki/update-checksums.sh` - Gerar/atualizar checksums SHA-256 após alterações
- `pki/verify-integrity.sh` - Verificar integridade dos ficheiros da CA usando checksums SHA-256
- `pki/checksums/` - Diretório para armazenar checksums SHA-256

**Medidas de Segurança:**

- **Controlo de Acesso**: Criar utilizador/grupo dedicado `ca`, definir permissões `600` para chaves privadas, `700` para diretórios, `644` para certificados
- **Proteção de Integridade**: Gerar checksums SHA-256 para todos os ficheiros críticos (chaves privadas, configs, index.txt, serial), armazenar em `checksums/`, verificar antes de operações

**Ficheiros a Proteger:**

- Chave privada da Root CA (`root-ca/private/root-ca.key`)
- Chave privada da Intermediate CA (`intermediate-ca/private/intermediate-ca.key`)
- Ficheiros de configuração (`openssl-root.cnf`, `openssl-intermediate.cnf`)
- Ficheiros da base de dados (`index.txt`, `serial`) - **REQUERIDO pelo Assignment 2**

## Fase 2.3: Revogação e CRL

**Requisitos do Assignment 2:**

- Suportar ciclo de vida completo de certificados: Emissão, verificação, revogação
- **Evidências de Teste**: O enunciado sublinha a necessidade de evidências de teste, particularmente para revogação

**Ficheiros a Criar:**

- `pki/revoke-cert.sh` - Revogar certificado por número de série ou ficheiro de certificado
- `pki/generate-crl.sh` - Gerar/atualizar Certificate Revocation List em formatos PEM e DER
- `pki/verify-revocation.sh` - Script exemplo mostrando como clientes verificam revogação usando CRL
- `pki/verify-cert.sh` - Script para verificar validade do certificado, cadeia, expiração e estado de revogação

**Evidências de Teste - Exemplo Real de Revogação:**

**IMPORTANTE**: Conforme requerido pelo enunciado, demonstrar pelo menos um exemplo real de revogação:

1. Emitir um certificado de teste (ex: `test-revoke.org.local`)
2. Revogar o certificado usando `revoke-cert.sh`
3. Gerar/atualizar o CRL usando `generate-crl.sh`
4. **Provar revogação** usando `openssl verify` com CRL:
   ```bash
   openssl verify -CAfile root-ca/certs/root-ca.crt \
                  -untrusted intermediate-ca/certs/intermediate-ca.crt \
                  -CRLfile intermediate-ca/crl/intermediate-ca.crl.pem \
                  -crl_check test-revoke-cert.pem
   ```


Resultado esperado: `error 23 at 0 depth lookup: certificate revoked`

5. Documentar o caso de teste no README com outputs de verificação antes/depois

Isto fornece evidência concreta de que a revogação funciona corretamente e os certificados são adequadamente marcados como revogados no CRL.

**Configuração CRL:**

- Período de validade do CRL (ex: 30 dias)
- Rastreamento do número do CRL
- Extensões CRL adequadas na configuração OpenSSL

## Fase 2.4: Geração de Certificados para Serviços

**Ficheiros a Criar:**

- `pki/issue-web-cert.sh` - Emitir certificado para web01.org.local
- `pki/issue-db-cert.sh` - Emitir certificado para db01.org.local para TLS PostgreSQL
- `pki/issue-ssh-cert.sh` - Emitir certificado para ssh01.org.local (ou vpn01.org.local)
- `pki/issue-cert-template.sh` - Script template para emitir qualquer certificado de serviço

**Output dos Certificados:**

Cada script gerará:

- Ficheiro de chave privada: `{service}-key.pem` (ex: `web01-key.pem`)
- Ficheiro de certificado: `{service}-cert.pem` (ex: `web01-cert.pem`)
- Cadeia de certificados: `{service}-chain.pem` (certificado + certificado intermediate CA)

**Detalhes dos Certificados:**

- **Subject**: CN={hostname} (ex: CN=web01.org.local)
- **SAN**: DNS:{hostname}
- **Key Usage**: Digital Signature, Key Encipherment
- **Extended Key Usage**: TLS Web Server Authentication
- **Validade**: 1 ano a partir da emissão

## Notas de Implementação

**Configuração OpenSSL:**

- Usar secção `v3_ca` para certificados CA
- Usar secção `v3_req` para certificados de servidor
- Configurar políticas de certificação adequadas
- Configurar pontos de distribuição CRL
- Configurar authority information access (AIA)

**Requisitos dos Scripts:**

- Todos os scripts devem ser executáveis (`chmod +x`)
- Incluir verificação de erros e validação
- Usar caminhos absolutos ou garantir que scripts são executados do diretório correto
- Incluir comentários explicando cada passo
- Suportar modos interativo e não-interativo quando apropriado

**Integração com Docker:**

- Scripts podem ser copiados para o container `ca01` ou executados do host
- Certificados podem ser montados como volumes para outros containers (web01, db01, ssh01)
- Considerar volume mounts para `/var/pki` se usar CA containerizada

## Dependências

- OpenSSL (versão suportando RSA 4096 e SHA-256)
- Bash shell
- Utilitários Unix padrão (mkdir, chmod, chown, etc.)

## Checklist de Testes

- [ ] Root CA pode ser inicializada e certificado auto-assinado gerado
- [ ] Intermediate CA pode ser criada e assinada pela Root CA
- [ ] Certificados de servidor podem ser emitidos para web01.org.local, db01.org.local, ssh01.org.local
- [ ] Certificados podem ser revogados e aparecer no CRL
- [ ] **Teste de revogação real**: Emitir certificado de teste, revogá-lo e verificar com `openssl verify -crl_check` que é corretamente identificado como revogado (fornece evidência para o assignment)
- [ ] Verificação de integridade detecta alterações nos ficheiros protegidos
- [ ] Permissões estão corretamente definidas nas chaves privadas e ficheiros da CA
- [ ] Certificados gerados funcionam com configuração TLS nginx e PostgreSQL