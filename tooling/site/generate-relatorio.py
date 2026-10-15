#!/usr/bin/env python3
"""Gera a versão consolidada do Relatório Metodológico do PulseLab (relatorio/index.html).
Reflete a metodologia ativa v2.3.x:
- Observabilidade silenciosa e não-invasiva
- Bancada coletiva como unidade de análise (LGPD Art. 14)
- Telemetria passiva do LEGO SPIKE Prime (.llsp3 a cada 10s)
- Encerramento ágil de turma (TurmaClosing: 4 carinhas + rubrica do educador)
- Dupla camada de persistência (IndexedDB + Bridge dados_locais/)
- Governança fail-closed por CAAE de CEP e tombstone de retirada ética
"""

import sys
from pathlib import Path

def generate_html(canonical_version: str) -> str:
    return f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="Relatório metodológico consolidado sobre métricas de processo, observabilidade silenciosa, validade e conformidade ética (LGPD Art. 14) do PulseLab v{canonical_version}.">
  <meta name="theme-color" content="#6547a8">
  <title>PulseLab — Relatório Metodológico de Pesquisa (v{canonical_version})</title>
  <style>
    :root {{
      color-scheme: light;
      --ink: #18212f;
      --muted: #606b7a;
      --paper: #fbfaf7;
      --surface: #ffffff;
      --surface-soft: #f3f0e9;
      --line: #ddd8ce;
      --violet: #5b3cc4;
      --violet-deep: #332073;
      --violet-soft: #eee9ff;
      --cyan: #087f8c;
      --cyan-soft: #e2f5f4;
      --green: #287a52;
      --green-soft: #e7f5ec;
      --amber: #92550a;
      --amber-soft: #fff2d6;
      --red: #a82e2e;
      --red-soft: #fde8e8;
      --shadow: 0 18px 55px rgba(39, 30, 73, 0.10);
      --radius: 18px;
      --content: 1240px;
    }}

    * {{ box-sizing: border-box; }}

    html {{
      scroll-behavior: smooth;
      scroll-padding-top: 28px;
    }}

    body {{
      margin: 0;
      color: var(--ink);
      background:
        radial-gradient(circle at 8% 0%, rgba(91, 60, 196, 0.10), transparent 30rem),
        radial-gradient(circle at 100% 22%, rgba(8, 127, 140, 0.08), transparent 29rem),
        var(--paper);
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      font-size: 16px;
      line-height: 1.7;
      text-rendering: optimizeLegibility;
    }}

    a {{
      color: var(--violet-deep);
      text-decoration-thickness: 1px;
      text-underline-offset: 3px;
    }}

    a:hover {{ color: var(--cyan); }}
    button {{ font: inherit; }}

    .reading-progress {{
      position: fixed;
      z-index: 100;
      inset: 0 auto auto 0;
      width: 0;
      height: 4px;
      background: linear-gradient(90deg, #8b6fff, #58dfd2);
      box-shadow: 0 1px 8px rgba(91, 60, 196, 0.24);
    }}

    .hero {{
      position: relative;
      overflow: hidden;
      color: var(--ink);
      background:
        radial-gradient(circle at 88% 10%, rgba(73, 217, 206, 0.24), transparent 24rem),
        radial-gradient(circle at 10% 90%, rgba(243, 124, 127, 0.15), transparent 20rem),
        linear-gradient(125deg, #f8f7fb, #eee8ff 62%, #e2f5f4);
      border-bottom: 1px solid var(--line);
    }}

    .hero::before,
    .hero::after {{
      content: "";
      position: absolute;
      border: 1px solid rgba(101, 71, 168, 0.15);
      border-radius: 50%;
      pointer-events: none;
    }}

    .hero::before {{
      width: 30rem;
      height: 30rem;
      right: -9rem;
      top: -17rem;
    }}

    .hero::after {{
      width: 18rem;
      height: 18rem;
      right: 12rem;
      bottom: -13rem;
    }}

    .hero-inner {{
      position: relative;
      z-index: 1;
      width: min(calc(100% - 40px), var(--content));
      margin: 0 auto;
      padding: 68px 0 56px;
    }}

    .eyebrow {{
      display: inline-flex;
      align-items: center;
      gap: 9px;
      margin: 0 0 20px;
      padding: 7px 12px;
      color: var(--violet-deep);
      background: rgba(255,255,255,0.68);
      border: 1px solid rgba(101, 71, 168, 0.20);
      border-radius: 999px;
      font-size: 0.78rem;
      font-weight: 760;
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }}

    .eyebrow::before {{
      content: "";
      width: 8px;
      height: 8px;
      background: #67e8d5;
      border-radius: 50%;
      box-shadow: 0 0 0 5px rgba(103, 232, 213, 0.12);
    }}

    .hero h1 {{
      max-width: 960px;
      margin: 0 0 18px;
      font-family: "Aptos Display", "Segoe UI", system-ui, sans-serif;
      font-size: clamp(2.4rem, 5.8vw, 4.6rem);
      line-height: 1.06;
      letter-spacing: -0.045em;
      text-wrap: balance;
    }}

    .hero-lead {{
      max-width: 890px;
      margin: 0;
      color: var(--muted);
      font-size: clamp(1.05rem, 2vw, 1.25rem);
      line-height: 1.6;
    }}

    .hero-meta {{
      display: flex;
      flex-wrap: wrap;
      gap: 10px 24px;
      margin-top: 26px;
      color: var(--muted);
      font-size: 0.88rem;
    }}

    .hero-meta strong {{ color: var(--violet-deep); }}

    .paradigm-callout {{
      margin-top: 24px;
      padding: 16px 20px;
      border-radius: 12px;
      background: rgba(91,60,196,0.07);
      border-left: 4px solid var(--violet);
      font-size: 0.90rem;
      color: #291d4e;
      line-height: 1.65;
    }}

    .paradigm-callout strong {{
      color: var(--violet-deep);
    }}

    .action-bar {{
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin-top: 26px;
    }}

    .button {{
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-height: 44px;
      padding: 10px 18px;
      color: var(--violet-deep);
      background: rgba(255,255,255,0.85);
      border: 1px solid rgba(101, 71, 168, 0.24);
      border-radius: 11px;
      cursor: pointer;
      font-weight: 700;
      text-decoration: none;
      transition: all 150ms ease;
    }}

    .button:hover {{
      color: var(--violet-deep);
      background: #fff;
      transform: translateY(-1px);
    }}

    .button.primary {{
      color: #fff;
      background: var(--violet);
      border-color: var(--violet);
    }}

    .button.primary:hover {{
      background: var(--violet-deep);
    }}

    .page-shell {{
      display: grid;
      grid-template-columns: 280px minmax(0, 1fr);
      gap: 36px;
      width: min(calc(100% - 40px), var(--content));
      margin: 0 auto;
      padding: 42px 0 80px;
      align-items: start;
    }}

    .toc {{
      position: sticky;
      top: 24px;
      max-height: calc(100vh - 48px);
      overflow: auto;
      padding: 18px;
      background: rgba(255,255,255,0.86);
      border: 1px solid var(--line);
      border-radius: 16px;
      box-shadow: 0 10px 35px rgba(39, 30, 73, 0.07);
      backdrop-filter: blur(12px);
      scrollbar-width: thin;
    }}

    .toc-title {{
      display: block;
      margin: 0 0 12px;
      color: var(--violet-deep);
      font-size: 0.74rem;
      font-weight: 820;
      letter-spacing: 0.1em;
      text-transform: uppercase;
    }}

    .toc nav {{
      display: grid;
      gap: 3px;
    }}

    .toc a {{
      display: block;
      padding: 6px 9px;
      color: var(--muted);
      border-left: 2px solid transparent;
      border-radius: 0 8px 8px 0;
      font-size: 0.84rem;
      line-height: 1.35;
      text-decoration: none;
      transition: 150ms ease;
    }}

    .toc a:hover,
    .toc a.is-active {{
      color: var(--violet-deep);
      background: var(--violet-soft);
      border-left-color: var(--violet);
      font-weight: 600;
    }}

    .toc a[data-level="3"] {{
      padding-left: 18px;
      font-size: 0.78rem;
    }}

    .toc-note {{
      margin: 16px 0 0;
      padding-top: 14px;
      color: var(--muted);
      border-top: 1px solid var(--line);
      font-size: 0.76rem;
      line-height: 1.45;
    }}

    .report {{
      min-width: 0;
      padding: 44px clamp(24px, 5vw, 68px) 64px;
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: var(--radius);
      box-shadow: var(--shadow);
    }}

    .report h1,
    .report h2,
    .report h3,
    .report h4 {{
      color: var(--ink);
      font-family: "Aptos Display", "Segoe UI", system-ui, sans-serif;
      line-height: 1.18;
      text-wrap: balance;
    }}

    .report h2 {{
      margin: 58px 0 18px;
      padding-top: 8px;
      color: var(--violet-deep);
      font-size: clamp(1.6rem, 2.8vw, 2.2rem);
      letter-spacing: -0.025em;
    }}

    .report h2:first-of-type {{ margin-top: 10px; }}

    .report h3 {{
      margin: 34px 0 14px;
      color: #29344a;
      font-size: clamp(1.18rem, 2vw, 1.45rem);
      letter-spacing: -0.012em;
    }}

    .report h4 {{
      margin: 24px 0 10px;
      font-size: 1.05rem;
      color: #3b4556;
    }}

    .report p {{ margin: 0 0 17px; }}

    .report ul,
    .report ol {{
      padding-left: 1.4rem;
      margin: 0 0 22px;
    }}

    .report li {{ margin: 7px 0; }}
    .report li::marker {{ color: var(--violet); font-weight: 700; }}

    .report blockquote {{
      position: relative;
      margin: 28px 0;
      padding: 20px 24px 20px 24px;
      color: #28223d;
      background: linear-gradient(135deg, var(--violet-soft), #f5f2ff);
      border: 1px solid #d9d0ff;
      border-left: 5px solid var(--violet);
      border-radius: 13px;
    }}

    .report blockquote::before {{
      content: "Princípio Metodológico Fundamental";
      display: block;
      margin-bottom: 8px;
      color: var(--violet);
      font-size: 0.72rem;
      font-weight: 820;
      letter-spacing: 0.1em;
      text-transform: uppercase;
    }}

    .report blockquote p:last-child {{ margin-bottom: 0; }}

    .report hr {{
      height: 1px;
      margin: 40px 0;
      background: var(--line);
      border: 0;
    }}

    .report table {{
      width: 100%;
      margin: 22px 0 30px;
      border-collapse: separate;
      border-spacing: 0;
      border: 1px solid var(--line);
      border-radius: 12px;
      font-size: 0.86rem;
      line-height: 1.5;
      overflow: hidden;
    }}

    .report thead th {{
      color: #fff;
      background: var(--violet-deep);
      font-weight: 700;
      text-align: left;
      padding: 12px 14px;
    }}

    .report th,
    .report td {{
      padding: 11px 13px;
      border-right: 1px solid var(--line);
      border-bottom: 1px solid var(--line);
      vertical-align: top;
    }}

    .report tr > *:last-child {{ border-right: 0; }}
    .report tbody tr:last-child > * {{ border-bottom: 0; }}
    .report tbody tr:nth-child(even) {{ background: #faf9f6; }}
    .report tbody tr:hover {{ background: var(--cyan-soft); }}
    .report .numeric {{ text-align: right; }}

    .badge-status {{
      display: inline-block;
      padding: 3px 8px;
      border-radius: 6px;
      font-size: 0.75rem;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }}
    .badge-done {{ background: var(--green-soft); color: var(--green); }}
    .badge-warn {{ background: var(--amber-soft); color: var(--amber); }}
    .badge-prohibited {{ background: var(--red-soft); color: var(--red); }}

    .report code {{
      padding: 0.15em 0.4em;
      color: #5634b2;
      background: #f0ecff;
      border-radius: 5px;
      font-family: "SFMono-Regular", Consolas, "Liberation Mono", monospace;
      font-size: 0.88em;
    }}

    .report pre {{
      overflow: auto;
      margin: 22px 0 28px;
      padding: 20px;
      color: #e8e3f5;
      background: #211938;
      border: 1px solid #392c59;
      border-radius: 12px;
      line-height: 1.55;
    }}

    .report pre code {{
      padding: 0;
      color: inherit;
      background: transparent;
    }}

    .report em {{ color: #454e5d; }}
    .report strong {{ color: #1e2636; }}

    .report a[href^="http"]::after {{
      content: " ↗";
      font-size: 0.76em;
      text-decoration: none;
    }}

    .back-to-top {{
      position: fixed;
      z-index: 50;
      right: 22px;
      bottom: 22px;
      display: grid;
      width: 44px;
      height: 44px;
      place-items: center;
      color: #fff;
      background: var(--violet-deep);
      border: 0;
      border-radius: 50%;
      box-shadow: 0 10px 28px rgba(51, 32, 115, 0.26);
      cursor: pointer;
      opacity: 0;
      pointer-events: none;
      transform: translateY(10px);
      transition: 180ms ease;
    }}

    .back-to-top.is-visible {{
      opacity: 1;
      pointer-events: auto;
      transform: translateY(0);
    }}

    .document-footer {{
      padding: 28px 20px 38px;
      color: var(--muted);
      text-align: center;
      font-size: 0.82rem;
    }}

    @media (max-width: 980px) {{
      .page-shell {{
        grid-template-columns: 1fr;
        gap: 20px;
      }}

      .toc {{
        position: static;
        max-height: none;
      }}

      .toc nav {{
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }}

      .toc a[data-level="3"] {{ display: none; }}
    }}

    @media (max-width: 680px) {{
      .hero-inner,
      .page-shell {{
        width: min(calc(100% - 24px), var(--content));
      }}

      .hero-inner {{ padding: 48px 0 40px; }}
      .hero h1 {{ font-size: clamp(2.1rem, 11vw, 3.1rem); }}
      .hero-meta {{ display: grid; gap: 6px; }}
      .action-bar {{ display: grid; grid-template-columns: 1fr; }}
      .toc nav {{ grid-template-columns: 1fr; }}
      .report {{ padding: 30px 18px 46px; border-radius: 14px; }}
      .report h2 {{ margin-top: 44px; }}

      .report table {{
        display: block;
        overflow-x: auto;
        white-space: normal;
        -webkit-overflow-scrolling: touch;
      }}

      .report th,
      .report td {{
        min-width: 140px;
      }}
    }}

    @media print {{
      @page {{ size: A4; margin: 18mm 16mm; }}

      body {{
        color: #000;
        background: #fff;
        font-size: 10.5pt;
      }}

      .reading-progress,
      .toc,
      .action-bar,
      .back-to-top,
      .document-footer {{
        display: none !important;
      }}

      .hero {{
        color: #000;
        background: #fff;
        border: 0;
      }}

      .hero::before,
      .hero::after,
      .eyebrow::before {{
        display: none;
      }}

      .hero-inner {{
        width: 100%;
        padding: 20mm 0 12mm;
      }}

      .eyebrow {{
        color: #333;
        background: transparent;
        border-color: #999;
      }}

      .hero h1 {{
        color: #000;
        font-size: 26pt;
      }}

      .hero-lead,
      .hero-meta,
      .hero-meta strong {{
        color: #222;
      }}

      .page-shell {{
        display: block;
        width: 100%;
        padding: 0;
      }}

      .report {{
        padding: 0;
        border: 0;
        border-radius: 0;
        box-shadow: none;
      }}

      .report h2 {{
        break-after: avoid;
        color: #000;
        font-size: 17pt;
      }}

      .report h3 {{
        break-after: avoid;
        color: #111;
        font-size: 13pt;
      }}

      .report table,
      .report blockquote,
      .report pre {{
        break-inside: avoid;
      }}

      .report thead th {{
        color: #000;
        background: #e8e8e8;
      }}

      .report a {{
        color: #000;
        text-decoration: none;
      }}

      .report a[href^="http"]::after {{ content: ""; }}
    }}
  </style>
</head>
<body>
  <div class="reading-progress" id="reading-progress" aria-hidden="true"></div>

  <header class="hero" id="inicio">
    <div class="hero-inner">
      <p class="eyebrow">Protocolo Científico e Metodologia Operacional · PulseLab v{canonical_version}</p>
      <h1>PulseLab como infraestrutura de mensuração em oficinas de robótica educacional</h1>
      <p class="hero-lead">Relatório metodológico consolidado sobre mensuração de processos, observabilidade silenciosa, integridade de dados e proteção rigorosa a menores (LGPD Art. 14) em ambientes práticos com LEGO SPIKE Prime.</p>
      
      <div class="hero-meta">
        <span><strong>Versão canônica:</strong> PulseLab {canonical_version}</span>
        <span><strong>Paradigma:</strong> Observabilidade Passiva por Bancada Coletiva</span>
        <span><strong>Autor:</strong> Vinicius Ferreira Amim</span>
        <span><strong>Instituição:</strong> Universidade Federal do Vale do São Francisco (UNIVASF)</span>
        <span><strong>Atuação:</strong> Setor de Pesquisa da FADEX · Robótica Educativa</span>
        <span><strong>Enquadramento Ético:</strong> LGPD (Art. 14) · Resolução CNS nº 510/2016</span>
      </div>

      <div class="paradigm-callout">
        <strong>Arquitetura Consolidada de Observabilidade (v{canonical_version}):</strong> O PulseLab estabelece um novo paradigma para a pesquisa em robótica educativa: <em>observar o processo sem perturbar a prática</em>. O software opera em modo <strong>silencioso e não-invasivo</strong> na tela das crianças durante toda a oficina (zero popups ou questionários intrusivos). A unidade de análise e observação é a <strong>bancada coletiva</strong> (2 a 8 estudantes), garantindo a conformidade estrita com o Art. 14 da LGPD (proibição absoluta de fotos, áudios, vídeos, nomes, digitação de teclas e capturas de tela). O sistema inspeciona periodicamente a complexidade estrutural do código LEGO SPIKE Prime (<code>.llsp3</code> a cada 10s via Bridge local), reúne uma avaliação lúdica ágil no encerramento da aula (<code>TurmaClosing</code>: 4 carinhas pela bancada + rubrica e apoio pelo educador) e persiste tudo localmente em dupla camada com política fail-closed ativada exclusivamente pelo CAAE do Comitê de Ética em Pesquisa (CEP).
      </div>

      <div class="action-bar">
        <a class="button primary" href="#resumo">Começar a leitura</a>
        <button class="button" type="button" onclick="window.print()">Imprimir ou salvar em PDF</button>
        <a class="button" href="relatorio-academico-metricas-pulselab-v1.4.md" title="Consultar arquivo de evolução histórica v1.4">Ver arquivo histórico v1.4 (Markdown)</a>
      </div>
    </div>
  </header>

  <div class="page-shell">
    <aside class="toc" aria-label="Sumário do relatório">
      <span class="toc-title">Neste relatório</span>
      <nav id="toc-nav">
        <a href="#resumo" data-level="2">Resumo</a>
        <a href="#sec-1-problema-de-pesquisa-e-justificativa" data-level="2">1. Problema de pesquisa e justificativa</a>
        <a href="#sec-2-enquadramento-metodologico" data-level="2">2. Enquadramento metodológico</a>
        <a href="#sec-2-1-desenho-recomendado" data-level="3">2.1 Desenho recomendado</a>
        <a href="#sec-2-2-unidades-de-observacao-e-de-analise" data-level="3">2.2 Bancada coletiva como unidade analítica</a>
        <a href="#sec-3-como-o-pulselab-transforma-a-oficina-em-numeros" data-level="2">3. Da prática ao dado empírico</a>
        <a href="#sec-3-1-cadeia-de-mensuracao" data-level="3">3.1 Cadeia de mensuração silenciosa</a>
        <a href="#sec-3-2-quatro-classes-de-indicadores" data-level="3">3.2 As quatro classes de indicadores</a>
        <a href="#sec-4-matriz-de-metricas-do-pulselab" data-level="2">4. Matriz de métricas do PulseLab</a>
        <a href="#sec-4-1-alcance-e-caracterizacao" data-level="3">4.1 Contexto e bancada</a>
        <a href="#sec-4-2-telemetria-estrutural-spike" data-level="3">4.2 Telemetria estrutural do LEGO SPIKE</a>
        <a href="#sec-4-3-encerramento-e-desfecho" data-level="3">4.3 Encerramento e desfecho da missão</a>
        <a href="#sec-4-4-qualidade-e-governanca" data-level="3">4.4 Qualidade, integridade e governança</a>
        <a href="#sec-4-5-expurgo-de-telemetrias-invasivas" data-level="3">4.5 Abolição de telemetrias invasivas</a>
        <a href="#sec-5-perguntas-de-pesquisa-e-hipoteses-testaveis" data-level="2">5. Perguntas de pesquisa e hipóteses</a>
        <a href="#sec-5-1-objetivo-geral" data-level="3">5.1 Objetivo geral</a>
        <a href="#sec-5-2-objetivos-especificos" data-level="3">5.2 Objetivos específicos</a>
        <a href="#sec-5-3-hipoteses" data-level="3">5.3 Hipóteses testáveis</a>
        <a href="#sec-6-plano-de-analise-quantitativa" data-level="2">6. Plano de análise quantitativa</a>
        <a href="#sec-6-1-preparacao" data-level="3">6.1 Preparação e integridade</a>
        <a href="#sec-6-2-analise-descritiva" data-level="3">6.2 Análise descritiva</a>
        <a href="#sec-6-3-modelos-recomendados" data-level="3">6.3 Modelos recomendados (GLMM e multinível)</a>
        <a href="#sec-6-4-dados-ausentes-e-etica" data-level="3">6.4 Dados ausentes e autodeterminação ética</a>
        <a href="#sec-6-5-tamanho-amostral" data-level="3">6.5 Dimensionamento amostral do piloto</a>
        <a href="#sec-7-criterios-propostos-para-declarar-o-piloto-viavel" data-level="2">7. Critérios de viabilidade do piloto</a>
        <a href="#sec-8-evidencias-de-validade-necessarias" data-level="2">8. Evidências de validade necessárias</a>
        <a href="#sec-9-auditoria-do-estado-atual-da-implementacao" data-level="2">9. Auditoria da implementação atual</a>
        <a href="#sec-10-por-que-o-aplicativo-agrega-valor-a-pesquisa" data-level="2">10. Valor agregado à pesquisa científica</a>
        <a href="#sec-11-limites-das-conclusoes" data-level="2">11. Limites das conclusões</a>
        <a href="#sec-12-perguntas-provaveis-da-banca-e-respostas-recomendadas" data-level="2">12. Perguntas da banca e respostas</a>
        <a href="#sec-13-roteiro-de-defesa-oral-em-dois-minutos" data-level="2">13. Defesa oral em dois minutos</a>
        <a href="#sec-14-plano-de-maturacao-e-protocolo-de-campo" data-level="2">14. Protocolo de campo e maturação</a>
        <a href="#sec-15-consideracoes-eticas-e-protecao-de-dados" data-level="2">15. Governança ética e LGPD (Art. 14)</a>
        <a href="#sec-16-conclusao" data-level="2">16. Conclusão</a>
        <a href="#referencias" data-level="2">Referências</a>
      </nav>
      <p class="toc-note">Use o botão “Imprimir ou salvar em PDF” para gerar o documento acadêmico formatado para submissão ou qualificação.</p>
    </aside>

    <main class="report" id="report-content">
      
      <h2 id="resumo">Resumo</h2>
      <p>Este relatório formaliza a metodologia de pesquisa e o protocolo de mensuração empírica do <strong>PulseLab v{canonical_version}</strong> para oficinas de robótica educacional com kits LEGO SPIKE Prime. Superando abordagens intrusivas anteriores baseadas em questionários periódicos em tela e telemetrias vigilantes, o PulseLab adota uma <strong>arquitetura de observabilidade silenciosa e não-invasiva</strong>. O desenho metodológico recomendado é observacional multicêntrico, em cortes transversais repetidos, tomando a <strong>bancada coletiva (2 a 8 estudantes)</strong> como unidade analítica primária.</p>
      
      <p>O sistema triangula quatro vertentes empíricas: (1) <em>contexto institucional e governança fail-closed</em> provisionada por polo regional com número oficial de CAAE aprovado por Comitê de Ética em Pesquisa (CEP/CONEP); (2) <em>telemetria passiva estrutural do artefato</em> via inspeção em segundo plano dos arquivos <code>.llsp3</code> a cada 10 segundos pelo Bridge local Windows (contagem de blocos executáveis, pilhas de controle, uso de motores, sensores, laços e condições, sem gravar código-fonte bruto ou texto de usuário); (3) <em>avaliação ágil de encerramento da oficina</em> (<code>TurmaClosing</code>) em dois eixos independentes: percepção global da bancada em escala nominal de 4 carinhas e rubrica pedagógica de desfecho da missão (0 a 3) com nível de apoio prestado pelo educador; e (4) <em>evidências operacionais de qualidade e integridade</em> com assinatura criptográfica do manifesto (<code>CONFIG_HASH</code>).</p>
      
      <p>A persistência ocorre em dupla camada atômica (IndexedDB transacional no navegador e arquivos JSONL locais no Bridge), sustentando operação offline irrestrita com retenção configurável (1 a 365 dias, padrão de 180 dias), sincronização assíncrona por Store-and-Forward para o Supabase e expurgo ético com <em>tombstone</em> imediato. Em conformidade absoluta com o <strong>Art. 14 da LGPD (Lei 13.709/2018)</strong>, são terminantemente abolidos registros de nomes de menores, fotos, vídeos, áudios, monitoramento de digitação de teclas e capturas de tela. Conclui-se que o PulseLab constitui uma infraestrutura rigorosa, escalável e eticamente defensável para qualificação acadêmica e estudos translacionais em Learning Analytics na escola pública brasileira.</p>
      
      <p><strong>Palavras-chave:</strong> robótica educacional; multimodal learning analytics; observabilidade silenciosa; bancada coletiva; mensuração educacional; LGPD; estudo observacional; LEGO SPIKE Prime.</p>
      
      <hr>

      <h2 id="sec-1-problema-de-pesquisa-e-justificativa">1. Problema de pesquisa e justificativa</h2>
      <p>Oficinas de robótica educacional em escolas públicas são ambientes dinâmicos, ruidosos, altamente práticos e inerentemente colaborativos. O trabalho dos estudantes divide-se de forma fluida entre o manuseio físico de blocos e engrenagens, a elaboração algorítmica em blocos Scratch, a testagem em arena e a mediação pontual do educador. A avaliação científica tradicional dessas práticas enfrenta uma contradição metodológica severa:</p>
      
      <ul>
        <li><strong>Foco excessivo no produto final:</strong> Mensurar apenas se o robô completou a pista ignora toda a trajetória de depuração, o tipo de dificuldade encontrada, a quantidade de mediação demandada e a qualidade da colaboração entre os pares.</li>
        <li><strong>Falha da observação humana intensiva:</strong> Alocar pesquisadores com pranchetas para registrar cada interação de dezenas de bancadas em várias escolas é financeiramente inviável, não escalável e introduz forte variabilidade entre observadores.</li>
        <li><strong>A armadilha dos questionários frequentes na tela:</strong> A imposição de questionários em tela durante a oficina (por exemplo, interrupções fixas aos 20 e 40 minutos) revelou-se profundamente contraproducente com crianças e adolescentes. Tais interrupções quebram o estado de concentração e imersão lúdica (<em>flow</em>), geram respostas randômicas causadas por "fadiga de questionário" apenas para fechar o popup na tela, e introduzem o viés de desejabilidade social (responder o que a criança acredita que o instrutor espera).</li>
        <li><strong>O perigo da vigilância digital:</strong> O uso de capturas de tela (<em>screenshots</em>), gravação global de teclas digitadas ou monitoramento de áudio/vídeo viola a privacidade dos estudantes, gera resistência institucional e fere diretamente o princípio do melhor interesse da criança preconizado pelo Art. 14 da LGPD.</li>
      </ul>

      <blockquote>
        <p><strong>Tese metodológica:</strong> Para produzir dados científicos válidos em robótica educativa, o instrumento deve observar o processo de forma <em>silenciosa, estrutural e não-invasiva</em>. A tecnologia deve coletar a telemetria do artefato computacional e registrar a mediação pedagógica sem transformar o ambiente escolar em um laboratório de vigilância e sem subtrair tempo pedagógico dos alunos.</p>
      </blockquote>

      <p>A literatura internacional em <em>Learning Analytics</em> adverte que a presença de tecnologias em sala de aula não garante, por si só, aprendizagem, e que métricas educacionais devem ser teoricamente ancoradas e eticamente proporcionais (BENITTI, 2012; SoLAR, 2025). Conforme demonstrado por Blikstein (2013) em <em>Multimodal Learning Analytics</em> (MMLA), em atividades abertas de construção física e lógica, o processo deve ser compreendido pela evolução dos artefatos construídos e pelas dinâmicas contextuais, e não pela redução da criança a respondente passivo de formulários digitais.</p>

      <hr>

      <h2 id="sec-2-enquadramento-metodologico">2. Enquadramento metodológico</h2>
      
      <h3 id="sec-2-1-desenho-recomendado">2.1 Desenho recomendado</h3>
      <p>O enquadramento científico rigoroso do PulseLab v{canonical_version} é definido como:</p>
      
      <blockquote>
        <p><strong>Estudo observacional multicêntrico, de cortes transversais repetidos por turma, com a bancada coletiva como unidade primária de observação e análise, em oficinas pontuais de robótica educacional com LEGO SPIKE Prime.</strong></p>
      </blockquote>

      <p>Características constitutivas do desenho:</p>
      <ul>
        <li><strong>Natureza observacional e ecológica:</strong> O aplicativo não altera a rotina das oficinas nem impõe sequências artificiais; ele opera de forma imperceptível no ambiente computacional real das bancadas escolares.</li>
        <li><strong>Cortes transversais repetidos:</strong> Cada bancada é observada durante uma sessão de oficina (duração típica de 60 a 90 minutos). O protocolo não efetua seguimento individual longitudinal de crianças ao longo dos anos, pois não há identificação pessoal dos alunos.</li>
        <li><strong>Ausência de alegações de causalidade estrita:</strong> Como o desenho do piloto é observacional e não dispõe de grupo controle randomizado (RCT), os dados sustentam relações de associação, trajetórias descritivas e modelos preditivos, mas não alegações causais unilaterais sobre o "impacto absoluto da robótica na inteligência infantil".</li>
        <li><strong>Diretrizes STROBE:</strong> A estruturação do relatório segue as diretrizes internacionais STROBE (<em>Strengthening the Reporting of Observational Studies in Epidemiology</em>) para relato transparente de variáveis, contextos, dados ausentes e limitações metodológicas (VON ELM et al., 2007).</li>
      </ul>

      <h3 id="sec-2-2-unidades-de-observacao-e-de-analise">2.2 Bancada coletiva como unidade analítica</h3>
      <p>Um dos avanços metodológicos mais importantes da versão {canonical_version} é a consolidação da <strong>bancada coletiva</strong> (2 a 8 estudantes) como unidade empírica irredutível:</p>

      <pre><code class="language-text">Polo Regional FADEX (Provisionamento institucional com CAAE de CEP aprovado)
└── Escola / Unidade de Ensino (school_code)
    └── Oficina / Turma (workshop_code, class_code)
        └── Bancada Coletiva [group_id UUID efêmero, group_size 2 a 8]
            ├── Telemetria Passiva SPIKE (inspeção de .llsp3 a cada 10s via Bridge)
            │   ├── Contagem de blocos executáveis e pilhas concorrentes
            │   └── Ativação de motores, sensores, laços de repetição e condições
            ├── Chamados de Apoio (registro pontual da mediação do educador)
            └── Encerramento da Turma (TurmaClosing)
                ├── Avaliação da Bancada (4 carinhas ou "Preferimos não responder")
                └── Avaliação do Educador (resultado da missão 0 a 3 + apoio recebido)
</code></pre>

      <p>A opção técnica e metodológica pela bancada coletiva é fundamentada em três pilares:</p>
      <ol>
        <li><strong>Realidade Pedagógica da Robótica:</strong> Em uma oficina com LEGO SPIKE Prime, as crianças constroem um único robô em equipe, compartilham um único computador e discutem colaborativamente a solução do problema. Tentar individualizar respostas em uma máquina compartilhada gerava filas artificiais, disputas pelo teclado e forte viés de contaminação mútua.</li>
        <li><strong>Prevenção de Pseudorreplicação Estatística:</strong> No paradigma anterior (v1.4), tratar crianças da mesma bancada como observações independentes inflava artificialmente os graus de liberdade estatísticos, violando premissas fundamentais de inferência. Na v{canonical_version}, a dependência intragrupo é respeitada estruturalmente.</li>
        <li><strong>Conformidade Estrita com LGPD (Art. 14):</strong> Ao tratar a bancada como unidade anônima/pseudonimizada com identificadores efêmeros, o sistema elimina a necessidade de coletar qualquer identificador pessoal individual de menores de idade, blindando juridicamente a pesquisa e protegendo integralmente os direitos das crianças.</li>
      </ol>

      <hr>

      <h2 id="sec-3-como-o-pulselab-transforma-a-oficina-em-numeros">3. Da prática ao dado empírico</h2>
      
      <h3 id="sec-3-1-cadeia-de-mensuracao">3.1 Cadeia de mensuração silenciosa</h3>
      <p>A coleta de dados opera através de um pipeline determinístico, transparente e não-obstrutivo ao longo das fases da oficina:</p>

      <table>
        <thead>
          <tr>
            <th>Fase da Oficina</th>
            <th>Dinâmica na Sala de Aula</th>
            <th>Mecanismo do PulseLab</th>
            <th>Registro Gerado</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td><strong>1. Abertura e Termos</strong></td>
            <td>Educador abre o PulseLab; verifica identificação da bancada e termo de assentimento.</td>
            <td>Verifica <code>provisionamento.json</code> (polo e CAAE do CEP). Assentimento livre desmarcado.</td>
            <td><code>session_started</code> com <code>group_id</code>, <code>group_size</code> e dados de contexto do polo.</td>
          </tr>
          <tr>
            <td><strong>2. Prática da Oficina</strong></td>
            <td>Estudantes montam o robô e programam no LEGO SPIKE 3. Foco 100% pedagógico.</td>
            <td><strong>Modo Silencioso:</strong> Zero popups. Bridge inspeciona a cada 10s arquivos <code>.llsp3</code> salvos.</td>
            <td>Eventos <code>spike_telemetry</code> com contagens de blocos, motores, sensores e laços.</td>
          </tr>
          <tr>
            <td><strong>3. Mediação Pontual</strong></td>
            <td>Bancada solicita ajuda com montagem ou lógica; instrutor atende na bancada.</td>
            <td>Instrutor pode registrar chamado de apoio no atalho discreto da tela.</td>
            <td>Eventos de chamada e mediação registrados com timestamp local.</td>
          </tr>
          <tr>
            <td><strong>4. Encerramento (TurmaClosing)</strong></td>
            <td>Término da aula. Instrutor clica em "Encerrar turma" no rodapé.</td>
            <td>Abre modal rápido em 2 etapas: (1) 4 carinhas para a bancada; (2) rubrica para o instrutor.</td>
            <td><code>experience_recorded</code> (1 a 4 ou null) e <code>rubric_completed</code> (resultado 0 a 3 e apoio).</td>
          </tr>
          <tr>
            <td><strong>5. Persistência e Guarda</strong></td>
            <td>Sessão é finalizada; sistema fica limpo para a próxima turma.</td>
            <td>Gravação atômica em IndexedDB e arquivos JSONL locais (<code>dados_locais/</code>).</td>
            <td><code>session_completed</code>. Cópia local retida por 180 dias; envio assíncrono para Supabase.</td>
          </tr>
        </tbody>
      </table>

      <h3 id="sec-3-2-quatro-classes-de-indicadores">3.2 As quatro classes de indicadores</h3>
      <p>Para assegurar clareza epistemológica na interpretação acadêmica, o PulseLab divide rigorosamente seus dados em quatro classes analíticas:</p>
      <ul>
        <li><strong>Classe 1 — Contexto Institucional:</strong> Dados geográficos e de governança (polo, regional, escola, turma, tamanho do grupo, CAAE). Não sofrem variação intraoficina; atuam como covariáveis de agrupamento.</li>
        <li><strong>Classe 2 — Telemetria Estrutural do Artefato:</strong> Dados objetivos extraídos diretamente do arquivo do projeto de código (LEGO SPIKE <code>.llsp3</code>). Descrevem a complexidade computacional, concorrência e tipos de componentes físicos acionados.</li>
        <li><strong>Classe 3 — Percepção Sintética da Bancada:</strong> Avaliação afetiva/lúdica de encerramento respondida coletivamente pelo grupo (escala de 4 carinhas). Representa a percepção de clima e satisfação do grupo, com direito irrestrito de recusa.</li>
        <li><strong>Classe 4 — Avaliação Pedagógica Mediada:</strong> Rubrica preenchida pelo educador avaliando o desfecho prático da missão e o nível de apoio fornecido. Atua como o desfecho pedagógico imediato observado.</li>
      </ul>

      <hr>

      <h2 id="sec-4-matriz-de-metricas-do-pulselab">4. Matriz de métricas do PulseLab</h2>

      <h3 id="sec-4-1-alcance-e-caracterizacao">4.1 Contexto e bancada</h3>
      <table>
        <thead>
          <tr>
            <th>Campo / Variável</th>
            <th>Tipo / Escala</th>
            <th>Significado Operacional</th>
            <th>Finalidade na Análise</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td><code>site_id</code>, <code>regional_hub</code></td>
            <td>Categórico (texto)</td>
            <td>Identificador do polo e coordenação regional</td>
            <td>Controle de heterogeneidade geográfica multicêntrica</td>
          </tr>
          <tr>
            <td><code>school_code</code></td>
            <td>Categórico (texto)</td>
            <td>Código da unidade escolar participante</td>
            <td>Nível de agrupamento hierárquico nos modelos mistos</td>
          </tr>
          <tr>
            <td><code>group_id</code></td>
            <td>UUID v4</td>
            <td>Identificador efêmero da bancada coletiva na sessão</td>
            <td>Unidade primária de análise; previne pseudorreplicação</td>
          </tr>
          <tr>
            <td><code>group_size</code></td>
            <td>Discreto (2 a 8)</td>
            <td>Número de estudantes colaborando naquela bancada</td>
            <td>Covariável explicativa sobre dinâmicas de colaboração</td>
          </tr>
          <tr>
            <td><code>machine_label</code></td>
            <td>Categórico (ex: BANCADA-01)</td>
            <td>Rótulo de inventário da máquina na sala de aula</td>
            <td>Auditoria técnica e controle de distribuição de kits</td>
          </tr>
        </tbody>
      </table>

      <h3 id="sec-4-2-telemetria-estrutural-spike">4.2 Telemetria estrutural do LEGO SPIKE</h3>
      <p>O parser local inspeciona passivamente os arquivos de projeto LEGO SPIKE Prime 3 (<code>.llsp3</code>). Não há gravação de código de usuário, strings livres ou nomes de variáveis:</p>
      
      <table>
        <thead>
          <tr>
            <th>Métrica de Código</th>
            <th>Definição no Parser Local</th>
            <th>Interpretação Pedagógica Válida</th>
            <th>O que NÃO deve ser alegado</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td><code>executable_blocks</code></td>
            <td>Contagem de blocos pertencentes a pilhas de gatilho de execução</td>
            <td>Volume de instruções acionáveis formuladas pela bancada</td>
            <td>Não equivale a "alta qualidade algorítmica" ou "código limpo"</td>
          </tr>
          <tr>
            <td><code>top_level_stacks</code></td>
            <td>Contagem de pilhas iniciadas por blocos chapéu (<em>hat blocks</em>)</td>
            <td>Grau de concorrência ou paralelismo (múltiplos eventos simultâneos)</td>
            <td>Não garante que as tarefas concorrentes operem sem conflito</td>
          </tr>
          <tr>
            <td><code>uses_motor</code></td>
            <td>Booleano (<code>true/false</code>)</td>
            <td>Uso intencional de blocos de motores individuais ou trem de força</td>
            <td>Não prova montagem mecânica correta ou engrenamento</td>
          </tr>
          <tr>
            <td><code>uses_sensor</code></td>
            <td>Booleano (<code>true/false</code>)</td>
            <td>Leitura de sensores (ultrassônico, cor, força ou giroscópio)</td>
            <td>Não garante calibração ou tratamento adequado de leituras</td>
          </tr>
          <tr>
            <td><code>uses_loop</code></td>
            <td>Booleano (<code>true/false</code>)</td>
            <td>Presença de estruturas de repetição (<em>sempre</em>, <em>repita N vezes</em>)</td>
            <td>Não indica ausência de loops infinitos indesejados</td>
          </tr>
          <tr>
            <td><code>uses_condition</code></td>
            <td>Booleano (<code>true/false</code>)</td>
            <td>Presença de desvios condicionais (<em>se... então... senão</em>)</td>
            <td>Não prova domínio conceitual abstrato de lógica booleana</td>
          </tr>
          <tr>
            <td><code>inferred_stage</code></td>
            <td>Ordinal (<code>empty</code>, <code>basic</code>, <code>intermediate</code>, <code>advanced</code>)</td>
            <td>Classificação algorítmica da sofisticação estrutural do código</td>
            <td>É um indicador sintático, não um diagnóstico psicológico do aluno</td>
          </tr>
        </tbody>
      </table>

      <h3 id="sec-4-3-encerramento-e-desfecho">4.3 Encerramento e desfecho da missão</h3>
      <p>No encerramento da oficina, o componente <code>TurmaClosing</code> gera dois registros independentes e complementares:</p>

      <table>
        <thead>
          <tr>
            <th>Dimensão</th>
            <th>Campo no Contrato</th>
            <th>Valores Possíveis</th>
            <th>Regra de Preenchimento e Salvaguarda</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td><strong>Experiência da Bancada</strong></td>
            <td><code>experiencia_bancada_v1</code></td>
            <td>1: 😫 Muito difícil/chato<br>2: 😕 Difícil<br>3: 😊 Legal<br>4: 🤩 Muito legal!<br><code>null</code>: Recusa</td>
            <td>Respondida pela bancada em 5 segundos. O botão <em>"Preferimos não responder"</em> grava <code>null</code>. A recusa é protegida e nunca gera penalidade acadêmica ou atribuição de zero.</td>
          </tr>
          <tr>
            <td><strong>Resultado Prático da Missão</strong></td>
            <td><code>resultado_bancada_v1</code></td>
            <td>0: Não concluiu<br>1: Concluiu em parte<br>2: Concluiu a missão<br>3: Concluiu e foi além</td>
            <td>Preenchida pelo educador com base na rubrica objetiva da missão estabelecida no protocolo (ex: missão <em>distance-stop</em>).</td>
          </tr>
          <tr>
            <td><strong>Apoio do Educador</strong></td>
            <td><code>apoio_instrutor_v1</code></td>
            <td><code>nenhum</code><br><code>algum</code><br><code>muito</code><br><code>null</code>: Pular</td>
            <td>Indica o nível de intervenção pedagógica que a bancada demandou para alcançar o desfecho. Essencial para diferenciar autonomia de dependência.</td>
          </tr>
        </tbody>
      </table>

      <h3 id="sec-4-4-qualidade-e-governanca">4.4 Qualidade, integridade e governança</h3>
      <table>
        <thead>
          <tr>
            <th>Métrica / Mecanismo</th>
            <th>Implementação Técnica</th>
            <th>Significado Científico</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td><code>CONFIG_HASH</code></td>
            <td>Hash SHA-256 do manifesto de contratos (<code>lib/contracts.js</code>)</td>
            <td>Garante reprodutibilidade científica absoluta: apenas dados coletados sob a mesma especificação matemática de itens são comparados.</td>
          </tr>
          <tr>
            <td><code>retention_days</code></td>
            <td>Valor inteiro configurável no polo (padrão 180 dias)</td>
            <td>Prazo estrito de custódia local. Expurgo automático executado periodicamente pelo navegador e pelo Bridge local.</td>
          </tr>
          <tr>
            <td><code>tombstone</code></td>
            <td>Registro persistente gravado em caso de desistência</td>
            <td>Impede reenvio, restauração ou qualquer uso futuro de dados de bancadas que exerceram seu direito de retirada ética.</td>
          </tr>
          <tr>
            <td><code>client_version</code></td>
            <td>Versão semântica canônica (ex: <code>{canonical_version}</code>)</td>
            <td>Controle de versionamento estrito sincronizado em todas as 39 superfícies do ecossistema PulseLab.</td>
          </tr>
        </tbody>
      </table>

      <h3 id="sec-4-5-expurgo-de-telemetrias-invasivas">4.5 Abolição de telemetrias invasivas</h3>
      <p>Em conformidade estrita com o Art. 14 da LGPD e as deliberações de ética em pesquisa, o PulseLab extinguiu terminantemente qualquer telemetria invasiva:</p>

      <table>
        <thead>
          <tr>
            <th>Mecanismo Avaliado</th>
            <th>Status no PulseLab v{canonical_version}</th>
            <th>Justificativa Ética e Metodológica</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td><strong>Captura de Tela (Screenshots)</strong></td>
            <td><span class="badge-status badge-prohibited">Abolido</span></td>
            <td>Invasivo à privacidade escolar; risco de capturar rostos refletidos ou arquivos pessoais; substituído com ampla superioridade técnica pelo parser passivo de <code>.llsp3</code>.</td>
          </tr>
          <tr>
            <td><strong>Monitoramento de Teclas (Keylogger)</strong></td>
            <td><span class="badge-status badge-prohibited">Abolido</span></td>
            <td>Incompatível com o Art. 14 da LGPD e com as diretrizes do CONEP; risco severo de captura de credenciais ou dados privados.</td>
          </tr>
          <tr>
            <td><strong>Inatividade de Mouse/Teclado</strong></td>
            <td><span class="badge-status badge-prohibited">Abolido</span></td>
            <td>Metodologicamente falho em robótica: crianças passam a maior parte do tempo montando engrenagens fisicamente, o que gerava falsos diagnósticos de "desatenção".</td>
          </tr>
          <tr>
            <td><strong>Questionários aos 20m e 40m</strong></td>
            <td><span class="badge-status badge-prohibited">Abolido</span></td>
            <td>Quebravam a imersão pedagógica, causavam fadiga em crianças e produziam dados contaminados por pressa e distração.</td>
          </tr>
          <tr>
            <td><strong>Identificação Pessoal de Alunos</strong></td>
            <td><span class="badge-status badge-prohibited">Abolido</span></td>
            <td>Substituído pela bancada coletiva (<code>group_id</code> anônimo de 2 a 8 estudantes), dispensando a custódia de dados pessoais sensíveis de menores.</td>
          </tr>
          <tr>
            <td><strong>Parser Passivo do LEGO SPIKE</strong></td>
            <td><span class="badge-status badge-done">Ativo</span></td>
            <td>Inspeciona periodicamente a estrutura sintática de projetos salvos a cada 10s sem qualquer intervenção humana e sem armazenar código bruto.</td>
          </tr>
          <tr>
            <td><strong>Encerramento de Turma Ágil</strong></td>
            <td><span class="badge-status badge-done">Ativo</span></td>
            <td>Encerra a coleta em menos de 15 segundos ao término da aula, preservando a harmonia pedagógica da oficina.</td>
          </tr>
        </tbody>
      </table>

      <hr>

      <h2 id="sec-5-perguntas-de-pesquisa-e-hipoteses-testaveis">5. Perguntas de pesquisa e hipóteses</h2>

      <h3 id="sec-5-1-objetivo-geral">5.1 Objetivo geral</h3>
      <p>Investigar a viabilidade empírica, a integridade métrica e os padrões de evolução algorítmica e colaborativa em oficinas de robótica educacional com LEGO SPIKE Prime, utilizando uma infraestrutura de observabilidade silenciosa e não-invasiva baseada na bancada coletiva como unidade analítica.</p>

      <h3 id="sec-5-2-objetivos-especificos">5.2 Objetivos específicos</h3>
      <ol>
        <li>Caracterizar a trajetória de complexidade estrutural dos projetos de robótica (contagem de blocos, sensores, condições) construídos pelas bancadas ao longo do tempo da oficina.</li>
        <li>Avaliar a associação entre o nível de complexidade algorítmica alcançado e o desfecho prático da missão avaliado pela rubrica do educador (0 a 3).</li>
        <li>Analisar o efeito mediador do nível de apoio pedagógico prestado pelo educador (nenhum, algum, muito) sobre a probabilidade de conclusão da missão.</li>
        <li>Verificar a congruência entre a avaliação afetiva da bancada (4 carinhas) e o desfecho prático alcançado na missão.</li>
        <li>Quantificar os índices de viabilidade técnica (taxa de eventos íntegros, completude de sessões, ausência de falhas locais) em ambiente escolar real desconectado da internet.</li>
      </ol>

      <h3 id="sec-5-3-hipoteses">5.3 Hipóteses testáveis</h3>
      <table>
        <thead>
          <tr>
            <th>Hipótese Formal</th>
            <th>Variáveis Analisadas</th>
            <th>Modelo de Teste</th>
            <th>Justificativa Teórica</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td><strong>H1 (Complexidade e Desfecho):</strong> Bancadas cujos programas integram sensores e condicionais possuem maior chance de alcançar desfecho superior na rubrica (≥ 2).</td>
            <td><code>uses_sensor</code>, <code>uses_condition</code>, <code>resultado_bancada_v1</code></td>
            <td>Regressão Logística Cumulativa Multinível</td>
            <td>Tarefas de desafio (como parada diante de obstáculo) exigem acoplamento funcional entre sensor e controle.</td>
          </tr>
          <tr>
            <td><strong>H2 (Mediação e Resolução):</strong> Bancadas com desfecho pleno (3) sob apoio reduzido exibem trajetórias mais contínuas de depuração no SPIKE que bancadas que demandaram apoio extensivo.</td>
            <td><code>apoio_instrutor_v1</code>, <code>executable_blocks</code>, <code>resultado_bancada_v1</code></td>
            <td>Modelos Lineares Generalizados Mistos (GLMM)</td>
            <td>A autonomia na depuração reflete apropriação dos conceitos computacionais sem dependência do instrutor.</td>
          </tr>
          <tr>
            <td><strong>H3 (Clima Afetivo e Sucesso):</strong> A percepção da bancada (4 carinhas) correlaciona-se positivamente com o desfecho alcançado, mas recusas concentram-se em tarefas não concluídas.</td>
            <td><code>experiencia_bancada_v1</code>, <code>resultado_bancada_v1</code>, recusas (<code>null</code>)</td>
            <td>Correlação Policórica e Teste Exato de Fisher</td>
            <td>O sentimento de competência e autoeficácia coletiva é fomentado pela resolução bem-sucedida do artefato.</td>
          </tr>
          <tr>
            <td><strong>H4 (Viabilidade e Integridade):</strong> A coleta em dupla camada alcança taxa de integridade local ≥ 98% e zero perda catastrófica após reinicialização da máquina.</td>
            <td><code>event_id</code>, integridade IndexedDB, JSONL do Bridge</td>
            <td>Análise Descritiva de Sobrevivência e Integridade</td>
            <td>A arquitetura offline-first assegura estabilidade operacional em redes escolares instáveis.</td>
          </tr>
        </tbody>
      </table>

      <hr>

      <h2 id="sec-6-plano-de-analise-quantitativa">6. Plano de análise quantitativa</h2>

      <h3 id="sec-6-1-preparacao">6.1 Preparação e integridade</h3>
      <ol>
        <li><strong>Validação de Manifesto e CAAE:</strong> Filtrar unicamente eventos que compartilhem o mesmo <code>CONFIG_HASH</code> canônico e pertençam a polos devidamente provisionados com CAAE ativo.</li>
        <li><strong>Deduplicação Atômica:</strong> Deduplicação determinística por <code>event_id</code> (UUID v4) gerado na origem, impedindo contagem repetida decorrente de múltiplos ciclos de sincronização.</li>
        <li><strong>Isolamento de Recusas Éticas:</strong> Bancadas que exerceram recusa (<code>null</code>) ou solicitaram expurgo são mantidas em tabela de auditoria ética e excluídas de inferências substantivas de desempenho, sem imputação depreciativa.</li>
      </ol>

      <h3 id="sec-6-2-analise-descritiva">6.2 Análise descritiva</h3>
      <ul>
        <li>Contagem de turmas, bancadas, escolas e polos participantes.</li>
        <li>Distribuição de frequência de <code>group_size</code> (2 a 8 estudantes por bancada).</li>
        <li>Frequências absolutas e relativas das categorias da rubrica da missão (0 a 3) e dos níveis de apoio docente (nenhum, algum, muito).</li>
        <li>Distribuição das 4 carinhas de clima da bancada, reportando expressamente a proporção de recusas ("Preferimos não responder").</li>
        <li>Medianas, percentis (P25, P75) e amplitudes interquartis para variáveis de código (<code>executable_blocks</code>, <code>top_level_stacks</code>), evitando médias aritméticas enganosas em distribuições assimétricas.</li>
      </ul>

      <h3 id="sec-6-3-modelos-recomendados">6.3 Modelos recomendados (GLMM e multinível)</h3>
      <p>Dada a estrutura naturalmente aninhada dos dados (bancadas aninhadas em turmas, que estão aninhadas em escolas) e a natureza ordinal da maioria dos desfechos, o uso de regressão linear clássica (OLS) é inadequado. O protocolo estabelece:</p>
      
      <p><strong>Para o desfecho da missão (0 a 3):</strong> Modelo Logístico Cumulativo de Efeitos Mistos (<em>Cumulative Link Mixed Model — CLMM</em>):</p>
      <pre><code class="language-text">logit(P(Resultado_ij ≤ k)) = θ_k - [β_1*(ComplexidadeSPIKE_ij) + β_2*(ApoioInstrutor_ij) + β_3*(TamanhoBancada_ij) + u_j]
onde:
- k ∈ {{0, 1, 2}} (categorias de corte ordinal)
- i indexa a bancada, j indexa a escola/turma
- u_j ~ N(0, σ²_escola) representa o efeito aleatório da unidade escolar</code></pre>

      <p>Essa formulação garante que a variabilidade entre turmas e instrutores seja controlada estatisticamente, evitando conclusões espúrias.</p>

      <h3 id="sec-6-4-dados-ausentes-e-etica">6.4 Dados ausentes e autodeterminação ética</h3>
      <p>Em conformidade com a ética em pesquisa educacional, <strong>uma recusa não é um erro do sistema nem uma falha do estudante</strong>. O participante tem o direito soberano de não responder. Portanto:</p>
      <ul>
        <li>É expressamente proibido imputar valores (como substituir <code>null</code> pela média ou por zero).</li>
        <li>Recusas devem ser tabuladas como categoria formal de autonomia: <em>"Taxa de exercício de recusa ética"</em>.</li>
        <li>Falhas técnicas (ex: máquina desligada abruptamente pelo disjuntor) devem ser distinguidas de recusas por meio dos logs de integridade do Bridge.</li>
      </ul>

      <h3 id="sec-6-5-tamanho-amostral">6.5 Dimensionamento amostral do piloto</h3>
      <p>O dimensionamento do piloto inicial de viabilidade prevê:</p>
      <ul>
        <li><strong>Fase 1 (Piloto Técnico):</strong> 3 a 5 escolas, aproximadamente 20 a 30 turmas, totalizando 80 a 120 bancadas (aproximadamente 250 a 400 estudantes). Objetivo: calibrar a robustez do Bridge, validar o parser e verificar a aceitabilidade do <code>TurmaClosing</code>.</li>
        <li><strong>Fase 2 (Estudo Multicêntrico de Associação):</strong> Mínimo de 300 bancadas distribuídas em múltiplos polos regionais para conferir poder estatístico (1 - β ≥ 0,80 a α = 0,05) para detecção de razões de chance (<em>odds ratios</em>) moderadas (OR ≥ 1,8) nos modelos ordinais multiníveis.</li>
      </ul>

      <hr>

      <h2 id="sec-7-criterios-propostos-para-declarar-o-piloto-viavel">7. Critérios de viabilidade do piloto</h2>
      <p>Para que o protocolo seja considerado maduro e apto para transição a estudos de larga escala, o piloto deve satisfazer os seguintes critérios objetivos pré-registrados:</p>

      <table>
        <thead>
          <tr>
            <th>Dimensão de Viabilidade</th>
            <th>Indicador Operacional</th>
            <th>Meta Mínima Exigida</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td><strong>Integridade Local</strong></td>
            <td>Sessões com gravação atômica simultânea em IndexedDB e arquivos JSONL do Bridge</td>
            <td class="numeric"><strong>≥ 99,0%</strong></td>
          </tr>
          <tr>
            <td><strong>Adesão ao Encerramento</strong></td>
            <td>Turmas com <code>TurmaClosing</code> completado (avaliação da bancada + rubrica)</td>
            <td class="numeric"><strong>≥ 92,0%</strong></td>
          </tr>
          <tr>
            <td><strong>Conformidade do Parser</strong></td>
            <td>Sessões com telemetria do LEGO SPIKE extraída com sucesso</td>
            <td class="numeric"><strong>≥ 95,0%</strong></td>
          </tr>
          <tr>
            <td><strong>Privacidade e LGPD</strong></td>
            <td>Payloads com nomes de estudantes, dados biométricos ou capturas de tela</td>
            <td class="numeric"><strong>0,0% (Zero absoluto)</strong></td>
          </tr>
          <tr>
            <td><strong>Conformidade de Hash</strong></td>
            <td>Eventos coletados com <code>CONFIG_HASH</code> idêntico ao canônico</td>
            <td class="numeric"><strong>100,0%</strong></td>
          </tr>
          <tr>
            <td><strong>Recuperação de Desistência</strong></td>
            <td>Execução bem-sucedida de purga e tombstone quando solicitado</td>
            <td class="numeric"><strong>100,0%</strong></td>
          </tr>
        </tbody>
      </table>

      <hr>

      <h2 id="sec-8-evidencias-de-validade-necessarias">8. Evidências de validade necessárias</h2>
      <p>Em consonância com os <em>Standards for Educational and Psychological Testing</em> (AERA; APA; NCME, 2014), a validade não é uma propriedade estática de um software, mas um argumento construído cumulativamente a partir de evidências empíricas:</p>

      <ol>
        <li><strong>Evidência de Conteúdo da Rubrica:</strong> Painel de juízes especialistas em robótica educativa avaliando a clareza dos 4 níveis de desfecho (0 a 3) e dos 3 níveis de apoio na missão de referência (ex: parada com sensor de distância).</li>
        <li><strong>Evidência de Processo de Resposta:</strong> Observação piloto com educadores e estudantes para confirmar que os 4 emojis de clima são prontamente compreendidos pelas crianças sem hesitação ou indução do mediador.</li>
        <li><strong>Evidência de Estrutura Interna e Convergência:</strong> Verificação da consistência entre a evolução dos blocos executáveis do SPIKE e o desfecho relatado na rubrica pelo educador.</li>
        <li><strong>Confiabilidade Interobservador da Rubrica:</strong> Em uma subamostra de bancadas do piloto, dois avaliadores independentes preenchem a rubrica da mesma missão para calcular o coeficiente Kappa ponderado de concordância (almejando κ ≥ 0,75).</li>
      </ol>

      <hr>

      <h2 id="sec-9-auditoria-do-estado-atual-da-implementacao">9. Auditoria da implementação atual</h2>
      <p>Esta seção discrimina o estado técnico rigoroso dos componentes na versão {canonical_version}:</p>

      <table>
        <thead>
          <tr>
            <th>Componente Arquitetural</th>
            <th>Arquivo / Subsistema</th>
            <th>Status Operacional</th>
            <th>Papel Metodológico</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td><strong>PWA Alunos Silenciosa</strong></td>
            <td><code>apps/student-pwa/app/student-page.jsx</code></td>
            <td><span class="badge-status badge-done">Operacional</span></td>
            <td>Interface de corredor sem questionários em tela; modo lab (<code>?lab=1</code>) para inspeção.</td>
          </tr>
          <tr>
            <td><strong>Encerramento de Turma</strong></td>
            <td>Componente <code>TurmaClosing</code></td>
            <td><span class="badge-status badge-done">Operacional</span></td>
            <td>Coleta rápida em 2 etapas: 4 carinhas pela bancada + rubrica do educador.</td>
          </tr>
          <tr>
            <td><strong>Bridge Local Windows</strong></td>
            <td><code>bridge/pulselab-bridge.ps1</code> (Porta 43128)</td>
            <td><span class="badge-status badge-done">Operacional</span></td>
            <td>Servidor HTTP local, rotas <code>/v1/</code>, persistência atômica em <code>dados_locais/</code>.</td>
          </tr>
          <tr>
            <td><strong>Parser Passivo SPIKE</strong></td>
            <td><code>bridge/spike-parser.ps1</code></td>
            <td><span class="badge-status badge-done">Operacional</span></td>
            <td>Inspeciona periodicamente a cada 10s arquivos <code>.llsp3</code>; extrai métricas estruturais.</td>
          </tr>
          <tr>
            <td><strong>Dupla Camada Local</strong></td>
            <td>IndexedDB + <code>dados_locais/*.jsonl</code></td>
            <td><span class="badge-status badge-done">Operacional</span></td>
            <td>Garante tolerância a falhas e persistência imediata mesmo offline.</td>
          </tr>
          <tr>
            <td><strong>Governança Fail-Closed</strong></td>
            <td><code>tooling/polo/gerar-pacote-polo.py</code></td>
            <td><span class="badge-status badge-done">Operacional</span></td>
            <td>Pesquisa só grava com <code>provisionamento.json</code> e CAAE oficial; senão, Modo Livre.</td>
          </tr>
          <tr>
            <td><strong>Retenção e Tombstone</strong></td>
            <td><code>enforceAbsoluteRetention</code> e limpeza horária</td>
            <td><span class="badge-status badge-done">Operacional</span></td>
            <td>Retenção configurável (180 dias) e expurgo ético definitivo com tombstone durável.</td>
          </tr>
          <tr>
            <td><strong>Exportador USB</strong></td>
            <td><code>Exportar-Dados-Pendrive.bat</code></td>
            <td><span class="badge-status badge-done">Operacional</span></td>
            <td>Consolidação dos dados em arquivo ZIP com manifesto e checksum SHA-256.</td>
          </tr>
          <tr>
            <td><strong>Atualizador Assinado</strong></td>
            <td><code>pulselab-update.ps1</code> com RSA-SHA256</td>
            <td><span class="badge-status badge-done">Operacional</span></td>
            <td>Atualização criptograficamente verificada sem intervenção manual na escola.</td>
          </tr>
        </tbody>
      </table>

      <hr>

      <h2 id="sec-10-por-que-o-aplicativo-agrega-valor-a-pesquisa">10. Valor agregado à pesquisa científica</h2>
      
      <p>A implantação do PulseLab agrega valor determinante à pesquisa em quatro dimensões fundamentais:</p>
      
      <ol>
        <li><strong>Observabilidade Silenciosa e Validade Ecológica:</strong> Ao eliminar questionários na tela e telas intrusivas, os estudantes agem de forma genuína. A atividade investigada é a robótica real, e não a habilidade de responder formulários digitais sob pressão de tempo.</li>
        <li><strong>Proteção por Design (Privacy by Design / LGPD Art. 14):</strong> A pesquisa nasce em conformidade jurídica estrita. Ao abolir capturas de tela, áudio, vídeo, gravação de teclas e identificadores de crianças, o projeto afasta riscos legais e garante a preservação da dignidade dos estudantes.</li>
        <li><strong>Padronização Multicêntrica e Reprodutibilidade:</strong> A coleta em dez escolas diferentes segue exatamente a mesma instrumentação, o mesmo manifesto matemático (<code>CONFIG_HASH</code>), a mesma periodicidade de inspeção de código e os mesmos critérios de registro.</li>
        <li><strong>Resiliência para a Escola Pública Brasileira:</strong> O ecossistema opera 100% offline. Toda a lógica de medição independe de internet ativa na bancada, viabilizando pesquisas rigorosas em qualquer região do semiárido ou do interior do país.</li>
      </ol>

      <hr>

      <h2 id="sec-11-limites-das-conclusoes">11. Limites das conclusões</h2>

      <h3>O que o PulseLab pode sustentar com rigor</h3>
      <ul>
        <li>Descrição temporal da evolução algorítmica e da complexidade estrutural dos artefatos programados no LEGO SPIKE Prime por bancada.</li>
        <li>Correlações empíricas entre sofisticação do código (sensores, condicionais, motores) e desfecho alcançado na missão.</li>
        <li>Relação entre o nível de apoio pedagógico prestado pelo mediador e a probabilidade de êxito da bancada.</li>
        <li>Padrões de satisfação coletiva imediata da bancada em relação ao desafio proposto.</li>
        <li>Indicadores auditáveis de viabilidade, completude e integridade da coleta distribuída em larga escala.</li>
      </ul>

      <h3>O que o PulseLab NÃO sustenta sozinho</h3>
      <ul>
        <li>Alegações de causalidade estrita sobre a robótica gerar aumento cognitivo individual permanente.</li>
        <li>Inferências psicológicas ou diagnósticos clínicos individuais de crianças.</li>
        <li>Medição de "aprendizagem conceitual profunda" baseada unicamente na quantidade de blocos inseridos no programa.</li>
        <li>Avaliação da montagem mecânica física do robô (o sistema lê o arquivo de software, não o aperto das vigas plásticas).</li>
        <li>Comparações individuais entre estudantes da mesma bancada (a unidade é o grupo).</li>
      </ul>

      <hr>

      <h2 id="sec-12-perguntas-provaveis-da-banca-e-respostas-recomendadas">12. Perguntas da banca e respostas</h2>

      <h3>1. “Por que adotar a bancada coletiva e não a criança individual como unidade de análise?”</h3>
      <p><strong>Resposta do Pesquisador:</strong> <em>“Em oficinas de robótica educativa, o robô é coletivo, o computador é compartilhado e a resolução é colaborativa. Individualizar respostas no mesmo teclado criaria forte contaminação recíproca e violaria o Artigo 14 da LGPD ao exigir identificação de menores. A bancada é a unidade ecológica real da atividade, evitando a pseudorreplicação estatística e garantindo privacidade por design.”</em></p>

      <h3>2. “Por que eliminar os questionários periódicos durante a oficina?”</h3>
      <p><strong>Resposta do Pesquisador:</strong> <em>“A literatura e os pilotos demonstraram que interromper crianças no meio da montagem ou programação quebra o estado de concentração e engajamento lúdico. As crianças respondiam aleatoriamente para fechar a tela rápido, ou respondiam com viés de agradar o instrutor. A observabilidade silenciosa do código e a avaliação rápida de encerramento eliminam esse viés, respeitando a fluência pedagógica.”</em></p>

      <h3>3. “Como confiar na telemetria de código se ela não grava o código inteiro?”</h3>
      <p><strong>Resposta do Pesquisador:</strong> <em>“O parser inspeciona a árvore sintática abstrata do arquivo oficial <code>.llsp3</code> e extrai contagens estruturais exatas: blocos executáveis, pilhas de concorrência, motores, sensores e laços de repetição. Não armazenamos strings ou comentários de usuário porque eles agregariam risco de privacidade sem ganho para a modelagem estatística da complexidade algorítmica.”</em></p>

      <h3>4. “Como a pesquisa atende às exigências éticas do CEP e da LGPD?”</h3>
      <p><strong>Resposta do Pesquisador:</strong> <em>“O sistema opera em modo fail-closed: a coleta de pesquisa permanece rigorosamente desligada em pacotes genéricos e só é ativada quando o pacote do polo inclui o CAAE do protocolo aprovado no CEP/CONEP. O assentimento é voluntário, e qualquer recusa ativa o Modo Livre, garantindo acesso pedagógico pleno sem gravação de dados. Além disso, o botão de retirada executa a exclusão imediata dos dados com tombstone irreversível.”</em></p>

      <h3>5. “Como o sistema se comporta em escolas sem conexão com a internet?”</h3>
      <p><strong>Resposta do Pesquisador:</strong> <em>“O PulseLab é nativamente offline-first. Toda a gravação é persistida no banco IndexedDB e nos arquivos locais do Bridge Windows. Se houver internet, ele sincroniza em segundo plano; se não houver, o educador utiliza a rotina de exportação via pendrive, que gera um arquivo ZIP com manifesto e checksum SHA-256 para auditoria e posterior ingestão.”</em></p>

      <hr>

      <h2 id="sec-13-roteiro-de-defesa-oral-em-dois-minutos">13. Defesa oral em dois minutos</h2>
      
      <blockquote>
        <p>“Senhores membros da banca examinadora: o desafio central na avaliação de oficinas de robótica escolar nunca foi a falta de entusiasmo dos alunos, mas sim a ausência de uma infraestrutura de mensuração que seja, ao mesmo tempo, cientificamente rigorosa e pedagogicamente respeitosa.</p>
        <p>Modelos tradicionais tentavam forçar crianças a responder questionários em tela a cada 20 minutos, quebrando o fluxo criativo e gerando dados viciados por pressa ou cansaço. Por outro lado, tentativas de vigilância eletrônica violavam a privacidade dos estudantes e a LGPD.</p>
        <p>O PulseLab v{canonical_version} resolve esse impasse através de um princípio basilar: <strong>observabilidade silenciosa e não-invasiva</strong>. Durante toda a prática com o LEGO SPIKE Prime, o sistema não exibe um único formulário na tela das crianças. Ele monitora passivamente a evolução estrutural do código em segundo plano a cada 10 segundos, extraindo a complexidade de blocos, motores, sensores e laços de repetição.</p>
        <p>A unidade de análise é a <strong>bancada coletiva</strong>, e não a criança isolada. Isso reflete a natureza colaborativa da robótica, elimina a pseudorreplicação estatística e assegura conformidade total com o Artigo 14 da LGPD, pois nenhum dado pessoal individual de menor é capturado. No encerramento da aula, o componente ágil reúne a percepção lúdica da bancada em quatro carinhas e a rubrica objetiva da missão preenchida pelo educador.</p>
        <p>Com persistência em dupla camada local, governança fail-closed acionada unicamente pelo CAAE do comitê de ética e operação offline-first, o PulseLab entrega dados limpos, estruturados e reprodutíveis para orientar a mediação docente e qualificar academicamente o impacto da robótica educativa pública.”</p>
      </blockquote>

      <hr>

      <h2 id="sec-14-plano-de-maturacao-e-protocolo-de-campo">14. Protocolo de campo e maturação</h2>
      
      <p>O cronograma de campo para execução do protocolo de pesquisa compreende três etapas sequenciais:</p>

      <ol>
        <li><strong>Fase de Alinhamento e Treinamento Docente (Semana 1–2):</strong>
          <ul>
            <li>Treinamento dos educadores na missão padronizada de referência (<em>distance-stop</em>).</li>
            <li>Calibração do preenchimento da rubrica de encerramento (0 a 3) e dos critérios de nível de apoio (nenhum, algum, muito).</li>
            <li>Simulação do fluxo de assentimento livre e ativação do Modo Livre em casos de recusa.</li>
          </ul>
        </li>
        <li><strong>Piloto Supervisionado de Campo (Semana 3–6):</strong>
          <ul>
            <li>Aplicação em 3 a 5 escolas públicas de diferentes polos regionais.</li>
            <li>Auditoria diária dos arquivos JSONL de log gerados pelo Bridge.</li>
            <li>Verificação da integridade das telemetrias passivas extraídas de <code>.llsp3</code>.</li>
            <li>Avaliação da aceitabilidade do modal de encerramento da turma pelas crianças.</li>
          </ul>
        </li>
        <li><strong>Consolidação e Modelagem Estatística (Semana 7–10):</strong>
          <ul>
            <li>Ingestão controlada no banco central Supabase e validação criptográfica de integridade de <code>CONFIG_HASH</code>.</li>
            <li>Ajuste dos Modelos Lineares Generalizados Mistos (GLMM) para verificação das hipóteses H1 a H4.</li>
            <li>Publicação dos relatórios técnicos e devolução pedagógica aos polos regionais sem identificação ou estigmatização de escolas.</li>
          </ul>
        </li>
      </ol>

      <hr>

      <h2 id="sec-15-consideracoes-eticas-e-protecao-de-dados">15. Governança ética e LGPD (Art. 14)</h2>
      
      <p>A governança ética do PulseLab fundamenta-se nas seguintes salvaguardas normativas e técnicas invioláveis:</p>

      <ul>
        <li><strong>Melhor Interesse da Criança e do Adolescente (LGPD Art. 14):</strong> Nenhum dado individual (nome, CPF, foto, áudio, vídeo, biometria ou endereço IP externo) é coletado, processado ou armazenado. Toda a observação circunscreve-se à bancada coletiva anônima.</li>
        <li><strong>Subordinação ao Sistema CEP/CONEP (Resolução CNS nº 510/2016):</strong> A coleta de pesquisa só pode operar com o número do Certificado de Apresentação de Apreciação Ética (CAAE) formalmente emitido por Comitê de Ética em Pesquisa, inserido no <code>provisionamento.json</code>. Na ausência desse arquivo, o aplicativo opera compulsoriamente em <em>Modo Livre</em>, sem qualquer gravação de pesquisa.</li>
        <li><strong>Assentimento Livre e Não-Punitivo:</strong> Na abertura da sessão, os termos de assentimento iniciam desmarcados. Caso os estudantes ou responsáveis optem por não participar, o Modo Livre é ativado automaticamente, garantindo acesso pedagógico integral às ferramentas do robô.</li>
        <li><strong>Custódia Local Temporária e Expurgo Absoluto:</strong> Os dados armazenados nas máquinas escolares possuem prazo estrito de expurgo (padrão de 180 dias, configurável no polo de 1 a 365 dias). O Bridge executa rotina automática de limpeza baseada em data de criação.</li>
        <li><strong>Garantia de Desistência com Tombstone Irreversível:</strong> O botão visível <em>"Parar de participar e apagar meus dados"</em> executa o expurgo definitivo e imediato do banco IndexedDB e dos arquivos do Bridge, grava um <em>tombstone</em> criptográfico que bloqueia qualquer ressincronização e dispara ordem de exclusão remota autenticada.</li>
      </ul>

      <hr>

      <h2 id="sec-16-conclusao">16. Conclusão</h2>
      
      <p>O <strong>PulseLab v{canonical_version}</strong> consolida uma mudança paradigmática fundamental no campo da mensuração educacional aplicada à robótica escolar. Ao substituir métodos intrusivos e vigilantes por uma <strong>arquitetura de observabilidade passiva, silenciosa e centrada na bancada coletiva</strong>, o sistema equilibra com sucesso o rigor metodológico da pesquisa com o respeito irrestrito à experiência lúdica e à privacidade de crianças e adolescentes.</p>

      <p>O ecossistema entrega dados empíricos de alta fidelidade: o código do robô é registrado em sua complexidade real; a mediação pedagógica é quantificada com transparência; o clima coletivo da turma é capturado em segundos; e os direitos fundamentais dos estudantes são integralmente preservados por design sob a égide da LGPD. O PulseLab não pretende substituir a teoria pedagógica ou o olhar sensível do educador; ao contrário, ele oferece a infraestrutura técnica necessária para que a educação e a pesquisa caminhem de forma ética, auditável e transformadora na escola pública.</p>

      <hr>

      <h2 id="referencias">Referências</h2>
      
      <p>AMERICAN EDUCATIONAL RESEARCH ASSOCIATION; AMERICAN PSYCHOLOGICAL ASSOCIATION; NATIONAL COUNCIL ON MEASUREMENT IN EDUCATION. <strong>Standards for educational and psychological testing</strong>. Washington, DC: AERA, 2014.</p>
      
      <p>BENITTI, Fabiane Barreto Vavassori. Exploring the educational potential of robotics in schools: a systematic review. <strong>Computers &amp; Education</strong>, v. 58, n. 3, p. 978–988, 2012. DOI: <a href="https://doi.org/10.1016/j.compedu.2011.10.006">10.1016/j.compedu.2011.10.006</a>.</p>
      
      <p>BLIKSTEIN, Paulo. Multimodal learning analytics. In: <strong>Proceedings of the Third International Conference on Learning Analytics and Knowledge — LAK ’13</strong>. New York: ACM, 2013. p. 102–106. DOI: <a href="https://doi.org/10.1145/2460296.2460316">10.1145/2460296.2460316</a>.</p>
      
      <p>BRASIL. Conselho Nacional de Saúde. <strong>Resolução nº 510, de 7 de abril de 2016</strong>. Dispõe sobre as normas aplicáveis a pesquisas em Ciências Humanas e Sociais. Brasília: Diário Oficial da União, 2016.</p>
      
      <p>BRASIL. <strong>Lei nº 13.709, de 14 de agosto de 2018</strong>. Lei Geral de Proteção de Dados Pessoais (LGPD). Brasília: Diário Oficial da União, 2018.</p>
      
      <p>PAAS, Fred et al. Cognitive load measurement as a means to advance cognitive load theory. <strong>Educational Psychologist</strong>, v. 38, n. 1, p. 63–71, 2003. DOI: <a href="https://doi.org/10.1207/S15326985EP3801_8">10.1207/S15326985EP3801_8</a>.</p>
      
      <p>SCHUESSLER, Katrin; FISCHER, Vanessa; WALPUSKI, Maik. Investigating construct validity of cognitive load measurement using single-item subjective rating scales. <strong>Instructional Science</strong>, v. 53, p. 71–97, 2025. DOI: <a href="https://doi.org/10.1007/s11251-024-09692-6">10.1007/s11251-024-09692-6</a>.</p>
      
      <p>SOCIETY FOR LEARNING ANALYTICS RESEARCH. <strong>What is learning analytics?</strong> SoLAR, 2025. Disponível em: <a href="https://www.solaresearch.org/about/what-is-learning-analytics/">https://www.solaresearch.org/about/what-is-learning-analytics/</a>.</p>
      
      <p>VAN GOG, Tamara et al. Timing and frequency of mental effort measurement: evidence in favour of repeated measures. <strong>Applied Cognitive Psychology</strong>, v. 26, n. 6, p. 833–839, 2012. DOI: <a href="https://doi.org/10.1002/acp.2883">10.1002/acp.2883</a>.</p>
      
      <p>VON ELM, Erik et al. The Strengthening the Reporting of Observational Studies in Epidemiology (STROBE) statement: guidelines for reporting observational studies. <strong>The Lancet</strong>, v. 370, n. 9596, p. 1453–1457, 2007. DOI: <a href="https://doi.org/10.1016/S0140-6736(07)61602-X">10.1016/S0140-6736(07)61602-X</a>.</p>

    </main>
  </div>

  <button class="back-to-top" id="back-to-top" type="button" aria-label="Voltar ao início" title="Voltar ao início">↑</button>

  <footer class="document-footer">
    Vinicius Ferreira Amim · Universidade Federal do Vale do São Francisco (UNIVASF) · Setor de Pesquisa da FADEX — Projeto Robótica Educativa
  </footer>

  <script>
    (() => {{
      const progress = document.getElementById("reading-progress");
      const toTop = document.getElementById("back-to-top");
      const tocLinks = [...document.querySelectorAll("#toc-nav a")];
      const sections = tocLinks
        .map((link) => document.getElementById(link.getAttribute("href").slice(1)))
        .filter(Boolean);

      const updateScroll = () => {{
        const root = document.documentElement;
        const available = root.scrollHeight - root.clientHeight;
        const ratio = available > 0 ? root.scrollTop / available : 0;
        progress.style.width = `${{Math.min(100, Math.max(0, ratio * 100))}}%`;
        toTop.classList.toggle("is-visible", root.scrollTop > 700);

        let active = sections[0];
        for (const section of sections) {{
          if (section.getBoundingClientRect().top <= 140) active = section;
        }}
        tocLinks.forEach((link) => {{
          link.classList.toggle("is-active", active && link.getAttribute("href") === `#${{active.id}}`);
        }});
      }};

      window.addEventListener("scroll", updateScroll, {{ passive: true }});
      window.addEventListener("resize", updateScroll);
      toTop.addEventListener("click", () => window.scrollTo({{ top: 0, behavior: "smooth" }}));
      updateScroll();
    }})();
  </script>
</body>
</html>
"""

def main():
    repo_root = Path(__file__).resolve().parents[2]
    # A página leva o marcador; tooling/site/build-hosting.py troca pela versão de VERSION ao publicar.
    version = "__PULSELAB_VERSION__"

    html = generate_html(version)
    target = repo_root / "apps" / "site" / "relatorio" / "index.html"
    target.write_text(html, encoding="utf-8")
    print(f"Relatório gerado com sucesso em {target} ({len(html)} bytes, versão {version})")

if __name__ == "__main__":
    main()
