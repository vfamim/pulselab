#!/usr/bin/env python3
"""Gera o pacote do PulseLab para Windows.

Na raiz do ZIP ficam só o Instalar-PulseLab.bat e a pasta arquivos/, que é exatamente o que vai
para %LOCALAPPDATA%\\PulseLab. O atualizador (pulselab-update.ps1, inclusive o das versões já
instaladas) reconhece arquivos/ como a única pasta com pulselab.ps1 e instala o conteúdo dela.
Ferramentas do pesquisador, guias e textos ficam fora: o instrutor só precisa do instalador.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import zipfile

# Versão canônica do projeto (arquivo VERSION na raiz).
VERSION = (Path(__file__).resolve().parents[2] / "VERSION").read_text(encoding="utf-8").strip()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


SENSITIVE_KEY_PATTERNS = (
    "secret",
    "token",
    "password",
    "service_role",
    "operational_jwt",
    "private_key",
    "supabase_key",
    "supabase_anon_key",
    "api_key",
    "apikey",
)


def scan_sensitive_configs(data: object, path: str = "") -> list[str]:
    """Recursively scan nested dictionaries and lists for sensitive keys with non-empty values."""
    violations: list[str] = []
    if isinstance(data, dict):
        for raw_k, v in data.items():
            k_str = str(raw_k)
            curr_path = f"{path}.{k_str}" if path else k_str
            k_lower = k_str.lower()
            if any(pattern in k_lower for pattern in SENSITIVE_KEY_PATTERNS):
                if v not in (None, "", [], {}):
                    violations.append(curr_path)
            violations.extend(scan_sensitive_configs(v, curr_path))
    elif isinstance(data, list):
        for idx, item in enumerate(data):
            curr_path = f"{path}[{idx}]"
            violations.extend(scan_sensitive_configs(item, curr_path))
    return violations


PAYLOAD_DIR = "arquivos"

# runtime/windows/ espelha arquivos/: launcher, atualizador, bridge e atalhos.
RUNTIME_DIR = Path("runtime") / "windows"

# Arquivos de runtime/windows/ que vão para o computador da oficina.
PAYLOAD_FILES = (
    "pulselab.ps1",
    "pulselab-update.ps1",
    "pulselab-installation.ps1",
    "iniciar-silencioso.vbs",
    "Iniciar-PulseLab.bat",
    "Exportar-Dados-Pendrive.bat",
    "pulselab.ico",
    "pulselab-green.ico",
    "pulselab-yellow.ico",
    "pulselab-red.ico",
)
# Arquivos da raiz do repositório que também vão no pacote.
ROOT_PAYLOAD_FILES = ("release-public-key.json",)
BRIDGE_FILES = ("pulselab-bridge.ps1", "spike-parser.ps1", "pulselab-tray.ps1")
CONFIG_FILES = ("defaults.json", "config.json", "missoes.json")


def assemble(repo_root: Path, root: Path, provisioning: Path | None = None) -> None:
    """Monta em root/ o conteúdo do ZIP: Instalar-PulseLab.bat e arquivos/."""
    runtime = repo_root / RUNTIME_DIR
    alunos_dir = repo_root / "alunos"
    if not alunos_dir.is_dir() or not (alunos_dir / "index.html").is_file():
        raise FileNotFoundError("PWA build missing in alunos/. Run 'npm run build' in apps/student-pwa first.")
    payload = root / PAYLOAD_DIR

    # 1. Aplicação dos alunos (servida de app/alunos pelo pulselab.ps1)
    shutil.copytree(alunos_dir, payload / "app" / "alunos")

    # 2. Bridge, launcher, atualizador e atalhos
    (payload / "bridge").mkdir(parents=True)
    for name in BRIDGE_FILES:
        shutil.copy2(runtime / "bridge" / name, payload / "bridge" / name)
    for name in PAYLOAD_FILES:
        shutil.copy2(runtime / name, payload / name)
    for name in ROOT_PAYLOAD_FILES:
        shutil.copy2(repo_root / name, payload / name)
    (payload / "scripts").mkdir()
    shutil.copy2(runtime / "scripts" / "exportar-pendrive.ps1", payload / "scripts" / "exportar-pendrive.ps1")

    # 3. Config (assegurando que nenhum segredo operacional seja distribuído)
    (payload / "config").mkdir()
    for cfg_name in CONFIG_FILES:
        cfg_file = repo_root / "config" / cfg_name
        cfg_data = json.loads(cfg_file.read_text(encoding="utf-8"))
        violations = scan_sensitive_configs(cfg_data)
        if violations:
            raise ValueError(
                f"Chave sensível com valor não vazio encontrada em {cfg_name}: {', '.join(violations)}"
            )
        shutil.copy2(cfg_file, payload / "config" / cfg_name)

    # 4. Provisionamento do polo (ativa a coleta) e versão
    if provisioning is not None:
        shutil.copy2(provisioning, payload / "provisionamento.json")
    (payload / "VERSION").write_text(VERSION + "\n", encoding="ascii")

    # 5. Único arquivo visível para o instrutor
    shutil.copy2(runtime / "Instalar-PulseLab.bat", root / "Instalar-PulseLab.bat")


def build_package(repo_root: Path, output: Path, provisioning: Path | None = None) -> Path:
    output.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="pulselab-package-") as temp_name:
        root = Path(temp_name)
        assemble(repo_root, root, provisioning)

        # 6. Compactar ZIP (reprodutível / determinístico)
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for file_path in sorted(path for path in root.rglob("*") if path.is_file()):
                arcname = file_path.relative_to(root).as_posix()
                zinfo = zipfile.ZipInfo(arcname, date_time=(2026, 10, 2, 0, 0, 0))
                zinfo.compress_type = zipfile.ZIP_DEFLATED
                zinfo.external_attr = 0o644 << 16
                with file_path.open("rb") as f:
                    archive.writestr(zinfo, f.read(), compresslevel=9)

    # 7. Checksum do arquivo ZIP
    checksum_path = output.with_suffix(output.suffix + ".sha256")
    checksum_path.write_text(f"{sha256(output)}  {output.name}\n", encoding="ascii")
    return output


def stage(repo_root: Path, dest: Path) -> Path:
    """Desenvolvimento: copia arquivos/ para dest/ sem compactar, preservando dest/dados_locais."""
    with tempfile.TemporaryDirectory(prefix="pulselab-stage-") as temp_name:
        root = Path(temp_name)
        assemble(repo_root, root)
        shutil.copytree(root / PAYLOAD_DIR, dest, dirs_exist_ok=True)
    return dest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        default=f"PulseLab-{VERSION}-Windows.zip",
        help="Output ZIP path",
    )
    parser.add_argument(
        "--stage",
        default=None,
        help="Monta a pasta arquivos/ neste diretório, sem ZIP (para rodar localmente)",
    )
    parser.add_argument(
        "--provisionamento",
        default=None,
        help="provisionamento.json do polo (gera o pacote que ativa a coleta)",
    )
    args = parser.parse_args()
    repo_root = Path(__file__).resolve().parents[2]
    if args.stage:
        print(f"Pacote montado em: {stage(repo_root, Path(args.stage).resolve())}")
        return 0
    provisioning = Path(args.provisionamento).resolve() if args.provisionamento else None
    package = build_package(repo_root, Path(args.output).resolve(), provisioning=provisioning)
    print(f"Package: {package}")
    print(f"SHA-256: {sha256(package)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
