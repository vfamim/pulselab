#!/usr/bin/env python3
"""Build the generic, secret-free PulseLab Windows installer package."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
import zipfile

VERSION = "1.5.0"
REQUIRED_FILES = {
    "agent/pulselab-agent.ps1": "agent/pulselab-agent.ps1",
    "config/config.json": "config/config.json",
    "supabase/scripts/enroll-device.ps1": "supabase/scripts/enroll-device.ps1",
    "Install-PulseLab.ps1": "installer/install.ps1",
}

BAT = r"""@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Install-PulseLab.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" pause
exit /b %EXIT_CODE%
"""

INSTRUCTIONS = """PULSELAB {version} - INSTALADOR WINDOWS SEGURO

REQUISITOS
- Windows 10 ou 11 com Windows PowerShell 5.1.
- URL e chave publica anon do projeto Supabase.
- Token de enrollment de uso unico emitido pelo coordenador.

INSTALACAO
1. Confirme o SHA-256 publicado no site/release.
2. Extraia todo o ZIP; nao execute de dentro do arquivo compactado.
3. Clique duas vezes em Instalar-PulseLab.bat.
4. Informe URL, anon key e identidade da instalacao.
5. Digite o token de enrollment no prompt mascarado.
6. Abra o atalho "Iniciar PulseLab - Oficina de Robotica".

SEGURANCA
- O pacote nao contem tokens, senhas ou service-role key.
- A sessao do dispositivo e protegida por DPAPI no usuario do Windows.
- Nao copie device_session.dat para outra conta ou computador.
"""


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_package(repo_root: Path, output: Path) -> Path:
    missing = [source for source in REQUIRED_FILES.values() if not (repo_root / source).is_file()]
    if missing:
        raise FileNotFoundError("Required installer inputs missing: " + ", ".join(missing))

    config = json.loads((repo_root / "config/config.json").read_text(encoding="utf-8-sig"))
    if config.get("version") != VERSION:
        raise ValueError(f"config version must be {VERSION}, got {config.get('version')!r}")
    for forbidden in ("device_access_token", "device_refresh_token", "service_role"):
        if forbidden in json.dumps(config).lower():
            raise ValueError(f"forbidden credential field in packaged config: {forbidden}")

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="pulselab-package-") as temp_name:
        stage = Path(temp_name) / f"PulseLab-{VERSION}-Windows"
        for archive_name, source_name in REQUIRED_FILES.items():
            destination = stage / archive_name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(repo_root / source_name, destination)

        (stage / "Instalar-PulseLab.bat").write_text(BAT, encoding="utf-8", newline="\r\n")
        (stage / "INSTRUCOES.txt").write_text(
            INSTRUCTIONS.format(version=VERSION), encoding="utf-8", newline="\r\n"
        )
        (stage / "VERSION.txt").write_text(VERSION + "\n", encoding="ascii")

        manifest_lines = []
        for file_path in sorted(path for path in stage.rglob("*") if path.is_file()):
            relative = file_path.relative_to(stage).as_posix()
            manifest_lines.append(f"{sha256(file_path)}  {relative}")
        (stage / "SHA256SUMS.txt").write_text("\n".join(manifest_lines) + "\n", encoding="ascii")

        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for file_path in sorted(path for path in stage.rglob("*") if path.is_file()):
                archive.write(file_path, file_path.relative_to(stage.parent).as_posix())

    checksum_path = output.with_suffix(output.suffix + ".sha256")
    checksum_path.write_text(f"{sha256(output)}  {output.name}\n", encoding="ascii")
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        default=f"PulseLab-{VERSION}-Windows.zip",
        help="Output ZIP path",
    )
    args = parser.parse_args()
    repo_root = Path(__file__).resolve().parent.parent
    package = build_package(repo_root, Path(args.output).resolve())
    print(f"Package: {package}")
    print(f"SHA-256: {sha256(package)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
