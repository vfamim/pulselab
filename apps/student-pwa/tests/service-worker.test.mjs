import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "../../..");
const publicSwPath = path.join(repoRoot, "apps/student-pwa/public/sw.js");
const distSwPath = path.join(repoRoot, "alunos/sw.js");

test("Service Worker: CACHE_NAME vem da versão canônica no build", () => {
  assert.ok(fs.existsSync(publicSwPath), "public/sw.js deve existir");
  const swContent = fs.readFileSync(publicSwPath, "utf-8");
  // A fonte usa o marcador; vite.config.js troca pelo conteúdo de VERSION ao gerar alunos/sw.js.
  assert.match(swContent, /CACHE_NAME\s*=\s*CACHE_PREFIX\s*\+\s*"__PULSELAB_VERSION__"/);
  assert.doesNotMatch(swContent, /CACHE_PREFIX\s*\+\s*"\d+\.\d+\.\d+"/, "sem versão escrita à mão");
});

test("Service Worker: instalação e ativação removem caches anteriores e precacheiam bundle atual", () => {
  const swContent = fs.readFileSync(publicSwPath, "utf-8");

  // Instalação remove caches antigos
  assert.match(
    swContent,
    /self\.addEventListener\s*\(\s*["']install["'][\s\S]*?caches\.delete/m,
    "Evento install deve remover versões antigas de cache"
  );

  // Ativação também garante expurgo de caches anteriores
  assert.match(
    swContent,
    /self\.addEventListener\s*\(\s*["']activate["'][\s\S]*?caches\.delete/m,
    "Evento activate deve remover versões antigas de cache"
  );

  // Precacheia shell e assets do index.html
  assert.match(
    swContent,
    /fetch\s*\(\s*["']\/alunos\/index\.html["']\s*,\s*\{\s*cache:\s*["']reload["']\s*\}\s*\)/,
    "Deve buscar index.html com reload para extrair assets do bundle atual"
  );
  assert.match(
    swContent,
    /html\.matchAll\(\/\(\?:src\|href\)="\(.*?\)"\/g\)/,
    "Deve extrair bundles de assets gerados pelo build"
  );
});

test("Service Worker: alunos/sw.js gerado pelo build traz a versão canônica", () => {
  if (!fs.existsSync(distSwPath)) return;
  const canonical = fs.readFileSync(path.join(repoRoot, "VERSION"), "utf-8").trim();
  const distContent = fs.readFileSync(distSwPath, "utf-8");
  assert.ok(distContent.includes(`CACHE_PREFIX + "${canonical}"`), `alunos/sw.js deve usar ${canonical}; rode npm run build`);
  assert.ok(!distContent.includes("__PULSELAB_VERSION__"), "marcador não substituído no build");
});
