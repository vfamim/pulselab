/**
 * ==============================================================================
 * PULSELAB v1.5.0 - GERADOR AUTOMÁTICO DE SLIDES NO GOOGLE PRESENTATIONS
 * ==============================================================================
 * Como aplicar este script na sua apresentação do Google Slides:
 * 1. Abra sua apresentação no Google Slides (ou crie uma em branco em slides.google.com).
 * 2. No menu superior, clique em: Extensões -> Apps Script.
 * 3. Apague todo o conteúdo do editor, cole este código completo e clique no ícone de "Salvar".
 * 4. Clique no botão "Executar" (Run).
 * 5. Conceda as permissões solicitadas pela sua conta Google.
 * 6. Volte à sua apresentação: todos os slides formatados no template oficial estarão prontos!
 * ==============================================================================
 */

function criarApresentacaoPulseLabOficial() {
  var presentation = SlidesApp.getActivePresentation();
  
  // Limpar slides existentes se desejar recriar
  var existingSlides = presentation.getSlides();
  for (var i = existingSlides.length - 1; i >= 0; i--) {
    existingSlides[i].remove();
  }

  // Paleta do Template Oficial PulseLab (Dark Mode / Slate Accent)
  var COLOR_DARK_BG     = '#0F172A'; // Slate 900
  var COLOR_LIGHT_BG    = '#F8FAFC'; // Slate 50
  var COLOR_CARD_BG     = '#1E293B'; // Slate 800
  var COLOR_CARD_LIGHT  = '#FFFFFF'; // White
  var COLOR_PRIMARY     = '#0284C7'; // Sky 600
  var COLOR_ACCENT      = '#38BDF8'; // Sky 400
  var COLOR_TEXT_DARK   = '#0F172A';
  var COLOR_TEXT_MUTED  = '#475569';
  var COLOR_TEXT_LIGHT  = '#F8FAFC';
  var COLOR_TEXT_SUB    = '#94A3B8';

  // ----------------------------------------------------------------------------
  // SLIDE 1: Capa (Tema Escuro)
  // ----------------------------------------------------------------------------
  var slide1 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  slide1.getBackground().setSolidFill(COLOR_DARK_BG);
  
  var title1 = slide1.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 90, 620, 70);
  title1.getText().setText("PULSELAB");
  title1.getText().getTextStyle().setFontSize(44).setBold(true).setForegroundColor(COLOR_ACCENT);
  
  var sub1 = slide1.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 165, 620, 70);
  sub1.getText().setText("Fundação de Observação Distribuída e Multimodal Learning Analytics (MMLA) para Robótica Educativa");
  sub1.getText().getTextStyle().setFontSize(19).setForegroundColor(COLOR_TEXT_LIGHT);
  
  var line1 = slide1.insertShape(SlidesApp.ShapeType.RECTANGLE, 50, 250, 620, 4);
  line1.getFill().setSolidFill(COLOR_PRIMARY);
  line1.getLineFill().setSolidFill(COLOR_PRIMARY);
  
  var meta1 = slide1.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 270, 620, 40);
  meta1.getText().setText("Versão 1.5.0  |  Oficinas LEGO® SPIKE™  |  LGPD & Ética by Design");
  meta1.getText().getTextStyle().setFontSize(13).setForegroundColor(COLOR_TEXT_SUB);
  
  slide1.getNotesPage().getSpeakerNotesShape().getText().setText("Hoje apresento o PulseLab, uma plataforma de observabilidade e Learning Analytics desenvolvida para abrir a caixa-preta do aprendizado em oficinas de robótica educacional.");

  // ----------------------------------------------------------------------------
  // SLIDE 2: 1. O que é o PulseLab (Tema Claro)
  // ----------------------------------------------------------------------------
  var slide2 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  slide2.getBackground().setSolidFill(COLOR_LIGHT_BG);
  
  var sec2 = slide2.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 25, 600, 25);
  sec2.getText().setText("1. VISÃO GERAL");
  sec2.getText().getTextStyle().setFontSize(12).setBold(true).setForegroundColor(COLOR_PRIMARY);
  
  var tit2 = slide2.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 45, 600, 40);
  tit2.getText().setText("O que é o PulseLab?");
  tit2.getText().getTextStyle().setFontSize(24).setBold(true).setForegroundColor(COLOR_TEXT_DARK);
  
  var cards2 = [
    { title: "Observação Distribuída", desc: "Infraestrutura não invasiva que instala um coletor leve nos computadores das escolas para acompanhar oficinas de robótica em escala." },
    { title: "Multimodal Learning Analytics", desc: "Coleta quantitativa que combina autoeficácia, esforço mental, telemetria de inatividade e evidências visuais de código." },
    { title: "Controle de Qualidade", desc: "Linha do tempo auditável de cada sessão para garantir a integridade da amostra de dados em pesquisas acadêmicas." }
  ];
  
  for (var c = 0; c < cards2.length; c++) {
    var posX = 50 + c * 215;
    var card = slide2.insertShape(SlidesApp.ShapeType.ROUNDED_RECTANGLE, posX, 100, 200, 250);
    card.getFill().setSolidFill(COLOR_CARD_LIGHT);
    card.getLineFill().setSolidFill('#E2E8F0');
    
    var cardText = slide2.insertShape(SlidesApp.ShapeType.TEXT_BOX, posX + 10, 110, 180, 230);
    cardText.getText().setText(cards2[c].title + "\n\n" + cards2[c].desc);
    cardText.getText().getRuns()[0].getTextStyle().setFontSize(15).setBold(true).setForegroundColor(COLOR_PRIMARY);
  }
  slide2.getNotesPage().getSpeakerNotesShape().getText().setText("O PulseLab é uma fundação de observação distribuída que coleta dados estruturados de aprendizagem em oficinas de robótica sem interromper a dinâmica da aula.");

  // ----------------------------------------------------------------------------
  // SLIDE 3: 2. O que ele faz (Tema Claro)
  // ----------------------------------------------------------------------------
  var slide3 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  slide3.getBackground().setSolidFill(COLOR_LIGHT_BG);
  
  var sec3 = slide3.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 25, 600, 25);
  sec3.getText().setText("2. FUNCIONALIDADES E RECURSOS");
  sec3.getText().getTextStyle().setFontSize(12).setBold(true).setForegroundColor(COLOR_PRIMARY);
  
  var tit3 = slide3.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 45, 600, 40);
  tit3.getText().setText("O que o PulseLab faz?");
  tit3.getText().getTextStyle().setFontSize(24).setBold(true).setForegroundColor(COLOR_TEXT_DARK);
  
  var items3 = [
    "Checkpoints Absolutos (20' e 40'): Janelas rápidas disparadas no tempo real da atividade para medir progresso e dúvida.",
    "Medição de Carga Cognitiva: Avaliação ordinal de esforço mental (1-4) baseada na Teoria de Sweller (1988).",
    "Visual Grounding (Código SPIKE): Captura atômica da janela do LEGO SPIKE no milissegundo exato da resposta.",
    "Divisão Real de Papéis: Mapeamento de quem operou o computador e quem esteve na montagem (Solo, Dupla, Trio ou Grupo).",
    "Cache Offline Resiliente: Armazenamento local com sincronização automática com o banco ao restabelecer conexão."
  ];
  
  for (var i = 0; i < items3.length; i++) {
    var posY = 95 + i * 52;
    var rowBox = slide3.insertShape(SlidesApp.ShapeType.RECTANGLE, 50, posY, 620, 46);
    rowBox.getFill().setSolidFill(COLOR_CARD_LIGHT);
    rowBox.getLineFill().setSolidFill('#CBD5E1');
    rowBox.getText().setText(items3[i]);
    rowBox.getText().getTextStyle().setFontSize(12.5).setForegroundColor(COLOR_TEXT_MUTED);
  }
  slide3.getNotesPage().getSpeakerNotesShape().getText().setText("O agente automatiza pop-ups nos minutos 20 e 40, realiza o grounding visual do código e garante resiliência offline se a internet da escola oscilar.");

  // ----------------------------------------------------------------------------
  // SLIDE 4: 3. Como ele contribui (Tema Escuro)
  // ----------------------------------------------------------------------------
  var slide4 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  slide4.getBackground().setSolidFill(COLOR_DARK_BG);
  
  var sec4 = slide4.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 25, 600, 25);
  sec4.getText().setText("3. IMPACTO E CONTRIBUIÇÃO");
  sec4.getText().getTextStyle().setFontSize(12).setBold(true).setForegroundColor(COLOR_ACCENT);
  
  var tit4 = slide4.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 45, 600, 40);
  tit4.getText().setText("Como o PulseLab contribui?");
  tit4.getText().getTextStyle().setFontSize(24).setBold(true).setForegroundColor(COLOR_TEXT_LIGHT);
  
  var contribs = [
    { title: "Para a Ciência e Pesquisa", desc: "Elimina o viés de memória pós-evento e o efeito Hawthorne de observadores físicos com pranchetas." },
    { title: "Para a Gestão Educacional", desc: "Oferece um painel central (research_session_quality) que valida a completude e qualidade das oficinas." },
    { title: "Para a Prática Pedagógica", desc: "Identifica se os gargalos ocorrem na lógica de programação, montagem mecânica ou sensores." },
    { title: "Ética e LGPD por Design", desc: "Pseudonimização total via installation_id, bucket privado com RLS e zero coleta biométrica ou áudio." }
  ];
  
  for (var p = 0; p < contribs.length; p++) {
    var col = p % 2;
    var row = Math.floor(p / 2);
    var posX = 50 + col * 320;
    var posY = 100 + row * 125;
    
    var pCard = slide4.insertShape(SlidesApp.ShapeType.ROUNDED_RECTANGLE, posX, posY, 300, 110);
    pCard.getFill().setSolidFill(COLOR_CARD_BG);
    pCard.getLineFill().setSolidFill('#334155');
    
    var pText = slide4.insertShape(SlidesApp.ShapeType.TEXT_BOX, posX + 10, posY + 10, 280, 90);
    pText.getText().setText(contribs[p].title + "\n" + contribs[p].desc);
    pText.getText().getRuns()[0].getTextStyle().setFontSize(14.5).setBold(true).setForegroundColor(COLOR_ACCENT);
  }
  slide4.getNotesPage().getSpeakerNotesShape().getText().setText("O PulseLab contribui abrindo a caixa-preta do aprendizado, fornecendo dados empíricos para pesquisadores e garantindo total conformidade com a LGPD.");

  // ----------------------------------------------------------------------------
  // SLIDE 5: 4. Como instalar (Tema Claro)
  // ----------------------------------------------------------------------------
  var slide5 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  slide5.getBackground().setSolidFill(COLOR_LIGHT_BG);
  
  var sec5 = slide5.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 25, 600, 25);
  sec5.getText().setText("4. IMPLANTAÇÃO E DISTRIBUIÇÃO");
  sec5.getText().getTextStyle().setFontSize(12).setBold(true).setForegroundColor(COLOR_PRIMARY);
  
  var tit5 = slide5.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 45, 600, 40);
  tit5.getText().setText("Como instalar o PulseLab?");
  tit5.getText().getTextStyle().setFontSize(24).setBold(true).setForegroundColor(COLOR_TEXT_DARK);
  
  var installSteps = [
    { title: "1. Build Standalone (.zip)", desc: "Gerado com 1 comando em Python ou PowerShell. Cria um pacote ZIP com a identidade da sede/escola." },
    { title: "2. Credenciais Embutidas", desc: "A Anon Key pública do Supabase e parâmetros da sede já vêm 100% embutidos. Zero digitação na escola." },
    { title: "3. Instalação em 2 Cliques", desc: "O técnico extrai o ZIP e executa o .bat na máquina do aluno (sem necessidade de privilégios de Admin)." },
    { title: "4. Atalho Automático", desc: "Cria o atalho 'Iniciar Pulselab - Oficina de Robótica' na Área de Trabalho para lançamento manual rápido." }
  ];
  
  for (var s = 0; s < installSteps.length; s++) {
    var col = s % 2;
    var row = Math.floor(s / 2);
    var posX = 50 + col * 320;
    var posY = 100 + row * 125;
    
    var sCard = slide5.insertShape(SlidesApp.ShapeType.ROUNDED_RECTANGLE, posX, posY, 300, 110);
    sCard.getFill().setSolidFill(COLOR_CARD_LIGHT);
    sCard.getLineFill().setSolidFill('#CBD5E1');
    
    var sText = slide5.insertShape(SlidesApp.ShapeType.TEXT_BOX, posX + 10, posY + 10, 280, 90);
    sText.getText().setText(installSteps[s].title + "\n" + installSteps[s].desc);
    sText.getText().getRuns()[0].getTextStyle().setFontSize(14.5).setBold(true).setForegroundColor(COLOR_PRIMARY);
  }
  slide5.getNotesPage().getSpeakerNotesShape().getText().setText("A instalação é extremamente simples: um arquivo .zip pré-configurado é baixado e executado com dois cliques na máquina do aluno.");

  // ----------------------------------------------------------------------------
  // SLIDE 6: 5. Como usar — Fluxo Operacional (Tema Claro)
  // ----------------------------------------------------------------------------
  var slide6 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  slide6.getBackground().setSolidFill(COLOR_LIGHT_BG);
  
  var sec6 = slide6.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 25, 600, 25);
  sec6.getText().setText("5. FLUXO OPERACIONAL NA PRÁTICA");
  sec6.getText().getTextStyle().setFontSize(12).setBold(true).setForegroundColor(COLOR_PRIMARY);
  
  var tit6 = slide6.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 45, 600, 40);
  tit6.getText().setText("Como usar na Oficina?");
  tit6.getText().getTextStyle().setFontSize(24).setBold(true).setForegroundColor(COLOR_TEXT_DARK);
  
  var roles = [
    { title: "👨‍🏫 Para o Instrutor", desc: "Clique no atalho no início da aula, confirme o contexto da turma (dupla/trio) e autorize. No final, avalia o desempenho pelo celular no portal /instrutor/." },
    { title: "👧‍💻 Para os Alunos", desc: "Trabalham normalmente no robô. Aos 20' e 40', respondem perguntas lúdicas de 20s sobre esforço mental e papel (Computador/Montagem)." },
    { title: "📊 Para o Pesquisador", desc: "Acessa o Dashboard Central (dashboard/index.html) para acompanhar taxas de conclusão, autoeficácia e exportar dados brutos." }
  ];
  
  for (var r = 0; r < roles.length; r++) {
    var posY = 95 + r * 85;
    var rCard = slide6.insertShape(SlidesApp.ShapeType.ROUNDED_RECTANGLE, 50, posY, 620, 75);
    rCard.getFill().setSolidFill(COLOR_CARD_LIGHT);
    rCard.getLineFill().setSolidFill('#CBD5E1');
    
    var rText = slide6.insertShape(SlidesApp.ShapeType.TEXT_BOX, 60, posY + 8, 600, 60);
    rText.getText().setText(roles[r].title + "\n" + roles[r].desc);
    rText.getText().getRuns()[0].getTextStyle().setFontSize(14).setBold(true).setForegroundColor(COLOR_PRIMARY);
  }
  slide6.getNotesPage().getSpeakerNotesShape().getText().setText("O uso é dividido de forma fluida entre o lançamento do instrutor, os autorrelatos rápidos dos alunos e o acompanhamento do pesquisador.");

  // ----------------------------------------------------------------------------
  // SLIDE 7: Arquitetura em 4 Pilares (Tema Escuro)
  // ----------------------------------------------------------------------------
  var slide7 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  slide7.getBackground().setSolidFill(COLOR_DARK_BG);
  
  var sec7 = slide7.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 25, 600, 25);
  sec7.getText().setText("ENGENHARIA E ARQUITETURA");
  sec7.getText().getTextStyle().setFontSize(12).setBold(true).setForegroundColor(COLOR_ACCENT);
  
  var tit7 = slide7.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 45, 600, 40);
  tit7.getText().setText("Arquitetura Distribuída em 4 Pilares");
  tit7.getText().getTextStyle().setFontSize(24).setBold(true).setForegroundColor(COLOR_TEXT_LIGHT);
  
  var pillars = [
    { title: "1. Agente Desktop (WPF)", desc: "Daemon PowerShell para Windows com interfaces XAML nativas e suporte offline." },
    { title: "2. Dashboard Analytics (Web)", desc: "Painel web para visualização de métricas e auditoria de qualidade (research_session_quality)." },
    { title: "3. Simulador Web (React)", desc: "Ambiente navegável para homologação de fluxos em Linux, macOS e Windows." },
    { title: "4. Backend Supabase & GitOps", desc: "PostgreSQL com RLS de inserção mínima, bucket privado e atualização remota via GitHub." }
  ];
  
  for (var pl = 0; pl < pillars.length; pl++) {
    var col = pl % 2;
    var row = Math.floor(pl / 2);
    var posX = 50 + col * 320;
    var posY = 100 + row * 125;
    
    var plCard = slide7.insertShape(SlidesApp.ShapeType.ROUNDED_RECTANGLE, posX, posY, 300, 110);
    plCard.getFill().setSolidFill(COLOR_CARD_BG);
    plCard.getLineFill().setSolidFill('#334155');
    
    var plText = slide7.insertShape(SlidesApp.ShapeType.TEXT_BOX, posX + 10, posY + 10, 280, 90);
    plText.getText().setText(pillars[pl].title + "\n" + pillars[pl].desc);
    plText.getText().getRuns()[0].getTextStyle().setFontSize(14.5).setBold(true).setForegroundColor(COLOR_ACCENT);
  }
  slide7.getNotesPage().getSpeakerNotesShape().getText().setText("A estrutura técnica é modular e resiliente, combinando agente local WPF, backend gerenciado no Supabase e controle remoto GitOps.");

  // ----------------------------------------------------------------------------
  // SLIDE 8: Conclusão (Tema Escuro)
  // ----------------------------------------------------------------------------
  var slide8 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  slide8.getBackground().setSolidFill(COLOR_DARK_BG);
  
  var tit8 = slide8.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 45, 620, 55);
  tit8.getText().setText("O Futuro da Observabilidade em Robótica Educativa");
  tit8.getText().getTextStyle().setFontSize(26).setBold(true).setForegroundColor(COLOR_TEXT_LIGHT);
  
  var quote8 = slide8.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 115, 620, 70);
  quote8.getText().setText("\"O PulseLab não substitui o professor nem julga o aluno: ele ilumina a jornada do aprendizado em robótica.\"");
  quote8.getText().getTextStyle().setFontSize(17).setItalic(true).setForegroundColor(COLOR_ACCENT);
  
  var body8 = slide8.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 205, 620, 130);
  body8.getText().setText("• Escala multicêntrica de baixo custo logístico\n• Integração direta entre pesquisa acadêmica e prática pedagógica\n• Transparência total e rigor metodológico sobre o aprendizado real");
  body8.getText().getTextStyle().setFontSize(15).setForegroundColor(COLOR_TEXT_SUB);
  
  slide8.getNotesPage().getSpeakerNotesShape().getText().setText("Com o PulseLab, conseguimos entender empiricamente como o aprendizado, a colaboração e a superação de desafios ocorrem a cada minuto da oficina.");
}
