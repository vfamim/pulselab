# Pulselab

Fundação de observação distribuída e controle de qualidade para oficinas de robótica escolar. O agente coleta autorrelatos pseudonimizados, evidências técnicas minimizadas e uma linha do tempo auditável de cada sessão realizada com kits LEGO SPIKE.

---

## Novidades da Versão 1.4.0

- **Preparação persistente da instalação**: cada máquina recebe `installation_id` e reaproveita sede, regional, escola, oficina, turma, atividade e tamanho do grupo.
- **Linha do tempo append-only**: início, heartbeats, checkpoints, pedidos de ajuda, trocas de papel, problemas de qualidade e encerramento são registrados em `research_session_events`.
- **Resumo protegido de qualidade**: `research_session_quality` classifica sessões completas, em andamento, abortadas ou que precisam de revisão.
- **Checkpoints absolutos**: os minutos 20 e 40 são calculados a partir do início real da atividade; o tempo gasto no primeiro questionário não adia intencionalmente o segundo.
- **Rastreabilidade**: versão do protocolo e hash SHA-256 da configuração acompanham os eventos.
- **Papéis dinâmicos**: a troca de programação e montagem pode ser solicitada e fica registrada.
- **Telemetria minimizada**: o agente envia categorias de aplicativo, não títulos de janelas ou nomes brutos de processos.
- **Evidência offline atômica**: uma resposta que depende de screenshot aguarda a imagem ficar sincronizável, evitando evidência órfã.
- **Compatibilidade Supabase atual**: permissões de inserção na Data API são declaradas explicitamente no schema.

Os instrumentos individuais, assentimento, pré/pós-oficina e cache offline introduzidos na versão 1.3 continuam presentes.

> A versão 1.4 é a primeira fundação do sistema distribuído. A ingestão ainda utiliza a chave pública e políticas de inserção anônima; autenticação individual de dispositivos e o painel central real permanecem como próximos incrementos antes de uma coleta acadêmica definitiva.

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
├── web/
│   └── agent-simulator/        # Simulador navegável do agente para Linux e validação
├── installer/
│   ├── build-installer.py      # Script Python para compilar o instalador único (Linux/macOS)
│   ├── build-installer.ps1     # Script PowerShell para compilar o instalador único (Windows)
│   └── setup-startup.ps1       # Setup manual via PowerShell por máquina
├── schema/
│   └── supabase-schema.sql     # DDL completo da tabela e bucket no Supabase
└── docs/
    ├── PLAN-pulselab-mvp.md    # Especificações históricas do MVP
    ├── protocolo-pesquisa-v1.md # Protocolo acadêmico e decisões pendentes
    ├── parecer-roadmap-observacao-distribuida.md # Parecer e roadmap de longo prazo
    ├── arquitetura-evidencias-v1.4.md # Contrato técnico do primeiro incremento
    ├── contexto-projeto-robotica-educativa.md # Contexto institucional público usado no front
    ├── validacao-simulador-web.md # Protocolo de validação do fluxo navegável
    ├── relatorio-metodologia-pulselab.html # Relatório navegável
    └── tcc-research-framework.md # Guia histórico do TCC
```

---

## Pré-requisitos

- Para o agente real: Windows 10 ou superior com PowerShell 5.1, um projeto
  configurado no [Supabase](https://supabase.com) e permissão de usuário padrão.
- Para o simulador: Linux, macOS ou Windows, Node.js e um navegador atual. O
  simulador não precisa de Supabase e não coleta dados reais.

## Simulador web no Linux

O fluxo da versão 1.4 pode ser percorrido no navegador sem uma máquina Windows:

```bash
cd web/agent-simulator
npm install
npm run dev
```

Acesse `http://localhost:3000`. A interface permite simular o fluxo padrão,
atraso de checkpoint, ausência do SPIKE e queda de rede, além de inspecionar os
eventos e exportar a sessão em JSON.

Essa versão valida a experiência do instrumento e seus contratos. Captura de
tela, detecção da janela do SPIKE, cache em disco, sincronização com Supabase e
integração Win32 continuam sendo responsabilidades do agente Windows. O roteiro
de avaliação está em
[`docs/validacao-simulador-web.md`](docs/validacao-simulador-web.md).

---

## Setup: Supabase

