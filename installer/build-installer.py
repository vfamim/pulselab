#!/usr/bin/env python3
"""Build the complete, self-contained PulseLab Windows release package (PWA + Bridge + SPIKE Parser)."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
import zipfile

VERSION = "3.0.1"


INSTRUCTIONS = """====================================================================
PULSELAB {version} — PACOTE PARA WINDOWS
====================================================================

O PulseLab acompanha oficinas de robótica com LEGO SPIKE. A tela das crianças
roda no Microsoft Edge e um servidor local (porta 43128) guarda os registros
neste computador.

REQUISITOS
- Windows 10 ou 11 (o PowerShell 5.1 já vem no Windows).
- Não precisa de internet durante a oficina nem de privilégio de administrador.

INSTALAR (uma vez por computador)
1. Extraia todo o ZIP.
2. Dê dois cliques em "Instalar-PulseLab.bat".
3. Se quiser, digite um nome para esta máquina (ex.: PET-LAB1-PC03) e tecle Enter.
   Anote o mesmo nome numa etiqueta no gabinete.
4. Use o atalho "PulseLab - Iniciar Oficina" na Área de Trabalho.

PACOTE DO POLO
- A coleta de pesquisa só é ativada pelo pacote do seu polo, que traz o arquivo
  provisionamento.json com a sede e o número do parecer ético (CAAE).
- O pacote genérico abre a oficina normalmente, mas não registra dados de pesquisa.
- Para ativar num computador já instalado, rode o "Instalar-PulseLab.bat" do pacote
  do polo. A identificação da máquina e os registros já feitos são mantidos.

ATUALIZAÇÕES
- Ao abrir, o PulseLab procura uma versão nova (no máximo 2 segundos sem internet).
- Só instala pacotes assinados pela equipe do projeto. Se a versão nova não abrir,
  volta sozinho para a anterior.
- Os registros em "dados_locais" nunca são apagados pela atualização.

EXPORTAR OS DADOS PARA PENDRIVE
1. Conecte o pendrive.
2. Use o atalho "PulseLab - Exportar Dados" na Área de Trabalho
   (ou dê dois cliques em "Exportar-Dados-Pendrive.bat").
3. A pasta criada no pendrive leva o nome da máquina e a data, com manifesto SHA-256.

DESINSTALAR
- Dê dois cliques em "Desinstalar-PulseLab.bat".

PRIVACIDADE
- Sem câmera, captura de tela, teclado ou nomes de crianças.
- Do SPIKE são lidas apenas contagens de blocos dos projetos salvos.
- O computador é identificado por um código aleatório e pelo nome que você escolher,
  nunca pelo nome do Windows ou do usuário.
