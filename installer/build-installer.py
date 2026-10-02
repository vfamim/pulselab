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

VERSION = "2.1.0"

INSTRUCTIONS = """====================================================================
PULSELAB {version} — PACOTE PORTÁTIL E OFFLINE PARA WINDOWS
====================================================================

O PulseLab é o ambiente de acompanhamento de oficinas de robótica escolar com LEGO SPIKE.
Totalmente desacoplado: interface executada diretamente no navegador padrão (PWA 100% offline),
servidor Bridge local mínimo em loopback (porta 43127), sincronização automática na nuvem (Store-and-Forward)
e leitura contínua de projetos (.llsp3).

REQUISITOS:
- Windows 10 ou 11 com Windows PowerShell 5.1 (já nativo no Windows).
- Zero internet necessária durante a oficina (funciona 100% offline).
- Envio automático para o banco da pesquisa assim que o computador conectar à internet.
- Não requer privilégios de administrador.

COMO USAR:

OPÇÃO 1: EXECUÇÃO DIRETA (Recomendado — Sem instalação)
1. Extraia todo o arquivo ZIP em qualquer pasta (ex: Área de Trabalho ou Pendrive).
2. Dê dois cliques em "Iniciar-PulseLab.bat".
3. O navegador padrão abrirá automaticamente em http://127.0.0.1:43127/alunos/.
4. O Bridge emitirá alertas sonoros e visuais aos 20 e 40 minutos de oficina.

OPÇÃO 2: INSTALAÇÃO NO SISTEMA (Com atalho na Área de Trabalho)
1. Extraia todo o arquivo ZIP.
2. Dê dois cliques em "Instalar-PulseLab.bat".
3. O atalho "PulseLab - Iniciar Oficina" será criado na Área de Trabalho.
4. Para abrir nas próximas oficinas, basta dar dois cliques no atalho.

COMO DESINSTALAR:
- Dê dois cliques em "Desinstalar-PulseLab.bat".

COLETA OFFLINE E EXPORTAÇÃO PARA PENDRIVE (SEM INTERNET NA ESCOLA):
1. Todas as oficinas são salvas automaticamente em disco na pasta "dados_locais".
2. Ao final do dia de oficinas, conecte um pendrive USB no computador.
3. Dê dois cliques em "Exportar-Dados-Pendrive.bat".
4. Todos os arquivos de sessões e eventos serão copiados para o pendrive com manifesto e hash SHA-256.
5. Quando o pesquisador estiver em um local com internet, dê dois cliques em "Importar-Para-Supabase.bat"
   para enviar os dados de forma consolidada para a base SQLite local e para o banco central Supabase.

RECURSOS DO PULSELAB v{version}:
- Foco total no robô: os alunos utilizam o app oficial LEGO SPIKE em tela cheia.
- O professor/instrutor está presente fisicamente na sala para mediar e apoiar em pessoa.
- Zero atrito e zero interrupções por pop-ups ou botões de ajuda virtuais.
- Questionário pré e pós rápido (4 perguntas cada, respondidas na própria bancada).
- Banco de dados local permanente em "dados_locais" (100% offline-first).
- Exportação com 1 clique para pendrive USB ("Exportar-Dados-Pendrive.bat").
- Consolidador SQLite e importador idempotente para o Supabase ("Importar-Para-Supabase.bat").
- Leitura automática de blocos do LEGO SPIKE (.llsp3) para telemetria de código.
- Alertas sonoros suaves aos 20 min e 40 min de oficina com foco inteligente de janela.
- Privacidade total (LGPD) — sem captura de webcam, prints ou dados pessoais.
"""

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_package(repo_root: Path, output: Path, folder_name: str | None = None) -> Path:
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
        if (repo_root / "bridge" / "pulselab-toast.ps1").is_file():
            shutil.copy2(repo_root / "bridge" / "pulselab-toast.ps1", stage / "bridge" / "pulselab-toast.ps1")

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

        # 6. Copiar Config
        if (repo_root / "config" / "defaults.json").is_file():
            shutil.copy2(repo_root / "config" / "defaults.json", stage / "config" / "defaults.json")
        if (repo_root / "config" / "config.json").is_file():
            shutil.copy2(repo_root / "config" / "config.json", stage / "config" / "config.json")

        # 7. Copiar Batch files e Launchers
        shutil.copy2(repo_root / "Instalar-PulseLab.bat", stage / "Instalar-PulseLab.bat")
        shutil.copy2(repo_root / "Iniciar-PulseLab.bat", stage / "Iniciar-PulseLab.bat")
        shutil.copy2(repo_root / "Desinstalar-PulseLab.bat", stage / "Desinstalar-PulseLab.bat")
        if (repo_root / "Exportar-Dados-Pendrive.bat").is_file():
            shutil.copy2(repo_root / "Exportar-Dados-Pendrive.bat", stage / "Exportar-Dados-Pendrive.bat")
        if (repo_root / "Importar-Para-Supabase.bat").is_file():
            shutil.copy2(repo_root / "Importar-Para-Supabase.bat", stage / "Importar-Para-Supabase.bat")
        shutil.copy2(repo_root / "pulselab.ps1", stage / "pulselab.ps1")
        shutil.copy2(repo_root / "installer" / "install.ps1", stage / "Install-PulseLab.ps1")
        if (repo_root / "pulselab.ico").is_file():
            shutil.copy2(repo_root / "pulselab.ico", stage / "pulselab.ico")
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

        # 9. Compactar ZIP
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for file_path in sorted(path for path in stage.rglob("*") if path.is_file()):
                archive.write(file_path, file_path.relative_to(stage.parent).as_posix())

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
    args = parser.parse_args()
    repo_root = Path(__file__).resolve().parent.parent
    package = build_package(repo_root, Path(args.output).resolve())
    print(f"Package: {package}")
    print(f"SHA-256: {sha256(package)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
