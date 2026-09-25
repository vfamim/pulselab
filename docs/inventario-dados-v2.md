# Inventário de dados — v2 de teste

Fonte executável das perguntas: `web/agent-simulator/lib/protocol.js`.
O export inclui o manifesto completo, versão e SHA-256 desse conteúdo; códigos
v1 não são reutilizados para construtos que mudaram.

| Família | Campos/representação | Finalidade | Limite/minimização |
|---|---|---|---|
| Contexto | sede, escola, turma, oficina, instrutor por códigos; faixa escolar; plataforma | Agrupamento e fidelidade | Sem nomes, datas de nascimento, renda ou diagnósticos |
| Sessão | UUID da sessão/bancada, tamanho real, ambiente test | Vinculação intrassessão e exclusão de testes | Não identifica uma criança longitudinalmente |
| Assentimento | slots A–D e aceites na sessão aceita | Confirmar escolha de cada integrante | Recusa inicial não cria registro; não substitui processo ético |
| Experiência | none/some/all/unknown | Composição da bancada | Não é experiência individual nem competência |
| Confiança/esforço/participação/compreensão/intenção | categorias 1–4 separadas | Percepções coletivas | Sem escore psicológico global ou média presumida |
| Etapa/bloqueio/afeto | categorias nominais | Descrição do momento e experiência | Sem inferência emocional automática |
| Conhecimento | alternativas em dois itens pré e dois pós | Teste de alinhamento e compreensão dos itens | Formas não validadas/equiparadas |
| Papéis | slot estável e tarefa confirmada | Exposição descritiva | Não prova participação efetiva |
| Ajuda | pedido/reconhecimento/início/resolução | Descrever mediação e latência | Atendimento local, não sistema remoto de emergência |
| Artefato | contagens, categorias, versão do parser, horário e ID local | Descrição do arquivo selecionado | Sem arquivo bruto, nome, caminho, comentários, variáveis ou IDs de blocos |
| Resultado | tentativas bem-sucedidas 0–3; explicação 0–3 | Resultado imediato observado da bancada | Não é aprendizagem individual ou retenção |
| Implementação | intervenções, minutos de preparo, dificuldade, próxima ação | Custo parcial e utilidade pedagógica | Categorias fechadas; sem texto livre identificável |
| Tempo/qualidade | início real, prompts, respostas, antecipações, atrasos, recusas | Ônus e disponibilidade de evidências | Relógio do cliente; não garantia de execução física |

`null` significa item recusado; `no_consensus` significa ausência de resposta
conjunta. Campo/etapa ausente é outra situação. O parser rejeita formato não
suportado; ausência de artefato não vira “zero aprendizagem”.

Armazenamento: uma sessão inteira em uma transação do IndexedDB
`pulselab-test-bancada-v2`. Não há outbox, arquivo Bridge, nuvem, respostas em
localStorage ou varredura do computador. O histórico usa o mesmo registro, não
uma cópia independente. Prazo absoluto: sete dias desde a criação, sem extensão
por retomada. Apagar/retirar elimina esse registro com todos os eventos juntos.

A limpeza automática só executa com o app aberto. Exportações e backups do
próprio navegador/computador não podem ser apagados pelo aplicativo; devem
constar dos procedimentos do responsável. O armazenamento não é cifrado pela
aplicação e é acessível a quem usa o mesmo perfil do navegador. Por isso esta
branch admite somente dados fictícios e não promete anonimato absoluto.

O export é rastreável quanto à versão, mas não possui assinatura de origem:
não se apresenta como prova criptográfica de que uma oficina aconteceu.
Autenticidade científica e backend v2 exigem desenvolvimento/validação antes
de produção. A migração atual restringe o banco legado por dispositivo/sede.
