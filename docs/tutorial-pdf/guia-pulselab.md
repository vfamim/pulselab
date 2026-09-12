---
marp: true
theme: default
paginate: true
size: 16:9
style: |
  @import url("https://fonts.googleapis.com/css2?family=Fredoka:wght@400;600;700&family=Nunito:wght@400;600;700;800&display=swap");

  section {
    font-family: "Nunito", sans-serif;
    background-color: #f8fafc;
    color: #1e293b;
    padding: 28px 40px;
  }

  h1, h2, h3 {
    font-family: "Fredoka", sans-serif;
    color: #0f172a;
    letter-spacing: -0.02em;
  }

  h1 {
    font-size: 2.2rem;
    color: #2563eb;
    margin-bottom: 0.3rem;
  }

  h2 {
    font-size: 1.45rem;
    margin-bottom: 0.4rem;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .badge {
    background-color: #e0e7ff;
    color: #3730a3;
    font-size: 0.82rem;
    font-weight: 800;
    padding: 4px 12px;
    border-radius: 9999px;
    display: inline-block;
    text-transform: uppercase;
  }

  .card-panel {
    background: #ffffff;
    border: 2px solid #e2e8f0;
    border-radius: 12px;
    padding: 10px 14px;
    box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.04);
    margin-bottom: 6px;
  }

  .grid-2 {
    display: grid;
    grid-template-columns: 1.18fr 1.02fr;
    gap: 20px;
    align-items: center;
  }

  .step-list {
    list-style: none;
    padding-left: 0;
    margin: 0;
  }

  .step-item {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    margin-bottom: 8px;
    font-size: 0.88rem;
    line-height: 1.32;
  }

  .step-num {
    background: #2563eb;
    color: white;
    font-weight: 800;
    width: 22px;
    height: 22px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.76rem;
    flex-shrink: 0;
    margin-top: 2px;
  }

  .highlight-box {
    background: #f1f5f9;
    border-left: 5px solid #2563eb;
    padding: 8px 12px;
    border-radius: 0 10px 10px 0;
    font-size: 0.82rem;
    margin-top: 6px;
  }

  .img-container {
    border-radius: 14px;
    overflow: hidden;
    border: 3px solid #cbd5e1;
    box-shadow: 0 8px 16px -2px rgba(0, 0, 0, 0.08);
  }

  .img-container img {
    width: 100%;
    height: auto;
    display: block;
  }

  .btn-badge {
    display: inline-block;
    padding: 2px 8px;
    border-radius: 6px;
    font-family: monospace;
    font-weight: 700;
    font-size: 0.8rem;
    background: #e2e8f0;
    color: #1e293b;
    border: 1px solid #cbd5e1;
  }

  footer {
    font-size: 0.72rem;
    color: #64748b;
    font-weight: 600;
  }
---

