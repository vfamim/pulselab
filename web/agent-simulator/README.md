# PulseLab — PWA de teste v2

Fonte da versão isolada descrita no [README principal](../../README.md).

```sh
npm ci
npm run dev -- --host 127.0.0.1 --port 4179
npm run check
```

O build é gerado em `alunos/`. O aplicativo usa `lib/protocol.js` como
fonte única das perguntas e `lib/research-session.js` como modelo da sessão.
O IndexedDB `pulselab-test-bancada-v2` guarda a sessão inteira numa transação.
Não há localStorage de respostas, outbox ou adaptador de envio remoto ativo.
A leitura opcional de .llsp3/.sb3/.json é local, por arquivo escolhido.

Playwright usa Google Chrome. Se necessário: `npx playwright install chrome`.
A leitura de ZIP usa fflate com limite de tamanho comprimido/descomprimido.
