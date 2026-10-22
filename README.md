# PulseLab

Camada de observação das oficinas do projeto Robótica Educativa (UNIVASF). Nos computadores das
oficinas, o PulseLab inicia com o Windows e fica só como um ícone na bandeja, perto do relógio.
Um servidor local em PowerShell (porta 43128) registra a atividade de cada bancada no LEGO SPIKE,
guarda os dados no próprio computador e envia à nuvem quando há internet.

Para as crianças, só uma aba do navegador fica aberta: o **questionário do fim da aula**, opcional e
sem nome, que a bandeja abre quando o PulseLab inicia com a coleta ligada. Nenhuma outra tela,
contador ou alerta aparece durante a aula.

## Na aula

O instrutor usa o menu do ícone da bandeja (botão direito):

| Item | O que faz |
|---|---|
| **Encerrar turma…** | Fecha a gravação da turma. A próxima começa sozinha no primeiro programa salvo no SPIKE. |
| **Não registrar esta turma** | Para recusas: mostra a aula ("Aula que começou às 14:05 (50 min)"), marca como não autorizada e pausa o registro até a próxima aula. Vale para a aula em andamento ou, sem ela, para a última encerrada. |
| **Ver situação** | Mostra se o registro está ativo, pausado ou desligado. |
| **Fechar PulseLab** | Desliga tudo até o computador ser ligado de novo ou o atalho ser usado. |

Sem encerramento, a sessão fecha sozinha depois de 40 minutos sem programa salvo no SPIKE
(`ended_by = "inatividade"`, contados da última versão salva ou, sem nenhuma, do início da aula;
o fim registrado é o último programa salvo),
depois de 3 horas ou quando o computador passa mais de 20 minutos desligado ou suspenso. Depois
de fechar por inatividade, a próxima turma começa no primeiro programa salvo e, até lá, **Não
registrar esta turma** vale para a aula que fechou sozinha.

## Pesquisa e privacidade

- **Coleta desligada por padrão.** O pacote genérico não registra dados de pesquisa. A coleta só
  liga com o pacote do polo, que traz o CAAE do parecer ético em `provisionamento.json`.
- **A unidade de análise é a bancada**, nunca uma criança identificada. Sem nomes, fotos, câmera,
  áudio, captura de tela ou teclado. As respostas individuais do questionário do fim da aula não têm
  nome, mas são desidentificadas, não anônimas: linha a linha só o pesquisador (`service_role`) as
  lê; no relatório aparecem somadas por polo e mês.
- **Assentimento verbal.** No início da aula o instrutor lê o
  [roteiro padronizado](docs/campo/assentimento-verbal.md). Uma recusa leva a **Não registrar esta
  turma**: a aula é marcada como não autorizada e nunca entra em análise. A exclusão definitiva é
  feita na revisão do pesquisador, com marca contra reenvio (veja "Dados e nuvem").
- **O que é registrado:** como a sessão terminou, interrupções, situação da pasta do SPIKE e, de
  cada versão salva do programa, só os tipos de blocos. Daí saem um escore de pensamento
  computacional adaptado de Dr. Scratch (ainda não validado) e, com calendário de missões, a
  cobertura da missão do dia.
- **Questionário do fim da aula** (instrumento `bancada-3.2.0`): na aba `http://127.0.0.1:43128/alunos/`,
  a bancada responde uma vez por aula como foram os testes com os carrinhos (linha preta, corrida,
  jogo de perguntas) e cada criança, sozinha, responde cinco frases com Sim / Mais ou menos / Não.
  Toda pergunta tem **Não quero responder**. Só códigos fixos (`sim`, `em_parte`, `recusou`...), sem
  nome, idade ou texto livre. Cada resposta vira um evento da aula (`bancada_result_recorded` ou
  `student_feedback_recorded`) com um código aleatório por rodada (`submission_id`), que só junta as
  respostas da mesma criança naquela rodada. Vão para a aula ativa ou, sem ela, para a última
  encerrada; em Modo Livre, com o registro pausado ou em aula não autorizada, nada é gravado.
