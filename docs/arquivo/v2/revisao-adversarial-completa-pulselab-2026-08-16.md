# Revisão adversarial completa do PulseLab

Data da revisão: 2026-08-16
Escopo: working tree local atual, incluindo alterações ainda não commitadas
Método: inspeção direta dos arquivos + revisão independente por agy e Codex + execução das verificações locais disponíveis

## 1. Veredito executivo

**NO-GO no estado atual para piloto em oficina, distribuição do instalador ou coleta acadêmica.**

O bloqueador imediato é objetivo: `agent/pulselab-agent.ps1` termina com um bloco `catch/finally` duplicado e não é sintaticamente executável (`agent/pulselab-agent.ps1:2034-2057`). O mesmo agente quebrado está embutido em `instalador/agent-payload.js`, com equivalência byte a byte confirmada.

Mesmo corrigindo o parse, persistem problemas críticos:

1. solo e trio quebram no motor porque `New-ResearchEvent` aceita somente `computer|assembly`, enquanto o fluxo gera `individual|member_3`;
2. retomada reinicia o cronômetro, deslocando checkpoints e fabricando atraso;
3. troca de papéis e rubrica do instrutor são código morto no agente;
4. o Portal do Instrutor simula autenticação e gravação, mas não autentica nem envia dados;
5. a ingestão anônima não garante autenticidade científica e aceita dados forjados;
6. o gerador web está protegido por senha exposta no próprio HTML, distribui o agente quebrado e gera configuração sem credenciais operacionais;
7. a suíte automatizada fica verde sem analisar a sintaxe PowerShell ou os fluxos reais.

A interface visual tem uma base coerente e o projeto demonstra boas intenções de minimização e auditabilidade, mas a implementação atual não sustenta as promessas funcionais, metodológicas e de segurança publicadas.

## 2. Como a revisão foi feita

### Arquivos principais revisados

- `agent/pulselab-agent.ps1`: motor Windows/WPF, estado, cronômetro, telemetria, fila offline e envio;
- `schema/supabase-schema.sql`: tabelas, constraints, RLS, Storage e view de qualidade;
- `web/agent-simulator/app/page.jsx`: máquina de estados do simulador;
- `web/agent-simulator/app/globals.css`: layout, responsividade e acessibilidade visual;
- `instrutor/index.html`: autenticação e avaliação do instrutor;
- `instalador/index.html` e `instalador/agent-payload.js`: gerador web;
- `installer/build-installer.py` e instaladores PowerShell;
- `tests/test_contracts.py` e `web/agent-simulator/tests/contracts.test.mjs`;
- README, configuração e Firebase Hosting.

### Execuções realizadas

- `python3 -m unittest discover -s tests -v`: **25 testes passaram**;
- `npm test --prefix web/agent-simulator`: **9 testes passaram**;
- `npm run build --prefix web/agent-simulator`: **build Vite concluído**;
- `npm run check --prefix web/agent-simulator`: **falhou**, pois o script `check` documentado no README não existe no `package.json`;
- JavaScript inline do portal e instalador: parseável;
- comparação do agente com o payload web: **mesmos bytes e mesmo SHA-256**;
- navegador não utilizado, conforme solicitado. UI/UX foi revisada pelos componentes, HTML, CSS, estados e contratos.

### Limites

Não houve execução do WPF em Windows 10/11, aplicação do SQL em um Supabase de homologação, inspeção das políticas efetivamente implantadas ou teste físico com LEGO SPIKE. Achados marcados como “confirmados” são demonstráveis no código atual; riscos que dependem de ACL, DPI, sobreposição de janelas ou infraestrutura real são identificados como hipóteses de campo.

## 3. Arquitetura observada

O PulseLab possui cinco superfícies diferentes:

1. **motor real**: script PowerShell 5.1 com WPF e Win32;
2. **ingestão**: PostgREST e Storage do Supabase usando chave `anon`;
3. **simulador React/Vite**: representa o fluxo sem executar Win32/Supabase;
4. **Portal do Instrutor**: HTML estático que hoje é apenas uma demonstração;
5. **distribuição**: geradores Python/PowerShell e um gerador público no navegador.

