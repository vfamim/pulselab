# Roteiro de teste isolado — PulseLab v2

Use somente pessoas fictícias e projetos de exemplo. Esta versão não representa
aprovação ética ou instrumento validado. Não aplique migrações na produção.

## Abrir no Windows

1. Na branch do PR, abra `test-packages/PulseLab-TESTE-v2-Windows.zip`,
   use o botão de download e extraia todo o pacote. O arquivo `.sha256`
   ao lado permite conferir sua integridade.
2. Execute `Iniciar-PulseLab.bat` na pasta extraída. Não execute scripts antigos
   da instalação principal. Não é preciso instalar Node no Windows.
3. Abra `http://127.0.0.1:43128/alunos/`. A porta principal 43127 não é usada.
4. Mantenha a janela do servidor aberta. Ao terminar, pode fechá-la.

No Linux/macOS, execute `npm ci` e `npm run dev -- --host 127.0.0.1 --port 4179`
em `web/agent-simulator` e abra `http://127.0.0.1:4179/alunos/`.

## Cenários de aceitação

| Cenário | Ação | Resultado esperado |
|---|---|---|
| Recusa | Preparar contexto fictício; continuar sem registros | Atividade livre; nenhuma sessão ou pergunta posterior |
| Aceite incompleto | Marcar só um integrante da dupla | Iniciar registros continua desabilitado |
| Coleta completa | Aceitar todos; responder pré; abrir check-ins 20/40; responder pós; preencher rubrica | Encerramento com resultado, devolutiva e exportação |
| Item recusado | Usar “Prefiro não responder” | Prossegue sem substituir por zero |
| Discordância | Usar “Não chegamos a uma resposta conjunta” | Categoria separada, sem média artificial |
| Individual | Selecionar 1 integrante | Não aparece pergunta de participação em grupo |
| Papéis | Confirmar novas tarefas na área do instrutor | Identidade da bancada permanece a mesma; não há troca automática |
| Ajuda | Solicitar; reconhecer; iniciar; resolver | Quatro momentos distintos no JSON |
| Antecipação | Abrir check-in manualmente | Marca 20/40 preservada; tempo real não vira 20/40 minutos |
| Etapa ausente | Encerrar sem os dois check-ins | Resumo informa quais etapas faltam |
| Rubrica | Tentar concluir sem resultado/explicação/apoio/devolutiva | Não conclui; ajuda não altera a pontuação de execução |
| Projeto | Selecionar exemplo salvo desta sessão | Só contagens/categorias; nenhuma inferência de missão ou probabilidade |
| Projeto incompatível | Selecionar Python/JSON sem blocos | Erro explícito; não produz “projeto vazio” ou “montagem inicial” |
| Retomada | Recarregar após salvar | Abrir sessão preserva contexto, identidade e início da atividade |
| Offline | Carregar build uma vez; desligar rede; recarregar | Interface e registros locais disponíveis |
| Retirada | Parar registros e apagar sessão | Apaga respostas, eventos, rubrica e artefatos locais juntos |
| Exportação | Baixar JSON | `environment: test`, instrumento completo e limites explícitos |

Para testar rapidamente, abra os controles de teste na tela da atividade. Eles
não falsificam o relógio: os registros ficam marcados como antecipados/manuais.
Para validar temporizadores reais, deixe a aba aberta durante 20 e 40 minutos.
Notificações nativas de foco não fazem parte deste pacote; verifique o fluxo com
a aba visível. O objetivo desta branch é comparar o protocolo e a experiência.

## Conferir isolamento

- A tela identifica a versão como teste e o envio à nuvem fica desativado.
- As ferramentas do navegador não devem mostrar POST para Supabase ou Bridge.
- A aplicação usa o IndexedDB `pulselab-test-bancada-v2` no endereço de teste.
- O servidor fornece apenas arquivos estáticos. Não há `events.jsonl`, leitura
  automática de pastas, tokens de dispositivo ou atualização a partir da main.
- Exportações são arquivos locais sob responsabilidade do testador. Não são
  apagadas pelo botão de retirada nem pela retenção do aplicativo.
- O banco apaga sessões expiradas ao iniciar o aplicativo; numa sessão ativa,
  também verifica a expiração a cada segundo. Navegador fechado não executa tarefas.

## Registrar feedback

Anote cenário, resultado esperado, resultado observado, navegador/Windows e
versão do pacote. Use códigos fictícios. Avalie compreensão das perguntas,
quantidade de pausas, facilidade de recusar e utilidade da devolutiva. Um teste
funcional bem-sucedido não prova validade científica ou aceitabilidade infantil.
