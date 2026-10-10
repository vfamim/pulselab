# Decisão de Arquitetura Ética: Coleta Silenciosa por Bancada Coletiva (Protocolo v2)

- **Data**: 10 de outubro de 2026
- **Status**: Implementado
- **Escopo**: Interface de Alunos (`/alunos/`), Configuração Institucional Fail-Closed e Modelo Coletivo de Bancada

---

## 1. Contexto e Motivação Ético-Metodológica

Durante as iterações anteriores do PulseLab, a interface de estudantes (`student-page.jsx`) apresentava telas interativas pré, durante e pós-oficina contendo formulários, perguntas de autoeficácia, escalas Likert, caixas de assentimento individual por membro (`memberAssents`) e avaliações individuais (`memberExperiences`, `member_index`).

Essa abordagem interativa gerava sérias fragilidades éticas e metodológicas:
1. **Governança Institucional, Ética e Jurídica (Art. 14 da LGPD e Diretrizes Éticas)**:
   - A realização de pesquisa acadêmica em ambiente escolar envolvendo crianças e adolescentes exige governança institucional, análise rigorosa do protocolo e validação ética e jurídica aplicável; a eventual necessidade de submissão e tramitação junto ao sistema CEP/CONEP depende do enquadramento regulatório, das diretrizes institucionais e do desenho da intervenção.
   - Autorizações escolares gerais ou termos de cessão de uso de imagem possuem finalidades estritamente separadas e **não cobrem** atividades de pesquisa científica, exigindo finalidade específica devidamente autorizada pela governança institucional.
   - Transferir formulários e caixas de seleção de "assentimento" para as crianças na tela do computador criava um ônus cognitivo artificial e uma falsa aparência de formalização, sem substituir os processos e validações prévios exigidos pelas instâncias responsáveis.
2. **Interrupção Pedagógica e Carga Cognitiva Estranha**:
   - As crianças frequentam a oficina para interagir com kits LEGO SPIKE Prime, montagem física e programação em blocos.
   - A exibição de formulários, botões e status técnicos desviava a atenção pedagógica da atividade prática.
3. **Falácia de Medição Individual em Atividade Colaborativa**:
   - Na bancada de robótica, o robô, os motores, os sensores e o projeto Scratch/Python são compartilhados coletivamente pela equipe (2 a 8 estudantes). Não existe "código individual" de uma única criança em um kit compartilhado.

---

## 2. Decisões Arquiteturais Adotadas

### 2.1 Rota Normal de Alunos Estritamente Silenciosa
- A rota pública acessada pelos estudantes (`http://127.0.0.1:43128/alunos/`) opera em modo estritamente silencioso:
  - **Zero formulários**: nenhuma pergunta ou campo de entrada de dados.
  - **Zero cartões de etapas ou botões interativos**: nenhum botão "Começar", "Avançar", "Concluir" para os alunos.
  - **Zero status técnicos ou identificadores**: nenhum UUID, código de computador ou contadores de fila visíveis aos estudantes.
  - **Zero avaliações infantis**: nenhuma escala de humor, emoticons ou notas individuais.
- **Fallback Não Interativo**:
  - A interface renderiza exclusivamente uma mensagem tranquila e neutra:
    > **“Oficina de robótica em andamento. Use o aplicativo LEGO SPIKE.”**
  - Os estudantes utilizam integralmente o software oficial LEGO SPIKE Prime sem qualquer distração ou atrito.

### 2.2 Diagnóstico Sintético Restrito Exclusivamente ao Laboratório (`?lab=1`)
- O modo sintético (`?lab=1`) é acessível exclusivamente por parâmetros explícitos de URL para engenheiros e pesquisadores em ambiente de desenvolvimento/teste.
- A rota normal de alunos não exibe nenhum elemento diagnóstico; todas as inspeções de estado da configuração, contadores do outbox local e ferramentas de teste de telemetria simulada e retirada ética ficam restritas ao parâmetro `?lab=1`.

### 2.3 Configuração Institucional Fail-Closed
A habilitação da observabilidade de pesquisa foi desacoplada de cliques de crianças e transferida para a configuração institucional validada:
- Arquivos de configuração (`config/defaults.json`, `config/config.json`) definem por padrão:
  - `research_collection_enabled = false`
  - `research_authorization_version = null`
  - `research_authorized_purposes = []`
- **Regra Estrita de Ativação**:
  A pesquisa acadêmica é autorizada **somente se TODOS** os critérios seguintes forem satisfeitos:
  1. `research_collection_enabled === true` (booleano estrito; strings como `"true"` ou truthy genérico são sumariamente rejeitadas);
  2. `research_authorization_version` for uma string não vazia identificando a versão da governança e protocolo institucional aprovado;
  3. `research_authorized_purposes` for um array contendo explicitamente a finalidade `"academic_research"`;
  4. `group_size` for um inteiro estrito entre `2` e `8` (garantindo que a unidade de observação seja a bancada coletiva).
