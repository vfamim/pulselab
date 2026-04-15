# PLAN-pulselab-mvp

> [!IMPORTANT]
> Revisao: 2026-04-15 — Decisoes do usuario incorporadas. Plano aprovado para FASE 4.

## Overview

**Pulselab** e um motor de observabilidade e coleta de engajamento para um projeto de educacao em robotica em escolas publicas. Alunos em duplas ou trios compartilham computadores Windows para programar kits LEGO Spike. O sistema coleta o nivel de dificuldade percebido em intervalos aleatorios com o minimo de interrupcao possivel (1 a 2 cliques).

O produto final e um daemon PowerShell invisivel, distribuido via atalho de startup, que dispara um pop-up kiosk no canto inferior direito da tela, captura a resposta do aluno e a persiste no Supabase — com resiliencia offline total.

---

## Project Type

**BACKEND + CLIENT-AGENT** — Nao e uma aplicacao web nem mobile. E um agente de sistema headless com interface grafica nativa (WinForms) e integracao com backend-as-a-service (Supabase/PostgreSQL via REST).

| Agente | Responsabilidade |
|--------|-----------------|
| `backend-specialist` | Contrato REST Supabase, cache offline, logica de retry |
| `devops-engineer` | Distribuicao via startup, GitOps pipeline |
| `security-auditor` | Gestao de secrets, surface de ataque, zero-priv |
| `database-architect` | Schema Supabase, RLS, DDL versionado |

---

## Success Criteria

| # | Criterio | Verificacao |
|---|----------|-------------|
| 1 | Script inicia em background sem janela de terminal visivel | Task Manager mostra processo sem janela associada |
| 2 | Pop-up dispara nos intervalos fixos de 5, 15 e 30 minutos por sessao | Log timestampado em `pulselab.log` com marcacao de intervalo |
| 3 | Fechar o pop-up apos clicar leva menos de 500ms e NAO fecha/minimiza o LEGO Spike | Timestamp no log; foco retorna ao Spike apos fechamento do form |
| 4 | Payload JSON enviado ao Supabase com sucesso | Linha registrada na tabela `responses` |
| 5 | Falha de rede grava payload em cache local | Arquivo `.cache/queue.json` existe e tem conteudo valido |
| 6 | Retry batch no proximo ciclo descarrega o cache | Cache esvaziado apos reconexao |
| 7 | Alteracoes de config via GitHub atualizam comportamento no proximo ciclo | Pull via `Invoke-WebRequest` no inicio de cada ciclo |
| 8 | Zero elevacao de privilegio necessaria | Script executa como usuario padrao sem prompt UAC |
| 9 | Cada aluno e identificado individualmente mesmo compartilhando a maquina | `student_id` registrado por sessao via prompt inicial no primeiro pop-up |

---

## Restricoes Arquiteturais (Nao Negociaveis)

| Restricao | Razao |
|-----------|-------|
| Zero instalacao de .exe | Politica de TI de escolas publicas: sem UAC |
| PowerShell 5.1+ apenas | Versao padrao no Windows 10 LTSC escolar |
| System.Windows.Forms (WinForms) | Nativo no .NET Framework, zero dependencias externas |
| Supabase via REST puro (`Invoke-RestMethod`) | Sem SDK, sem npm, sem nada instalado |
| Secrets fora do repositorio | Variaveis de ambiente de usuario via `setup-startup.ps1` |
| GitOps para configuracao | `config.json` versionado no GitHub, lido remotamente no boot de cada ciclo |
| Pop-up NAO pode fechar o LEGO Spike | Form e `TopMost` mas sem capturar foco permanente; foco retorna ao Spike pos-clique |
| Intervalo fixo: 5, 15 e 30 minutos | Padrao pedagogico definido pelo pesquisador; sem aleatoriedade nos intervalos |

---

## Tech Stack

