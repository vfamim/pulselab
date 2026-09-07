# Handoff técnico — PWA dos alunos, Bridge PowerShell e integração com SPIKE

> Data do handoff: 7 de setembro de 2026  
> Branch de trabalho: `feat/student-pwa-linux-first`  
> Estado: protótipo da PWA implementado e validado; Bridge e adaptador SPIKE ainda não implementados.

## 1. Objetivo atual

Construir a experiência de coleta do PulseLab com foco exclusivo nos alunos das
oficinas de robótica. O produto precisa funcionar em escolas sem internet ou com
conexões muito lentas, interromper pouco a atividade e alertar de forma confiável
nos checkpoints de 20 e 40 minutos.

A arquitetura definida durante esta sessão é híbrida:

```text
Bridge PowerShell mínimo, executado no Windows
├── serve a webapp empacotada pelo endereço local
├── mantém o relógio da sessão
├── alerta nos checkpoints mesmo com o navegador oculto
└── abre a webapp na etapa correta
                    ↕
PWA dos alunos, React/Vite
├── preparação da aula
├── assentimento individual
├── pré, checkpoints e pós
├── passagem privada entre participantes
├── outbox em IndexedDB
└── sincronização futura quando houver internet
                    ↓
Fireclaw/API de ingestão/Supabase, quando disponíveis
```

O PowerShell não deve conter questionários nem ser a implementação da interface.
Ele funciona como companion/bridge local. A PWA é a única referência para a
jornada dos alunos.

## 2. Estado da branch

Todas as alterações estão na branch:

```text
feat/student-pwa-linux-first
```

As alterações ainda não foram commitadas. Não executar `git reset`, `git clean`
ou trocar de branch descartando o worktree antes de revisar e preservar os
arquivos.

No momento do handoff, o `git status --short` continha:

```text
 M .gitignore
 M README.md
 M firebase.json
 M web/agent-simulator/README.md
 M web/agent-simulator/app/globals.css
 M web/agent-simulator/index.html
 M web/agent-simulator/package-lock.json
 M web/agent-simulator/package.json
 M web/agent-simulator/src/main.jsx
 M web/agent-simulator/vite.config.js
?? alunos/
?? docs/HANDOFF-pwa-alunos-spike-bridge.md
?? docs/arquitetura-aplicacao-alunos.md
?? web/agent-simulator/app/student-page.jsx
?? web/agent-simulator/e2e/
?? web/agent-simulator/lib/student-store.js
?? web/agent-simulator/playwright.config.js
?? web/agent-simulator/public/
```

O agente PowerShell legado não foi alterado nesta branch.

## 3. O que já foi implementado

### 3.1 Jornada exclusiva dos alunos

O ponto de entrada React agora utiliza:

- `web/agent-simulator/app/student-page.jsx`;
- `web/agent-simulator/lib/student-store.js`;
- `web/agent-simulator/app/globals.css`.

Fluxo implementado:

```text
Preparação por adulto
        ↓
Assentimento A → passagem → B → passagem → C, quando houver
        ↓
Pré A → passagem → B → passagem → C
        ↓
Atividade com cronômetro absoluto
        ↓ 20 min
Checkpoint individual → troca de papéis → atividade
        ↓ 40 min
Checkpoint individual → encerramento
        ↓
Pós A → passagem → B → passagem → C
        ↓
Sessão concluída e mantida na outbox local
```

Grupos de uma, duas ou três pessoas percorrem a mesma máquina de estados. Em
atividade individual, as passagens de dispositivo e a troca de papéis são
omitidas.

### 3.2 Privacidade e experiência

O protótipo dos alunos:

- não solicita nome, e-mail ou matrícula;
- não captura a tela;
- não detecta nem registra outros aplicativos;
- não possui rubrica ou trilha do instrutor;
- mostra uma tela neutra antes de entregar o dispositivo a outra pessoa;
- não cria evento quando algum participante recusa o assentimento;
- informa o estado verdadeiro: salvo localmente e aguardando sincronização;
- possui modo normal limpo e modo técnico por `?lab=1`.

O modo de laboratório permite abrir imediatamente os checkpoints de 20 e 40
minutos e inspecionar a outbox, sem alterar o fluxo de produção.

### 3.3 Offline e retomada