O desenho conceitual — eventos append-only, identificadores por sessão, fila offline, bucket privado e telemetria categorizada — é razoável. O principal problema é que as cinco superfícies não compartilham uma máquina de estados e um contrato executável único. Isso criou divergências graves entre documentação, simulador, agente, schema, portal e instaladores.

## 4. Top 12 impeditivos

| ID | Severidade | Achado | Evidência principal | Impacto |
|---|---|---|---|---|
| P01 | Bloqueador | PowerShell termina com `finally` duplicado e chaves excedentes | `agent/pulselab-agent.ps1:2034-2057` | O agente não inicia |
| P02 | Crítica | Solo/trio geram papéis rejeitados pelo próprio construtor de eventos | `agent/pulselab-agent.ps1:808-813`, `1109-1127` | Grupos 1 e 3 falham na primeira resposta |
| P03 | Crítica | Portal ignora senha e não grava no Supabase | `instrutor/index.html:727-812` | Autoria e persistência são fictícias |
| P04 | Crítica | Inserts anônimos permitem forjar eventos, avaliações e objetos | `schema/supabase-schema.sql:180-188`, `260-268`, `371-376`, `431-440` | Dataset acadêmico não é autenticável |
| P05 | Alta | Retomada reinicia cronômetro em zero mantendo horário antigo | `agent/pulselab-agent.ps1:1793-1823`, `1943-1966` | Checkpoints atrasam e tempos ficam inválidos |
| P06 | Alta | Troca de papéis e rubrica são funções sem chamada | `agent/pulselab-agent.ps1:1401`, `1766`; nenhuma invocação | Protocolo publicado não é executado |
| P07 | Alta | Fluxo padrão do simulador também pula troca, rubrica e `activity_end` | `page.jsx:766-785`; nenhuma chamada a `setScreen("role_swap")` ou `setScreen("activity_end")` | Simulador valida um fluxo diferente do prometido |
| P08 | Alta | Qualidade SQL usa contagens fixas de dupla e aceita timeout/recusa como resposta | `schema/supabase-schema.sql:309-357` | Sessão inválida pode virar `complete`; solo é penalizado |
| P09 | Alta | Gerador web usa senha pública, agente quebrado e configuração sem Supabase | `instalador/index.html:524-533`, `677-720`, `746-806`; `agent-payload.js` | Instalador público não é controle de acesso nem artefato confiável |
| P10 | Alta | Testes verdes não analisam PowerShell nem renderizam os fluxos | `tests/test_contracts.py:121-253`; `contracts.test.mjs` | Falhas fatais passam pela CI |
| P11 | Alta | Fila offline é sobrescrita sem atomicidade, lock ou recuperação | `agent/pulselab-agent.ps1:708-725`, `754-805` | Queda ou concorrência pode perder toda a fila |
| P12 | Alta | Reconfiguração durante sessão altera contexto global dos eventos | `agent/pulselab-agent.ps1:1591-1611` | Uma sessão pode misturar escola/oficina/atividade |

## 5. Revisão do motor do aplicativo

### P01 — Erro de sintaxe fatal

**Estado:** confirmado. **Severidade:** bloqueador.

Depois do `catch` externo, há um primeiro `finally` inválido contendo um fragmento repetido e, em seguida, outro `finally` (`agent/pulselab-agent.ps1:2049-2053`). Isso impede o parsing antes de qualquer janela ou log operacional.

O problema é agravado por dois fatos:

- os 25 testes Python passaram porque inspecionam strings e blocos XAML isolados, não o parser PowerShell;
- `instalador/agent-payload.js` embute exatamente os mesmos bytes do arquivo quebrado.

**Correção:** remover o fragmento duplicado e adicionar gate obrigatório com Windows PowerShell 5.1, por exemplo parsing via `[System.Management.Automation.Language.Parser]::ParseFile`, além de execução smoke em Windows.

### P02 — Grupos de 1 e 3 não funcionam

**Estado:** confirmado. **Severidade:** crítica.

