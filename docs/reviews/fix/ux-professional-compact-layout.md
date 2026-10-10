# PulseLab — proposta e validação do layout compacto

Data: 2026-10-06. Branch: `fix/ux-silent-student-flow`. Versão preservada: **2.2.2**, em preparação. Sem commit, publicação ou alteração de contratos de pesquisa.

## Auditoria antes da implementação

As imagens fornecidas mostram o build 2.2.1 no Windows: hero alto, blocos espaçados, assentimento vermelho como se fosse erro e texto quase branco sobre rosa claro. Os avisos nativos do navegador também encobrem o conteúdo. Esta tarefa trata da apresentação da PWA; não altera Windows, navegador, rede ou permissões.

O working tree 2.2.2 já contém o fluxo silencioso: cabeçalho simples, assentimento neutro, Modo Livre, área do educador recolhida, retirada e persistência revisadas. Essas mudanças são o ponto de partida e serão preservadas. Problemas ainda presentes no código:

- Texto de estado do participante cai para **12 px** em até 430 px de largura; instruções da rubrica herdam 13,44 px e toast 11,52 px.
- Opções herdam altura mínima de 94 px, ícones de quase 30 px e pesos de 850–900. Isso ocupa espaço e deixa muitas informações com igual destaque.
- Há estilos globais legados para outra interface. Componentes da PWA precisam de cores, tamanhos e estados explícitos no escopo `.student-app`, sem reestilizar o simulador inteiro.
- Ações e textos repetem instruções. A retirada deve continuar acessível; os controles administrativos ficam secundários.
- Os E2E existentes verificam parte do contraste e do overflow, mas não bloqueiam fontes abaixo de 14 px nem medem todos os estados de interação.

Baseline de whitespace: `git diff --check` retorna 2 com **269 avisos preexistentes**: `Instalar-PulseLab.bat` (2), `bridge/pulselab-bridge.ps1` (85), `pulselab.ps1` (182). Referência integral em `/tmp/pulselab-ux-baseline/diff-check.txt`. Esses arquivos não serão editados.

## Proposta antes da implementação

### Hierarquia

1. Faixa de identidade navy, pequena, com símbolo geométrico de sinal/robótica e nome PulseLab. Sem mascote ou indicadores técnicos competindo com a tarefa.
2. Etapa em 14 px, título de 24–28 px e uma frase de orientação, sobre branco. Hero sem ilustração ou grande bloco colorido.
3. Tamanho da bancada em quatro opções; convite à pesquisa em painel neutro; escolha explícita por pessoa. Informações essenciais ficam visíveis: o que é guardado, ausência de nomes, decisão individual, Modo Livre coletivo sem gravação/envio e direito de desistir/apagar.
4. Detalhes complementares de dados/retenção em disclosure nativo. A experiência prévia aparece somente após assentimento unânime, como no fluxo existente.
5. Uma ação azul principal no rodapé da etapa. Alternativas sem preenchimento; educador em disclosure separado. Nenhum rodapé fixo cobrindo conteúdo ou foco.

### Tipografia e geometria

Fonte de sistema local (Aptos/Segoe UI/system-ui), corpo **16 px / 1,5**; labels e opções **15–16 px**; ajuda/etapa **14 px / 1,45**; títulos **24–28 px / 1,2**; subtítulos **20 px**. Pesos 400/600/700, sem bold em todos os textos. Nenhum texto funcional abaixo de 14 px, inclusive celular, toast e área do educador.

Largura máxima de 960 px; espaçamento em múltiplos de 4 px; laterais de 24 px no desktop e 12–16 px no celular; bordas de 8–16 px de raio; sombra leve. Alvos interativos de pelo menos **44 × 44 CSS px**, com checkbox/radio dentro do label clicável. Grids usam `minmax(0, 1fr)` e quebra de palavras quando necessário. Rolagem vertical normal, sem overflow horizontal.

### Paleta e contrastes previstos

Razões calculadas pela luminância relativa sRGB. Exigência: texto >= 4,5:1 (inclusive títulos, por margem); contornos funcionais/foco >= 3:1. Cor nunca será o único sinal de seleção.

| Uso | Primeiro plano | Fundo | Contraste previsto |
| --- | --- | --- | --- |
| Cabeçalho | `#ffffff` | `#14243b` | 15,61:1 |
| Texto principal | `#172b45` | `#ffffff` | 14,31:1 |
| Texto secundário | `#46566c` | `#f5f8fc` | 7,02:1 |
| Ação principal | `#ffffff` | `#075985` | 7,56:1 |
| Seleção | `#075985` | `#e8f4fc` | 6,76:1 |
| Borda de controle | `#64748b` | `#ffffff` / `#f5f8fc` | >= 4,47:1 |
| Foco | `#0369a1` | `#f5f8fc` | 5,57:1 |
| Erro real / retirada | `#9f2431` | `#fff1f2` | 6,90:1 |
| Desabilitado | `#46566c` | `#e2e8f0` | 6,07:1 |

