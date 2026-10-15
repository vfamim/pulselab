#!/usr/bin/env bash
# Gera o guia do instrutor publicado em /tutorial/ (HTML) e o PDF para impressão
# a partir de docs/campo/guia-instrutor.md. O PDF precisa do Google Chrome ou Chromium.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"
MARP=(npx --yes @marp-team/marp-cli@4.5.1 --html --no-stdin docs/campo/guia-instrutor.md)
"${MARP[@]}" -o apps/site/tutorial/index.html
"${MARP[@]}" --pdf -o apps/site/tutorial/PulseLab-Guia-Ilustrado.pdf
