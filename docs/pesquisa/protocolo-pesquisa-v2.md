# Protocolo PulseLab v2 — oficinas por bancada

Status: descreve a operação a partir da versão 2.4.0. Itens de encerramento e
medidas do programa ainda são rascunho, pendentes de validação do pesquisador.
A coleta com crianças depende da aprovação, pelo CEP, da emenda de
assentimento verbal ([assentimento verbal](../campo/assentimento-verbal.md)). Não altera
retrospectivamente o significado dos dados v1. Unidade de análise: bancada.

## Pergunta e contribuição

Em oficinas escolares de robótica com infraestrutura limitada, qual conjunto
mínimo de dados permite descrever dificuldades e resultados da atividade com
validade suficiente para orientar a mediação, preservando a participação
voluntária e impondo baixo esforço de coleta?

A contribuição pretendida é evidência sobre viabilidade, validade e utilidade
de uma coleta minimizada. Não se afirma eliminação de vieses, custo zero ou
efeito causal da robótica.

O primeiro estudo será de desenvolvimento/viabilidade. Comparação de escolas,
aprendizagem individual, retenção e redução de desigualdade exigem outros
desenhos e não são resultados deste aplicativo.

## Unidade e participantes

A bancada é o grupo de crianças que usa o mesmo computador e o mesmo kit
durante a aula inteira. Cada computador é uma bancada. Nenhuma medida é
atribuída a uma criança; respostas e medidas da bancada não são duplicadas por
integrante.

Faixa escolar, idade mínima, critérios de inclusão e adaptações de
acessibilidade precisam ser definidos com a equipe pedagógica e constar do
protocolo aprovado.

## Assentimento e recusa

Resumo; o procedimento completo está em [assentimento
verbal](../campo/assentimento-verbal.md).

- As famílias são informadas antes, por TCLE ou aviso aos responsáveis com
  possibilidade de recusa, conforme aprovado pelo CEP.
- No início de cada aula, o instrutor lê um roteiro padronizado: o que é
  registrado (como o programa do robô evolui no computador da bancada e uma
  pergunta curta no fim), o que não é (nomes, fotos, vídeo, áudio, teclas,
  cliques, tela), que participar é voluntário e que qualquer um pode recusar a
  qualquer momento, sem consequência.
- Se qualquer criança da bancada, ou sua família, recusar, o instrutor usa
  **Não registrar esta turma** no ícone do PulseLab daquele computador. Os dados
  da turma atual naquele computador são apagados, com marca de exclusão que
  impede o retorno por pendrive ou reenvio, e o registro pausa até a próxima
  turma. A bancada continua a atividade normalmente.
- Não há caixas de assentimento nem botão de retirada na tela.

## Operação na aula (2.4.0)

1. O PulseLab inicia com o Windows. Um ícone na área de notificação (bandeja)
   mostra que o registro está ativo. Nenhuma página fica aberta durante a aula.
   Se o PulseLab parar, a bandeja o reinicia.
2. A sessão da turma começa sozinha quando o PulseLab inicia ou, depois de uma
   turma encerrada, quando a bancada salva o primeiro programa.
3. A bancada trabalha no aplicativo LEGO SPIKE. O PulseLab lê os projetos
   salvos no computador.
4. No fim, o instrutor clica com o botão direito no ícone e escolhe
   **Encerrar turma…**. Abre um formulário curto:
   - pergunta coletiva da bancada com 4 carinhas ou "Preferimos não responder";
   - resultado da bancada (0 a 3) e apoio recebido (nenhum, algum, muito),
     preenchidos pelo instrutor, que pode pular.
5. Se ninguém encerrar, a sessão fecha sozinha depois de 3 horas, ou na próxima
   inicialização quando o computador ficou desligado por mais de 20 minutos.
   Assim, esquecer de encerrar não mistura turmas.

Menu da bandeja: **Encerrar turma…**, **Não registrar esta turma**,
**Ver situação**.

