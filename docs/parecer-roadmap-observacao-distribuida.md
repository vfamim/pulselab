# PulseLab — Parecer e Roadmap de Observação Distribuída

> Status: documento de referência para discussão e desenvolvimento futuro.
> Data do registro: 26 de julho de 2026.
> Natureza: diagnóstico crítico, visão de produto e backlog metodológico.
> Este documento não substitui protocolo de pesquisa aprovado, parecer do CEP, plano estatístico, política de privacidade ou especificação técnica detalhada.

## 1. Contexto e necessidade central

O projeto possui sedes em cidades diferentes, incluindo Juazeiro-BA, Paulo Afonso-BA, Sobradinho-BA e outras unidades. A coordenação da pesquisa está concentrada em Juazeiro, sem disponibilidade de pesquisadores para acompanhar presencialmente todas as oficinas.

Essa limitação provoca:

- perda de dados;
- perda de oportunidades de pesquisa;
- aplicação desigual dos instrumentos;
- dificuldade para acompanhar o processo vivido pelas duplas;
- dependência da presença física de uma segunda pessoa;
- baixa capacidade de auditar a execução do protocolo nas diferentes sedes.

O pilar do PulseLab é, portanto:

> Permitir que um pesquisador central acompanhe, audite e analise oficinas realizadas em múltiplas sedes sem a necessidade de um pesquisador local permanente em cada unidade.

O propósito não deve ser descrito inicialmente como a substituição de toda a inteligência de um pesquisador. A proposta tecnicamente e academicamente defensável é substituir grande parte da presença logística, da aplicação mecânica de instrumentos e do transporte manual de dados por uma infraestrutura de observação distribuída.

## 2. Veredito sobre o estado atual

O PulseLab possui uma boa ideia central e uma base promissora de coleta, mas ainda deve ser tratado como um agente experimental para piloto.

No estado atual, ele:

- automatiza perguntas;
- registra respostas individuais pseudonimizadas;
- registra contexto institucional;
- coleta telemetria técnica pontual;
- captura a região da tela correspondente à janela do SPIKE;
- mantém uma fila offline;
- permite pedidos de ajuda;
- solicita uma avaliação final do instrutor.

Ele ainda não constitui:

- uma metodologia acadêmica concluída;
- uma escala científica validada;
- um sistema de observação contínua;
- uma avaliação objetiva de aprendizagem;
- uma substituição integral da observação humana;
- um painel remoto funcional de acompanhamento das sedes;
- uma infraestrutura com autenticidade e integridade científica plenamente asseguradas.

### 2.1 Posicionamento recomendado

Enquanto o processo de validação não estiver concluído, utilizar:

> Instrumento experimental em processo de validação para coleta distribuída de evidências sobre oficinas de robótica educacional.

Após validação, o posicionamento pretendido poderá ser:

> Protocolo de coleta multicêntrica automatizada, com observação distribuída e auditoria remota, sem pesquisador local permanente.

### 2.2 Alegações que devem ser evitadas no estado atual

- “O sistema elimina a necessidade de observadores.”
- “O sistema elimina o efeito Hawthorne.”
- “O screenshot valida o estado mental da criança.”
- “O sistema mede aprendizagem.”
- “O sistema monitora continuamente o engajamento.”
- “A telemetria comprova colaboração.”
- “Tamanho do arquivo representa evolução do conhecimento.”
- “A coleta offline garante perda zero.”
- “RLS e pseudonimização tornam o projeto automaticamente compatível com a LGPD.”

## 3. O que significa oferecer “olhos” em todas as sedes

Um sistema de observação remota precisa responder, com evidências:

