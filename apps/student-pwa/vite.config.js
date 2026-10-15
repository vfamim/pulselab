import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.resolve(here, "../../alunos");
// Versão única do projeto: o código usa __PULSELAB_VERSION__ e o build troca pelo conteúdo de VERSION.
const VERSION_TOKEN = "__PULSELAB_VERSION__";
const version = fs.readFileSync(path.resolve(here, "../../VERSION"), "utf-8").trim();

// Arquivos de public/ são copiados sem passar pelo bundler; o service worker recebe a versão aqui.
const versionedServiceWorker = {
  name: "pulselab-versioned-sw",
  apply: "build",
  closeBundle() {
    const sw = path.join(outDir, "sw.js");
    fs.writeFileSync(sw, fs.readFileSync(sw, "utf-8").replaceAll(VERSION_TOKEN, version));
  }
};

export default defineConfig({
  base: "/alunos/",
  define: { [VERSION_TOKEN]: JSON.stringify(version) },
  plugins: [react(), versionedServiceWorker],
  build: {
    outDir,
    emptyOutDir: true
  }
});
