# Relatório das aulas

O relatório junta o que chegou pela internet (Supabase) e o que veio por pendrive (SQLite do
importador) numa tabela com **uma linha por aula de bancada**, isto é, o que um computador
registrou durante uma turma. A mesma aula nunca aparece duas vezes, mesmo que tenha chegado pelos
dois caminhos. Aulas que a turma pediu para não registrar ficam de fora.

Não há nomes, fotos nem texto livre: só os campos descritos abaixo.

## Como gerar

```sh
# Só com o pendrive, sem internet (depois de importar com --no-cloud)
python3 tooling/data/relatorio-pulselab.py --sqlite dados_locais/pulselab_consolidado.sqlite --sem-nuvem

# Nuvem e pendrive, só um polo e um mês
python3 tooling/data/relatorio-pulselab.py --de 2026-10-01 --ate 2026-10-31 --polo PET
```

| Opção | O que faz |
|---|---|
| `--sqlite arquivo` | SQLite do importador. Sem a opção, usa `dados_locais/pulselab_consolidado.sqlite` se existir. |
| `--sem-nuvem` | Não acessa a internet, mesmo com credencial configurada. |
| `--de` / `--ate` | Período das aulas, no formato `AAAA-MM-DD` (inclusive). |
| `--polo` | Só um polo (código do pacote do polo, ex.: `PET`). |
| `--saida pasta` | Onde gravar. Padrão: `relatorios/AAAA-MM-DD/` (fora do git). |
| `--hoje AAAA-MM-DD` | Data de referência para contar dias sem dados. Padrão: hoje. |

A nuvem usa a mesma credencial do importador (`PULSELAB_SERVICE_ROLE_KEY` ou
`PULSELAB_OPERATIONAL_JWT`). Sem credencial, o relatório usa só o pendrive. Com o JWT de
pesquisador, aparecem só os polos aos quais a conta está vinculada.

Os CSV abrem direto no Excel em português: separador `;`, vírgula decimal, `sim`/`não`. No R ou no
pandas, use `sep=';'` e `decimal=','`.

Horários estão no fuso dos polos (UTC-3). Semanas começam na segunda-feira.

## Arquivos

### `relatorio.md`

Resumo para leitura: totais, a seção **Atenção** (máquinas sem dados há mais de 7 dias e aulas com
qualidade ruim), o resumo semanal por polo e a lista de aulas.

### `aulas.csv`: uma linha por aula

| Coluna | Significado |
|---|---|
| `session_id` | Código aleatório da aula. Serve só para não duplicar. |
| `polo` | Código do polo. |
| `escola` | Código da escola do pacote do polo (`nao_informado` quando faltou). |
| `maquina` | Rótulo da máquina escolhido na instalação (ex.: `PET-LAB1-PC03`). |
| `installation_id` | Código aleatório da instalação do PulseLab na máquina. |
| `data_local`, `hora_inicio`, `hora_fim` | Dia e horários da aula. Sem `hora_fim`, a aula não foi encerrada. |
| `duracao_min` | Duração em minutos. |
| `encerrada_por` | `instrutor` (menu da bandeja), `tempo` (limite de 3 horas) ou `sem_encerramento` (computador desligado ou suspenso por mais de 20 minutos). |
| `interrompida` | `sim` se o computador ficou sem sinal no meio da aula, o PulseLab reiniciou ou houve registro corrompido. |
| `fase` | `completed` (encerrada) ou `in_progress` (ainda aberta quando os dados saíram). |
| `modo_inicio` | `atividade_spike` (começou no primeiro programa salvo) ou `abertura_app` (começou quando o PulseLab abriu). |
| `versoes_programa` | Quantas versões diferentes do programa a bancada salvou no SPIKE. |
| `blocos_executaveis` | Blocos que fazem algo no último programa salvo. |
| `usa_motor`, `usa_sensor`, `usa_laco`, `usa_condicao` | Se o último programa usa motor, sensor, repetição ou condição (se/senão). |
| `ct_score` | Escore de pensamento computacional do último programa (0 a 21), adaptado de Dr. Scratch, **ainda não validado**. Vazio em programas Python. |
| `spike_status` | Situação da leitura do SPIKE no fim da aula: `ok`, `python`, `sem_alteracao`, `sem_projeto`, `pasta_nao_encontrada`, `arquivo_invalido`, `arquivo_bloqueado`, `leitor_indisponivel`. |
| `sinais_de_vida` | Quantos sinais de vida o PulseLab registrou durante a aula. |
| `maior_lacuna_min` | Maior intervalo sem sinal de vida, em minutos. |
| `reinicios` | Quantas vezes o PulseLab reiniciou durante a aula. |
| `linhas_corrompidas` | Registros ilegíveis encontrados ao retomar a aula. |
| `client_version` | Versão do PulseLab na máquina (ex.: `bridge/3.0.9`). |
| `instrument_version` | Versão do instrumento de pesquisa. |
| `origem` | `nuvem`, `pendrive` ou `nuvem+pendrive`. |
| `qualidade` | `boa` ou `ruim`. |
| `motivo_qualidade` | Por que é ruim: `aula não encerrada`, `interrompida`, `nenhum programa salvo`, `problema no SPIKE (...)`. |

Campo vazio quer dizer que a informação não chegou. Pendrives importados antes desta versão do
importador não trazem `maquina`, `installation_id`, `modo_inicio` e as versões: importe-os de novo.

### `resumo-polos.csv`: por polo e semana

| Coluna | Significado |
|---|---|
| `polo` | Código do polo. |
| `semana_inicio` | Segunda-feira da semana. |
| `aulas` | Número de aulas de bancada. |
| `maquinas` | Número de máquinas diferentes com aula. |
| `duracao_mediana_min` | Duração do meio: metade das aulas durou menos, metade mais. Aulas abertas não entram. |
| `pct_encerradas_instrutor` | % das aulas encerradas pelo instrutor no menu da bandeja. |
| `pct_interrompidas` | % das aulas interrompidas. |
| `pct_sem_spike` | % das aulas sem nenhum programa salvo no SPIKE. |

### `maquinas-sem-envio.csv`: uma linha por máquina

Todas as máquinas conhecidas, da que está há mais tempo sem dados para a mais recente. Com a nuvem,
inclui máquinas cadastradas que nunca enviaram nada.

| Coluna | Significado |
|---|---|
| `polo`, `maquina`, `installation_id` | Identificação da máquina. |
| `ultimo_envio_nuvem` | Quando chegou o último dado pela internet. |
| `aulas_30d_nuvem` | Aulas recebidas pela internet nos últimos 30 dias. |
| `ultima_aula_pendrive` | Data da última aula vinda por pendrive. |
| `ultimo_dado` | O mais recente entre os dois caminhos. |
| `dias_sem_dados` | Dias desde `ultimo_dado`. |
| `situacao` | `ok`, `sem dados há mais de 7 dias` ou `nunca enviou dados`. |

## Origem dos dados

Na nuvem, o relatório lê a view `research_aula_bancada`, que achata o resumo da sessão enviado pelo
bridge, e a view `research_installation_last_seen`. As duas respeitam o acesso das tabelas
(`security_invoker`). No pendrive, lê as tabelas `sessions` e `session_events` do SQLite do
importador.