| Camada | Tecnologia | Justificativa |
|--------|------------|---------------|
| Agent/Client | PowerShell 5.1 + WinForms | Nativo, zero deps, sem UAC |
| UI | `System.Windows.Forms.Form` | Popup modal kiosk sem borda |
| Networking | `Invoke-RestMethod` (HTTPS) | Built-in no PS 5.1 |
| Persistencia Remota | Supabase REST API (PostgreSQL) | BaaS gerenciado, sem servidor proprio |
| Cache Local | `.cache/queue.json` (`ConvertTo-Json`) | Fila offline-first |
| Configuracao | GitHub raw content URL | GitOps: single source of truth |
| Distribuicao | Atalho `.lnk` em `shell:startup` | Zero UAC, por-usuario |
| Logging | `pulselab.log` (append) | Auditoria de sessoes e erros |

---

## File Structure

```
pulselab/
├── docs/
│   └── PLAN-pulselab-mvp.md          # Este plano
├── agent/
│   └── pulselab-agent.ps1            # Script principal (daemon)
├── config/
│   └── config.json                   # Config GitOps (versionada no GitHub)
├── installer/
│   └── setup-startup.ps1             # Cria atalho em shell:startup (sem UAC)
├── schema/
│   └── supabase-schema.sql           # DDL da tabela responses
├── .cache/
│   └── queue.json                    # Cache offline (gitignored)
├── .gitignore
└── README.md
```

> `.cache/` e `*.log` devem estar no `.gitignore`. Nunca commitar dados de alunos ou secrets.

---

## Architecture Decision Records (ADRs)

### ADR-001: WinForms sobre alternativas

**Decisao:** `[System.Windows.Forms.Form]` em PowerShell.

| Alternativa | Motivo da Rejeicao |
|-------------|-------------------|
| HTML/HTA | Obsoleto no Windows 10 moderno, rendering inconsistente |
| AutoHotKey | Binario externo, politica de TI pode bloquear |
| Electron | Exige instalacao, ~150MB, fora de escopo |
| WinForms | 100% nativo no .NET Framework 4.x, zero deps, controle total de posicao e `TopMost` |

### ADR-002: Offline-first com fila local

**Decisao:** Toda tentativa de POST e envolta em `try/catch`. Em caso de falha, o payload e serializado via `ConvertTo-Json` e appendado a `.cache/queue.json`. O inicio de cada ciclo executa `Invoke-FlushCache` antes de registrar nova resposta.

**Razao:** Rede escolar e extremamente intermitente. Perder dados de sessao e inaceitavel para o projeto de pesquisa.

### ADR-003: GitOps para config remota

**Decisao:** `config.json` e lido de uma URL raw do GitHub no inicio de cada ciclo via `Invoke-WebRequest`. Se a requisicao falhar, usa ultimo config cacheado localmente.

**Razao:** Permite alterar intervalos, perguntas e endpoints sem redistribuir o script para cada maquina.

### ADR-004: Secrets via variavel de ambiente de usuario

**Decisao:** `SUPABASE_ANON_KEY` e `SUPABASE_URL` sao lidos de variaveis de ambiente de usuario, configurados por `setup-startup.ps1` via `[Environment]::SetEnvironmentVariable(..., "User")`.

**Razao:** Secrets nunca devem residir em arquivos no repositorio. Variaveis de usuario nao exigem elevacao de privilegio.

### ADR-005: Overlay sem captura de foco (LEGO Spike compatibility)

**Decisao:** O `Form` exibido usa `TopMost = $true` e `ShowDialog()`, mas apos o clique do aluno o foco e devolvido explicitamente ao processo LEGO Spike via `[System.Windows.Forms.Form]::ActiveForm` + `SetForegroundWindow` via P/Invoke.

**Razao:** O ambiente de trabalho do aluno e o LEGO Spike Education App. Qualquer interrupcao que minimize ou desfoque o aplicativo perde o estado de fluxo da atividade e ja causa a friccao que o sistema tenta minimizar. O pop-up deve ser percebido como um overlay nao-destrutivo.

