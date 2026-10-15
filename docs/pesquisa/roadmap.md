# Roadmap do PulseLab

Itens futuros, fora da versão 2.4.0. Nada aqui está implementado nem aprovado
pelo CEP. Cada item que mudar o que é coletado precisa entrar no protocolo, no
inventário de dados e, se for o caso, em nova emenda antes de ir para campo.

Referência anterior, mais ampla: [parecer e roadmap de observação
distribuída](../arquivo/v2/parecer-roadmap-observacao-distribuida.md) (julho de 2026).

## Pré-requisitos da 2.4.0 em campo

- Emenda ao CEP para assentimento verbal aprovada
  ([assentimento verbal](../campo/assentimento-verbal.md), seção 3).
- Aviso aos responsáveis ou TCLE alinhado ao checklist da seção 5 do mesmo
  documento.
- Revisão humana da seção 2 do AGENTS.md, já reescrita para o assentimento
  verbal e o item "Não registrar esta turma".
- Máquinas que se atualizam sozinhas mantêm o atalho de inicialização que já
  tinham: só a reinstalação com o pacote 2.4.0 cria o início automático com o
  Windows. Até lá, o instrutor abre o PulseLab pelo atalho da Área de Trabalho.
- Aplicar a migração `20261014120000_bancada_quality_and_withdrawal_tombstones`
  no Supabase antes de publicar a release: o bridge 2.4.0 envia as colunas
  `ended_by`, `interrupted` e `data_quality`.
- Guia ilustrado (tutorial e PDF do pacote) com imagens da bandeja do Windows.
  As imagens atuais mostram a tela da bancada no navegador, que não é mais usada
  durante a aula.

## Perguntas do instrutor sobre a turma

No fim da aula, além dos itens por bancada, o instrutor responderia 3 itens
fechados sobre a turma inteira:

1. "Quantas bancadas concluíram a missão do dia?" (número)
2. "O ritmo da turma foi:" abaixo do esperado / esperado / acima do esperado
3. "Algo atrapalhou a aula?" nada / falta de energia / robô ou peça com
   problema / problema no computador / atraso / outro

Regras:

- Sem texto livre, para não correr o risco de alguém escrever nomes.
- Ligação com as sessões das bancadas por polo e data, sem identificador de
  criança.
- Respondidas uma vez por turma, não em cada computador. Definir em qual
  computador ou canal o instrutor responde.

## Validações pendentes

- **Leitor do SPIKE.** Conferir o leitor de projetos `.llsp3` contra cerca de
  30 arquivos reais de oficinas (com autorização), comparando a estrutura
  extraída com a inspeção manual de cada projeto. Registrar a versão do leitor
  em cada resultado.
- **Escore de pensamento computacional.** O escore adaptado de Dr. Scratch
  (Moreno-León, Robles & Román-González, 2015) está marcado como "adaptado, não
  validado". Antes de usar em análise: revisar a correspondência entre blocos
  do SPIKE e as dimensões originais, verificar concordância com avaliação de
  especialistas numa amostra e relatar limites. O escore descreve o programa,
  não a aprendizagem da criança.
- **Itens de encerramento.** A pergunta da bancada e os itens do instrutor
  continuam como rascunho até a validação do pesquisador (compreensão pela
  faixa etária, concordância entre instrutores).

## Catálogo e calendário de missões

- Catálogo versionado de missões, com os elementos esperados no programa de
  cada uma (por exemplo, uso de sensor, laço, condição).
- Calendário por polo dizendo qual missão foi aplicada em cada data.
- Com o calendário configurado, o PulseLab já calcula quanto dos elementos
  esperados o programa final alcançou. Sem calendário, essa medida fica vazia,
  não zero.

