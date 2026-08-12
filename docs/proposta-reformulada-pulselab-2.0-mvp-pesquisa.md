# PulseLab 2.0 — proposta reformulada e MVP de pesquisa

> **Data da revisão:** 7 de agosto de 2026  
> **Escopo:** auditoria do repositório, comparação com soluções e propostas similares e reformulação do produto e do programa de pesquisa.  
> **Status:** documento de decisão. Não substitui protocolo aprovado, parecer ético, plano estatístico, política de privacidade ou aconselhamento jurídico.  
> **Versão examinada:** agente e contratos 1.4.0, incluindo as alterações locais existentes na data da revisão.

## 1. Síntese executiva

O PulseLab tem uma contribuição promissora, mas ela precisa ser formulada com precisão:

> **O PulseLab é uma infraestrutura independente de plataforma para coleta distribuída, pseudonimizada, versionada e auditável de evidências sobre processo, implementação e resultados imediatos em oficinas de robótica educacional.**

O produto não deve ser apresentado, neste estágio, como medidor automático de aprendizagem, carga cognitiva, engajamento ou colaboração. Sua primeira entrega científica defensável é provar que oficinas realizadas em várias sedes podem produzir dados completos, comparáveis, autênticos e de baixo ônus sem um pesquisador presencial permanente.

A revisão indica quatro mudanças de direção:

1. **De coletor para infraestrutura de pesquisa:** protocolo, atividade, instrumento, rubrica, versão, qualidade e proveniência precisam ser parte do produto.
2. **De SPIKE para arquitetura independente de fornecedor:** o parque SPIKE pode sustentar o piloto, mas o portfólio foi retirado de venda em 30 de junho de 2026; o núcleo deve aceitar adaptadores para outras plataformas.
3. **De telemetria ampla para mensuração orientada por construto:** só coletar um dado quando houver pergunta científica, interpretação prevista e regra de descarte.
4. **De demonstração para MVP verificável:** autenticação real, resultado objetivo, qualidade de dados, separação entre ambientes e protocolo ético são requisitos de entrada, não melhorias futuras.

O MVP recomendado não tenta responder se a oficina “funciona”. Ele responde primeiro:

> **É viável executar um protocolo multicêntrico de coleta em oficinas de robótica, com completude, fidelidade, segurança, baixo ônus e qualidade suficientes para um estudo substantivo posterior?**

Aprendizagem imediata, colaboração e mediação entram como desfechos exploratórios no piloto e se tornam confirmatórios somente após validação dos instrumentos e cálculo amostral.

---

## 2. Diagnóstico do estado atual

### 2.1 Pontos fortes que devem ser preservados

- modelo append-only com `event_id` idempotente;
- linha do tempo de sessão separada das respostas individuais;
- tempo absoluto baseado em relógio monotônico;
- `protocol_version`, `config_version` e `config_hash` em cada evento;
- pseudônimos por sessão em vez de nomes de estudantes;
- distinção entre resposta concluída, recusada e expirada;
- classificação local de aplicativo, sem envio do título bruto da janela;
- bucket privado e ausência de leitura anônima declarada;
- tentativa de manter evento e screenshot como uma unidade no reenvio offline;
- simulador navegável e exportação de sessão para inspeção;
- testes de contrato que cobrem versões, esquema, telemetria minimizada e empacotamento.

Na revisão, os **20 testes Python** e o teste de contratos JavaScript passaram. O build Vite também foi produzido com sucesso em diretório temporário.

### 2.2 Lacunas críticas encontradas

| Prioridade | Evidência no projeto | Risco | Decisão recomendada |
|---|---|---|---|
| P0 | A tela de contexto é ignorada quando tudo está pré-configurado, mas `authorization_verified = true` é registrado incondicionalmente | uma sessão pode declarar autorização sem confirmação atual do instrutor | confirmação de autorização deve ocorrer em toda sessão e produzir evento próprio, sem atalho |
| P0 | `anon` pode inserir qualquer linha válida em `research_events`, `research_session_events` e no bucket | fabricação de dados, spam, custo e perda de autenticidade científica | retirar escrita direta do cliente; usar gateway autenticado, credencial revogável por instalação e validação no servidor |
| P0 | o portal do instrutor aceita qualquer e-mail, não autentica e apenas usa `console.log` e um modal de sucesso | falsa impressão de login e persistência | rotular como simulação ou implementar Auth, associação de instrutor e inserção real antes do uso |
| P0 | a função de troca de papel existe, mas não é chamada; a lista de participantes recria papéis fixos | exposição aos papéis é registrada incorretamente | implementar transições de papel e registrar papel efetivo por participante e etapa |
| P0 | a rubrica existe no agente Windows, mas não é chamada nem persistida | não há desfecho objetivo principal | persistir um único resultado de grupo, separado de ajuda e respostas individuais |
| P0 | `knowledge_questions` está vazio e o agente não aplica pré/pós de conhecimento | não há medida direta de aprendizagem | criar itens alinhados a objetivos por `activity_version` e validar antes de alegações de aprendizagem |
| P0 | o app permite grupos de 1, 3 e 4, mas `New-ResearchEvent` aceita apenas os papéis `computer` e `assembly` | execução falha fora de duplas | restringir o MVP a duplas ou completar e testar suporte de 1–4; o modelo de dados pode permanecer extensível |
| P0 | screenshots estão ativos por padrão e o upload anônimo aceita qualquer caminho no bucket | risco desproporcional de privacidade e abuso | desligar por padrão; reintroduzir apenas em subestudo aprovado, com URL assinada, MIME, tamanho, caminho e retenção controlados |
| P1 | a view de qualidade assume dois participantes e conta linhas mesmo quando `declined` ou `timeout` | sessão pode parecer completa sem respostas analíticas válidas | calcular oportunidades esperadas por `participant_count` e separar presença, validade e recusa |
| P1 | a rubrica atual mistura execução da missão e quantidade de ajuda | circularidade em análises entre ajuda e desempenho | pontuar correção/robustez da missão separadamente da intensidade de suporte |
| P1 | há pedido de ajuda, mas não reconhecimento, início ou resolução | não é possível medir atendimento ou efeito da mediação | incluir `help_acknowledged`, `help_started` e `help_resolved` |
| P1 | configuração remota aponta para `main`, que é mutável | o hash prova conteúdo, mas não garante que a versão foi aprovada ou pode ser recuperada | publicar manifestos imutáveis e assinados por versão e arquivar a configuração usada |
| P1 | fila local é JSON/JPG em claro, sem mutex e reescrita por inteiro | exposição local, corrupção em queda e conflito entre instâncias | usar outbox transacional, proteção DPAPI e bloqueio de instância |
| P1 | tabelas aceitam contexto repetido sem vínculo a uma sessão registrada | eventos da mesma sessão podem contradizer escola, atividade ou protocolo | validar o envelope no gateway e manter entidade de sessão canônica |
| P1 | ambientes de demonstração e pesquisa não estão claramente separados | dados fictícios podem contaminar análise e comunicação | projetos/bases/chaves distintos e `environment` obrigatório no envelope |
| P2 | o README solicita `npm run check`, mas o script não existe | verificação documentada falha antes do build | corrigir o contrato de scripts e adicionar lint/typecheck real ou remover a instrução |

