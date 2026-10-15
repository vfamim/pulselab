#!/usr/bin/env python3
"""Atualiza a versão do PulseLab em todas as superfícies canônicas do repositório."""

import re
import sys
from pathlib import Path


# newline="" preserva o fim de linha original (CRLF nos .ps1/.bat, exigido pelo Windows).
def read_text(path: Path) -> str:
    with open(path, encoding="utf-8", newline="") as f:
        return f.read()


def write_text(path: Path, content: str) -> None:
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(content)


def release_links(content: str, new_v: str) -> str:
    """Links de download da Release do GitHub: tag e nome do ZIP."""
    content = re.sub(r'releases/download/v[0-9\.]+/', f'releases/download/v{new_v}/', content)
    return re.sub(r'PulseLab-[0-9\.]+-Windows\.zip', f'PulseLab-{new_v}-Windows.zip', content)


def bump(old_v: str, new_v: str):
    repo_root = Path(__file__).resolve().parents[2]

    # 1. VERSION
    write_text(repo_root / "VERSION", f"{new_v}\n")

    # 2. package.json
    pkg_json = repo_root / "package.json"
    content = read_text(pkg_json)
    content = re.sub(r'"version":\s*"[^"]+"', f'"version": "{new_v}"', content)
    write_text(pkg_json, content)

    # 3. apps/student-pwa/package.json
    web_pkg_json = repo_root / "apps/student-pwa/package.json"
    content = read_text(web_pkg_json)
    content = re.sub(r'"version":\s*"[^"]+"', f'"version": "{new_v}"', content)
    write_text(web_pkg_json, content)

    # 3b. apps/student-pwa/package-lock.json (só a versão do próprio pacote, não a das dependências)
    web_lock = repo_root / "apps/student-pwa/package-lock.json"
    content = read_text(web_lock)
    content = re.sub(r'^(  "version":\s*)"[^"]+"', rf'\g<1>"{new_v}"', content, count=1, flags=re.M)
    content = re.sub(r'(    "": \{\s*"name":\s*"[^"]+",\s*"version":\s*)"[^"]+"', rf'\g<1>"{new_v}"', content, count=1)
    write_text(web_lock, content)

    # 4. version.json
    v_json = repo_root / "version.json"
    content = read_text(v_json)
    content = re.sub(r'"current_version":\s*"[^"]+"', f'"current_version": "{new_v}"', content)
    content = re.sub(r'"latest_stable":\s*"[^"]+"', f'"latest_stable": "{new_v}"', content)
    content = re.sub(r'"version":\s*"[^"]+"', f'"version": "{new_v}"', content)
    content = release_links(content, new_v)
    write_text(v_json, content)

    # 5. config/defaults.json
    def_json = repo_root / "config/defaults.json"
    content = read_text(def_json)
    content = re.sub(r'"client_version":\s*"[^"]+"', f'"client_version": "{new_v}"', content)
    write_text(def_json, content)

    # 6. config/config.json
    cfg_json = repo_root / "config/config.json"
    content = read_text(cfg_json)
    content = re.sub(r'"version":\s*"[^"]+"', f'"version": "{new_v}"', content)
    write_text(cfg_json, content)

    # 7. apps/student-pwa/app/student-page.jsx
    stu_page = repo_root / "apps/student-pwa/app/student-page.jsx"
    content = read_text(stu_page)
    content = re.sub(r'const CLIENT_VERSION = "(student-pwa/)?[^"]+";', rf'const CLIENT_VERSION = "\g<1>{new_v}";', content)
    content = re.sub(r'oficina de robótica · v[0-9\.]+', f'oficina de robótica · v{new_v}', content)
    write_text(stu_page, content)

    # 8. runtime/windows/bridge/pulselab-bridge.ps1
    br_ps1 = repo_root / "runtime/windows/bridge/pulselab-bridge.ps1"
    content = read_text(br_ps1)
    content = re.sub(r"\$script:BridgeVersion = (['\"])[^'\"]+\1", rf"$script:BridgeVersion = \g<1>{new_v}\g<1>", content)
    content = re.sub(r"\$script:PulseLabVersion = '[^']+'", f"$script:PulseLabVersion = '{new_v}'", content)
    content = re.sub(r"version = '[0-9\.]+'", f"version = '{new_v}'", content)
    write_text(br_ps1, content)

    # 9. runtime/windows/pulselab.ps1
    pl_ps1 = repo_root / "runtime/windows/pulselab.ps1"
    content = read_text(pl_ps1)
    content = re.sub(r"\$localVersion = (['\"])[^'\"]+\1", rf"$localVersion = \g<1>{new_v}\g<1>", content)
    write_text(pl_ps1, content)

    # 10. Service workers (fonte e cópia publicada em alunos/)
    for sw_js in (repo_root / "apps/student-pwa/public/sw.js", repo_root / "alunos/sw.js"):
        content = read_text(sw_js)
        content = re.sub(r'const CACHE_NAME = CACHE_PREFIX \+ "[^"]+";', f'const CACHE_NAME = CACHE_PREFIX + "{new_v}";', content)
        write_text(sw_js, content)

    # 11. tooling/release/build-installer.py
    bi_py = repo_root / "tooling/release/build-installer.py"
    content = read_text(bi_py)
    content = re.sub(r'VERSION = "[^"]+"', f'VERSION = "{new_v}"', content)
    write_text(bi_py, content)

    # 12. tooling/release/build-offline-package.sh
    bsh = repo_root / "tooling/release/build-offline-package.sh"
    content = read_text(bsh)
    content = re.sub(r'PulseLab-[0-9\.]+-Windows\.zip', f'PulseLab-{new_v}-Windows.zip', content)
    content = re.sub(r'PulseLab-Alunos-Offline-v[0-9\.]+\.zip', f'PulseLab-Alunos-Offline-v{new_v}.zip', content)
    write_text(bsh, content)

    # 13. tooling/data/importar-para-supabase.py
    imp_py = repo_root / "tooling/data/importar-para-supabase.py"
    content = read_text(imp_py)
    content = re.sub(r'default="[0-9\.]+"', f'default="{new_v}"', content)
    write_text(imp_py, content)

    # 14. runtime/windows/Instalar-PulseLab.bat
    inst_bat = repo_root / "runtime/windows/Instalar-PulseLab.bat"
    content = read_text(inst_bat)
    content = re.sub(r'\(v[0-9\.]+\)', f'(v{new_v})', content)
    write_text(inst_bat, content)

    # 15. Atualizar-Site-Firebase.bat
    att_bat = repo_root / "tooling/site/Atualizar-Site-Firebase.bat"
    content = read_text(att_bat)
    content = re.sub(r'PulseLab-[0-9\.]+-Windows\.zip', f'PulseLab-{new_v}-Windows.zip', content)
    write_text(att_bat, content)

    # 16. index.html
    idx_html = repo_root / "apps/site/index.html"
    content = read_text(idx_html)
    content = re.sub(r'PulseLab v[0-9\.]+', f'PulseLab v{new_v}', content)
    content = re.sub(r'v[0-9\.]+ Oficinas Rotativas', f'v{new_v} Oficinas Rotativas', content)
    write_text(idx_html, content)

    # 17. instalador/index.html
    inst_html = repo_root / "apps/site/instalador/index.html"
    content = read_text(inst_html)
    content = release_links(content, new_v)
    content = re.sub(r'PulseLab v[0-9\.]+', f'PulseLab v{new_v}', content)
    write_text(inst_html, content)

    # 18. testes/index.html
    test_html = repo_root / "apps/site/testes/index.html"
    content = read_text(test_html)
    content = release_links(content, new_v)
    content = re.sub(r'PulseLab Offline v[0-9\.]+', f'PulseLab Offline v{new_v}', content)
    content = re.sub(r'v[0-9\.]+ Oficinas Rotativas', f'v{new_v} Oficinas Rotativas', content)
    write_text(test_html, content)

    # 19. Guia do instrutor: fonte e página gerada (tooling/site/build-guia.sh refaz HTML e PDF)
    for guide in (repo_root / "docs/campo/guia-instrutor.md", repo_root / "apps/site/tutorial/index.html"):
        content = read_text(guide)
        content = re.sub(r'PulseLab [0-9\.]+', f'PulseLab {new_v}', content)
        content = release_links(content, new_v)
        write_text(guide, content)

    # 19b. relatorio/index.html (página pública; o relatório v1.4 em si é histórico)
    rel_html = repo_root / "apps/site/relatorio/index.html"
    content = read_text(rel_html)
    content = re.sub(r'publicado com PulseLab v[0-9\.]+', f'publicado com PulseLab v{new_v}', content)
    write_text(rel_html, content)

    # Documentos não são reescritos: menções a versões neles são registros de quando algo mudou.
    print(f"Versão atualizada de {old_v} para {new_v} em todas as superfícies.")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Uso: python3 bump-version.py <versao_antiga> <nova_versao>")
        sys.exit(1)
    bump(sys.argv[1], sys.argv[2])
