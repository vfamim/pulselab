# Pulselab

Motor de observabilidade distribuído e coleta de engajamento multimodal (MMLA) projetado para laboratórios de robótica escolar. Captura dados de auto-relato de crianças (em duplas assíncronas) trabalhando com kits LEGO SPIKE, correlacionando-os com telemetria passiva do sistema operacional (janela ativa, inatividade e tamanho de arquivos).

---

## Novidades da Versão 1.2.0 🚀

- **Execução Sob Demanda (Não Invasiva)**: O script não roda mais na inicialização automática do Windows (sem chaves em `Startup` ou agendador de tarefas). O instrutor da oficina inicia o fluxo manualmente através de um atalho fácil na Área de Trabalho.
- **Interfaces Gráficas em WPF**: Telas lúdicas, dinâmicas e com design moderno em tons de violeta escuro e azul, contendo botões interativos e emojis adequados para o público infantil (Login, Pop-up duplo de Carga Cognitiva e Encerramento).
- **Telemetria de SO e Arquivos**: Rastreia a janela ativa, o nome do processo em primeiro plano, o tempo de inatividade (ociosidade do mouse/teclado) e o tamanho em KB do último arquivo `.llsp` ou `.spk` alterado na pasta de documentos.
- **Captura e Compressão de Tela**: Tira um print screen da área de trabalho no milissegundo anterior à abertura do pop-up e comprime a imagem em JPEG (qualidade 60%) para economizar largura de banda escolar antes de enviá-la ao Supabase Storage.
- **Resiliência Offline Total**: Se a conexão Wi-Fi da escola cair, os payloads JSON e os prints comprimidos são salvos localmente em `C:\Users\Public\Pulselab\cache\`. Eles são retransmitidos em lote automaticamente no próximo ciclo ativo ou ao concluir a oficina.

---

## Arquitetura do Repositório

```
pulselab/
├── agent/
│   └── pulselab-agent.ps1      # Daemon PowerShell WPF (coletor em background e interfaces)
├── config/
│   └── config.json             # Configuração remota GitOps (fonte de verdade no GitHub)
├── installer/
│   └── setup-startup.ps1       # Setup por máquina (execução única sob demanda)
├── schema/
│   └── supabase-schema.sql     # DDL completo da tabela e bucket no Supabase
└── docs/
    └── PLAN-pulselab-mvp.md    # Especificações do plano técnico anterior
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
   - Recriar a tabela `responses` com a estrutura atualizada.
   - Criar o bucket público `screenshots` no Supabase Storage.
   - Ativar as políticas de RLS (*Row Level Security*) necessárias para permitir que clientes anônimos insiram dados e printscreens, garantindo a privacidade dos alunos (LGPD).

---

## Setup: GitHub (GitOps)

1. Edite o arquivo `config/config.json`:
   - Insira o identificador regional em `"regional_hub"` (ex: `"Polo-Nordeste-01"`).
   - Configure `"config_remote_url"` com a URL raw do seu repositório pessoal:
     ```
     https://raw.githubusercontent.com/vfamim/pulselab/main/config/config.json
     ```
2. Realize o commit e envie para a branch `main` ou de release ativa.

---

## Deploy e Configuração por Máquina (Única vez)

Execute o comando a seguir **uma única vez** no computador do aluno, abrindo o PowerShell com permissões de usuário padrão (sem Administrador):

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\installer\setup-startup.ps1" `
    -SupabaseUrl "https://SEU_PROJECT_REF.supabase.co" `
    -SupabaseKey "SUA_ANON_KEY"
```

### O que o instalador faz?
1. Salva as credenciais do Supabase de forma segura nas variáveis de ambiente do usuário do Windows (`PULSELAB_URL` e `PULSELAB_KEY`).
2. Verifica se a máquina possui suporte nativo às dependências WPF/XAML.
3. Remove atalhos legados de inicialização automática.
4. Cria um atalho na Área de Trabalho com o nome **"Iniciar Pulselab - Oficina de Robótica"** para lançamento manual do instrutor.

---

## Como Usar na Oficina (Fluxo do Usuário)

1. O instrutor dá início à oficina e clica duas vezes no atalho **"Iniciar Pulselab - Oficina de Robótica"** na Área de Trabalho.
2. A **Janela 1 (Login)** aparece para que os alunos digitem seus nomes (Aluno do Computador e Aluno da Mesa). Ao clicar em "Iniciar Oficina", a tela se oculta e o cronômetro começa a correr em segundo plano.
3. Um **ícone na barra de tarefas (System Tray)** aparece silenciosamente no canto inferior direito para indicar o status da coleta.
4. Nos minutos **20 e 40**, o script tira um print comprimido em JPEG, e a **Janela 2 (Pop-up de Carga Cognitiva)** aparece sobreposta na tela do LEGO SPIKE. Os alunos avaliam o esforço do desafio (Likert de 1 a 4). Ao clicarem em "Salvar Expedição", a tela se fecha e devolve o foco ao LEGO SPIKE.
5. Ao término da oficina, o instrutor clica com o botão direito no ícone da barra de tarefas e seleciona **"Concluir Oficina"**. A **Janela 3 (Encerramento)** se abre para capturar o sentimento das crianças ( emojis de Orgulho, Concentração ou Frustração) e o desejo de voltar. Em seguida, os dados finais (marcador 99) são transmitidos e o daemon finaliza graciosamente.

---

## Comportamento de Conexão Offline

Caso ocorram oscilações na rede Wi-Fi escolar:
- A resposta e o print comprimido do momento são salvos localmente no caminho:
  `C:\Users\Public\Pulselab\cache\`
- O daemon mantém os arquivos protegidos localmente. Na amostragem seguinte ou ao forçar a conclusão da oficina, o daemon detecta o restabelecimento da rede, faz o upload em lote de todas as imagens, envia os payloads JSON correspondentes para a tabela e limpa a pasta de cache.

---

## Modo de Simulação Rápida (Desenvolvedor / Teste)

Para testar todo o fluxo do daemon em poucos minutos sem esperar 20/40 minutos reais:

1. Abra `config/config.json` e altere as opções:
   - `"debug_mode"`: `true`
   - `"interval_marks_minutes"`: `[1, 2]`
2. Execute o agente manualmente. Com esta flag ativa, **1 minuto configurado no array passará a durar exatamente 1 minuto no cronômetro real** (em vez dos tempos longos de aula). O pop-up aparecerá consecutivamente aos 60 e aos 120 segundos de teste.