- O snapshot da tela atual permite retomar após fechar ou recarregar a página.
- Eventos append-only são armazenados em IndexedDB.
- O relógio usa timestamps absolutos; fechar a página não pausa a atividade.
- Um service worker mantém o shell e os assets versionados para abertura offline.
- O build é publicado no caminho `/alunos/`.
- `firebase.json` possui rewrite de `/alunos/**` para `/alunos/index.html`.

O envio real ainda não foi implementado. Todos os eventos ficam em estado
`queued`. O botão de envio simulado existe somente em `?lab=1` e está rotulado
como simulação.

### 3.4 Build e dependências

O build atual está no diretório `alunos/` e ocupa aproximadamente 276 KB:

```text
alunos/
├── assets/index-CEtnE08Y.css
├── assets/index-D9lUpdQM.js
├── icon.svg
├── index.html
├── manifest.webmanifest
└── sw.js
```

A árvore herdada do simulador foi reduzida. A aplicação utiliza React, ReactDOM,
Vite e Playwright. A última auditoria retornou zero vulnerabilidades conhecidas.

### 3.5 Testes executados

Comando principal:

```bash
cd /home/vfamim/Dev/pulselab/web/agent-simulator
npm run check
```

Último resultado registrado:

- 3 testes unitários aprovados;
- 4 testes end-to-end aprovados no Google Chrome do Linux;
- build Vite aprovado;
- `npm audit --audit-level=high`: zero vulnerabilidades;
- `git diff --check`: sem erros.

Os testes end-to-end cobrem:

1. jornada completa de dois alunos e dois checkpoints;
2. recusa sem criação de eventos;
3. retomada depois de reload;
4. abertura da aplicação sem internet pelo service worker.

## 4. Como executar na próxima sessão

Instalar dependências de desenvolvimento:

```bash
cd /home/vfamim/Dev/pulselab/web/agent-simulator
npm install
```

Executar localmente:

```bash
npm run dev -- --host 127.0.0.1
```

Usar o caminho apresentado pelo Vite com `/alunos/`. Para testes acelerados:

```text
/alunos/?lab=1
```

Gerar o artefato de produção:

```bash
npm run build
```

## 5. Arquitetura de distribuição offline definida

A entrega para as escolas deve ser um único ZIP portátil baixado pelo site
Fireclaw, transportável por pendrive e utilizável sem Node, npm ou banco local.

Estrutura pretendida:

```text
PulseLab-Alunos-<versão>.zip
├── Instalar-PulseLab.bat
├── Iniciar-PulseLab.bat
├── bridge/
│   └── pulselab-bridge.ps1
├── app/
│   └── alunos/               # saída exata do Vite
├── config/
│   └── defaults.json
├── Desinstalar-PulseLab.bat
├── VERSION
└── SHA256SUMS
```

Instalação planejada:

1. baixar e extrair o ZIP;
2. executar `Instalar-PulseLab.bat`;
3. copiar arquivos para `%LOCALAPPDATA%\PulseLab`;
4. criar um atalho para iniciar a oficina;
5. executar o Bridge e abrir `http://127.0.0.1:43127/alunos/`.

A porta deve ser fixa. IndexedDB e service workers são vinculados à origem,
incluindo a porta; usar uma porta aleatória faria uma instalação perder acesso
às sessões salvas por outra origem.

Dados e agenda do Bridge devem ficar fora da pasta substituída por atualizações:

```text
%LOCALAPPDATA%\PulseLab\
├── app\       # atualizável
├── bridge\    # atualizável
└── data\      # preservado
```

### Pendência antes de declarar o ZIP totalmente offline

`web/agent-simulator/index.html` ainda referencia Google Fonts. O layout possui
fontes de sistema como fallback e o teste offline passa, mas essas referências
devem ser removidas ou as fontes devem ser empacotadas antes da distribuição.

## 6. Responsabilidades planejadas do Bridge

O Bridge PowerShell deverá:

1. iniciar um servidor HTTP vinculado somente a `127.0.0.1:43127`;
2. servir exclusivamente os arquivos estáticos compilados;
3. aceitar agenda de sessão com `session_id`, `started_at` e marcas `[20, 40]`;
4. persistir a agenda em `%LOCALAPPDATA%\PulseLab\data`;
5. detectar checkpoints vencidos depois de suspensão ou reinício;
6. tocar um som e mostrar um alerta nativo compacto;
7. abrir a webapp diretamente no checkpoint ao confirmar o alerta;
8. repetir o alerta, com limite, enquanto não houver confirmação;
9. aceitar o ACK da webapp depois da resposta;
10. expor um endpoint `/health` para diagnóstico.