`Get-ParticipantList` produz papel `individual` para solo e `member_3` para trio (`1109-1127`). Entretanto, `New-ResearchEvent` usa `[ValidateSet("computer", "assembly")]` (`808-813`). O PowerShell lança erro de validação quando tenta salvar o primeiro pré-questionário.

Isso contradiz a configuração e a UI que permitem `group_size` entre 1 e 3.

**Correção:** definir o enum de papéis em um contrato compartilhado e testar matrizes completas para 1, 2 e 3 participantes. O schema já aceita `individual` e `member_3`, mas motor, simulador e qualidade precisam ser alinhados.

### P05 — Retomada temporal incorreta

**Estado:** confirmado. **Severidade:** alta.

Na retomada, `ActivityStartedAt` é restaurado, mas `Start-ResearchLoop` cria um novo `Stopwatch` em zero (`1795-1799`). `Wait-UntilActivityTime` espera o alvo integral com base nesse cronômetro novo (`1756-1763`, `1821-1823`).

Exemplo: uma oficina interrompida aos 25 minutos, com checkpoint 20 concluído, volta a esperar 40 minutos para o marco 40. O questionário aparecerá perto do minuto real 65 e será classificado com atraso artificial.

**Correção:** persistir elapsed monotônico ou calcular `elapsedBeforeRestart = Now - ActivityStartedAt`, inicializando o agendamento pelo tempo restante. Ajustes de relógio devem ser tratados explicitamente.

### P13 — Retomada mistura versões do protocolo

**Estado:** confirmado. **Severidade:** alta.

`Get-RemoteConfig` roda antes de restaurar a sessão (`1937-1944`). O estado persistido não contém snapshot de perguntas, marcos, config e hash (`248-285`). Uma oficina reiniciada depois de atualização remota pode combinar pré-questionário antigo com checkpoints novos.

**Correção:** salvar a configuração canônica completa ou uma referência imutável assinada junto da sessão e usar exatamente esse snapshot até o encerramento.

### P14 — Retomada pode falhar por variável não inicializada

**Estado:** confirmado. **Severidade:** alta.

`$participants` é definido dentro do loop de checkpoint (`1883`). Se uma sessão retomada já possuir todos os checkpoints, ou se o encerramento for acionado antes do próximo marco, o loop pula essa atribuição. O pós-questionário usa `$participants` em `1915` sob `StrictMode`, gerando erro fatal.

**Correção:** construir a lista de participantes no início de `Start-ResearchLoop` e validá-la contra o snapshot da sessão.

### P06 — Troca de papéis e rubrica não executadas

**Estado:** confirmado. **Severidade:** alta.

`Show-WpfInstructorRubric` e `Invoke-ConfiguredRoleSwap` existem, mas não são chamadas. Após os checkpoints, o agente segue diretamente para o encerramento e pós-questionário (`1900-1925`).

Mesmo se a troca fosse chamada, `Get-ParticipantList` reconstrói papéis estáticos (`computer`, `assembly`, `member_3`) e ignora `ParticipantComputerRole` e `ParticipantAssemblyRole`; eventos posteriores perderiam a troca.

**Impacto:** equilíbrio de participação e avaliação do instrutor, descritos como partes do protocolo, não entram no dataset.

### P15 — Encerramento antecipado registra contagem configurada, não realizada

**Estado:** confirmado. **Severidade:** média.

`session_completed.details.checkpoint_count` recebe `$marks.Count` (`1923-1925`), mesmo se o instrutor encerrar antes dos checkpoints. A view pode ainda marcar revisão pela contagem real, mas o evento final contém informação falsa.

**Correção:** registrar `CompletedCheckpoints.Count`, motivo de encerramento e conjunto de marcos efetivamente concluídos.

### P16 — Reconfiguração durante sessão quebra a identidade da coleta

**Estado:** confirmado. **Severidade:** alta.

O menu da bandeja mantém “Reconfigurar Contexto da Máquina” disponível durante a atividade (`1597-1600`). A tela altera variáveis globais usadas por eventos subsequentes e salva o perfil. Assim, uma mesma `session_id` pode começar em uma escola/oficina e terminar em outra.

**Correção:** congelar contexto de sessão. Reconfiguração deve afetar somente a próxima sessão ou exigir encerramento explícito da atual.

