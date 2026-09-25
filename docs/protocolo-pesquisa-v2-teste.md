# Protocolo PulseLab v2 — versão para teste

Status: protótipo experimental, somente dados fictícios. Substitui a descrição
operacional v1 para esta branch; não altera retrospectivamente o significado
dos dados v1. Unidade principal: bancada, composta por 1 a 4 integrantes.

## Pergunta e contribuição

Em oficinas escolares de robótica com infraestrutura limitada, qual conjunto
mínimo de dados permite descrever dificuldades e resultados da atividade com
validade suficiente para orientar a mediação, preservando a participação
voluntária e impondo baixo esforço de coleta?

A contribuição pretendida é evidência sobre viabilidade, validade e utilidade
de uma coleta minimizada. Não se afirma originalidade da combinação de logs e
autorrelatos, eliminação de vieses, custo zero ou efeito causal da robótica.

O primeiro estudo será de desenvolvimento/viabilidade. Comparação de escolas,
aprendizagem individual, retenção e redução de desigualdade exigem outros
desenhos e não são resultados deste aplicativo.

## Unidade e participantes

As respostas são da bancada. Não serão duplicadas por integrante nem tratadas
como medidas individuais repetidas. O UUID da bancada permanece estável;
papéis são atributos confirmados separadamente, nunca identidades.

Faixa escolar é contexto agregado. Selecionar uma faixa no software não valida
linguagem ou instrumento para essa população. Idade mínima, anos escolares,
critérios de inclusão e adaptações de acessibilidade precisam ser definidos
com a equipe pedagógica antes de um estudo com participantes.

Duplas são o cenário principal a validar. Individual, trio e quarteto podem
ser simulados, mas precisam de avaliação própria e análise separada. Não há
equivalência de mensuração demonstrada entre tamanhos de grupo.

## Atividade de referência

`distance-stop`, versão `0.1-test`: programar avanço e parada diante de
obstáculo a menos de 10 cm; realizar três tentativas nas mesmas condições.
Objetivos: relacionar leitura do sensor, condição de parada e repetição da
leitura. A versão da atividade é incluída em cada sessão.

A atividade é uma proposta de teste que requer revisão pedagógica. Usar outra
missão exige outra versão, itens e critérios correspondentes. A seleção de
“outra plataforma” permite testar o relato e a rubrica sem parser, não afirma
equivalência pedagógica entre kits.

## Fluxo e escolhas

1. Instrutor fornece códigos de sede, escola, oficina, turma e instrutor,
   faixa escolar, plataforma e tamanho real da bancada.
2. Confirma uso de dados fictícios nesta versão.
3. Cada integrante recebe convite e tem opção desmarcada de aceite. Todos
   precisam aceitar para haver registros da bancada. Recusa de qualquer um
   libera a atividade sem criar sessão de pesquisa.
4. Pré: experiência do grupo, confiança e dois itens conceituais experimentais.
5. Atividade: papéis confirmados manualmente; pedido e atendimento de ajuda.
6. Check-ins 20/40: esforço coletivo percebido, etapa, bloqueio e oportunidade
   de participação. Solo não recebe o item de participação do grupo.
7. Pós: compreensão percebida, intenção, afeto e dois itens conceituais.
8. Instrutor avalia execução em três tentativas, explicação e intervenções
   separadamente; informa preparação, dificuldade e próxima ação pedagógica.
9. Devolutiva apresenta resultado observado e limites. Exportação é explícita.

Cada pergunta permite recusa. Ausência de consenso é uma categoria própria,
não um ponto intermediário de escala. Retirada encerra os registros e apaga
toda a sessão local. A atividade pedagógica permanece disponível.

O aceite nesta interface é uma simulação de um processo de assentimento. Não
substitui informação acessível, autorização institucional, consentimento de
responsáveis quando aplicável nem avaliação ética. Esses processos devem ser
definidos e validados institucionalmente antes de liberar outro ambiente.

## Medidas e interpretação

- Esforço: percepção coletiva sobre esforço investido; não diagnóstico de
  carga cognitiva individual nem decomposição de tipos de carga.
- Confiança: expectativa coletiva de realizar a missão; não uma escala de
  autoeficácia individual validada.
- Participação: oportunidade percebida de contribuir; papéis/revezamento
  permanecem descritivos e não definem automaticamente colaboração boa/ruim.
- Execução: 0–3 tentativas que satisfazem o critério da missão, independentemente
  da ajuda recebida. Explicação: rubrica 0–3, avaliada separadamente.
- Conhecimento: dois itens em cada forma, alinhamento conceitual proposto,
  equivalência ainda não demonstrada; não calcular “ganho” como resultado validado.
- Artefato: presença de categorias e contagens no arquivo escolhido. Não prova
  autoria, execução, conexão entre blocos, estágio ou aprendizagem. Variação é
  apenas diferença líquida da contagem, não edição/adicionamento real de blocos.
- Ajuda: quatro timestamps de observação manual. Não há envio de alerta remoto;
  levantar a mão continua sendo o procedimento de sala.
- Ônus: tempo com formulários abertos e preparação declarada. Tempo de tela
  inclui pausas e não equivale automaticamente a tempo ativo de resposta.

## Qualidade, análise e ética

Conclusão operacional, respostas disponíveis, recusas, discordâncias, etapas
ausentes, rubrica, telemetria e desvios temporais são apresentados separadamente.
Uma recusa não torna a criança inadequada nem se converte em resposta válida.
Todo export desta branch é inelegível para análise científica substantiva.

Quando houver estudo aprovado, analisar bancadas agrupadas por oficina/escola,
com correlação intrassessão. Eventos não são participantes independentes.
Não combinar versões ou tamanhos de grupo sem avaliar comparabilidade. Relatar
dados ausentes e perdas técnicas por contexto; não limitar a apresentação às
sessões completas. Definir hipóteses e plano antes de olhar resultados.

Não há evidência causal, longitudinal ou de equidade neste protótipo. O
[plano de validação](plano-validacao-v2.md) define o trabalho empírico pendente.

## Governança a formalizar antes de participantes reais

- Instituição controladora, responsáveis, contato e direitos dos participantes.
- Tramitação ética aplicável, consentimento e assentimento acessíveis.
- População, atividade aprovada, formação docente e critérios da rubrica.
- Necessidade de cada campo e definição de retenção, cópias e descarte.
- Ambiente remoto separado e ingestão autenticada do contrato v2, ainda ausente
  e deliberadamente bloqueada nesta versão local.
- Treinamento, instrumentos de observação e validação com especialistas/crianças.
- Política de devolutiva sem rankings ou identificação de participantes.

A migração de acesso incluída no PR protege o esquema legado e deve ser
revisada/testada em homologação antes de eventual implantação. Ela não cria
autorização para transportar exports de teste à produção.