- Se a configuração for ausente, inacessível ou inválida perante qualquer uma das quatro condições:
  - O sistema entra imediatamente em **Modo Livre interno**.
  - **Zero transmissão** (qualquer fila local de eventos é estritamente impedida de envio em segundo plano).
  - **Zero persistência** (nenhum evento de pesquisa é gravado em IndexedDB ou localStorage).

### 2.4 Inicialização Automática e Idempotente de Sessão
- Quando a configuração institucional é válida e autorizada:
  - Uma sessão coletiva de bancada é inicializada automaticamente em segundo plano.
  - Emite `session_started` com os dados coletivos da bancada (`group_size`, protocolo versionado).
- **Garantia de Idempotência no Reload**:
  - Caso o navegador seja recarregado durante a oficina, o sistema detecta o snapshot ativo já iniciado e restaura o estado sem emitir novo `session_started`.

---

## 3. Modelo Coletivo de Bancada e Campos Coletivos/Pseudonimizados

### 3.1 Eliminação Integral de Campos Individuais
Foram permanentemente abolidos do fluxo operacional, dos eventos e dos payloads:
- `memberAssents` (checkboxes de indivíduos);
- `memberExperiences` (notas ou respostas de integrantes específicos);
- `member_index` (índices numéricos de crianças na bancada);
- Questionários de autoeficácia ou esforço mental individual;
- `participant_id` individualizado (ex.: `PARTICIPANTE-A`, `PARTICIPANTE-B`).

### 3.2 Campos Coletivos/Pseudonimizados Residuais Mantidos
Para atender aos contratos de sincronização segura (Store-and-Forward), isolamento multi-tenant por sede e integridade científica, são mantidos exclusivamente os seguintes identificadores operacionais e metadados técnicos de natureza coletiva e pseudonimizada:

| Campo | Tipo / Origem | Justificativa Operacional e Salvaguarda |
| :--- | :--- | :--- |
| `session_id` | UUID v4 efêmero | Chave primária da sessão da bancada na oficina. Não vinculado a cadastro de estudante. |
| `group_id` / `dyad_id` | UUID v4 efêmero | Identificador da bancada coletiva (2 a 8 estudantes). Impossibilita isolar um indivíduo. |
| `installation_id` | UUID v4 por dispositivo | Identificador da instalação do PulseLab no computador da escola, exigido pelas políticas RLS. |
| `computer_id` | Derivado (`PC-XXXXXX`) | Prefixo pseudônimo derivado dos primeiros caracteres do `installation_id`. |
| `site_id` | Código institucional | Identificador do polo/sede regional (ex.: `Polo-Nordeste`) para particionamento RLS. |
| `school_code`, `workshop_code`, `class_code` | Códigos operacionais | Códigos genéricos da turma/oficina escolar (ex.: `turma-geral`, `oficina-spike`). |
| `group_size` | Inteiro (2 a 8) | Quantidade de integrantes trabalhando colaborativamente no mesmo kit robótico. |
| `protocol_version`, `client_version`, `config_hash` | Hash / String SemVer | Integridade metodológica e comprovação de auditoria de instrumentos versionados. |
| `spike_telemetry` | Objeto numérico/booleano | Métricas estruturais do projeto LEGO SPIKE (`executable_blocks`, contagem de pilhas, uso de motor/sensor). Não contém nomes de arquivos nem código Scratch/Python. |

---

## 4. Governança Institucional, Limites Jurídicos e Diretrizes Éticas

1. **Princípio da Minimização de Dados (LGPD Art. 6º, III e Art. 14)**:
   - Nenhum dado pessoal identificável de crianças (nome, foto, vídeo, áudio, biometria, e-mail, matrícula) é coletado, trafegado ou persistido em qualquer superfície do sistema. Os dados são estritamente coletivos e pseudonimizados por bancada.
2. **Retenção Absoluta de 7 Dias**:
   - Dados locais armazenados no IndexedDB (`pulselab-student-runner`) e no Bridge local Windows expiram irrevogavelmente em 7 dias a partir da criação, sendo purgados por rotinas atômicas.
3. **Direito de Revogação e Expurgo Imediato**:
   - O mecanismo de retirada ética (`withdrawSession` / `resetBridgeSession`) limpa imediatamente a sessão ativa, purga o banco local, remove identificadores temporários e registra tombstone durável que impede qualquer transmissão posterior.
4. **Isolamento de Rede Fail-Closed**:
   - Em ambiente sem credencial operacional de dispositivo ou sem autorização institucional ativa, qualquer envio para a nuvem é terminantemente bloqueado, garantindo operação offline-first integral em escolas municipais e estaduais.
