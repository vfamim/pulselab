# Simulador web do agente PulseLab

Aplicação navegável para validar linguagem, ordem das telas, instrumentos,
eventos e regras de qualidade da versão 1.5.0 em Linux ou qualquer navegador.

O simulador não acessa APIs Win32, não captura a tela e não envia dados ao
Supabase. Telemetria, relógio e conectividade são representações controladas
para testes.

## Executar

```bash
npm install
npm run dev
```

Acesse `http://localhost:3000`.

## Validar

```bash
npm test
npm run check
npm run build
```

## Cenários

- fluxo padrão;
- checkpoint atrasado;
- janela do SPIKE ausente;
- queda de rede e sincronização posterior;
- encerramento antecipado;
- troca de papéis não confirmada;
- recusa de assentimento;
- aborto na rubrica.

No encerramento é possível baixar um JSON com a sessão, as respostas e toda a
linha do tempo gerada.
