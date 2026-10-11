# Handoff Técnico Consolidado — PWA dos Alunos, Bridge PowerShell e SPIKE (v2.3.3)

> Versão Operacional: **2.3.2**
> Status: **Implementado, Validado e em Produção**
> Componentes Principais: PWA React (`web/agent-simulator/` compilada em `alunos/`), Bridge Loopback (`bridge/pulselab-bridge.ps1`), Parser SPIKE (`spike-parser.js` e `spike-parser.ps1`) e Sincronização Cloud/Offline.

---

## 1. Visão Geral da Arquitetura

O PulseLab é uma plataforma de observabilidade pedagógica para oficinas de robótica escolar com kits LEGO SPIKE Prime (UNIVASF). O sistema opera de forma híbrida e não invasiva:

```text
Bridge Local Windows (PowerShell 5.1 na porta 43128)
├── Servidor HTTP loopback seguro (TcpListener em 127.0.0.1:43128)
├── Servidor de arquivos estáticos da PWA (pasta alunos/)
├── Monitoramento de arquivos LEGO SPIKE (spike-parser.ps1)
├── Persistência dupla em disco (dados_locais/events.jsonl e sessions.jsonl)
├── Gerenciamento de tokens de polo e auto-cadastro
└── Limpeza atômica periódica por retenção (Invoke-BridgeRetentionCleanup)
                    ↕ (HTTP Loopback)
PWA dos Alunos (React/Vite em /alunos/)
├── Interface silenciosa dos estudantes (student-page.jsx)
├── Coleta passiva periódica da telemetria SPIKE a cada 10s (/v1/spike/metrics)
├── Encerramento de turma (avaliação de bancada + rubrica do educador)
├── Persistência em IndexedDB (pulselab-student-runner)
├── Painel de diagnóstico de engenharia no Modo Laboratório (?lab=1)
└── Motor de envio em lote para Supabase a cada 30s (sync-engine.js)
```

---

## 2. Princípios Operacionais e Salvaguardas Éticas

### 2.1 Experiência Silenciosa do Aluno
- A rota padrão dos alunos (`http://127.0.0.1:43128/alunos/`) é **100% silenciosa**.
- **Sem interrupções**: não há formulários, questionários de autoeficácia, escalas Likert nem alertas intrusivos durante a oficina.
- A tela exibe uma mensagem tranquila e neutra:
  > *“Oficina de robótica em andamento. Use o aplicativo LEGO SPIKE. Monte, programe e teste o seu robô na bancada.”*
- Todo o foco cognitivo das crianças permanece na montagem física e na programação no aplicativo oficial do robô.

### 2.2 Bancada Coletiva como Unidade de Análise (LGPD Art. 14)
- A unidade analítica da pesquisa é a **bancada colaborativa** (`group_size` entre 2 e 8 integrantes).
- **Proteção a menores**: não são coletados nomes, fotos, vídeos, áudios, endereços IP externos, e-mails, matrículas ou identificadores individuais de crianças.
- Interceptação global de teclado (`GetAsyncKeyState`) e capturas de tela (screenshots) foram totalmente abolidas do projeto.
- Dispositivos são identificados por um `installation_id` aleatório gravado em `dados_locais/installation.json` e por um rótulo amigável escolhido na instalação (ex.: `PET-LAB1-PC03`). O nome do usuário do Windows ou da máquina não são expostos.

### 2.3 Coleta Passiva de Telemetria SPIKE
- A cada 10 segundos, a PWA consulta `/v1/spike/metrics` do Bridge.
- O Bridge monitora a pasta de projetos em `Documents\LEGO Education\SPIKE 3` (e equivalentes) e lê arquivos `.llsp3`, Scratch `.sb3` ou scripts Python recém-salvos.
- O parser (`spike-parser.js` no frontend e `spike-parser.ps1` no Bridge) extrai apenas contagens estruturais agregadas:
  - `executable_blocks`: total de blocos funcionais;
  - `top_level_stacks`: pilhas de execução independentes;
  - `uses_motor`, `uses_sensor`, `uses_loop`, `uses_condition`: flags booleanas de categorias utilizadas;
  - `inferred_stage`: estágio técnico deduzido da estrutura do código.
- **Privacidade total**: variáveis criadas pelos alunos, comentários, textos livres, arquivos de áudio ou identificadores Bluetooth do Hub nunca são extraídos ou persistidos.

### 2.4 Encerramento de Turma pelo Educador e Bancada
- A sessão da turma vai da abertura do app (ou encerramento da turma anterior) até o clique no botão discreto **"Encerrar turma"**.
- Ao final da oficina, o modal exibe:
  1. **Avaliação da Bancada**: Uma pergunta com 4 carinhas (*"Como foi a oficina para a sua bancada hoje?"*, opções de 1 a 4 ou *"Preferimos não responder"*).
  2. **Registro do Educador**: Avaliação rápida de resultado (0 a 3: *Não concluiu*, *Concluiu em parte*, *Concluiu a missão*, *Concluiu e foi além*) e apoio recebido (*nenhum*, *algum*, *muito*, ou *Pular avaliação*).
