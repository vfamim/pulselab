# Revisão adversarial da PWA infantil — 4 de outubro de 2026

Base: `5390b52559431766f2e9810112d3e00ac846b09b`, versão 2.2.1. Trabalho local na branch `fix/ux-silent-student-flow`, sem publicação. As linhas da tabela referem-se à base, antes das alterações. Screenshots somente de dados sintéticos de QA, fora do repositório; nenhuma captura adicionada ao produto.

## Fase A — achados antes de editar

| Severidade | Evidência na base | Achado e consequência |
| --- | --- | --- |
| Alta | `web/agent-simulator/index.html:38`; `app/student-page.jsx:628–670` | `body` impõe `#f8fafc`. Participantes pendentes herdam texto quase branco no painel claro: **1,06:1**. Participantes aceitos: **4,26:1**. O título e a explicação vermelhos medem 5,83:1 e 7,49:1: não são a falha numérica principal, mas o vermelho comunica erro indevidamente. |
| Alta | `app/student-page.jsx:638,670` | Checkbox desmarcado já é descrito como recusa; confunde ausência de escolha com decisão voluntária. Dois botões fazem a mesma recusa. |
| Alta | `app/student-page.jsx:841–1067`; `app/globals.css:670` | Avaliação usa textos quase brancos em cartões brancos. Botão principal branco sobre `#0284c7`: **4,10:1**, insuficiente para o tamanho normal usado. |
| Alta | `app/student-page.jsx:2226–2361`; `app/globals.css:2242` | Topbar sem quebra adequada: largura real **491 px** no viewport de 390 px. Primeira ação abaixo da dobra: y=834,5 em 1280×720; y=791,5 em 1024×768; y=915,9 em 768×1024; y=1275,8 em 390×844. |
| Alta | `app/student-page.jsx:1881–1932,2266` | Retirada escondida sob “Reiniciar”, volta ao assentimento e aguarda operações assíncronas antes de bloquear coleta. Requisições em voo e outras abas podem regravar depois do expurgo. |
| Alta | `lib/evaluation.js:37–65`; `app/student-page.jsx:1179,2139`; `lib/student-store.js:241` | Restauração não valida idade do snapshot em localStorage. Expurgo só do IndexedDB permite ressuscitar sessão expirada. Limite usa `<`, e evento órfão prioriza sincronização sobre ocorrência. |
| Alta | `app/student-page.jsx:1736–1777,1800–1841` | Conclusão aguarda Bridge sem timeout e ignora falha ao salvar sessão no IndexedDB, apesar da promessa visual de salvamento seguro. |
| Média | `app/student-page.jsx:722–778,1565` | Cronômetro com `aria-live`, status e atualização de telemetria, pedido de notificações sem uso e funções de alerta órfãs. Distração e pressão sem papel pedagógico. |
| Média | `app/student-page.jsx:813–1069,2200` | Modo Livre entra em formulário de pesquisa sem poder responder às avaliações individuais. Rubrica do educador compete com a experiência da criança. |
| Média | `app/student-page.jsx:1103–1135,2277–2359` | IDs, versão, contadores, exportação e controles de laboratório expostos no fluxo normal; sincronização pode prometer nuvem apesar de envio desativado. |
| Média | `app/student-page.jsx:369,391–455,934–1057` | Sem foco no título após transições; grupos de rádio sem legend; foco de rádio oculto sem destaque no rótulo; modal depende de callback recriado a cada render. |
| Média | `app/student-page.jsx:1253–1257,60` | Mudança do tamanho conserva aceites de posições removidas; quiz começa “realizado” sem observação. |
| Média | `app/student-page.jsx:2102–2122` | Resultado assíncrono pode chegar depois da retirada/finalização; polling em updater React tem efeitos colaterais e propaga campo de inferência automática. |

Medição: Chromium local com bloqueio de rede externa. Cores calculadas por luminância sRGB, compondo transparências sobre a superfície real. Critério de texto: [WCAG 2.2, contraste mínimo](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html), 4,5:1 normal e 3:1 grande. Alvos de 44 px são requisito deste trabalho (mais rigoroso que o mínimo AA de 24 px com exceções). Não houve auditoria de conformidade legal nem uso de serviços/dados reais.

## Fases B/C

### Alterações implementadas

- Reescrita da jornada infantil para três telas curtas: início/assentimento, atividade e desafio final.
- Remoção do cronômetro visível, alertas, notificações, IDs, contadores e status técnicos do conteúdo principal.
- Estados de assentimento neutros, reversíveis e individuais, sem tratar ausência de escolha como recusa.
- Contraste textual corrigido; o menor contraste medido nas telas exercitadas foi **5,56:1**.
- Alvos interativos com pelo menos 44 × 44 px e foco visível.
- Foco enviado ao título principal após transições, reload e retirada.
- Ação inicial integralmente visível em 1280×720, 1024×768, 768×1024 e 390×844. Medições críticas: rodapé até y=717,58 em 1280×720 e y=810,27 em 390×844.
- Área do educador recolhida e separada visualmente do conteúdo infantil; ferramentas de laboratório aparecem somente com `?lab=1` e dados sintéticos são marcados.
- Linguagem de retirada alterada para “Parar de participar e apagar meus dados”.
- Relógio interno de retenção passa a começar apenas quando a sessão assentida realmente começa.
- Snapshots e eventos sem timestamp confiável são expurgados de forma fail-closed.
- Retirada agora cria tombstone durável no Bridge, impede reenvio, tenta exclusão remota autenticada e mantém fila persistente de retry.
- Nova RPC `purge_own_research_session(uuid)` limita a exclusão remota à instalação autenticada e ao site correspondente.
- Retenção institucional do banco passou a incluir `research_bancada_sessions`.

### Verificação independente

- **54/54 testes unitários** aprovados.
- **40/40 testes Playwright E2E** aprovados em Chromium.
- **43/43 asserções pgTAP** aprovadas em PostgreSQL descartável.
- Build Vite de produção aprovado e artefatos de `alunos/` regenerados.
- Verificador de consistência confirmou todas as superfícies na versão 2.2.2 (release preparada a partir da base 2.2.1).
- `git diff --check` aprovado; `bridge/pulselab-bridge.ps1` preservado em CRLF para Windows PowerShell 5.1.
- Retirada exercitada em duas abas, com resposta atrasada do Bridge, expurgo local, tombstone e contrato remoto restrito.
- Relógio de retenção testado após três dias de espera antes do assentimento e seis dias após o início efetivo.

### Limites da conclusão

- Os testes automatizados comprovam contraste textual, alvos, foco e ausência de overflow nos estados exercitados; **não equivalem a uma certificação completa de conformidade WCAG 2.2 AA**.
- A área do educador continua disponível na mesma página, porém recolhida. Uma separação por autenticação ou aplicação distinta exigiria mudança de produto e operação.
- A exclusão remota depende da aplicação da nova migração e de um JWT operacional válido. Sem conectividade, o Bridge conserva somente o identificador de retirada e repete a exclusão; o conteúdo retirado não volta à fila de sincronização.

### Resultado

Os bloqueadores encontrados nas revisões independentes — expurgo remoto, confirmação/retry durável, relógio iniciado antes do assentimento e ação inicial fora da dobra — foram corrigidos e cobertos por testes. A release local preparada para deploy é a 2.2.2 (PATCH), com todas as superfícies operacionais, testes e artefatos sincronizados. A branch está tecnicamente pronta para revisão humana final, permanecendo sem commit, merge ou deploy.