### 2.3 Observações adicionais de segurança do banco

- `authorized_instructors` permite que qualquer usuário autenticado leia todas as linhas ativas; a autorização deve verificar a própria identidade ou uma função administrativa, não expor a lista completa.
- `instructor_evaluations` aceita inserção anônima e recebe `instructor_email` do cliente, permitindo falsificação.
- avaliações do instrutor são ligadas apenas por códigos textuais de oficina e turma, sem `session_id`/`group_id` obrigatório.
- a política de Storage limita apenas o bucket; não limita instalação, caminho, extensão, MIME ou tamanho.
- o esquema usa RLS e privilégios mínimos de leitura, o que é positivo, mas `WITH CHECK (true)` garante formato, não origem, autorização nem coerência científica.
- as chaves legadas `anon`/`service_role` estão anunciadas pelo Supabase para depreciação até o fim de 2026. Chaves publicáveis novas não são JWT e não devem ser enviadas como `Authorization: Bearer`, como o agente faz hoje.

---

## 3. Risco estratégico: o produto não pode depender do SPIKE

A LEGO Education encerrou as vendas do SPIKE Prime e Essential em **30 de junho de 2026**. O aplicativo SPIKE continuará recebendo correções e suporte a sistemas operacionais até **30 de junho de 2031**, mas não receberá novas funcionalidades depois da retirada do produto. A nova linha Computer Science & AI usa o Coding Canvas, trabalha com faixas K–2, 3–5 e 6–8 e propõe grupos de quatro; os projetos continuam locais e sem login do estudante.

Isso não invalida o piloto com equipamentos já instalados. A implicação é arquitetural:

```text
Núcleo PulseLab
├── protocolo, instrumentos e versões
├── sessões, participantes e grupos
├── eventos, qualidade e resultados
├── autenticação, sincronização e auditoria
└── adaptadores de plataforma
    ├── SPIKE App (legado suportado até 2031)
    ├── LEGO Coding Canvas
    ├── Scratch/Blockly
    ├── MakeCode ou outra plataforma
    └── atividade sem computador
```

`spike_window_detected` deve virar algo como `platform_adapter_status`; `.llsp` e `.spk` devem ser propriedades do adaptador, não do modelo científico central.

---

## 4. O que soluções similares ensinam

| Solução/proposta | Como funciona | Aprendizado para o PulseLab | O que não copiar diretamente |
|---|---|---|---|
| **PELARS** | combina logs da IDE, sensores, imagens/vídeo, autorregistro e codificação humana em tarefas abertas de computação física | alinhar modalidades ao desenho da atividade; cruzar processo, produto e observação; envolver professor no desenho do painel | infraestrutura sensorial intrusiva e cara; os primeiros estudos não justificam transferência automática para crianças ou escala multicêntrica |
| **Dr. Scratch** | recebe projeto/URL do Scratch e produz dimensões de pensamento computacional; possui análise em lote | extrair características semânticas do artefato e permitir processamento em lote | transformar escore de estrutura de código em “aprendizagem” sem validade para a atividade e a população |
| **Code.org Teacher Dashboard** | mostra progresso, tempo, última atividade, código, avaliações e itens para revisão | painel orientado à decisão; visão por turma e etapa; exportação; separar trabalho concluído de trabalho correto | usar tempo ou bolha concluída como prova de domínio; a própria Code.org alerta que várias tarefas não são autoavaliadas por correção |
| **Raspberry Pi Code Classroom** | integra editor em blocos/Python/web, turmas, submissão para revisão e feedback docente | incorporar fluxo explícito “pronto para revisão → avaliado → feedback”, em vez de apenas coletar dados | exigir contas nominais de estudantes no MVP de pesquisa |
| **LEGO Education** | fornece planos, checklist observacional, autoavaliação e avaliação por pares; a nova linha associa tarefa física e Coding Canvas | alinhar rubrica à lição e permitir observação docente curta; preparar grupos de quatro no modelo futuro | acoplar o protocolo científico ao ciclo de vida de um único fornecedor |
| **Caliper/xAPI** | padroniza envelopes e vocabulários de eventos que podem ser enviados a um repositório de aprendizagem | manter evento canônico versionado e oferecer exportação compatível | implementar toda a especificação antes de estabilizar o vocabulário de domínio |
| **SnapClass** (proposta emergente/preprint) | combina gestão de sala em programação por blocos, ajuda levantada e sinais como ociosidade | reforça a utilidade de fila de ajuda e painel de orquestração | inferir engajamento ou dificuldade de ociosidade/IA antes de validação independente |

