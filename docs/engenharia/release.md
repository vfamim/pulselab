# Release

Como uma versão sai do repositório e chega às máquinas dos polos. Regras de versionamento em
AGENTS.md §1; atualizador assinado em AGENTS.md §3.3.

## 1. Subir a versão (no PR)

```sh
python3 tooling/release/bump-version.py 3.0.5 3.0.6
```

Atualiza `VERSION` e os arquivos que guardam o número escrito (pacotes npm, `version.json`,
`config/`, bridge, launcher e instalador), preservando o CRLF dos `.ps1` e `.bat`. Se algum padrão
não casar, nada é gravado. PWA, service worker, páginas do site e empacotador leem `VERSION` no
build pelo marcador `__PULSELAB_VERSION__` e não precisam de bump (AGENTS.md §1.2). Depois:

- editar `notes` em `version.json`;
- `python3 tooling/release/check-version-consistency.py`.

`alunos/` não é versionado: `npm run build` em `apps/student-pwa` o gera para testar ou empacotar
localmente. O guia do instrutor só precisa de `./tooling/site/build-guia.sh` quando o texto em
`docs/campo/guia-instrutor.md` mudar.

O CI (`.github/workflows/ci.yml`) falha se alguma superfície divergir.

## 2. Gerar o pacote (depois do merge na `main`)

```sh
./tooling/release/build-offline-package.sh
```

Gera `dist/PulseLab-X.Y.Z-Windows.zip` e o `.sha256` (fora do git). As páginas não repetem o hash:
apontam para o `.sha256` publicado na release. Rode o verificador de versão de novo; com o ZIP
presente ele confere o checksum, a chave pública empacotada e a ausência de `provisionamento.json`.

## 3. Publicar a release assinada

```sh
python3 tooling/release/publicar-release.py publicar --notes "PulseLab X.Y.Z - ..."
```

Assina o manifesto `pulselab-update.json` com a chave privada (`~/.pulselab/release-key.pem`, fora
do repositório) e cria a release `vX.Y.Z` no GitHub com o ZIP, o `.sha256`, o manifesto e a
assinatura. Com `--pre`, sai como pré-release e não chega às máquinas.

As máquinas consultam só a última release publicada. O launcher confere a assinatura e o SHA-256,
troca as pastas com backup em `_update_backup` e volta à versão anterior se o servidor local não
iniciar. `dados_locais/` e `provisionamento.json` nunca são tocados.

## 4. Site

O merge na `main` dispara `.github/workflows/firebase-hosting-merge.yml`, que roda o CI, gera o
pacote e publica em `hosting-dist/` só o que está listado em `tooling/site/build-hosting.py`. Como a
página de download aponta para a release `vX.Y.Z`, publique a release logo após o merge para o link
não ficar quebrado.

## Pacote do polo

`tooling/polo/gerar-pacote-polo.py` gera o `provisionamento.json` do polo (código, regional, escola,
retenção de 1 a 365 dias, calendário de missões). A coleta de pesquisa só liga com `--caae`;
`--sem-pesquisa` identifica o polo sem coletar. O arquivo é entregue separado do ZIP genérico, que
nunca liga a coleta.