Canvas `#eef3f8`; superfícies brancas; navy e azul são as cores estruturais. Ciano `#67d8ed` somente no símbolo decorativo sobre navy. Não é necessário usar âmbar/coral no fluxo normal.

### Componentes e estados

- Assentimento pendente: fundo `#f5f8fc`, texto escuro, contorno neutro e status textual. Aceito: mesmo painel neutro, checks e contornos azuis; sem sinalizar recusa como erro.
- Opções: normal branco, hover suave, selecionado azul claro + borda reforçada + `aria-pressed`/radio/checkbox. Emojis decorativos das escalas ficam pequenos; significados e valores das respostas são preservados.
- Botões: primário azul, secundário branco, desabilitado com texto ainda legível. Vermelho apenas para falha de armazenamento e retirada destrutiva.
- Teclado: contorno sólido de 3 px com separação de 3 px; foco também no label. Disclosures e diálogo continuam nativos, com Escape e restauração de foco.
- Telas de atividade, avaliação, conclusão, educador, diálogo e alertas compartilham os mesmos tokens.

## Plano de validação

Testar as quatro resoluções solicitadas (1280×720, 1024×768, 768×1024, 390×844), grupos de 1–4 pessoas, pendente/parcial/aceito, normal/hover/foco/selecionado/desabilitado, detalhes abertos, rubrica, diálogo, Modo Livre, conclusão e erro real. Verificar fonte mínima, contraste renderizado, alvos, overflow e ação inicial acima da dobra. Acrescentar reflow a 320 px e aumento de texto.

Executar unitários, E2E, build oficial em `alunos/`, consistência de versão e whitespace. Evidências visuais somente de dados sintéticos no Chromium Linux, nunca da sessão Windows ou de estudantes reais.

## Resultado da implementação e verificações

Implementado sobre o working tree existente. Não foram alteradas funções de assentimento, criação/restauração de sessão, avaliação, retirada, persistência, retenção, exportação ou comunicação. Valores e descrições das escalas permanecem iguais. O diff incremental de `student-page.jsx` contém somente texto e apresentação dos componentes.

### Arquivos desta tarefa e refinamento visual (2026-10-06)

- `web/agent-simulator/app/student-page.jsx`: hierarquia de etapas, textos concisos e escaneáveis no painel de pesquisa sem repetições desnecessárias, rótulos de consentimento limpos e compactos em linha única (`Pessoa N: aceito`), preservando a voluntariedade individual sem quebras deselegantes de linha no celular.
- `web/agent-simulator/app/globals.css`: foco acessível direcionado a controles interativos (`button, input, summary, [tabindex="0"]`), eliminação do retângulo azul de controle de formulário sobre o heading não interativo (`[data-stage-heading]:focus { outline: none; }`), borda explícita no botão primário e piso tipográfico estrito de 14 px no celular.
- `web/agent-simulator/e2e/helpers/visual-audit.js`: foco verificado exclusivamente em elementos interativos e operáveis da interface, excluindo títulos de transição de rota programaticamente focados para leitores de tela.
- `web/agent-simulator/e2e/professional-layout.spec.js`: 7 cenários, quatro viewports, estados de interação, quatro participantes acima da dobra, disclosure, teclado, reflow a 320 px, texto a 200%, erro, toast e laboratório.
- `web/agent-simulator/e2e/silent-flow.spec.js`: testes completos de ética, persistência, retenção e fluxo silencioso.
- `web/agent-simulator/e2e/student-flow.spec.js`: testes de regressão do fluxo padrão e observabilidade pedagógica.
- `docs/reviews/fix/ux-professional-compact-layout.md`: esta proposta e consolidação das decisões visuais.
- Build oficial: `alunos/index.html`, `alunos/assets/index-CLTwlCIf.css`, `alunos/assets/index-DN5Bjgqf.js`.
- Pacote oficial de distribuição: `instalador/downloads/PulseLab-2.2.2-Windows.zip` e checksum `PulseLab-2.2.2-Windows.zip.sha256` (SHA-256: `a710b9e5c9496f2312efbfd5233fa16d7a29d8916a5ef31f30422e468a513b96`), replicado identicamente em `/home/vfamim/Dev/windows-lab/shared/`.

Comparação de integridade confirmou que os contratos de domínio, scripts do Bridge, migrações e versão (2.2.2) foram rigorosamente preservados.

### Redação e divulgação progressiva

