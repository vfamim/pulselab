# 🚀 PulseLab: Revelando a Jornada Invisível da Robótica Educativa

---

## 1. O que é o PulseLab?
O **PulseLab** é uma infraestrutura inovadora de **Observação Distribuída** e **Multimodal Learning Analytics (MMLA)** projetada para abrir a "caixa-preta" da aprendizagem prática. 

Mais do que um simples coletor de dados, o PulseLab é uma fundação de controle de qualidade e rigor metodológico para pesquisas acadêmicas e avaliações pedagógicas em larga escala. Ele roda de forma leve e silenciosa nos computadores dos alunos, capturando autorrelatos dinâmicos, métricas de colaboração e evidências visuais de código (Visual Grounding) no exato instante em que o aprendizado acontece.

---

## 2. O Problema que Ele Resolve: A "Caixa-Preta" da Oficina
Nas pesquisas tradicionais de robótica educacional e Aprendizagem Baseada em Projetos (PBL), a avaliação costuma focar em dois extremos: **questionários antes da aula** e o **resultado final da montagem** (se o robô funcionou). 

Esse modelo tradicional deixa uma lacuna científica crítica:
* **Viés de Memória (Recency Effect):** No questionário final, o aluno tende a reportar apenas a sensação dos últimos minutos da oficina (o sucesso ou frustração do teste final), esquecendo gargalos importantes ocorridos no meio da atividade.
* **Efeito Hawthorne e Custo Logístico:** Enviar pesquisadores com pranchetas para observar e anotar o comportamento das crianças altera a dinâmica natural do grupo (os alunos agem de forma diferente por se sentirem vigiados) e torna a pesquisa em múltiplas escolas financeiramente inviável.
* **Opacidade Processual:** Sem dados empíricos do processo, não há como saber quando a dupla travou, quem realmente programou, ou quantas vezes o professor precisou intervir.

**O PulseLab resolve isso ao atuar como um observador neutro, não invasivo e distribuído em tempo real.**

---

## 3. Como Funciona?
O PulseLab opera de forma simples e fluida em 4 etapas:

1. **Setup Sem Fricção (2 Cliques):** A escola recebe um pacote ZIP com parâmetros de sede e chaves criptográficas já embutidos. O instrutor clica em um atalho na Área de Trabalho e insere apenas o código da turma e o tamanho do grupo (se são duplas, trios ou alunos solo).
2. **Coleta Atômica (Checkpoints 20' e 40'):** Enquanto os alunos programam nos kits LEGO® SPIKE™, o agente monitora a atividade em segundo plano. Exatamente aos 20 e 40 minutos da oficina real, o PulseLab exibe pop-ups lúdicos de 20 segundos solicitando um autorrelato rápido da experiência.
3. **Visual Grounding Imediato:** No milissegundo em que o aluno responde ao checkpoint, o agente realiza um screenshot atômico da tela do LEGO SPIKE. Isso permite associar cientificamente o estado psicológico do aluno (ex: frustração ou facilidade) com o código real que ele estava construindo naquele instante.
4. **Resiliência Offline:** Se a internet da escola oscilar ou cair, todos os dados e capturas de tela são enfileirados localmente em um cache seguro. Quando a conexão retorna, a sincronização com o banco de dados Supabase na nuvem ocorre automaticamente, garantindo zero perda de dados.
5. **Portal do Instrutor:** Uma área dedicada de avaliação para o professor analisar a performance geral e a didática de forma externa, sem poluir a experiência dos alunos na máquina.

---

## 4. Por que Essas Perguntas? (E que respostas elas nos trazem)

O PulseLab não faz perguntas genéricas. Cada questionamento é cientificamente fundamentado para gerar métricas tratáveis quantitativamente em R, Python ou SPSS:

### As Perguntas e suas Justificativas:
* **"Antes de hoje, você já tinha programado?" / "Eu acho que consigo fazer um robô cumprir uma missão":**
  * *Por quê?* Mede a **autoeficácia percebida** antes e depois do evento para calcular o impacto real da oficina no senso de capacidade do aluno ($\Delta E$).
* **"Quanto você precisou pensar para fazer a parte em que estava agora?":**
  * *Por quê?* Avalia a **Carga Cognitiva** (baseada na Teoria da Carga Cognitiva de Sweller, 1988), classificando se o esforço foi ideal, insuficiente ou excessivo.
* **"Desde a última pergunta, nós dois tivemos oportunidade de dar ideias?":**
  * *Por quê?* Mede a percepção subjetiva de **colaboração e equidade** no grupo.
* **"Neste momento, você esteve mais no Computador/Programação, na Montagem ou em Ambos?":**
  * *Por quê?* Mapeia a **divisão real de papéis** e identifica desequilíbrios na dinâmica do grupo (ex: um aluno monopolizando o teclado).

### Exemplos do que o PulseLab nos Permite Responder:
* 💡 *“Alunos que passam 80% do tempo exclusivamente na montagem física apresentam o mesmo ganho de autoeficácia que aqueles que controlam o código?”*
* 💡 *“Picos de esforço mental excessivo no checkpoint de 20 minutos (fase de desenvolvimento) estão correlacionados com desistências ou frustrações severas registradas na autoavaliação final?”*
* 💡 *“A percepção de colaboração diminui quando o tamanho do grupo aumenta de dupla para trio na robótica educativa?”*

---

## 5. Conclusão: Iluminando a Jornada
O PulseLab transforma a subjetividade de uma oficina de robótica em dados concretos, auditáveis e cientificamente robustos. Em conformidade com a LGPD por design (sem biometria, sem coleta de áudio, sem títulos de janelas pessoais e com dados pseudonimizados), o sistema resguarda a ética estudantil ao mesmo tempo em que fornece aos pesquisadores o controle de qualidade necessário.

**Em suma, o PulseLab não julga o aluno nem substitui o professor: ele ilumina a jornada invisível do aprendizado.**
