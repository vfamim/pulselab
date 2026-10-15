# Release

Como uma versão sai do repositório e chega às máquinas dos polos. Regras de versionamento em
AGENTS.md §1; atualizador assinado em AGENTS.md §3.3.

## 1. Subir a versão (no PR)

```sh
python3 scripts/bump-version.py 3.0.5 3.0.6
```

Atualiza todas as superfícies conferidas por `scripts/check-version-consistency.py` e preserva o
CRLF dos `.ps1` e `.bat`. Depois:

- editar `notes` em `version.json`;
- `npm run build` para regenerar `alunos/` (bundle e `sw.js`);
- `./scripts/build-guia.sh` para regenerar o guia do instrutor (`tutorial/index.html` e o PDF) a
  partir de `docs/campo/guia-instrutor.md`;
- `python3 scripts/check-version-consistency.py`.

O CI (`.github/workflows/ci.yml`) falha se alguma superfície divergir.

## 2. Gerar o pacote (depois do merge na `main`)

```sh
./scripts/build-offline-package.sh
```

Gera `instalador/downloads/PulseLab-X.Y.Z-Windows.zip` e o `.sha256` (fora do git). Copie o hash
para `instalador/index.html` e `testes/index.html` e rode o verificador de versão de novo: com o
ZIP presente ele confere o checksum, a chave pública empacotada e a ausência de
`provisionamento.json`.

## 3. Publicar a release assinada

```sh
python3 scripts/publicar-release.py publicar --notes "PulseLab X.Y.Z - ..."
```

Assina o manifesto `pulselab-update.json` com a chave privada (`~/.pulselab/release-key.pem`, fora
do repositório) e cria a release `vX.Y.Z` no GitHub com o ZIP, o `.sha256`, o manifesto e a
assinatura. Com `--pre`, sai como pré-release e não chega às máquinas.

As máquinas consultam só a última release publicada. O launcher confere a assinatura e o SHA-256,
troca as pastas com backup em `_update_backup` e volta à versão anterior se o servidor local não
iniciar. `dados_locais/` e `provisionamento.json` nunca são tocados.

## 4. Site

O merge na `main` dispara `.github/workflows/firebase-hosting-merge.yml`, que roda o CI, gera o
pacote e publica em `hosting-dist/` só as pastas listadas em `scripts/build-hosting.py`. Como a
página de download aponta para a release `vX.Y.Z`, publique a release logo após o merge para o link
não ficar quebrado.

## Pacote do polo

`scripts/gerar-pacote-polo.py` gera o `provisionamento.json` do polo (código, regional, escola,
retenção de 1 a 365 dias, calendário de missões). A coleta de pesquisa só liga com `--caae`;
`--sem-pesquisa` identifica o polo sem coletar. O arquivo é entregue separado do ZIP genérico, que
nunca liga a coleta.
