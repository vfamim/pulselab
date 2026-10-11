# Protocolo PulseLab v2 — versão para teste (v2.3.3)

Status: instrumento em rascunho operacional e protótipo de pesquisa. Substitui a descrição
operacional v1; não altera retrospectivamente o significado de dados históricos.
Unidade principal: bancada coletiva, composta por 2 a 8 integrantes.

## Pergunta e contribuição

Em oficinas escolares de robótica com infraestrutura limitada, qual conjunto
mínimo de dados permite descrever dificuldades e resultados da atividade com
validade suficiente para orientar a mediação, preservando a participação
voluntária e impondo baixo esforço de coleta?

A contribuição pretendida é evidência sobre viabilidade, validade e utilidade
de uma coleta minimizada e passiva. Não se afirma originalidade da combinação de logs e
autorrelatos, eliminação de vieses, custo zero ou efeito causal da robótica.

O primeiro estudo será de desenvolvimento/viabilidade. Comparação de escolas,
aprendizagem individual, retenção e redução de desigualdade exigem outros
desenhos e não são resultados deste aplicativo.

## Unidade e participantes

As respostas são da bancada coletiva. Não serão duplicadas por integrante nem tratadas
como medidas individuais repetidas. O UUID da bancada permanece estável (`group_id`).
Em conformidade com a LGPD (Art. 14), não são coletados nomes, fotos, vídeos, áudios,
matrículas, CPF ou identificadores individuais de crianças.

Faixa escolar é contexto agregado. Selecionar uma faixa no software não valida
linguagem ou instrumento para essa população. Idade mínima, anos escolares,
critérios de inclusão e adaptações de acessibilidade precisam ser definidos
com a equipe pedagógica antes de um estudo com participantes.

Bancadas colaborativas de 2 a 8 integrantes são a unidade analítica. Respostas
individuais e comparações intra-equipe não são geradas pelo instrumento.

## Atividade de referência

`distance-stop`, versão `0.1-test`: programar avanço e parada diante de
obstáculo a menos de 10 cm; realizar três tentativas nas mesmas condições.
Objetivos: relacionar leitura do sensor, condição de parada e repetição da
leitura. A versão da atividade é incluída em cada sessão.

A atividade é uma proposta de teste que requer revisão pedagógica. Usar outra
missão exige outra versão, itens e critérios correspondentes. A seleção de
“outra plataforma” permite testar o relato e a rubrica sem parser, não afirma
equivalência pedagógica entre kits.

## Fluxo e escolhas (v2.3.3)

1. Contexto institucional provisionado pelo polo (`provisionamento.json`) com código
   do polo, regional e CAAE oficial aprovado pelo comitê de ética (CEP/CONEP).
   Sem o provisionamento, o sistema opera em Modo Livre com coleta desativada.
2. Durante a oficina: **experiência silenciosa do aluno**. Zero formulários, questionários
   ou popups intrusivos na tela. As crianças concentram 100% de sua atenção na montagem e
   programação com o kit LEGO SPIKE Prime.
3. Observabilidade passiva: o Bridge local inspeciona periodicamente os arquivos de projeto
   salvos (`.llsp3`, Scratch `.sb3`, Python) e emite métricas agregadas de complexidade estrutural
   (blocos executáveis, motores, sensores, loops e condições) sem armazenar código de usuário.
4. Encerramento de turma: acionado no término da aula pelo botão discreto "Encerrar turma":
   - **Bancada**: responde a uma pergunta rápida com 4 carinhas sobre como foi a oficina hoje
     (`experiencia_bancada_v1`, com opção "Preferimos não responder").
   - **Educador**: registra o desfecho prático da bancada (0 a 3: *Não concluiu*, *Concluiu em parte*,
     *Concluiu a missão*, *Concluiu e foi além*) e o apoio recebido (*nenhum*, *algum*, *muito*, ou *Pular avaliação*).
5. Concluído o registro, a sessão da bancada é encerrada e persistida em dupla camada (IndexedDB + Bridge),
   ficando pronta para a próxima turma.

Cada item permite recusa. Retirada ética pelo botão "Parar de participar e apagar meus dados"
encerra os registros imediatamente, purga o banco local e grava tombstone durável.
A atividade pedagógica permanece disponível em Modo Livre.

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
