#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}/web/agent-simulator"
npm run build
python3 installer/build-installer.py --output instalador/downloads/PulseLab-3.0.0-Windows.zip