O Bridge não deverá receber respostas, código do projeto, nomes, imagens ou
telemetria geral de mouse/teclado.

Protocolo mínimo proposto:

```text
GET  /health
POST /v1/sessions
GET  /v1/sessions/{id}/schedule
POST /v1/sessions/{id}/checkpoints/{mark}/ack
```

Segurança mínima:

- bind somente em loopback;
- origem e `Content-Type` estritamente validados;
- token temporário por execução para comandos mutáveis;
- proteção contra path traversal no servidor estático;
- limites de payload e frequência;
- nenhuma chave administrativa dentro da PWA ou do ZIP.

## 7. Alertas: o que existe e o que falta

O agente legado já possui peças reaproveitáveis:

- `Get-SpikeWindowHandle`, linha aproximada 925;
- `Get-ActiveTelemetry`, linha aproximada 941;
- `NotifyIcon`, linha aproximada 2765;
- `ShowBalloonTip`, linha aproximada 2803.

O alerta robusto planejado combina:

1. som curto;
2. notificação na área do Windows;
3. destaque do ícone na barra de tarefas;
4. janela pequena “Hora do check-in”, sem tela cheia;
5. botão “Responder agora” que abre a webapp;
6. repetição controlada se for ignorado.

Não depender somente de notificações do navegador. Elas exigem permissão, podem
ser suprimidas e não fornecem um agendamento offline confiável com o navegador
completamente encerrado.

## 8. Investigação realizada sobre metadados do SPIKE

### 8.1 Estado atual do agente

O código atual não interpreta o projeto. `Get-LastSpikeFileSize` procura o
arquivo mais recente em `Documents\LEGO SPIKE` e devolve apenas seu tamanho.

Problema encontrado: a função procura `*.llsp` e `*.spk`, mas não `*.llsp3`, que
é o formato atual do SPIKE App 3.

### 8.2 Estrutura do `.llsp3` verificada empiricamente

Foi baixado e inspecionado um projeto público `.llsp3`. O arquivo é um contêiner
ZIP com:

```text
manifest.json
scratch.sb3
icon.svg
monitors.json
```

O `scratch.sb3` também é um ZIP e contém `project.json`. Esse JSON possui os
targets do Scratch, blocos, opcodes, inputs, fields, comentários, variáveis e
extensões.

No arquivo analisado foi possível obter, sem renderizar imagens:

- tipo `word-blocks`;
- data de criação e último salvamento;
- extensões utilizadas;
- quantidade total de blocos;
- quantidade de stacks de nível superior;
- blocos de sombra e executáveis;
- categorias como eventos, controle, motores, sensores e luzes;
- presença de loops, condicionais e procedimentos.

O manifesto também continha nome e identificadores do Hub. Esses campos não
devem sair do parser nem ser persistidos.

### 8.3 Métricas seguras propostas

```json
{
  "source": "spike_project",
  "project_saved": true,
  "format": "llsp3",
  "language": "word-blocks",
  "executable_blocks": 31,
  "top_level_stacks": 4,
  "uses_motor": true,
  "uses_sensor": true,
  "uses_loop": true,
  "uses_condition": false,
  "blocks_added_since_previous": 8,
  "blocks_removed_since_previous": 2,
  "inferred_stage": "integration",
  "inference_confidence": 0.82
}
```

Não persistir:

- código bruto;
- textos, comentários e strings;
- nome ou caminho completo do projeto;
- preview SVG;
- dados de áudio;
- nome, UUID ou identificador Bluetooth do Hub;
- valores que não sejam necessários à atividade definida.

### 8.4 Como inferir a etapa

Não usar somente contagem de blocos. Cada atividade deve possuir um adaptador
versionado com marcos técnicos esperados, por exemplo:

```text
Atividade 01
├── evento inicial
├── configuração de motores
├── movimento básico
├── leitura de sensor
├── condição ou repetição
└── integração e testes
```

Snapshots no início, 20 minutos, 40 minutos e final permitem observar a evolução
estrutural. A saída deve ser tratada como inferência, sempre com fonte e nível de
confiança.

### 8.5 Limites confirmados

- O arquivo representa o último estado salvo, não necessariamente o canvas vivo.
- Ausência de mudança pode significar montagem física, discussão ou arquivo não
  salvo; não significa automaticamente inatividade.
