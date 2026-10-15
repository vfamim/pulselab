# PulseLab — Aplicação dos Alunos (PWA v2.3.1)

Código-fonte da Progressive Web App (PWA) dos alunos, descrita no [README principal](../../README.md).
A aplicação é desenvolvida em React com Vite e executada no navegador dos computadores das
oficinas de robótica (`http://127.0.0.1:43128/alunos/`).

## Comandos Rápidos

```sh
npm ci
npm run dev -- --host 127.0.0.1 --port 4179
npm run test:unit
npm run check
npm run build
```

- O build de produção estático é gerado em `../../alunos/` (não versionado). A versão vem de `VERSION`: o código usa `__PULSELAB_VERSION__` e o `vite.config.js` substitui no build, inclusive no `sw.js`.
- Testes E2E utilizam Playwright com Chromium (`npx playwright install chromium`) e rodam no CI.
- A suíte de testes unitários (`npm run test:unit`) valida os contratos, parser de telemetria, persistência e governança fail-closed.

## Princípios de Arquitetura e Experiência (v2.3.1)

### 1. Experiência Silenciosa do Aluno
Na rota padrão (`/alunos/`), a interface é 100% silenciosa e serena:
- **Zero formulários ou perguntas**: nenhuma interrupção, escala de humor ou caixa de seleção na tela das crianças durante a oficina.
- **Zero popups ou alertas intrusivos**: o aplicativo permanece em segundo plano ou exibe uma mensagem neutra orientando o uso do software LEGO SPIKE Prime.
- **Foco pedagógico integral**: os estudantes dedicam sua atenção à montagem física e programação no app oficial do robô.

### 2. Bancada Coletiva como Unidade de Análise (LGPD Art. 14)
- A unidade observada é a bancada coletiva (2 a 8 integrantes, `group_size`).
- Em conformidade estrita com o Art. 14 da LGPD para proteção de menores, **não são coletados**:
  nomes, fotos, vídeos, áudios, e-mails, matrículas, digitação de teclas ou capturas de tela (screenshots).
- Não existem identificadores nominais ou individuais de crianças. Apenas identificadores coletivos efêmeros (`session_id`, `group_id`) e contextuais (`site_id`, `machine_label`).

### 3. Coleta Passiva de Telemetria SPIKE
- A cada 10 segundos, a PWA consulta o Bridge local via `GET /v1/spike/metrics`.
- O parser do Bridge (`runtime/windows/bridge/spike-parser.ps1`) analisa projetos salvos do LEGO SPIKE Prime (`.llsp3`, Scratch `.sb3`, Python); a PWA só recebe as métricas agregadas.
- Extrai estritamente métricas estruturais agregadas: contagem de blocos executáveis, pilhas de blocos, uso de motores, sensores, laços de repetição (`loops`) e condicionais (`conditions`).
- **Privacidade total do código**: variáveis de usuário, strings livres, dados de áudio e identificadores Bluetooth do Hub nunca são extraídos ou persistidos.

### 4. Encerramento de Turma pelo Educador/Bancada
- No final da oficina, o educador ou a bancada toca no botão discreto **"Encerrar turma"**.
- O fluxo de fechamento possui apenas duas etapas ultra-rápidas:
  1. **Avaliação da Bancada**: Pergunta coletiva simples com 4 carinhas ("Como foi a oficina para a sua bancada hoje?", com opção "Preferimos não responder").
  2. **Registro do Educador**: Avaliação pedagógica de desfecho com resultado (0 a 3: "Não concluiu", "Concluiu em parte", "Concluiu a missão", "Concluiu e foi além") e nível de apoio recebido ("nenhum", "algum", "muito", ou "Pular avaliação").
- Os contratos e manifestos formais residem em `lib/contracts.js` (`INSTRUMENT_MANIFEST`, `CONFIG_HASH`).

### 5. Modo Laboratório (`?lab=1`)
- Acessível adicionando `?lab=1` à URL (`http://127.0.0.1:43128/alunos/?lab=1`).
- Reservado exclusivamente para pesquisadores e desenvolvedores em ambiente de testes:
  - Painel lateral de diagnóstico técnico com status da conexão com o Bridge;
  - Inspeção em tempo real da telemetria SPIKE detectada;
  - Simulação de eventos e telemetria sintética;
  - Disparo de retirada ética para expurgo imediato.

### 6. Persistência em Dupla Camada
1. **Camada do Navegador**: IndexedDB local (`pulselab-student-runner`), gerenciado por `lib/student-store.js` com stores transacionais `events` e `sessions`.
2. **Camada do Bridge Local**: Eventos e snapshots são enviados via HTTP loopback para o Bridge (`/v1/events` e `/v1/sessions/save`) e armazenados em disco na pasta `dados_locais/` (`events.jsonl`, `sessions.jsonl`).
- **Retenção Configurável**: Dados locais expiram de acordo com `retention_days` do polo (padrão 180 dias), com expurgo atômico pelo navegador e pelo Bridge.

### 7. Governança Fail-Closed e Sincronização
- **Modo Livre por Padrão**: Se não houver configuração institucional autorizada (`provisionamento.json` gerado com CAAE do CEP), o sistema opera em Modo Livre — nenhuma gravação é persistida e nenhuma transmissão remota ocorre.
- **Sincronização em Nuvem**: Quando autorizada e online, o motor de sincronização (`lib/sync-engine.js`) envia lotes de eventos ao Supabase via Store-and-Forward a cada 30 segundos sob credenciais rotativas do dispositivo.