"""

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


def build_package(
    repo_root: Path,
    output: Path,
    folder_name: str | None = None,
    provisioning: Path | None = None,
) -> Path:
    if folder_name is None:
        folder_name = f"PulseLab-{VERSION}-Windows"

    alunos_dir = repo_root / "alunos"
    if not alunos_dir.is_dir() or not (alunos_dir / "index.html").is_file():
        raise FileNotFoundError("PWA build missing in alunos/. Run 'npm run build' in web/agent-simulator first.")

    output.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="pulselab-package-") as temp_name:
        stage = Path(temp_name) / folder_name

        # 1. Estrutura de pastas
        (stage / "app" / "alunos").mkdir(parents=True, exist_ok=True)
        (stage / "bridge").mkdir(parents=True, exist_ok=True)
        (stage / "config").mkdir(parents=True, exist_ok=True)
        (stage / "tools").mkdir(parents=True, exist_ok=True)
        (stage / "scripts").mkdir(parents=True, exist_ok=True)
        (stage / "dados_locais" / "sessoes").mkdir(parents=True, exist_ok=True)

        # 2. Copiar PWA
        shutil.copytree(alunos_dir, stage / "alunos", dirs_exist_ok=True)
        shutil.copytree(alunos_dir, stage / "app" / "alunos", dirs_exist_ok=True)

        # 3. Copiar Bridge
        shutil.copy2(repo_root / "bridge" / "pulselab-bridge.ps1", stage / "bridge" / "pulselab-bridge.ps1")
        shutil.copy2(repo_root / "bridge" / "spike-parser.ps1", stage / "bridge" / "spike-parser.ps1")
        shutil.copy2(repo_root / "bridge" / "pulselab-tray.ps1", stage / "bridge" / "pulselab-tray.ps1")

        # 4. Copiar Scripts de Exportação e Importação Offline
        if (repo_root / "scripts" / "exportar-pendrive.ps1").is_file():
            shutil.copy2(repo_root / "scripts" / "exportar-pendrive.ps1", stage / "scripts" / "exportar-pendrive.ps1")
        if (repo_root / "scripts" / "importar-para-supabase.py").is_file():
            shutil.copy2(repo_root / "scripts" / "importar-para-supabase.py", stage / "scripts" / "importar-para-supabase.py")
        if (repo_root / "scripts" / "importar-para-supabase.ps1").is_file():
            shutil.copy2(repo_root / "scripts" / "importar-para-supabase.ps1", stage / "scripts" / "importar-para-supabase.ps1")

        # 5. Copiar Tools
        if (repo_root / "tools" / "spike-probe.ps1").is_file():
            shutil.copy2(repo_root / "tools" / "spike-probe.ps1", stage / "tools" / "spike-probe.ps1")

        # 6. Copiar Config (assegurando que nenhum segredo operacional seja distribuído)
        for cfg_name in ("defaults.json", "config.json", "missoes.json"):
            cfg_file = repo_root / "config" / cfg_name
            if cfg_file.is_file():
                cfg_data = json.loads(cfg_file.read_text(encoding="utf-8"))
                violations = scan_sensitive_configs(cfg_data)
                if violations:
                    raise ValueError(
                        f"Chave sensível com valor não vazio encontrada em {cfg_name}: {', '.join(violations)}"
                    )
                shutil.copy2(cfg_file, stage / "config" / cfg_name)

        # 7. Copiar Batch files e Launchers
        shutil.copy2(repo_root / "Instalar-PulseLab.bat", stage / "Instalar-PulseLab.bat")
        shutil.copy2(repo_root / "Iniciar-PulseLab.bat", stage / "Iniciar-PulseLab.bat")
        if (repo_root / "iniciar-silencioso.vbs").is_file():
            shutil.copy2(repo_root / "iniciar-silencioso.vbs", stage / "iniciar-silencioso.vbs")
        shutil.copy2(repo_root / "Desinstalar-PulseLab.bat", stage / "Desinstalar-PulseLab.bat")
        if (repo_root / "Exportar-Dados-Pendrive.bat").is_file():
            shutil.copy2(repo_root / "Exportar-Dados-Pendrive.bat", stage / "Exportar-Dados-Pendrive.bat")
        if (repo_root / "Importar-Para-Supabase.bat").is_file():
            shutil.copy2(repo_root / "Importar-Para-Supabase.bat", stage / "Importar-Para-Supabase.bat")
        shutil.copy2(repo_root / "pulselab.ps1", stage / "pulselab.ps1")
        shutil.copy2(repo_root / "pulselab-update.ps1", stage / "pulselab-update.ps1")
        shutil.copy2(repo_root / "pulselab-installation.ps1", stage / "pulselab-installation.ps1")
        if (repo_root / "release-public-key.json").is_file():
            shutil.copy2(repo_root / "release-public-key.json", stage / "release-public-key.json")
        if provisioning is not None:
            shutil.copy2(provisioning, stage / "provisionamento.json")
        shutil.copy2(repo_root / "installer" / "install.ps1", stage / "Install-PulseLab.ps1")
        for icon_name in ("pulselab.ico", "pulselab-green.ico", "pulselab-yellow.ico", "pulselab-red.ico"):
            icon_file = repo_root / icon_name
            if icon_file.is_file():
                shutil.copy2(icon_file, stage / icon_name)
        if (repo_root / "tutorial" / "PulseLab-Guia-Ilustrado.pdf").is_file():
            shutil.copy2(repo_root / "tutorial" / "PulseLab-Guia-Ilustrado.pdf", stage / "PulseLab-Guia-Ilustrado.pdf")

        # 7. Instruções e Versão
        (stage / "INSTRUCOES.txt").write_text(
            INSTRUCTIONS.format(version=VERSION), encoding="utf-8", newline="\r\n"
        )
        (stage / "VERSION").write_text(VERSION + "\n", encoding="ascii")
        (stage / "VERSION.txt").write_text(VERSION + "\n", encoding="ascii")

        # 8. Manifesto SHA256SUMS.txt
        manifest_lines = []
        for file_path in sorted(path for path in stage.rglob("*") if path.is_file()):
            relative = file_path.relative_to(stage).as_posix()
            manifest_lines.append(f"{sha256(file_path)}  {relative}")
        (stage / "SHA256SUMS.txt").write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")

        # 9. Compactar ZIP (reprodutível / determinístico)
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for file_path in sorted(path for path in stage.rglob("*") if path.is_file()):
                arcname = file_path.relative_to(stage.parent).as_posix()
                zinfo = zipfile.ZipInfo(arcname, date_time=(2026, 10, 2, 0, 0, 0))
                zinfo.compress_type = zipfile.ZIP_DEFLATED
                zinfo.external_attr = 0o644 << 16
                with file_path.open("rb") as f:
                    archive.writestr(zinfo, f.read(), compresslevel=9)

    # 10. Checksum do arquivo ZIP
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
    parser.add_argument(
        "--provisionamento",
        default=None,
        help="provisionamento.json do polo (gera o pacote que ativa a coleta)",
    )
    args = parser.parse_args()
    repo_root = Path(__file__).resolve().parent.parent
    provisioning = Path(args.provisionamento).resolve() if args.provisionamento else None
    package = build_package(repo_root, Path(args.output).resolve(), provisioning=provisioning)
    print(f"Package: {package}")
    print(f"SHA-256: {sha256(package)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