O diferencial defensável do PulseLab é a combinação de **baixo custo, operação offline, pesquisa multicêntrica, pseudonimização, reconstrução temporal e controle de qualidade**. Ele não precisa competir com ambientes de programação; deve instrumentar atividades realizadas neles.

---

## 5. Proposta reformulada

### 5.1 Nome conceitual

> **PulseLab 2.0 — infraestrutura de pesquisa e qualidade para aprendizagem prática em robótica e computação criativa.**

### 5.2 Problema

Oficinas distribuídas geram produtos e experiências relevantes, mas deixam pouca evidência comparável sobre:

- quem foi alcançado;
- qual atividade e versão foram aplicadas;
- com que fidelidade a oficina ocorreu;
- como esforço, progresso, papel e ajuda mudaram;
- o que o grupo conseguiu executar;
- o que cada participante conseguiu explicar ou responder;
- qual foi a completude, autenticidade e qualidade dos dados;
- quais mudanças pedagógicas decorreram dos achados.

### 5.3 Público e decisões apoiadas

| Usuário | Decisão apoiada |
|---|---|
| instrutor local | quem pediu ajuda, qual etapa falta e como encerrar corretamente |
| coordenação pedagógica | qual atividade ou etapa concentra dificuldade e qual formação precisa ser revista |
| pesquisador | quais sessões são utilizáveis, quais precisam de auditoria e quais hipóteses podem ser testadas |
| gestor do programa | alcance, adoção, custo operacional, fidelidade e sustentabilidade por sede |
| comunidade escolar | devolutiva agregada, compreensível e não estigmatizante |

### 5.4 Limites de alegação

O produto pode informar **processo, implementação, resultado imediato e qualidade da evidência**. Não deve gerar diagnóstico individual, ranking de criança/instrutor/escola, decisão punitiva, rótulo de engajamento ou inferência emocional automática.

---

## 6. Teoria de mudança e programa de pesquisa

```text
Recursos e desenho
atividade versionada + formação + kits + protocolo
        │
        ▼
Implementação
alcance + adesão + fidelidade + suporte + qualidade técnica
        │
        ▼
Processos de aprendizagem
tentativas + depuração + esforço + papéis + colaboração + ajuda
        │
        ▼
Produtos imediatos
missão + artefato + explicação individual + conhecimento pós
        │
        ▼
Resultados posteriores
retenção + autoeficácia + retorno + continuidade em computação
```

Essa cadeia impede que um sinal técnico seja confundido com resultado educacional. `idle_seconds`, por exemplo, pertence à evidência contextual; ele não salta diretamente para “desengajamento”.

### 6.1 Estudos previstos

1. **Estudo 0 — desenvolvimento e validade de conteúdo/processo de resposta**  
   Co-desenho com instrutores, especialistas e crianças; entrevistas cognitivas; refinamento da atividade, dos itens e da rubrica.

2. **Estudo 1 — piloto multicêntrico de viabilidade**  
   Desfecho primário: completude e fidelidade da coleta. Secundários: ônus, aceitabilidade, falhas, pedidos de ajuda e distribuição das medidas.

3. **Estudo 2 — validade e processo**  
   Comparação entre PulseLab e observação estruturada em amostra; concordância da rubrica; relações entre esforço, progresso, ajuda, artefato e resultado.

4. **Estudo 3 — efetividade**  
   Somente após validação: desenho por conglomerados, lista de espera, implementação escalonada ou quase-experimento, conforme viabilidade institucional.

5. **Estudo 4 — retenção, equidade e sustentabilidade**  
   Seguimento, manutenção da oferta, adoção por sedes, custo e distribuição dos resultados entre grupos definidos previamente.

O MVP entrega o Estudo 1 e prepara o Estudo 2. Ele não promete o Estudo 3.

### 6.2 Pergunta primária do MVP

> Em oficinas pontuais realizadas em mais de uma sede, o PulseLab consegue obter o conjunto mínimo de dados válidos por sessão, com fidelidade temporal, origem autenticada, baixo ônus para o instrutor e proteção adequada dos participantes?

### 6.3 Hipóteses exploratórias reformuladas

