# PulseLab como infraestrutura de mensuração em oficinas de robótica educacional

## Relatório acadêmico sobre métricas, validade e contribuição científica

**Versão analisada:** PulseLab 1.4  
**Data:** 29 de julho de 2026  
**Autor:** Vinicius Ferreira Amim  
**Instituição:** Universidade Federal do Vale do São Francisco  
**Atuação no projeto:** Setor de Pesquisa da FADEX — Projeto Robótica Educacional  
**Status do documento:** base para qualificação, apresentação à banca e protocolo de estudo piloto

> **Tese central para a banca:** o PulseLab agrega valor científico porque converte oficinas distribuídas e efêmeras em sessões de pesquisa padronizadas, pseudonimizadas, temporalmente alinhadas e auditáveis. O aplicativo não substitui a teoria, a rubrica pedagógica nem a análise estatística; ele cria a infraestrutura necessária para que perguntas sobre processo, colaboração, esforço percebido, ajuda e resultados imediatos possam ser respondidas com dados comparáveis.

---

## Resumo

Este relatório avalia a capacidade do PulseLab 1.4 de produzir métricas úteis para pesquisas em oficinas de robótica educacional com LEGO SPIKE. A análise combina o protocolo de pesquisa, o modelo de dados, o agente Windows, o simulador e o painel disponíveis no repositório. O desenho recomendado é observacional multicêntrico, de cortes transversais repetidos, com medidas intrassessão. O sistema registra contexto da oficina, experiência prévia, autoeficácia inicial, esforço mental percebido, situação de progresso, pedidos de ajuda, colaboração, compreensão percebida, afetos, intenção de retorno e evidências operacionais de completude e qualidade. A arquitetura também permite reconstruir a linha do tempo da sessão e distinguir respostas concluídas, recusadas e expiradas.

O principal valor científico do PulseLab é a padronização da observação em diferentes escolas e momentos: o mesmo instrumento, os mesmos marcos temporais, a mesma codificação e a versão exata da configuração acompanham cada evento. Isso aumenta a comparabilidade, a rastreabilidade e a possibilidade de análise reprodutível. Entretanto, o sistema ainda não deve ser apresentado como instrumento validado de “carga cognitiva” nem como prova autônoma de aprendizagem. A questão de esforço utiliza uma adaptação ordinal de quatro categorias que requer evidências de validade para a população atendida. Além disso, a rubrica de desempenho está implementada no simulador e prevista no banco, mas não é atualmente persistida pelo agente Windows; os itens pré/pós de conhecimento permanecem indefinidos; e o dashboard exibe dados simulados.

Conclui-se que o PulseLab já é adequado como infraestrutura de um piloto de viabilidade e de investigação do processo vivido na oficina. Após completar a rubrica, definir os itens de conhecimento, validar o instrumento, implantar o painel analítico real e formalizar os procedimentos éticos, poderá sustentar estudos quantitativos mais fortes sobre associações entre esforço, colaboração, mediação e desempenho imediato.

**Palavras-chave:** robótica educacional; learning analytics; mensuração educacional; esforço mental; aprendizagem colaborativa; estudo observacional; qualidade de dados.

---

## 1. Problema de pesquisa e justificativa

Oficinas de robótica são experiências práticas, colaborativas e distribuídas entre programação, montagem, teste, discussão e intervenção do instrutor. Uma avaliação restrita ao produto final perde a trajetória que levou ao resultado. Por outro lado, manter pesquisadores observando todas as duplas em várias escolas é custoso, pouco escalável e sujeito a variações entre observadores.

A literatura sobre robótica educacional identifica resultados promissores, mas também ressalta que a presença do recurso tecnológico não garante, por si só, melhoria da aprendizagem e que o método de avaliação precisa ser cuidadosamente definido (BENITTI, 2012). No campo de *learning analytics*, o objetivo não é apenas acumular registros digitais, mas coletar, analisar, interpretar e comunicar dados de modo teoricamente relevante e acionável para melhorar ensino e aprendizagem (SoLAR, 2025). A abordagem multimodal é particularmente pertinente a tarefas abertas, como construir um robô ou um programa, nas quais processo e produto não ficam inteiramente representados em uma única prova ou em cliques de uma plataforma (BLIKSTEIN, 2013).

O PulseLab responde a esse problema ao combinar quatro camadas:

1. **contexto:** escola, oficina, turma, atividade, experiência prévia e papel;
2. **processo percebido:** esforço mental, estado de progresso, necessidade de ajuda e colaboração;
3. **resultado imediato:** compreensão percebida, afetos, intenção de retorno e, após a integração pendente, desempenho da missão e conhecimento específico;
4. **qualidade da evidência:** linha do tempo, completude, atrasos, recusas, timeouts, sincronização, versão do protocolo e alertas técnicos.

Essa combinação permite responder não somente “quantas crianças participaram?”, mas “em que momento houve maior esforço?”, “quais situações antecederam pedidos de ajuda?”, “a experiência foi diferente conforme o papel?”, “a colaboração se associou ao desempenho?” e “com que completude e atraso esses dados foram obtidos?”.

---

## 2. Enquadramento metodológico

### 2.1 Desenho recomendado

O desenho compatível com o funcionamento atual é:

> **Estudo observacional multicêntrico, de cortes transversais repetidos, com medidas intrassessão, realizado em oficinas pontuais de robótica educacional.**

