# Pulselab

Fundação de observação distribuída e controle de qualidade para oficinas de robótica escolar. O agente coleta autorrelatos pseudonimizados, evidências técnicas minimizadas e uma linha do tempo auditável de cada sessão realizada com kits LEGO SPIKE.

---

## Novidades da Versão 1.7.0

- **Arquitetura Web-First Desacoplada (PWA 100% Offline)**: A jornada dos alunos roda diretamente no navegador padrão, eliminando sobrecarga e travamentos de interface, com armazenamento local em IndexedDB e service worker completo.
- **Instalador Portátil Zero-Internet (ZIP de ~92 KB)**: Pacote autônomo transportável por pendrive, sem download de fontes remotas ou dependências externas, instalável com 2 cliques e sem permissões de administrador.
- **Bridge HTTP Local Mínimo & Alertas Nativos**: Servidor leve em loopback (`127.0.0.1:43127`) com relógio de sessão independente e alertas sonoros/visuais para avisar os alunos aos 20 e 40 minutos.
- **Parser Estrutural de Projetos LEGO SPIKE (.llsp3)**: Análise automática de blocos Scratch/Python para inferência de avanço técnico e redução drástica das perguntas dos questionários.

---

## Novidades da Versão 1.6.0

- **Zero Configuração para Escolas e Usuários Não-Técnicos**: Removida a necessidade de preencher manualmente URL do Supabase, anon key e tokens de enrollment durante a instalação. O instalador e o agente já vêm pré-configurados com os parâmetros da nuvem.
- **Execução Direta ou Instalação com 2 Cliques**: O pacote permite rodar diretamente via `Iniciar-Oficina-Oficial.bat` sem instalação ou instalar no sistema via `Instalar-PulseLab.bat` sem intervenção no terminal.
- **Auto-Update Seguro Mantido**: Atualização automática transparente do código do agente via GitHub com validação criptográfica SHA-256 e fallback offline de 3 segundos.

---

## Novidades da Versão 1.5.1

- **Launcher com Auto-Update Seguro**: O script `pulselab.ps1` agora atua como ponto de entrada padrão. Ao abrir o aplicativo, ele verifica atualizações do agente no GitHub e as aplica de forma atômica.
- **Validação Criptográfica SHA-256 e Sem Execução em Memória**: Total conformidade com Windows Defender e políticas de antivírus de laboratórios escolares (sem injeção em memória / `IEX`).
- **Fallback Offline Transparente**: Timeout de 3 segundos para garantir inicialização imediata e estável mesmo sem conexão à internet.
- **Preservação de Sessão DPAPI**: Atualizações no código do agente não interferem nas credenciais cifradas (`device_session.dat`) ou nos dados da instalação.

---

## Novidades da Versão 1.5.0

- **Autenticação individual por dispositivo**: cada máquina usa JWT próprio, vinculado por RLS a `auth.uid()`, `installation_id` e `site_id`.
- **Enrollment de uso único**: o coordenador emite um token aleatório com expiração; a Edge Function o consome antes de criar a conta do dispositivo.
- **Segredos protegidos no Windows**: access/refresh tokens ficam cifrados por DPAPI em `%LOCALAPPDATA%\PulseLab\device_session.dat`.
- **Motor corrigido**: grupos solo, dupla e trio, troca de papéis, rubrica obrigatória e retomada com tempo absoluto estão no fluxo executável.
- **Fila offline robusta**: escrita atômica, mutex, quarentena e recuperação sem inflar cobertura acadêmica.
- **Portal real**: autenticação Supabase, whitelist ativa e persistência de avaliações vinculadas à sessão.
- **Instalador seguro**: pacote ZIP genérico, sem credenciais, sem pipe remoto e com manifestos SHA-256.
- **CI ampliada**: Windows PowerShell 5.1, contratos Python/Node, build web e pgTAP/RLS com Supabase local.

---

## Arquitetura do Repositório (v1.7.0)

```
pulselab/
├── bridge/
│   ├── pulselab-bridge.ps1     # Bridge HTTP local (porta 43127), relógio e alertas nativos
│   └── spike-parser.ps1        # Parser offline de arquivos .llsp3 do LEGO SPIKE App 3
├── alunos/                     # Build de produção estático da PWA dos alunos (HTML/CSS/JS)
├── web/
│   └── agent-simulator/        # Código-fonte da PWA (React, Vite, IndexedDB e testes)
├── config/
│   ├── defaults.json           # Configurações padrão offline
│   └── config.json             # Configuração do protocolo (v1.7.0)
├── instalador/                 # Página do instalador web e downloads dos pacotes ZIP
│   └── downloads/              # Pacotes PulseLab-1.7.0-Windows.zip e PulseLab-Alunos-Offline-v1.7.0.zip
├── testes/                     # Aba oculta para homologação rápida e download
├── tutorial/                   # Guia operacional ilustrado interativo em slides (Marp)
├── dashboard/                  # Painel de acompanhamento e visualização
├── scripts/
│   └── build-offline-package.sh # Compilador do pacote 100% offline (~88 KB)
└── installer/
    ├── build-installer.py      # Builder do pacote Windows
    └── install.ps1             # Instalador local zero-touch
```