<!-- Slide 1: Capa -->
<div style="text-align: center; padding-top: 14px;">
  <span class="badge" style="background:#dbeafe; color:#1d4ed8; font-size:0.95rem; padding: 5px 14px;">
    Guia Operacional Ilustrado
  </span>
  <h1 style="font-size: 2.8rem; margin-top: 10px; color: #1e40af;">
    PulseLab 1.7.1
  </h1>
  <p style="font-size: 1.15rem; color: #475569; max-width: 860px; margin: 0 auto 20px auto; font-weight: 600;">
    Instalação 100% offline, controles do pesquisador, telemetria passiva do LEGO SPIKE (.llsp3) e check-ins rápidos por dupla.
  </p>

  <div style="display: flex; justify-content: center; gap: 14px; margin-top: 8px; flex-wrap: wrap;">
    <div class="card-panel" style="background:#eff6ff; border-color:#bfdbfe; width: 195px; text-align: center;">
      <div style="font-size: 1.5rem; margin-bottom: 2px;">📦</div>
      <strong style="color: #1e3a8a; font-size: 0.9rem;">1. Instalação Offline</strong>
      <p style="font-size: 0.72rem; color:#64748b; margin: 2px 0 0 0;">ZIP autônomo · Sem login</p>
    </div>
    <div class="card-panel" style="background:#f0fdf4; border-color:#bbf7d0; width: 195px; text-align: center;">
      <div style="font-size: 1.5rem; margin-bottom: 2px;">👥</div>
      <strong style="color: #166534; font-size: 0.9rem;">2. Resposta por Dupla</strong>
      <p style="font-size: 0.72rem; color:#64748b; margin: 2px 0 0 0;">15s no início · Sem fila</p>
    </div>
    <div class="card-panel" style="background:#fdf4ff; border-color:#f5d0fe; width: 195px; text-align: center;">
      <div style="font-size: 1.5rem; margin-bottom: 2px;">⚙️</div>
      <strong style="color: #86198f; font-size: 0.9rem;">3. Botões & Controles</strong>
      <p style="font-size: 0.72rem; color:#64748b; margin: 2px 0 0 0;">Reset, avanços e export</p>
    </div>
    <div class="card-panel" style="background:#faf5ff; border-color:#e9d5ff; width: 195px; text-align: center;">
      <div style="font-size: 1.5rem; margin-bottom: 2px;">🤖</div>
      <strong style="color: #6b21a8; font-size: 0.9rem;">4. Telemetria SPIKE</strong>
      <p style="font-size: 0.72rem; color:#64748b; margin: 2px 0 0 0;">Parser de blocos .llsp3</p>
    </div>
    <div class="card-panel" style="background:#fffbeb; border-color:#fde68a; width: 195px; text-align: center;">
      <div style="font-size: 1.5rem; margin-bottom: 2px;">⏱️</div>
      <strong style="color: #92400e; font-size: 0.9rem;">5. Check-ins 20/40m</strong>
      <p style="font-size: 0.72rem; color:#64748b; margin: 2px 0 0 0;">Alertas e foco inteligente</p>
    </div>
  </div>
</div>

---

<!-- Slide 2: Etapa 1 - Instalação Passo a Passo -->
## <span class="badge" style="background:#dbeafe; color:#1e40af;">Etapa 1</span> Instalação Passo a Passo (100% Offline)

<div class="grid-2">
  <div>
    <ul class="step-list">
      <li class="step-item">
        <span class="step-num">1</span>
        <div><strong>Baixar o ZIP:</strong> Obtenha <code>PulseLab-1.7.1-Windows.zip</code> (~318 KB) pela web ou transporte via pendrive para os computadores da escola.</div>
      </li>
      <li class="step-item">
        <span class="step-num">2</span>
        <div><strong>Extrair os Arquivos:</strong> Clique com botão direito no <code>.zip</code> e selecione <em>"Extrair Tudo..."</em> para uma pasta (ex: Área de Trabalho).</div>
      </li>
      <li class="step-item">
        <span class="step-num">3</span>
        <div><strong>Modo Instalador (Recomendado):</strong> Dê dois cliques em <code>Instalar-PulseLab.bat</code>. Ele copia os arquivos para <code>%LOCALAPPDATA%\PulseLab</code> e cria o atalho oficial <strong>"PulseLab - Iniciar Oficina"</strong> na Área de Trabalho com o ícone do robô.</div>
      </li>
      <li class="step-item">
        <span class="step-num">4</span>
        <div><strong>Modo Portátil (Opcional):</strong> Se preferir rodar direto sem instalar nada, basta executar <code>Iniciar-PulseLab.bat</code>.</div>
      </li>
    </ul>

    <div class="highlight-box">
      🛡️ <strong>Imune a Deep Freeze:</strong> A aplicação utiliza gravação dupla (IndexedDB + arquivo local em disco), garantindo que os dados não se percam em reinicializações.
    </div>
  </div>

  <div class="img-container">
    <img src="images/01-instalacao.jpg" alt="Instalação do PulseLab no Windows" />
  </div>
</div>

---

<!-- Slide 3: Etapa 2 - Jornada da Dupla -->
## <span class="badge" style="background:#dcfce7; color:#166534;">Etapa 2</span> Como Usar a Aplicação: Jornada da Dupla

