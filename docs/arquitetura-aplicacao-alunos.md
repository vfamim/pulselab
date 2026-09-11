# Arquitetura proposta — aplicação dos alunos

## Decisão

O fluxo de coleta dos alunos passa a ser uma PWA. O PowerShell atual permanece
como legado enquanto a nova trilha é validada, mas não é mais a referência de
produto para os alunos.

Essa decisão elimina a diferença entre “simulador Linux” e “aplicativo Windows”:
React, CSS, máquina de estados, armazenamento local e service worker são o mesmo
artefato gerado pelo build e publicado para qualquer navegador compatível.

## Como a aplicação funciona

```text
Preparação por adulto
        ↓
Consentimento individual A → passagem → B → passagem → C (se houver)
        ↓
Pré individual A → passagem → B → passagem → C
        ↓
Atividade em grupo, cronômetro absoluto
        ↓ 20 min
Checkpoint individual → troca de papéis → atividade
        ↓ 40 min
Checkpoint individual → encerramento da atividade
        ↓
Pós individual A → passagem → B → passagem → C
        ↓
Sessão concluída e mantida na outbox até sincronizar
```

Grupos de uma, duas ou três pessoas usam a mesma máquina de estados. Para uma
pessoa, as telas de passagem e a troca de papéis são omitidas.

## Princípios de experiência

- cada tela pede uma única decisão curta;
- não são coletados nome, e-mail ou matrícula;
- antes de trocar de participante, uma tela neutra esconde a resposta anterior;
- a recusa encerra a tentativa sem criar eventos;
- a página não precisa ficar em tela cheia ou sobre o SPIKE;
- o texto diz o estado real: “salvo neste dispositivo” e “aguardando
  sincronização”, sem declarar envio que não aconteceu;
- controles técnicos aparecem apenas com `?lab=1`.

## Componentes

```text
PWA React/Vite
├── máquina de estados da jornada
├── relógio baseado em timestamps
├── snapshot recuperável da tela atual
├── outbox append-only em IndexedDB
└── service worker para shell offline
            ↓ (próxima etapa)
API de ingestão autenticada e idempotente
            ↓
Supabase/Postgres com RLS
├── research_events
└── research_session_events
```

O navegador nunca deve receber uma chave secreta do Supabase. A API de ingestão
validará a instalação, limitará tamanho e frequência dos lotes e responderá quais
`event_id` foram aceitos. Somente então a outbox marcará esses registros como
sincronizados.

## Garantia Linux → produção

Não há transpilação para PowerShell nem empacotamento nativo. O pipeline testa o
diretório `alunos/`, que é exatamente a saída estática destinada à hospedagem.
No Linux, o Chrome percorre automaticamente:

- a jornada completa de dois participantes e dois checkpoints;
- a recusa antes da coleta;
- a retomada após reload;
- a inicialização offline pelo service worker;
- o layout responsivo, verificável no mesmo navegador usado em aula.

Ainda será saudável executar uma matriz de navegadores antes do piloto — por
exemplo Chrome/Edge nas versões disponíveis nas escolas — mas isso passa a ser
compatibilidade web, não equivalência entre dois sistemas operacionais e duas
bases de código.

## Recorte desta branch

Implementado:

- jornada dos alunos sem rubrica/trilha do instrutor;
- modo normal e modo de laboratório;
- build publicado em `/alunos/`;
- PWA instalável e shell offline;
- persistência local e retomada;
- outbox com eventos alinhados aos contratos atuais;
- testes unitários e end-to-end no Linux.

Próximas entregas:

1. API real de ingestão e autenticação do dispositivo;
2. sincronização em lote com retry e confirmação por evento;
3. configuração remota versionada do instrumento;
4. validação dos textos e escalas com alunos antes do piloto;
5. migração explícita ou retirada do agente PowerShell após a validação.