- **H1:** a distribuição do esforço mental percebido varia por etapa, papel efetivamente exercido e experiência prévia.
- **H2:** menor latência entre pedido e início de ajuda se associa a maior probabilidade de transição de bloqueio para progresso no checkpoint seguinte.
- **H3:** exposição equilibrada aos papéis e participação percebida se associam ao desempenho do grupo e à explicação individual, sem incluir ajuda dentro do escore de desempenho.
- **H4:** o desempenho pós-oficina em itens alinhados à atividade é superior ao pré, com incerteza e agrupamento explicitados; no estudo observacional, isso é mudança imediata, não efeito causal.
- **H5 futura:** após introduzir comparador adequado, estudantes expostos à oficina apresentam resultado superior ao grupo comparador no desfecho primário pré-especificado.

---

## 7. Escopo do MVP

### 7.1 Dentro do MVP

- duplas como única composição operacional validada;
- uma atividade principal, com versão e objetivos de aprendizagem congelados;
- confirmação de autorização por sessão e assentimento individual;
- pré-teste curto, dois checkpoints ligados a etapas e pós-teste curto;
- troca de papéis registrada e papel efetivamente exercido;
- pedido, reconhecimento, início e resolução de ajuda;
- rubrica de grupo registrada uma vez;
- explicação individual curta ou item de aplicação;
- ingestão autenticada por instalação;
- outbox offline transacional e protegida;
- painel real de qualidade, operação e auditoria;
- exportação de dados de pesquisa com dicionário e versões;
- ambiente de homologação separado do ambiente de pesquisa;
- trilha de auditoria e política de retenção implementada.

### 7.2 Fora do MVP

- câmera, áudio, biometria, eye tracking ou sensores corporais;
- screenshots por padrão;
- IA para inferir emoção, carga, engajamento ou risco;
- ranking de estudantes, instrutores, turmas ou escolas;
- suporte operacional a trios e quartetos antes de validação própria;
- identificação longitudinal de estudantes;
- causalidade ou promessa de aumento de aprendizagem;
- processamento integral de Caliper/xAPI; apenas envelope compatível e exportador.

### 7.3 Fluxo mínimo

1. Coordenador publica `activity_version` e `protocol_version` imutáveis.
2. Instalação autenticada baixa apenas versões autorizadas para sua sede.
3. Instrutor inicia sessão, confirma autorização atual e recebe código de sessão.
4. Participantes recebem assentimento individual; recusa encerra somente a coleta.
5. Pré-teste mede perfil mínimo e conhecimento alinhado.
6. A atividade inicia e registra etapas, não apenas relógio corrido.
7. Checkpoint A registra papel, esforço e progresso; troca de papel é confirmada.
8. Pedido de ajuda entra em fila local e recebe tempos de atendimento.
9. Checkpoint B repete processo e inclui participação percebida.
10. Instrutor registra a rubrica de grupo, sem incluir quantidade de ajuda no escore.
11. Cada participante responde pós-teste e explicação individual.
12. O sistema exibe o que foi sincronizado e o que continua pendente.
13. O painel classifica a sessão por completude, validade e desvios.

### 7.4 Checkpoints por etapa, com fallback temporal

Os minutos 20 e 40 não representam a mesma situação em oficinas diferentes. Recomenda-se:

- gatilho principal por etapa, como `construcao_concluida` e `teste_integrado`;
- janela temporal esperada por atividade;
- fallback absoluto quando o instrutor não marcar a etapa;
- registro de `stage_expected`, `stage_reported`, `scheduled_at`, `prompted_at`, `responded_at` e atraso.

Isso preserva comparação pedagógica e permite analisar desvio de duração.

---

## 8. Métricas recomendadas

### 8.1 Núcleo de implementação e escala

Uma adaptação de RE-AIM organiza o programa sem transformar o MVP em estudo clínico:

| Dimensão | Métricas |
|---|---|
| Alcance | oficinas/participantes elegíveis, convidados, autorizados e com coleta; perfil de não participação apenas no nível aprovado |
| Resultado imediato | conhecimento, missão, explicação individual, experiência e efeitos indesejados |
| Adoção | sedes e instrutores elegíveis que iniciam e repetem o protocolo |
| Implementação | fidelidade às etapas, versão correta, troca de papéis, ajuda atendida, tempo e custo operacional |
| Manutenção | sedes ainda ativas, retenção de instrutores, custo por sessão e uso após apoio intensivo |

### 8.2 Catálogo mínimo do MVP

| Construto | Medida direta | Unidade | Observação |
|---|---|---|---|
| experiência prévia | item ordinal 1–4 | participante | variável de ajuste, não desfecho |
| conhecimento da atividade | 3–5 itens pré/pós | participante/item | alinhamento explícito ao objetivo; forma paralela quando necessário |
| autoeficácia | 1–3 itens curtos | participante | se for central, preferir mais de um item validado/adaptado |
| esforço mental percebido | item ordinal por etapa | participante/checkpoint | não chamar de carga cognitiva objetiva |
| progresso | quatro estados + recusa | participante/checkpoint | transições são mais informativas que média |
| papel exercido | autorrelato + transição de sistema | participante/etapa | comparar concordância entre fontes |
| participação percebida | item ordinal no segundo checkpoint | participante | não equivale a colaboração observada |
| ajuda | pedido, reconhecimento, início, fim e tipo | grupo/episódio | permite latência e dose de suporte |
| missão | rubrica analítica | grupo | uma linha por grupo; avaliador identificado por ID |
| explicação | rubrica curta 0–3 | participante | ancora contribuição individual |
| artefato | hash e características locais | grupo/versão | sem arquivo bruto no MVP, salvo justificativa |
| aceitabilidade | retorno + instrumento curto do instrutor | participante/instrutor | separar aceitabilidade de aprendizagem |
| qualidade | oportunidades, válidos, recusas, atrasos, erros e sync | sessão/site | desfecho primário do piloto |

