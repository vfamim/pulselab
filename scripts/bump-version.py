#!/usr/bin/env python3
"""Atualiza a versão do PulseLab em todas as superfícies canônicas do repositório."""

import re
import sys
from pathlib import Path

def bump(old_v: str, new_v: str):
    repo_root = Path(__file__).resolve().parent.parent

    # 1. VERSION
    (repo_root / "VERSION").write_text(f"{new_v}\n", encoding="utf-8")

    # 2. package.json
    pkg_json = repo_root / "package.json"
    content = pkg_json.read_text(encoding="utf-8")
    content = re.sub(r'"version":\s*"[^"]+"', f'"version": "{new_v}"', content)
    pkg_json.write_text(content, encoding="utf-8")

    # 3. web/agent-simulator/package.json
    web_pkg_json = repo_root / "web/agent-simulator/package.json"
    content = web_pkg_json.read_text(encoding="utf-8")
    content = re.sub(r'"version":\s*"[^"]+"', f'"version": "{new_v}"', content)
    web_pkg_json.write_text(content, encoding="utf-8")

    # 4. version.json
    v_json = repo_root / "version.json"
    content = v_json.read_text(encoding="utf-8")
    content = re.sub(r'"current_version":\s*"[^"]+"', f'"current_version": "{new_v}"', content)
    content = re.sub(r'"latest_stable":\s*"[^"]+"', f'"latest_stable": "{new_v}"', content)
    v_json.write_text(content, encoding="utf-8")

    # 5. config/defaults.json
    def_json = repo_root / "config/defaults.json"
    content = def_json.read_text(encoding="utf-8")
    content = re.sub(r'"client_version":\s*"[^"]+"', f'"client_version": "{new_v}"', content)
    def_json.write_text(content, encoding="utf-8")

    # 6. config/config.json
    cfg_json = repo_root / "config/config.json"
    content = cfg_json.read_text(encoding="utf-8")
    content = re.sub(r'"version":\s*"[^"]+"', f'"version": "{new_v}"', content)
    cfg_json.write_text(content, encoding="utf-8")

    # 7. web/agent-simulator/app/student-page.jsx
    stu_page = repo_root / "web/agent-simulator/app/student-page.jsx"
    content = stu_page.read_text(encoding="utf-8")
    content = re.sub(r'const CLIENT_VERSION = "[^"]+";', f'const CLIENT_VERSION = "{new_v}";', content)
    content = re.sub(r'oficina de robótica · v[0-9\.]+', f'oficina de robótica · v{new_v}', content)
    stu_page.write_text(content, encoding="utf-8")

    # 8. bridge/pulselab-bridge.ps1
    br_ps1 = repo_root / "bridge/pulselab-bridge.ps1"
    content = br_ps1.read_text(encoding="utf-8")
    content = re.sub(r"\$script:BridgeVersion = '[^']+'", f"$script:BridgeVersion = '{new_v}'", content)
    content = re.sub(r"\$script:PulseLabVersion = '[^']+'", f"$script:PulseLabVersion = '{new_v}'", content)
    content = re.sub(r"version = '[0-9\.]+'", f"version = '{new_v}'", content)
    br_ps1.write_text(content, encoding="utf-8")

    # 9. pulselab.ps1
    pl_ps1 = repo_root / "pulselab.ps1"
    content = pl_ps1.read_text(encoding="utf-8")
    content = re.sub(r"\$localVersion = '[^']+'", f"$localVersion = '{new_v}'", content)
    pl_ps1.write_text(content, encoding="utf-8")

    # 10. web/agent-simulator/public/sw.js
    sw_js = repo_root / "web/agent-simulator/public/sw.js"
    content = sw_js.read_text(encoding="utf-8")
    content = re.sub(r'const CACHE_NAME = CACHE_PREFIX \+ "[^"]+";', f'const CACHE_NAME = CACHE_PREFIX + "{new_v}";', content)
    sw_js.write_text(content, encoding="utf-8")

    # 11. installer/build-installer.py
    bi_py = repo_root / "installer/build-installer.py"
    content = bi_py.read_text(encoding="utf-8")
    content = re.sub(r'VERSION = "[^"]+"', f'VERSION = "{new_v}"', content)
    bi_py.write_text(content, encoding="utf-8")

    # 12. scripts/build-offline-package.sh
    bsh = repo_root / "scripts/build-offline-package.sh"
    content = bsh.read_text(encoding="utf-8")
    content = re.sub(r'PulseLab-[0-9\.]+-Windows\.zip', f'PulseLab-{new_v}-Windows.zip', content)
    content = re.sub(r'PulseLab-Alunos-Offline-v[0-9\.]+\.zip', f'PulseLab-Alunos-Offline-v{new_v}.zip', content)
    bsh.write_text(content, encoding="utf-8")

    # 13. scripts/importar-para-supabase.py
    imp_py = repo_root / "scripts/importar-para-supabase.py"
    content = imp_py.read_text(encoding="utf-8")
    content = re.sub(r'default="[0-9\.]+"', f'default="{new_v}"', content)
    imp_py.write_text(content, encoding="utf-8")

    # 14. Instalar-PulseLab.bat
    inst_bat = repo_root / "Instalar-PulseLab.bat"
    content = inst_bat.read_text(encoding="utf-8")
    content = re.sub(r'\(v[0-9\.]+\)', f'(v{new_v})', content)
    inst_bat.write_text(content, encoding="utf-8")

    # 15. Atualizar-Site-Firebase.bat
    att_bat = repo_root / "Atualizar-Site-Firebase.bat"
    content = att_bat.read_text(encoding="utf-8")
    content = re.sub(r'PulseLab-[0-9\.]+-Windows\.zip', f'PulseLab-{new_v}-Windows.zip', content)
    att_bat.write_text(content, encoding="utf-8")

    # 16. index.html
    idx_html = repo_root / "index.html"
    content = idx_html.read_text(encoding="utf-8")
    content = re.sub(r'PulseLab v[0-9\.]+', f'PulseLab v{new_v}', content)
    content = re.sub(r'v[0-9\.]+ Oficinas Rotativas', f'v{new_v} Oficinas Rotativas', content)
    idx_html.write_text(content, encoding="utf-8")

    # 17. instalador/index.html
    inst_html = repo_root / "instalador/index.html"
    content = inst_html.read_text(encoding="utf-8")
    content = re.sub(r'PulseLab-[0-9\.]+-Windows\.zip', f'PulseLab-{new_v}-Windows.zip', content)
    content = re.sub(r'PulseLab v[0-9\.]+', f'PulseLab v{new_v}', content)
    inst_html.write_text(content, encoding="utf-8")

    # 18. testes/index.html
    test_html = repo_root / "testes/index.html"
    content = test_html.read_text(encoding="utf-8")
    content = re.sub(r'PulseLab-[0-9\.]+-Windows\.zip', f'PulseLab-{new_v}-Windows.zip', content)
    content = re.sub(r'PulseLab Offline v[0-9\.]+', f'PulseLab Offline v{new_v}', content)
    test_html.write_text(content, encoding="utf-8")

    # 19. tutorial/index.html
    tut_html = repo_root / "tutorial/index.html"
    content = tut_html.read_text(encoding="utf-8")
    content = re.sub(r'PulseLab [0-9\.]+', f'PulseLab {new_v}', content)
    content = re.sub(r'PulseLab-[0-9\.]+-Windows\.zip', f'PulseLab-{new_v}-Windows.zip', content)
    tut_html.write_text(content, encoding="utf-8")

    # 20. Operational docs
    for doc in [
        repo_root / "README.md",
        repo_root / "docs/arquitetura-aplicacao-alunos.md",
        repo_root / "docs/HANDOFF-pwa-alunos-spike-bridge.md",
        repo_root / "docs/inventario-dados-v2.md",
        repo_root / "docs/protocolo-pesquisa-v2-teste.md",
        repo_root / "docs/roteiro-teste-v2.md",
        repo_root / "web/agent-simulator/README.md",
    ]:
        if doc.is_file():
            txt = doc.read_text(encoding="utf-8")
            txt = txt.replace(f"v{old_v}", f"v{new_v}").replace(f" {old_v}", f" {new_v}")
            doc.write_text(txt, encoding="utf-8")

    print(f"Versão atualizada de {old_v} para {new_v} em todas as superfícies.")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Uso: python3 bump-version.py <versao_antiga> <nova_versao>")
        sys.exit(1)
    bump(sys.argv[1], sys.argv[2])
