# Secure Communications and Cybersecurity Infrastructure

Academic project for **Comunicações e Cibersegurança**.

**Authors:** David Cameijo, Gonçalo Nogueira  


## Overview

This repository implements a containerised security lab composed of a public-facing
web service, a PostgreSQL backend, a private certificate authority, a reverse proxy,
and an nftables firewall. It also contains scripts for configuring a separate Kali
Linux VM as an SSH certificate-authenticated host.

The main request path is:

```text
Client -> nginx01:443 -> web01:3000 -> db01:5432
          TLS             HTTPS/mTLS       PostgreSQL TLS + client certificate
```

Docker Compose creates two static bridge networks:

- DMZ: `172.18.0.0/16`
- Internal: `172.19.0.0/16`

## Academic context

The project was developed for the Communications and Cybersecurity course and
covers network segmentation, TLS, mutual TLS, PKI operations, authenticated web
access, role-based authorization, configuration integrity checks, and
certificate-based SSH access.

## Implemented features

- Nginx reverse proxy with HTTP-to-HTTPS redirection and TLS 1.3.
- Express web service with:
  - `GET /health` health endpoint.
  - User registration with bcrypt password hashing.
  - TOTP setup with QR-code generation.
  - Password and TOTP login for users with 2FA enabled.
  - JWT access tokens with a 24-hour expiry.
  - Read access for authenticated users and write access for `readwrite` and
    `admin` roles.
  - In-memory failed-login lockout after more than two failed attempts, lasting
    15 minutes.
  - Registration and login rate limits.
- PostgreSQL 15 database with users and data tables.
- PostgreSQL TLS configuration and client-certificate verification through
  `pg_hba.conf` changes made by the database entrypoint.
- nftables firewall with default-drop input and forwarding policies, explicit
  service rules, logging, and CA network isolation.
- Two-level OpenSSL PKI (root and intermediate CA), including:
  - Server and client certificate issuance.
  - Certificate-chain and expiry verification.
  - Certificate revocation and CRL generation.
  - SHA-256 integrity checks for selected PKI files.
- SSH CA scripts using Ed25519 user certificates.
- Kali VM SSH setup with password authentication disabled, certificate
  authentication enabled, forwarding support, session limits, and configuration
  integrity checks.

## Technologies and dependencies

- Docker and Docker Compose
- Debian 12-based custom containers
- Nginx
- Node.js, Express, `pg`, `bcryptjs`, `speakeasy`, `qrcode`,
  `jsonwebtoken`, `express-rate-limit`, and `dotenv`
- PostgreSQL 15
- OpenSSL
- nftables
- OpenSSH
- Bash

The web application dependencies are declared in
[`WEB/app/package.json`](WEB/app/package.json). The repository-level
[`package.json`](package.json) does not define project start or test scripts.

## Architecture and directories

```text
Projeto_CC/
├── docker-compose.yml       # Services, networks, static IPs, and mounts
├── WEB/                     # Express service and its container image
│   └── app/server.js        # HTTP API and small browser UI
├── DB/                      # PostgreSQL initialization and entrypoint scripts
├── FW/                      # nftables image, rules, and integrity check
├── nginx/                   # Reverse-proxy configuration and TLS entrypoint
├── pki/                     # Root/intermediate CA and certificate scripts
├── SSH01/                   # Kali VM SSH setup and verification scripts
├── postgres/tls/            # PostgreSQL server certificate material
└── report/                  # LaTeX report and test evidence
```

The Compose services are `web01`, `db01`, `nginx`, `ca01`, and `fw01`.
`ssh01` is configured outside Compose on a Kali Linux VM.

## Installation and configuration

### Prerequisites

- Docker Engine with the Compose plugin.
- Bash, OpenSSL, and standard Unix utilities for the PKI scripts.
- A Kali Linux VM, shared-folder access, and root privileges if the SSH
  component is used.

The container stack is designed around Linux containers and privileged
networking. The SSH setup scripts are not Windows-native scripts.

### Environment configuration

Create a root `.env` file containing values for the variables consumed by
`docker-compose.yml` and `WEB/app/server.js`:

```dotenv
PORT=3000
DB_HOST=db01
DB_PORT=5432
DB_USER=<database-user>
DB_PASSWORD=<database-password>
DB_NAME=<database-name>
JWT_SECRET=<long-random-secret>
```

Do not commit `.env`, private keys, client keys, or passwords. The checked-out
repository contains certificate and key material; replace it with locally
generated material before using the project outside a controlled academic
environment.

### PKI preparation

From `pki/`, the available scripts can initialise the CA hierarchy and create
the certificates required by the services:

```bash
./scripts/init-ca.sh
./scripts/setup-security.sh
./scripts/generate-root-ca.sh
./scripts/generate-intermediate-ca.sh
./scripts/issue-server-cert.sh <hostname>
./scripts/issue-client-cert.sh <client-name>
./scripts/update-checksums.sh
```

The Compose mounts expect the resulting certificate files to be copied into
the service-specific certificate directories. The exact filenames must match
the paths referenced by the Compose mounts and application configuration.

## Running the project

From the repository root:

```bash
docker compose up --build -d
docker compose ps
```

The reverse proxy publishes ports `80` and `443`; PostgreSQL publishes port
`5432` on the host. For local certificates issued by the project CA, example
requests use `-k`:

```bash
curl -k https://localhost/health
```

To stop the stack:

```bash
docker compose down
```

## Usage examples

Register a user. The response includes a TOTP secret and QR-code data:

```bash
curl -k https://localhost/register \
  -H "Content-Type: application/json" \
  -d '{"username":"demo-user","password":"<password-at-least-8-characters>"}'
```

Log in with the returned TOTP code:

```bash
curl -k https://localhost/login \
  -H "Content-Type: application/json" \
  -d '{"username":"demo-user","password":"<password>","otp":"<six-digit-code>"}'
```

Use the returned JWT to read data:

```bash
curl -k https://localhost/data \
  -H "Authorization: Bearer <jwt-token>"
```

Write operations require an `admin` or `readwrite` role:

```bash
curl -k -X POST https://localhost/data \
  -H "Authorization: Bearer <jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{"title":"Example","content":"Example content"}'
```

Useful container checks include:

```bash
docker exec fw01 nft list ruleset
docker exec web01 /usr/local/bin/config-integrity.sh verify
docker exec db01 /usr/local/bin/config-integrity.sh verify
```

For SSH certificate access, generate an SSH CA and user certificate under
`pki/ssh-ca/`, then run `SSH01/setup-ssh-vm.sh` inside the Kali VM. The
complete VM-specific procedure is documented in [`SSH01/README.md`](SSH01/README.md).

## Tests and verification

No automated unit, integration, or end-to-end test suite was found in the
repository, and no test command is declared in the package manifests.

Verification is provided through executable checks and manual scenarios:

```bash
./pki/scripts/verify-integrity.sh
./pki/scripts/verify-cert.sh <certificate-file>
./pki/scripts/verify-revocation.sh <certificate-file-or-serial>
sudo ./SSH01/verify-ssh-integrity.sh
```

The `report/` directory contains LaTeX documentation and screenshots of
manual checks for registration, JWT authentication, RBAC, login lockout,
TLS/mTLS, firewall rules, and integrity verification.

## Known limitations

- The project has no automated test suite or published coverage result.
- The stack depends on pre-existing certificate filenames and private CA
  material; certificate generation and deployment are not fully automated by
  Compose.
- The default Compose configuration uses static container IP addresses, so
  changing network addresses requires corresponding firewall-rule changes.
- Login lockout state is stored in the web process memory and is lost when the
  container restarts; it is not an external fail2ban service.
- The web integrity script creates its initial checksum baseline when none
  exists. This is an integrity check, not an independently protected
  tamper-evident store.
- The application has a fallback JWT secret if `JWT_SECRET` is absent; a
  production deployment must provide a strong secret.
- Local certificates are not publicly trusted, so browser or curl certificate
  warnings are expected unless the project CA is installed as trusted.
- SSH deployment requires a separately managed Kali VM and is not started by
  Docker Compose.
- The repository includes academic evidence and generated certificate
  material; it is not presented as a production deployment or security
  guarantee.

## License

No license is specified in the repository.