### 8.3 Rubrica de grupo proposta

Quatro dimensões independentes, cada uma de 0 a 3:

1. **Cumprimento da missão:** comportamento observável correto.
2. **Robustez:** repete a missão ou responde a variação prevista.
3. **Conceito-alvo:** o artefato contém a lógica/sensor/estrutura esperada.
4. **Teste e depuração:** há evidência de testar, identificar e corrigir problema.

Registrar separadamente:

- número e tipo de intervenções;
- grau de orientação fornecida;
- problema técnico externo;
- principal dificuldade;
- tempo até a conclusão.

Assim, ajuda pode explicar o resultado sem fazer parte dele.

### 8.4 Indicadores de qualidade e fórmulas

```text
taxa_conclusao = sessões com session_completed / sessões iniciadas

completude_core = oportunidades core com response_status=completed
                  / oportunidades core esperadas

taxa_recusa = oportunidades declined / oportunidades apresentadas

taxa_timeout = oportunidades timeout / oportunidades apresentadas

fidelidade_etapas = etapas obrigatórias registradas na ordem válida
                    / etapas obrigatórias esperadas

latencia_ajuda = help_started_at - help_requested_at

latencia_sync = received_at - occurred_at

recuperacao_offline = eventos enfileirados confirmados no servidor
                      / eventos enfileirados
```

“Registro presente”, “resposta válida”, “recusa” e “falha técnica” devem aparecer separadamente.

### 8.5 Critérios de progressão do piloto

Os limites abaixo são metas operacionais a revisar com equipe e piloto, não verdades universais:

| Indicador | Verde | Amarelo | Vermelho |
|---|---:|---:|---:|
| sessões com conjunto core válido | ≥ 85% | 70–84% | < 70% |
| eventos confirmados em até 24 h | ≥ 95% | 85–94% | < 85% |
| sessões com versão/proveniência coerentes | ≥ 98% | 90–97% | < 90% |
| rubricas de grupo concluídas | ≥ 90% | 75–89% | < 75% |
| checkpoints com atraso acima da janela | ≤ 10% | 11–25% | > 25% |
| falha fatal da aplicação | ≤ 2% | 3–5% | > 5% |
| incidente material de privacidade | 0 | — | ≥ 1: pausar e revisar |

A decisão de avançar deve considerar os critérios em conjunto e incluir instrutores, coordenação, pesquisa e governança.

---

## 9. Arquitetura técnica recomendada

```text
Agente/Runner local
├── UI do protocolo
├── adaptador da plataforma
├── máquina de estados da sessão
├── outbox local transacional + DPAPI
└── cliente de ingestão
          │ lote assinado, idempotente, com sequência
          ▼
Gateway de ingestão
├── autentica instalação
├── valida versão, site, esquema e tamanho
├── limita frequência
├── rejeita contexto incoerente
└── grava com credencial somente no servidor
          ▼
Postgres/Supabase
├── private: eventos brutos, instrumentos, sessões e auditoria
├── analytics: dados derivados versionados
└── api: views mínimas para painéis autenticados
          ▼
Painel
├── operação e ajuda
├── qualidade e sincronização
├── auditoria por exceção/amostra
└── pesquisa agregada e exportação
```

### 9.1 Autenticação de dispositivo

- cadastro prévio de instalação, sede e escola;
- segredo de bootstrap usado uma única vez;
- credencial de dispositivo armazenada com DPAPI;
- troca por token de curta duração;
- escopo limitado à instalação e às versões autorizadas;
- rotação e revogação;
- número sequencial por instalação/lote para detectar lacunas e replay;
- nenhum `service_role` ou chave secreta no cliente.

No Supabase, uma Edge Function ou serviço equivalente pode atuar como gateway. Tabelas de pesquisa não precisam ficar graváveis diretamente pela Data API pública.

### 9.2 Portal do instrutor

- autenticação real por magic link, OTP ou OIDC institucional;
- o servidor deriva `instructor_id`; não aceita e-mail autorrelatado como identidade;
- associação explícita entre instrutor, sede e sessão;
- política RLS baseada em `auth.uid()` e associação, não apenas `TO authenticated`;
- avaliação com `session_id`/`group_id` e unicidade por avaliador/versão;
- modo demonstração em projeto e URL separados.

### 9.3 Modelo de dados mínimo

- `protocol_versions`
- `instrument_versions` e `instrument_items`
- `activity_versions` e `learning_objectives`
- `sites`, `installations` e `instructor_assignments`
- `sessions` e `session_participants`
- `session_events`
- `item_responses`
- `help_episodes`
- `group_outcomes` e `individual_explanations`
- `artifact_features`
- `ingestion_batches`
- `quality_flags`
- `withdrawal_requests`

O evento continua append-only. Estado atual, qualidade e conjuntos analíticos são projeções reproduzíveis, não edições do registro bruto.

### 9.4 Envelope canônico

Campos comuns:

- `event_id`, `schema_version`, `event_type`;
- `session_id`, `group_id`, `participant_id` opcional;
- `site_id`, `installation_id` e sequência;
- `protocol_version`, `instrument_version`, `activity_version`;
- `occurred_at`, `elapsed_ms`, `received_at`;
- `actor_type`, `object_type`, `stage_id`;
- `payload` validado e minimizado;
- `environment = test | pilot | research`.

