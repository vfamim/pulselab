# Estrutura de Tese Científica (TCC) - Pulselab MMLA

Este guia descreve como estruturar o seu **Trabalho de Conclusão de Curso (TCC)** ou artigo de pesquisa científica com base nos resultados do Pulselab, preparando sua defesa para ser avaliada com nota máxima por uma banca acadêmica.

A grande inovação científica a ser defendida aqui é o **Protocolo de Coleta Multicêntrica Assegurada Sem Observador Presencial**, que mitiga vieses comportamentais e viabiliza a pesquisa em larga escala com custo logístico quase zero.

---

## 📘 1. Estrutura de Capítulos para o TCC

### Capítulo 1: Introdução
* **Contexto:** A popularização da robótica educacional (ex: LEGO SPIKE) e a necessidade de avaliar o aprendizado de forma científica e não invasiva.
* **O Problema de Pesquisa:** Métodos tradicionais de avaliação (como provas escritas e observadores humanos sentados ao lado dos alunos):
  1. Geram o **Efeito Hawthorne** (os alunos mudam o comportamento por saberem que estão sendo vigiados).
  2. Possuem baixa escalabilidade (um observador só consegue avaliar uma ou duas duplas por vez).
  3. Apresentam alto custo logístico e financeiro para abranger múltiplos polos regionais.
* **Objetivo Geral:** Validar um modelo de observabilidade multimodal distribuído e assíncrono para avaliar a carga cognitiva e o engajamento de alunos de robótica em larga escala, dispensando observadores locais.

### Capítulo 2: Fundamentação Teórica
* **Teoria da Carga Cognitiva (Sweller, 1988):** Divisão em carga intrínseca, pertinente e estranha. Como o block-based coding (Scratch) otimiza esses fatores.
* **Multimodal Learning Analytics (MMLA):** O cruzamento de múltiplos canais de dados (físicos, digitais e auto-relatos) para estudar o processo de aprendizagem ativa.
* **Robótica Educacional e Aprendizagem Colaborativa:** O equilíbrio de papéis (PC vs. Montagem Física) no desenvolvimento de competências socioemocionais.

### Capítulo 3: Metodologia (O Protocolo Pulselab)
* **Arquitetura de Coleta Distribuída:** Descrição de como o agente PowerShell roda nas máquinas de forma passiva, eliminando o fator de interferência do pesquisador presencial.
* **O Fluxo de Triangulação de Dados:**
  1. *Subjetivo (Auto-relato):* Pop-ups lúdicos programados de Carga Cognitiva nos minutos 20 e 40.
  2. *Comportamental (Telemetria):* Monitoramento ativo de processos em foco e inatividade do mouse/teclado.
  3. *Artefato de Código:* Registro do crescimento em bytes dos arquivos `.llsp` / `.spk`.
  4. *Evidência Visual:* Capturas de tela (screenshots) automáticas e comprimidas no milissegundo do popup.
* **Resiliência e LGPD:** Tratamento de dados offline em cache local e conformidade com RLS do Supabase para proteção da identidade dos estudantes.

### Capítulo 4: Resultados e Discussão (A Apresentação para a Banca)
* **Validação Quantitativa (Correlações):** Apresentar matrizes de correlação estatística (ex: correlação negativa entre inatividade e avanço de tamanho de arquivo; correlação positiva entre carga cognitiva relatada e estagnação de código).
* **Grounding Visual e Triangulação:** Demonstrar casos onde a telemetria acusou inatividade com carga alta e o screenshot provou um loop sem saída no LEGO SPIKE.
* **Mitigação do Efeito Hawthorne:** Provar que a ausência do observador presencial resultou em respostas mais honestas das crianças (comparando turmas históricas observadas manualmente com as turmas automatizadas).

### Capítulo 5: Conclusões
* **Síntese:** A viabilidade de um único pesquisador monitorar dezenas de turmas em múltiplos estados simultaneamente a partir de um único painel web.
* **Contribuição Pedagógica:** Recomendações curriculares baseadas em evidências multimodais de dificuldade de código.

---

## 🎯 2. Argumentos de Defesa para Impressionar a Banca

Se a banca questionar a robustez metodológica do projeto, você poderá utilizar estes três contra-argumentos científicos:

1. **"Como vocês garantem a confiabilidade do auto-relato de crianças?"**
   * *Resposta:* "Através do **Grounding Visual**. Cada resposta de carga cognitiva é pareada instantaneamente com um print screen comprimido do código no mesmo segundo do clique. Se uma criança clica em carga '1' (muito fácil) mas o print mostra a tela vazia ou código incompleto, ou se clica em '4' (muito difícil) e o print mostra um loop infinito mal programado, conseguimos realizar uma triangulação qualitativa dos dados para validar a acurácia das respostas."

2. **"Sem um pesquisador na sala, como sabemos se os alunos não estavam jogando ou distraídos?"**
   * *Resposta:* "O Pulselab rastreia o processo ativo do Windows em tempo real (`telemetry_foreground_app`). Se o aluno alternou para o navegador (Chrome/Edge) ou jogos, a telemetria sinaliza desvio de foco. Se o aluno ficou conversando sem programar, o sensor de ociosidade (`telemetry_idle_seconds`) registra inatividade acima de 300 segundos, mantendo a fidelidade comportamental."

3. **"A coleta distribuída não sofre com instabilidades de rede das escolas?"**
   * *Resposta:* "Desenvolvemos resiliência offline nativa. Caso a rede da escola sofra oscilações, os logs e os prints comprimidos são retidos em cache seguro na própria máquina (`C:\Users\Public\Pulselab\cache`) e retransmitidos de forma silenciosa assim que a rede restabelece ou na finalização do daemon (Marco 99), garantindo zero perda de dados de pesquisa."
