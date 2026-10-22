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

## 2. Publicar a release assinada (GitHub Actions)

Depois do merge na `main`: **Actions → Publicar release → Run workflow**, a partir da `main`, com as
notas (`PulseLab X.Y.Z - ...`) e, se for o caso, **Pré-release** marcado (não chega às máquinas até
ser promovida). O workflow `.github/workflows/publicar-release.yml`:

1. roda o CI inteiro;
2. espera a aprovação no ambiente `release` (Actions → o run → **Review deployments → Approve**);
3. gera `dist/PulseLab-X.Y.Z-Windows.zip` e o `.sha256` e confere a versão com o pacote;
4. assina o manifesto `pulselab-update.json` com a chave do secret `PULSELAB_RELEASE_KEY`, que só
   existe num arquivo temporário do runner e é apagado no fim;
5. cria a release `vX.Y.Z` no commit que gerou o pacote, com o ZIP, o `.sha256`, o manifesto e a
   assinatura.

O script recusa uma chave que não seja a par de `release-public-key.json`: as máquinas recusariam a
release. A chave privada não fica em computador nenhum. O repositório é público, então o Actions e
a aprovação obrigatória do ambiente não têm custo; se ele virar privado, a aprovação obrigatória
deixa de existir no plano Free.

As máquinas consultam só a última release publicada. O launcher confere a assinatura e o SHA-256,
troca as pastas com backup em `_update_backup` e volta à versão anterior se o servidor local não
iniciar. `dados_locais/` e `provisionamento.json` nunca são tocados.

### Configuração única (feita pelo responsável, no GitHub)

1. **2FA** na conta do GitHub (app autenticador ou chave física, não SMS). A conta passa a ser a
   única porta para publicar.
2. **Ambiente**: Settings → Environments → New environment → `release`.
   - **Required reviewers**: o responsável.
   - **Deployment branches and tags**: Selected branches → `main`.
   - **Allow administrators to bypass**: desmarcado.
3. **Secret**: no ambiente `release` → Add environment secret → nome `PULSELAB_RELEASE_KEY`, valor = o
   conteúdo inteiro do PEM da chave privada (de `-----BEGIN` a `-----END ... KEY-----`). O GitHub não
   mostra o valor de novo.
4. **Cópia offline**: o secret não pode ser lido de volta. Guarde uma cópia da chave, protegida por
   senha (`openssl pkey -in <chave> -aes-256-cbc -out <pendrive>/release-key.pem`), num pendrive
   com outra pessoa ou com a instituição, e a senha separada dele.
5. **Apague a chave do computador** onde ela foi gerada, depois de conferir o secret com uma
   pré-release e a cópia offline.

### Publicação local (contingência)

Se o Actions estiver indisponível, com a cópia offline:

```sh
./tooling/release/build-offline-package.sh
python3 tooling/release/publicar-release.py publicar --private <pendrive>/release-key.pem --notes "PulseLab X.Y.Z - ..."
```

### Perda ou vazamento da chave

- **Conta do GitHub ou chave comprometida**: revogue sessões e tokens (github.com/settings/sessions e
  /tokens) e troque a senha. Gere uma chave nova (`publicar-release.py gerar-chave --private
  <caminho fora do repositório>`), commite o novo `release-public-key.json` por PR revisado e publique
  essa versão **ainda assinada com a chave antiga**: as máquinas só confiam na antiga, e é ela que
  entrega a nova. Depois troque o secret pela chave nova e apague a antiga.
- **Chave perdida sem cópia**: as máquinas não aceitam mais nenhuma atualização. Gere uma chave nova
  e reinstale o PulseLab com o pacote do polo em cada computador.

## 3. Site

O merge na `main` dispara `.github/workflows/firebase-hosting-merge.yml`, que roda o CI, gera o
pacote e publica em `hosting-dist/` só o que está listado em `tooling/site/build-hosting.py`. Como a
página de download aponta para a release `vX.Y.Z`, publique a release logo após o merge para o link
não ficar quebrado.

## Pacote do polo

`tooling/polo/gerar-pacote-polo.py` gera o `provisionamento.json` do polo (código, regional, escola,
retenção de 1 a 365 dias, calendário de missões). A coleta de pesquisa só liga com `--caae`;
`--sem-pesquisa` identifica o polo sem coletar. O arquivo é entregue separado do ZIP genérico, que
nunca liga a coleta.

O script também cria a chave do pendrive do polo (`manifest_hmac_key`). Ela vai no
`provisionamento.json` e fica guardada em `dist-polos/chaves-manifesto.json`, que lista uma chave
por polo. Gerar o pacote de novo reaproveita a chave. Nos polos, o exportador de pendrive assina a
coleta com ela. No computador do pesquisador, o importador usa o arquivo para aceitar a coleta e
enviá-la ao Supabase.

`dist-polos/chaves-manifesto.json` é tão sensível quanto o token de cadastro. Ele fica fora do git
e sai com permissão 0600. Faça backup num lugar seguro: se o arquivo se perder, os pendrives dos
polos não chegam à nuvem até gerar pacotes novos e reinstalar as máquinas. Para trocar a chave de
um polo, apague a linha dele no arquivo e gere o pacote de novo. Pendrives exportados antes da
reinstalação continuam assinados com a chave antiga. A variável `PULSELAB_MANIFEST_HMAC_KEY`
continua valendo: no exportador ela tem prioridade sobre a chave do polo, e no importador é aceita
junto com a chave do polo.
