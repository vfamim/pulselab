# Pulselab

Motor de observabilidade distribuído e coleta de engajamento multimodal (MMLA) projetado para laboratórios de robótica escolar. Captura dados de auto-relato de crianças (em duplas assíncronas) trabalhando com kits LEGO SPIKE, correlacionando-os com telemetria passiva do sistema operacional (janela ativa, inatividade e tamanho de arquivos).

---

## Novidades da Versão 1.3.0

- **Eventos individuais e pseudônimos**: cada participante recebe um código temporário; nomes não são coletados no banco analítico.
- **Consentimento e assentimento**: o instrutor confirma as autorizações aplicáveis, cada criança aceita ou recusa a coleta e pode deixar uma pergunta sem resposta.
- **Medidas separadas**: esforço mental, situação da dupla e colaboração deixaram de ser tratados como uma única escala.
- **Pré e pós-oficina**: experiência prévia, autoeficácia, compreensão percebida, afetos, intenção de retorno e rubrica do instrutor.
- **Contexto multicêntrico**: escola, oficina, turma, faixa escolar, atividade e versão do protocolo acompanham cada evento.
- **Privacidade reforçada**: a captura é limitada à janela do SPIKE, armazenada em bucket privado e o cache fica no perfil local do usuário.
- **Timestamps confiáveis**: horário real da resposta e horário de recebimento são preservados separadamente para eventos offline.

---

## Arquitetura do Repositório

```
pulselab/
├── agent/
│   └── pulselab-agent.ps1      # Daemon PowerShell WPF (coletor em background e interfaces)
├── config/
│   └── config.json             # Configuração remota GitOps (fonte de verdade no GitHub)
├── dashboard/
│   └── index.html              # Painel Analytics (Resultados, Metodologia, TCC e Coletor)
├── installer/
│   ├── build-installer.py      # Script Python para compilar o instalador único (Linux/macOS)
│   ├── build-installer.ps1     # Script PowerShell para compilar o instalador único (Windows)
│   └── setup-startup.ps1       # Setup manual via PowerShell por máquina
├── schema/
│   └── supabase-schema.sql     # DDL completo da tabela e bucket no Supabase
└── docs/
    ├── PLAN-pulselab-mvp.md    # Especificações históricas do MVP
    ├── protocolo-pesquisa-v1.md # Protocolo acadêmico e decisões pendentes
    ├── relatorio-metodologia-pulselab.html # Relatório navegável
    └── tcc-research-framework.md # Guia histórico do TCC
```

---

## Pré-requisitos

