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
    Guia Operacional Ilustrado
  </span>
  <h1 style="font-size: 3rem; margin-top: 12px; color: #1e40af;">
    PulseLab 1.7.0
  </h1>
  <p style="font-size: 1.25rem; color: #475569; max-width: 840px; margin: 0 auto 24px auto; font-weight: 600;">
    Instalação 100% offline, jornada simplificada por dupla, telemetria automática do LEGO SPIKE (.llsp3) e check-ins rápidos.
  </p>

  <div style="display: flex; justify-content: center; gap: 16px; margin-top: 10px;">
    <div class="card-panel" style="background:#eff6ff; border-color:#bfdbfe; width: 210px; text-align: center;">
      <div style="font-size: 1.6rem; margin-bottom: 2px;">📦</div>
      <strong style="color: #1e3a8a; font-size: 0.95rem;">1. Instalação Offline</strong>
      <p style="font-size: 0.75rem; color:#64748b; margin: 2px 0 0 0;">ZIP ~92 KB · Zero Internet</p>
    </div>
    <div class="card-panel" style="background:#f0fdf4; border-color:#bbf7d0; width: 210px; text-align: center;">
      <div style="font-size: 1.6rem; margin-bottom: 2px;">👥</div>
      <strong style="color: #166534; font-size: 0.95rem;">2. Resposta por Dupla</strong>
      <p style="font-size: 0.75rem; color:#64748b; margin: 2px 0 0 0;">15s no início · Sem burocracia</p>
    </div>
    <div class="card-panel" style="background:#faf5ff; border-color:#e9d5ff; width: 210px; text-align: center;">
      <div style="font-size: 1.6rem; margin-bottom: 2px;">🤖</div>
      <strong style="color: #6b21a8; font-size: 0.95rem;">3. Telemetria SPIKE</strong>
      <p style="font-size: 0.75rem; color:#64748b; margin: 2px 0 0 0;">Parser de blocos & fases</p>
    </div>
    <div class="card-panel" style="background:#fffbeb; border-color:#fde68a; width: 210px; text-align: center;">
      <div style="font-size: 1.6rem; margin-bottom: 2px;">⏱️</div>
      <strong style="color: #92400e; font-size: 0.95rem;">4. Checkpoints 20/40m</strong>
      <p style="font-size: 0.75rem; color:#64748b; margin: 2px 0 0 0;">Alertas nativos & Fechamento</p>
    </div>
  </div>
</div>

---

<!-- Slide 2: Etapa 1 - Instalação do Pacote ZIP -->
## <span class="badge" style="background:#dbeafe; color:#1e40af;">Etapa 1</span> Como Instalar o Pacote ZIP (100% Offline)

<div class="grid-2">
  <div>
    <ul class="step-list">
      <li class="step-item">
        <span class="step-num">1</span>
        <div><strong>Baixar o ZIP:</strong> Baixe <code>PulseLab-1.7.0-Windows.zip</code> (~92 KB) diretamente ou transporte por pendrive.</div>
      </li>
      <li class="step-item">
        <span class="step-num">2</span>
        <div><strong>Extrair:</strong> Clique com o botão direito sobre o arquivo <code>.zip</code> e escolha <em>"Extrair Tudo..."</em> em qualquer pasta (ex: Área de Trabalho).</div>
      </li>
      <li class="step-item">
        <span class="step-num">3</span>
        <div><strong>Instalação com 2 Cliques:</strong> Dê dois cliques em <code>Instalar-PulseLab.bat</code> (cria atalho na Área de Trabalho) ou em <code>Iniciar-PulseLab.bat</code> (roda direto sem instalar).</div>
      </li>
      <li class="step-item">
        <span class="step-num">4</span>
        <div><strong>Zero Configuração:</strong> O Bridge HTTP local sobe em segundo plano e abre a aplicação em <code>http://127.0.0.1:43127/alunos/</code>.</div>
      </li>
    </ul>

    <div class="highlight-box">
      ✨ <strong>Pronto para usar:</strong> A interface web abre no navegador padrão com relógio e alertas sonoros ativos no Windows!
    </div>
  </div>

  <div class="img-container">
    <img src="images/01-instalacao.jpg" alt="Tela de Instalação e Execução" />
  </div>
</div>

---