### P17 — Bloqueios e reentrância

**Estado:** confirmado no código; impacto de campo requer Windows. **Severidade:** média.

- chamadas HTTP são síncronas e podem bloquear até 10 segundos por evento;
- flush processa itens sequencialmente no mesmo thread;
- o loop usa `Application.DoEvents()`, o que permite reentrância de menus enquanto o estado está sendo alterado;
- pré, pós, assentimento e rubrica não têm timeout; só checkpoint possui `DispatcherTimer`;
- não há mutex/singleton, então dois atalhos podem operar sobre `session_state.json` e `research-queue.json` simultaneamente.

**Correção:** separar UI, scheduler e transporte; serializar side effects em uma fila transacional; criar lock por instalação; desabilitar ações incompatíveis por estado.

### P18 — Captura e recursos GDI

**Estado:** risco confirmado no desenho; conteúdo capturado depende do Windows. **Severidade:** média.

`CopyFromScreen` captura pixels da região, não o conteúdo isolado da janela (`592-608`). Notificações ou janelas sobrepostas podem entrar na imagem. `Graphics` e `Bitmap` não ficam em `finally`, podendo vazar handles em exceções.

**Correção:** avaliar `PrintWindow`/Windows Graphics Capture, mascarar chrome e notificações, garantir `Dispose` em `finally`, registrar consentimento específico e oferecer captura desativada por protocolo.

## 6. Cache offline, sincronização e observabilidade

### P11 — Persistência não atômica

A fila é lida por inteiro, desserializada, acrescida e sobrescrita diretamente com `Set-Content`. Uma queda durante escrita pode truncar o único arquivo. Não existe arquivo temporário + rename atômico, journal, lock, backup válido, checksum, quarentena de item inválido ou limite de crescimento.

**Impacto:** o mecanismo criado para proteger contra rede ruim vira ponto único de perda local.

### P19 — Evidência ausente pode ser silenciosamente degradada

No flush, a retenção forte ocorre apenas quando o arquivo local existe. Se `local_screenshot_path` estiver preenchido, mas o arquivo tiver sido apagado ou corrompido, o fluxo pode enviar a linha sem `screenshot_path` (`769-790`) em vez de gerar `quality_issue` explícito.

**Correção:** estados de entrega separados (`image_pending`, `image_missing`, `row_pending`, `complete`), nunca inferidos apenas por path; manifest com hash/tamanho; quality event em perda local.

### P20 — Dados locais sem política de retenção

Respostas, estado e screenshots ficam em `%LocalAppData%\PulseLab` sem criptografia de aplicação, expiração, cota, purge por retirada ou inventário para suporte. A fila pode crescer indefinidamente.

O uso de escopo local é melhor que área pública, mas ainda precisa de ACL validada, retenção documentada e rotina de limpeza auditável.

### Pontos positivos reais

- `event_id` e `on_conflict=event_id` oferecem idempotência básica;
- bucket é privado;
- upload e linha tentam permanecer como unidade;
- títulos brutos de janela são anulados na fonte;
- `occurred_at` e `received_at` distinguem origem de ingestão;
- eventos de qualidade explícitos são uma boa direção.

Esses mecanismos são úteis, mas não compensam a ausência de atomicidade local e autenticação do emissor.

## 7. Segurança, privacidade e integridade científica

### P04 — Insert-only não garante autenticidade

A RLS impede leitura anônima, o que reduz exfiltração. Porém, `WITH CHECK (true)` permite que qualquer portador da chave pública envie eventos com qualquer `installation_id`, `session_id`, escola, oficina e participante. Storage aceita qualquer objeto anônimo no bucket sem prefixo, MIME, tamanho ou cota.

Para telemetria de baixo risco isso pode ser aceitável em protótipo isolado; para pesquisa acadêmica, significa que a origem do dado não é demonstrável.

**Correção:** provisionar identidade por dispositivo/instalação, JWT curto ou endpoint de ingestão; vincular claims ao prefixo e aos campos permitidos; aplicar rate limit, tamanho e MIME; separar ambiente de demonstração e pesquisa.

