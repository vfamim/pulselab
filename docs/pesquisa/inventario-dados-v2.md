# Inventário de dados — v2 (a partir da 2.4.0)

O que o PulseLab registra quando a coleta está ligada pelo pacote do polo.
Fonte dos itens de encerramento: `apps/student-pwa/lib/contracts.js`
(manifesto do instrumento, com versão e SHA-256). Protocolo:
[protocolo v2](protocolo-pesquisa-v2.md). Assentimento:
[assentimento verbal](../campo/assentimento-verbal.md).

| Família | Conteúdo | Finalidade | Limite/minimização |
|---|---|---|---|
| Contexto | polo, escola, oficina e turma por códigos (`nao_informado` quando ausentes) | Agrupamento e fidelidade | Sem nomes de crianças, datas de nascimento, renda ou diagnósticos |
| Máquina | `installation_id` aleatório e rótulo escolhido na instalação | Identificar a bancada/computador e separar polos | Nunca nome do Windows, do usuário ou caminhos pessoais |
| Sessão | identificador aleatório da sessão, início e fim, versões de protocolo, instrumento e software | Delimitar a turma e rastrear versões | Não identifica criança nem acompanha ninguém entre aulas |
| Encerramento | `ended_by`: `instrutor`, `tempo` (limite de 3 horas), `sem_encerramento` (fechada pelo Bridge, p. ex. computador desligado por mais de 20 minutos) ou `inatividade` (40 minutos sem nova versão de programa salva no SPIKE, contados da última versão salva ou, sem nenhuma, do início da turma) | Qualidade: separar turmas fechadas pelo instrutor das fechadas automaticamente | Sem dado pessoal |
| Continuidade | `interrupted`; sinal de vida (`heartbeat`) a cada 5 minutos; maior intervalo sem sinal; reinícios do Bridge | Saber se a coleta foi interrompida | Só horários técnicos |
| Pasta do SPIKE | `spike_status`: se a pasta de projetos foi encontrada | Distinguir "sem projeto" de "pasta ausente" | Sem nomes de arquivos ou caminhos pessoais |
| Estrutura do programa | por versão salva: contagem por tipo de bloco (`opcode_counts`), uso de motor, sensor, laço, condição, variável e procedimento, `structure_hash` | Descrever como o programa evoluiu | Nunca textos digitados (nomes de variáveis, mensagens, comentários), arquivo bruto ou nome do projeto |
| Escore de pensamento computacional | `ct_score`, adaptado de Dr. Scratch, marcado "adaptado, não validado" | Descrever a complexidade do programa | Mede o programa, não a criança |
| Cobertura da missão | `mission_coverage`: proporção dos elementos esperados presentes no programa final, só com calendário de missões configurado | Relacionar o programa à missão do dia | Sem calendário: ausente, não zero |
| Pergunta da bancada (legado) | 4 carinhas ou "Preferimos não responder" | Experiência coletiva da aula | Aceita pela rota de encerramento, sem tela desde a 2.4.0 |
| Itens do instrutor (legado) | resultado 0–3; apoio nenhum/algum/muito; ou pulado | Resultado prático e mediação | Aceitos pela rota de encerramento, sem tela desde a 2.4.0 |
| Questionário do fim da aula: bancada | evento `bancada_result_recorded`, um por pergunta (1 a 3): linha preta até o fim (`sim`, `em_parte`, `nao`), corrida (`ganhamos`, `terminamos_sem_ganhar`, `nao_terminamos`, `nao_participamos`), jogo de perguntas (`quase_todas`, `metade`, `poucas`, `sem_quiz`) ou `recusou` | Resultado prático dos testes com os carrinhos | Respondido pela bancada junto, uma vez por aula (o bridge recusa o segundo envio) |
| Questionário do fim da aula: crianças | evento `student_feedback_recorded`, um por pergunta (4 a 8): gostou da aula, quer outra aula, autoconfiança antes e agora, ajudou na bancada; `sim`, `mais_ou_menos`, `nao` ou `recusou` | Percepção das crianças e mudança de autoconfiança (6 contra 7) | Sem nome e opcional (desidentificado, não anônimo; linha a linha só o pesquisador lê): sem nome, idade, texto livre ou ordem de quem respondeu; "Não quero responder" em toda pergunta; a escolha não fica na tela |
| Metadados das respostas | `item_id`, `value`, `refused`, `instrument_version` (`bancada-3.2.0`), `submission_id` (código aleatório gerado na aba a cada rodada), `item_order`, `session_active`, `minutes_since_session_start` | Parear as respostas da mesma rodada (6 e 7), separar aula em andamento de aula encerrada e sinalizar respostas tardias | `submission_id` não se repete entre rodadas nem entre aulas: não acompanha a criança; nada fica guardado no navegador. Nas respostas das crianças o horário gravado é o do início da aula, sem `minutes_since_session_start`, para que o horário não ligue a rodada a uma criança |
| Aula não autorizada | `authorization_status = "nao_autorizada"` e `marked_at` no snapshot da sessão; `sessions_unauthorized.txt` no computador (`session_id` e data da marcação); `research_unauthorized_sessions` na nuvem | Garantir que a aula recusada nunca entre em relatório ou análise até a revisão do pesquisador | Não guarda motivo nem quem recusou; restauração exige motivo registrado pelo pesquisador |
| Aula apagada na revisão | marca de exclusão (`research_withdrawals` na nuvem, `withdrawn_sessions` no SQLite): só o identificador da sessão apagada | Impedir que dados apagados voltem por pendrive ou reenvio | Não guarda motivo nem quem recusou |

