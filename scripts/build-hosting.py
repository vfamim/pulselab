#!/usr/bin/env python3
"""Monta a pasta publicada no Firebase Hosting a partir de uma lista explícita.

O hosting publica somente o que está em PUBLIC_ENTRIES. Arquivos fora da lista
(credenciais, dados_locais, bases SQLite, scripts) nunca chegam ao site, mesmo
que existam na raiz do repositório local.
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

PUBLIC_ENTRIES = (
    "index.html",
    "pulselab.ico",
    "assets",
    "alunos",
    "instrutor",
    "instalador",
    "tutorial",
    "testes",
    "relatorio",
)

# Defesa em profundidade: mesmo dentro das pastas públicas, estes padrões nunca são publicados.
FORBIDDEN_PATTERNS = (
    "*adminsdk*",
    "*.env",
    ".env*",
    "*.sqlite",
    "*.sqlite3",
    "*.db",
    "*.pem",
    "*.key",
    "device_session.*",
    "tokens.json",
)

OUTPUT_DIR_NAME = "hosting-dist"


def is_forbidden(path: Path) -> bool:
    return any(path.match(pattern) for pattern in FORBIDDEN_PATTERNS)


def build(repo_root: Path, output: Path) -> list[str]:
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)

    published: list[str] = []
    for entry in PUBLIC_ENTRIES:
        source = repo_root / entry
        if not source.exists():
            raise FileNotFoundError(f"Entrada pública ausente: {entry}")
        files = [source] if source.is_file() else sorted(p for p in source.rglob("*") if p.is_file())
        for file_path in files:
            relative = file_path.relative_to(repo_root)
            if is_forbidden(relative) or any(part.startswith(".") for part in relative.parts):
                continue
            target = output / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(file_path, target)
            published.append(relative.as_posix())
    return published


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default=None, help="Pasta de saída (padrão: hosting-dist/ na raiz)")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    output = Path(args.output).resolve() if args.output else repo_root / OUTPUT_DIR_NAME
    if output == repo_root or repo_root.is_relative_to(output):
        print("Saída não pode ser a raiz do repositório.", file=sys.stderr)
        return 1

    published = build(repo_root, output)
    print(f"{len(published)} arquivos em {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