1. Acesse o painel do seu projeto no Supabase Studio.
2. Abra o **SQL Editor**.
3. Execute todo o conteúdo de `schema/supabase-schema.sql`. Isso irá:
   - Criar, sem apagar a tabela legada, a tabela `research_events`.
   - Criar `research_session_events` para a linha do tempo e controle de qualidade.
   - Criar a view protegida `research_session_quality` para o futuro backend do painel.
   - Adicionar os campos de rastreabilidade 1.4 a bancos já existentes.
   - Configurar `screenshots` como bucket privado.
   - Remover a política de leitura pública criada pela versão 1.2.
   - Conceder explicitamente apenas `INSERT` ao agente anônimo; consultas devem ocorrer em backend autorizado.

> RLS é uma salvaguarda técnica, mas não substitui consentimento, assentimento, minimização, controle de acesso e política de retenção.

---

## Setup: GitHub (GitOps)

1. Edite o arquivo `config/config.json`:
   - Defina `"site_id"` para a sede/cidade inicial ou informe-o ao gerar o instalador.
   - Insira o identificador regional em `"regional_hub"` (ex: `"Polo-Nordeste-01"`).
   - Defina os códigos padrão de escola, oficina e turma. Valores que ainda começarem com `CONFIGURE_` aparecerão vazios na primeira abertura.
   - Ajuste `activity_id` e as perguntas somente após aprovação da versão do protocolo.
   - Configure `"config_remote_url"` com a URL raw do seu repositório pessoal:
     ```
     https://raw.githubusercontent.com/vfamim/pulselab/main/config/config.json
     ```
2. Realize o commit e envie para a branch `main` ou de release ativa.

Sede, regional, escola, oficina, turma, atividade e tamanho do grupo são persistidos em `%LOCALAPPDATA%\PulseLab\installation.json` após a primeira confirmação válida. Na próxima execução, a preparação reaparece preenchida para conferência e edição. A confirmação das autorizações nunca é reutilizada: precisa ser marcada em cada oficina. Atualizações remotas do protocolo não substituem a identidade local da instalação.

---

## Deploy e Configuração por Máquina (Única vez)

O fluxo recomendado é gerar um instalador standalone em uma máquina de preparação e copiar somente esse instalador para as máquinas das escolas. O arquivo `.env` fica exclusivamente na máquina de preparação e nunca deve ser copiado, versionado ou enviado ao GitHub.

> A chave usada pelo agente deve ser a chave pública `anon` do Supabase. Nunca use `service_role` em um instalador distribuído.

### 1. Preparar as credenciais na máquina de preparação

Na raiz do projeto, crie um arquivo chamado `.env`:

```env
PULSELAB_URL=https://SEU_PROJECT_REF.supabase.co
PULSELAB_KEY=SUA_ANON_KEY
```

O `.env` já está coberto pelo `.gitignore`. Confirme antes de gerar o instalador:

```bash
git status --short --ignored .env
```

O resultado deve indicar que `.env` está ignorado. Não publique esse arquivo.

### Opção A: Instalador Standalone Único (.bat) - Recomendado

Gere um arquivo `Install-Pulselab-*.bat` autônomo que já contém as credenciais do Supabase, o agente e a configuração embutidos. O instrutor/técnico só precisa executar esse arquivo nas máquinas com dois cliques.

#### 2. Gerar o Instalador
Você pode gerar o instalador a partir de qualquer ambiente:

- **No Linux/macOS (usando Python)**:
  ```bash
  # Gerar arquivo .bat solto ou arquivo .zip empacotado (--zip)
  python3 installer/build-installer.py \
      --site-id "JUAZEIRO-BA" \
      --regional-hub "POLO-VALE-SAO-FRANCISCO" \
      --school-code "ESCOLA-01" \
      --zip \
      --output "Install-Pulselab-Juazeiro-BA.zip"
  ```