<!-- Slide 3: Etapa 2 - Como Funciona a Jornada da Dupla -->
## <span class="badge" style="background:#dcfce7; color:#166534;">Etapa 2</span> Jornada Rápida da Dupla (Sem Burocracia)

<div class="grid-2">
  <div>
    <ul class="step-list">
      <li class="step-item">
        <span class="step-num" style="background:#16a34a;">1</span>
        <div><strong>Preparação Instantânea:</strong> O instrutor confere a turma e clica em <em>"Iniciar Oficina"</em>. Não há termos de consentimento repetitivos nem divisão de alunos A/B.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#16a34a;">2</span>
        <div><strong>Início Rápido (15 segundos):</strong> A dupla responde apenas 2 perguntas sobre experiência prévia e confiança para o desafio.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#16a34a;">3</span>
        <div><strong>Foco no SPIKE:</strong> Ao clicar em <em>"Começar Atividade"</em>, o cronômetro inicia em segundo plano e a dupla pode focar 100% na montagem do robô.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#16a34a;">4</span>
        <div><strong>Persistência Local:</strong> Todos os dados ficam protegidos no armazenamento local (IndexedDB) com tolerância total a quedas de energia ou fechamento acidental.</div>
      </li>
    </ul>
  </div>

  <div class="img-container">
    <img src="images/02-como-usar.jpg" alt="Tela de Atividade e Cronômetro" />
  </div>
</div>

---

<!-- Slide 4: Etapa 3 - Telemetria Automática do LEGO SPIKE 3 -->
## <span class="badge" style="background:#f3e8ff; color:#6b21a8;">Etapa 3</span> Telemetria Automática do LEGO SPIKE (.llsp3)

<div class="grid-2">
  <div>
    <ul class="step-list">
      <li class="step-item">
        <span class="step-num" style="background:#9333ea;">1</span>
        <div><strong>Captura Invisível:</strong> O servidor Bridge local monitora a pasta de projetos do LEGO SPIKE App 3 em <code>Documents\LEGO Education\SPIKE 3</code>.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#9333ea;">2</span>
        <div><strong>Parser Estrutural:</strong> Extrai a quantidade de blocos programados, uso de motores, sensores de cor/distância, laços de repetição e condições lógicas.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#9333ea;">3</span>
        <div><strong>Inferência de Estágios:</strong> Classifica o progresso da equipe (<em>Movimento Básico $\rightarrow$ Reativo a Sensores $\rightarrow$ Laço Autônomo $\rightarrow$ Missão Integrada</em>).</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#9333ea;">4</span>
        <div><strong>100% Ético & LGPD:</strong> Não coleta nomes, fotos, telas, variáveis de texto ou códigos do Hub.</div>
      </li>
    </ul>
  </div>

  <div class="img-container">
    <img src="images/03-encerramento.jpg" alt="Telemetria Estrutural do SPIKE" />
  </div>
</div>

---

<!-- Slide 5: Etapa 4 - Checkpoints e Encerramento -->
## <span class="badge" style="background:#fef3c7; color:#92400e;">Etapa 4</span> Check-ins (20 e 40 min) & Encerramento

<div class="grid-2">
  <div>
    <ul class="step-list">
      <li class="step-item">
        <span class="step-num" style="background:#d97706;">1</span>
        <div><strong>Alertas Sonoros e Visuais:</strong> Aos 20 e 40 minutos de oficina, o Bridge emite um aviso discreto no Windows chamando a atenção da dupla.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#d97706;">2</span>
        <div><strong>Check-in de 20 Segundos:</strong> 3 perguntas rápidas (esforço mental, situação do avanço e colaboração da equipe) + botão de pedir ajuda ao instrutor.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#d97706;">3</span>
        <div><strong>Sem Troca de Telas:</strong> Ao salvar o check-in de 20min, a dupla volta direto para a montagem sem interrupções.</div>
      </li>
      <li class="step-item">
        <span class="step-num" style="background:#d97706;">4</span>
        <div><strong>Fechamento:</strong> No final da aula, 3 perguntas de autoavaliação encerram o ciclo e salvam o arquivo JSON da oficina.</div>
      </li>
    </ul>
  </div>

  <div class="img-container">
    <img src="images/04-suporte.jpg" alt="Check-in Rápido e Fechamento" />
  </div>
</div>