A coleta só fica ligada no computador instalado com o pacote do polo
(`provisionamento.json` com CAAE). No pacote genérico nada é registrado para
pesquisa.

## Medidas e interpretação

- **Experiência da bancada:** uma pergunta coletiva, 4 categorias ou recusa.
  Avaliação global da aula pela bancada; não mede motivação, carga cognitiva ou
  aprendizagem. Recusa não é ponto neutro.
- **Resultado (0–3):** avaliação do instrutor sobre a missão da bancada.
  **Apoio:** nenhum/algum/muito. Receber apoio não é penalidade. Pular é uma
  categoria própria, não zero.
- **Estrutura do programa:** a cada versão salva do projeto SPIKE, os tipos de
  blocos e sua organização. Nunca textos digitados pelas crianças (nomes de
  variáveis, mensagens, comentários). Descreve o artefato, não prova autoria,
  execução no robô nem aprendizagem.
- **Escore de pensamento computacional:** adaptado de Dr. Scratch
  (Moreno-León, Robles & Román-González, 2015), marcado como "adaptado, não
  validado". Mede o programa, não a criança.
- **Cobertura da missão:** quando o polo tem calendário de missões configurado,
  quanto dos elementos esperados da missão o programa final alcançou. Sem
  calendário, a medida fica ausente, não zero.

Essas medidas descrevem o programa e a avaliação da aula. Nenhuma delas mede a
aprendizagem individual.

## Qualidade dos dados

Cada sessão registra:

- como terminou: `instrutor`, `tempo` (3 horas) ou `sem_encerramento`
  (computador desligado por mais de 20 minutos);
- se a coleta foi interrompida: computador desligado ou falhas no "sinal de
  vida" emitido a cada 5 minutos;
- situação da pasta de projetos do SPIKE (encontrada ou não).

A equipe de pesquisa vê no painel quais máquinas estão sem enviar dados há X
dias. Sessões encerradas por tempo ou sem encerramento, ou com interrupções,
são analisadas separadamente ou com essa marcação; ausência de projeto SPIKE
não vira "zero".

## Análise e ética

Analisar bancadas agrupadas por oficina/escola/polo. Eventos e versões do
programa não são participantes independentes. Não combinar versões do
instrumento sem avaliar comparabilidade. Relatar dados ausentes, recusas,
turmas não registradas e perdas técnicas por contexto; não limitar a
apresentação às sessões completas. Definir hipóteses e plano antes de olhar os
resultados. Não há evidência causal, longitudinal ou de equidade.

Os dados são desidentificados, não anônimos: a escola sabe quem sentou em cada
bancada em determinado dia. Base: Resolução CNS 510/2016 e LGPD (art. 7º, IV;
art. 14). Detalhes em [assentimento verbal](../campo/assentimento-verbal.md), seção 4.

Retenção local: `retention_days` do pacote do polo (padrão 180 dias, 1 a 365),
igual no protocolo, no TCLE e no pacote. A cópia local permanece durante todo o
prazo, mesmo depois do envio à nuvem ou da exportação.

## Governança a formalizar antes de coleta real

- Emenda ao CEP (assentimento verbal) aprovada e CAAE no pacote do polo.
- Instituição controladora, responsáveis, contato e direitos dos participantes.
- Aviso aos responsáveis ou TCLE com recusa prévia e contato para recusa depois
  da aula.
- Formação dos instrutores no roteiro e no menu da bandeja.
- Validação dos itens de encerramento, do leitor SPIKE e do escore adaptado
  ([roadmap](roadmap.md)).
- Política de devolutiva sem rankings ou identificação de participantes.

## O que saiu da versão anterior deste protocolo

A versão anterior deste documento descrevia uma branch de teste com dados
fictícios: aceites individuais desmarcados na tela, itens pré e pós,
check-ins aos 20 e 40 minutos, papéis por integrante, pedido de ajuda na tela e
botão de retirada. Nada disso faz parte da versão atual. O texto anterior está
no histórico do git.