### P03/P21 — Avaliação do instrutor é falsificável e não associável

`instructor_evaluations` aceita `anon` e qualquer `instructor_email`; a whitelist não participa da policy. A tabela não contém `session_id`, `dyad_id` ou `installation_id`, então oficina + turma não identificam de forma inequívoca vários computadores da mesma aula.

Além disso, usuários autenticados podem consultar toda a whitelist ativa porque a policy verifica apenas `is_active`, não `auth.jwt()->>'email'`.

**Correção:** exigir usuário autenticado autorizado, vincular `instructor_email` ao claim do JWT e registrar identificadores de sessão/grupo. Não expor a lista completa para todos os autenticados.

### P08 — View de qualidade mede linhas, não completude válida

A view conta todos os eventos `pre/checkpoint/post`, independentemente de `response_status`. Recusas e timeouts satisfazem os limiares. Os limiares também são fixos em duas pessoas (`pre >= 2`, `checkpoint >= expected*2`, `post >= 2`).

Consequências:

- solo completo nunca atende o mínimo de duas respostas;
- trio pode ser considerado completo sem todos os participantes;
- duplicatas lógicas podem preencher a contagem;
- uma sessão com apenas recusas/timeouts pode virar `complete`;
- não existe unicidade por sessão + participante + etapa + marco.

**Correção:** derivar quantidade esperada do `participant_count` congelado, contar somente `completed` quando a métrica exigir resposta, tratar recusas como estado ético válido mas analiticamente distinto e validar cobertura por participante/marco.

### P22 — Minimização ainda possui vazamentos potenciais

- `computer_id = $env:COMPUTERNAME` pode conter nome de aluno ou patrimônio identificável;
- screenshot da janela pode conter nome de projeto, conta, arquivo ou notificação;
- arquivo SPIKE “mais recente” pode pertencer a outra turma (`574-581`);
- caminhos e respostas offline ficam disponíveis no perfil local.

**Correção:** usar ID aleatório da instalação no lugar do hostname, avaliar necessidade de screenshot, mascarar metadados e produzir DPIA/LIA e política de retenção antes de coleta com menores.

### P23 — Configuração remota é trilha de supply chain

O agente aceita configuração de `main` e registra o hash apenas depois; não verifica assinatura ou allowlist de campos. Uma alteração indevida no repositório pode mudar instrumentos e potencialmente redirecionar destino/credenciais se campos forem preenchidos.

**Correção:** releases imutáveis, assinatura, schema estrito, allowlist, versão aprovada do protocolo e processo de rollback.

## 8. Portal do Instrutor

### P03 — Autenticação e persistência são simuladas

O submit do login usa apenas o e-mail, ignora o valor da senha e chama `openInstructorPanel` (`728-733`). Recuperação e troca de senha exibem mensagens sem backend. O envio da avaliação monta payload, faz `console.log`, espera 400 ms e afirma que o dado foi salvo (`751-812`). Não há `fetch`, Supabase client ou chamada de autenticação.

Isso não é apenas “MVP incompleto”: a UI comunica sucesso inexistente, o que causa perda silenciosa de dados e falsa confiança operacional.

**Correção:** enquanto não houver backend real, rotular toda a página como demonstração e impedir linguagem de gravação. Depois, implementar Supabase Auth real, whitelist ligada ao JWT, submit transacional, erro/retry e confirmação retornada pelo servidor.

### P24 — Viés e estado visual inconsistente

Desempenho e intervenções aparecem pré-selecionados. Isso induz resposta e prejudica neutralidade do instrumento. Ao fechar o modal, `form.reset()` restaura inputs ocultos, mas as classes visuais `.selected` não são sincronizadas, criando divergência entre o que o usuário vê e o payload seguinte.

**Correção:** nenhuma resposta inicial; seleção obrigatória; estado controlado único; após reset, limpar classes e estados ARIA.

### Acessibilidade do portal

- opções customizadas não expõem `aria-pressed`/`aria-selected`;
- modal não tem `role="dialog"`, `aria-modal`, foco inicial, trap de foco, Escape ou restauração de foco;
- alertas não são regiões vivas;
- autenticação falsa torna toda a jornada de recuperação enganosa.