<div class="grid-2">
  <div>
    <ul class="step-list">
      <li class="step-item">
        <span class="step-num" style="background:#16a34a;">1</span>
        <div><strong>Abertura Automática:</strong> Ao executar o atalho, o Bridge sobe em segundo plano e abre a aplicação no navegador padrão em <code>http://127.0.0.1:43127/alunos/</code>.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#16a34a;">2</span>
        <div><strong>Início Rápido (15 segundos):</strong> A dupla escolhe os papéis iniciais (quem programa e quem monta) e responde 2 perguntas rápidas de clareza do desafio e ânimo da equipe.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#16a34a;">3</span>
        <div><strong>Foco no LEGO SPIKE:</strong> Ao clicar em <em>"Começar Atividade"</em>, o cronômetro começa a rodar. A aba pode ficar em segundo plano enquanto os alunos utilizam o app do SPIKE.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#16a34a;">4</span>
        <div><strong>Zero Burocracia:</strong> Sem cadastros individuais nominais, sem senhas e sem coletar informações privadas das crianças.</div>
      </li>
    </ul>

    <div class="highlight-box" style="border-left-color: #16a34a;">
      ⏱️ <strong>Tempo Real:</strong> O relógio avança minuto a minuto e agenda automaticamente os alertas aos 20m e aos 40m.
    </div>
  </div>

  <div class="img-container">
    <img src="images/02-como-usar.jpg" alt="Tela de Atividade e Cronômetro" />
  </div>
</div>

---

<!-- Slide 4: Etapa 3 - Guia de Botões e Controles -->
## <span class="badge" style="background:#fdf4ff; color:#86198f;">Etapa 3</span> Guia de Botões e Controles Disponíveis

<div class="grid-2">
  <div>
    <p style="font-size: 0.86rem; color:#475569; margin-bottom: 8px;">
      O PulseLab dispõe de ferramentas para o pesquisador demonstrar ou controlar a oficina a qualquer instante:
    </p>

    <div class="card-panel" style="border-color:#d8b4fe; background:#faf5ff;">
      <strong style="color:#7e22ce; font-size: 0.88rem;">Painel do Pesquisador: Botão <span class="btn-badge">⚙️ Controles</span></strong>
      <ul style="font-size: 0.8rem; margin: 4px 0 0 16px; padding: 0; line-height: 1.35;">
        <li><span class="btn-badge">🔄 Reiniciar</span>: Zera a sessão atual e volta à tela inicial (ideal para novas turmas ou reinício de teste).</li>
        <li><span class="btn-badge">⏩ Check-in 20m</span>: Força o salto temporal imediato para o marco de 20 min sem esperar o relógio real.</li>
        <li><span class="btn-badge">⏩ Fechamento 40m</span>: Força o salto temporal para a tela de encerramento da oficina.</li>
        <li><span class="btn-badge">✨ Preencher teste</span>: Preenche as opções automaticamente para validações rápidas.</li>
      </ul>
    </div>

    <div class="card-panel" style="border-color:#cbd5e1; background:#ffffff;">
      <strong style="color:#1e293b; font-size: 0.88rem;">Botões Operacionais dos Alunos</strong>
      <ul style="font-size: 0.8rem; margin: 4px 0 0 16px; padding: 0; line-height: 1.35;">
        <li><span class="btn-badge">📥 Exportar Dados</span>: Na barra superior, baixa o arquivo <code>.json</code> completo da oficina para pen-drive ou backup.</li>
        <li><span class="btn-badge">Pedir Ajuda</span>: Notifica necessidade de apoio pedagógico durante a montagem.</li>
        <li><span class="btn-badge">Salvar e Continuar</span>: Confirma as respostas do check-in e volta direto à atividade.</li>
      </ul>
    </div>
  </div>

  <div class="img-container">
    <img src="images/03-encerramento.jpg" alt="Painel de Controles e Botões" />
  </div>
</div>

---

<!-- Slide 5: Etapa 4 - Alertas Visuais, Sonoros e Foco Inteligente -->
## <span class="badge" style="background:#fef3c7; color:#92400e;">Etapa 4</span> Alertas Visuais, Sonoros e Foco Inteligente