1. A oficina começou e terminou?
2. O protocolo correto foi utilizado?
3. Qual atividade foi realizada?
4. Em qual etapa a dupla estava em cada momento?
5. O SPIKE estava sendo utilizado?
6. Houve atividade, inatividade, bloqueio ou desvio técnico?
7. Quem exercia cada papel?
8. Houve troca de papéis?
9. A dupla pediu ajuda?
10. O pedido foi atendido e em quanto tempo?
11. A missão foi concluída?
12. Qual foi a qualidade objetiva do resultado?
13. Os dados esperados foram coletados?
14. Houve falha, atraso, recusa ou desvio de protocolo?
15. Quais sessões precisam ser revisadas pelo pesquisador central?

O estado atual oferece flashes aos 20 e 40 minutos. A visão futura deve produzir uma linha do tempo estruturada da sessão.

## 4. Arquitetura conceitual futura

```text
Juazeiro ───────┐
Paulo Afonso ───┤
Sobradinho ─────┼──► Evidências padronizadas ──► Pesquisador central
Outras sedes ───┘              │
                               ├── painel de qualidade
                               ├── alertas e exceções
                               ├── sessões incompletas
                               ├── evidências para auditoria
                               └── base para análise acadêmica
```

O sistema futuro deve ser composto por cinco capacidades:

1. coleta local automatizada;
2. identificação segura de sede, dispositivo, oficina e atividade;
3. sincronização resiliente;
4. controle central de qualidade;
5. revisão amostral ou por exceção pelo pesquisador.

## 5. Papel das pessoas no modelo futuro

### 5.1 Pesquisador central

- define perguntas, hipóteses e protocolo;
- aprova versões do instrumento;
- acompanha qualidade e completude;
- revisa sessões sinalizadas;
- audita amostras aleatórias;
- conduz validação e análise estatística;
- controla acesso, retenção e uso científico dos dados.

### 5.2 Instrutor local

O instrutor não precisa receber formação completa de pesquisador. Sua atuação pode ser operacional:

- iniciar a sessão;
- confirmar a verificação das autorizações aplicáveis;
- selecionar a oficina ou atividade;
- garantir que cada criança responda individualmente;
- atender pedidos de ajuda;
- executar o teste final padronizado;
- encerrar a sessão;
- comunicar falhas excepcionais.

### 5.3 Aplicação

- aplica instrumentos no momento previsto;
- coleta evidências técnicas;
- registra eventos e tempos;
- detecta ausência de dados;
- orienta o instrutor;
- sincroniza os eventos;
- produz alertas;
- permite auditoria central.

## 6. Modalidades de evidência

### 6.1 Autorrelatos

Continuar coletando separadamente:

- experiência prévia;
- autoeficácia;
- esforço mental percebido;
- situação de progresso ou bloqueio;
- colaboração percebida;
- compreensão percebida;
- afetos;
- intenção de retorno;
- recusa por pergunta.

Cuidados:

- linguagem adaptada à faixa etária;
- entrevistas cognitivas com crianças;
- respostas ocultas entre integrantes da dupla;
- possibilidade de não responder cada item, e não apenas abandonar todo o questionário;
- distinção clara entre esforço, dificuldade, carga cognitiva, colaboração e afeto.

### 6.2 Linha do tempo técnica

Em vez de duas observações isoladas, registrar eventos minimizados ao longo da sessão:

- sessão iniciada;
- atividade iniciada;
- SPIKE ativo ou inativo;
- intervalo agregado de atividade;
- intervalo agregado de inatividade;
- alteração relevante do artefato;
- checkpoint aberto;
- resposta concluída;
- ajuda solicitada;
- ajuda reconhecida;
- troca de papel;
- etapa concluída;
- missão iniciada;
- missão finalizada;
- sessão encerrada;
- falha técnica;
- sincronização concluída.

Não registrar continuamente títulos completos de janelas ou conteúdo de aplicativos que não pertençam à pesquisa. Preferir categorias técnicas, como `spike_active`, `other_app` e `system_idle`.

### 6.3 Artefato digital

Possíveis evidências:

- hash e tamanho do projeto;
- número de salvamentos;
- versão final do arquivo;
- screenshots vinculados a eventos específicos;
- rubrica do código aplicada posteriormente;
- comparação entre estados do projeto.