Cada estudante participa de uma oficina, mas responde em diferentes momentos dentro da mesma sessão. Portanto:

- o estudo descreve processo e resultados imediatos;
- as medidas dos minutos 20 e 40 da mesma criança são dependentes;
- participantes de uma mesma dupla compartilham tarefa, robô, instrutor e contexto;
- duplas estão agrupadas em oficinas, escolas e polos;
- não existe seguimento individual suficiente para medir retenção ou desenvolvimento longitudinal;
- sem grupo comparador ou implantação experimental, associações não devem ser redigidas como efeitos causais.

As recomendações STROBE são uma referência apropriada para relatar de forma transparente desenho, participantes, variáveis, vieses, tamanho amostral, dados ausentes e limitações de estudos observacionais (VON ELM et al., 2007).

### 2.2 Unidades de observação e de análise

```text
Polo/região
└── Escola
    └── Oficina/turma
        └── Sessão/dupla
            ├── Participante A
            │   ├── pré
            │   ├── checkpoint 20
            │   ├── checkpoint 40
            │   └── pós
            └── Participante B
                ├── pré
                ├── checkpoint 20
                ├── checkpoint 40
                └── pós
```

O **evento** é a unidade de armazenamento; o **participante** é a unidade das respostas individuais; a **dupla** é a unidade natural da missão compartilhada; e a **oficina/escola** representa o contexto de aplicação. Uma análise correta deve respeitar esses níveis para não tratar observações correlacionadas como se fossem independentes.

---

## 3. Como o PulseLab transforma a oficina em números

### 3.1 Cadeia de mensuração

| Etapa | O que ocorre na oficina | Registro produzido | Informação que pode ser estimada |
|---|---|---|---|
| Entrada | Contexto e assentimento são conferidos | IDs pseudonimizados, escola, turma, atividade e versão | alcance, composição da amostra e rastreabilidade |
| Pré-oficina | Cada participante responde individualmente | experiência prévia e autoeficácia | perfil inicial e variáveis de ajuste |
| Minuto 20 | Resposta individual e evidência técnica | esforço, progresso, ajuda, papel, latência e atraso | estado inicial do processo |
| Troca de papéis | Participantes alternam funções | evento `role_swapped` ou alerta | adesão ao protocolo e exposição aos papéis |
| Minuto 40 | Nova resposta individual | esforço, progresso, ajuda e colaboração | mudança intrassessão e colaboração percebida |
| Encerramento | Instrutor e participantes avaliam a oficina | experiência final e, quando integrado, rubrica | resultado imediato e aceitabilidade |
| Sincronização | Eventos são enviados ou enfileirados | horário local, recebimento e IDs únicos | perda, atraso, recuperação e duplicidade |

### 3.2 Três classes de indicadores

Para evitar conclusões indevidas, o relatório científico deve separar:

- **medidas diretas:** respostas dadas por participante ou instrutor;
- **indicadores derivados:** proporções, distribuições, transições e estimativas calculadas a partir das respostas;
- **evidências auxiliares:** telemetria e screenshots usados para contexto ou auditoria, sem equivaler automaticamente a aprendizagem, engajamento ou estado mental.

Essa separação é fundamental. Um valor digital só se torna uma medida educacional defensável quando existe uma definição do construto, um procedimento padronizado e evidências que sustentem a interpretação pretendida. Os *Standards for Educational and Psychological Testing* tratam validade como o conjunto de evidências e teoria que sustenta a interpretação dos escores para um uso proposto (AERA; APA; NCME, 2014).

---

## 4. Matriz de métricas do PulseLab

### 4.1 Alcance e caracterização

| Indicador | Definição operacional | Campo/fonte | Escala | Uso científico |
|---|---|---|---|---|
| Sessões iniciadas | contagem distinta de `session_id` com `session_started` | `research_session_events` | contagem | alcance operacional |
| Sessões encerradas | sessões com `session_completed` | `research_session_events` | contagem e proporção | adesão ao fluxo |
| Participantes com coleta | combinação distinta de sessão e participante | `participant_id` + `session_id` | contagem | tamanho observado da amostra |
| Cobertura territorial | escolas, sedes e polos distintos | `school_code`, `site_id`, `regional_hub` | contagem/categorias | diversidade de contextos |
| Experiência prévia | nunca, uma vez, algumas, muitas | `prior_robotics` | ordinal 1–4 | caracterização e ajuste |
| Autoeficácia inicial | discordo muito a concordo muito | `self_efficacy_pre` | ordinal 1–4 | perfil inicial e moderador |

**Limite de caracterização:** para reduzir o tempo do instrumento, o PulseLab
não solicita mais a idade individual. Assim, os dados do aplicativo não permitem
comparações ou ajustes estatísticos por idade. A faixa etária do público continua
sendo definida institucionalmente no protocolo da oficina, e não inferida a
partir dos eventos coletados. A coluna histórica `student_age` permanece nullable
no schema apenas para compatibilidade com registros anteriores.

**Leitura correta:** “142 participantes com eventos de pesquisa registrados” é tecnicamente mais preciso que “142 estudantes impactados”. O aplicativo mede participação na coleta; “impacto” exige um desfecho e um desenho capazes de demonstrar mudança atribuível ao programa.

