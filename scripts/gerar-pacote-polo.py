#!/usr/bin/env python3
"""Gera o pacote do PulseLab para um polo, com provisionamento.json.

O pacote genérico não registra dados de pesquisa. O pacote do polo leva a sede e o
CAAE do parecer ético; ao rodar o Instalar-PulseLab.bat dele, a coleta é ativada
naquele computador sem apagar a identificação da máquina nem os registros existentes.

Exemplo:
  python3 scripts/gerar-pacote-polo.py --polo PET --regional Petrolina --caae 12345678.9.0000.1234
  python3 scripts/gerar-pacote-polo.py --polo SBF --regional "Senhor do Bonfim" --sem-pesquisa
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CAAE_PATTERN = re.compile(r"^\d{8}\.\d\.\d{4}\.\d{4}$")
POLO_PATTERN = re.compile(r"^[A-Z0-9][A-Z0-9_-]{1,23}$")


def load_builder():
    spec = importlib.util.spec_from_file_location("build_installer", ROOT / "installer" / "build-installer.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def build_provisioning(polo: str, regional: str, caae: str | None, school: str | None) -> dict:
    if not POLO_PATTERN.match(polo):
        raise ValueError("Código do polo deve ter 2 a 24 caracteres: letras maiúsculas, números, - ou _.")
    research = caae is not None
    if research and not CAAE_PATTERN.match(caae):
        raise ValueError("CAAE deve seguir o formato 12345678.9.0000.1234.")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    data = {
        "provisioning_id": f"{polo}-{stamp}",
        "site_id": polo,
        "regional_hub": regional,
        "research_collection_enabled": research,
        "research_authorization_version": caae,
        "research_authorized_purposes": ["academic_research"] if research else [],
    }
    if school:
        data["school_code"] = school
    return data


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--polo", required=True, help="Código curto do polo (ex.: PET, JUA, SBF)")
    parser.add_argument("--regional", required=True, help="Nome da regional ou cidade")
    parser.add_argument("--escola", default=None, help="Código da escola, quando o pacote é de uma escola só")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--caae", help="CAAE do parecer que autoriza a coleta neste polo")
    group.add_argument("--sem-pesquisa", action="store_true", help="Identifica o polo sem ligar a coleta")
    parser.add_argument("--out-dir", default=str(ROOT / "dist-polos"))
    args = parser.parse_args(argv)

    try:
        provisioning = build_provisioning(args.polo, args.regional, args.caae, args.escola)
    except ValueError as exc:
        print(f"Erro: {exc}", file=sys.stderr)
        return 2

    builder = load_builder()
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    output = out_dir / f"PulseLab-{builder.VERSION}-{args.polo}-Windows.zip"

    with tempfile.TemporaryDirectory(prefix="pulselab-polo-") as tmp:
        prov_path = Path(tmp) / "provisionamento.json"
        prov_path.write_text(json.dumps(provisioning, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        builder.build_package(
            ROOT,
            output,
            folder_name=f"PulseLab-{builder.VERSION}-{args.polo}-Windows",
            provisioning=prov_path,
        )

    state = f"coleta ATIVA (CAAE {args.caae})" if args.caae else "coleta desligada"
    print(f"Pacote do polo {args.polo}: {output} — {state}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
