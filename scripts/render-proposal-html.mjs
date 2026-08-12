#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(scriptDirectory, "..");
const sourcePath = resolve(
  projectRoot,
  "docs/proposta-reformulada-pulselab-2.0-mvp-pesquisa.md",
);
const outputPath = resolve(projectRoot, "relatorio/proposta-pulselab-2.0.html");

const markdown = await readFile(sourcePath, "utf8");

function escapeHtml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function slugify(value) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/<[^>]+>/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}

function normalizeHref(href) {
  if (
    href.startsWith("http://") ||
    href.startsWith("https://") ||
    href.startsWith("#") ||
    href.startsWith("../") ||
    href.startsWith("/")
  ) {
    return href;
  }

  if (href.endsWith(".md")) {
    return `../docs/${href}`;
  }

  return href;
}

function renderInline(value) {
  const tokens = [];
  const stash = (html) => {
    const token = `\u0000TOKEN${tokens.length}\u0000`;
    tokens.push(html);
    return token;
  };

  let output = value.replace(/`([^`]+)`/g, (_, code) =>
    stash(`<code>${escapeHtml(code)}</code>`),
  );

  output = output.replace(/\[([^\]]+)]\(([^)]+)\)/g, (_, label, rawHref) => {
    const href = normalizeHref(rawHref.trim());
    const external = /^https?:\/\//.test(href)
      ? ' target="_blank" rel="noopener noreferrer"'
      : "";
    const safeLabel = escapeHtml(label)
      .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
      .replace(/\*([^*]+)\*/g, "<em>$1</em>");
    return stash(
      `<a href="${escapeHtml(href)}"${external}>${safeLabel}</a>`,
    );
  });

  output = escapeHtml(output)
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/\*([^*]+)\*/g, "<em>$1</em>");

  tokens.forEach((token, index) => {
    output = output.replace(`\u0000TOKEN${index}\u0000`, token);
  });

  return output;
}

function splitTableRow(line) {
  return line
    .trim()
    .replace(/^\|/, "")
    .replace(/\|$/, "")
    .split("|")
    .map((cell) => cell.trim());
}

function isTableDivider(line) {
  const cells = splitTableRow(line);
  return cells.length > 1 && cells.every((cell) => /^:?-{3,}:?$/.test(cell));
}

function startsBlock(lines, index) {
  const line = lines[index] ?? "";
  const next = lines[index + 1] ?? "";
  return (
    !line.trim() ||
    /^#{1,4}\s+/.test(line) ||
    /^```/.test(line) ||
    /^(?:-{3,}|\*{3,}|_{3,})\s*$/.test(line) ||
    /^>\s?/.test(line) ||
    /^[-*]\s+/.test(line) ||
    /^\d+\.\s+/.test(line) ||
    (line.includes("|") && isTableDivider(next))
  );
}