- O protocolo público oficial do Hub documenta upload, controle de execução e
  notificações dos dispositivos, mas não uma leitura do projeto aberto no
  editor.
- Conectar o Bridge diretamente ao Hub pode disputar USB/Bluetooth com o SPIKE e
  não é recomendado.
- A montagem física do robô não pode ser conhecida sem câmera ou instrumentação
  adicional.

## 9. Investigação pendente: canvas vivo pela UI Automation

A aplicação SPIKE nativa declara suporte a acessibilidade e leitores de tela.
Isso torna plausível consultar sua árvore de acessibilidade do Windows por
UI Automation, sem screenshot.

Sinais desejados:

- SPIKE aberto e em primeiro plano;
- solução Prime ou Essential;
- projeto, lição ou tela inicial;
- canvas de programação, instruções de montagem ou painel do Hub;
- modo Word Blocks, Icon Blocks ou Python;
- executar/parar, quando exposto;
- categoria do bloco focado;
- categorias dos blocos visíveis;
- confirmação de que o aluno está no quadro esperado da atividade.

Isso ainda não foi verificado em uma instalação real do SPIKE no Windows. O
resultado depende do que o aplicativo expõe na árvore UIA e pode variar entre
versões.

### Spike Probe proposto

Criar `tools/spike-probe.ps1`, somente leitura, que:

1. localiza o HWND do SPIKE;
2. enumera as árvores UIA Control, Content e Raw;
3. coleta `ControlType`, `AutomationId`, nome acessível normalizado, foco e
   bounding rectangle;
4. nunca invoca, clica ou altera controles;
5. substitui textos livres e identificadores por categorias ou hashes locais;
6. exporta um JSON sanitizado para análise;
7. permite comparar SPIKE 3.x, Prime/Essential e blocos/Python.

Uma execução curta em um computador Windows com o SPIKE instalado é inevitável
para confirmar essa superfície. O desenvolvimento pode continuar no Linux; o
probe pode ser executado uma única vez por alguém na máquina escolar e o JSON
sanitizado retornado ao repositório como fixture. Depois disso, testes de parser
e classificação podem rodar normalmente no Linux.

## 10. Redução proposta dos questionários

Metadados técnicos não substituem experiências subjetivas. Eles podem substituir
ou confirmar apenas a pergunta de progresso técnico.

Proposta inicial para piloto:

```text
Checkpoint de 20 minutos
├── esforço mental
└── necessidade de ajuda

Checkpoint de 40 minutos
├── esforço mental
└── colaboração

Coleta automática
├── etapa técnica inferida do projeto
├── papel planejado pela troca da webapp
└── presença no canvas/quadro, se UIA for validada
```

Continuam necessariamente autorrelatados:

- esforço mental;
- frustração/afeto;
- colaboração;
- compreensão percebida;
- intenção de participar novamente;
- contribuição individual, quando isso fizer parte da pergunta de pesquisa.

## 11. Próximas tarefas em ordem recomendada

### P0 — Preservar e consolidar o protótipo

1. revisar `git status` e esta documentação;
2. remover Google Fonts ou empacotar fontes locais;
3. executar novamente `npm run check` e `npm audit`;
4. realizar um commit do corte PWA antes de iniciar o Bridge.

### P1 — Implementar o Bridge mínimo

1. servidor estático em `127.0.0.1:43127`;
2. endpoint `/health`;
3. agenda persistente de sessão;
4. alerta acelerado em modo de teste, por exemplo 20 e 40 segundos;
5. ACK enviado pela PWA;
6. retomada de checkpoint vencido;
7. abertura da rota correta no navegador.

### P2 — Empacotar o ZIP offline

1. criar o layout portátil;
2. criar instalador por usuário, sem administrador;
3. preservar `data/` em atualizações;
4. gerar `VERSION` e SHA-256;
5. testar descompactação e inicialização em pasta limpa;
6. publicar o ZIP versionado no Fireclaw.

### P3 — Adaptador de arquivo SPIKE

1. aceitar `.llsp`, `.llsp3` e, se necessário, `.spk`;
2. selecionar explicitamente o projeto da sessão, evitando “arquivo mais
   recente” de outra turma;
3. ler ZIP com `System.IO.Compression` do próprio .NET/PowerShell;
4. suportar blocos e Python;
5. gerar apenas métricas agregadas;
6. aplicar limites contra arquivos corrompidos ou ZIP bombs;
7. usar retry ao ler um arquivo durante salvamento;
8. criar fixtures anonimizadas para testes no Linux.