Tamanho de arquivo não deve ser interpretado sozinho como aprendizagem ou evolução do código.

### 6.4 Evidência física

Sem câmera ou sensores adicionais, o PulseLab não consegue observar diretamente:

- montagem;
- colaboração corporal ou verbal;
- comportamento físico do robô;
- execução da pista;
- participação individual fora do computador.

#### Opção A — sem câmera

Limitar as perguntas científicas a:

- autorrelato;
- processo digital;
- pedidos de ajuda;
- atividade técnica;
- resultados objetivos da missão;
- viabilidade da coleta.

Não alegar observação direta da colaboração física.

#### Opção B — câmera superior limitada

Utilizar uma câmera apontada para mesa, robô e mãos, evitando rostos e áudio sempre que possível.

Possibilidades:

- fotografia em etapas predefinidas;
- pequenos clipes acionados por evento;
- gravação somente do teste final;
- revisão posterior por rubrica;
- auditoria de uma amostra, sem análise integral de todas as sessões.

Essa opção exige justificativa de necessidade, avaliação ética específica, minimização, controle de acesso e política de retenção.

### 6.5 Resultado objetivo da missão

Substituir uma nota única e subjetiva por dimensões separadas:

- missão iniciada;
- missão concluída;
- etapas concluídas;
- precisão;
- tempo;
- número de tentativas;
- uso correto de componentes;
- uso correto de sensores;
- acertos no quiz;
- necessidade de ajuda;
- explicação do funcionamento;
- participação individual, quando observável.

Conclusão e quantidade de ajuda não devem ser misturadas na mesma nota.

## 7. Painel central necessário

O painel de resultados atual é demonstrativo. O primeiro painel funcional deve priorizar qualidade operacional, não indicadores promocionais.

### 7.1 Visão geral

- sedes cadastradas;
- dispositivos instalados;
- dispositivos online;
- oficinas ativas;
- última sincronização;
- versão do agente;
- versão e hash do protocolo;
- atividade em execução.

### 7.2 Qualidade da coleta

- eventos esperados versus recebidos;
- sessões completas, incompletas ou abortadas;
- checkpoints atrasados;
- recusas e timeouts;
- evidências ausentes;
- falhas de upload;
- filas offline;
- relógios possivelmente incorretos;
- versões incompatíveis;
- códigos institucionais inválidos.

### 7.3 Alertas

- dupla solicitou ajuda;
- pedido não reconhecido;
- sessão sem atividade;
- SPIKE não localizado;
- missão não registrada;
- dispositivo sem sincronizar;
- sede aplicando configuração desatualizada;
- padrão anormal de respostas;
- duas instâncias do agente na mesma máquina.

### 7.4 Auditoria

- seleção aleatória de sessões;
- sessões sinalizadas por regra;
- acesso controlado a imagens;
- rubrica aplicada por avaliador;
- histórico de decisões;
- concordância entre avaliadores;
- registro de exclusões e correções.

## 8. Configuração multicêntrica

O arquivo remoto global atual não é suficiente para atividades simultâneas em cidades diferentes.

Criar uma hierarquia:

```text
regional_hub
└── school
    └── device
        └── workshop
            └── activity
                └── protocol_version
```

### 8.1 Identidade fixa da instalação

Cada máquina deve receber:

- `installation_id`;
- `device_id`;
- `regional_hub`;
- `school_code`;
- credencial própria;
- data de instalação;
- versão autorizada do agente.

Sede e dispositivo não devem depender de digitação manual em cada oficina.

### 8.2 Identidade variável da sessão

Selecionar ou receber de uma agenda central:

- `workshop_id`;
- `class_code`;
- `activity_id`;
- instrutor responsável;
- protocolo aplicável;
- duração planejada.

### 8.3 Reprodutibilidade da configuração

Registrar em cada sessão:

- versão;
- hash criptográfico da configuração;
- conteúdo congelado ou referência imutável;
- momento de ativação;
- responsável pela aprovação.

Alterações no GitHub não podem modificar silenciosamente um protocolo sem mudança de versão.

## 9. Divergências metodológicas e técnicas já identificadas

### 9.1 Papéis

O protocolo exige alternância entre programação e montagem, mas o agente mantém `computer` e `assembly` fixos durante toda a sessão.

Futuro:

- registrar o papel por checkpoint;
- solicitar ou confirmar a troca;
- registrar recusas ou desvios;
- suportar trios separadamente.

### 9.2 Tempo

O segundo checkpoint acumula o tempo gasto no primeiro questionário, nos uploads e no processamento.

Futuro:

- utilizar relógio monotônico;
- agendar checkpoints em relação ao início real da atividade;
- registrar `scheduled_at`, `prompted_at`, `captured_at`, `responded_at` e `received_at`;
- registrar atraso;
- vincular o checkpoint à etapa pedagógica.

### 9.3 Respostas sequenciais

As duas crianças respondem no mesmo computador e em momentos diferentes, embora compartilhem a mesma telemetria anterior.

Futuro:

- registrar o momento individual de cada resposta;
- impedir a exibição da resposta anterior;
- criar procedimento de privacidade entre pares;
- avaliar uso de segundo dispositivo ou modo de resposta por QR code, quando viável.

### 9.4 Screenshot offline

Existe um caminho em que o upload da imagem falha, o evento textual é enviado com sucesso e o arquivo local fica sem associação para reenvio.

Futuro:

- tratar evento e evidência como uma unidade transacional;
- manter estado explícito do upload;
- atualizar o evento depois do envio da imagem;
- confirmar integridade por hash;
- eliminar arquivos locais apenas após confirmação;
- definir expiração e descarte seguro.

### 9.5 Captura de tela

`CopyFromScreen` captura o retângulo da tela correspondente à janela. Se outra janela estiver sobreposta, conteúdo externo pode ser capturado.

Futuro:

- avaliar API de captura específica da janela;
- validar que o processo é realmente o SPIKE;
- não capturar quando minimizado, oculto ou sobreposto;
- remover títulos, notificações e identificadores;
- considerar desativar screenshots até existir justificativa científica.

### 9.6 Telemetria de janela

O título da janela ativa pode conter informações não relacionadas à pesquisa.

Futuro:

- não armazenar títulos completos;
- classificar o processo localmente;
- transmitir apenas categorias;
- aplicar minimização por padrão.

### 9.7 Resultado no nível da dupla

A rubrica da dupla é duplicada nas linhas dos dois participantes.

Futuro:

- tabela ou evento de sessão/dupla;
- resultados compartilhados registrados uma única vez;
- respostas individuais separadas;
- unidade de análise explicitada.

### 9.8 Sessões sem dados

Se assentimento for recusado, o agente encerra sem permitir calcular quantas duplas foram convidadas. Também faltam estados centralizados de início, abandono e falha.

Futuro:

- definir com o CEP uma contagem agregada de elegibilidade e recusas;
- criar `session_status`;
- distinguir `not_started`, `declined`, `aborted`, `technical_failure`, `completed` e `synced`;
- não registrar informação individual de quem não consentiu além do que for aprovado.

## 10. Integridade, autenticação e segurança

### 10.1 Problema atual

A política de inserção anônima aceita qualquer linha compatível com o schema. A chave pública permite que um terceiro fabrique eventos.

Isso protege parcialmente a confidencialidade, mas não garante autenticidade ou integridade científica.

### 10.2 Direção futura

- credencial individual por instalação;
- registro prévio dos dispositivos;
- token de curta duração;
- endpoint de ingestão controlado;
- validação server-side;
- vínculo entre dispositivo, sede e escola;
- limites de frequência e tamanho;
- rejeição de versões não autorizadas;
- assinatura ou hash do lote;
- logs de auditoria;
- rotação e revogação de credenciais.

