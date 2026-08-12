# 📘 Texto Explicativo da Última Sessão & Roteiro para o Google Slides

> **Apresentação:** PulseLab v1.4.0 — Fundação de Observação Distribuída e MMLA para Robótica Educativa  
> **Link da Apresentação do Usuário:** [Google Slides - PulseLab Presentation](https://docs.google.com/presentation/d/17QKRj2Fc39wnWUDHPcAK2PBHKrpSSSSdNpe0CJWoicg/edit#slide=id.g3f6e972cc8a_2_66)

---

## 📑 Texto Explicativo Completo (Resgatado da Última Sessão)

### 1. Justificativa Científica & O Problema da "Caixa-Preta" (*Black Box Problem*)
Nas pesquisas de Robótica Educacional (RE) e Aprendizagem Baseada em Projetos (PBL), um dos maiores desafios metodológicos é a **"Caixa-Preta" da Oficina**. Tradicionalmente, as pesquisas avaliam a robótica escolar observando apenas o **resultado final da montagem** (o robô pronto) ou aplicando **questionários pós-evento**.

Esse modelo tradicional apresenta 3 grandes entraves científicos:
1. **Viés de Memória (Recency Effect):** O estudante responde ao questionário final lembrando apenas dos últimos minutos da aula, ignorando picos de sobrecarga ou frustração ocorridos no meio da atividade.
2. **Efeito Hawthorne & Alto Custo Logístico:** A presença de um observador físico anotando o comportamento das crianças altera a dinâmica natural da dupla e é inviável financeiramente para cobrir múltiplas escolas.
3. **Opacidade do Processo Intrassessão:** Não é possível determinar quantitativamente quando o grupo travou, qual integrante operou o código, ou quantas vezes o instrutor interveio.

---

### 2. A Solução PulseLab (v1.4)
O **PulseLab** foi projetado para solucionar empiricamente essa lacuna. Ele atua como uma **fundação de observação distribuída e controle de qualidade**, capturando autorrelatos pseudonimizados nos minutos exatos **20 e 40 (checkpoints absolutos)** das oficinas com kits LEGO SPIKE.

**Diferenciais Metodológicos:**
* **Checkpoints Absolutos (20' e 40'):** O cronômetro é calculado a partir do início real da atividade; o tempo gasto no primeiro formulário não adia intencionalmente o segundo.
* **Tamanho Dinâmico de Grupo:** O sistema pergunta quantos alunos estão naquele computador (`1` Solo, `2` Dupla, `3` Trio, `4` Grupo de 4).
* **Autorrelato de Papel Real:** O aluno seleciona em qual parte esteve mais tempo (`Computador / Programação`, `Montagem`, ou `Um pouco dos dois`), registrando a divisão real de trabalho.
* **Separacao do Portal do Instrutor (`/instrutor/`):** A avaliação do instrutor é feita por web app próprio no celular/tablet, liberando os alunos para um encerramento direto e gratificante.

---

### 3. Taxonomia de Métricas Quantitativas (MMLA)
O PulseLab transforma vivências em sala de aula em variáveis numéricas prontas para análise inferencial em R, Python (SciPy/Statsmodels) e SPSS:

* **Delta de Autoeficácia Percebida ($\Delta E$):** $\Delta E = E_{\text{post}} - E_{\text{pre}}$, medindo a evolução da percepção de capacidade antes e depois da oficina.
* **Índice de Esforço Mental Percebido ($M_{\text{effort}}$):** Escala ordinal de 1 a 4 fundamentada na Teoria da Carga Cognitiva (Sweller, 1988).
* **Grounding Visual & Telemetria:** No exato milissegundo em que o aluno responde ao checkpoint, o agente realiza uma captura atômica da janela do aplicativo LEGO SPIKE e registra a inatividade minimizada.
* **Métricas de Qualidade da Sessão (`research_session_quality`):** Rastreio auditável de latência de exibição, recusas éticas (*declines*), timeouts e sincronização do cache offline.

---

### 4. Arquitetura Tecnológica em 4 Pilares
1. **Coletor Desktop Windows (`agent/pulselab-agent.ps1`):** Daemon em PowerShell WPF com pop-ups lúdicos e captura atômica.
2. **Central Analytics Web (`dashboard/index.html`):** Painel em Dark Mode para pesquisadores com controle de qualidade.
3. **Simulador Web Navegável (`web/agent-simulator`):** Ambiente React/Vite para validação de cenários em Linux, macOS e Windows.
4. **Backend Supabase & GitOps (`schema/supabase-schema.sql`):** PostgreSQL com RLS, bucket privado de screenshots e atualização remota de parâmetros via `config/config.json`.

---

### 5. Ética & LGPD by Design
* **Pseudonimização:** Chaves de instalação (`installation_id`) sem coleta de nomes.
* **Telemetria Minimizada:** Apenas categorias de aplicativo (ex: *IDE*, *Navegador*), sem títulos de janelas.
* **Bucket Privado:** Screenshots gravados com RLS no Supabase, acessíveis apenas por backend autenticado.
* **Zero Biometria:** Sem uso de webcam, microfone ou rastreamento facial.

---

## 🎨 Roteiro Slide a Slide para o Google Slides

### Slide 1: Capa & Título
* **Título:** PulseLab v1.4.0 — Observabilidade Distribuída em Robótica Educativa
* **Subtítulo:** Multimodal Learning Analytics (MMLA) e Controle de Qualidade em Oficinas Escolares
* **Notas do Orador:** *"Hoje apresentamos o PulseLab, uma infraestrutura de observação não invasiva que abre a caixa-preta do aprendizado em robótica escolar."*

### Slide 2: O Problema — A "Caixa-Preta" da Robótica
* **Título:** O Desafio Científico nas Oficinas de Robótica
* **Cartões:**
  1. *Efeito Hawthorne & Custo:* Observadores físicos alteram o comportamento natural e são inviáveis em escala.
  2. *Viés de Memória:* Avaliações pós-teste lembram apenas do final da aula.
  3. *Opacidade do Processo:* Falta de dados empíricos sobre quando o grupo travou ou como dividiu as tarefas.
* **Notas do Orador:** *"Nas pesquisas tradicionais de robótica, só vemos o robô finalizado. O PulseLab foi criado para capturar o processo em tempo real."*

### Slide 3: A Solução PulseLab — Observação Passiva
* **Título:** Checkpoints Absolutos & Coleta Estruturada
* **Tópicos:**
  * Checkpoints lúdicos padronizados aos **20 e 40 minutos**.
  * Autorrelato de esforço mental (1–4), estado de progresso e papel real (*Computador* vs. *Montagem*).
  * Tamanho dinâmico do grupo (1 a 4 alunos por máquina).
  * Encerramento direto do aluno + Web App isolado do Instrutor (`/instrutor/`).
* **Notas do Orador:** *"O agente roda em segundo plano e coleta auto-relatos rápidos aos 20 e 40 minutos, sem deslocar a linha do tempo da oficina."*

### Slide 4: Arquitetura em 4 Pilares
* **Título:** Engenharia Distribuída & Resiliência
* **Pilares:**
  1. *Coletor Desktop WPF (Windows)*
  2. *Central Analytics (Dashboard Web)*
  3. *Simulador Web Navegável (Linux/macOS/Windows)*
  4. *Backend Supabase & GitOps (PostgreSQL + RLS + GitHub)*
* **Notas do Orador:** *"A arquitetura combina resiliência offline atômica, controle GitOps de perguntas e segurança via RLS no Supabase."*

### Slide 5: Triangulação Multimodal (MMLA)
* **Título:** Visual Grounding & Métrica de Qualidade
* **Tópicos:**
  * Contexto: Escola, turma, idade do aluno (8-15+ anos), papel na dupla.
  * Carga Cognitiva: Medição ordinal ($M_{\text{effort}}$) baseada em Sweller (1988).
  * Screenshot Atômico: Captura da janela do LEGO SPIKE no exato milissegundo da resposta.
  * Auditoria de Qualidade: View `research_session_quality` rastreia taxa de conclusão e latências.
* **Notas do Orador:** *"O grande diferencial é o Visual Grounding: alinhar a resposta subjetiva da criança com a imagem exata do código naquele segundo."*

### Slide 6: Ética & LGPD by Design
* **Título:** Proteção Rigorosa dos Dados dos Estudantes
* **Tópicos:**
  * Pseudonimização total via `installation_id`.
  * Telemetria minimizada (categorias de app, sem títulos de janelas).
  * Bucket privado Supabase com RLS.
  * Zero webcam, áudio ou biometria.
* **Notas do Orador:** *"O sistema foi concebido respeitando estritamente a LGPD e as diretrizes do CEP/CONEP para pesquisas escolares."*

### Slide 7: Entregáveis do Projeto
* **Título:** Recursos & Ferramentas de Demonstração
* **Tópicos:**
  * Landing Page em GitHub Pages (`index.html`).
  * Simulador Web Navegável (`web/agent-simulator`).
  * Relatórios Acadêmicos de Métricas e Banca (`docs/`).
  * Framework de TCC e Protocolo de Pesquisa v1.
* **Notas do Orador:** *"Disponibilizamos uma landing page pública, simulador web para homologação e relatórios acadêmicos completos."*

### Slide 8: Conclusão
* **Título:** O Futuro da Pesquisa em Robótica Educativa
* **Citação:** *"O PulseLab não substitui o professor nem julga o aluno: ele ilumina a jornada do aprendizado em robótica."*
* **Notas do Orador:** *"Com o PulseLab, conseguimos entender empiricamente como a aprendizagem e a colaboração acontecem a cada minuto da oficina."*

---

## ⚡ Google Apps Script Especificamente para a sua Apresentação

Para aplicar este texto e estrutura **diretamente na sua apresentação vinculada ao link**:

1. Abra a sua apresentação no Google Slides:  
   🔗 [https://docs.google.com/presentation/d/17QKRj2Fc39wnWUDHPcAK2PBHKrpSSSSdNpe0CJWoicg/edit](https://docs.google.com/presentation/d/17QKRj2Fc39wnWUDHPcAK2PBHKrpSSSSdNpe0CJWoicg/edit)
2. No menu superior, clique em **Extensões** ➔ **Apps Script**.
3. Apague o código padrão e cole o código abaixo:

```javascript
/**
 * Script de Atualização para a Apresentação PulseLab:
 * ID: 17QKRj2Fc39wnWUDHPcAK2PBHKrpSSSSdNpe0CJWoicg
 */
function atualizarApresentacaoPulseLabOficial() {
  var presentationId = "17QKRj2Fc39wnWUDHPcAK2PBHKrpSSSSdNpe0CJWoicg";
  var presentation = SlidesApp.openById(presentationId);
  
  // Limpa os slides anteriores se desejar recriar do zero
  var slides = presentation.getSlides();
  for (var i = slides.length - 1; i >= 0; i--) {
    slides[i].remove();
  }

  // Cores do Projeto
  var DARK_BG = '#0F172A';
  var LIGHT_BG = '#F8FAFC';
  var PRIMARY = '#0284C7';
  var ACCENT = '#38BDF8';
  var TEXT_DARK = '#0F172A';
  var TEXT_MUTED = '#475569';
  var TEXT_LIGHT = '#F8FAFC';

  // SLIDE 1: Capa
  var s1 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  s1.getBackground().setSolidFill(DARK_BG);
  
  var t1 = s1.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 100, 620, 80);
  t1.getText().setText("PULSELAB v1.4.0");
  t1.getText().getTextStyle().setFontSize(42).setBold(true).setForegroundColor(ACCENT);
  
  var sub1 = s1.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 180, 620, 80);
  sub1.getText().setText("Fundação de Observação Distribuída e Multimodal Learning Analytics (MMLA) para Robótica Educativa");
  sub1.getText().getTextStyle().setFontSize(18).setForegroundColor(TEXT_LIGHT);
  
  s1.getNotesPage().getSpeakerNotesShape().getText().setText("Hoje apresentamos o PulseLab, uma infraestrutura de observação não invasiva que abre a caixa-preta do aprendizado em robótica escolar.");

  // SLIDE 2: O Problema
  var s2 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  s2.getBackground().setSolidFill(LIGHT_BG);
  
  var t2 = s2.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 40, 620, 50);
  t2.getText().setText("O Desafio Científico: A 'Caixa-Preta' da Robótica");
  t2.getText().getTextStyle().setFontSize(24).setBold(true).setForegroundColor(TEXT_DARK);
  
  var cards2 = [
    { title: "1. Efeito Hawthorne & Logística", desc: "Observadores físicos alteram o comportamento natural das crianças e são inviáveis em escala." },
    { title: "2. Viés de Memória (Recency)", desc: "Questionários pós-evento lembram apenas dos últimos minutos, ignorando picos de sobrecarga mental." },
    { title: "3. Opacidade do Processo", desc: "Falta de dados empíricos sobre quando o grupo travou ou como dividiu o trabalho (Computador vs. Montagem)." }
  ];
  
  for (var i = 0; i < cards2.length; i++) {
    var box = s2.insertShape(SlidesApp.ShapeType.ROUNDED_RECTANGLE, 50 + i * 215, 110, 200, 240);
    box.getFill().setSolidFill('#FFFFFF');
    box.getLineFill().setSolidFill('#CBD5E1');
    box.getText().setText(cards2[i].title + "\n\n" + cards2[i].desc);
    box.getText().getRuns()[0].getTextStyle().setFontSize(15).setBold(true).setForegroundColor(PRIMARY);
  }
  s2.getNotesPage().getSpeakerNotesShape().getText().setText("Nas pesquisas tradicionais de robótica, só vemos o robô finalizado. O PulseLab foi criado para capturar o processo em tempo real.");

  // SLIDE 3: A Solução
  var s3 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  s3.getBackground().setSolidFill(LIGHT_BG);
  
  var t3 = s3.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 40, 620, 50);
  t3.getText().setText("A Solução PulseLab: Checkpoints Absolutos");
  t3.getText().getTextStyle().setFontSize(24).setBold(true).setForegroundColor(TEXT_DARK);
  
  var s3Text = s3.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 110, 620, 240);
  s3Text.getText().setText(
    "• Checkpoints lúdicos padronizados aos 20 e 40 minutos da oficina.\n\n" +
    "• Autorrelato de esforço mental (1-4), progresso e papel real (Computador vs. Montagem).\n\n" +
    "• Tamanho dinâmico do grupo selecionável no início (1 a 4 alunos).\n\n" +
    "• Encerramento direto do aluno + Web App exclusivo do Instrutor (/instrutor/)."
  );
  s3Text.getText().getTextStyle().setFontSize(15).setForegroundColor(TEXT_MUTED);
  s3.getNotesPage().getSpeakerNotesShape().getText().setText("O agente roda em segundo plano e coleta auto-relatos rápidos aos 20 e 40 minutos, sem deslocar a linha do tempo da oficina.");

  // SLIDE 4: Arquitetura
  var s4 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  s4.getBackground().setSolidFill(DARK_BG);
  
  var t4 = s4.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 40, 620, 50);
  t4.getText().setText("Arquitetura Tecnológica em 4 Pilares");
  t4.getText().getTextStyle().setFontSize(24).setBold(true).setForegroundColor(TEXT_LIGHT);
  
  var pilares = [
    "1. Coletor Desktop WPF (Windows) - Agent PowerShell Daemon",
    "2. Central Analytics (Web) - Dashboard Dark Mode com research_session_quality",
    "3. Simulador Web Navegável (React/Vite) - Validação em Linux, macOS e Windows",
    "4. Backend Supabase & GitOps - PostgreSQL + RLS + Atualizações via GitHub"
  ];
  for (var p = 0; p < pilares.length; p++) {
    var pBox = s4.insertShape(SlidesApp.ShapeType.RECTANGLE, 50, 110 + p * 60, 620, 50);
    pBox.getFill().setSolidFill('#1E293B');
    pBox.getLineFill().setSolidFill('#334155');
    pBox.getText().setText(pilares[p]);
    pBox.getText().getTextStyle().setFontSize(14).setForegroundColor(ACCENT);
  }
  s4.getNotesPage().getSpeakerNotesShape().getText().setText("A arquitetura combina resiliência offline atômica, controle GitOps de perguntas e segurança via RLS no Supabase.");

  // SLIDE 5: MMLA
  var s5 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  s5.getBackground().setSolidFill(LIGHT_BG);
  
  var t5 = s5.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 40, 620, 50);
  t5.getText().setText("Triangulação Multimodal & Visual Grounding");
  t5.getText().getTextStyle().setFontSize(24).setBold(true).setForegroundColor(TEXT_DARK);
  
  var s5Text = s5.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 110, 620, 240);
  s5Text.getText().setText(
    "• Contexto: Sede, escola, turma, idade do aluno (8-15+ anos) e papel atribuído.\n\n" +
    "• Carga Cognitiva: Medição ordinal de esforço (Meffort, 1-4) baseada em Sweller (1988).\n\n" +
    "• Visual Grounding: Screenshot da janela do LEGO SPIKE no milissegundo da resposta.\n\n" +
    "• Auditoria de Qualidade: View research_session_quality rastreia completude e latência."
  );
  s5Text.getText().getTextStyle().setFontSize(15).setForegroundColor(TEXT_MUTED);
  s5.getNotesPage().getSpeakerNotesShape().getText().setText("O grande diferencial é o Visual Grounding: alinhar a resposta subjetiva da criança com a imagem exata do código naquele segundo.");

  // SLIDE 6: LGPD
  var s6 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  s6.getBackground().setSolidFill(LIGHT_BG);
  
  var t6 = s6.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 40, 620, 50);
  t6.getText().setText("Segurança & Ética (LGPD by Design)");
  t6.getText().getTextStyle().setFontSize(24).setBold(true).setForegroundColor(TEXT_DARK);
  
  var s6Text = s6.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 110, 620, 240);
  s6Text.getText().setText(
    "• Pseudonimização Total: Identificação por installation_id (sem coleta de nomes).\n\n" +
    "• Telemetria Minimizada: Apenas categorias de software (sem títulos de janela).\n\n" +
    "• Bucket Privado Supabase: Screenshots salvos com permissão RLS exclusiva.\n\n" +
    "• Zero Biometria: Nenhuma gravação de áudio, webcam ou rastreamento facial."
  );
  s6Text.getText().getTextStyle().setFontSize(15).setForegroundColor(TEXT_MUTED);
  s6.getNotesPage().getSpeakerNotesShape().getText().setText("O sistema foi concebido respeitando estritamente a LGPD e as diretrizes do CEP/CONEP para pesquisas escolares.");

  // SLIDE 7: Recursos
  var s7 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  s7.getBackground().setSolidFill(LIGHT_BG);
  
  var t7 = s7.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 40, 620, 50);
  t7.getText().setText("Entregáveis & Ferramentas de Demonstração");
  t7.getText().getTextStyle().setFontSize(24).setBold(true).setForegroundColor(TEXT_DARK);
  
  var s7Text = s7.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 110, 620, 240);
  s7Text.getText().setText(
    "• Landing Page GitHub Pages (index.html): Galeria de telas e simulador ao vivo.\n\n" +
    "• Simulador Web Navegável (web/agent-simulator): Teste navegável para Linux/Windows.\n\n" +
    "• Relatórios Acadêmicos (docs/): Fundamentação psicométrica e modelos estatísticos ordinais.\n\n" +
    "• Framework de TCC & Protocolo v1: Estrutura completa para bancas e comitês de ética."
  );
  s7Text.getText().getTextStyle().setFontSize(15).setForegroundColor(TEXT_MUTED);
  s7.getNotesPage().getSpeakerNotesShape().getText().setText("Disponibilizamos uma landing page pública, simulador web para homologação e relatórios acadêmicos completos.");

  // SLIDE 8: Conclusão
  var s8 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  s8.getBackground().setSolidFill(DARK_BG);
  
  var t8 = s8.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 60, 620, 60);
  t8.getText().setText("O Futuro da Robótica Educativa");
  t8.getText().getTextStyle().setFontSize(32).setBold(true).setForegroundColor(TEXT_LIGHT);
  
  var q8 = s8.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 150, 620, 90);
  q8.getText().setText("\"O PulseLab não substitui o professor nem julga o aluno: ele ilumina a jornada do aprendizado em robótica.\"");
  q8.getText().getTextStyle().setFontSize(20).setItalic(true).setForegroundColor(ACCENT);
  
  s8.getNotesPage().getSpeakerNotesShape().getText().setText("Com o PulseLab, conseguimos entender empiricamente como a aprendizagem e a colaboração acontecem a cada minuto da oficina.");
}
```

4. Clique em **Salvar** (💾) e depois em **Executar (Run)**.
5. A sua apresentação no link indicado será **totalmente preenchida e atualizada em tempo real com todo o texto da última sessão!**