- Windows 10 ou superior com PowerShell 5.1 (padrão de fábrica)
- Projeto configurado no [Supabase](https://supabase.com)
- Permissão de usuário padrão (sem privilégios administrativos / UAC)

---

## Setup: Supabase

1. Acesse o painel do seu projeto no Supabase Studio.
2. Abra o **SQL Editor**.
3. Execute todo o conteúdo de `schema/supabase-schema.sql`. Isso irá:
   - Criar, sem apagar a tabela legada, a tabela `research_events`.
   - Configurar `screenshots` como bucket privado.
   - Remover a política de leitura pública criada pela versão 1.2.
   - Permitir apenas inserções anônimas; consultas devem ocorrer em backend autorizado.

> RLS é uma salvaguarda técnica, mas não substitui consentimento, assentimento, minimização, controle de acesso e política de retenção.

---

## Setup: GitHub (GitOps)

1. Edite o arquivo `config/config.json`:
   - Insira o identificador regional em `"regional_hub"` (ex: `"Polo-Nordeste-01"`).
   - Defina os códigos padrão de escola, oficina e turma ou preencha-os na abertura de cada sessão.
   - Ajuste `activity_id` e as perguntas somente após aprovação da versão do protocolo.
   - Configure `"config_remote_url"` com a URL raw do seu repositório pessoal:
     ```
     https://raw.githubusercontent.com/vfamim/pulselab/main/config/config.json
     ```
2. Realize o commit e envie para a branch `main` ou de release ativa.

---

## Deploy e Configuração por Máquina (Única vez)

Para implantar a aplicação nas máquinas dos alunos, você tem duas opções. A **Opção A** permite gerar um instalador standalone contendo tudo embutido (incluindo credenciais), evitando a necessidade de digitar chaves na máquina dos alunos.

### Opção A: Instalador Standalone Único (.bat) - Recomendado

Gere um arquivo `Install-Pulselab.bat` autônomo que já contém as credenciais do Supabase, o agente e a configuração embutidos. O instrutor/técnico só precisa executar esse arquivo nas máquinas com dois cliques.

#### 1. Gerar o Instalador
Você pode gerar o instalador a partir de qualquer ambiente:

- **No Linux/macOS (usando Python)**:
  ```bash
  python3 installer/build-installer.py --url "https://SEU_PROJECT_REF.supabase.co" --key "SUA_ANON_KEY"
  ```

- **No Windows (usando PowerShell)**:
  ```powershell
  .\installer\build-installer.ps1 -SupabaseUrl "https://SEU_PROJECT_REF.supabase.co" -SupabaseKey "SUA_ANON_KEY"
  ```

Isso criará o arquivo `Install-Pulselab.bat` na raiz do projeto.

#### 2. Executar na máquina do aluno
1. Copie o arquivo `Install-Pulselab.bat` para um pendrive ou rede escolar.
2. Na máquina do aluno, execute o arquivo clicando **duas vezes** nele (sem necessidade de privilégios de Administrador).
3. O instalador copiará os arquivos necessários de forma transparente para `C:\Users\Public\Pulselab\`, configurará as chaves no ambiente do usuário e criará o atalho na Área de Trabalho.

---

### Opção B: Instalação Manual (PowerShell)

Caso prefira executar o setup manual passando as chaves via parâmetros na máquina do aluno:

Execute o comando a seguir no computador do aluno, abrindo o PowerShell com permissões de usuário padrão (sem Administrador):

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\installer\setup-startup.ps1" `
    -SupabaseUrl "https://SEU_PROJECT_REF.supabase.co" `
    -SupabaseKey "SUA_ANON_KEY"
```

---

### O que os instaladores fazem na máquina?
1. Copiam os arquivos necessários para execução (o standalone coloca em `C:\Users\Public\Pulselab`).
2. Salvam a URL e a chave anônima do Supabase nas variáveis de ambiente do usuário (`PULSELAB_URL` e `PULSELAB_KEY`).
3. Verificam se a máquina possui suporte nativo às dependências WPF/XAML.
4. Removem atalhos legados de inicialização automática.
5. Criam o atalho lúdico na Área de Trabalho com o nome **"Iniciar Pulselab - Oficina de Robótica"** para lançamento manual pelo instrutor.

---

## Como Usar na Oficina (Fluxo do Usuário)

1. O instrutor abre o atalho e informa códigos de escola, oficina e turma, sem nomes de estudantes.
2. O instrutor confirma que verificou as autorizações e o consentimento aplicáveis.
3. Cada criança recebe o convite de assentimento. Se qualquer uma recusar, o coletor encerra e a dupla continua normalmente na oficina.
4. As crianças respondem, separadamente, experiência prévia e autoeficácia.
5. Aos **20 e 40 minutos**, cada participante responde sozinho sobre esforço mental e situação da dupla. A colaboração é perguntada aos 40 minutos por padrão.
6. Se alguém selecionar “precisamos de ajuda agora”, o agente alerta o instrutor pelo ícone da bandeja.
7. A captura opcional contém apenas a janela do SPIKE e é enviada ao bucket privado.
8. Depois do último checkpoint, o agente aguarda o instrutor selecionar **Concluir Oficina**; não existe mais encerramento automático aos 40 minutos.
9. O instrutor registra desempenho da missão, intervenções e dificuldade principal. Depois, cada participante responde compreensão, afetos e intenção de retorno.

---

## Comportamento de Conexão Offline

Caso ocorram oscilações na rede Wi-Fi escolar, eventos e imagens pendentes são armazenados em `%LOCALAPPDATA%\PulseLab\cache`. O agente tenta reenviá-los no checkpoint seguinte, na inicialização ou no encerramento. `event_id` torna o reenvio idempotente e evita duplicações.

---

## Modo de Simulação Rápida (Desenvolvedor / Teste)

Para testar todo o fluxo sem esperar 20/40 minutos reais:

1. Abra `config/config.json` e altere as opções:
   - `"debug_mode"`: `true`
   - `"interval_marks_minutes"`: `[1, 2]`
2. Execute o agente manualmente. Em debug, cada unidade do array equivale a **um segundo**: `[1, 2]` abre os checkpoints aproximadamente no primeiro e no segundo segundo. Use somente com dados de teste.