---

## O Que o PulseLab Coleta e Como Funciona

### 1. Respostas Rápidas da Dupla (Jornada em 5 Passos)
A aplicação elimina o "passa-passa" de teclado. A dupla que compartilha o computador responde conjuntamente em menos de 1 minuto em toda a oficina:
- **Início (15 segundos):** Experiência prévia com robótica e confiança para o desafio.
- **Checkpoints aos 20 e 40 minutos (20 segundos):** Esforço mental exigido, situação do progresso (travamos/começando/avançando/testando), colaboração e botão de pedir socorro ao professor.
- **Finalização (30 segundos):** Compreensão do que foi construído/programado, sensação da equipe e interesse em novas oficinas.

### 2. Telemetria Automática do LEGO SPIKE 3 (.llsp3)
O Bridge inspeciona o projeto salvo no SPIKE (`Documents\LEGO Education\SPIKE 3`) de forma contínua e nos marcos de 20 e 40 minutos:
- **Contagem de blocos funcionais:** Volume real de blocos Scratch/Python programados.
- **Detecção de componentes:** Uso de blocos de motores, sensores de cor/distância/força, laços de repetição (`repeat/forever`) e condições lógicas (`if/else`).
- **Inferência automática de estágios:** Classifica o avanço técnico da equipe (*Vazio $\rightarrow$ Montagem Inicial $\rightarrow$ Movimento Básico $\rightarrow$ Reativo a Sensores $\rightarrow$ Laço Autônomo $\rightarrow$ Missão Integrada*).
- **Delta de evolução:** Quantidade de blocos adicionados ou removidos entre o minuto 20 e o minuto 40.

> 🔒 **Privacidade por Design (LGPD):** O PulseLab **NÃO** coleta nomes de alunos, fotos de webcam, prints de tela, textos digitados em variáveis nem identificadores Bluetooth do Hub.

---

## Como Instalar e Executar

### 1. Pacote 100% Offline (Recomendado para Escolas)
1. Baixe `PulseLab-1.7.0-Windows.zip` (~92 KB) em [`instalador/downloads/`](instalador/downloads/).
2. Extraia o ZIP em qualquer pasta (ex: Área de Trabalho ou Pendrive).
3. Dê 2 cliques em `Instalar-PulseLab.bat` (cria o atalho) ou em `Iniciar-PulseLab.bat` (roda direto).
4. O navegador padrão abre automaticamente em `http://127.0.0.1:43127/alunos/` com funcionamento autônomo e sem conexão à internet.

### 2. Desenvolvimento e Testes no Linux / Navegador
```bash
cd web/agent-simulator
npm install
npm run dev
# Ou execute a suíte de testes unitários e ponta-a-ponta:
npm run check
```

### 3. Gerar o pacote de release reproduzível

```bash
# Compila PWA, gera ZIPs para instalador/downloads e atualiza checksums:
./scripts/build-offline-package.sh
```

Ou diretamente via Python / PowerShell:

```bash
python3 installer/build-installer.py \
  --output instalador/downloads/PulseLab-1.7.0-Windows.zip
```

```powershell
.\installer\build-installer.ps1 `
  -OutputPath .\instalador\downloads\PulseLab-1.7.0-Windows.zip
```

Os builders geram o ZIP pré-configurado com a PWA compilada, Bridge local, `SHA256SUMS.txt` interno e manifesto `.zip.sha256`.

---

## Como Usar na Oficina (Jornada em 5 Telas da Dupla)

1. **Preparação:** O instrutor abre o atalho, confere o código da turma/estação e clica em *Iniciar Oficina*.
2. **Check-in Inicial (15s):** A dupla responde duas perguntas rápidas sobre experiência prévia e confiança para o desafio do dia.
3. **Oficina em Andamento:** O cronômetro de tempo absoluto inicia e a dupla foca 100% no SPIKE. O Bridge analisa os arquivos `.llsp3` do robô em segundo plano.
4. **Checkpoints aos 20 e 40 minutos (20s):** Alertas sonoros e visuais avisam os alunos para avaliarem esforço mental, progresso e colaboração (com botão de socorro ao professor).
5. **Check-out Final & Conclusão (30s):** Autoavaliação da compreensão, sensação da equipe e gravação segura na outbox local em IndexedDB.

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


Confirme que o agente é a versão 1.7.0:

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
O agente exige uma sessão de dispositivo válida protegida por DPAPI, além da URL e da chave pública `anon`.

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
