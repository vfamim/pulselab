# PulseLab — aplicação dos alunos

PWA web-first para conduzir a coleta consentida durante a atividade de
robótica. A mesma aplicação React/Vite é executada e testada em Linux e
publicada como arquivos web estáticos; não existe uma segunda implementação
PowerShell/Windows para este fluxo.

## Jornada implementada

1. um adulto informa os códigos da aula e confirma a autorização institucional;
2. cada participante escolhe individualmente se quer participar;
3. cada participante responde duas perguntas antes da atividade;
4. a atividade começa com checkpoints automáticos aos 20 e 40 minutos;
5. o dispositivo mostra uma tela de passagem antes de cada resposta individual;
6. depois do primeiro checkpoint, a dupla troca os papéis;
7. cada participante responde a etapa final;
8. a sessão permanece na fila local até existir um adaptador de sincronização.

Não há nomes, fotos da tela, detecção do SPIKE, telemetria de janelas, trilha do
instrutor ou rubrica nesta aplicação.

## Persistência e offline

- o estado atual é salvo localmente e pode ser retomado após fechar a página;
- os eventos append-only ficam em IndexedDB;
- o service worker mantém o shell e os arquivos versionados para abrir offline;
- o relógio usa timestamps absolutos, então fechar e reabrir a página não pausa
  o tempo da atividade;
- enquanto o backend não estiver conectado, a interface diz explicitamente que
  os registros aguardam sincronização e não simula sucesso no modo normal.

## Executar no Linux

```bash
cd web/agent-simulator
npm install
npm run dev -- --host 127.0.0.1
```

O Vite informa a porta local. O caminho público de produção é `/alunos/`.

Para percorrer a aula sem esperar 20 e 40 minutos, use `?lab=1`. Esse modo
mostra a outbox técnica e oferece botões para abrir os checkpoints. Ele não
altera a jornada apresentada aos alunos em produção.

## Validar o mesmo artefato que será publicado

```bash
npm run check
```

O comando executa testes unitários, gera `../../alunos/` e abre esse build no
Google Chrome instalado no Linux para os testes end-to-end. A suíte cobre o
fluxo completo de dois alunos, recusa sem eventos, retomada depois de reload e
abertura offline pelo service worker.

Comandos separados:

```bash
npm run test:unit
npm run build
npm run test:e2e
```

## Fronteira ainda pendente

O envio real não faz parte deste primeiro corte. A próxima entrega deve incluir
um endpoint de ingestão autenticado, idempotente por `event_id`, que aceite lotes
da outbox e grave nas tabelas `research_events` e
`research_session_events`. Chaves administrativas nunca devem ir para o PWA.