<div class="grid-2">
  <div>
    <ul class="step-list">
      <li class="step-item">
        <span class="step-num" style="background:#d97706;">1</span>
        <div><strong>Robô Mascote na Tela:</strong> Ao completar 20 min e 40 min, um modal animado com o robozinho PulseLab surge na tela do navegador.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#d97706;">2</span>
        <div><strong>Acorde Sonoro Harmônico:</strong> Sintetizado via Web Audio API nativa (notas C5-E5-G5-C6), o som toca sem necessitar de arquivos externos ou internet.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#d97706;">3</span>
        <div><strong>Pop-up Toast no Windows:</strong> Caso o navegador esteja minimizado, o Bridge exibe um pop-up nativo com som no canto inferior direito da tela.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#d97706;">4</span>
        <div><strong>Foco sem Duplicatas:</strong> Ao clicar em <em>"Responder agora"</em>, o Windows traz a janela já aberta do navegador direto para o topo da tela, sem criar novas abas e preservando o tempo exato!</div>
      </li>
    </ul>

    <div class="highlight-box" style="border-left-color: #d97706;">
      🛡️ <strong>Zero Conflito:</strong> Garante que duas abas nunca concorram pelo mesmo cronômetro ou sobrescrevam respostas.
    </div>
  </div>

  <div class="img-container">
    <img src="images/04-suporte.jpg" alt="Alerta com Robô e Pop-up do Windows" />
  </div>
</div>

---

<!-- Slide 6: Etapa 5 - Telemetria do SPIKE Prime -->
## <span class="badge" style="background:#f3e8ff; color:#6b21a8;">Etapa 5</span> Telemetria Automática do LEGO SPIKE (.llsp3)

<div class="grid-2">
  <div>
    <ul class="step-list">
      <li class="step-item">
        <span class="step-num" style="background:#9333ea;">1</span>
        <div><strong>Varredura Transparente:</strong> O Bridge monitora a pasta de projetos em <code>Documents\LEGO Education\SPIKE 3</code> silenciosamente a cada 15 segundos.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#9333ea;">2</span>
        <div><strong>Extração de Complexidade:</strong> Abre o <code>.llsp3</code> localmente e contabiliza blocos de motores, sensores, laços (<code>forever</code>, <code>repeat</code>) e condicionais (<code>if/else</code>).</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#9333ea;">3</span>
        <div><strong>Indicador Visual na PWA:</strong> Quando detectado, a barra verde exibe: <em>"🤖 LEGO SPIKE Conectado: X blocos detectados · Estágio inferido"</em>.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#9333ea;">4</span>
        <div><strong>Proteção Ética Absoluta (LGPD):</strong> O parser não lê nomes de variáveis criadas pelos alunos, textos digitados, fotos ou códigos do robô.</div>
      </li>
    </ul>
  </div>

  <div class="img-container">
    <img src="images/02-como-usar.jpg" alt="Telemetria SPIKE Integrada" />
  </div>
</div>

---

<!-- Slide 7: Etapa 6 - Encerramento e Persistência -->
## <span class="badge" style="background:#ecfdf5; color:#065f46;">Etapa 6</span> Fechamento, Exportação e Persistência Segura

<div class="grid-2">
  <div>
    <ul class="step-list">
      <li class="step-item">
        <span class="step-num" style="background:#059669;">1</span>
        <div><strong>Autoavaliação Final (3 perguntas):</strong> Aos 40 minutos, a dupla avalia a compreensão do que foi programado, o desejo de participar de novas oficinas e o sentimento final.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#059669;">2</span>
        <div><strong>Gravação Dupla no Computador:</strong> Os eventos da oficina são gravados tanto no IndexedDB do navegador quanto em <code>%LOCALAPPDATA%\PulseLab\data\events.jsonl</code>.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#059669;">3</span>
        <div><strong>Exportação Manual com 1 Clique:</strong> Basta clicar em <span class="btn-badge">📥 Exportar Dados</span> no topo da página para baixar o arquivo JSON completo para conferência.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#059669;">4</span>
        <div><strong>Sincronização em Nuvem:</strong> Se o computador tiver conexão com a internet, os eventos são sincronizados automaticamente com o Supabase da pesquisa.</div>
      </li>
    </ul>

    <div class="highlight-box" style="border-left-color: #059669;">
      🎉 <strong>Oficina Concluída com Sucesso:</strong> A dupla finaliza a atividade com sensação de dever cumprido e a pesquisa científica obtém dados fidedignos e auditáveis!
    </div>
  </div>

  <div class="img-container">
    <img src="images/03-encerramento.jpg" alt="Tela de Fechamento da Oficina" />
  </div>
</div>