Manter mapeamento de verbos e objetos para Caliper/xAPI possibilita integração futura sem acoplar o núcleo a uma especificação externa.

### 9.5 Artefato em vez de screenshot

Preferir extração local de características alinhadas à atividade:

- blocos/conceitos esperados presentes;
- quantidade de versões/salvamentos;
- alterações entre estados;
- execução/teste registrado;
- hash do arquivo final;
- resultado da missão.

Enviar características, não conteúdo bruto. Se o formato não permitir extração confiável, usar rubrica humana e manter screenshot fora do core.

---

## 10. Plano de validade e análise

### 10.1 Evidências de validade

1. **Conteúdo:** matriz objetivo → tarefa → item → rubrica, revisada por especialistas.
2. **Processo de resposta:** entrevistas cognitivas por faixa etária e observação de uso.
3. **Estrutura interna:** distribuição, piso/teto e funcionamento de itens; IRT/Rasch somente com tamanho adequado.
4. **Relações externas:** comparação com observação estruturada, rubrica e instrumento de CT apropriado à idade.
5. **Confiabilidade:** dupla avaliação de uma amostra; kappa ponderado/ICC com intervalo de confiança.
6. **Equidade:** compreensão, dados ausentes e possível funcionamento diferencial por idade, série, sede e acessibilidade.
7. **Consequências:** falsos alertas, interrupção, estigma, aumento de trabalho e uso indevido do painel.

Instrumentos como TechCheck/cCTt podem servir como âncora externa em faixas etárias compatíveis. Não devem ser recortados ou traduzidos informalmente sem autorização e nova evidência de validade.

### 10.2 Plano estatístico inicial

- relatório de fluxo com todos os denominadores;
- descritivos e intervalos de confiança por sessão, oficina e sede;
- modelos ordinais multinível para esforço, progresso e rubricas;
- modelos item a item ou escore validado para conhecimento pré/pós;
- efeitos aleatórios ou erros robustos para participante, grupo, oficina e sede, conforme amostra;
- análise de transição para `progress_state`;
- tempo até ajuda atendida apenas quando relógios e eventos estiverem validados;
- análise principal e sensibilidades por qualidade, versão e atraso;
- `declined`, `timeout`, `technical_failure` e ausência estrutural separados;
- hipóteses confirmatórias, exclusões, transformação de escores e multiplicidade pré-especificadas;
- cálculo amostral do estudo substantivo por simulação após obter variâncias e ICCs do piloto.

Não calcular a amostra definitiva a partir de um efeito inflado do piloto. O tamanho do piloto deve ser guiado pela precisão desejada para as taxas de viabilidade e pelos critérios de progressão.

### 10.3 Validação em campo

- entrevistas cognitivas iterativas em faixas etárias relevantes;
- primeira aplicação acompanhada em uma sede;
- amostra de sessões com observador e aplicativo em paralelo;
- dupla pontuação independente de missões selecionadas;
- teste online, offline, queda durante upload, relógio incorreto, app ausente e duplicidade;
- segunda sede operando sem pesquisador local, com auditoria remota;
- congelamento da versão antes do piloto multicêntrico.

---

## 11. Ética, privacidade e governança

O protocolo deve considerar conjuntamente:

- LGPD, em especial melhor interesse, transparência, necessidade e direitos de crianças e adolescentes;
- Enunciado CD/ANPD nº 1/2023;
- Lei nº 14.874/2024 sobre pesquisa com seres humanos;
- Decreto nº 12.651/2025, que regulamenta o Sistema Nacional de Ética em Pesquisa com Seres Humanos;
- Resolução CNS nº 510/2016, que permanece indicada para Ciências Humanas e Sociais;
- regras e orientações da instituição proponente e do CEP competente.

### 11.1 Condições antes de qualquer coleta científica

- instituição proponente, pesquisador responsável, controlador, operadores e encarregado/canal definidos;
- aprovação ética prévia e versão aprovada arquivada;
- TCLE/processo de consentimento e assentimento compatível com idade e contexto;
- confirmação verificável sem colocar identidade parental no banco analítico;
- finalidade e base legal documentadas para cada classe de dado;
- relatório de impacto/avaliação de risco quando indicado;
- matriz de acesso e registro de auditoria;
- prazos de retenção e descarte por modalidade;
- procedimento de incidente, retirada e comunicação;
- contrato e avaliação do fornecedor de nuvem;
- plano de devolutiva para participantes e comunidades.

### 11.2 Retirada e direitos

O fluxo atual permite recusar uma tela, mas não oferece retirada da pesquisa depois do início. O MVP deve:

- permitir interromper a coleta em qualquer checkpoint;
- diferenciar “não responder este item” de “retirar participação”;
- fornecer código de retirada que não revele identidade ao pesquisador;
- definir o que acontece com dados já coletados conforme protocolo e obrigação aplicável;
- impedir nova captura após retirada;
- preservar a participação pedagógica e o atendimento.

### 11.3 Minimização por modalidade

| Modalidade | MVP | Regra |
|---|---|---|
| respostas estruturadas | sim | somente itens aprovados e versão congelada |
| eventos técnicos | sim | categorias e qualidade; nunca título bruto ou texto livre |
| artefato derivado | sim | extrair localmente e enviar características/hash |
| screenshot | não por padrão | subestudo, necessidade demonstrada, acesso restrito e retenção curta aprovada |
| áudio/vídeo | não | somente protocolo próprio, infraestrutura e justificativa específica |
| IA/predição | não | exige finalidade, validação, avaliação de viés, transparência e supervisão humana |