**Implementacao:**
```powershell
# Antes de exibir o form: capturar handle do processo LEGO Spike
$spikeProcess = Get-Process | Where-Object { $_.MainWindowTitle -match 'Spike' } | Select-Object -First 1
$spikeHandle  = if ($spikeProcess) { $spikeProcess.MainWindowHandle } else { [IntPtr]::Zero }

# Exibir popup
$form.ShowDialog()

# Apos fechamento: devolver foco ao Spike
if ($spikeHandle -ne [IntPtr]::Zero) {
    [Win32.NativeMethods]::SetForegroundWindow($spikeHandle) | Out-Null
}
```

### ADR-006: Identificacao de aluno por sessao (student_id)

**Decisao:** No inicio de cada ciclo daemon (boot do script), antes do primeiro sleep, um form WinForms simples exibe campos de texto para cada aluno informar seu nome ou codigo. Os dados sao armazenados em memoria para a sessao e vinculados a todos os payloads daquela sessao.

**Razao:** Multiplos alunos compartilham a mesma maquina em turnos. Para rastrear dificuldade por aluno (nao por maquina), e necessario capturar identidade. A abordagem por sessao (no boot) e a menos intrusiva: um único prompt no inicio, sem interrupcao durante a atividade.

**Fluxo:**
```
[Boot do Daemon]
    |
    v
[Show-StudentSelectForm]
  - Campo: "Aluno 1: ___" (obrigatorio)
  - Campo: "Aluno 2: ___" (opcional)
  - Campo: "Aluno 3: ___" (opcional)
  - Botao: "Iniciar"
    |
    v
$sessionStudents = @("Ana", "Bruno")  # lista de nomes/ids da sessao

# Cada payload inclui:
"students": ["Ana", "Bruno"]
# (array de strings; responsabilidade de analise e do pesquisador)
```

**ADR-006 Schema Impact:** Adicionar coluna `students jsonb` na tabela `responses` (array de nomes/ids).

---

## Task Breakdown

### Ordem de Execucao e Dependencias

```
TASK-010 (DDL) ──┐
TASK-002 (cfg)   ├──> TASK-003 (skeleton) ──> TASK-004 (init+log) ──┬──> TASK-005 (config)
                 ┘                                                    └──> TASK-006 (UI)
                                                                          |
                                                      TASK-005, TASK-006 ──> TASK-007 (send+cache)
                                                                          |
                                                              TASK-007 ──> TASK-008 (loop)
                                                                          |
                                                              TASK-008 ──> TASK-009 (deploy)
                                                                          |
                                                              TASK-009 ──> TASK-011 (readme)
```

---

### TASK-001 - Definir Schema Supabase

- **Agent:** `database-architect` | **Skill:** `database-design` | **Priority:** P0
- **Dependencies:** Nenhuma
- **INPUT:** Requisitos de coleta (sessao, maquina, atividade, resposta, timestamp)
- **OUTPUT:** Schema documentado com tipos e constraints
- **VERIFY:** Campos corretos, tipos validados, RLS policy definida

**Campos da tabela `responses` (atualizados com ADR-006):**
```sql
id             uuid DEFAULT gen_random_uuid() PRIMARY KEY
session_id     text NOT NULL        -- guid gerado no boot do daemon
computer_id    text NOT NULL        -- $env:COMPUTERNAME
activity_id    text NOT NULL        -- vem do config.json
students       jsonb NOT NULL       -- array de nomes/ids dos alunos da sessao
difficulty     integer NOT NULL CHECK (difficulty BETWEEN 1 AND 5)
interval_mark  integer NOT NULL     -- 5, 15 ou 30 (minuto do ciclo que disparou)
responded_at   timestamptz NOT NULL DEFAULT now()
client_version text                 -- versao do script para rastreio de deploy
```

---

### TASK-002 - Definir Estrutura do config.json GitOps

- **Agent:** `backend-specialist` | **Skill:** `api-patterns` | **Priority:** P0
- **Dependencies:** TASK-001
- **INPUT:** Todos os parametros configuráveis do sistema
- **OUTPUT:** Schema documentado de `config.json` e arquivo de exemplo em `config/config.json`
- **VERIFY:** JSON valido, todos os campos com valores default sensiveis

