# Inventário de Dados e Governança Ética — PulseLab v2.3.3

A fonte canônica dos contratos e itens do instrumento é `web/agent-simulator/lib/contracts.js`,
cujo manifesto possui integridade garantida pelo hash canônico `CONFIG_HASH` (SHA-256).

---

## 1. Famílias de Dados e Minimização (LGPD Art. 14)

Em conformidade estrita com o Art. 14 da LGPD (proteção de dados de crianças e adolescentes),
**o PulseLab não coleta, não processa e não armazena dados pessoais individualizados de menores**:
são terminantemente proibidos nomes, fotos, vídeos, áudios, endereços IP externos, e-mails,
matrículas escolares, CPF ou registros de digitação de teclas.

A unidade de análise é a **bancada coletiva** (`group_size` entre 2 e 8 estudantes).

| Família | Campos e Representação | Finalidade Operacional | Limites de Minimização e Salvaguardas |
|---|---|---|---|
| **Contexto** | `site_id`, `school_code`, `workshop_code`, `class_code`, `machine_label` | Agrupamento de sessões por polo e turma | Valores não informados são normalizados para `nao_informado`. Nenhum nome próprio de pessoa ou dados privados de computadores escolares. |
| **Bancada e Sessão** | `session_id` (UUID efêmero), `group_id` (UUID efêmero), `group_size` (inteiro de 2 a 8) | Identificação técnica da bancada na oficina | Unidade é sempre a bancada coletiva; impede qualquer correlação com indivíduos específicos ou identificação longitudinal de alunos. |
| **Telemetria de Robótica (SPIKE)** | `executable_blocks`, `top_level_stacks`, `uses_motor`, `uses_sensor`, `uses_loop`, `uses_condition`, `inferred_stage` | Observabilidade passiva do progresso técnico e complexidade do projeto | **Zero código bruto**: proibida a extração de nomes de variáveis, comentários, strings livres, áudios do Scratch, UUIDs de blocos ou identificadores Bluetooth do Hub. |
| **Avaliação da Bancada (Encerramento)** | `experiencia_bancada_v1` (escala nominal de 4 carinhas: 1 a 4) ou `null` (recusa) | Percepção coletiva da bancada sobre a oficina realizada | Registro coletivo único no encerramento da turma. Botão "Preferimos não responder" respeita a recusa sem penalidades ou substituição por zero. |
| **Avaliação do Educador (Encerramento)** | `resultado_bancada_v1` (0 a 3) e `apoio_instrutor_v1` (`nenhum`, `algum`, `muito`) | Desfecho pedagógico imediato observado da missão | Rubrica preenchida pelo educador após a oficina; separada em resultado da tarefa e nível de apoio prestado. Não calcula "nota" ou diagnóstico psicológico infantil. |
| **Linha do Tempo (Eventos)** | `session_started`, `spike_telemetry`, `ending_requested`, `experience_recorded`, `rubric_completed`, `session_completed`, `session_aborted` | Registro temporal da oficina para análise de processos pedagógicos | Timestamps gerados localmente; eventos append-only estruturados sem campos arbitrários. |

---

## 2. Persistência em Dupla Camada e Retenção

Os dados coletados são salvos simultaneamente em duas camadas locais e atômicas:
1. **Camada do Navegador**: Banco IndexedDB `pulselab-student-runner` com os object stores transacionais `events` e `sessions`.
2. **Camada do Bridge Local**: Arquivos locais em disco na pasta `dados_locais/` (`dados_locais/events.jsonl` e `dados_locais/sessions.jsonl`).

### 2.1 Prazo de Retenção Local (`retention_days`)
- Os registros permanecem gravados no computador por `retention_days` dias, conforme definido no arquivo de provisionamento do polo (`provisionamento.json`, padrão de 180 dias, configurável de 1 a 365 dias).
- A cópia local é mantida durante todo o período, mesmo após envio com sucesso para a nuvem ou exportação para pendrive.
- O navegador executa expurgo periódico (`enforceAbsoluteRetention`) e o Bridge executa limpeza automática horária (`Invoke-BridgeRetentionCleanup`).

### 2.2 Retirada Ética e Expurgo Imediato
- A qualquer momento, o botão **"Parar de participar e apagar meus dados"** pode ser acionado.
- A ação:
  1. Purga atomicamente o IndexedDB local;
  2. Apaga os arquivos da sessão ativa no Bridge;
  3. Registra um **tombstone** durável que impede qualquer sincronização futura ou reexportação de dados daquela bancada;
  4. Executa requisição autenticada de exclusão remota no Supabase.

---

## 3. Transmissão, Nuvem e Exportação Offline

- **Modo Livre por Padrão**: Pacotes genéricos iniciam com `research_collection_enabled = false`. Nenhum dado de pesquisa é persistido ou transmitido sem a presença de `provisionamento.json` gerado com número de CAAE oficial do comitê de ética (CEP/CONEP).
- **Sincronização em Nuvem (Supabase)**: Máquinas conectadas transmitem eventos via Store-and-Forward a cada 30 segundos, sob tokens rotativos de dispositivo gerenciados pelo Bridge.
- **Exportação Física (Pendrive)**: Em escolas sem internet, o atalho **PulseLab - Exportar Dados** consolida os registros locais em um arquivo ZIP portátil com manifesto de auditoria e checksum SHA-256.
