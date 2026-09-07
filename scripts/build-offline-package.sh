#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION=$(cat "${ROOT_DIR}/VERSION" 2>/dev/null || echo "1.6.0")
PACKAGE_NAME="PulseLab-Alunos-v${VERSION}"
DIST_ROOT="${ROOT_DIR}/dist-offline"
STAGE_DIR="${DIST_ROOT}/${PACKAGE_NAME}"
ZIP_OUTPUT="${DIST_ROOT}/${PACKAGE_NAME}.zip"

echo "=================================================="
echo "PulseLab — Construção do Pacote 100% Offline"
echo "Versão: ${VERSION}"
echo "Destino: ${ZIP_OUTPUT}"
echo "=================================================="

# 1. Compilar a PWA
echo "[1/4] Compilando a PWA dos alunos (Vite)..."
cd "${ROOT_DIR}/web/agent-simulator"
npm run build

# 2. Limpar e estruturar o diretório de empacotamento
echo "[2/4] Estruturando pacote portátil offline..."
rm -rf "${DIST_ROOT}"
mkdir -p "${STAGE_DIR}/app/alunos"
mkdir -p "${STAGE_DIR}/bridge"
mkdir -p "${STAGE_DIR}/tools"
mkdir -p "${STAGE_DIR}/config"

# Copiar arquivos da webapp
cp -r "${ROOT_DIR}/alunos/"* "${STAGE_DIR}/app/alunos/"

# Copiar scripts do Bridge e ferramentas
cp "${ROOT_DIR}/bridge/pulselab-bridge.ps1" "${STAGE_DIR}/bridge/"
cp "${ROOT_DIR}/bridge/spike-parser.ps1" "${STAGE_DIR}/bridge/"
if [ -f "${ROOT_DIR}/tools/spike-probe.ps1" ]; then
    cp "${ROOT_DIR}/tools/spike-probe.ps1" "${STAGE_DIR}/tools/"
fi

# Copiar configurações e instaladores
cp "${ROOT_DIR}/config/defaults.json" "${STAGE_DIR}/config/"
cp "${ROOT_DIR}/Instalar-PulseLab.bat" "${STAGE_DIR}/"
cp "${ROOT_DIR}/Iniciar-PulseLab.bat" "${STAGE_DIR}/"
cp "${ROOT_DIR}/Desinstalar-PulseLab.bat" "${STAGE_DIR}/"
echo "${VERSION}" > "${STAGE_DIR}/VERSION"

# 3. Compactar em formato ZIP
echo "[3/4] Gerando arquivo compactado ZIP..."
cd "${DIST_ROOT}"
if command -v zip >/dev/null 2>&1; then
    zip -r -q "${PACKAGE_NAME}.zip" "${PACKAGE_NAME}"
else
    python3 -c "import shutil; shutil.make_archive('${PACKAGE_NAME}', 'zip', '.', '${PACKAGE_NAME}')"
fi

# 4. Gerar Checksums SHA-256
echo "[4/4] Gerando somas de verificação SHA-256..."
cd "${DIST_ROOT}"
sha256sum "${PACKAGE_NAME}.zip" > "${PACKAGE_NAME}.zip.sha256"
sha256sum "${PACKAGE_NAME}.zip" > SHA256SUMS

echo "=================================================="
echo "Pacote gerado com sucesso!"
echo "Arquivo: ${ZIP_OUTPUT}"
echo "Tamanho: $(du -h "${ZIP_OUTPUT}" | cut -f1)"
echo "SHA-256: $(cat "${PACKAGE_NAME}.zip.sha256")"
echo "=================================================="