### 4.2 Processo de aprendizagem e colaboração

| Indicador | Definição operacional | Campo/fonte | Escala | Forma recomendada de reportar |
|---|---|---|---|---|
| Esforço mental percebido | quanto o participante precisou pensar naquele momento | `mental_effort` | ordinal 1–4 | distribuição por categoria, mediana e modelo ordinal |
| Mudança de esforço | diferença de distribuição entre minutos 20 e 40 | `mental_effort` + `interval_mark` | transição ordinal | probabilidades estimadas e razão de chances |
| Situação de progresso | avanço independente, dúvida, tentativa sem avanço ou ajuda imediata | `progress_state` | categórica ordenável com cautela | proporções e transições |
| Bloqueio | participante relata tentativa sem avanço ou necessidade de ajuda | derivado de `progress_state` | binária | prevalência por checkpoint |
| Pedido de ajuda | participante seleciona “precisamos de ajuda agora” | `help_requested` e evento homônimo | binária | pedidos por 100 participantes/checkpoints |
| Colaboração percebida | oportunidade de ambos darem ideias e participarem | `collaboration`, no minuto 40 | ordinal 1–4 | distribuição e associação com resultado |
| Papel exercido | programação/computador ou montagem/teste | `participant_role` e `self_reported_role` | nominal | comparação por papel e momento |
| Adesão à troca | sessão contém `role_swapped` quando esperado | linha do tempo | binária | proporção de sessões aderentes |
| Latência de resposta | tempo entre apresentação e término da resposta | `response_latency_ms` | contínua | mediana e percentis; carga operacional |

O item de esforço se inspira em uma tradição de escalas subjetivas breves. Medidas de esforço podem oferecer informação que não aparece no desempenho isoladamente (PAAS et al., 2003), e medidas repetidas reduzem a dependência de uma avaliação retrospectiva única (VAN GOG et al., 2012). Contudo, a escala clássica de Paas utiliza nove categorias; o PulseLab adota quatro alternativas e linguagem infantil. Estudos recentes reforçam que esforço investido e dificuldade percebida não são necessariamente o mesmo construto e que adaptações exigem investigação de validade (SCHUESSLER; FISCHER; WALPUSKI, 2024). Assim, o termo recomendado para o dado atual é **“esforço mental percebido em escala ordinal experimental de quatro categorias”**, e não “carga cognitiva objetiva”.

### 4.3 Resultado imediato e experiência final

| Indicador | Definição operacional | Campo/fonte | Situação na versão auditada | Interpretação permitida |
|---|---|---|---|---|
| Compreensão percebida | capacidade declarada de explicar o funcionamento do robô | `post_understanding` | coletado pelo agente | percepção de compreensão, não prova de domínio |
| Afetos | até duas escolhas entre seis categorias | `post_affects` | coletado pelo agente | perfil afetivo descritivo |
| Intenção de retorno | não a sim, em quatro categorias | `post_return_intent` | coletado pelo agente | aceitabilidade/intenção, não “satisfação” geral |
| Desempenho da missão | rubrica 0–3 preenchida pelo instrutor | `mission_performance` | schema e simulador; integração pendente no agente Windows | resultado observável da dupla |
| Intervenções do instrutor | 0, 1, 2 ou 3 ou mais | `instructor_interventions` | schema e simulador; integração pendente no agente Windows | intensidade aproximada de mediação |
| Dificuldade principal | montagem, lógica, sensor, técnica, colaboração etc. | `primary_issue` | schema e simulador; integração pendente no agente Windows | categorização do gargalo |
| Conhecimento específico | escore de itens alinhados à atividade | `knowledge_score`, `knowledge_answers` | previsto no schema; itens ausentes | ganho imediato quando houver pré e pós equivalentes |

As respostas finais não devem ser fundidas em um único “índice de sucesso”. Uma criança pode relatar esforço alto, sentir frustração e ainda concluir a missão; outra pode desejar retornar sem demonstrar o conceito trabalhado. Manter as dimensões separadas preserva informação e evita interpretar afeto, esforço e aprendizagem como sinônimos.

### 4.4 Qualidade, completude e viabilidade

| Indicador | Fórmula ou regra | Fonte | Decisão apoiada |
|---|---|---|---|
| Taxa de conclusão | sessões com `session_completed` / sessões iniciadas | linha do tempo | viabilidade do fluxo |
| Taxa de sessões completas | `quality_status = complete` / sessões encerradas | view `research_session_quality` | seleção e auditoria |
| Taxa de revisão | `needs_review` / sessões encerradas | view de qualidade | carga de revisão manual |
| Resposta válida por fase | `response_status = completed` / oportunidades previstas | `research_events` | quantidade analiticamente utilizável |
| Recusa | `declined` / oportunidades previstas | `research_events` | aceitabilidade e proteção da autonomia |
| Timeout | `timeout` / oportunidades previstas | `research_events` | usabilidade e perda técnica |
| Atraso do checkpoint | diferença entre horário previsto e apresentação | `checkpoint_lateness_ms` | comparabilidade temporal |
| Cobertura de screenshot | checkpoints com captura / checkpoints esperados | view e linha do tempo | disponibilidade da evidência opcional |
| Continuidade do agente | heartbeats observados em relação à duração | eventos `heartbeat` | falhas e interrupções |
| Latência de sincronização | `received_at - occurred_at` | ambas as tabelas | períodos offline, com cautela sobre relógio local |
| Consistência do protocolo | sessões por `protocol_version` e `config_hash` | ambas as tabelas | comparabilidade e reprodutibilidade |
| Alertas de qualidade | contagem por código | eventos `quality_issue` | revisão de atraso, janela, captura e troca |

