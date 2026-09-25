#!/usr/bin/env python3
"""Build the isolated, portable PulseLab TEST package; never includes old collectors."""
from __future__ import annotations
import argparse
import hashlib
from pathlib import Path
import tempfile
import zipfile
import shutil

VERSION = "2.0.0-test.1"
INSTRUCTIONS = """PulseLab TESTE — protocolo v2
Use somente dados ficticios. Instrumento ainda nao validado.
Extraia todo o ZIP e execute Iniciar-PulseLab.bat (Windows 10/11).
O navegador abre em http://127.0.0.1:43128/alunos/.
Mantenha a janela do servidor aberta; feche-a ao terminar.
Nao ha instalacao, envio a nuvem, atualizacao automatica ou leitura de pastas.
O aplicativo funciona offline apos carregar uma vez.
Registros de teste usam armazenamento proprio no navegador e expiram em 7 dias;
a limpeza ocorre ao abrir o aplicativo e durante uma sessao ativa.
Exporte pelo aplicativo; arquivos exportados nao sao apagados automaticamente.
Para retirar uma sessao: Parar registros e apagar sessao.
Leia ROTEIRO-DE-TESTE.md e PROTOCOLO.md.
"""
def sha256(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def build_package(repo_root: Path, output: Path, folder_name: str | None = None) -> Path:
    app = repo_root / 'alunos'
    if not (app / 'index.html').is_file():
        raise FileNotFoundError('Compile a PWA primeiro: npm run build.')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='pulselab-test-package-') as temp:
        stage = Path(temp) / (folder_name or 'PulseLab-TESTE-v2')
        (stage / 'bridge').mkdir(parents=True)
        shutil.copytree(app, stage / 'app' / 'alunos')
        for name in ['Iniciar-PulseLab.bat', 'pulselab.ps1']:
            shutil.copy2(repo_root / name, stage / name)
        shutil.copy2(repo_root / 'bridge' / 'pulselab-bridge.ps1', stage / 'bridge' / 'pulselab-bridge.ps1')
        for source, target in [('docs/roteiro-teste-v2.md','ROTEIRO-DE-TESTE.md'),('docs/protocolo-pesquisa-v2-teste.md','PROTOCOLO.md')]:
            shutil.copy2(repo_root / source, stage / target)
        (stage / 'INSTRUCOES.txt').write_text(INSTRUCTIONS, encoding='utf-8')
        (stage / 'VERSION').write_text(VERSION, encoding='ascii')
        manifest = [sha256(p) + '  ' + p.relative_to(stage).as_posix() for p in sorted(stage.rglob('*')) if p.is_file()]
        (stage / 'SHA256SUMS.txt').write_text('\n'.join(manifest) + '\n', encoding='utf-8')
        with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path in sorted(stage.rglob('*')):
                if path.is_file(): archive.write(path, path.relative_to(stage.parent).as_posix())
    output.with_suffix(output.suffix + '.sha256').write_text(sha256(output) + '  ' + output.name + '\n', encoding='ascii')
    return output

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default='dist-test/PulseLab-TESTE-v2-Windows.zip')
    args = parser.parse_args()
    package = build_package(Path(__file__).resolve().parents[1], Path(args.output).resolve())
    print('Package:', package)
    print('SHA-256:', sha256(package))
    return 0

if __name__ == '__main__': raise SystemExit(main())
