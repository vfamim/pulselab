# PulseLab — Protocolo de validação do simulador web

## 1. Finalidade

O simulador web permite que coordenação, instrutores e participantes percorram
o fluxo do agente PulseLab 1.4 em Linux, macOS, Windows, tablet ou celular. Ele
foi criado para validar o desenho do instrumento antes de ampliar o piloto para
outras sedes.

O teste deve responder a perguntas como:

- as instruções são compreendidas sem a presença do pesquisador central?
- cada pessoa entende quando deve responder sozinha?
- recusa, pedido de ajuda e encerramento são claros?
- o instrutor consegue conduzir a sessão sem improvisar o protocolo?
- falhas técnicas ficam visíveis e geram uma decisão de qualidade?
- a linha do tempo permite reconstruir o que ocorreu?

## 2. Limite da evidência

O simulador é uma representação controlada. Ele não captura tela, não detecta o
LEGO SPIKE, não mede inatividade real, não grava no Supabase e não executa o
cache offline do agente Windows.

Portanto, um teste bem-sucedido oferece evidência sobre usabilidade, linguagem,
sequência operacional, estrutura dos dados e regras automáticas de qualidade.
Ele não demonstra, sozinho, que:

- a aplicação substitui observação humana;
- as medidas têm validade científica;
- a coleta real funciona em todas as máquinas;
- os eventos enviados correspondem fielmente ao comportamento observado;
- os resultados podem ser generalizados para todas as sedes.

Essas afirmações dependem de piloto presencial, comparação entre fontes,
confiabilidade entre observadores, testes do agente Windows e governança ética.

## 3. Participantes recomendados

Em cada rodada, envolver:

- um instrutor que ainda não conheça detalhadamente o fluxo;
- uma dupla representativa do público-alvo;
- um facilitador que apenas observe e registre dificuldades;
- na fase inicial, o pesquisador central para comparar a tela com o ocorrido.

O facilitador não deve ensinar o caminho da interface. Qualquer ajuda necessária
é um achado de usabilidade e deve ser registrada.

## 4. Cenários mínimos

| Cenário | Ação principal | Resultado esperado |
|---|---|---|
| Fluxo padrão | Concluir todas as etapas | Status `Completa`, dois checkpoints e oito respostas |
| Recusa | Recusar o assentimento | Oficina continua sem eventos de pesquisa |
| Resposta recusada | Usar “Prefiro não responder” | Recusa individual registrada sem bloquear o fluxo |
| Pedido de ajuda | Escolher “Precisamos de ajuda agora” | Alerta ao instrutor e evento `help_requested` |
| Troca não confirmada | Informar que não foi possível trocar | Evento de qualidade e revisão da sessão |
| Checkpoint atrasado | Selecionar o cenário de atraso | Alerta `checkpoint_late` e status de revisão |
| SPIKE ausente | Selecionar o cenário correspondente | Falhas de detecção e captura visíveis |
| Rede indisponível | Selecionar queda de rede | Eventos na fila até sincronização manual |
| Encerramento antecipado | Encerrar antes dos dois marcos | Sessão incompleta ou destinada à revisão |
| Aborto | Abortar na rubrica | Status `Interrompida` |

## 5. Roteiro de uma sessão

1. Abrir o simulador em tela cheia.
2. Informar apenas códigos institucionais de teste.
3. Solicitar que instrutor e dupla sigam o fluxo sem explicação adicional.
4. Registrar cada dúvida, pausa, retorno de tela e ajuda do facilitador.
5. Ao final, abrir as abas **Linha do tempo**, **Respostas** e **Tudo**.
6. Conferir o status de qualidade e exportar o JSON.
7. Fazer uma entrevista curta, separando a percepção da dupla da percepção do
   instrutor.
8. Não usar nomes, imagens ou informações reais de estudantes na simulação.

## 6. Perguntas de debriefing

Para participantes:

- houve alguma palavra que você não entendeu?
- em que momento você ficou em dúvida sobre o que fazer?
- você sentiu que podia recusar ou pular uma resposta?
- ficou claro quando a resposta era individual?
- o pedido de ajuda pareceu seguro e fácil de usar?

Para instrutores:

- você conseguiria executar o fluxo sem o pesquisador central?
- quais etapas competem com a condução da oficina?
- os alertas dizem claramente o que fazer?
- o registro final descreve o que você realmente observou?
- em que situação você telefonaria para a coordenação?

Para a coordenação:

- a linha do tempo permite reconstruir a sessão?
- os alertas distinguem falha técnica de dificuldade pedagógica?
- é possível decidir entre aceitar, revisar ou excluir a sessão?
- que evidência continua dependendo de observação humana?

## 7. Métricas do piloto de usabilidade

Registrar por sede e sem identificação nominal:

- conclusão do fluxo sem ajuda;
- tempo por etapa;
- quantidade e tipo de dúvidas;
- erros de navegação;
- respostas recusadas;
- pedidos de ajuda;
- sessões completas, em revisão e interrompidas;
- divergências entre o status automático e o julgamento do pesquisador.

Como critério inicial de avanço, recomenda-se que todas as tarefas críticas
sejam concluídas sem ajuda em pelo menos duas rodadas consecutivas por perfil de
usuário, que nenhuma pessoa interprete a recusa como punição e que todo alerta
tenha uma ação operacional conhecida. Esses critérios são de produto, não
limiares de validade científica.

## 8. Validação metodológica posterior

Depois de estabilizar a interface:

1. aplicar o agente real e uma observação humana simultaneamente em Juazeiro;
2. comparar pedidos de ajuda, estágios, participação, resultado da missão e
   problemas técnicos;
3. estimar concordância entre registros humanos e digitais;
4. revisar itens e regras com divergência sistemática;
5. repetir em uma segunda sede com suporte remoto;
6. somente então expandir para todas as sedes.

O resultado desejado não é eliminar toda presença humana. É tornar a coleta
padronizada, auditável e viável com instrutores locais, supervisão central e
auditorias amostrais.

## 9. Decisão ao final de cada rodada

Classificar cada achado como:

- **linguagem**: texto ambíguo, técnico ou inadequado à faixa etária;
- **fluxo**: ordem ou transição confusa;
- **operação**: exige atenção impraticável do instrutor;
- **ética**: autonomia, privacidade ou assentimento insuficientes;
- **dado**: evento ausente, inconsistente ou sem interpretação;
- **qualidade**: alerta ausente, excessivo ou sem ação;
- **infraestrutura**: depende de teste no agente Windows.

Uma rodada valida o incremento quando não restam falhas críticas de linguagem,
ética ou operação e quando os eventos exportados correspondem às ações
realizadas. A credibilidade científica continua condicionada às etapas de
validação metodológica.
