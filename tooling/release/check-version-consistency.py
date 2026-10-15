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

    # 3. apps/student-pwa/package.json e package-lock.json
    web_pkg = repo_root / "apps/student-pwa/package.json"
    if web_pkg.is_file():
        data = read_json(web_pkg)
        if data.get("version") != canonical:
            errors.append(f"apps/student-pwa/package.json: esperado version='{canonical}', encontrado='{data.get('version')}'")

    web_lock = repo_root / "apps/student-pwa/package-lock.json"
    if web_lock.is_file():
        data = read_json(web_lock)
        if data.get("version") != canonical:
            errors.append(f"apps/student-pwa/package-lock.json: esperado version='{canonical}', encontrado='{data.get('version')}'")

    # 4. version.json
    v_json = repo_root / "version.json"
    if v_json.is_file():
        data = read_json(v_json)
        if data.get("version") != canonical:
            errors.append(f"version.json: esperado version='{canonical}', encontrado='{data.get('version')}'")
        if data.get("auto_update_enabled") is not True:
            errors.append("version.json: auto_update_enabled deve ser true para permitir atualizações automáticas verificadas")
        expected_pkg_url = f"https://github.com/vfamim/pulselab/releases/download/v{canonical}/PulseLab-{canonical}-Windows.zip"
        if data.get("package_url") != expected_pkg_url:
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

    # 6. Bridge PowerShell: runtime/windows/bridge/pulselab-bridge.ps1
    bridge_ps1 = repo_root / "runtime/windows/bridge/pulselab-bridge.ps1"
    if bridge_ps1.is_file():
        content = read_text(bridge_ps1)
        expected_bv = f'$script:BridgeVersion = "{canonical}"'
        if expected_bv not in content:
            errors.append(f"runtime/windows/bridge/pulselab-bridge.ps1: não contém '{expected_bv}'")
        if re.search(r'protocol_version = "\d+\.\d+\.\d+"', content):
            errors.append("runtime/windows/bridge/pulselab-bridge.ps1: protocol_version não pode ser a versão do software")

    # 7. Launcher: runtime/windows/pulselab.ps1
    launcher_ps1 = repo_root / "runtime/windows/pulselab.ps1"
    if launcher_ps1.is_file():
        content = read_text(launcher_ps1)
        expected_lv = f'$localVersion = "{canonical}"'
        if expected_lv not in content:
            errors.append(f"runtime/windows/pulselab.ps1: fallback de versão deve ser '{expected_lv}'")

    # 8-13. Superfícies que recebem a versão no build pelo marcador (sem número fixo no código)
    token = "__PULSELAB_VERSION__"
    hardcoded = re.compile(r"PulseLab-\d+\.\d+\.\d+-Windows|releases/download/v\d")
    release_link = f"https://github.com/vfamim/pulselab/releases/download/v{token}/PulseLab-{token}-Windows.zip"
    templated = {
        "apps/student-pwa/app/student-page.jsx": [
            "const CLIENT_VERSION = `student-pwa/${__PULSELAB_VERSION__}`;",
            "oficina de robótica · v{__PULSELAB_VERSION__}",
        ],
        "apps/student-pwa/public/sw.js": ['const CACHE_NAME = CACHE_PREFIX + "__PULSELAB_VERSION__";'],
        "apps/student-pwa/vite.config.js": ['"../../VERSION"', "[VERSION_TOKEN]: JSON.stringify(version)"],
        "tooling/release/build-installer.py": ['/ "VERSION").read_text('],
        "tooling/release/build-offline-package.sh": ["< VERSION", "PulseLab-${VERSION}-Windows.zip"],
        "tooling/site/Atualizar-Site-Firebase.bat": ["set /p VERSION=<VERSION", "PulseLab-%VERSION%-Windows.zip"],
        "tooling/site/build-hosting.py": ['VERSION_TOKEN = "__PULSELAB_VERSION__"'],
        "apps/site/index.html": [f"PulseLab v{token}", f"v{token} Oficinas Rotativas"],
        "apps/site/instalador/index.html": [release_link, f"{release_link}.sha256", f"PulseLab v{token}"],
        "apps/site/testes/index.html": [release_link, f"{release_link}.sha256", f"PulseLab Offline v{token}"],
        "apps/site/relatorio/index.html": [f"PulseLab v{token}"],
    }
    for rel, required in templated.items():
        path = repo_root / rel
        if not path.is_file():
            errors.append(f"{rel}: arquivo ausente")
            continue
        content = read_text(path)
        for snippet in required:
            if snippet not in content:
                errors.append(f"{rel}: deve conter '{snippet}'")
        if hardcoded.search(content) or f"v{canonical}" in content:
            errors.append(f"{rel}: versão escrita à mão; use {token} (preenchido no build)")
    build_sh = repo_root / "tooling/release/build-offline-package.sh"
    if build_sh.is_file() and "Alunos-Offline" in read_text(build_sh):
        errors.append("tooling/release/build-offline-package.sh: não gerar mais a cópia PulseLab-Alunos-Offline (duplicata do ZIP)")

    # Build da PWA (não versionado): quando existe, precisa ser da versão atual
    built_sw = repo_root / "alunos/sw.js"
    if built_sw.is_file() and f'CACHE_PREFIX + "{canonical}"' not in read_text(built_sw):
        errors.append(f"alunos/sw.js: build desatualizado; rode npm run build (esperado {canonical})")

    # 12. Instalador (vai pronto no ZIP)
    instalar_bat = repo_root / "runtime/windows/Instalar-PulseLab.bat"
    if instalar_bat.is_file():
        content = read_text(instalar_bat)
        if f"(v{canonical})" not in content:
            errors.append(f"runtime/windows/Instalar-PulseLab.bat: deve exibir título com '(v{canonical})'")

    # 14. Verificação de Checksums de Pacotes quando presentes
    pkg_dist = repo_root / f"dist/PulseLab-{canonical}-Windows.zip"
    pkg_dist_sha = repo_root / f"dist/PulseLab-{canonical}-Windows.zip.sha256"
    if pkg_dist.is_file() and pkg_dist_sha.is_file():
        real_hash = sha256_file(pkg_dist)
        sha_text = pkg_dist_sha.read_text(encoding="ascii").strip()
        if not sha_text.startswith(real_hash):
            errors.append(f"Checksum mismatch em {pkg_dist_sha}: hash real é {real_hash}")

    # 15. Um único identificador de protocolo: o do manifesto do instrumento (contracts.js)
    contracts_js = repo_root / "apps/student-pwa/lib/contracts.js"
    if contracts_js.is_file() and config_json.is_file():
        match = re.search(r'export const PROTOCOL_VERSION = "([^"]+)"', read_text(contracts_js))
        protocol = match.group(1) if match else None
        if read_json(config_json).get("protocol_version") != protocol:
            errors.append(f"config/config.json: protocol_version deve ser '{protocol}' (igual a lib/contracts.js)")

    # 16. Atualizador assinado: sem a chave pública no pacote, as máquinas nunca mais se atualizam.
    public_key = repo_root / "release-public-key.json"
    if not public_key.is_file():
        errors.append("release-public-key.json ausente: gere com tooling/release/publicar-release.py gerar-chave")
    elif pkg_dist.is_file():  # o ZIP não é versionado; a checagem roda localmente após o build
        import zipfile

        with zipfile.ZipFile(pkg_dist) as archive:
            names = {name.split("/", 1)[-1] for name in archive.namelist()}
            for required in ("release-public-key.json", "pulselab-update.ps1", "pulselab-installation.ps1"):
                if required not in names:
                    errors.append(f"{pkg_dist.name}: pacote sem {required}")
            if "provisionamento.json" in names:
                errors.append(f"{pkg_dist.name}: pacote genérico não pode conter provisionamento.json")
            key_entries = [name for name in archive.namelist() if name.endswith("release-public-key.json")]
            packaged_key = archive.read(key_entries[0]) if key_entries else b""
            if packaged_key and json.loads(packaged_key) != read_json(public_key):
                errors.append(f"{pkg_dist.name}: chave pública do pacote difere de release-public-key.json")

    return errors


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
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