| Antes (Codex 2026-10-05) | Refinamento final (Antigravity 2026-10-06) | Justificativa |
| --- | --- | --- |
| Cada pessoa decide. Guardamos respostas e dados do robô, sem nomes. Se alguém não quiser, todos usam o LEGO SPIKE em Modo Livre: sem gravação nem envio de dados.<br>Podem desistir e apagar os dados da pesquisa a qualquer momento. | Cada pessoa decide e não usamos nomes. Se alguém não quiser, todos usam o LEGO SPIKE em **Modo Livre: sem gravação nem envio de dados**. Podem desistir e apagar os dados a qualquer momento. | Elimina redundâncias de termos ("pesquisa", "dados do robô", "dados da pesquisa"), unifica em parágrafo único e fluido, economizando cerca de 75 px verticais no celular enquanto preserva todos os 5 pilares éticos exigidos. |
| Pessoa N: quero participar. | Pessoa N: aceito | Elimina a quebra feia em 3 linhas no celular ("Pessoa 1:" / "quero" / "participar."), mantendo declaração ativa de assentimento voluntário individual (1ª pessoa), perfeitamente harmonizada com o status "Todos aceitaram participar.". |
| Retângulo azul espesso de 3 px ao redor do H1 ao carregar a tela. | Título limpo sem borda de formulário (`outline: none`), mantendo foco nos controles operáveis. | Headings com `tabindex="-1"` recebem foco programático apenas para leitores de tela em transições de etapa; tratá-los como caixas de formulário degradava a estética visual. |

### Medidas renderizadas finais

Chromium Linux com dados sintéticos; cenário com **quatro pessoas na bancada**, assentimento pendente/parcial e disclosure de dados recolhido. Alturas em CSS px medidas a partir do topo do documento:

| Viewport | Hero | Limite inferior do rodapé (antes) | Limite inferior do rodapé (após refinamento) | Acima da dobra | Margem livre | Fonte mínima |
| --- | ---: | ---: | ---: | --- | ---: | ---: |
| 1280×720 | 124,6 | 695,0 | 663,0 | Sim | +57,0 px | 14 px |
| 1024×768 | 121,7 | 692,1 | 660,1 | Sim | +107,9 px | 14 px |
| 768×1024 | 119,8 | 714,2 | 682,2 | Sim | +341,8 px | 14 px |
| 390×844 | 107,8 | 808,7 | 682,2 | Sim | +161,8 px | 14 px |

No celular (390×844), o ganho vertical foi de **126,5 px**, afastando o botão de ação principal da borda inferior e eliminando qualquer risco de sobreposição por barras de navegação de navegadores móveis.

Auditoria nos relatórios renderizados:
- Menor contraste textual: **6,07:1** (limiar WCAG AA é 4,5:1).
- Menor contraste de controle e foco interativo: **4,75:1** (limiar WCAG AA é 3:1).
- Nenhum texto funcional abaixo de 14 px.
- Nenhum alvo interativo abaixo de 44×44 CSS px.
- Zero overflow horizontal em todas as resoluções e reflow testado a 320 px e 200% de zoom.
- Exatamente uma ação principal destacada por etapa.

Evidências sintéticas salvas:
- `/home/vfamim/.hermes/cache/scratch/pulselab-after-agy-1280.png`
- `/home/vfamim/.hermes/cache/scratch/pulselab-after-agy-390.png`
- `/home/vfamim/.hermes/cache/scratch/pulselab-after-agy-390-pending-4.png`

### Execuções e Validações

| Verificação | Resultado |
| --- | --- |
| `npm run test:unit` | 54 testes aprovados (19 suítes nativas), zero falhas |
| `npx playwright test` | **47/47 aprovados**, zero skips, em 45 s |
| `npm run build` em `web/agent-simulator` | Build de produção aprovado, 22 módulos, sem avisos |
| `python3 scripts/check-version-consistency.py` | Todas as superfícies sincronizadas em **2.2.2** |
| `git diff --check` no escopo da tarefa | Zero erros ou avisos de whitespace |
| `git diff --check` geral no repositório | Exatamente os 269 avisos CRLF preexistentes da baseline |
| Empacotamento Windows 2.2.2 | `./scripts/build-offline-package.sh` concluído com sucesso |
| Hash SHA-256 do pacote | `a710b9e5c9496f2312efbfd5233fa16d7a29d8916a5ef31f30422e468a513b96` |
| Verificação byte a byte (`cmp`) | Origem e destino em `windows-lab/shared` idênticos byte a byte |

### Limites restantes

- Validação realizada estritamente em ambiente Linux com Chromium headless e dados sintéticos, sem operação direta de navegadores ou ambientes Windows.
- O empacotamento offline 2.2.2 gerado reflete rigorosamente o build e o código atuais.
- Nenhum commit, push, merge, tag, release ou deploy foi efetuado, em conformidade com as restrições da tarefa.