**Estrutura do config.json (atualizada):**
```json
{
  "version": "1.1.0",
  "activity_id": "atividade-01-spike",
  "question_text": "Quao dificil esta essa atividade?",
  "interval_marks_minutes": [5, 15, 30],
  "scale_min": 1,
  "scale_max": 5,
  "timeout_seconds": 90,
  "max_students_per_machine": 3,
  "supabase_url_env_var": "PULSELAB_URL",
  "supabase_key_env_var": "PULSELAB_KEY",
  "config_remote_url": "https://raw.githubusercontent.com/ORG/pulselab/main/config/config.json"
}
```

> `interval_marks_minutes` substitui `interval_min/max_minutes`. O daemon dispara o pop-up nos minutos 5, 15 e 30 de cada sessao (sequencialmente, sem aleatoriedade).

---

### TASK-003 - Criar Esqueleto do Agente PowerShell

- **Agent:** `backend-specialist` | **Skill:** `clean-code` | **Priority:** P1
- **Dependencies:** TASK-001, TASK-002
- **INPUT:** ADRs validados, schema Supabase, estrutura config.json
- **OUTPUT:** `agent/pulselab-agent.ps1` com funcoes stub documentadas, sem implementacao
- **VERIFY:** Script carrega sem erro no PS 5.1, todos os stubs identificados com assinatura correta

**Funcoes (stubs atualizados):**
```
Initialize-Session       # Gera session_id, le hostname, carrega env vars
Show-StudentSelectForm   # Form WinForms de identificacao dos alunos (1-3 campos)
Get-RemoteConfig         # Invoke-WebRequest para config.json no GitHub (com fallback)
Invoke-IntervalSleep     # Start-Sleep calculado a partir de interval_marks (5->15->30->30...)
Get-SpikeWindowHandle    # Localiza handle do processo LEGO Spike para restaurar foco
Show-PulseForm           # Cria WinForms popup, retorna inteiro selecionado ou $null
Restore-SpikeFocus       # SetForegroundWindow via P/Invoke para devolver foco ao Spike
Send-ResponseToSupabase  # POST via Invoke-RestMethod ao Supabase
Add-ToLocalQueue         # Fallback: serializa payload em .cache/queue.json
Invoke-FlushCache        # Tenta reenviar payloads em fila
Write-PulseLog           # Logger com timestamp, nivel, mensagem
Start-DaemonLoop         # Loop principal: config -> flush -> intervals -> UI -> send
```

---

### TASK-004 - Implementar Initialize-Session e Write-PulseLog

- **Agent:** `backend-specialist` | **Skill:** `clean-code` | **Priority:** P1
- **Dependencies:** TASK-003
- **INPUT:** Esqueleto do script
- **OUTPUT:** Funcoes de inicializacao e logging funcionais
- **VERIFY:** Log gravado com timestamp ISO 8601, session_id unico (GUID) por execucao

**Formato de log obrigatorio:**
```
[2026-04-15 10:30:00] [INFO] Session initialized. session_id=3f7a2b1c computer_id=PC-SALA02-14
[2026-04-15 10:30:01] [ERROR] Remote config unreachable. Using cached config.
[2026-04-15 11:15:43] [INFO] Response recorded. difficulty=3 activity=atividade-01-spike
```

---

### TASK-005 - Implementar Get-RemoteConfig com Fallback Local

- **Agent:** `backend-specialist` | **Skill:** `api-patterns` | **Priority:** P1
- **Dependencies:** TASK-004
- **INPUT:** URL raw do GitHub para config.json
- **OUTPUT:** Objeto de config carregado (remoto ou cache local)
- **VERIFY:** Funciona offline com ultimo config; falha silenciosa logada; novo config em producao sem redistribuicao do script

---

### TASK-006 - Implementar Show-PulseForm (WinForms UI)

