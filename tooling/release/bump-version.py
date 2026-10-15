#!/usr/bin/env python3
"""Atualiza a versão do PulseLab nas superfícies que guardam o número literalmente.

Uso: python3 tooling/release/bump-version.py <versao_antiga> <nova_versao>

A PWA, o service worker, as páginas do site, o empacotador e os scripts de build leem VERSION no
momento do build (marcador __PULSELAB_VERSION__) e não precisam de bump. Ficam aqui só os arquivos
que vão prontos para as máquinas ou para o npm. Cada padrão precisa casar; se algum falhar, nada
é gravado. O fim de linha original é preservado (CRLF nos .ps1 e .bat).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
RELEASE = r"releases/download/v{v}/PulseLab-{v}-Windows\.zip"

# arquivo -> padrões (regex com {v} no lugar da versão antiga); o grupo casado com {v} é trocado
SURFACES: dict[str, list[str]] = {
    "package.json": [r'"version": "{v}"'],
    "apps/student-pwa/package.json": [r'"version": "{v}"'],
    "apps/student-pwa/package-lock.json": [r'\A\{{\n  "name": "[^"]+",\n  "version": "{v}"', r'\n    "": \{{\n      "name": "[^"]+",\n      "version": "{v}"'],
    "version.json": [r'"version": "{v}"', RELEASE],
    "config/defaults.json": [r'"client_version": "{v}"'],
    "config/config.json": [r'"version": "{v}"'],
    "runtime/windows/bridge/pulselab-bridge.ps1": [r'\$script:BridgeVersion = "{v}"'],
    "runtime/windows/pulselab.ps1": [r'\$localVersion = "{v}"'],
    "runtime/windows/Instalar-PulseLab.bat": [r"\(v{v}\)"],
}


def read(path: Path) -> str:
    with path.open(encoding="utf-8", newline="") as f:
        return f.read()


def write(path: Path, content: str) -> None:
    with path.open("w", encoding="utf-8", newline="") as f:
        f.write(content)


def bump(old_v: str, new_v: str) -> None:
    for v in (old_v, new_v):
        if not re.fullmatch(r"\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?", v):
            sys.exit(f"Versão inválida: {v}")
    current = read(REPO_ROOT / "VERSION").strip()
    if current != old_v:
        sys.exit(f"VERSION contém {current}, não {old_v}")

    old_re = re.escape(old_v)
    updated = {REPO_ROOT / "VERSION": f"{new_v}\n"}
    missing: list[str] = []
    for rel, patterns in SURFACES.items():
        path = REPO_ROOT / rel
        content = read(path)
        for pattern in patterns:
            regex = re.compile(pattern.format(v=old_re))
            new_content = regex.sub(lambda m: m.group(0).replace(old_v, new_v), content)
            if new_content == content:
                missing.append(f"{rel}: {pattern.format(v=old_v)}")
            content = new_content
        updated[path] = content

    if missing:
        print("Nada foi gravado. Padrões não encontrados:", file=sys.stderr)
        for item in missing:
            print(f"  - {item}", file=sys.stderr)
        sys.exit(1)

    for path, content in updated.items():
        write(path, content)
    print(f"Versão {old_v} -> {new_v} em {len(updated)} arquivos.")
    print("Depois: editar notes em version.json e rodar tooling/release/check-version-consistency.py.")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Uso: python3 tooling/release/bump-version.py <versao_antiga> <nova_versao>")
    bump(sys.argv[1], sys.argv[2])