## 9. Simulador web e experiência UI/UX

### P07 — Máquina de estados não representa o protocolo

No checkpoint 20, o simulador volta para `activity`; nunca entra em `role_swap`. No checkpoint 40, segue diretamente para `post_a`; nunca entra em `activity_end` ou rubrica (`766-785`). `RoleSwapScreen` e `ActivityEndScreen` existem, mas não possuem transição de entrada.

A rubrica é alcançada apenas pelo botão de encerramento antecipado da tela de atividade. No caminho normal, `savedRubric` permanece vazio e os posts carregam valores nulos, enquanto a sessão pode ser marcada completa.

### P25 — Trio incompleto no simulador

`activeParticipants` inclui C, mas `roles` começa somente com A/B (`230`, `399-402`). Eventos de C recebem papel ausente. O schema exige `participant_role NOT NULL`. Status de checkpoint grava apenas A/B (`774-777`) e o resumo espera exatamente duas respostas (`1794-1804`).

### P26 — Cenários documentados não estão implementados como seleção

README do simulador lista fluxo padrão, atraso, SPIKE ausente, offline, encerramento antecipado, troca não confirmada, recusa e aborto. `SCENARIOS` contém somente quatro opções técnicas. Alguns casos podem ser acionados indiretamente, mas não existe uma suíte reproduzível que confirme os sete caminhos documentados.

### Qualidades de UI observadas nos arquivos

- hierarquia clara, linguagem majoritariamente direta e cards consistentes;
- separação visível entre simulação e coleta real;
- `fieldset/legend` nas escalas;
- `:focus-visible` e `prefers-reduced-motion`;
- responsividade declarada até 760 px;
- botões grandes e estados selecionados visíveis em grande parte do fluxo;
- opção “Prefiro não responder” preservada.

### Problemas de UI/UX e acessibilidade

1. **Opções de progresso e emoções:** são botões sem `aria-pressed`, ao contrário de `ScaleQuestion`.
2. **Abas de evidência:** não têm semântica de tabs nem `aria-selected`.
3. **Feedback:** toast não possui `role="status"`/`aria-live`.
4. **Foco:** mudança de tela não move foco para o novo `h1`; leitor de tela pode permanecer em posição antiga.
5. **Seleção visual:** regras duplicadas de `.scale-option.is-selected > span` deixam `background: transparent !important` vencer o fundo pretendido e reduzem contraste do ícone (`globals.css:727-755`).
6. **Mobile:** abaixo de 760 px, cenário e reinício desaparecem; capacidades essenciais de validação somem em vez de serem recolocadas.
7. **Carga cognitiva:** o simulador mostra simultaneamente roteiro, formulário, controles de rede e payload técnico; é ótimo para pesquisador, mas excessivo para criança. A interface infantil deveria ocultar instrumentação técnica.
8. **Privacidade prática:** telas sequenciais no mesmo computador dizem “responda sozinho”, mas não oferecem handoff, tela neutra ou confirmação de que o colega se afastou.
9. **WPF fixo:** janelas de 630×560, 650×740 e 660×710 com `NoResize`/`Topmost` podem falhar em DPI alto ou telas pequenas. O corpo possui scroll em alguns casos, mas cabeçalho/rodapé fixos ainda podem ficar comprimidos.
10. **Saída/recuperação:** várias janelas `WindowStyle=None` não oferecem fechar, ajuda ou recuperação explícita.

### Recomendação de produto

Separar três modos:

- **modo participante:** somente a pergunta atual, sem telemetria/payload;
- **modo instrutor:** contexto, andamento, pedidos de ajuda e encerramento;
- **modo validação/pesquisador:** cenários, timeline e JSON técnico.

Hoje o simulador mistura os três públicos.

## 10. Instalação e atualização

### P09 — “Área restrita” do gerador web não é restrita

Usuário e senha aparecem preenchidos no HTML e repetidos como texto no JavaScript. `passwordHash` não é hash. Alterar `sessionStorage` para `authenticated` libera a tela.

