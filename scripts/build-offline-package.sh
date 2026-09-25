#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}/web/agent-simulator"
npm run build
cd "${ROOT_DIR}"
python3 installer/build-installer.py --output dist-test/PulseLab-TESTE-v2-Windows.zip