- **No Windows (usando PowerShell)**:
  ```powershell
  # Gerar arquivo .bat solto ou pacote .zip empacotado (-ZipPackage)
  .\installer\build-installer.ps1 `
      -SiteId "JUAZEIRO-BA" `
      -RegionalHub "POLO-VALE-SAO-FRANCISCO" `
      -SchoolCode "ESCOLA-01" `
      -ZipPackage `
      -OutputPath ".\Install-Pulselab-Juazeiro-BA.zip"
  ```

Os dois scripts leem automaticamente `PULSELAB_URL` e `PULSELAB_KEY` do `.env`. A chave `PULSELAB_KEY` é a **chave pública (`anon`)** do Supabase. Graças ao RLS (Row Level Security) configurado no banco de dados, esta chave possui **permissão de acesso mínimo necessário (INSERT-only)**: ela permite que as máquinas registrem telemetria e enviem evidências, mas impede qualquer leitura, alteração ou exclusão dos dados coletados por outras máquinas.

Os parâmetros de identidade alteram somente a cópia da configuração embutida no instalador; o `config/config.json` do projeto não é modificado. Ao utilizar a opção `--zip` / `-ZipPackage`, um arquivo `.zip` contendo o instalador `.bat` e o arquivo `INSTRUCOES.txt` será gerado, pronto para ser enviado às escolas via Google Drive, e-mail ou WhatsApp.

#### 3. Executar na máquina do aluno
1. Envie ou copie o pacote ZIP (`Install-Pulselab-*.zip`) ou o `.bat` para os responsáveis ou para um pendrive.
2. Na máquina do aluno, extraia o ZIP e execute o arquivo `.bat` clicando **duas vezes** nele (sem necessidade de privilégios de Administrador).
3. O instalador copiará os arquivos necessários de forma transparente para `C:\Users\Public\Pulselab\`, configurará as chaves no ambiente do usuário e criará o atalho na Área de Trabalho.
4. Feche a janela do instalador após a mensagem de conclusão.

---

### Alternativa: Instalação Manual (PowerShell)

Caso prefira executar o setup manual passando as chaves via parâmetros na máquina do aluno:

Execute o comando a seguir no computador do aluno, abrindo o PowerShell com permissões de usuário padrão (sem Administrador):

```powershell
$u="https://SEU_PROJECT_REF.supabase.co"; $k="SUA_ANON_KEY"; iex (irm "https://raw.githubusercontent.com/vfamim/pulselab/main/installer/install.ps1")
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

1. O instrutor abre o atalho, revisa os dados operacionais pré-preenchidos e corrige o que mudou, sem nomes de estudantes.
2. O instrutor confirma que verificou as autorizações e o consentimento aplicáveis.
3. Cada criança recebe o convite de assentimento. Se qualquer uma recusar, o coletor encerra e a dupla continua normalmente na oficina.
4. As crianças respondem, separadamente, experiência prévia e autoeficácia.
5. A atividade recebe uma linha do tempo com heartbeats técnicos minimizados.
6. Aos **20 e 40 minutos absolutos**, cada participante responde sozinho sobre esforço mental e situação da dupla. A colaboração é perguntada aos 40 minutos por padrão.
7. Depois do minuto 20, o agente solicita e registra a troca dos papéis por padrão.
8. Se alguém selecionar “precisamos de ajuda agora”, o agente alerta o instrutor e registra o evento.
9. A captura opcional registra a região da tela correspondente à janela do SPIKE e é enviada ao bucket privado.
10. Problemas como atraso, ausência da janela do SPIKE ou falha de captura geram eventos de qualidade.
11. Depois do último checkpoint, o agente aguarda o instrutor selecionar **Concluir Oficina**.
12. O instrutor registra desempenho da missão, intervenções e dificuldade principal. Depois, cada participante responde compreensão, afetos e intenção de retorno.

---

## Comportamento de Conexão Offline

Caso ocorram oscilações na rede Wi-Fi escolar, respostas, eventos de sessão e imagens pendentes são armazenados em `%LOCALAPPDATA%\PulseLab\cache`. O agente tenta reenviá-los no checkpoint seguinte, na inicialização ou no encerramento. `event_id` torna o reenvio idempotente e evita duplicações.

O cache não deve ser copiado para outra máquina. Se uma máquina ficar offline durante toda a oficina, preserve o perfil local até que o agente consiga sincronizar os eventos.

## Atualização do agente

Para atualizar as máquinas:

1. Edite e valide o código/configuração na máquina de preparação.
2. Gere um novo instalador com a versão atualizada.
3. Execute o novo instalador em cada computador.
4. Teste uma oficina de homologação antes de distribuir para todas as escolas.