**Nota técnica:** a view atual conta linhas pré, checkpoint e pós independentemente de `response_status`. Logo, uma sessão pode conter todos os registros esperados e, ao mesmo tempo, possuir recusas ou timeouts. Para a análise, “registro presente” e “resposta válida” devem ser apresentados separadamente. Recusas são um resultado ético legítimo e não devem ser recodificadas como baixa qualidade do participante.

### 4.5 Evidências auxiliares que não devem virar rótulos automáticos

| Evidência | O que realmente registra | O que não prova |
|---|---|---|
| Categoria do aplicativo | `spike`, `other` ou `unknown` no instante observado | distração ou engajamento |
| Inatividade | segundos desde a última entrada de mouse/teclado | tempo improdutivo; a dupla pode estar montando ou discutindo |
| Tamanho do arquivo | tamanho do projeto encontrado no momento | qualidade do código, progresso conceitual ou aprendizagem |
| Screenshot privado | estado visual da janela do SPIKE no checkpoint | pensamento, emoção ou autoria individual |
| Heartbeat | agente em execução e contexto técnico mínimo | participação pedagógica contínua |

Esses registros podem gerar hipóteses, selecionar casos para revisão ou contextualizar respostas. Não devem produzir diagnósticos automáticos como “aluno distraído”, “carga ideal” ou “bloqueio cognitivo detectado” sem validação contra observação estruturada e critérios previamente definidos.

---

## 5. Perguntas de pesquisa e hipóteses testáveis

### 5.1 Objetivo geral

Analisar as relações entre esforço mental percebido, colaboração em dupla, necessidade de ajuda e desempenho imediato de estudantes durante oficinas pontuais de robótica educacional com LEGO SPIKE, avaliando simultaneamente a viabilidade e a qualidade da coleta distribuída.

### 5.2 Objetivos específicos

1. Descrever o esforço mental percebido nos minutos 20 e 40.
2. Estimar a frequência e a transição de situações de dúvida, bloqueio e ajuda.
3. Comparar respostas conforme papel exercido e momento da oficina.
4. Investigar a associação entre colaboração percebida, mediação do instrutor e desempenho da missão.
5. Estimar ganho imediato em conhecimentos específicos, após a implantação dos itens pré/pós.
6. Quantificar completude, atrasos, perdas, recusas e recuperação de eventos em diferentes escolas.

### 5.3 Hipóteses

| Hipótese | Variáveis | Teste principal | Condição para ser testada |
|---|---|---|---|
| H1: a distribuição do esforço difere entre 20 e 40 minutos | esforço, momento, papel | modelo ordinal de efeitos mistos | já coletável |
| H2: bloqueio/pedido de ajuda se associa a mais mediação | progresso/ajuda e intervenções | regressão ordinal ou logística multinível | integrar rubrica no agente |
| H3: maior colaboração se associa a melhor desempenho | colaboração e missão 0–3 | modelo ordinal ajustado | integrar e validar rubrica |
| H4: o desempenho em conhecimento é superior no pós | itens pré/pós | modelo pareado/misto por item ou escore | definir e implementar itens |
| H5: a coleta distribuída alcança os critérios de viabilidade | completude, atraso, timeout e sincronização | estimativas com IC 95% | já avaliável no piloto |

O resultado de uma hipótese deve ser apresentado por estimativa, intervalo de confiança e incerteza, não apenas por valor de *p*. “Não significativo” não significa “sem efeito”, sobretudo em pilotos pequenos.

---

## 6. Plano de análise quantitativa

### 6.1 Preparação

1. congelar uma versão do protocolo e registrar seu hash;
2. definir previamente desfecho primário, exclusões e covariáveis;
3. criar dicionário de dados com rótulos e codificação;
4. separar dados de teste, homologação e pesquisa;
5. deduplicar por `event_id`;
6. identificar sessão, dupla, participante, momento, papel e atividade;
7. distinguir `completed`, `declined` e `timeout`;
8. manter um relatório de fluxo da amostra desde sessões iniciadas até registros analisados.

### 6.2 Análise descritiva

- contagens de escolas, oficinas, sessões, duplas e participantes;
- distribuição por experiência prévia e autoeficácia;
- frequências e intervalos de confiança de esforço, progresso, ajuda, colaboração e resultados finais;
- matrizes de transição entre minutos 20 e 40;
- medianas e intervalos interquartis para latência e atraso;
- completude e perdas por escola, versão, máquina e oficina;
- comparação descritiva entre sessões completas e sessões com revisão.

Escalas de quatro categorias não devem ser apresentadas somente por média. A média “2,4/4” pressupõe distâncias iguais entre categorias e, isoladamente, esconde a distribuição. Barras de proporção, medianas, probabilidades previstas e modelos ordinais são mais defensáveis.

### 6.3 Modelos recomendados

**H1 — esforço mental:** modelo ordinal de ligação cumulativa, com momento, papel, experiência prévia e atividade como efeitos fixos. Incluir interceptos aleatórios para participante e dupla; oficina/escola entram como níveis adicionais quando o número de agrupamentos permitir.