### P4 — Executar o Spike Probe no Windows

1. gerar diagnóstico UIA sanitizado;
2. verificar canvas, quadro, modo, execução e bloco focado;
3. testar com SPIKE minimizado e em primeiro plano;
4. comparar versões disponíveis nas escolas;
5. decidir se UIA entra no produto ou permanece apenas experimental.

### P5 — Sincronização real

1. API de ingestão autenticada e idempotente por `event_id`;
2. envio em lote com retry e confirmação parcial;
3. marcação de evento como sincronizado somente após ACK do servidor;
4. RLS e validação do dispositivo no backend;
5. política de retenção e exclusão local;
6. nenhuma chave secreta na PWA ou no Bridge.

## 12. Critérios de aceite do próximo corte

- a aula inicia e termina sem internet;
- nenhuma dependência é baixada durante instalação ou execução;
- o mesmo build web testado no Linux é servido pelo Bridge no Windows;
- alertas funcionam com a janela da webapp minimizada;
- checkpoint ignorado é lembrado novamente e pode ser retomado;
- reinício ou suspensão não perde a agenda;
- respostas nunca passam pelo processo PowerShell;
- recusa não cria eventos;
- atualizações não apagam dados pendentes;
- parser SPIKE nunca persiste código ou identificadores do Hub;
- inferências técnicas sempre incluem origem, versão e confiança;
- falha de leitura do SPIKE não impede o questionário ou a atividade.

## 13. Questões que ainda exigem decisão

1. O projeto SPIKE será salvo em uma pasta padronizada pelo PulseLab ou escolhido
   uma vez no início da sessão?
2. Quantas vezes o alerta será repetido e em qual intervalo?
3. A troca de papéis será somente orientada ou confirmada por cada aluno?
4. Quais blocos constituem cada marco das atividades 01, 02 e 03?
5. O modo Python fará parte do piloto inicial?
6. Qual versão do SPIKE está instalada na maioria das escolas?
7. As políticas escolares permitem PowerShell assinado e execução por usuário?
8. Qual navegador e versão estão disponíveis nos computadores?
9. O envio será feito diretamente pela PWA ou por uma API intermediária do
   Fireclaw?

## 14. Referências usadas na investigação

- LEGO Education — aplicação e linguagens do SPIKE:  
  https://education.lego.com/en-us/teacher-resources/lego-education-spike-prime/support-technical-info/lego-education-spike-prime-support-technical-info-get-the-lego-education-spiketm-app/
- LEGO Education — dados e privacidade do SPIKE:  
  https://education.lego.com/en-us/app-privacy-policy/
- LEGO Education — acessibilidade da aplicação nativa e web:  
  https://spike.legoeducation.com/prime/settings/accessibility
- Protocolo oficial do Hub SPIKE Prime:  
  https://github.com/LEGO/spike-prime-docs
- Parser aberto de `.llsp/.llsp3` usado como referência técnica:  
  https://github.com/astrospark/flippertools
- Projeto `.llsp3` público usado apenas para verificar o formato:  
  https://github.com/bradjmsu/cookies2025
- Microsoft UI Automation:  
  https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-obtainingelements

## 15. Documentos relacionados no repositório

- `docs/arquitetura-aplicacao-alunos.md` — decisão web-first original;
- `web/agent-simulator/README.md` — execução, testes e escopo da PWA;
- `docs/protocolo-pesquisa-v1.md` — protocolo científico atual;
- `docs/revisao-adversarial-completa-pulselab-2026-08-16.md` — riscos
  encontrados na arquitetura anterior;
- `schema/supabase-schema.sql` — contratos atuais do banco;
- `agent/pulselab-agent.ps1` — implementação Windows legada e peças que podem ser
  extraídas para o Bridge.

## 16. Mensagem sugerida para iniciar a próxima sessão

```text
Continue o desenvolvimento do PulseLab pela documentação
docs/HANDOFF-pwa-alunos-spike-bridge.md. Estamos na branch
feat/student-pwa-linux-first, com alterações ainda não commitadas. Não descarte o
worktree. Primeiro confira branch, status e testes; depois execute o P0 e avance
para o Bridge mínimo do P1. Preserve a PWA como única interface dos alunos e o
PowerShell apenas como servidor local, relógio e motor de alertas.
```
