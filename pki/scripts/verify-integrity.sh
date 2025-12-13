#!/bin/bash

# Script para verificar integridade dos ficheiros críticos da PKI usando checksums SHA-256
# Assignment 2 - PKI Infrastructure
# Política: "As configurações da CA (base de dados/ficheiro com informação de certificados) 
#            devem ter mecanismos de controlo de integridade"
# Uso: ./scripts/verify-integrity.sh

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
CHECKSUMS_FILE="$PKI_DIR/checksums/checksums.sha256"

echo -e "${GREEN}=== Verificação de Integridade da PKI ===${NC}"
echo "Diretório PKI: $PKI_DIR"
echo "Ficheiro de checksums: $CHECKSUMS_FILE"
echo ""

# Verificar se ficheiro de checksums existe
if [ ! -f "$CHECKSUMS_FILE" ]; then
    echo -e "${RED}Erro: Ficheiro de checksums não encontrado!${NC}"
    echo ""
    echo -e "${YELLOW}Execute primeiro:${NC}"
    echo -e "${YELLOW}  ./scripts/update-checksums.sh${NC}"
    exit 1
fi

# Contadores
total_files=0
verified_files=0
failed_files=0
missing_files=0

echo -e "${YELLOW}Verificando integridade dos ficheiros...${NC}"
echo ""

# Ler cada linha do ficheiro de checksums
while IFS= read -r line || [ -n "$line" ]; do
    # Ignorar linhas vazias
    [ -z "$line" ] && continue
    
    # Extrair checksum esperado e path relativo
    expected_checksum=$(echo "$line" | awk '{print $1}')
    relative_path=$(echo "$line" | awk '{print $2}')
    full_path="$PKI_DIR/$relative_path"
    
    total_files=$((total_files + 1))
    
    # Verificar se ficheiro existe
    if [ ! -f "$full_path" ]; then
        echo -e "${RED}  ✗ FICHEIRO AUSENTE: $relative_path${NC}"
        missing_files=$((missing_files + 1))
        continue
    fi
    
    # Calcular checksum atual
    current_checksum=$(sha256sum "$full_path" | awk '{print $1}')
    
    # Comparar checksums
    if [ "$current_checksum" = "$expected_checksum" ]; then
        echo -e "${GREEN}  ✓ OK: $relative_path${NC}"
        verified_files=$((verified_files + 1))
    else
        echo -e "${RED}  ✗ ALTERADO: $relative_path${NC}"
        echo -e "${RED}      Esperado: $expected_checksum${NC}"
        echo -e "${RED}      Atual:    $current_checksum${NC}"
        failed_files=$((failed_files + 1))
    fi
done < "$CHECKSUMS_FILE"

echo ""

# Resumo
echo -e "${BLUE}=== Resumo da Verificação ===${NC}"
echo ""
echo "Total de ficheiros verificados: $total_files"
echo -e "${GREEN}Ficheiros íntegros: $verified_files${NC}"

if [ $missing_files -gt 0 ]; then
    echo -e "${RED}Ficheiros ausentes: $missing_files${NC}"
fi

if [ $failed_files -gt 0 ]; then
    echo -e "${RED}Ficheiros alterados: $failed_files${NC}"
    echo ""
    echo -e "${RED}⚠ ATENÇÃO: Alguns ficheiros críticos foram alterados!${NC}"
    echo -e "${RED}  Isto pode indicar tampering ou alterações não autorizadas.${NC}"
    echo ""
    echo -e "${YELLOW}Recomendações:${NC}"
    echo -e "${YELLOW}  1. Investigar as alterações nos ficheiros reportados${NC}"
    echo -e "${YELLOW}  2. Se as alterações são legítimas, atualizar checksums:${NC}"
    echo -e "${YELLOW}     ./scripts/update-checksums.sh${NC}"
    echo -e "${YELLOW}  3. Se as alterações são suspeitas, considerar regenerar a CA${NC}"
    exit 1
fi

if [ $missing_files -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}⚠ ATENÇÃO: Alguns ficheiros esperados não foram encontrados.${NC}"
    echo -e "${YELLOW}  Se estes ficheiros foram removidos intencionalmente, atualize os checksums.${NC}"
    exit 1
fi

# Tudo OK
if [ $verified_files -eq $total_files ] && [ $failed_files -eq 0 ] && [ $missing_files -eq 0 ]; then
    echo -e "${GREEN}✓ Todos os ficheiros críticos estão íntegros!${NC}"
    echo ""
    echo -e "${BLUE}A integridade da PKI foi verificada com sucesso.${NC}"
    exit 0
fi