O agente carrega a configuração remota definida em `config_remote_url`, mas a configuração local deve continuar válida para funcionamento offline.

## Checklist antes da primeira oficina

- [ ] O schema `schema/supabase-schema.sql` foi executado no Supabase.
- [ ] O bucket `screenshots` está privado.
- [ ] A chave utilizada é `anon`, nunca `service_role`.
- [ ] O `.env` está apenas na máquina de preparação.
- [ ] O instalador standalone não foi adicionado ao Git.
- [ ] Uma máquina de teste recebeu o instalador com sucesso.
- [ ] O atalho **Iniciar Pulselab - Oficina de Robótica** aparece na Área de Trabalho.
- [ ] A configuração contém códigos válidos de região, atividade e perguntas.
- [ ] Sede, regional e escola aparecem corretamente no perfil da instalação.
- [ ] O fluxo de assentimento e o protocolo de ajuda foram explicados ao instrutor.
- [ ] Foi realizado um teste com internet e outro sem internet.
- [ ] O evento apareceu em `research_events` após a sincronização.
- [ ] A sessão produziu `session_started`, `heartbeat` e `session_completed` em `research_session_events`.
- [ ] A sessão recebeu o estado esperado em `research_session_quality`.

## Solução de problemas

### O instalador pede credenciais

O `.env` não foi encontrado ou está com nomes incorretos. Verifique se contém exatamente `PULSELAB_URL` e `PULSELAB_KEY`.

### O agente informa que faltam credenciais

Execute o instalador novamente no mesmo usuário que abrirá o atalho. As variáveis são gravadas no escopo do usuário do Windows; outro usuário da máquina não as herdará.

### A oficina não aparece no Supabase

Verifique `%LOCALAPPDATA%\PulseLab\pulselab.log`, a conectividade HTTPS e o conteúdo de `%LOCALAPPDATA%\PulseLab\cache\research-queue.json`.

### O screenshot não aparece

Screenshots dependem de o aplicativo SPIKE estar aberto e de o bucket privado permitir upload. As imagens privadas devem ser acessadas por backend autorizado, não por link público.

### O agente usa configuração antiga

Verifique `config_remote_url`, a versão registrada no log e se a máquina consegue acessar o conteúdo raw do GitHub. Em modo offline, o último arquivo local válido é usado.

---

## Testar o agente no Windows com checkpoints acelerados

Estas instruções percorrem o agente real em WPF. Use somente códigos e dados de
teste.

### 1. Baixar a versão correta

Em uma pasta de trabalho, abra o PowerShell:

```powershell
git clone https://github.com/vfamim/pulselab.git
cd pulselab
git switch main
```

Se o repositório já estiver no computador:

```powershell
git fetch origin
git switch main
git pull --ff-only
```

Confirme que o agente é a versão 1.4.0:

```powershell
Select-String .\agent\pulselab-agent.ps1 -Pattern 'Version    :'
```

### 2. Escolher o modo de teste

Para testar o fluxo completo com a configuração remota e o Supabase, execute:

```powershell
.\Testar-Pulselab-Rapido.bat
```

Nesse modo, os marcos continuam identificados como 20 e 40 minutos no banco,
mas as janelas aparecem aproximadamente aos 20 e 40 segundos.

Para abrir os checkpoints consecutivamente, sem editar `config.json` nem
desligar o Wi-Fi, execute:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\pulselab.ps1 -DebugMode
```

`-DebugMode` usa o arquivo local, mantém os identificadores 20 e 40 e elimina a
espera somente para essa execução. Nenhum valor precisa ser restaurado depois.
O agente ainda exige credenciais do Supabase no arquivo local ou nas variáveis
`PULSELAB_URL` e `PULSELAB_KEY`.

## Verificações automatizadas

Execute os testes de contrato com Python 3:

```bash
python3 -m unittest discover -s tests -v
```

Os testes conferem configuração, versões, eventos aceitos pelo schema, permissões do coletor, minimização da telemetria, integridade básica dos blocos XAML e conteúdo embutido no instalador.

Para verificar também o simulador web:

```bash
npm test --prefix web/agent-simulator
npm run check --prefix web/agent-simulator
npm run build --prefix web/agent-simulator
```
