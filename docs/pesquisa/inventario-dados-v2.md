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
| Encerramento | `ended_by`: `instrutor`, `tempo` (limite de 3 horas) ou `sem_encerramento` (fechada pelo Bridge, p. ex. computador desligado por mais de 20 minutos) | Qualidade: separar turmas fechadas pelo instrutor das fechadas automaticamente | Sem dado pessoal |
| Continuidade | `interrupted`; sinal de vida (`heartbeat`) a cada 5 minutos; maior intervalo sem sinal; reinícios do Bridge | Saber se a coleta foi interrompida | Só horários técnicos |
| Pasta do SPIKE | `spike_status`: se a pasta de projetos foi encontrada | Distinguir "sem projeto" de "pasta ausente" | Sem nomes de arquivos ou caminhos pessoais |
| Estrutura do programa | por versão salva: contagem por tipo de bloco (`opcode_counts`), uso de motor, sensor, laço, condição, variável e procedimento, `structure_hash` | Descrever como o programa evoluiu | Nunca textos digitados (nomes de variáveis, mensagens, comentários), arquivo bruto ou nome do projeto |
| Escore de pensamento computacional | `ct_score`, adaptado de Dr. Scratch, marcado "adaptado, não validado" | Descrever a complexidade do programa | Mede o programa, não a criança |
| Cobertura da missão | `mission_coverage`: proporção dos elementos esperados presentes no programa final, só com calendário de missões configurado | Relacionar o programa à missão do dia | Sem calendário: ausente, não zero |
| Pergunta da bancada | 4 carinhas ou "Preferimos não responder" | Experiência coletiva da aula | Uma resposta por bancada; recusa não é ponto neutro |
| Itens do instrutor | resultado 0–3; apoio nenhum/algum/muito; ou pulado | Resultado prático e mediação | Sobre a bancada; pular não é zero |
| Turma não registrada | marca de exclusão: só o identificador da sessão apagada | Impedir que dados apagados voltem por pendrive ou reenvio | Não guarda motivo nem quem recusou |

Não registra: nomes, fotos, vídeo, áudio, teclas, cliques, captura de tela,
identificadores Bluetooth do hub, texto livre.

Armazenamento e prazo: no computador, pelo `retention_days` do pacote do polo
(padrão 180 dias, faixa de 1 a 365), mesmo depois de exportado ou enviado. Saída
por pendrive (atalho "PulseLab - Exportar Dados") ou envio à nuvem do projeto
quando a máquina está cadastrada e conectada. "Não registrar esta turma" apaga
os dados da turma atual naquele computador e grava a marca de exclusão.

Os dados são desidentificados, não anônimos: rótulo do computador e data,
combinados com informação da escola sobre quem sentou em cada bancada, podem
apontar para um grupo de crianças. Tratar como dados pessoais.

O armazenamento local não é cifrado pela aplicação e é acessível a quem usa o
mesmo perfil do Windows. Exportações em pendrive e cópias fora do PulseLab não
são apagadas pelo aplicativo; devem constar dos procedimentos do responsável.

A versão anterior deste inventário (branch de teste com aceites por
integrante, itens pré/pós e check-ins) está no histórico do git.