### 10.3 Supabase

- declarar `GRANT INSERT` explicitamente;
- manter RLS;
- evitar leitura pelo cliente;
- restringir uploads por identidade, caminho, tipo e tamanho;
- separar bucket de teste e produção;
- executar Security Advisor;
- testar inserção e upload com a mesma função usada pelo agente;
- confirmar região, backup e política de retenção;
- nunca distribuir `service_role`.

### 10.4 Cliente Windows

- impedir duas instâncias simultâneas;
- assinar o agente ou verificar integridade;
- não executar código modificável em pasta pública;
- proteger a configuração;
- mostrar erros operacionais ao instrutor;
- usar atualizações versionadas;
- testar Windows 10 e 11;
- testar PowerShell 5.1;
- manter logs sem respostas ou conteúdo sensível;
- criptografar ou proteger o cache local;
- limpar o cache após confirmação.

## 11. Ética, privacidade e governança

### 11.1 Antes de coleta científica

Definir:

- instituição proponente;
- pesquisador responsável;
- controlador dos dados;
- operador ou fornecedores;
- encarregado ou canal de contato;
- CEP responsável;
- base legal aplicável;
- TCLE;
- TALE ou processo de assentimento;
- política de acesso;
- prazo de retenção;
- procedimento de exclusão;
- procedimento de retirada;
- tratamento de incidentes;
- política de publicação;
- retorno dos resultados à comunidade.

### 11.2 Assentimento

O convite deve explicar, em linguagem adequada:

- finalidade da pesquisa;
- perguntas;
- telemetria;
- screenshots, fotos ou vídeos, quando houver;
- desconfortos;
- benefícios esperados;
- voluntariedade;
- possibilidade de não responder;
- possibilidade de sair depois;
- não prejuízo à oficina;
- contato do responsável e do CEP.

O assentimento não substitui o consentimento ou a autorização aplicável do responsável.

### 11.3 Pseudonimização

Não coletar nomes no banco analítico é uma boa salvaguarda, mas os dados continuam potencialmente identificáveis por:

- escola;
- turma;
- horário;
- computador;
- atividade;
- screenshot;
- vídeo;
- grupos pequenos;
- combinação de eventos.

Tratar o conjunto como dado pessoal pseudonimizado até que uma avaliação formal demonstre anonimização.

### 11.4 Minimização

Para cada campo, responder:

1. Qual pergunta científica exige este dado?
2. Existe alternativa menos invasiva?
3. Quem acessará?
4. Por quanto tempo?
5. Como será descartado?
6. Qual dano pode decorrer de vazamento ou uso inadequado?

## 12. Diagnóstico das hipóteses atuais

### H1 — esforço aos 20 e 40 minutos

Testável, depois de corrigir temporização, papéis, atraso e validade do item.

### H2 — bloqueio e intervenção

Parcialmente circular, pois pedir ajuda produz um alerta que pode causar a intervenção.

Possível reenquadramento:

- tempo entre pedido e resposta;
- proporção de pedidos atendidos;
- evolução depois da ajuda;
- diferença entre pedidos explícitos e bloqueios sem pedido.

### H3 — participação equilibrada e desempenho

Ainda não testável de forma forte. Existe apenas percepção de colaboração, sem medida objetiva de participação.

Necessário:

- rubrica;
- troca registrada de papéis;
- evidência física ou avaliação estruturada;
- medida individual ou da dupla claramente definida.

### H4 — conhecimento pré e pós

Não implementada.

Necessário:

- objetivos pedagógicos por atividade;
- itens equivalentes;
- revisão por especialistas;
- entrevistas cognitivas;
- regras de pontuação;
- análise pareada;
- separação entre compreensão percebida e conhecimento demonstrado.

## 13. Primeiro estudo academicamente recomendável

### 13.1 Título conceitual

> Desenvolvimento e avaliação de viabilidade de um protocolo distribuído de coleta de dados em oficinas de robótica educacional.