O controle deve ser removido ou substituído por autenticação de servidor. Segurança client-side aqui é apenas aparência.

### Artefato operacional inválido

O gerador web usa `PULSELAB_DEFAULT_CONFIG`, que possui `supabase_url` e `supabase_key` vazios. Diferentemente de `installer/build-installer.py`, a página não solicita credenciais nem as injeta. O agente gerado falhará em `Get-EnvCredentials`, salvo se a máquina já tiver variáveis configuradas.

Além disso, o payload embutido é exatamente o PowerShell com erro fatal.

### Supply chain e execução

- `iex (irm .../main/installer/install.ps1)` executa branch mutável sem pin, assinatura ou checksum;
- instruções recomendam contornar SmartScreen e executar `Unblock-File` recursivo;
- scripts são instalados em `C:\Users\Public\Pulselab` e executados com `ExecutionPolicy Bypass`;
- não há validação do tamanho/hash do agente antes de anunciar sucesso;
- fallback de download usa sempre `Install-Pulselab-Teste.zip`, independentemente da cidade;
- não há assinatura de código, manifesto de release, rollback ou atualização transacional.

A possibilidade de outro usuário local alterar o script em `C:\Users\Public` depende das ACLs reais, mas deve ser tratada como risco alto e testada. O ideal é diretório por máquina com ACL restrita e artefato assinado.

## 11. Testes e qualidade de engenharia

### O que os testes atuais comprovam

- configuração possui marcos crescentes;
- tipos de evento emitidos por padrões específicos aparecem no schema;
- bucket é privado e permissões de leitura anônima não são concedidas no SQL versionado;
- blocos XAML extraídos são XML bem formado;
- instalador Python embute bytes esperados;
- utilitário de qualidade do simulador cobre alguns estados básicos;
- build web é gerável.

### O que os testes não comprovam

- parsing ou execução do PowerShell;
- transições reais da máquina de estados;
- solo/dupla/trio;
- retomada antes, durante e depois de cada checkpoint;
- interrupção entre participantes;
- unicidade lógica e qualidade por participante;
- corrupção/atomicidade da fila;
- falha parcial Storage OK/PostgREST falhou e vice-versa;
- autenticação e RLS reais;
- portal do instrutor;
- gerador web;
- acessibilidade por teclado/leitor de tela;
- DPI e resoluções Windows;
- integração com janela SPIKE;
- observabilidade e suporte em máquinas distribuídas.

### Débitos confirmados na própria automação

- README manda executar `npm run check`, mas esse script não existe;
- testes por busca de strings deram verde com motor não parseável;
- `getQualityStatus` do simulador usa mínimos padrão incompatíveis com 1–3 participantes;
- não há CI Windows obrigatória;
- não há teste que compare transições alcançáveis com telas/funções declaradas.

## 12. Síntese crítica de agy e Codex

### Consenso entre os revisores

agy e Codex convergiram nos pontos centrais:

- erro fatal no final do PowerShell;
- Portal do Instrutor sem autenticação real;
- avaliação anônima falsificável;
- senha hardcoded no gerador;
- fragilidade da fila offline;
- lacunas de acessibilidade;
- testes insuficientes;
- decisão NO-GO.

### Contribuições mais fortes do Codex

- identificou o cronômetro reiniciado na retomada;
- encontrou `$participants` não inicializado após retomada;
- demonstrou que troca de papéis e rubrica são código morto;
- encontrou contagem de recusas/timeouts como sessão completa;
- apontou a ausência de vínculo da avaliação do instrutor com sessão/grupo;
- detectou os fluxos inacessíveis e estados de acessibilidade do React/CSS.

### Contribuições mais fortes do agy

- destacou rapidamente o parse fatal, a autenticação fictícia e o `anon INSERT` da avaliação;
- chamou atenção para I/O integral da fila e para a chave persistida no ambiente;
- reforçou a diferença entre simulador controlado e telemetria real.

### Correções aplicadas na síntese

Nem toda observação dos agentes foi aceita literalmente:

