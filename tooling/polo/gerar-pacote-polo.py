#!/usr/bin/env python3
"""Gera o pacote do PulseLab para um polo, com provisionamento.json.

O pacote genérico não registra dados de pesquisa. O pacote do polo leva a sede e o
CAAE do parecer ético; ao rodar o Instalar-PulseLab.bat dele, a coleta é ativada
naquele computador sem apagar a identificação da máquina nem os registros existentes.

Com --token-cadastro (arquivo gerado por supabase/scripts/provision_device.py --token-polo),
cada máquina se cadastra sozinha na nuvem no primeiro contato com a internet. O token vai
dentro do ZIP: distribua o pacote só para o polo e revogue o token se o ZIP circular.

Cada polo recebe também uma chave HMAC (manifest_hmac_key) que assina as coletas exportadas por
pendrive. A mesma chave fica do lado do pesquisador em <out-dir>/chaves-manifesto.json
({site_id: chave}); o importador a usa para aceitar o pendrive do polo e enviá-lo à nuvem. Gerar o
pacote de novo reutiliza a chave do polo. Guarde esse arquivo com o mesmo cuidado do token.

Exemplo:
  python3 tooling/polo/gerar-pacote-polo.py --polo PET --regional Petrolina --caae <CAAE do parecer aprovado>
  python3 tooling/polo/gerar-pacote-polo.py --polo SBF --regional "Senhor do Bonfim" --sem-pesquisa

Com --calendario (CSV com as colunas data,mission_id; data no formato AAAA-MM-DD), o bridge
sabe qual missão do catálogo config/missoes.json é a do dia e mede quanto o programa final atingiu.
"""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import os
import re
import secrets
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CAAE_PATTERN = re.compile(r"^\d{8}\.\d\.\d{4}\.\d{4}$")
# Exemplo da documentação: casa com o formato, mas não é parecer de CEP nenhum.
EXAMPLE_CAAE = "12345678.9.0000.1234"
POLO_PATTERN = re.compile(r"^[A-Z0-9][A-Z0-9_-]{1,23}$")
MANIFEST_KEYS_FILE = "chaves-manifesto.json"
MANIFEST_KEY_PATTERN = re.compile(r"^[0-9a-f]{64}$")


