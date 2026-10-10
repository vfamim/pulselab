#!/usr/bin/env python3
"""
Automated Version Consistency Checker for PulseLab.

Ensures that the canonical version in VERSION is synchronized across all
code, configs, public pages, launchers, Service Worker, and distribution scripts.
Fails with a non-zero exit code if any operational surface diverges.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import sys


def read_text(path: Path) -> str:
    if not path.is_file():
        raise FileNotFoundError(f"Arquivo obrigatório não encontrado: {path}")
    return path.read_text(encoding="utf-8")


def read_json(path: Path) -> dict:
    return json.loads(read_text(path))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def check_version_consistency(repo_root: Path) -> list[str]:
    errors: list[str] = []

    # 1. Versão canônica
    version_file = repo_root / "VERSION"
    if not version_file.is_file():
        return ["Arquivo canônico VERSION não encontrado na raiz."]
    canonical = version_file.read_text(encoding="utf-8").strip()
    if not re.match(r"^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?$", canonical):
        return [f"Formato inválido de versão em VERSION: '{canonical}'"]

    # 2. package.json raiz
    pkg_root = repo_root / "package.json"
    if pkg_root.is_file():
        pkg_data = read_json(pkg_root)
        if pkg_data.get("version") != canonical:
            errors.append(f"package.json (raiz): esperado version='{canonical}', encontrado='{pkg_data.get('version')}'")

    # 3. web/agent-simulator/package.json e package-lock.json
    web_pkg = repo_root / "web/agent-simulator/package.json"
    if web_pkg.is_file():
        data = read_json(web_pkg)
        if data.get("version") != canonical:
            errors.append(f"web/agent-simulator/package.json: esperado version='{canonical}', encontrado='{data.get('version')}'")

    web_lock = repo_root / "web/agent-simulator/package-lock.json"
    if web_lock.is_file():
        data = read_json(web_lock)
        if data.get("version") != canonical:
            errors.append(f"web/agent-simulator/package-lock.json: esperado version='{canonical}', encontrado='{data.get('version')}'")

    # 4. version.json
    v_json = repo_root / "version.json"
    if v_json.is_file():
        data = read_json(v_json)
        if data.get("version") != canonical:
            errors.append(f"version.json: esperado version='{canonical}', encontrado='{data.get('version')}'")
        if data.get("auto_update_enabled") is not True:
            errors.append("version.json: auto_update_enabled deve ser true para permitir atualizações automáticas verificadas")
        expected_pkg_url = f"PulseLab-{canonical}-Windows.zip"
        if expected_pkg_url not in data.get("package_url", ""):
            errors.append(f"version.json: package_url deve referenciar {expected_pkg_url}")

    # 5. config/defaults.json e config/config.json
    defaults_json = repo_root / "config/defaults.json"
    if defaults_json.is_file():
        data = read_json(defaults_json)
        if data.get("client_version") != canonical:
            errors.append(f"config/defaults.json: esperado client_version='{canonical}', encontrado='{data.get('client_version')}'")

    config_json = repo_root / "config/config.json"
    if config_json.is_file():
        data = read_json(config_json)
        if data.get("version") != canonical:
            errors.append(f"config/config.json: esperado version='{canonical}', encontrado='{data.get('version')}'")

    # 6. Bridge PowerShell: bridge/pulselab-bridge.ps1
    bridge_ps1 = repo_root / "bridge/pulselab-bridge.ps1"
    if bridge_ps1.is_file():
        content = read_text(bridge_ps1)
        expected_bv = f'$script:BridgeVersion = "{canonical}"'
        if expected_bv not in content:
            errors.append(f"bridge/pulselab-bridge.ps1: não contém '{expected_bv}'")
        if f'protocol_version = "{canonical}"' not in content:
            errors.append(f"bridge/pulselab-bridge.ps1: /v1/config deve retornar protocol_version='{canonical}'")

    # 7. Launcher: pulselab.ps1
    launcher_ps1 = repo_root / "pulselab.ps1"
    if launcher_ps1.is_file():
        content = read_text(launcher_ps1)
        expected_lv = f'$localVersion = "{canonical}"'
        if expected_lv not in content:
            errors.append(f"pulselab.ps1: fallback de versão deve ser '{expected_lv}'")

    # 8. PWA UI: web/agent-simulator/app/student-page.jsx
    student_page = repo_root / "web/agent-simulator/app/student-page.jsx"
    if student_page.is_file():
        content = read_text(student_page)
        expected_cv = f'const CLIENT_VERSION = "student-pwa/{canonical}";'
        if expected_cv not in content:
            errors.append(f"student-page.jsx: não contém '{expected_cv}'")
        expected_ui_tag = f"oficina de robótica · v{canonical}"
        if expected_ui_tag not in content:
            errors.append(f"student-page.jsx: rodapé da UI deve conter '{expected_ui_tag}'")

    # 9. Service Worker: web/agent-simulator/public/sw.js
    sw_file = repo_root / "web/agent-simulator/public/sw.js"
    if sw_file.is_file():
        content = read_text(sw_file)
        expected_cache = f'const CACHE_NAME = CACHE_PREFIX + "{canonical}";'
        if expected_cache not in content:
            errors.append(f"web/agent-simulator/public/sw.js: CACHE_NAME deve ser '{expected_cache}'")

    # 10. Empacotador: installer/build-installer.py
    builder_py = repo_root / "installer/build-installer.py"
    if builder_py.is_file():
        content = read_text(builder_py)
        expected_v = f'VERSION = "{canonical}"'
        if expected_v not in content:
            errors.append(f"installer/build-installer.py: esperado '{expected_v}'")

    # 11. Script de build offline: scripts/build-offline-package.sh
    build_sh = repo_root / "scripts/build-offline-package.sh"
    if build_sh.is_file():
        content = read_text(build_sh)
        zip_name = f"PulseLab-{canonical}-Windows.zip"
        if zip_name not in content:
            errors.append(f"scripts/build-offline-package.sh: deve referenciar '{zip_name}'")
        offline_name = f"PulseLab-Alunos-Offline-v{canonical}.zip"
        if offline_name not in content:
            errors.append(f"scripts/build-offline-package.sh: deve referenciar '{offline_name}'")

    # 12. Scripts Batch de instalação e atualização
    instalar_bat = repo_root / "Instalar-PulseLab.bat"
    if instalar_bat.is_file():
        content = read_text(instalar_bat)
        if f"(v{canonical})" not in content:
            errors.append(f"Instalar-PulseLab.bat: deve exibir título com '(v{canonical})'")

    atualizar_bat = repo_root / "Atualizar-Site-Firebase.bat"
    if atualizar_bat.is_file():
        content = read_text(atualizar_bat)
        zip_name = f"PulseLab-{canonical}-Windows.zip"
        if zip_name not in content:
            errors.append(f"Atualizar-Site-Firebase.bat: deve referenciar '{zip_name}'")

    # 13. Páginas públicas operacionais
    index_html = repo_root / "index.html"
    if index_html.is_file():
        content = read_text(index_html)
        if f"PulseLab v{canonical}" not in content:
            errors.append(f"index.html: deve conter 'PulseLab v{canonical}'")
        if f"v{canonical} Oficinas Rotativas" not in content:
            errors.append(f"index.html: tag da hero deve conter 'v{canonical} Oficinas Rotativas'")

    instalador_html = repo_root / "instalador/index.html"
    if instalador_html.is_file():
        content = read_text(instalador_html)
        zip_name = f"PulseLab-{canonical}-Windows.zip"
        if zip_name not in content:
            errors.append(f"instalador/index.html: link de download deve referenciar '{zip_name}'")
        if f"PulseLab Protocol v{canonical}" not in content and f"PulseLab v{canonical}" not in content:
            errors.append(f"instalador/index.html: cabeçalho deve referenciar v{canonical}")

    testes_html = repo_root / "testes/index.html"
    if testes_html.is_file():
        content = read_text(testes_html)
        zip_name = f"PulseLab-{canonical}-Windows.zip"
        if zip_name not in content:
            errors.append(f"testes/index.html: link de download deve referenciar '{zip_name}'")
        if f"PulseLab Offline v{canonical}" not in content:
            errors.append(f"testes/index.html: título deve conter 'PulseLab Offline v{canonical}'")

    tutorial_html = repo_root / "tutorial/index.html"
    if tutorial_html.is_file():
        content = read_text(tutorial_html)
        if f"PulseLab {canonical}" not in content:
            errors.append(f"tutorial/index.html: deve conter 'PulseLab {canonical}'")
        if f"PulseLab-{canonical}-Windows.zip" not in content:
            errors.append(f"tutorial/index.html: deve referenciar 'PulseLab-{canonical}-Windows.zip'")

    relatorio_html = repo_root / "relatorio/index.html"
    if relatorio_html.is_file():
        content = read_text(relatorio_html)
        if f"PulseLab v{canonical}" not in content and f"PulseLab {canonical}" not in content:
            errors.append(f"relatorio/index.html: deve conter 'PulseLab v{canonical}'")

    # 14. Verificação de Checksums de Pacotes quando presentes
    pkg_dist = repo_root / f"instalador/downloads/PulseLab-{canonical}-Windows.zip"
    pkg_dist_sha = repo_root / f"instalador/downloads/PulseLab-{canonical}-Windows.zip.sha256"
    if pkg_dist.is_file() and pkg_dist_sha.is_file():
        real_hash = sha256_file(pkg_dist)
        sha_text = pkg_dist_sha.read_text(encoding="ascii").strip()
        if not sha_text.startswith(real_hash):
            errors.append(f"Checksum mismatch em {pkg_dist_sha}: hash real é {real_hash}")
        # Conferir se os sites públicos exibem o mesmo hash
        if instalador_html.is_file():
            inst_text = read_text(instalador_html)
            if real_hash not in inst_text:
                errors.append(f"instalador/index.html: não contém o checksum SHA-256 real do pacote ({real_hash})")
        if testes_html.is_file():
            test_text = read_text(testes_html)
            if real_hash not in test_text:
                errors.append(f"testes/index.html: não contém o checksum SHA-256 real do pacote ({real_hash})")

    return errors


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    errors = check_version_consistency(repo_root)
    if errors:
        print("❌ FALHA NA CONSISTÊNCIA DE VERSÃO DO PULSELAB:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1
    version_file = repo_root / "VERSION"
    canonical = version_file.read_text(encoding="utf-8").strip()
    print(f"✅ SUCESSO: Todas as superfícies operacionais do PulseLab estão perfeitamente sincronizadas na versão {canonical}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
