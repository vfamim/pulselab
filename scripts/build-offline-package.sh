#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}/web/agent-simulator"
npm run build
cd "${ROOT_DIR}"
python3 installer/build-installer.py --output instalador/downloads/PulseLab-2.2.3-Windows.zip
cp -f instalador/downloads/PulseLab-2.2.3-Windows.zip instalador/downloads/PulseLab-Alunos-Offline-v2.2.3.zip
cp -f instalador/downloads/PulseLab-2.2.3-Windows.zip.sha256 instalador/downloads/PulseLab-Alunos-Offline-v2.2.3.zip.sha256
sed -i 's/PulseLab-2.2.3-Windows.zip/PulseLab-Alunos-Offline-v2.2.3.zip/' instalador/downloads/PulseLab-Alunos-Offline-v2.2.3.zip.sha256
