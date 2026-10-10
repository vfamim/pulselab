import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "../../..");
const publicSwPath = path.join(repoRoot, "web/agent-simulator/public/sw.js");
const distSwPath = path.join(repoRoot, "alunos/sw.js");

test("Service Worker: CACHE_NAME incrementado e não permanece em 2.0.0-test.1", () => {
  assert.ok(fs.existsSync(publicSwPath), "public/sw.js deve existir");
  const swContent = fs.readFileSync(publicSwPath, "utf-8");

  // Versão não pode permanecer 2.0.0-test.1
  assert.doesNotMatch(
    swContent,
    /2\.0\.0-test\.1/,
    "A versão do cache no Service Worker não deve permanecer como 2.0.0-test.1"
  );

  // Versão deve estar incrementada para 2.2.3
  assert.match(
    swContent,
    /CACHE_NAME\s*=\s*CACHE_PREFIX\s*\+\s*["']2\.2\.3["']/,
    "CACHE_NAME deve ser incrementado para 2.2.3"
  );

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

test("Service Worker: artefato alunos/sw.js atualizado pelo build contém versão incrementada", () => {
  if (fs.existsSync(distSwPath)) {
    const distContent = fs.readFileSync(distSwPath, "utf-8");
    assert.doesNotMatch(distContent, /2\.0\.0-test\.1/);
  }
});
