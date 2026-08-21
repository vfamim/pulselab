---
marp: true
theme: default
paginate: true
size: 16:9
style: |
  @import url('https://fonts.googleapis.com/css2?family=Fredoka:wght@400;600;700&family=Nunito:wght@400;600;700;800&display=swap');

  section {
    font-family: 'Nunito', sans-serif;
    background-color: #f8fafc;
    color: #1e293b;
    padding: 32px 44px;
  }

  h1, h2, h3 {
    font-family: 'Fredoka', sans-serif;
    color: #0f172a;
    letter-spacing: -0.02em;
  }

  h1 {
    font-size: 2.2rem;
    color: #2563eb;
    margin-bottom: 0.3rem;
  }

  h2 {
    font-size: 1.5rem;
    margin-bottom: 0.5rem;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .badge {
    background-color: #e0e7ff;
    color: #3730a3;
    font-size: 0.85rem;
    font-weight: 800;
    padding: 4px 12px;
    border-radius: 9999px;
    display: inline-block;
    text-transform: uppercase;
  }

  .card-panel {
    background: #ffffff;
    border: 2px solid #e2e8f0;
    border-radius: 14px;
    padding: 12px 16px;
    box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.04);
    margin-bottom: 8px;
  }

  .grid-2 {
    display: grid;
    grid-template-columns: 1.18fr 1.02fr;
    gap: 22px;
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
    font-size: 0.92rem;
    line-height: 1.32;
  }

  .step-num {
    background: #2563eb;
    color: white;
    font-weight: 800;
    width: 24px;
    height: 24px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.8rem;
    flex-shrink: 0;
    margin-top: 2px;
  }

  .highlight-box {
    background: #f1f5f9;
    border-left: 5px solid #2563eb;
    padding: 8px 12px;
    border-radius: 0 10px 10px 0;
    font-size: 0.85rem;
    margin-top: 8px;
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

  footer {
    font-size: 0.72rem;
    color: #64748b;
    font-weight: 600;
  }
---

<!-- Slide 1: Capa -->
<div style="text-align: center; padding-top: 20px;">
  <span class="badge" style="background:#dbeafe; color:#1d4ed8; font-size:0.95rem; padding: 5px 14px;">
    Guia Operacional Passo a Passo
  </span>
  <h1 style="font-size: 3rem; margin-top: 12px; color: #1e40af;">
    PulseLab 1.6.0
  </h1>
  <p style="font-size: 1.25rem; color: #475569; max-width: 820px; margin: 0 auto 24px auto; font-weight: 600;">
    Como instalar o pacote ZIP, conduzir oficinas de robótica, coletar telemetria de interação e concluir o ciclo pela bandeja do sistema.
  </p>

  <div style="display: flex; justify-content: center; gap: 16px; margin-top: 10px;">
    <div class="card-panel" style="background:#eff6ff; border-color:#bfdbfe; width: 210px; text-align: center;">
      <div style="font-size: 1.6rem; margin-bottom: 2px;">📦</div>
      <strong style="color: #1e3a8a; font-size: 0.95rem;">1. Instalação ZIP</strong>
      <p style="font-size: 0.75rem; color:#64748b; margin: 2px 0 0 0;">Setup & Matrícula</p>
    </div>
    <div class="card-panel" style="background:#f0fdf4; border-color:#bbf7d0; width: 210px; text-align: center;">
      <div style="font-size: 1.6rem; margin-bottom: 2px;">🖱️</div>
      <strong style="color: #166534; font-size: 0.95rem;">2. Uso & Telemetria</strong>
      <p style="font-size: 0.75rem; color:#64748b; margin: 2px 0 0 0;">Cliques, Teclas & Checkpoint</p>
    </div>
    <div class="card-panel" style="background:#faf5ff; border-color:#e9d5ff; width: 210px; text-align: center;">
      <div style="font-size: 1.6rem; margin-bottom: 2px;">📥</div>
      <strong style="color: #6b21a8; font-size: 0.95rem;">3. Concluir na Bandeja</strong>
      <p style="font-size: 0.75rem; color:#64748b; margin: 2px 0 0 0;">Botão Direito & Rubrica</p>
    </div>
    <div class="card-panel" style="background:#fffbeb; border-color:#fde68a; width: 210px; text-align: center;">
      <div style="font-size: 1.6rem; margin-bottom: 2px;">🌐</div>
      <strong style="color: #92400e; font-size: 0.95rem;">4. Web & Suporte</strong>
      <p style="font-size: 0.75rem; color:#64748b; margin: 2px 0 0 0;">Portal & Fale Conosco</p>
    </div>
  </div>
</div>

---

<!-- Slide 2: Etapa 1 - Instalação do Pacote ZIP -->
## <span class="badge" style="background:#dbeafe; color:#1e40af;">Etapa 1</span> Como Instalar o Pacote ZIP

<div class="grid-2">
  <div>
    <ul class="step-list">
      <li class="step-item">
        <span class="step-num">1</span>
        <div><strong>Baixar o ZIP:</strong> Baixe o arquivo compactado <code>PulseLab-1.6.0-Windows.zip</code> no computador da oficina.</div>
      </li>
      <li class="step-item">
        <span class="step-num">2</span>
        <div><strong>Extrair Todo o Conteúdo:</strong> Clique com o botão direito sobre o <code>.zip</code> e escolha <em>"Extrair Tudo..."</em> em uma pasta local.</div>
      </li>
      <li class="step-item">
        <span class="step-num">3</span>
        <div><strong>Executar Instalador:</strong> Abra a pasta extraída e dê dois cliques no executável <code>Instalar-PulseLab.bat</code>.</div>
      </li>
      <li class="step-item">
        <span class="step-num">4</span>
        <div><strong>Matrícula e Token:</strong> Preencha Cidade/Escola e digite o <strong>Token de uso único</strong> fornecido pela coordenação.</div>
      </li>
    </ul>

    <div class="highlight-box">
      ✨ <strong>Atalho Criado:</strong> O atalho <em>"Iniciar PulseLab - Oficina de Robótica"</em> será gerado na Área de Trabalho!
    </div>
  </div>

  <div class="img-container">
    <img src="images/01-instalacao.jpg" alt="Tela de Instalação e Matrícula" />
  </div>
</div>

---

<!-- Slide 3: Etapa 2 - Como Usar na Oficina & Telemetria -->
## <span class="badge" style="background:#dcfce7; color:#166534;">Etapa 2</span> Como Usar na Oficina & Telemetria

<div class="grid-2">
  <div>
    <ul class="step-list">
      <li class="step-item">
        <span class="step-num" style="background:#16a34a;">1</span>
        <div><strong>Início & Assentimento:</strong> O instrutor confere a turma e as crianças recebem o convite lúdico de participação.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#16a34a;">2</span>
        <div><strong>Telemetria Automática:</strong> O PulseLab 1.6.0 contabiliza em segundo plano o volume agregado de <strong>cliques do mouse</strong> e <strong>teclas digitadas</strong> (sem registrar o que é digitado, preservando 100% a privacidade).</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#16a34a;">3</span>
        <div><strong>Checkpoints (20 e 40 min):</strong> Janelas leves surgem para avaliar esforço mental, humor da dupla e alternância de papéis.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#16a34a;">4</span>
        <div><strong>Botão de Ajuda:</strong> O botão <em>"Precisamos de Ajuda!"</em> avisa o instrutor imediatamente.</div>
      </li>
    </ul>
  </div>

  <div class="img-container">
    <img src="images/02-como-usar.jpg" alt="Tela de Checkpoint e Telemetria" />
  </div>
</div>

---

<!-- Slide 3: Etapa 3 - Como Encerrar o Ciclo pela Bandeja -->
## <span class="badge" style="background:#f3e8ff; color:#6b21a8;">Etapa 3</span> Como Encerrar o Ciclo (Bandeja do Sistema)

<div class="grid-2">
  <div>
    <ul class="step-list">
      <li class="step-item">
        <span class="step-num" style="background:#9333ea;">1</span>
        <div><strong>Ícone na Bandeja:</strong> No canto inferior direito da tela (perto do relógio do Windows), localize o ícone de pulso do PulseLab.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#9333ea;">2</span>
        <div><strong>Clique com o Botão Direito:</strong> Clique com o botão direito no ícone da bandeja e selecione <strong>"Concluir Oficina"</strong>.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#9333ea;">3</span>
        <div><strong>Rubrica da Missão:</strong> O modal abre para o instrutor registrar as estrelas de desempenho LEGO e intervenções.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#9333ea;">4</span>
        <div><strong>Autoavaliação & Sincronização:</strong> Os alunos respondem ao feedback final e a sessão é enviada à nuvem Supabase.</div>
      </li>
    </ul>
  </div>

  <div class="img-container">
    <img src="images/03-encerramento.jpg" alt="Menu da Bandeja e Conclusão" />
  </div>
</div>

---

<!-- Slide 4: Etapa 4 - Web Portal & Suporte -->
## <span class="badge" style="background:#fef3c7; color:#92400e;">Etapa 4</span> Web Portal, Dúvidas & Fale Comigo

<div class="grid-2">
  <div>
    <div class="card-panel" style="background:#fffbeb; border-color:#fde68a; margin-bottom: 6px;">
      <strong style="color:#92400e;">🌐 Web Portal do PulseLab:</strong>
      <p style="font-size:0.84rem; color:#78350f; margin:2px 0 0 0;">Acesse <a href="https://pulselab-robotica-edu.web.app" target="_blank" style="color:#b45309; font-weight:700;">pulselab-robotica-edu.web.app</a> para acessar o Portal do Instrutor, baixar atualizações e consultar dashboards.</p>
    </div>

    <div class="card-panel" style="background:#f8fafc; border-color:#cbd5e1; margin-bottom: 6px;">
      <strong style="color:#334155;">📶 Offline & Resiliência:</strong>
      <p style="font-size:0.84rem; color:#475569; margin:2px 0 0 0;">Se a internet cair, todas as respostas e telemetria ficam salvas no cache seguro local e sincronizam no próximo sinal.</p>
    </div>

    <div class="highlight-box" style="background:#eff6ff; border-color:#3b82f6; color:#1e40af; margin-top:6px;">
      💬 <strong>Dúvidas ou Suporte?</strong> Fale diretamente com a coordenação do projeto pelo canal institucional ou abra um chamado no portal.
    </div>
  </div>

  <div class="img-container">
    <img src="images/04-suporte.jpg" alt="Web Portal e Suporte" />
  </div>
</div>
