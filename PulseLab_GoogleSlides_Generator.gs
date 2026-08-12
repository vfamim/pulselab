/**
 * ==============================================================================
 * PULSELAB v1.4.0 - GOOGLE SLIDES AUTOMATIC PRESENTATION GENERATOR
 * ==============================================================================
 * Como usar no Google Workspace:
 * 1. Abra o Google Slides (slides.google.com) e crie uma nova apresentação em branco.
 * 2. No menu superior, clique em: Extensões -> Apps Script.
 * 3. Apague todo o conteúdo do editor, cole este código completo e clique em "Salvar" (ícone de disquete).
 * 4. Clique no botão "Executar" (Run).
 * 5. Conceda as permissões solicitadas pela sua conta Google.
 * 6. Volte à sua apresentação do Google Slides: todos os 8 slides formatados, com cards e notas do orador estarão criados!
 * ==============================================================================
 */

function criarApresentacaoPulseLab() {
  var presentation = SlidesApp.getActivePresentation();
  
  // Limpar slides existentes se houver
  var existingSlides = presentation.getSlides();
  for (var i = existingSlides.length - 1; i >= 0; i--) {
    existingSlides[i].remove();
  }

  // Paleta de Cores
  var COLOR_DARK_BG = '#0F172A';
  var COLOR_LIGHT_BG = '#F8FAFC';
  var COLOR_CARD_BG = '#1E293B';
  var COLOR_CARD_LIGHT = '#FFFFFF';
  var COLOR_PRIMARY = '#0284C7';
  var COLOR_ACCENT = '#38BDF8';
  var COLOR_TEXT_DARK = '#0F172A';
  var COLOR_TEXT_MUTED = '#475569';
  var COLOR_TEXT_LIGHT = '#F8FAFC';
  var COLOR_TEXT_SUB = '#94A3B8';

  // SLIDE 1: Capa (Tema Escuro)
  var slide1 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  slide1.getBackground().setSolidFill(COLOR_DARK_BG);
  
  var title1 = slide1.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 100, 620, 80);
  title1.getText().setText("PULSELAB");
  title1.getText().getTextStyle().setFontSize(44).setBold(true).setForegroundColor(COLOR_ACCENT);
  
  var sub1 = slide1.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 180, 620, 70);
  sub1.getText().setText("Observabilidade Distribuída em Robótica Educativa com Multimodal Learning Analytics (MMLA)");
  sub1.getText().getTextStyle().setFontSize(20).setForegroundColor(COLOR_TEXT_LIGHT);
  
  var line1 = slide1.insertShape(SlidesApp.ShapeType.RECTANGLE, 50, 270, 620, 4);
  line1.getFill().setSolidFill(COLOR_PRIMARY);
  line1.getLineFill().setSolidFill(COLOR_PRIMARY);
  
  var meta1 = slide1.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 290, 620, 40);
  meta1.getText().setText("Versão 1.4.0 Live  |  Projeto Robótica Educativa  |  LGPD & Ética by Design");
  meta1.getText().getTextStyle().setFontSize(13).setForegroundColor(COLOR_TEXT_SUB);
  
  slide1.getNotesPage().getSpeakerNotesShape().getText().setText("Boa tarde a todos. Hoje apresento o PulseLab, uma plataforma de observabilidade e Learning Analytics desenvolvida para oficinas de robótica educacional.");

  // SLIDE 2: O Desafio Científico
  var slide2 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  slide2.getBackground().setSolidFill(COLOR_LIGHT_BG);
  
  var sec2 = slide2.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 30, 600, 30);
  sec2.getText().setText("O DESAFIO CIENTÍFICO");
  sec2.getText().getTextStyle().setFontSize(13).setBold(true).setForegroundColor(COLOR_PRIMARY);
  
  var tit2 = slide2.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 55, 600, 45);
  tit2.getText().setText("A 'Caixa-Preta' das Oficinas de Robótica");
  tit2.getText().getTextStyle().setFontSize(24).setBold(true).setForegroundColor(COLOR_TEXT_DARK);
  
  var cards2Data = [
    { title: "1. Efeito Hawthorne", desc: "O estudante altera seu comportamento natural ao se perceber continuamente observado por um pesquisador físico." },
    { title: "2. Alto Custo Logístico", desc: "Impossibilidade financeira e operacional de enviar equipes de observação para dezenas de escolas simultaneamente." },
    { title: "3. Perda do Processo", desc: "Avaliações tradicionais focam apenas no robô pronto, ignorando momentos de dúvida, frustração e colaboração." }
  ];
  
  for (var c = 0; c < cards2Data.length; c++) {
    var posX = 50 + c * 215;
    var card = slide2.insertShape(SlidesApp.ShapeType.ROUNDED_RECTANGLE, posX, 120, 200, 240);
    card.getFill().setSolidFill(COLOR_CARD_LIGHT);
    card.getLineFill().setSolidFill('#E2E8F0');
    
    var cardText = slide2.insertShape(SlidesApp.ShapeType.TEXT_BOX, posX + 10, 130, 180, 220);
    cardText.getText().setText(cards2Data[c].title + "\n\n" + cards2Data[c].desc);
    cardText.getText().getRuns()[0].getTextStyle().setFontSize(16).setBold(true).setForegroundColor(COLOR_PRIMARY);
  }
  slide2.getNotesPage().getSpeakerNotesShape().getText().setText("Quando avaliamos o aprendizado em robótica, nos deparamos com uma caixa-preta: vemos o robô final, mas não o processo real de aprendizagem.");

  // SLIDE 3: A Solução PulseLab
  var slide3 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  slide3.getBackground().setSolidFill(COLOR_LIGHT_BG);
  
  var sec3 = slide3.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 30, 600, 30);
  sec3.getText().setText("A SOLUÇÃO PULSELAB");
  sec3.getText().getTextStyle().setFontSize(13).setBold(true).setForegroundColor(COLOR_PRIMARY);
  
  var tit3 = slide3.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 55, 600, 45);
  tit3.getText().setText("Coleta Passiva & Checkpoints Estruturados");
  tit3.getText().getTextStyle().setFontSize(24).setBold(true).setForegroundColor(COLOR_TEXT_DARK);
  
  var items3Data = [
    "Checkpoints Absolutos (20' e 40'): Pop-ups lúdicos padronizados disparados no tempo exato da atividade.",
    "Autorrelato Rápido & Objetivo: Métricas de esforço mental (1-4), progresso percebido e papel na dupla.",
    "Zero Deslocamento de Tempo: O tempo de resposta do aluno não atrasa o próximo checkpoint.",
    "Suporte em Tempo Real (Pesquisa-Ação): Botão 'Precisamos de ajuda' alerta o instrutor instantaneamente."
  ];
  
  for (var i = 0; i < items3Data.length; i++) {
    var posY = 115 + i * 62;
    var rowBox = slide3.insertShape(SlidesApp.ShapeType.RECTANGLE, 50, posY, 620, 54);
    rowBox.getFill().setSolidFill(COLOR_CARD_LIGHT);
    rowBox.getLineFill().setSolidFill('#CBD5E1');
    rowBox.getText().setText(items3Data[i]);
    rowBox.getText().getTextStyle().setFontSize(13).setForegroundColor(COLOR_TEXT_MUTED);
  }
  slide3.getNotesPage().getSpeakerNotesShape().getText().setText("O PulseLab roda em segundo plano e aplica formulários simples nos minutos 20 e 40 da oficina, capturando o estado do aluno sem interromper o fluxo.");

  // SLIDE 4: Arquitetura
  var slide4 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  slide4.getBackground().setSolidFill(COLOR_DARK_BG);
  
  var sec4 = slide4.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 30, 600, 30);
  sec4.getText().setText("ARQUITETURA TECNOLÓGICA");
  sec4.getText().getTextStyle().setFontSize(13).setBold(true).setForegroundColor(COLOR_ACCENT);
  
  var tit4 = slide4.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 55, 600, 45);
  tit4.getText().setText("Engenharia Distribuída em 4 Pilares");
  tit4.getText().getTextStyle().setFontSize(24).setBold(true).setForegroundColor(COLOR_TEXT_LIGHT);
  
  var pillarsData = [
    { title: "1. Coletor Desktop (WPF)", desc: "Daemon em segundo plano para Windows com pop-ups e captura atômica." },
    { title: "2. Central Analytics (Web)", desc: "Painel em Dark Mode com visões de qualidade (research_session_quality)." },
    { title: "3. Simulador Web (React)", desc: "Ambiente navegável para testes de cenários em Linux, macOS e Windows." },
    { title: "4. Backend & GitOps", desc: "Supabase PostgreSQL com RLS e atualização remota via config.json." }
  ];
  
  for (var p = 0; p < pillarsData.length; p++) {
    var col = p % 2;
    var row = Math.floor(p / 2);
    var posX = 50 + col * 320;
    var posY = 120 + row * 125;
    
    var pCard = slide4.insertShape(SlidesApp.ShapeType.ROUNDED_RECTANGLE, posX, posY, 300, 110);
    pCard.getFill().setSolidFill(COLOR_CARD_BG);
    pCard.getLineFill().setSolidFill('#334155');
    
    var pText = slide4.insertShape(SlidesApp.ShapeType.TEXT_BOX, posX + 10, posY + 10, 280, 90);
    pText.getText().setText(pillarsData[p].title + "\n" + pillarsData[p].desc);
    pText.getText().getRuns()[0].getTextStyle().setFontSize(15).setBold(true).setForegroundColor(COLOR_ACCENT);
  }
  slide4.getNotesPage().getSpeakerNotesShape().getText().setText("A arquitetura é dividida em quatro pilares principais, garantindo resiliência offline, segurança no Supabase e flexibilidade via GitOps.");

  // SLIDE 5: MMLA
  var slide5 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  slide5.getBackground().setSolidFill(COLOR_LIGHT_BG);
  
  var sec5 = slide5.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 30, 600, 30);
  sec5.getText().setText("METODOLOGIA MMLA");
  sec5.getText().getTextStyle().setFontSize(13).setBold(true).setForegroundColor(COLOR_PRIMARY);
  
  var tit5 = slide5.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 55, 600, 45);
  tit5.getText().setText("Triangulação Multimodal & Visual Grounding");
  tit5.getText().getTextStyle().setFontSize(24).setBold(true).setForegroundColor(COLOR_TEXT_DARK);
  
  var mmlaData = [
    "Contexto da Sessão: Escola, turma, idade, autoeficácia e papel atribuído (Montador ou Programador).",
    "Processo Percebido: Auto-relato ordinal de esforço mental (1-4), bloqueios e pedidos de ajuda.",
    "Grounding Visual & Telemetria: Screenshot da janela do LEGO SPIKE no ms exato + inatividade minimizada.",
    "Métricas de Qualidade: Linha do tempo auditável com latência de resposta, declínios e resiliência offline."
  ];
  
  for (var m = 0; m < mmlaData.length; m++) {
    var posY = 115 + m * 62;
    var mBox = slide5.insertShape(SlidesApp.ShapeType.RECTANGLE, 50, posY, 620, 54);
    mBox.getFill().setSolidFill(COLOR_CARD_LIGHT);
    mBox.getLineFill().setSolidFill('#CBD5E1');
    mBox.getText().setText(mmlaData[m]);
    mBox.getText().getTextStyle().setFontSize(13).setForegroundColor(COLOR_TEXT_MUTED);
  }
  slide5.getNotesPage().getSpeakerNotesShape().getText().setText("No exato milissegundo em que o aluno responde, o agente captura a tela do LEGO SPIKE. Isso gera o grounding visual indispensável para validar o relato subjetivo.");

  // SLIDE 6: LGPD
  var slide6 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  slide6.getBackground().setSolidFill(COLOR_LIGHT_BG);
  
  var sec6 = slide6.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 30, 600, 30);
  sec6.getText().setText("SEGURANÇA & ÉTICA");
  sec6.getText().getTextStyle().setFontSize(13).setBold(true).setForegroundColor(COLOR_PRIMARY);
  
  var tit6 = slide6.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 55, 600, 45);
  tit6.getText().setText("Proteção Rigorosa dos Dados (LGPD by Design)");
  tit6.getText().getTextStyle().setFontSize(24).setBold(true).setForegroundColor(COLOR_TEXT_DARK);
  
  var lgpdData = [
    { title: "Pseudonimização Total", desc: "Identificação por installation_id por máquina. Nenhum nome de estudante é armazenado." },
    { title: "Telemetria Minimizada", desc: "Coleta apenas categorias de softwares (ex: IDE, Navegador). Sem títulos de janela ou keylogging." },
    { title: "Bucket Privado & RLS", desc: "Screenshots gravados em bucket privado do Supabase com acesso restrito a backend autorizado." },
    { title: "Zero Biometria ou Áudio", desc: "Nenhuma gravação de áudio, imagem de webcam ou rastreamento facial é utilizada." }
  ];
  
  for (var g = 0; g < lgpdData.length; g++) {
    var col = g % 2;
    var row = Math.floor(g / 2);
    var posX = 50 + col * 320;
    var posY = 120 + row * 125;
    
    var gCard = slide6.insertShape(SlidesApp.ShapeType.ROUNDED_RECTANGLE, posX, posY, 300, 110);
    gCard.getFill().setSolidFill(COLOR_CARD_LIGHT);
    gCard.getLineFill().setSolidFill('#CBD5E1');
    
    var gText = slide6.insertShape(SlidesApp.ShapeType.TEXT_BOX, posX + 10, posY + 10, 280, 90);
    gText.getText().setText(lgpdData[g].title + "\n" + lgpdData[g].desc);
    gText.getText().getRuns()[0].getTextStyle().setFontSize(15).setBold(true).setForegroundColor(COLOR_PRIMARY);
  }
  slide6.getNotesPage().getSpeakerNotesShape().getText().setText("Tudo foi construído sob estritos princípios da LGPD e diretrizes éticas do CEP/CONEP: sem captura de nomes, webcam ou áudio.");

  // SLIDE 7: Recursos
  var slide7 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  slide7.getBackground().setSolidFill(COLOR_LIGHT_BG);
  
  var sec7 = slide7.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 30, 600, 30);
  sec7.getText().setText("RECURSOS DO PROJETO");
  sec7.getText().getTextStyle().setFontSize(13).setBold(true).setForegroundColor(COLOR_PRIMARY);
  
  var tit7 = slide7.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 55, 600, 45);
  tit7.getText().setText("Entregáveis & Ferramentas de Demonstração");
  tit7.getText().getTextStyle().setFontSize(24).setBold(true).setForegroundColor(COLOR_TEXT_DARK);
  
  var delivData = [
    "Landing Page GitHub Pages: Página interativa com galeria visual e simulador ao vivo (index.html).",
    "Simulador Web Navegável: Ambiente React para homologar o agente sem máquinas Windows (web/agent-simulator).",
    "Relatório Acadêmico v1.4: Fundamentação psicométrica e modelos de estatística ordinal (docs/).",
    "Framework de TCC & Banca: Roteiro de capítulos e fundamentação técnica para bancas examinadoras."
  ];
  
  for (var d = 0; d < delivData.length; d++) {
    var posY = 115 + d * 62;
    var dBox = slide7.insertShape(SlidesApp.ShapeType.RECTANGLE, 50, posY, 620, 54);
    dBox.getFill().setSolidFill(COLOR_CARD_LIGHT);
    dBox.getLineFill().setSolidFill('#CBD5E1');
    dBox.getText().setText(delivData[d]);
    dBox.getText().getTextStyle().setFontSize(13).setForegroundColor(COLOR_TEXT_MUTED);
  }
  slide7.getNotesPage().getSpeakerNotesShape().getText().setText("O projeto conta com landing page, simulador web para testes navegáveis e toda a fundamentação acadêmica documentada.");

  // SLIDE 8: Conclusão
  var slide8 = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
  slide8.getBackground().setSolidFill(COLOR_DARK_BG);
  
  var tit8 = slide8.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 50, 620, 60);
  tit8.getText().setText("O Futuro da Observabilidade em Robótica Educativa");
  tit8.getText().getTextStyle().setFontSize(28).setBold(true).setForegroundColor(COLOR_TEXT_LIGHT);
  
  var quote8 = slide8.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 130, 620, 80);
  quote8.getText().setText("\"O PulseLab não substitui o professor nem julga o aluno: ele ilumina a jornada do aprendizado em robótica.\"");
  quote8.getText().getTextStyle().setFontSize(18).setItalic(true).setForegroundColor(COLOR_ACCENT);
  
  var body8 = slide8.insertShape(SlidesApp.ShapeType.TEXT_BOX, 50, 230, 620, 120);
  body8.getText().setText("• Escala multicêntrica de baixo custo logístico\n• Integração imediata entre pesquisa e ação pedagógica\n• Transparência total sobre a qualidade e amostragem dos dados");
  body8.getText().getTextStyle().setFontSize(15).setForegroundColor(COLOR_TEXT_SUB);
  
  slide8.getNotesPage().getSpeakerNotesShape().getText().setText("Com o PulseLab, conseguimos entender não apenas SE o aluno aprendeu, mas COMO o aprendizado e a colaboração acontecem a cada minuto.");
}