- **Retenção local** de `retention_days` do pacote do polo (1 a 365, padrão 180 dias), mesmo depois
  de exportar ou enviar. Aula que ainda não saiu do computador (nuvem ou pendrive) fica guardada além
  desse prazo até sair, no máximo até 31/12/2032. O prazo precisa constar no protocolo e no TCLE.
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
   registros para um pendrive e o atalho **Questionário PulseLab** reabre a aba do questionário.

Para ligar a coleta, use o pacote do polo em vez do genérico. Reinstalar por cima mantém a
identificação da máquina e os registros. Guia para instrutores:
[`docs/campo/guia-instrutor.md`](docs/campo/guia-instrutor.md).

## Dados e nuvem

Tudo fica em `dados_locais/` no computador, pasta que nenhuma atualização ou reinstalação apaga.
Com internet, o bridge envia ao Supabase a cada 30 segundos: os eventos um a um e o resumo da
sessão quando ela fecha. Polos sem internet enviam quando o instrutor conecta ou exportam por
pendrive (veja abaixo).
O relatório das aulas (uma linha por aula, resumo semanal por polo, testes com os carrinhos e o que
as crianças disseram no questionário, por polo e mês) sai com
`python3 tooling/data/relatorio-pulselab.py`: veja [docs/pesquisa/relatorio.md](docs/pesquisa/relatorio.md).

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

### Polos sem internet (pendrive)

Os dados do pendrive vão para o mesmo Supabase dos polos com internet:

1. O pacote do polo leva uma chave do polo. A mesma chave fica no computador do pesquisador, em
   `dist-polos/chaves-manifesto.json`. Gerar o pacote de novo reaproveita a chave do polo.
2. No polo, o atalho **PulseLab - Exportar Dados** copia os registros para o pendrive e assina a
   coleta com a chave. A chave fica no computador da escola e não vai para o pendrive.
3. O pesquisador conecta o pendrive e roda `tooling/data/Importar-Para-Supabase.bat` (ou
   `python3 tooling/data/importar-para-supabase.py`). O importador escolhe a chave pelo polo
   escrito na coleta e só envia à nuvem o que confere.

Guarde `dist-polos/chaves-manifesto.json` com o mesmo cuidado do token: quem tem a chave consegue
fazer uma coleta falsa daquele polo passar como verdadeira. O arquivo fica fora do git. Se gerar
pacotes em outro computador, leve o arquivo junto ou indique o caminho com `--chaves`. Se faltar a
chave de um polo, o importador diz qual polo e onde colocar o arquivo. Máquinas instaladas com um
pacote antigo exportam sem assinatura: reinstale com o pacote do polo gerado por esta versão. Sem
chave, `--no-cloud` guarda a coleta só no SQLite local.

Quando a turma não é registrada, a retirada vale mesmo se a pasta do pendrive for recusada,
porque ela só apaga dados.

## Atualização automática

Ao abrir, o launcher consulta a última release do GitHub (no máximo 2 s sem internet) e só
instala pacotes com manifesto assinado pela chave do projeto e SHA-256 conferido. A troca de
pastas guarda a versão anterior em `_update_backup` e volta para ela se o servidor local não
subir. Pré-releases não chegam às máquinas.

## Estrutura do repositório

| Pasta | Conteúdo |
|---|---|
| `runtime/windows/` | O que roda nas máquinas: launcher, atualizador, bridge, bandeja e instalador (mesmo layout da pasta `arquivos/` do ZIP) |
| `apps/student-pwa/` | Questionário do fim da aula (React + Vite); o build vai para `alunos/`, fora do git |
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
```

Depois do merge: **Actions → Publicar release → Run workflow** e aprovar no ambiente `release`. O
workflow gera o pacote, assina com a chave guardada no secret do GitHub (ela não fica em computador
nenhum) e cria a release. O merge na `main` publica o site; publique a release logo em seguida,
porque o link de download aponta para ela. Passo a passo em [docs/engenharia/release.md](docs/engenharia/release.md).
