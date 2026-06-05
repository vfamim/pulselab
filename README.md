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

Como os computadores da faculdade podem ter restrições (bloqueio de pendrive, falta de Git), você tem **duas formas** extremamente simples de distribuir e instalar o Pulselab nas máquinas dos alunos:

### Método A: Instalação Remota via PowerShell (Recomendado)
Este método **não requer Git** e **não requer pendrive**. Ele usa comandos nativos do Windows para baixar o repositório como ZIP diretamente do GitHub, extrair na pasta pública (`C:\Users\Public\pulselab-main`) e deixar tudo configurado.

1. Abra o **PowerShell** no computador do aluno (como usuário comum, sem privilégios de administrador/UAC).
2. Defina as credenciais do seu Supabase e execute o comando abaixo (substituindo pelas suas chaves reais):

```powershell
$u="https://SEU_PROJECT_REF.supabase.co"; $k="SUA_ANON_KEY"; iex (irm "https://raw.githubusercontent.com/vfamim/pulselab/main/installer/install.ps1")
```

*Pronto!* O script fará o download, configurará o `config.json` portátil local e criará o atalho **"Iniciar Pulselab - Oficina de Robótica"** na Área de Trabalho do aluno.

---

### Método B: Pasta Compactada Pré-Configurada (Alternativa Offline/Nuvem)
Ideal para laboratórios onde o download direto via terminal pode ser bloqueado ou para quando você quer configurar tudo apenas uma vez no seu próprio computador:

1. No seu computador de desenvolvimento, configure o arquivo [config.json](file:///c:/Users/VFAMI/Dev/pulselab/config/config.json) com a URL e a Anon Key do seu Supabase:
   ```json
   "supabase_url": "https://SEU_PROJECT_REF.supabase.co",
   "supabase_key": "SUA_ANON_KEY",
   ```
2. Compacte toda a pasta `pulselab` em um arquivo `.zip` (ex: `pulselab.zip`).
3. Suba o arquivo ZIP para o seu **Google Drive, Dropbox ou OneDrive** e gere um link de compartilhamento.
4. No computador da faculdade:
   - Abra o navegador e baixe o ZIP pelo link gerado.
   - Extraia a pasta em qualquer diretório (ex: na Área de Trabalho ou Documentos).
   - Dê dois cliques em [Iniciar-Pulselab.bat](file:///c:/Users/VFAMI/Dev/pulselab/Iniciar-Pulselab.bat) uma vez para criar o atalho oficial na Área de Trabalho e iniciar o daemon.

---

### O que o processo de instalação faz?
1. Salva as credenciais do Supabase diretamente no `config/config.json` portátil e, opcionalmente, nas variáveis de ambiente do usuário (`PULSELAB_URL` e `PULSELAB_KEY`).
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

## Modos de Simulação Rápida e Testes (Desenvolvedor / Homologação)

Existem duas formas principais de testar todo o fluxo do daemon em poucos minutos sem esperar os 20 ou 40 minutos de aula reais:

### 1. Modo de Teste em Produção Rápido (`-ProductionTest`) - **Recomendado para verificar o Supabase**
Use este parâmetro quando quiser validar a comunicação de ponta a ponta com o banco de dados do Supabase usando a configuração oficial de produção, porém de forma acelerada:
* Ele sincroniza normalmente com o arquivo de configuração remota GitOps (ou cache local).
* Mantém os marcadores de intervalo reais em `[20, 40]` (evitando a violação da restrição do banco de dados `CHECK (interval_mark IN (20, 40, 99))`).
* **Trata os minutos da configuração como segundos no cronômetro**: os pop-ups de amostragem abrirão aos 20 segundos e aos 40 segundos de teste.

Execute pelo terminal:
```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\agent\pulselab-agent.ps1" -ProductionTest
```

### 2. Modo de Debug Local (`-DebugMode` ou `"debug_mode": true`)
Utilizado para simulações locais rápidas sem dependência de internet ou de sincronização da configuração remota do GitOps:
* Força temporariamente os marcadores de intervalo para `[1, 2]` minutos.
* Ignora a sincronização do arquivo remoto.
* **Atenção**: Como os marcadores enviados passam a ser `1` e `2`, as inserções no banco de dados de produção do Supabase falharão caso a tabela possua a restrição ativa. É ideal para desenvolvimento offline das interfaces WPF ou lógica do sistema operacional.

Execute pelo terminal:
```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\agent\pulselab-agent.ps1" -DebugMode
```
