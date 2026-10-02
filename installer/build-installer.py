#!/usr/bin/env python3
"""Build the portable PulseLab package with auto-update and Supabase sync support."""
from __future__ import annotations
import argparse
import hashlib
from pathlib import Path
import tempfile
import zipfile
import shutil

INSTRUCTIONS = """PulseLab — Protocolo de Observabilidade e Registro de Bancada
Extraia todo o ZIP e execute Iniciar-PulseLab.bat (Windows 10/11).
O navegador abre automaticamente em http://127.0.0.1:43128/alunos/.
Mantenha a janela do servidor aberta durante a atividade; feche-a ao terminar.
O sistema possui atualizacao automatica ao iniciar via GitHub e sincronizacao
com o banco de dados em nuvem assim que houver conexao com a internet.
O aplicativo tambem funciona 100% offline via armazenamento local no navegador.
"""

def sha256(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def build_package(repo_root: Path, output: Path, folder_name: str | None = None) -> Path:
    app = repo_root / 'alunos'
    if not (app / 'index.html').is_file():
        raise FileNotFoundError('Compile a PWA primeiro: npm run build.')
    
    version = (repo_root / 'VERSION').read_text().strip() if (repo_root / 'VERSION').is_file() else '2.0.1'
    output.parent.mkdir(parents=True, exist_ok=True)
    
    with tempfile.TemporaryDirectory(prefix='pulselab-package-') as temp:
        stage = Path(temp) / (folder_name or f'PulseLab-{version}-Windows')
        (stage / 'bridge').mkdir(parents=True)
        (stage / 'config').mkdir(parents=True)
        shutil.copytree(app, stage / 'app' / 'alunos')
        shutil.copytree(app, stage / 'alunos')
        
        for name in ['Iniciar-PulseLab.bat', 'pulselab.ps1', 'version.json']:
            if (repo_root / name).is_file():
                shutil.copy2(repo_root / name, stage / name)
                
        shutil.copy2(repo_root / 'bridge' / 'pulselab-bridge.ps1', stage / 'bridge' / 'pulselab-bridge.ps1')
        if (repo_root / 'config' / 'config.json').is_file():
            shutil.copy2(repo_root / 'config' / 'config.json', stage / 'config' / 'config.json')
            
        for source, target in [('docs/roteiro-teste-v2.md', 'ROTEIRO-DE-TESTE.md'), ('docs/protocolo-pesquisa-v2-teste.md', 'PROTOCOLO.md')]:
            if (repo_root / source).is_file():
                shutil.copy2(repo_root / source, stage / target)
                
        (stage / 'INSTRUCOES.txt').write_text(INSTRUCTIONS, encoding='utf-8')
        (stage / 'VERSION').write_text(version + '\n', encoding='ascii')
        
        manifest = [sha256(p) + '  ' + p.relative_to(stage).as_posix() for p in sorted(stage.rglob('*')) if p.is_file()]
        (stage / 'SHA256SUMS.txt').write_text('\n'.join(manifest) + '\n', encoding='utf-8')
        
        with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path in sorted(stage.rglob('*')):
                if path.is_file():
                    archive.write(path, path.relative_to(stage.parent).as_posix())
                    
    output.with_suffix(output.suffix + '.sha256').write_text(sha256(output) + '  ' + output.name + '\n', encoding='ascii')
    return output

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default='dist-test/PulseLab-2.0.1-Windows.zip')
    args = parser.parse_args()
    repo_root = Path(__file__).resolve().parents[1]
    package = build_package(repo_root, Path(args.output).resolve())
    print('Package:', package)
    print('SHA-256:', sha256(package))
    
    # Also generate downloads copies for instalador/downloads
    dl_dir = repo_root / 'instalador' / 'downloads'
    dl_dir.mkdir(parents=True, exist_ok=True)
    version = (repo_root / 'VERSION').read_text().strip()
    
    for filename in [f'PulseLab-{version}-Windows.zip', f'PulseLab-Alunos-Offline-v{version}.zip']:
        target_zip = dl_dir / filename
        shutil.copy2(package, target_zip)
        target_zip.with_suffix(target_zip.suffix + '.sha256').write_text(sha256(target_zip) + '  ' + target_zip.name + '\n', encoding='ascii')
        print(f'Generated: {target_zip}')
        
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