function renderMarkdown(source) {
  const lines = source.replaceAll("\r\n", "\n").split("\n");
  const headings = [];
  const usedIds = new Map();
  const html = [];
  let index = 0;
  let sectionOpen = false;

  const uniqueId = (label) => {
    const base = slugify(label) || "secao";
    const count = usedIds.get(base) ?? 0;
    usedIds.set(base, count + 1);
    return count === 0 ? base : `${base}-${count + 1}`;
  };

  while (index < lines.length) {
    const line = lines[index];

    if (!line.trim()) {
      index += 1;
      continue;
    }

    if (/^(?:-{3,}|\*{3,}|_{3,})\s*$/.test(line)) {
      index += 1;
      continue;
    }

    const heading = line.match(/^(#{1,4})\s+(.+)$/);
    if (heading) {
      const level = heading[1].length;
      const label = heading[2].trim();

      if (level === 1) {
        index += 1;
        continue;
      }

      const id = uniqueId(label);
      if (level === 2) {
        if (sectionOpen) html.push("</section>");
        sectionOpen = true;
        headings.push({ id, label: label.replace(/^\d+\.\s*/, "") });
        const number = label.match(/^(\d+)\./)?.[1]?.padStart(2, "0") ?? "";
        html.push(`<section class="doc-section" id="${id}">`);
        if (number) html.push(`<p class="section-kicker">${number} · Documento completo</p>`);
        html.push(`<h2>${renderInline(label.replace(/^\d+\.\s*/, ""))}</h2>`);
      } else {
        html.push(`<h${level} id="${id}">${renderInline(label)}</h${level}>`);
      }
      index += 1;
      continue;
    }

    if (/^```/.test(line)) {
      const language = line.slice(3).trim();
      const code = [];
      index += 1;
      while (index < lines.length && !/^```/.test(lines[index])) {
        code.push(lines[index]);
        index += 1;
      }
      if (index < lines.length) index += 1;
      const className = language ? ` class="language-${escapeHtml(language)}"` : "";
      html.push(
        `<div class="code-wrap"><pre><code${className}>${escapeHtml(code.join("\n"))}</code></pre></div>`,
      );
      continue;
    }

    if (/^>\s?/.test(line)) {
      const quote = [];
      while (index < lines.length && /^>\s?/.test(lines[index])) {
        quote.push(lines[index].replace(/^>\s?/, ""));
        index += 1;
      }
      html.push(`<blockquote><p>${renderInline(quote.join(" "))}</p></blockquote>`);
      continue;
    }

    if (line.includes("|") && isTableDivider(lines[index + 1] ?? "")) {
      const headers = splitTableRow(line);
      const rows = [];
      index += 2;
      while (index < lines.length && lines[index].includes("|") && lines[index].trim()) {
        rows.push(splitTableRow(lines[index]));
        index += 1;
      }

      const headerHtml = headers
        .map((cell, column) => `<th scope="col" data-column="${column}">${renderInline(cell)}</th>`)
        .join("");
      const bodyHtml = rows
        .map((row) => {
          const priority = /^P[0-2]$/.test(row[0] ?? "")
            ? ` class="priority-${row[0].toLowerCase()}"`
            : "";
          return `<tr${priority}>${row
            .map((cell) => `<td>${renderInline(cell)}</td>`)
            .join("")}</tr>`;
        })
        .join("");

      html.push(
        `<div class="table-wrap" tabindex="0" role="region" aria-label="Tabela com rolagem horizontal"><table><thead><tr>${headerHtml}</tr></thead><tbody>${bodyHtml}</tbody></table></div>`,
      );
      continue;
    }

    const unordered = line.match(/^[-*]\s+(.+)$/);
    const ordered = line.match(/^\d+\.\s+(.+)$/);
    if (unordered || ordered) {
      const tag = unordered ? "ul" : "ol";
      const items = [];
      let checklist = false;

      while (index < lines.length) {
        const match =
          tag === "ul"
            ? lines[index].match(/^[-*]\s+(.+)$/)
            : lines[index].match(/^\d+\.\s+(.+)$/);
        if (!match) break;

        let item = match[1];
        const checkbox = item.match(/^\[([ xX])]\s+(.+)$/);
        if (checkbox) {
          checklist = true;
          const checked = checkbox[1].toLowerCase() === "x";
          item = `<span class="checkmark" aria-hidden="true">${checked ? "✓" : ""}</span>${renderInline(checkbox[2])}`;
        } else {
          item = renderInline(item);
        }
        items.push(`<li>${item}</li>`);
        index += 1;
      }

      const className = checklist ? ' class="checklist"' : "";
      html.push(`<${tag}${className}>${items.join("")}</${tag}>`);
      continue;
    }

    const paragraph = [line.trim()];
    index += 1;
    while (index < lines.length && !startsBlock(lines, index)) {
      paragraph.push(lines[index].trim());
      index += 1;
    }
    html.push(`<p>${renderInline(paragraph.join(" "))}</p>`);
  }

  if (sectionOpen) html.push("</section>");
  return { body: html.join("\n"), headings };
}

const { body, headings } = renderMarkdown(markdown);
const toc = headings
  .map(
    ({ id, label }, index) =>
      `<a href="#${id}"><span>${String(index + 1).padStart(2, "0")}</span>${renderInline(label)}</a>`,
  )
  .join("\n");

const html = `<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="Revisão estratégica do PulseLab, benchmark de soluções similares, proposta acadêmica e escopo do MVP de pesquisa.">
  <meta name="theme-color" content="#24164f">
  <title>PulseLab 2.0 — proposta reformulada e MVP de pesquisa</title>
  <style>
    :root {
      color-scheme: light;
      --ink: #17202e;
      --muted: #5e6878;
      --paper: #f8f7f3;
      --surface: #ffffff;
      --surface-2: #f0eee8;
      --line: #dedad1;
      --violet-950: #24164f;
      --violet-800: #3c257f;
      --violet-650: #5d43bc;
      --violet-100: #eee9ff;
      --teal-700: #087783;
      --teal-100: #e0f4f2;
      --green-700: #28734f;
      --green-100: #e4f3e9;
      --amber-800: #8c5206;
      --amber-100: #fff1d2;
      --red-800: #9b3434;
      --red-100: #fde8e8;
      --shadow: 0 18px 56px rgba(36, 22, 79, 0.10);
      --radius: 20px;
      --max: 1240px;
    }

    * { box-sizing: border-box; }

    html {
      scroll-behavior: smooth;
      scroll-padding-top: 28px;
    }

    body {
      margin: 0;
      color: var(--ink);
      background:
        radial-gradient(circle at 7% 1%, rgba(93, 67, 188, 0.10), transparent 27rem),
        radial-gradient(circle at 98% 17%, rgba(8, 119, 131, 0.08), transparent 25rem),
        var(--paper);
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      font-size: 1rem;
      line-height: 1.68;
      text-rendering: optimizeLegibility;
    }

    a { color: var(--violet-800); text-decoration-thickness: 1px; text-underline-offset: 3px; }
    a:hover { color: var(--teal-700); }
    button { font: inherit; }

    .skip-link {
      position: fixed;
      z-index: 999;
      top: 10px;
      left: 10px;
      padding: 10px 14px;
      color: #fff;
      background: var(--violet-950);
      border-radius: 8px;
      transform: translateY(-180%);
    }

    .skip-link:focus { transform: translateY(0); }

    .reading-progress {
      position: fixed;
      z-index: 100;
      inset: 0 auto auto 0;
      width: 0;
      height: 4px;
      background: linear-gradient(90deg, #8c6ff1, #52d0c2);
    }

    .hero {
      position: relative;
      overflow: hidden;
      color: #fff;
      background: linear-gradient(125deg, #1d123f 0%, #432788 58%, #08717c 125%);
    }

    .hero::before,
    .hero::after {
      content: "";
      position: absolute;
      border: 1px solid rgba(255,255,255,0.13);
      border-radius: 50%;
      pointer-events: none;
    }

    .hero::before { width: 32rem; height: 32rem; top: -18rem; right: -9rem; }
    .hero::after { width: 19rem; height: 19rem; right: 15rem; bottom: -14rem; }

    .hero-inner {
      position: relative;
      z-index: 1;
      display: grid;
      grid-template-columns: minmax(0, 1.45fr) minmax(270px, 0.75fr);
      gap: clamp(30px, 6vw, 82px);
      align-items: end;
      width: min(calc(100% - 40px), var(--max));
      margin: 0 auto;
      padding: clamp(58px, 8vw, 104px) 0 64px;
    }

    .eyebrow {
      display: inline-flex;
      align-items: center;
      gap: 9px;
      margin: 0 0 18px;
      padding: 7px 12px;
      color: #e2dcff;
      background: rgba(255,255,255,0.10);
      border: 1px solid rgba(255,255,255,0.18);
      border-radius: 999px;
      font-size: 0.76rem;
      font-weight: 800;
      letter-spacing: 0.10em;
      text-transform: uppercase;
    }

    .eyebrow::before {
      content: "";
      width: 8px;
      height: 8px;
      background: #67e8d5;
      border-radius: 50%;
      box-shadow: 0 0 0 5px rgba(103, 232, 213, 0.13);
    }

    h1, h2, h3, h4 {
      margin-top: 0;
      font-family: "Aptos Display", "Segoe UI", system-ui, sans-serif;
      line-height: 1.16;
      text-wrap: balance;
    }

    h1 {
      max-width: 850px;
      margin-bottom: 20px;
      font-size: clamp(2.55rem, 6.2vw, 5.35rem);
      letter-spacing: -0.055em;
    }

    .hero-lead {
      max-width: 780px;
      margin: 0;
      color: #e9e6f4;
      font-size: clamp(1.08rem, 2vw, 1.32rem);
    }

    .hero-meta {
      display: flex;
      flex-wrap: wrap;
      gap: 10px 22px;
      margin-top: 28px;
      color: #d1cbe7;
      font-size: 0.87rem;
    }

    .hero-meta strong { color: #fff; }

    .actions { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 30px; }

    .button {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-height: 44px;
      padding: 10px 16px;
      color: #fff;
      background: rgba(255,255,255,0.10);
      border: 1px solid rgba(255,255,255,0.24);
      border-radius: 11px;
      cursor: pointer;
      font-weight: 750;
      text-decoration: none;
    }

    .button:hover { color: #fff; background: rgba(255,255,255,0.18); }
    .button.primary { color: var(--violet-950); background: #fff; }
    .button.primary:hover { color: var(--violet-650); background: #f3f0ff; }

    .hero-question {
      padding: 24px;
      background: rgba(13, 8, 33, 0.28);
      border: 1px solid rgba(255,255,255,0.18);
      border-radius: 18px;
      backdrop-filter: blur(10px);
      box-shadow: 0 20px 48px rgba(0,0,0,0.13);
    }

    .hero-question small {
      display: block;
      margin-bottom: 10px;
      color: #75e3d8;
      font-weight: 800;
      letter-spacing: 0.09em;
      text-transform: uppercase;
    }

    .hero-question p { margin: 0; font-size: 1.04rem; line-height: 1.55; }

    .quick-read {
      width: min(calc(100% - 40px), var(--max));
      margin: -28px auto 0;
      position: relative;
      z-index: 2;
    }

    .quick-grid {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      overflow: hidden;
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 18px;
      box-shadow: var(--shadow);
    }

    .quick-item { padding: 21px 22px; }
    .quick-item + .quick-item { border-left: 1px solid var(--line); }
    .quick-item small { display: block; color: var(--violet-650); font-weight: 800; letter-spacing: 0.06em; text-transform: uppercase; }
    .quick-item strong { display: block; margin: 5px 0 3px; font-size: 1.02rem; }
    .quick-item span { display: block; color: var(--muted); font-size: 0.84rem; line-height: 1.45; }

    .mobile-toc {
      display: none;
      width: min(calc(100% - 26px), var(--max));
      margin: 26px auto 0;
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 13px;
    }

    .mobile-toc summary { padding: 14px 16px; cursor: pointer; font-weight: 800; }
    .mobile-links { display: grid; padding: 0 12px 12px; }
    .mobile-links a { padding: 8px 5px; text-decoration: none; }

    .layout {
      display: grid;
      grid-template-columns: 270px minmax(0, 1fr);
      gap: 48px;
      width: min(calc(100% - 40px), var(--max));
      margin: 0 auto;
      padding: 58px 0 92px;
    }

    .toc {
      position: sticky;
      top: 24px;
      align-self: start;
      max-height: calc(100vh - 48px);
      overflow: auto;
      padding: 18px;
      background: rgba(255,255,255,0.80);
      border: 1px solid var(--line);
      border-radius: 16px;
      box-shadow: 0 10px 28px rgba(36, 22, 79, 0.06);
      backdrop-filter: blur(14px);
      scrollbar-width: thin;
    }

    .toc-title {
      margin: 0 0 10px;
      color: var(--muted);
      font-size: 0.74rem;
      font-weight: 850;
      letter-spacing: 0.10em;
      text-transform: uppercase;
    }

    .toc a {
      display: grid;
      grid-template-columns: 27px 1fr;
      gap: 3px;
      margin: 2px 0;
      padding: 7px 8px;
      color: var(--muted);
      border-radius: 8px;
      font-size: 0.82rem;
      line-height: 1.28;
      text-decoration: none;
    }

    .toc a span { color: #958ca7; font-variant-numeric: tabular-nums; }
    .toc a:hover, .toc a.active { color: var(--violet-800); background: var(--violet-100); }

    main { min-width: 0; }

    .document-note {
      margin-bottom: 54px;
      padding: 18px 20px;
      color: var(--muted);
      background: var(--surface-2);
      border: 1px solid var(--line);
      border-radius: 13px;
      font-size: 0.91rem;
    }

    .doc-section {
      margin-bottom: 76px;
      scroll-margin-top: 24px;
    }

    .section-kicker {
      margin: 0 0 8px;
      color: var(--violet-650);
      font-size: 0.75rem;
      font-weight: 850;
      letter-spacing: 0.12em;
      text-transform: uppercase;
    }

    h2 {
      margin-bottom: 20px;
      color: var(--violet-950);
      font-size: clamp(1.8rem, 3.1vw, 2.55rem);
      letter-spacing: -0.038em;
    }

    h3 {
      margin: 34px 0 12px;
      color: var(--ink);
      font-size: 1.24rem;
      letter-spacing: -0.012em;
    }

    h4 { margin: 24px 0 8px; font-size: 1.03rem; }
    p { margin: 0 0 17px; }
    ul, ol { margin: 0 0 20px; padding-left: 1.35rem; }
    li + li { margin-top: 7px; }
    li::marker { color: var(--violet-650); font-weight: 800; }

    blockquote {
      margin: 24px 0;
      padding: 24px 26px;
      color: var(--violet-950);
      background: var(--violet-100);
      border: 1px solid #d6ccfa;
      border-left: 5px solid var(--violet-650);
      border-radius: 15px;
      font-family: Georgia, "Times New Roman", serif;
      font-size: clamp(1.06rem, 2vw, 1.24rem);
      line-height: 1.53;
    }

    main > blockquote:first-child {
      margin-top: 0;
      color: var(--muted);
      background: var(--surface-2);
      border-color: var(--line);
      border-left-color: var(--teal-700);
      font-family: inherit;
      font-size: 0.9rem;
    }

    blockquote p:last-child { margin-bottom: 0; }

    code {
      padding: 0.15em 0.38em;
      color: #35256d;
      background: #eeeaf8;
      border: 1px solid #dfd8ef;
      border-radius: 5px;
      font: 0.88em/1.4 "SFMono-Regular", Consolas, "Liberation Mono", monospace;
      overflow-wrap: anywhere;
    }

    .code-wrap {
      margin: 23px 0;
      overflow-x: auto;
      background: #17202e;
      border: 1px solid #2b3748;
      border-radius: 15px;
      box-shadow: 0 12px 30px rgba(23, 32, 46, 0.10);
    }

    pre { margin: 0; padding: 23px; min-width: max-content; }
    pre code { padding: 0; color: #e5eaf2; background: transparent; border: 0; font-size: 0.9rem; line-height: 1.65; overflow-wrap: normal; }

    .table-wrap {
      margin: 23px 0 28px;
      overflow-x: auto;
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 15px;
      box-shadow: 0 8px 22px rgba(36, 22, 79, 0.04);
      outline: none;
    }

    .table-wrap:focus { box-shadow: 0 0 0 3px rgba(93, 67, 188, 0.20); }

    table { width: 100%; border-collapse: collapse; font-size: 0.91rem; }
    th, td { min-width: 135px; padding: 13px 15px; border-bottom: 1px solid var(--line); text-align: left; vertical-align: top; }
    th { color: var(--violet-950); background: var(--surface-2); font-size: 0.75rem; letter-spacing: 0.045em; text-transform: uppercase; }
    tr:last-child td { border-bottom: 0; }
    tbody tr:hover { background: #fbfaff; }
    tr.priority-p0 td:first-child { color: var(--red-800); background: var(--red-100); font-weight: 900; }
    tr.priority-p1 td:first-child { color: var(--amber-800); background: var(--amber-100); font-weight: 900; }
    tr.priority-p2 td:first-child { color: var(--green-700); background: var(--green-100); font-weight: 900; }

    .checklist {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px;
      padding: 0;
      list-style: none;
    }

    .checklist li {
      display: grid;
      grid-template-columns: 22px 1fr;
      gap: 10px;
      align-items: start;
      margin: 0;
      padding: 12px 14px;
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 10px;
    }

    .checkmark {
      display: grid;
      place-items: center;
      width: 18px;
      height: 18px;
      margin-top: 3px;
      color: #fff;
      background: var(--violet-100);
      border: 1px solid #cbbff2;
      border-radius: 5px;
      font-size: 0.72rem;
      font-weight: 900;
    }

    .back-top {
      position: fixed;
      z-index: 20;
      right: 20px;
      bottom: 20px;
      display: grid;
      place-items: center;
      width: 44px;
      height: 44px;
      color: #fff;
      background: var(--violet-800);
      border: 0;
      border-radius: 50%;
      box-shadow: 0 10px 24px rgba(36, 22, 79, 0.22);
      cursor: pointer;
      opacity: 0;
      transform: translateY(12px);
      transition: opacity 160ms ease, transform 160ms ease;
      pointer-events: none;
    }

    .back-top.visible { opacity: 1; transform: translateY(0); pointer-events: auto; }

    footer {
      padding: 32px 20px 48px;
      color: var(--muted);
      border-top: 1px solid var(--line);
      text-align: center;
      font-size: 0.86rem;
    }

    footer strong { color: var(--violet-800); }

    @media (max-width: 1020px) {
      .hero-inner { grid-template-columns: 1fr; }
      .hero-question { max-width: 700px; }
      .quick-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .quick-item:nth-child(3) { border-left: 0; border-top: 1px solid var(--line); }
      .quick-item:nth-child(4) { border-top: 1px solid var(--line); }
      .layout { display: block; }
      .toc { display: none; }
      .mobile-toc { display: block; }
    }

    @media (max-width: 680px) {
      .hero-inner { width: min(calc(100% - 28px), var(--max)); padding: 52px 0 54px; }
      .quick-read { width: min(calc(100% - 26px), var(--max)); }
      .quick-grid { grid-template-columns: 1fr; }
      .quick-item + .quick-item { border-top: 1px solid var(--line); border-left: 0; }
      .layout { width: min(calc(100% - 26px), var(--max)); padding-top: 40px; }
      .doc-section { margin-bottom: 58px; }
      .checklist { grid-template-columns: 1fr; }
      blockquote { padding: 20px; }
      th, td { padding: 12px; }
      .back-top { right: 13px; bottom: 13px; }
    }

    @media (prefers-reduced-motion: reduce) {
      html { scroll-behavior: auto; }
      .back-top { transition: none; }
    }

    @media print {
      @page { margin: 1.6cm; }
      :root { --paper: #fff; --surface: #fff; }
      body { background: #fff; font-size: 10pt; }
      .reading-progress, .actions, .quick-read, .mobile-toc, .toc, .back-top { display: none !important; }
      .hero { color: #111; background: #fff; border-bottom: 2px solid var(--violet-950); }
      .hero::before, .hero::after, .hero-question { display: none; }
      .hero-inner { display: block; width: 100%; padding: 20px 0 26px; }
      .hero h1 { color: var(--violet-950); font-size: 30pt; }
      .hero-lead, .hero-meta { color: #444; }
      .eyebrow { color: var(--violet-950); background: var(--violet-100); border-color: #d6ccfa; }
      .layout { display: block; width: 100%; padding: 28px 0; }
      .doc-section { margin-bottom: 34px; }
      h2, h3 { break-after: avoid; }
      blockquote, .table-wrap, .code-wrap, .checklist li { break-inside: avoid; box-shadow: none; }
      .table-wrap { overflow: visible; }
      table { font-size: 8.4pt; }
      th, td { min-width: 0; padding: 7px; }
      a { color: inherit; }
      footer { padding-bottom: 0; }
    }
  </style>
</head>
<body>
  <a class="skip-link" href="#conteudo">Pular para o conteúdo</a>
  <div class="reading-progress" id="readingProgress" aria-hidden="true"></div>

  <header class="hero" id="topo">
    <div class="hero-inner">
      <div>
        <p class="eyebrow">Revisão estratégica · Agosto de 2026</p>
        <h1>PulseLab 2.0</h1>
        <p class="hero-lead">Proposta reformulada, arquitetura de pesquisa e MVP para produzir evidências distribuídas, comparáveis e auditáveis em oficinas de robótica educacional.</p>
        <div class="hero-meta">
          <span><strong>Base examinada:</strong> agente e contratos 1.4.0</span>
          <span><strong>Escopo:</strong> produto, método, métricas e governança</span>
          <span><strong>Status:</strong> documento de decisão</span>
        </div>
        <div class="actions">
          <a class="button primary" href="#1-sintese-executiva">Começar a leitura</a>
          <a class="button" href="#7-escopo-do-mvp">Ir ao MVP</a>
          <button class="button" type="button" id="printButton">Imprimir ou salvar em PDF</button>
        </div>
      </div>
      <aside class="hero-question" aria-label="Pergunta central do MVP">
        <small>Pergunta central do MVP</small>
        <p>É viável executar um protocolo multicêntrico de coleta em oficinas de robótica com completude, fidelidade, segurança, baixo ônus e qualidade suficientes para um estudo substantivo posterior?</p>
      </aside>
    </div>
  </header>

  <section class="quick-read" aria-label="Resumo em quatro pontos">
    <div class="quick-grid">
      <div class="quick-item"><small>Posicionamento</small><strong>Infraestrutura de pesquisa</strong><span>Não um medidor automático de aprendizagem.</span></div>
      <div class="quick-item"><small>Primeiro teste</small><strong>Viabilidade multicêntrica</strong><span>Qualidade, fidelidade, segurança e ônus.</span></div>
      <div class="quick-item"><small>MVP</small><strong>Duplas, uma atividade</strong><span>Pré, dois checkpoints, rubrica e pós.</span></div>
      <div class="quick-item"><small>Saída</small><strong>Relatório de viabilidade</strong><span>Decisão verde, amarela ou vermelha.</span></div>
    </div>
  </section>

  <details class="mobile-toc">
    <summary>Navegar pelas 16 seções</summary>
    <nav class="mobile-links" aria-label="Sumário móvel">${toc}</nav>
  </details>

  <div class="layout">
    <aside class="toc" aria-label="Sumário do documento">
      <p class="toc-title">Neste documento</p>
      <nav id="tocNav">${toc}</nav>
    </aside>

    <main id="conteudo" tabindex="-1">
${body}
    </main>
  </div>

  <button class="back-top" id="backTop" type="button" aria-label="Voltar ao topo">↑</button>

  <footer>
    <strong>PulseLab 2.0</strong> · versão HTML gerada a partir do documento de decisão em Markdown.<br>
    Este relatório não substitui protocolo aprovado, parecer ético, plano estatístico, política de privacidade ou aconselhamento jurídico.
  </footer>

  <script>
    const progress = document.getElementById("readingProgress");
    const backTop = document.getElementById("backTop");
    const printButton = document.getElementById("printButton");
    const tocLinks = [...document.querySelectorAll("#tocNav a")];
    const sections = [...document.querySelectorAll(".doc-section")];

    function updateScrollUI() {
      const available = document.documentElement.scrollHeight - window.innerHeight;
      const ratio = available > 0 ? Math.min(window.scrollY / available, 1) : 0;
      progress.style.width = (ratio * 100) + "%";
      backTop.classList.toggle("visible", window.scrollY > 700);
    }

    const observer = new IntersectionObserver((entries) => {
      const visible = entries
        .filter((entry) => entry.isIntersecting)
        .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)[0];
      if (!visible) return;
      tocLinks.forEach((link) => {
        const active = link.getAttribute("href") === "#" + visible.target.id;
        link.classList.toggle("active", active);
        if (active) link.setAttribute("aria-current", "location");
        else link.removeAttribute("aria-current");
      });
    }, { rootMargin: "-15% 0px -72% 0px" });

    sections.forEach((section) => observer.observe(section));
    window.addEventListener("scroll", updateScrollUI, { passive: true });
    backTop.addEventListener("click", () => window.scrollTo({ top: 0, behavior: "smooth" }));
    printButton.addEventListener("click", () => window.print());
    updateScrollUI();
  </script>
</body>
</html>
`;

await writeFile(outputPath, html, "utf8");
console.log(`HTML gerado: ${outputPath}`);