- Os contratos formais e hashes canônicos residem em `web/agent-simulator/lib/contracts.js` (`INSTRUMENT_MANIFEST`, `CONFIG_HASH`).

### 2.5 Modo Laboratório (`?lab=1`)
- Acessível adicionando o parâmetro `?lab=1` na URL da aplicação.
- Exclusivo para inspeção de engenharia e simulação:
  - Painel de status da conexão com o Bridge e contadores de eventos;
  - Visualização em tempo real das métricas da telemetria SPIKE;
  - Disparo de eventos simulados e testes de carga;
  - Gatilho manual para teste de retirada ética com expurgo de dados.

---

## 3. Persistência em Dupla Camada e Governança

### 3.1 Armazenamento Duplo
1. **IndexedDB do Navegador**: O banco `pulselab-student-runner` gerencia os object stores `events` e `sessions` via `lib/student-store.js`.
2. **Arquivos Locais em Disco no Bridge**: Toda mutação enviada para o Bridge é persistida em formato append-only seguro em `dados_locais/events.jsonl` e `dados_locais/sessions.jsonl`.
- Essa arquitetura garante imunidade a crashes do navegador, reinicializações acidentais ou sistemas com congelamento de disco (como Deep Freeze com exclusão de pastas).

### 3.2 Política de Retenção Configurável
- Registros locais expiram de acordo com o parâmetro `retention_days` do pacote do polo (padrão de 180 dias, configurável de 1 a 365 dias).
- O navegador executa `enforceAbsoluteRetention` ao iniciar e o Bridge executa `Invoke-BridgeRetentionCleanup` a cada hora, expurgando registros antigos de forma atômica.

### 3.3 Retirada Ética Imediata
- O botão "Parar de participar e apagar meus dados" executa a exclusão definitiva imediata de todos os dados locais no IndexedDB e no Bridge.
- Registra um tombstone durável que impede que eventos daquela sessão sejam ressincronizados ou exportados posteriormente.

---

## 4. Distribuição Portátil, Atualização e Sincronização

### 4.1 Estrutura 100% Portátil
O PulseLab é distribuído em um pacote ZIP autônomo que não requer instalação com privilégios de administrador:
```text
PulseLab-2.3.2-Windows/
├── Instalar-PulseLab.bat
├── Iniciar-PulseLab.bat
├── pulselab.ps1
├── bridge/
│   ├── pulselab-bridge.ps1
│   └── spike-parser.ps1
├── alunos/               # PWA React compilada pelo Vite
├── config/
│   ├── defaults.json
│   └── config.json
├── dados_locais/         # Preservada entre atualizações
│   ├── installation.json
│   ├── events.jsonl
│   └── sessions.jsonl
├── release-public-key.json
└── VERSION
```

### 4.2 Atualização Automática Assinada por Chave RSA
- O launcher consulta o manifesto `pulselab-update.json` da última release publicada no GitHub com timeout rápido (2 s).
- O manifesto precisa estar assinado por chave privada RSA-SHA256 externa ao repositório.
- A chave pública acompanha o pacote (`release-public-key.json`). Sem ela ou com assinatura inválida, nenhuma atualização ocorre.
- O ZIP baixado tem seu hash SHA-256 conferido contra o manifesto assinado e é instalado por troca atômica de pastas.
- Se o servidor local não responder após a troca, a versão anterior é restaurada imediatamente a partir de `_update_backup`.
- As pastas `dados_locais/` e `provisionamento.json` **nunca são sobrescritas ou apagadas**.

### 4.3 Sincronização em Nuvem (Supabase) e Exportação em Pendrive
- **Online**: Máquinas com internet realizam sincronização Store-and-Forward a cada 30 segundos com o Supabase via Edge Function autenticada (`enroll-device`). O token do polo é utilizado no primeiro contato e trocado por credenciais de máquina rotativas.
- **Offline**: Em escolas sem conexão, o educador utiliza o atalho **PulseLab - Exportar Dados**, gerando um arquivo ZIP com manifesto e checksum SHA-256 para transporte em pendrive.

---

## 5. Comandos de Manutenção e Testes

Para validar a integridade da aplicação:
```bash
# Testes unitários do frontend e contratos
cd web/agent-simulator && npm ci && npm run test:unit && npm run build

# Validação estrita de sincronização de versão
python3 scripts/check-version-consistency.py

# Testes de unidade dos scripts operacionais
python3 -m unittest scripts.test_importador scripts.test_council scripts.test_release scripts.test_build_hosting scripts.test_bridge_cloud

# Validação do servidor portátil e sintaxe PowerShell
pwsh -File scripts/test-portable-server.ps1
```
