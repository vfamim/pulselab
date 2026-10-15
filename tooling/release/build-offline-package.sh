#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${ROOT_DIR}/apps/student-pwa"
npm run build
cd "${ROOT_DIR}"
python3 tooling/release/build-installer.py --output dist/PulseLab-3.0.8-Windows.zip