def load_builder():
    spec = importlib.util.spec_from_file_location("build_installer", ROOT / "tooling" / "release" / "build-installer.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_enrollment_token(bundle_path: Path, polo: str) -> str:
    bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
    if bundle.get("site_id") != polo:
        raise ValueError(f"Token de cadastro é do polo {bundle.get('site_id')!r}, não de {polo!r}.")
    if bundle.get("installation_id"):
        raise ValueError("Token de cadastro é de uma máquina só; gere um token do polo com --token-polo.")
    token = bundle.get("enrollment_token") or ""
    if len(token) < 32:
        raise ValueError("Arquivo de token de cadastro sem enrollment_token válido.")
    return token


def ensure_manifest_key(keys_path: Path, polo: str) -> str:
    """Chave HMAC do polo para assinar o pendrive: reutiliza a de keys_path ou cria e grava (0600)."""
    keys: dict[str, str] = {}
    if keys_path.is_file():
        try:
            keys = json.loads(keys_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise ValueError(f"{keys_path} não é um JSON válido ({exc}); corrija o arquivo antes de gerar o pacote.") from exc
        if not isinstance(keys, dict):
            raise ValueError(f"{keys_path} deve ser um objeto {{polo: chave}}.")
    current = keys.get(polo)
    if isinstance(current, str) and MANIFEST_KEY_PATTERN.match(current):
        return current
    if current is not None:
        raise ValueError(f"Chave do polo {polo} em {keys_path} é inválida (esperado hexadecimal de 64 caracteres).")

    key = secrets.token_hex(32)
    keys[polo] = key
    keys_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = keys_path.with_name(keys_path.name + ".tmp")
    fd = os.open(str(tmp), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(dict(sorted(keys.items())), handle, indent=2)
        handle.write("\n")
    os.replace(tmp, keys_path)
    try:
        os.chmod(keys_path, 0o600)
    except OSError:
        pass
    return key


DATE_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def read_mission_calendar(csv_path: Path, catalog_path: Path = ROOT / "config" / "missoes.json") -> list[dict]:
    """Lê o calendário de missões do polo e confere cada missão contra o catálogo do pacote."""
    known = set()
    if catalog_path.is_file():
        catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
        known = {str(m.get("mission_id")) for m in catalog.get("missoes", []) if m.get("mission_id")}
    entries = []
    with csv_path.open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            day = (row.get("data") or "").strip()
            mission = (row.get("mission_id") or "").strip()
            if not DATE_PATTERN.match(day):
                raise ValueError(f"Data inválida no calendário: {day!r} (use AAAA-MM-DD).")
            datetime.strptime(day, "%Y-%m-%d")
            if mission not in known:
                raise ValueError(f"Missão {mission!r} do calendário não existe em config/missoes.json.")
            entries.append({"data": day, "mission_id": mission})
    return entries


def build_provisioning(polo: str, regional: str, caae: str | None, school: str | None, retention_days: int = 180) -> dict:
    if not POLO_PATTERN.match(polo):
        raise ValueError("Código do polo deve ter 2 a 24 caracteres: letras maiúsculas, números, - ou _.")
    research = caae is not None
    if research and not CAAE_PATTERN.match(caae):
        raise ValueError("CAAE deve seguir o formato 12345678.9.0000.1234.")
    if research and caae == EXAMPLE_CAAE:
        raise ValueError("Esse é o CAAE de exemplo da documentação; use o CAAE do parecer aprovado.")
    if not 1 <= retention_days <= 365:
        raise ValueError("Retenção local deve ficar entre 1 e 365 dias.")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    data = {
        "provisioning_id": f"{polo}-{stamp}",
        "site_id": polo,
        "regional_hub": regional,
        "research_collection_enabled": research,
        "research_authorization_version": caae,
        "research_authorized_purposes": ["academic_research"] if research else [],
        "retention_days": retention_days,
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
    parser.add_argument("--token-cadastro", default=None, help="Arquivo do token do polo (provision_device.py --token-polo)")
    parser.add_argument("--retencao-dias", type=int, default=180, help="Dias que os registros ficam no computador (1 a 365)")
    parser.add_argument("--calendario", default=None, help="CSV data,mission_id com a missão de cada dia (catálogo em config/missoes.json)")
    parser.add_argument("--out-dir", default=str(ROOT / "dist-polos"))
    args = parser.parse_args(argv)

    try:
        provisioning = build_provisioning(args.polo, args.regional, args.caae, args.escola, args.retencao_dias)
        if args.token_cadastro:
            provisioning["enrollment_token"] = read_enrollment_token(Path(args.token_cadastro), args.polo)
        if args.calendario:
            provisioning["calendario_missoes"] = read_mission_calendar(Path(args.calendario))
        out_dir = Path(args.out_dir).resolve()
        keys_path = out_dir / MANIFEST_KEYS_FILE
        provisioning["manifest_hmac_key"] = ensure_manifest_key(keys_path, args.polo)
    except ValueError as exc:
        print(f"Erro: {exc}", file=sys.stderr)
        return 2

    builder = load_builder()
    out_dir.mkdir(parents=True, exist_ok=True)
    output = out_dir / f"PulseLab-{builder.VERSION}-{args.polo}-Windows.zip"

    with tempfile.TemporaryDirectory(prefix="pulselab-polo-") as tmp:
        prov_path = Path(tmp) / "provisionamento.json"
        prov_path.write_text(json.dumps(provisioning, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        builder.build_package(ROOT, output, provisioning=prov_path)

    state = f"coleta ATIVA (CAAE {args.caae})" if args.caae else "coleta desligada"
    if args.token_cadastro:
        state += "; cadastro automático na nuvem"
    print(f"Pacote do polo {args.polo}: {output} — {state}")
    print(f"Chave do pendrive do polo em {keys_path}: guarde com o mesmo cuidado do token (o importador precisa dela).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
