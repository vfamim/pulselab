#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION=$(cat "${ROOT_DIR}/VERSION" 2>/dev/null || echo "1.7.0")
PACKAGE_NAME="PulseLab-${VERSION}-Windows"
OFFLINE_PACKAGE_NAME="PulseLab-Alunos-Offline-v${VERSION}"
DIST_ROOT="${ROOT_DIR}/dist-offline"
STAGE_DIR="${DIST_ROOT}/${PACKAGE_NAME}"
DOWNLOADS_DIR="${ROOT_DIR}/instalador/downloads"

echo "=================================================="
echo "PulseLab — Construção do Pacote 100% Offline (v${VERSION})"
echo "=================================================="

# 1. Compilar a PWA
echo "[1/4] Compilando a PWA dos alunos (Vite)..."
cd "${ROOT_DIR}/web/agent-simulator"
npm run build

# 2. Executar o construtor Python para gerar os pacotes
echo "[2/4] Gerando pacotes ZIP de distribuição..."
mkdir -p "${DOWNLOADS_DIR}"

python3 "${ROOT_DIR}/installer/build-installer.py" \
    --output "${DOWNLOADS_DIR}/PulseLab-${VERSION}-Windows.zip"

python3 "${ROOT_DIR}/installer/build-installer.py" \
    --output "${DOWNLOADS_DIR}/${OFFLINE_PACKAGE_NAME}.zip"

# Limpar qualquer lixo residual na raiz se houver
rm -f "${ROOT_DIR}/Install-Pulselab.zip" "${ROOT_DIR}/Install-Pulselab.zip.sha256" "${ROOT_DIR}/"*.zip.sha256

echo "[3/4] Checksums gerados:"
echo "PulseLab-${VERSION}-Windows.zip: $(cat "${DOWNLOADS_DIR}/PulseLab-${VERSION}-Windows.zip.sha256")"
echo "${OFFLINE_PACKAGE_NAME}.zip: $(cat "${DOWNLOADS_DIR}/${OFFLINE_PACKAGE_NAME}.zip.sha256")"

echo "=================================================="
echo "Pacotes gerados com sucesso!"
echo "=================================================="
