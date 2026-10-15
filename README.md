# PulseLab

Camada de observação das oficinas do projeto Robótica Educativa (UNIVASF). Nos computadores das
oficinas, o PulseLab inicia com o Windows e fica só como um ícone na bandeja, perto do relógio.
Um servidor local em PowerShell (porta 43128) registra a atividade de cada bancada no LEGO SPIKE,
guarda os dados no próprio computador e envia à nuvem quando há internet.

Nenhuma tela aparece para as crianças durante a aula.

## Na aula

O instrutor usa o menu do ícone da bandeja (botão direito):

| Item | O que faz |
|---|---|
| **Encerrar turma…** | Fecha a gravação da turma. A próxima começa sozinha no primeiro programa salvo no SPIKE. |
| **Não registrar esta turma** | Para recusas: mostra a aula ("Aula que começou às 14:05 (50 min)"), marca como não autorizada e pausa o registro até a próxima aula. Vale para a aula em andamento ou, sem ela, para a última encerrada. |
| **Ver situação** | Mostra se o registro está ativo, pausado ou desligado. |
| **Fechar PulseLab** | Desliga tudo até o computador ser ligado de novo ou o atalho ser usado. |

Sem encerramento, a sessão fecha sozinha depois de 3 horas ou quando o computador passa mais de
20 minutos desligado ou suspenso.

## Pesquisa e privacidade

- **Coleta desligada por padrão.** O pacote genérico não registra dados de pesquisa. A coleta só
  liga com o pacote do polo, que traz o CAAE do parecer ético em `provisionamento.json`.
- **A unidade de análise é a bancada**, nunca a criança. Sem nomes, fotos, câmera, áudio, captura
  de tela ou teclado.
- **Assentimento verbal.** No início da aula o instrutor lê o
  [roteiro padronizado](docs/campo/assentimento-verbal.md). Uma recusa leva a **Não registrar esta
  turma**: a aula é marcada como não autorizada e nunca entra em análise. A exclusão definitiva é
  feita na revisão do pesquisador, com marca contra reenvio (veja "Dados e nuvem").
- **O que é registrado:** como a sessão terminou, interrupções, situação da pasta do SPIKE e, de
  cada versão salva do programa, só os tipos de blocos. Daí saem um escore de pensamento
  computacional adaptado de Dr. Scratch (ainda não validado) e, com calendário de missões, a
  cobertura da missão do dia.
- **Retenção local** de `retention_days` do pacote do polo (1 a 365, padrão 180 dias), mesmo depois
  de exportar ou enviar. O prazo precisa constar no protocolo e no TCLE.
- A máquina é identificada por um código aleatório e por um rótulo escolhido na instalação, nunca
  pelo nome do Windows ou do usuário.

Itens, rubricas e a pergunta de pesquisa ainda dependem de validação acadêmica: veja
[`docs/pesquisa/`](docs/pesquisa/).

## Instalação nos polos

O ZIP da release tem só duas coisas: `Instalar-PulseLab.bat` e a pasta `arquivos/`.

1. Extraia o ZIP (botão direito > **Extrair tudo…**).
2. Dê dois cliques em `Instalar-PulseLab.bat` e, se quiser, informe o rótulo da máquina
   (ex.: `PET-LAB1-PC03`).
3. Pronto: o PulseLab abre com o Windows. O atalho **PulseLab - Exportar Dados** copia os
   registros para um pendrive.

Para ligar a coleta, use o pacote do polo em vez do genérico. Reinstalar por cima mantém a
identificação da máquina e os registros. Guia para instrutores:
[`docs/campo/guia-instrutor.md`](docs/campo/guia-instrutor.md).

## Dados e nuvem

Tudo fica em `dados_locais/` no computador, pasta que nenhuma atualização ou reinstalação apaga.
Com internet, o bridge envia ao Supabase a cada 30 segundos: os eventos um a um e o resumo da
sessão quando ela fecha. Polos sem internet enviam quando o instrutor conecta ou exportam por
pendrive, e o pesquisador importa com `tooling/data/Importar-Para-Supabase.bat`.