**H2 — ajuda e mediação:** modelar a probabilidade ou intensidade de intervenção em função do estado de progresso/pedido de ajuda, ajustando por momento, experiência e atividade. Como a intervenção é medida no nível da dupla, não duplicar a rubrica nas duas linhas pós.

**H3 — colaboração e desempenho:** modelar a rubrica 0–3 como desfecho ordinal. A associação deve ser ajustada por experiência prévia, atividade e intervenções. O resultado será associação, não efeito causal.

**H4 — conhecimento:** construir itens equivalentes alinhados aos objetivos de cada `activity_id`. Avaliar respostas por item e escore, emparelhar pré/pós e relatar mudança com intervalo de confiança. Sem comparador, usar “ganho imediato observado”, e não “impacto causado”.

**H5 — viabilidade:** estimar proporções de sessões concluídas, completas e revisadas, além de atraso e sincronização. Comparar escolas ou instalações somente quando houver volume suficiente e quando a interpretação não permitir reidentificação ou ranqueamento injustificado.

### 6.4 Dados ausentes e sensibilidade

- relatar recusas e timeouts separadamente;
- não imputar automaticamente respostas recusadas;
- verificar se a ausência se concentra por escola, momento ou papel;
- repetir análises principais em conjunto completo e em cenários de sensibilidade, quando justificável;
- não excluir uma sessão apenas porque contém alerta técnico; aplicar regras definidas antes de observar o resultado.

### 6.5 Tamanho amostral

O relatório não propõe um número arbitrário de participantes. O cálculo deve partir:

1. do desfecho primário;
2. do menor efeito considerado educacionalmente relevante;
3. do número esperado de escolas, oficinas e duplas;
4. da correlação entre respostas da mesma criança e da mesma dupla;
5. da taxa de perda observada no piloto.

Para modelos multinível ordinais, a estratégia mais transparente é estimar parâmetros preliminares no piloto e realizar cálculo por simulação. O piloto deve ser dimensionado inicialmente para testar compreensão, operação e variabilidade, e não para “provar” eficácia.

---

## 7. Critérios propostos para declarar o piloto viável

Os valores abaixo são **metas operacionais provisórias**, a serem aprovadas e registradas antes do piloto; não são resultados atuais:

| Critério | Meta proposta |
|---|---:|
| Sessões com desfecho registrado | ≥ 95% das sessões iniciadas |
| Sessões tecnicamente completas ou justificadamente revisadas | ≥ 90% |
| Checkpoints apresentados dentro do limite configurado | ≥ 95% |
| Registros sem duplicidade de `event_id` | 100% |
| Sessões com versão/hash esperados | 100% |
| Separação documentada entre recusas e falhas técnicas | 100% |
| Screenshots públicos | 0 |
| Payloads com nome de participante ou título bruto de janela | 0 |

O limite técnico existente para atraso é 120 segundos. Além da proporção abaixo desse limite, recomenda-se reportar mediana e percentil 95. Uma meta não atingida não invalida automaticamente o projeto: identifica o componente que precisa ser corrigido antes da coleta confirmatória.

---

## 8. Evidências de validade necessárias

O aplicativo padroniza a coleta, mas padronização não equivale a validade. A denominação recomendada durante o piloto é:

> **Instrumento experimental em processo de validação para avaliação da experiência e do processo em oficinas de robótica educacional.**

O argumento de validade deve reunir:

1. **conteúdo:** especialistas verificam se os itens representam esforço, progresso, colaboração e os objetivos pedagógicos;
2. **processo de resposta:** entrevistas cognitivas avaliam como crianças entendem perguntas e alternativas;
3. **estrutura interna:** distribuição, efeito teto/piso e relações entre itens/momentos;
4. **relações com outras variáveis:** comparar ajuda relatada com intervenção registrada, observação estruturada e desempenho;
5. **consequências do uso:** verificar se alertas apoiam o instrutor sem estigmatizar ou retirar apoio;
6. **confiabilidade da rubrica:** dois avaliadores pontuam uma amostra de missões e têm sua concordância estimada;
7. **invariância e equidade:** investigar compreensão e funcionamento das medidas entre faixas etárias, escolas e contextos, se a amostra permitir.

O screenshot pode apoiar uma rubrica qualitativa, desde que existam categorias, avaliadores treinados, concordância e proteção de dados. Ele não “valida a resposta da criança” de modo automático.

---

## 9. Auditoria do estado atual da implementação

Esta seção impede que a apresentação confunda intenção, protótipo e dado real.

| Componente | Estado verificado | Consequência para o relatório |
|---|---|---|
| Pré: experiência e autoeficácia | implementado no agente e no schema | disponível para piloto |
| Checkpoints 20/40 | implementados com tempo absoluto | disponível para piloto |
| Esforço, progresso, ajuda e colaboração | implementados | disponíveis como medidas experimentais |
| Pós: compreensão, afetos e retorno | implementado | disponível para piloto |
| Linha do tempo, heartbeat e alertas | implementados | viabilidade e auditoria disponíveis |
| Cache e reenvio idempotente | implementados; requer homologação real | permite testar resiliência |
| Rubrica do instrutor | tela existe no agente; simulador persiste; fluxo Windows não a chama atualmente | desempenho, intervenções e dificuldade ainda não devem ser anunciados como coletados pelo agente real |
| Conhecimento pré/pós | campos existem; `knowledge_questions` está vazio | aprendizagem imediata ainda não é mensurada |
| View de qualidade | implementada no schema | exige backend/consulta autorizada |
| Dashboard central | interface com números simulados e exportações fictícias | não apresentar seus valores como resultados |
| Autenticação individual de dispositivos | pendente | piloto supervisionado, não coleta acadêmica definitiva de alta garantia |
| Validação psicométrica | pendente | não chamar a escala de validada |