- **Agent:** `backend-specialist` | **Skill:** `clean-code` | **Priority:** P1
- **Dependencies:** TASK-004
- **INPUT:** Texto da pergunta, escala min/max do config, timeout_seconds, handle do Spike
- **OUTPUT:** Form WinForms retornando inteiro (1-5) ao ser clicado, `$null` em timeout; foco devolvido ao Spike apos fechamento
- **VERIFY:**
  - Aparece no canto inferior direito sem borda (`FormBorderStyle = None`)
  - `TopMost = $true` sobrepoe outras janelas
  - LEGO Spike NAO e minimizado nem perde estado durante o overlay
  - Fechar via clique < 500ms
  - Apos fechamento, janela do Spike retorna ao primeiro plano
  - Auto-fecha apos `timeout_seconds` sem resposta, loga `TIMEOUT`

**Especificacao visual:**
```
Largura:  380px | Altura: 180px (adicional para label de alunos)
Posicao:  Bottom-Right (Screen.PrimaryScreen.WorkingArea)
Cor fundo: #1A1A2E
Subtitulo: "[Ana, Bruno]" (nomes da sessao), Segoe UI 9pt, cor #888888
Pergunta:  Label branco, Segoe UI 12pt Bold
Botoes:    5 botoes (1-5), cor #4A90E2, hover #5BA3F5
Borda:     None (FormBorderStyle.None)
TopMost:   True
```

**Requisito critico — P/Invoke para restaurar foco:**
```powershell
# Declarar antes do loop
Add-Type @"
  using System;
  using System.Runtime.InteropServices;
  public class Win32NativeMethods {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
  }
"@
```

---

### TASK-007 - Implementar Send-ResponseToSupabase e Fila Offline

- **Agent:** `backend-specialist` | **Skill:** `api-patterns` | **Priority:** P1
- **Dependencies:** TASK-005, TASK-006
- **INPUT:** Payload JSON com campos da tabela `responses`
- **OUTPUT:** POST bem-sucedido ou payload salvo em `.cache/queue.json`
- **VERIFY:**
  - Sucesso: registro aparece no Supabase Studio
  - Com rede desligada: `.cache/queue.json` criado com payload valido
  - Com rede religada no ciclo seguinte: cache enviado e esvaziado

**Payload JSON (atualizado com ADR-006):**
```json
{
  "session_id": "3f7a2b1c-...",
  "computer_id": "PC-SALA02-14",
  "activity_id": "atividade-01-spike",
  "students": ["Ana", "Bruno"],
  "difficulty": 3,
  "interval_mark": 15,
  "responded_at": "2026-04-15T10:30:00-03:00",
  "client_version": "1.1.0"
}
```

**Supabase REST Endpoint:**
```
POST https://{ref}.supabase.co/rest/v1/responses
Headers: apikey, Authorization: Bearer, Content-Type, Prefer: return=minimal
```

---

### TASK-008 - Implementar Start-DaemonLoop

- **Agent:** `backend-specialist` | **Skill:** `clean-code` | **Priority:** P1
- **Dependencies:** TASK-004 a TASK-007
- **INPUT:** Todas as funcoes implementadas
- **OUTPUT:** Loop infinito funcional com log de cada ciclo
- **VERIFY:** Script roda por 2 ciclos com intervalo reduzido (2 min para debug) sem crash; log consistente

---

### TASK-009 - Implementar setup-startup.ps1 (Distribuicao)

- **Agent:** `devops-engineer` | **Skill:** `deployment-procedures` | **Priority:** P2
- **Dependencies:** TASK-008
- **INPUT:** Path do script principal, credenciais Supabase
- **OUTPUT:** `installer/setup-startup.ps1` que:
  1. Define `PULSELAB_URL` e `PULSELAB_KEY` como variaveis de ambiente de usuario
  2. Cria atalho `.lnk` em `$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup`
  3. Atalho usa `-ExecutionPolicy Bypass -WindowStyle Hidden -File pulselab-agent.ps1`
- **VERIFY:** Apos reiniciar, processo ativo no Task Manager sem janela; `pulselab.log` criado

---

### TASK-010 - Criar supabase-schema.sql

- **Agent:** `database-architect` | **Skill:** `database-design` | **Priority:** P0
- **Dependencies:** TASK-001
- **INPUT:** Schema definido na TASK-001
- **OUTPUT:** `schema/supabase-schema.sql` pronto para executar no Supabase SQL Editor
- **VERIFY:** Executar no Supabase: tabela criada, RLS ativa, anon key pode INSERT mas nao SELECT