Aulas marcadas como não autorizadas sobem com `authorization_status = "nao_autorizada"` (e saem no
pendrive em `sessions_unauthorized.txt`), ficam guardadas e fora das views de análise e de qualidade
(`research_session_is_authorized`). Não há prazo automático para apagar, porque há polos que entregam
pendrive meses depois. O pesquisador revisa:

```sh
python3 tooling/data/revisar-nao-autorizadas.py                       # lista (nuvem e SQLite consolidado)
python3 tooling/data/revisar-nao-autorizadas.py --apagar <session_id>  # ou --apagar-todas: o padrão
python3 tooling/data/revisar-nao-autorizadas.py --restaurar <session_id> --motivo "texto"
```

Apagar grava o tombstone em `research_withdrawals` (e no SQLite) antes de remover, o que barra reenvio
pelo bridge e reimportação por pendrive. Usa as mesmas credenciais do importador
(`PULSELAB_SERVICE_ROLE_KEY`).

O cadastro das máquinas na nuvem é automático, com um token por polo:

```sh
# 1. Token do polo (precisa da service role; o arquivo sai com permissão 0600, fora do git)
python3 supabase/scripts/provision_device.py --site-id PET --token-polo --max-usos 40 --validade-dias 60 --output token-PET.json
# 2. Pacote do polo com o token
python3 tooling/polo/gerar-pacote-polo.py --polo PET --regional Petrolina --caae <CAAE> --token-cadastro token-PET.json
```

No primeiro contato com a internet, cada máquina se cadastra pela função `enroll-device`, apaga o
token do disco e passa a renovar o acesso sozinha. O token vai dentro do ZIP do polo: se o pacote
circular fora do polo, revogue-o (`revoked_at` em `device_enrollment_tokens`) e gere outro.

## Atualização automática

Ao abrir, o launcher consulta a última release do GitHub (no máximo 2 s sem internet) e só
instala pacotes com manifesto assinado pela chave do projeto e SHA-256 conferido. A troca de
pastas guarda a versão anterior em `_update_backup` e volta para ela se o servidor local não
subir. Pré-releases não chegam às máquinas.

## Estrutura do repositório

| Pasta | Conteúdo |
|---|---|
| `runtime/windows/` | O que roda nas máquinas: launcher, atualizador, bridge, bandeja e instalador (mesmo layout da pasta `arquivos/` do ZIP) |
| `apps/student-pwa/` | Página da bancada (React + Vite); o build vai para `alunos/`, fora do git |
| `apps/site/` | Site público: início, instalador, tutorial, testes e relatório |
| `config/` | Configuração empacotada e catálogo de missões |
| `supabase/` | Migrações, testes SQL, função `enroll-device` e scripts de cadastro |
| `tooling/` | Release e versão (`release/`), site (`site/`), pacote do polo (`polo/`), importação de pendrive (`data/`) e utilitários de desenvolvimento (`dev/`) |
| `tests/` | Testes Python, PowerShell e do banco |
| `docs/` | Documentação por público: [índice](docs/README.md) |

## Desenvolvimento

```sh
cd apps/student-pwa && npm ci && npm run build && npm run test:unit && npm run test:e2e && cd ../..
python3 tooling/release/check-version-consistency.py
python3 -m unittest discover -s tests/python -p 'test_*.py'
pwsh -File tests/powershell/test-launcher-update.ps1
python3 tests/check-database.py   # Docker: migrações e RLS num Postgres descartável
```

`VERSION` é a fonte única da versão: o build injeta o número na PWA, no service worker e no site.
Toda mudança entra na `main` por PR com o CI verde. Regras para agentes de IA em
[AGENTS.md](AGENTS.md).

## Release

```sh
python3 tooling/release/bump-version.py <atual> <nova>   # no PR
./tooling/release/build-offline-package.sh               # depois do merge: dist/PulseLab-<versão>-Windows.zip
python3 tooling/release/publicar-release.py publicar --notes "PulseLab <versão> - ..."
```

O merge na `main` publica o site; publique a release logo em seguida, porque o link de download
aponta para ela. Passo a passo em [docs/engenharia/release.md](docs/engenharia/release.md).