Evidências técnicas internas:

- [Protocolo de pesquisa v1](https://github.com/vfamim/pulselab/blob/main/docs/protocolo-pesquisa-v1.md)
- [Arquitetura de evidências 1.4](https://github.com/vfamim/pulselab/blob/main/docs/arquitetura-evidencias-v1.4.md)
- [Schema Supabase](https://github.com/vfamim/pulselab/blob/main/schema/supabase-schema.sql)
- [Configuração do instrumento](https://github.com/vfamim/pulselab/blob/main/config/config.json)
- [Agente Windows](https://github.com/vfamim/pulselab/blob/main/agent/pulselab-agent.ps1)
- [Simulador web](https://github.com/vfamim/pulselab/blob/main/web/agent-simulator/app/page.jsx)
- [Dashboard demonstrativo](https://github.com/vfamim/pulselab/blob/main/dashboard/index.html)

---

## 10. Por que o aplicativo agrega valor à pesquisa

### 10.1 Padronização

Perguntas, alternativas, marcos temporais e códigos são aplicados da mesma forma. Isso reduz variação introduzida por formulários diferentes, horários improvisados e registros livres.

### 10.2 Observação do processo

Dois checkpoints permitem analisar transições dentro da oficina. O projeto deixa de registrar apenas “concluiu/não concluiu” e passa a estudar como esforço, dúvida, ajuda, colaboração e papel evoluem.

### 10.3 Escala multicêntrica

O mesmo protocolo pode operar em escolas e polos diferentes. A ampliação territorial aumenta a capacidade de investigar variação entre contextos, embora não transforme uma amostra de conveniência em amostra representativa.

### 10.4 Rastreabilidade e reprodutibilidade

Cada evento contém versão do protocolo, configuração e hash. Uma análise pode identificar exatamente quais sessões usaram o mesmo instrumento, reduzindo o risco de misturar versões.

### 10.5 Qualidade mensurável da própria pesquisa

O PulseLab mede não apenas a oficina, mas a coleta: completude, atraso, recusa, timeout, falha de captura e sincronização. Assim, a banca pode avaliar a qualidade dos dados com números em vez de assumir que “o formulário funcionou”.

### 10.6 Ação pedagógica

O pedido de ajuda gera alerta ao instrutor. O sistema fecha o ciclo entre dado e ação sem usar a pesquisa como motivo para negar suporte. Futuramente, padrões agregados poderão orientar revisão de atividade, formação de instrutores e alocação de apoio.

### 10.7 Minimização e proteção

O agente não solicita nomes, cria pseudônimos por sessão, envia categoria de aplicativo em vez de título bruto da janela e usa bucket privado para capturas. Essas escolhas apoiam minimização, mas não substituem governança, consentimento/assentimento, retenção, controle de acesso e avaliação ética.

---

## 11. Limites das conclusões

### O PulseLab pode sustentar

- descrição de participantes, sessões e contextos;
- trajetória intrassessão de esforço e progresso;
- frequência de bloqueio, ajuda, colaboração e afetos;
- comparação exploratória por papel, momento, atividade e contexto;
- associação entre medidas, quando os desfechos estiverem implementados;
- viabilidade, completude e qualidade da coleta distribuída.

### O PulseLab ainda não sustenta sozinho

- causalidade da oficina sobre aprendizagem;
- retenção de longo prazo;
- diagnóstico individual de carga cognitiva;
- eliminação do efeito Hawthorne;
- inferência de distração a partir de inatividade ou aplicativo;
- equivalência entre tamanho de arquivo e progresso;
- aprendizagem medida apenas por compreensão percebida;
- resultados numéricos exibidos no dashboard demonstrativo;
- autenticidade forte da origem de todos os eventos.

O argumento mais convincente não é afirmar que o sistema mede tudo; é demonstrar que ele conhece o limite de cada medida e registra as condições necessárias para interpretações auditáveis.

---

## 12. Perguntas prováveis da banca e respostas recomendadas

### “O aplicativo mede aprendizagem?”

**Resposta:** “Hoje ele mede de forma estruturada o processo e a experiência imediata: esforço percebido, progresso, ajuda, colaboração e compreensão declarada. Aprendizagem imediata passará a ser medida quando os itens pré/pós de conhecimento alinhados a cada atividade e a rubrica de desempenho forem integrados e validados. Não confundimos percepção com domínio.”

### “Como confiar no autorrelato de crianças?”

**Resposta:** “Não tratamos uma resposta isolada como verdade absoluta. Usamos linguagem curta, respostas individuais, medidas no momento da atividade e um plano de validação com especialistas, entrevistas cognitivas, piloto e comparação com rubrica e intervenção. A validade é um argumento acumulado, não uma propriedade automática do software.”

### “Uma escala de quatro pontos pode ser chamada de carga cognitiva?”

**Resposta:** “A formulação atual mede esforço mental percebido em uma escala ordinal experimental. Ela dialoga com a literatura de esforço mental, mas é uma adaptação infantil de quatro categorias e precisa ser validada. Por isso evitamos o rótulo de carga cognitiva objetiva.”

### “Screenshot e inatividade provam bloqueio?”

**Resposta:** “Não. São evidências contextuais. A construção física ou a discussão podem gerar inatividade legítima, e uma imagem não revela estado mental. Esses sinais servem para auditoria, amostragem de casos e triangulação com critérios explícitos.”

### “Como vocês evitam pseudorreplicação?”

**Resposta:** “Os dados mantêm IDs de participante, dupla, sessão, oficina e escola. A análise usa modelos compatíveis com medidas repetidas e agrupamento, em vez de tratar cada linha como observação independente.”

### “Podem dizer que a oficina causou melhora?”

**Resposta:** “Não com o desenho atual. Podemos relatar mudança imediata e associações. Uma afirmação causal exigiria um comparador, randomização, implantação escalonada ou outra estratégia de identificação previamente planejada.”

### “O painel já mostra resultados reais?”

**Resposta:** “Não. O painel atual é um protótipo visual claramente marcado como simulado. Os resultados científicos somente serão apresentados após conexão autenticada, congelamento do protocolo, coleta aprovada e análise reprodutível.”

### “A coleta offline garante zero perda?”

**Resposta:** “Ela reduz o risco por meio de fila local e reenvio idempotente. ‘Zero perda’ é uma hipótese técnica a verificar em homologação, não uma garantia a priori. O próprio sistema permite quantificar sucesso, atraso e falhas de sincronização.”

### “Como fica a ética com crianças?”

**Resposta:** “A participação científica depende dos procedimentos institucionais aplicáveis, consentimento do responsável e assentimento da criança. Recusa não altera a participação pedagógica. Usamos pseudonimização e minimização, mas ainda precisamos formalizar controlador, acesso, retenção, descarte e necessidade das imagens.”

---

## 13. Roteiro de defesa oral em dois minutos

> “Nosso problema não é falta de atividades de robótica; é falta de evidência padronizada sobre o que acontece dentro delas. Uma missão concluída mostra o produto, mas não mostra quando a dupla teve dificuldade, quanto apoio recebeu, se ambos participaram nem com que qualidade os dados foram coletados.
>
> O PulseLab transforma cada oficina em uma sessão reconstruível. Antes da atividade, registra contexto, experiência e autoeficácia. Nos minutos 20 e 40, cada participante responde individualmente sobre esforço e progresso; no minuto 40, também sobre colaboração. O sistema registra papel, troca de funções, pedido de ajuda, tempo e qualidade da coleta. No encerramento, mede compreensão percebida, afetos e intenção de retorno. Cada evento leva uma versão e um hash do protocolo, o que permite comparar apenas sessões metodologicamente equivalentes.
>
> Nosso diferencial não é prometer que telemetria lê a mente da criança. É separar medidas diretas, indicadores derivados e evidências auxiliares, respeitando seus limites. Com modelos ordinais e multinível, poderemos estimar mudanças dentro da sessão e associações entre colaboração, ajuda e desempenho, sem fingir independência entre crianças da mesma dupla.
>
> Hoje o sistema já sustenta um piloto de processo e viabilidade. Para medir aprendizagem imediata, vamos integrar a rubrica do instrutor e itens pré/pós específicos; para uma coleta definitiva, vamos validar o instrumento, implantar autenticação de dispositivos e submeter o protocolo à avaliação ética aplicável. Assim, o PulseLab não substitui o método científico: ele torna o método executável, escalável e auditável.” 

---

## 14. Plano de maturação antes da coleta definitiva

### Prioridade crítica

1. integrar `Show-WpfInstructorRubric` ao fluxo real do agente Windows;
2. persistir a rubrica uma única vez por dupla ou garantir deduplicação analítica;
3. definir objetivos pedagógicos e itens pré/pós por `activity_id`;
4. revisar a view para distinguir presença de registro e resposta concluída;
5. conectar um painel real por backend autenticado, mantendo os dados simulados fora da apresentação de resultados;
6. provisionar identidade e credencial revogável por instalação;
7. definir controlador, perfis de acesso, retenção, descarte e necessidade dos screenshots.

### Validação

8. realizar revisão de conteúdo por especialistas;
9. conduzir entrevistas cognitivas com a faixa etária atendida;
10. executar piloto de usabilidade e viabilidade;
11. testar concordância da rubrica entre avaliadores;
12. estimar parâmetros para cálculo amostral;
13. congelar instrumento e plano de análise;
14. registrar previamente hipóteses, exclusões e desfecho primário.

### Coleta e comunicação

15. separar ambientes e bases de teste e pesquisa;
16. produzir relatório de fluxo e qualidade antes dos resultados educacionais;
17. apresentar estimativas, intervalos de confiança e limitações;
18. divulgar somente resultados agregados que não permitam reidentificação.

---

## 15. Considerações éticas e proteção de dados

A LGPD determina que o tratamento de dados de crianças e adolescentes observe seu melhor interesse e estabelece requisitos específicos de transparência e consentimento no tratamento de dados de crianças (BRASIL, 2018, art. 14). A Resolução CNS nº 510/2016 dispõe sobre pesquisas em Ciências Humanas e Sociais com dados diretamente obtidos de participantes e enfatiza dignidade, autonomia, privacidade e prevenção de danos (BRASIL, 2016).

Para o projeto, isso implica:

- avaliação pelo sistema CEP/Conep quando aplicável, sob responsabilidade institucional;
- consentimento do responsável e assentimento em linguagem adequada;
- liberdade de recusa sem prejuízo à oficina;
- justificativa de necessidade e proporcionalidade para screenshots;
- informação clara sobre dados, finalidade, acesso e retenção;
- proteção do cache local e do bucket;
- plano de resposta a incidentes;
- agregação de resultados para impedir reidentificação de criança, turma ou escola;
- vedação de decisões punitivas ou rótulos individuais baseados em sinais experimentais.

A pseudonimização reduz risco, mas os eventos contextuais e as imagens continuam potencialmente vinculáveis a uma sessão. Portanto, não devem ser descritos como anônimos sem uma avaliação específica de reidentificação.

---

## 16. Conclusão

O PulseLab agrega valor à pesquisa em três níveis. No nível **metodológico**, padroniza instrumentos, momentos e unidades de análise. No nível **analítico**, produz variáveis capazes de descrever trajetórias intrassessão e testar associações com modelos adequados. No nível **operacional**, quantifica a qualidade da própria coleta por completude, atraso, recusa, timeout, alertas e rastreabilidade de versão.

Sua contribuição científica mais defensável é funcionar como **infraestrutura de observação distribuída e controle de qualidade para oficinas de robótica educacional**. O sistema não transforma qualquer registro em evidência de aprendizagem; ao contrário, cria condições para distinguir perfil, processo, resultado e qualidade. Essa arquitetura permite que conclusões futuras sejam apoiadas por números cujo significado, origem e limite interpretativo estejam documentados.

No estado atual, o PulseLab está pronto para um piloto supervisionado de viabilidade e processo. A integração da rubrica, o desenvolvimento do pré/pós de conhecimento, a validação do instrumento, a governança ética e o painel real são condições para avançar de protótipo de pesquisa a sistema de mensuração acadêmica consolidado.

---

## Referências

AMERICAN EDUCATIONAL RESEARCH ASSOCIATION; AMERICAN PSYCHOLOGICAL ASSOCIATION; NATIONAL COUNCIL ON MEASUREMENT IN EDUCATION. **Standards for educational and psychological testing**. Washington, DC: AERA, 2014. Disponível em: <https://www.testingstandards.net/uploads/7/6/6/4/76643089/standards_2014edition.pdf>. Acesso em: 29 jul. 2026.

BENITTI, Fabiane Barreto Vavassori. Exploring the educational potential of robotics in schools: a systematic review. **Computers & Education**, v. 58, n. 3, p. 978–988, 2012. DOI: <https://doi.org/10.1016/j.compedu.2011.10.006>.

BLIKSTEIN, Paulo. Multimodal learning analytics. In: **Proceedings of the Third International Conference on Learning Analytics and Knowledge — LAK ’13**. New York: ACM, 2013. p. 102–106. DOI: <https://doi.org/10.1145/2460296.2460316>.

BRASIL. Conselho Nacional de Saúde. **Resolução nº 510, de 7 de abril de 2016**. Dispõe sobre as normas aplicáveis a pesquisas em Ciências Humanas e Sociais. Disponível em: <https://www.gov.br/conselho-nacional-de-saude/pt-br/atos-normativos/resolucoes/2016/resolucao-no-510.pdf>. Acesso em: 29 jul. 2026.

BRASIL. **Lei nº 13.709, de 14 de agosto de 2018**. Lei Geral de Proteção de Dados Pessoais. Disponível em: <https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm>. Acesso em: 29 jul. 2026.

PAAS, Fred et al. Cognitive load measurement as a means to advance cognitive load theory. **Educational Psychologist**, v. 38, n. 1, p. 63–71, 2003. DOI: <https://doi.org/10.1207/S15326985EP3801_8>.

SCHUESSLER, Katrin; FISCHER, Vanessa; WALPUSKI, Maik. Investigating construct validity of cognitive load measurement using single-item subjective rating scales. **Instructional Science**, v. 53, p. 71–97, 2025. Publicação on-line em 2024. DOI: <https://doi.org/10.1007/s11251-024-09692-6>.

SOCIETY FOR LEARNING ANALYTICS RESEARCH. **What is learning analytics?** 2025. Disponível em: <https://www.solaresearch.org/about/what-is-learning-analytics/>. Acesso em: 29 jul. 2026.

VAN GOG, Tamara et al. Timing and frequency of mental effort measurement: evidence in favour of repeated measures. **Applied Cognitive Psychology**, v. 26, n. 6, p. 833–839, 2012. DOI: <https://doi.org/10.1002/acp.2883>.

VON ELM, Erik et al. The Strengthening the Reporting of Observational Studies in Epidemiology (STROBE) statement: guidelines for reporting observational studies. **The Lancet**, v. 370, n. 9596, p. 1453–1457, 2007. DOI: <https://doi.org/10.1016/S0140-6736(07)61602-X>.