- chave `anon` não deve ser tratada como segredo equivalente a `service_role`; o risco real é o poder concedido pelas policies e a possibilidade de abuso/forja;
- a existência de `member_4` no enum não é, por si só, falha atual. O defeito concreto é o motor aceitar somente dois papéis enquanto a UI oferece 1–3 pessoas;
- RLS insert-only protege leitura, mas não autenticidade. O relatório evita afirmar exposição de leitura sem evidência.

## 13. Plano de correção priorizado

### Fase 0 — interromper distribuição

1. Não publicar nem distribuir o ZIP/BAT atual.
2. Retirar ou rotular `/instrutor/` e `/instalador/` como protótipos não operacionais.
3. Preservar o working tree antes de qualquer correção; há alterações locais e artefatos não rastreados.

### Fase 1 — restaurar executabilidade

1. Corrigir o bloco final do agente.
2. Adicionar parser PowerShell 5.1 em CI Windows.
3. Executar smoke real de abertura/fechamento WPF.
4. Regerar payload e todos os instaladores somente depois do gate verde.

### Fase 2 — fechar contrato e máquina de estados

1. Definir contrato único para participantes, papéis, eventos e estados.
2. Corrigir matriz 1/2/3 ou, mais seguro para o piloto, limitar explicitamente a dupla até a matriz estar testada.
3. Tornar troca de papéis, rubrica e encerramento transições obrigatórias/alcançáveis.
4. Congelar contexto e configuração por sessão.
5. Corrigir retomada pelo tempo transcorrido.

### Fase 3 — integridade e segurança

1. Identidade por dispositivo/instalação e endpoint autenticado.
2. Policies vinculadas a claims, prefixos, MIME e tamanho.
3. Portal com Supabase Auth real e avaliação associada à sessão.
4. Qualidade baseada em participante/marco/status, não contagem bruta.
5. Assinar releases e eliminar execução de `main` mutável.

### Fase 4 — resiliência

1. Fila transacional/atômica com lock, backup, limites e recuperação.
2. Estado de evidência explícito e quality event em arquivo perdido.
3. Mutex de instância única.
4. Transporte fora do thread de UI e retry com backoff/jitter.
5. política de retenção e purge.

### Fase 5 — UX e validação de campo

1. Separar interfaces por público.
2. Corrigir foco, ARIA, modal, toast, tabs e teclado.
3. Testar Windows 10/11, 100/125/150% DPI e resoluções escolares.
4. Testar com participantes e instrutores, com protocolo ético aprovado.
5. Homologar online/offline, hibernação, restart e falha parcial.

## 14. Critérios de Go/No-Go

### Site informativo público

**GO condicional**, desde que links para portal/instalador sejam removidos ou claramente rotulados como demonstração e nenhuma promessa de gravação real permaneça.

### Simulador para demonstração interna

**GO condicional para demonstração técnica**, sem tratar os resultados como validação do agente real. Antes, corrigir as transições mortas e a matriz de participantes.

### Piloto controlado com dados sintéticos

**NO-GO agora.** Pode virar GO após P01, P02, P05, P06, P07, P09, P10, P11 e P12, seguido de smoke em Windows e Supabase de homologação.

### Piloto com crianças e coleta real

**NO-GO.** Além dos bloqueadores técnicos, requer autenticação de origem, retenção, revisão de screenshot/hostname, rastreabilidade do consentimento/assentimento, protocolo de incidente e validação ética/metodológica.

### Coleta acadêmica definitiva

**NO-GO.** Requer evidência de validade do instrumento, schema imutável por protocolo, integridade por participante/marco, dispositivo autenticado, auditoria de RLS, CI Windows, homologação offline e trilha de release assinada.

## 15. Conclusão

O PulseLab tem um conceito técnico promissor — eventos append-only, minimização de telemetria, idempotência e qualidade explícita são decisões boas. Porém, o produto atual está em estado de protótipo inconsistente: o motor não parseia; recursos metodológicos centrais não são chamados; portal e gerador simulam segurança/funcionalidade; e os testes validam presença de código, não execução.

A prioridade correta não é polir a interface. É restaurar executabilidade, unificar a máquina de estados, proteger integridade da coleta e construir testes de execução reais. Só depois UI e distribuição devem voltar a ser expandidas.
