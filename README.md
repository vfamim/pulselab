# Pulselab

Motor de observabilidade e coleta de engajamento para o projeto de educacao em robotica em escolas publicas. Coleta o nivel de dificuldade percebido pelos alunos em intervalos fixos (5, 15 e 30 minutos) durante sessoes com kits LEGO Spike.

---

## Arquitetura

```
pulselab/
├── agent/
│   └── pulselab-agent.ps1      # Daemon PowerShell (roda invisivel no background)
├── config/
│   └── config.json             # Configuracao GitOps (fonte de verdade no GitHub)
├── installer/
│   └── setup-startup.ps1       # Setup por maquina (uma unica execucao)
├── schema/
│   └── supabase-schema.sql     # DDL da tabela responses no Supabase
└── docs/
    └── PLAN-pulselab-mvp.md    # Plano tecnico completo
```

---

## Pre-requisitos

- Windows 10+ com PowerShell 5.1 (padrao do sistema)
- Projeto criado no [Supabase](https://supabase.com)
- Repositorio clonado ou copiado na maquina destino

---

## Setup: Supabase

1. Acesse o Supabase Studio do seu projeto
2. Abra o **SQL Editor**
3. Execute o conteudo de `schema/supabase-schema.sql`
4. Verifique que a tabela `responses` foi criada com RLS ativa

---

## Setup: GitHub (GitOps)

1. Edite `config/config.json`:
   - Altere `activity_id` para o identificador da atividade atual
   - Altere `config_remote_url` para a URL raw do seu repositorio:
     ```
     https://raw.githubusercontent.com/SEU_USUARIO/pulselab/main/config/config.json
     ```
2. Commit e push para a branch `main`

---

## Deploy por maquina (manual)

Execute o seguinte comando **uma vez por maquina**, como usuario padrao (sem Administrador):

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\installer\setup-startup.ps1" `
    -SupabaseUrl "https://SEU_PROJECT_REF.supabase.co" `
    -SupabaseKey "SUA_ANON_KEY"
```

O script:
1. Salva as credenciais como variaveis de ambiente do usuario (sem UAC)
2. Cria um atalho em `shell:startup` para iniciar o daemon automaticamente em cada login

---

## Iniciar manualmente (sem reiniciar)

```powershell
powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File ".\agent\pulselab-agent.ps1"
```

---

## Verificar funcionamento

O daemon grava logs em `agent\pulselab.log`:

```
[2026-04-15 10:30:00] [INFO] Session initialized. version=1.1.0 session_id=... computer_id=PC-SALA02-14
[2026-04-15 10:30:01] [INFO] Students registered for session. count=2 students=Ana,Bruno
[2026-04-15 10:35:00] [INFO] Popup response received. difficulty=3 elapsed_ms=2341
[2026-04-15 10:35:00] [INFO] Response sent to Supabase. difficulty=3 interval_mark=5
```

---

## Atualizar configuracao (GitOps)

Para alterar a atividade, os intervalos ou a pergunta:

1. Edite `config/config.json` no repositorio
2. Commit e push para `main`
3. A alteracao e aplicada automaticamente no proximo ciclo de cada daemon

---

## Comportamento offline

Quando o Supabase esta inacessivel, o payload e salvo em `.cache/queue.json`. No proximo ciclo, o daemon tenta reenviar todos os itens da fila antes de registrar uma nova resposta.

---

## Troubleshooting

| Problema | Causa provavel | Solucao |
|----------|----------------|---------|
| Daemon nao inicia no login | GPO bloqueia execucao de scripts | Solicitar ao TI liberar via GPO ou usar `-ExecutionPolicy Bypass` no atalho |
| Popup nao aparece | Erro de credenciais ou config ausente | Verificar `pulselab.log` para mensagens `[ERROR]` |
| Dados nao chegam ao Supabase | Firewall bloqueando `*.supabase.co` | Verificar `.cache/queue.json`; solicitar liberacao ao TI |
| LEGO Spike perde foco | Versao do Spike com nome de processo diferente | Verificar log para `LEGO Spike process not found`; abrir issue com nome do processo |

---

## Modo debug

Para testar com intervalos de segundos (em vez de minutos), edite `config/config.json`:

```json
"debug_mode": true
```

Com `debug_mode: true`, o daemon dorme N segundos em vez de N minutos entre os ciclos.

---

## Seguranca e privacidade

- Credenciais armazenadas como variaveis de usuario do Windows (nao em arquivos)
- Dados de alunos nunca sao commitados no repositorio (`.cache/` no `.gitignore`)
- RLS do Supabase: a `anon key` utilizada pelo daemon permite apenas `INSERT`
- Nenhum dado pessoal alem do nome informado no inicio da sessao e coletado

---

## Versao

`1.1.0` — Intervalos fixos 5/15/30min, identificacao de alunos por sessao, compatibilidade LEGO Spike.