Não registra: nomes, fotos, vídeo, áudio, teclas, cliques, captura de tela,
identificadores Bluetooth do hub, texto livre.

Questionário do fim da aula: a bandeja abre a aba `http://127.0.0.1:43128/alunos/`
uma vez quando o PulseLab inicia, só com a coleta ativa; o atalho "Questionário
PulseLab" reabre a aba. As respostas vão para a aula ativa ou, sem ela, para a
última encerrada (o mesmo alvo de "Não registrar esta turma"). Em Modo Livre, com o
registro pausado, em aula marcada como não autorizada ou sem aula, nada é gravado e
a aba só agradece. Uma rodada abandonada no meio (2 minutos sem toque) é
descartada. No relatório, as respostas aparecem somadas por polo e mês.

Armazenamento e prazo: no computador, pelo `retention_days` do pacote do polo
(padrão 180 dias, faixa de 1 a 365), mesmo depois de exportado ou enviado. Aula que
passou do prazo sem ter saído do computador (nem pela nuvem nem por pendrive)
continua guardada até sair, no máximo até 31/12/2032; depois dessa data tudo é
apagado. Na nuvem, os dados ficam até 31/12/2032 (`research_archive_deadline`). Saída
por pendrive (atalho "PulseLab - Exportar Dados") ou envio à nuvem do projeto
quando a máquina está cadastrada e conectada.

"Não registrar esta turma" marca como não autorizada a aula em andamento ou, sem
ela, a última aula encerrada (se outra não começou depois). Nada é apagado na hora:
há polos sem internet que entregam o pendrive meses depois, então não existe prazo
automático para apagar. A aula marcada segue para a nuvem ou para o pendrive com a
marca e fica fora de todas as views de análise e de qualidade
(`research_session_is_authorized`) e das views `*_autorizad*` do SQLite
consolidado. O pesquisador, único com acesso aos dados, revisa as aulas marcadas
com `tooling/data/revisar-nao-autorizadas.py`: o padrão é apagar (nuvem e SQLite,
com marca de exclusão contra reenvio); restaurar exige motivo, que fica gravado. A
cópia no computador da bancada segue a retenção normal.

Os dados são desidentificados, não anônimos: rótulo do computador e data,
combinados com informação da escola sobre quem sentou em cada bancada, podem
apontar para um grupo de crianças. Tratar como dados pessoais.

O armazenamento local não é cifrado pela aplicação e é acessível a quem usa o
mesmo perfil do Windows. Exportações em pendrive e cópias fora do PulseLab não
são apagadas pelo aplicativo; devem constar dos procedimentos do responsável.

A versão anterior deste inventário (branch de teste com aceites por
integrante, itens pré/pós e check-ins) está no histórico do git.