### 13.2 Desfecho primário

Viabilidade operacional:

- oficinas elegíveis;
- oficinas iniciadas;
- consentimentos e assentimentos aplicáveis;
- eventos esperados;
- eventos recebidos;
- sessões completas;
- timeouts;
- atrasos;
- perdas de evidência;
- sincronização offline;
- carga sobre o instrutor;
- compreensão das perguntas;
- pedidos de ajuda;
- tempo de resposta;
- desvios de protocolo.

### 13.3 Desfechos secundários exploratórios

- esforço percebido;
- progressão ou bloqueio;
- colaboração percebida;
- experiência prévia;
- autoeficácia;
- afetos;
- intenção de retorno;
- desempenho objetivo da missão.

Não usar o piloto para alegações definitivas sobre aprendizagem ou impacto.

## 14. Estratégia de validação sem pesquisadores permanentes

Não é necessário manter pesquisadores em todas as unidades. É necessário calibrar o sistema antes da operação autônoma.

### Fase 1 — Juazeiro

- 10 a 20 oficinas acompanhadas pelo pesquisador;
- aplicativo e observação humana em paralelo;
- comparação de tempos, bloqueios, papéis, ajuda e resultado;
- entrevistas cognitivas;
- avaliação do impacto dos pop-ups;
- identificação de proxies úteis e inúteis.

### Fase 2 — segunda sede

- instrutor local executa o protocolo;
- pesquisador acompanha remotamente uma parte;
- missão final registrada;
- amostra revisada;
- comparação entre sedes;
- revisão das instruções e da rubrica.

### Fase 3 — quatro sedes

- operação sem pesquisador local permanente;
- painel central real;
- auditoria aleatória;
- revisão por exceção;
- visitas ocasionais;
- controle de versão e qualidade.

### Fase 4 — estudo substantivo

Somente depois da validação:

- congelar instrumento;
- calcular amostra;
- registrar previamente hipóteses e análise;
- executar estudo observacional ou comparativo;
- reportar conforme diretrizes adequadas, como STROBE quando aplicável.

## 15. Modelo de auditoria remota

O pesquisador central não precisa assistir a todas as oficinas.

O sistema deve selecionar:

- todas as sessões com falha;
- todas as sessões com pedido de ajuda não atendido;
- todas as sessões incompletas;
- sessões com valores extremos;
- sessões com divergência entre participantes;
- sessões com desvio da rubrica;
- uma amostra aleatória de sessões normais.

O trabalho humano passa a ser orientado por risco e amostragem.

## 16. Retorno à sociedade

Coletar dados não constitui, sozinho, retorno social. O PulseLab deve criar um ciclo:

```text
coleta
  └── análise
      └── identificação de dificuldades
          └── ajuste pedagógico
              └── devolutiva às sedes
                  └── nova avaliação
```

Entregas possíveis:

- relatório periódico para cada sede;
- principais dificuldades por atividade;
- pontos em que mais ajuda é solicitada;
- materiais pedagógicos a revisar;
- comparação da fidelidade de execução;
- recomendações de formação dos instrutores;
- devolutiva pública agregada;
- apresentação acessível para estudantes, famílias e parceiros;
- registro das mudanças realizadas a partir dos achados.

O alerta de ajuda pode gerar benefício imediato, mas transforma o sistema em parte da intervenção pedagógica. Isso deve ser reconhecido no desenho do estudo.

## 17. Backlog priorizado

### P0 — antes de dados reais destinados à pesquisa

- [ ] Definir responsável institucional, CEP e governança.
- [ ] Definir TCLE, assentimento e retirada.
- [ ] Definir idade mínima e linguagem.
- [ ] Definir atividade, etapas e missão.
- [ ] Definir rubrica objetiva.
- [ ] Desativar screenshots até justificar sua necessidade.
- [ ] Corrigir identidade por sede e dispositivo.
- [ ] Corrigir autenticação da ingestão.
- [ ] Corrigir permissões explícitas no Supabase.
- [ ] Corrigir temporização absoluta.
- [ ] Corrigir troca de papéis.
- [ ] Corrigir fila de screenshots.
- [ ] Impedir instâncias duplicadas.
- [ ] Criar sessão e estados de completude.