Revisões de MMLA encontram evidência ainda fraca de impacto no mundo real e tratamento insuficiente de ética. Mais modalidades não significam automaticamente melhor ciência.

### 11.4 Publicação e devolutiva

- suprimir células pequenas conforme política pré-definida;
- não publicar ranking de sedes ou instrutores;
- separar painel operacional restrito de relatório público agregado;
- produzir resumo acessível para estudantes e famílias;
- registrar qual mudança curricular ou de formação foi feita a partir dos achados;
- publicar dicionário, protocolo, código de análise e histórico de versões quando possível, nunca dados reidentificáveis.

---

## 12. Backlog de implementação

### Gate 0 — protocolo e governança

- [ ] escolher uma atividade e definir objetivos observáveis;
- [ ] decidir idade/série e manter duplas no MVP;
- [ ] construir matriz de mensuração e rubrica;
- [ ] atualizar documentos para Lei 14.874/2024 e Decreto 12.651/2025;
- [ ] aprovar consentimento, assentimento, retirada e plano de dados;
- [ ] desligar screenshots por padrão;
- [ ] separar demonstração, homologação e pesquisa.

### Sprint 1 — integridade funcional

- [ ] exigir confirmação de autorização em toda sessão;
- [ ] remover opções de grupo não suportadas ou completar suporte;
- [ ] corrigir troca e papel por etapa;
- [ ] chamar e persistir rubrica uma vez por grupo;
- [ ] implementar itens pré/pós por `activity_version`;
- [ ] implementar ajuda reconhecida/iniciada/resolvida;
- [ ] implementar retirada durante a sessão.

### Sprint 2 — segurança e ingestão

- [ ] migrar de chaves legadas e remover escrita anônima direta;
- [ ] cadastrar e autenticar instalações;
- [ ] criar gateway com validação, rate limit, sequência e idempotência;
- [ ] restringir Data API e Storage;
- [ ] implementar outbox transacional, proteção local e mutex;
- [ ] separar schemas privados e API mínima;

### Sprint 3 — qualidade e painel

- [ ] criar entidades canônicas de sessão, grupo e resultados;
- [ ] corrigir oportunidades esperadas por participante e status;
- [ ] painel de ajuda e sincronização;
- [ ] painel de completude, desvios e versões;
- [ ] auditoria por exceção e amostra aleatória;
- [ ] exportação com dicionário, snapshot e proveniência.

### Sprint 4 — validação

- [ ] testes unitários, contrato, integração e end-to-end no Supabase de homologação;
- [ ] teste real em Windows 10/11 e PowerShell 5.1;
- [ ] caos offline, duplicidade, queda e relógio incorreto;
- [ ] revisão de acessibilidade e entrevistas cognitivas;
- [ ] concordância da rubrica e comparação com observação;
- [ ] ensaio em segunda sede;
- [ ] congelar release do piloto.

---

## 13. Cronograma orientado por gates

Prazos de aprovação ética e pactuação institucional não devem ser comprimidos artificialmente. Após Gate 0:

| Período indicativo | Entrega |
|---|---|
| semanas 1–2 | contrato de atividade, instrumentos, eventos e dados |
| semanas 3–5 | fluxo do agente, papéis, rubrica, ajuda e retirada |
| semanas 6–8 | autenticação, gateway, outbox e banco |
| semanas 9–10 | painel e exportação |
| semanas 11–12 | integração, segurança e homologação Windows/offline |
| 4–6 semanas seguintes | piloto acompanhado e segunda sede |
| após análise | decisão verde/amarela/vermelha e release seguinte |

O MVP termina com um **relatório de viabilidade**, não apenas com software publicado.

---

## 14. Critérios de aceite do MVP

O MVP está concluído quando:

- nenhuma sessão declara autorização sem ação atual verificável;
- a origem de cada lote pode ser atribuída a uma instalação autorizada e revogada;
- não existe inserção anônima direta nas tabelas de pesquisa;
- duplas percorrem o fluxo completo com papel correto antes/depois da troca;
- rubrica, ajuda e conhecimento são persistidos nas unidades certas;
- recusa, retirada, timeout e falha são distinguíveis;
- sessão completa é calculada pelo protocolo e pelo número de participantes;
- modo offline sobrevive a queda sem corromper ou expor a fila;
- painel mostra apenas dados reais do ambiente selecionado e identifica proveniência;
- cada métrica exibida possui definição, denominador, versão e limite interpretativo;
- os testes incluem banco real de homologação e Windows, não apenas inspeção estática;
- a equipe produz relatório de fluxo, qualidade, incidentes e decisão de progressão;
- screenshots, IA, áudio e vídeo não fazem parte do core.

---

## 15. Contribuição acadêmica reformulada

A contribuição mais forte não é “usar screenshots e telemetria para medir aprendizagem”. É:

> **Desenvolver e avaliar uma infraestrutura de pesquisa de baixo custo que torna observáveis, comparáveis e auditáveis oficinas práticas distribuídas, preservando a separação entre perfil, processo, implementação, resultado e qualidade da evidência.**

Possíveis produtos acadêmicos:

1. artigo de desenvolvimento e viabilidade do protocolo distribuído;
2. artigo de validade e confiabilidade do instrumento/rubrica;
3. estudo de processo sobre ajuda, papéis e transições de progresso;
4. estudo de efetividade com comparador após maturação;
5. conjunto aberto de contratos, dicionário, simulador e dados sintéticos;
6. guia de governança e operação multicêntrica para contextos escolares de baixa conectividade.

Essa formulação amplia o projeto além do LEGO SPIKE, aumenta sua vida útil e cria uma agenda científica cumulativa em vez de depender de uma única coleta ou de uma alegação excessiva.

---

## 16. Referências e fontes consultadas

### Produtos, propostas e padrões

- LEGO Education. [SPIKE Portfolio Retirement — What Users Need to Know](https://education.lego.com/en-us/spike-update-2026/).
- LEGO Group. [LEGO Education Announces Hands-on Computer Science & AI Learning Solution](https://www.lego.com/en-us/aboutus/news/2026/january/lego-education-cs-ai).
- LEGO Education. [SPIKE Prime FAQs — avaliação, faixa e organização](https://education.lego.com/en-us/product-resources/spike-prime/troubleshooting/spike-prime-faqs/).
- Cukurova et al. [Using Multimodal Learning Analytics to Identify Aspects of Collaborative Problem Solving in Project-Based Learning](https://discovery.ucl.ac.uk/id/eprint/1561454/1/37-3.pdf).
- Dr. Scratch. [Batch Mode](https://www.drscratch.org/learn/Modes/BatchMode/).
- Code.org. [Viewing student progress](https://support.code.org/hc/en-us/articles/115000693231-Viewing-student-progress).
- Raspberry Pi Foundation. [Code Classroom](https://classroom.raspberrypi.org/en).
- 1EdTech. [Caliper Analytics 1.2 Specification](https://www.imsglobal.org/spec/caliper/v1p2/).
- ADL. [Experience API specification](https://www.adlnet.gov/assets/uploads/xAPI_v1.0.1-2013-10-01.pdf).
- Zhong et al. [Investigating the Period of Switching Roles in Pair Programming in a Primary School](https://eric.ed.gov/?id=EJ1147017).

### Mensuração, implementação e ética de analytics

- RE-AIM. [What is RE-AIM?](https://re-aim.org/learn/what-is-re-aim/).
- Eldridge et al. [CONSORT extension to randomised pilot and feasibility trials](https://www.bmj.com/content/355/bmj.i5239).
- Relkin, Johnson e Bers. [A Normative Analysis of the TechCheck Computational Thinking Assessment](https://eric.ed.gov/?id=EJ1389718).
- El-Hamamsy et al. [The competent Computational Thinking test](https://arxiv.org/abs/2203.05980).
- Frontiers in Education. [Rubric development and validation for assessing educational robotics skills](https://www.frontiersin.org/journals/education/articles/10.3389/feduc.2024.1496242/full).
- Alwahaby et al. [The evidence of impact and ethical considerations of Multimodal Learning Analytics](https://discovery.ucl.ac.uk/id/eprint/10143076/).
- Martinez-Maldonado et al. [Lessons Learnt from a Multimodal Learning Analytics Deployment In-the-wild](https://arxiv.org/abs/2303.09099).
- UNICEF, UNESCO e Global Privacy Assembly. [Data Governance for EdTech](https://www.unicef.org/innocenti/reports/data-governance-edtech).

### Marco brasileiro

- Brasil. [Lei nº 13.709/2018 — LGPD](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm).
- ANPD. [Enunciado CD/ANPD nº 1/2023 sobre crianças e adolescentes](https://www.gov.br/anpd/pt-br/assuntos/noticias/anpd-divulga-enunciado-sobre-o-tratamento-de-dados-pessoais-de-criancas-e-adolescentes).
- Brasil. [Lei nº 14.874/2024 — pesquisa com seres humanos](https://www.planalto.gov.br/ccivil_03/_ato2023-2026/2024/lei/l14874.htm).
- Brasil. [Decreto nº 12.651/2025](https://planalto.gov.br/ccivil_03/_ato2023-2026/2025/decreto/d12651.htm).
- Conselho Nacional de Saúde. [Resolução nº 510/2016](https://www.gov.br/conselho-nacional-de-saude/pt-br/camaras-tecnicas-e-comissoes/conep/legislacao/resolucoes/resolucao-no-510-de-07-de-abril-de-2016).

### Supabase e segurança

- Supabase. [Securing your API](https://supabase.com/docs/guides/api/securing-your-api).
- Supabase. [Securing Edge Functions](https://supabase.com/docs/guides/functions/auth).
- Supabase. [Understanding API keys](https://supabase.com/docs/guides/getting-started/api-keys).
- Supabase. [Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security).
- Supabase. [2026 Data API breaking changes](https://supabase.com/changelog?tags=data+apis).

### Documentos internos relacionados

- [Protocolo de pesquisa v1](protocolo-pesquisa-v1.md)
- [Relatório acadêmico de métricas 1.4](relatorio-academico-metricas-pulselab-v1.4.md)
- [Arquitetura de evidências 1.4](arquitetura-evidencias-v1.4.md)
- [Parecer e roadmap anterior](parecer-roadmap-observacao-distribuida.md)
- [Schema Supabase](../schema/supabase-schema.sql)
- [Agente Windows](../agent/pulselab-agent.ps1)
- [Simulador web](../web/agent-simulator/app/page.jsx)