**RLS Policy:**
```sql
-- Anon key: somente INSERT (privacidade dos alunos, LGPD)
CREATE POLICY "anon_insert_only" ON responses
  FOR INSERT TO anon WITH CHECK (true);

-- SELECT restrito a service_role (dashboard/Metabase)
```

---

### TASK-011 - Criar README.md com Manual de Deploy

- **Agent:** `documentation-writer` | **Skill:** `documentation-templates` | **Priority:** P3
- **Dependencies:** TASK-009, TASK-010
- **INPUT:** Todos os componentes implementados
- **OUTPUT:** `README.md` com: pre-requisitos, setup Supabase, configuracao via GitHub, deploy via setup-startup.ps1, troubleshooting
- **VERIFY:** Terceiro consegue fazer deploy do zero seguindo o README sem assistencia adicional

---

## Fluxo do Daemon (Diagrama)

```
[Windows Startup]
     |
     v
pulselab-agent.ps1 iniciado com -WindowStyle Hidden
     |
     v
Initialize-Session
  - session_id = [guid]
  - computer_id = $env:COMPUTERNAME
  - Le env vars PULSELAB_URL e PULSELAB_KEY
  - Registra handle do processo LEGO Spike (Get-SpikeWindowHandle)
     |
     v
Show-StudentSelectForm
  - "Aluno 1:", "Aluno 2:", "Aluno 3:" (1 obrigatorio, 2 opcionais)
  - Retorna $sessionStudents = @("Ana", "Bruno")
     |
     v
Get-RemoteConfig (GitHub) | fallback: config local
Invoke-FlushCache (.cache/queue.json se existir)
     |
     v
[LOOP DE INTERVALOS: 5 min -> 15 min -> 30 min -> 30 min -> ...]
     |
     |---> Invoke-IntervalSleep ($intervalMark)   # dorme ate proximo mark
     |
     |---> Get-SpikeWindowHandle (atualiza handle se Spike foi reiniciado)
     |
     |---> Show-PulseForm
     |       - Subtitulo mostra nomes dos alunos da sessao
     |       - Exibe pergunta e botoes 1-5
     |       - Aguarda clique (ou timeout 90s)
     |       - Retorna $difficulty ou $null
     |
     |---> Restore-SpikeFocus ($spikeHandle)      # SetForegroundWindow
     |
     |---> if ($difficulty -ne $null)
     |         Send-ResponseToSupabase
     |           - Payload inclui students[], interval_mark
     |           - Sucesso: Write-PulseLog INFO "Response sent"
     |           - Falha:   Add-ToLocalQueue $payload
     |
     |---> Write-PulseLog INFO "Interval complete. mark=$intervalMark"
     |
     [proximo intervalo: 30 min fixo apos terceiro mark]
```

---

## Risk Register

| # | Risco | Prob | Impacto | Mitigacao |
|---|-------|------|---------|-----------|
| R01 | GPO da escola bloqueia execucao de scripts | Alta | Critico | Setup instrui admin a liberar via GPO; atalho ja usa `-ExecutionPolicy Bypass` |
| R02 | GitHub raw URL bloqueada pelo proxy escolar | Media | Alto | Fallback para config.json local cacheado; documentar como atualizar manualmente |
| R03 | Supabase bloqueado por firewall | Media | Alto | Cache offline absorve dados; sincronizado quando possivel |
| R04 | Pop-up captura foco e fecha/minimiza o LEGO Spike | Alta | Alto | ADR-005: `SetForegroundWindow` restaura Spike apos fechamento; testar em maquina real com Spike aberto |
| R05 | LEGO Spike nao esta aberto quando pop-up dispara | Media | Baixo | `Get-SpikeWindowHandle` retorna `[IntPtr]::Zero`; `Restore-SpikeFocus` e no-op silencioso |
| R06 | Aluno fecha `StudentSelectForm` sem preencher Aluno 1 | Media | Alto | Botao Iniciar desabilitado (`Enabled = $false`) ate `TextBox1.Text.Trim() -ne ''` |
| R07 | Log cresce indefinidamente | Baixa | Baixo | Rotacao: se > 5MB, renomear `pulselab.log.bak` e criar novo |