### P1 — piloto

- [ ] Criar painel real de qualidade.
- [ ] Criar linha do tempo de eventos.
- [ ] Implementar recusa por item.
- [ ] Separar resultado, ajuda e participação.
- [ ] Criar teste final padronizado.
- [ ] Criar configuração imutável por sede.
- [ ] Realizar entrevistas cognitivas.
- [ ] Testar Windows 10/11 e modo offline.
- [ ] Criar dados e ambiente exclusivos de homologação.
- [ ] Documentar SOP do instrutor.

### P2 — validação

- [ ] Comparar aplicativo e pesquisador em Juazeiro.
- [ ] Calcular concordância entre avaliadores.
- [ ] Validar proxies de telemetria.
- [ ] Validar rubrica do artefato.
- [ ] Avaliar reatividade aos checkpoints.
- [ ] Testar segunda sede.
- [ ] Revisar e congelar instrumento.

### P3 — expansão

- [ ] Implantar em quatro sedes.
- [ ] Criar auditoria remota por risco.
- [ ] Criar relatórios por sede.
- [ ] Criar exportação reproduzível.
- [ ] Criar scripts estatísticos versionados.
- [ ] Calcular amostra do estudo definitivo.
- [ ] Registrar previamente o plano de análise.

## 18. Decisões futuras

1. Quais fenômenos são prioritários: viabilidade, bloqueio, desempenho, aprendizagem ou colaboração?
2. Quais atividades serão padronizadas?
3. Todas as oficinas possuem a mesma duração?
4. Qual é a etapa aos 20 e 40 minutos?
5. Como os papéis são trocados?
6. Como funcionam trios?
7. Qual é o resultado objetivo da missão?
8. Screenshots são indispensáveis?
9. Será usada câmera superior?
10. Será gravado áudio?
11. Como será registrada a missão final?
12. O instrutor registrará alguma rubrica?
13. Como pedidos de ajuda serão reconhecidos?
14. Quem acessará imagens e vídeos?
15. Qual será a retenção?
16. Como o participante solicitará retirada?
17. Como dispositivos serão autenticados?
18. Como atividades simultâneas receberão configurações diferentes?
19. Como escolas receberão devolutivas?
20. Qual evidência será necessária para declarar que o sistema opera sem pesquisador local permanente?

## 19. Critério de sucesso da visão

O PulseLab cumprirá seu propósito quando:

- as sedes puderem operar sem pesquisador local;
- o pesquisador central souber quais oficinas ocorreram;
- a aderência ao protocolo puder ser verificada;
- dados incompletos forem detectados rapidamente;
- os resultados principais forem objetivos ou validados;
- uma amostra puder ser auditada remotamente;
- configurações e instrumentos forem reproduzíveis;
- privacidade, ética e segurança estiverem formalizadas;
- achados gerarem devolutivas e melhorias pedagógicas.

## 20. Síntese

A falta de pesquisadores em todas as sedes não invalida o projeto. Ela é precisamente o problema de pesquisa e de produto que o PulseLab deve resolver.

A contribuição mais forte não é alegar que um software possui a mesma percepção de um pesquisador humano. É demonstrar que evidências padronizadas, coletadas automaticamente e auditadas remotamente, permitem que um único pesquisador acompanhe múltiplas unidades com qualidade aceitável.

O modelo pretendido é:

> coleta automatizada em todas as oficinas, observação humana concentrada na validação e auditoria amostral, e coordenação científica central.

Essa solução preserva a viabilidade operacional, reconhece os limites do instrumento e cria um caminho realista para credibilidade acadêmica.
