# Arquitetura da Aplicação de Alunos (PWA v2.3.3)

## 1. Decisão Arquitetural e Visão Geral

A aplicação de observabilidade para as oficinas de robótica escolar é implementada como
uma Progressive Web App (PWA) desenvolvida em React e Vite. O build é compilado de forma
estática e publicado no diretório `alunos/`, sendo servido localmente em loopback pelo
Bridge PowerShell (`http://127.0.0.1:43128/alunos/`) ou hospedado em servidor web.

Essa abordagem garante equivalência total entre ambientes: desenvolvimento no Linux/macOS
e execução nas salas de aula Windows rodam exatamente o mesmo artefato web, a mesma máquina
de estados, o mesmo armazenamento local e o mesmo Service Worker offline.

## 2. Princípios de Experiência e Salvaguardas Éticas (v2.3.3)

### 2.1 Experiência Silenciosa do Aluno
- **Zero Interrupção Pedagógica**: Durante a atividade prática, a tela não exibe questionários,
  escalas Likert, formulários, caixas de diálogo ou alarmes de checkpoint aos 20 ou 40 minutos.
- **Tela Neutra e Serena**: A interface exibe exclusivamente a mensagem orientadora:
  > *“Oficina de robótica em andamento. Use o aplicativo LEGO SPIKE. Monte, programe e teste o seu robô na bancada.”*
- **Foco Integral na Aprendizagem Maker**: Os estudantes concentram 100% de sua atenção na
  montagem física do kit e na programação no software oficial LEGO SPIKE Prime.

### 2.2 Bancada Coletiva como Unidade de Análise (LGPD Art. 14)
- **Unidade de Observação**: A bancada colaborativa de 2 a 8 integrantes (`group_size`).
- **Proteção Integral de Menores**: Não são coletados nomes, fotos, vídeos, áudios, e-mails,
  matrículas, digitação de teclas (`GetAsyncKeyState`) nem capturas de tela (screenshots).
- **Sem Rastreamento Individual**: Não existem identificadores individuais de crianças. Apenas
  identificadores efêmeros da bancada (`session_id`, `group_id`) e operacionais do dispositivo
  (`installation_id`, `machine_label`, `site_id`).

### 2.3 Coleta Passiva de Telemetria SPIKE
- A PWA executa polling periódico a cada 10 segundos via `GET http://127.0.0.1:43128/v1/spike/metrics`.
- O parser de projetos (`lib/spike-parser.js`) analisa arquivos `.llsp3`, Scratch `.sb3` e scripts
  Python salvos pela bancada.
- Extrai apenas contagens estruturais agregadas: blocos executáveis, pilhas de blocos, presença
  de motores, sensores, loops e condições, sem jamais registrar código-fonte bruto, comentários,
  nomes de variáveis ou identificadores de hardware.

### 2.4 Encerramento de Turma pelo Educador/Bancada
- A sessão da turma abrange todo o período desde a abertura do app (ou conclusão da turma anterior)
  até o acionamento do botão discreto **"Encerrar turma"**.
- Ao final da oficina, o fluxo apresenta duas etapas concisas:
  1. **Avaliação da Bancada**: Uma pergunta rápida com 4 carinhas (*"Como foi a oficina para a sua bancada hoje?"*, com opção *"Preferimos não responder"*).
  2. **Registro do Educador**: Avaliação pedagógica de desfecho com resultado prático (0 a 3: *Não concluiu*, *Concluiu em parte*, *Concluiu a missão*, *Concluiu e foi além*) e apoio recebido (*nenhum*, *algum*, *muito*, ou *Pular avaliação*).
- Concluído o registro, a sessão é finalizada e o aplicativo fica pronto para a próxima turma.

### 2.5 Modo Laboratório (`?lab=1`)
- Acesso restrito a engenharia via parâmetro de busca na URL (`?lab=1`).
- Permite diagnosticar a conexão com o Bridge, verificar métricas de telemetria em tempo real,
  injetar telemetria sintética e acionar expurgo ético de dados sem interferir na visualização
  silenciosa das crianças.

## 3. Topologia e Componentes

```text
Navegador do Estudante (PWA React/Vite em /alunos/)
├── Shell estático e Service Worker offline (sw.js)
├── Interface silenciosa para estudantes (student-page.jsx)
├── Modal de encerramento rápido da turma (contracts.js)
├── Parser de projetos LEGO SPIKE (.llsp3 / .sb3 / Python)
├── Persistência local no IndexedDB (pulselab-student-runner)
└── Sincronizador de eventos em lote (sync-engine.js)
            ↕ (Loopback HTTP em 127.0.0.1:43128)
Bridge Local PowerShell (Windows)
├── Servidor HTTP estático seguro
├── Monitoramento de arquivos SPIKE (spike-parser.ps1)
├── Persistência dupla em disco (dados_locais/events.jsonl e sessions.jsonl)
└── Limpeza atômica por prazo de retenção (Invoke-BridgeRetentionCleanup)
            ↓ (Store-and-Forward a cada 30 segundos, quando online)
Supabase Backend (Postgres com RLS)
├── Edge Function autenticada (enroll-device)
├── Tabela de eventos (research_session_events)
└── Tabela de sessões concluídas (research_session_snapshots)
```

## 4. Persistência em Dupla Camada e Retenção

1. **Camada do Navegador**: IndexedDB `pulselab-student-runner` com object stores `events` e
   `sessions` manipulados transacionalmente por `lib/student-store.js`.
2. **Camada do Bridge Local**: Toda mutação é enviada em loopback ao Bridge (`/v1/events` e
   `/v1/sessions/save`) e gravada em formato append-only (`dados_locais/events.jsonl` e
   `dados_locais/sessions.jsonl`).
- **Retenção Local Configurável**: Dados no IndexedDB e no Bridge expiram no prazo `retention_days`
  definido no provisionamento do polo (padrão de 180 dias, ajustável de 1 a 365 dias).
- **Retirada Ética Imediata**: O acionamento do botão "Parar de participar e apagar meus dados"
  purga imediatamente o IndexedDB, apaga os arquivos da sessão ativa no Bridge e grava um
  tombstone que impede ressincronização.

## 5. Governança Fail-Closed e Modos de Operação

- **Modo Livre (Padrão)**: O pacote genérico opera com a coleta desativada (`research_collection_enabled: false`).
  Nenhum evento é gravado em disco ou transmitido para a nuvem.
- **Modo Pesquisa (Autorizado)**: A coleta só é ativada quando o pacote do polo inclui um
  `provisionamento.json` gerado com número de CAAE oficial aprovado pelo comitê de ética (CEP/CONEP)
  e credenciais rotativas de dispositivo.
- **Transmissão e Exportação**:
  - Máquinas conectadas transmitem a cada 30 segundos para o Supabase.
  - Máquinas offline exportam os registros para pendrive via atalho **PulseLab - Exportar Dados**,
    gerando um arquivo ZIP com manifesto e checksum SHA-256.

## 6. Pipeline de Garantia de Qualidade

- **Testes Unitários**: `npm run test:unit` valida os contratos do instrumento, parser SPIKE,
  store IndexedDB e regras de governança fail-closed.
- **Testes E2E (Playwright)**: `npm run test:e2e` valida a experiência silenciosa, encerramento
  de turma e funcionamento offline pelo Service Worker.
- **Validação de Consistência**: `python3 scripts/check-version-consistency.py` assegura que
  todas as superfícies operacionais permaneçam estritamente sincronizadas na versão canônica.