---

## GitOps Governance

### O que fica no GitHub

| Arquivo | Tipo | Racional |
|---------|------|----------|
| `config/config.json` | Config | Single source of truth para todos os daemons |
| `agent/pulselab-agent.ps1` | Codigo | Versionado, auditado |
| `installer/setup-startup.ps1` | Codigo | Deploy reproduzivel |
| `schema/supabase-schema.sql` | DDL | Data-as-Code: schema e codigo |
| `README.md` | Docs | Runbook para pesquisadores |

### O que NUNCA vai ao GitHub

| Item | Razao |
|------|-------|
| `PULSELAB_KEY` / `PULSELAB_URL` | Secrets |
| `.cache/queue.json` | Dados de alunos (LGPD) |
| `*.log` | Dados operacionais locais |

---

## Open Questions — RESOLVIDAS

> [!NOTE]
> Todas as questoes respondidas pelo usuario em 2026-04-15. Decisoes incorporadas ao plano.

| # | Questao | Decisao |
|---|---------|----------|
| Q1 | Identidade individual do aluno? | **SIM.** Multiplos alunos por maquina; `students jsonb[]` capturado via `Show-StudentSelectForm` no boot da sessao |
| Q2 | Segmentacao por turma/atividade? | **NAO.** Mesma rotina sempre; config global unico |
| Q3 | Rollout manual ou automatizado? | **MANUAL.** `setup-startup.ps1` executado por maquina |
| Q4 | Dashboard de visualizacao? | **NAO** por enquanto. RLS restricao anon-insert mantida; sem views adicionais no MVP |

---

## Phase X - Verification Checklist

> Nao marcar [x] sem verificacao real em maquina Windows com PS 5.1.

### Funcional
- [ ] Script inicia invisivel (Task Manager: processo sem janela)
- [ ] `pulselab.log` criado com entrada `INIT` no boot
- [ ] `Show-StudentSelectForm` aparece no boot, Aluno 1 obrigatorio
- [ ] Config carregado do GitHub com sucesso
- [ ] Pop-up dispara nos minutos 5, 15 e 30 da sessao (testar com 0.5, 1 e 2 min em modo debug)
- [ ] LEGO Spike NAO e minimizado ou fechado durante o overlay
- [ ] Apos clicar, foco retorna ao LEGO Spike imediatamente
- [ ] Clique em botao fecha form em < 500ms
- [ ] Registro aparece na tabela `responses` do Supabase com `students` e `interval_mark` corretos
- [ ] Com rede desligada: payload salvo em `.cache/queue.json`
- [ ] Com rede religada: cache enviado e esvaziado no ciclo seguinte

### Seguranca
- [ ] Nenhum secret em arquivo commitado no repositorio
- [ ] RLS ativa: anon key nao consegue SELECT na tabela `responses`
- [ ] Script executa como usuario padrao sem prompt UAC

### Qualidade de Codigo
- [ ] Nenhum emoticon em comentarios, logs ou strings
- [ ] Todos os logs com formato `[YYYY-MM-DD HH:mm:ss] [NIVEL] Mensagem`
- [ ] Sem `Write-Host` de debug em producao (usar flag `$DebugMode`)

### GitOps
- [ ] `config.json` (v1.1.0) commitado com `interval_marks_minutes: [5, 15, 30]`
- [ ] `supabase-schema.sql` commitado com coluna `students jsonb` e `interval_mark integer`
- [ ] `.gitignore` cobre `.cache/`, `*.log`, `.env`

### Distribuicao
- [ ] `setup-startup.ps1` executa em maquina limpa sem erros
- [ ] Apos reiniciar, daemon ativo automaticamente
- [ ] README permite deploy do zero por terceiro sem assistencia

---

*Plano gerado por `@project-planner` | Pulselab MVP | 2026-04-15*
