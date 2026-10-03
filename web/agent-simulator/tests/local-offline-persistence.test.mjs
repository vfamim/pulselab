import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  countStoredEvents,
  countStoredSessions,
  getLocalStoreSummary
} from "../lib/student-store.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "../../..");
const bridgePath = path.join(repoRoot, "bridge", "pulselab-bridge.ps1");
const studentPagePath = path.join(repoRoot, "web/agent-simulator/app/student-page.jsx");

test("Persistência local: student-store exporta funções de contagem e resumo", () => {
  assert.equal(typeof countStoredEvents, "function");
  assert.equal(typeof countStoredSessions, "function");
  assert.equal(typeof getLocalStoreSummary, "function");
});

test("Persistência local Bridge: ausência de File::Replace incompatível e variável $pid somente-leitura", () => {
  assert.ok(fs.existsSync(bridgePath), "pulselab-bridge.ps1 deve existir");
  const bridgeCode = fs.readFileSync(bridgePath, "utf-8");

  // Não deve conter chamadas quebradas a File::Replace com $null
  assert.doesNotMatch(
    bridgeCode,
    /\[System\.IO\.File\]::Replace\(/,
    "Bridge não deve usar [System.IO.File]::Replace que quebra no PowerShell 5.1"
  );

  // Deve implementar função auxiliar segura Move-BridgeAtomicFile
  assert.match(
    bridgeCode,
    /function\s+Move-BridgeAtomicFile/,
    "Bridge deve implementar Move-BridgeAtomicFile para escrita atômica robusta"
  );

  // Não deve tentar sobrescrever a variável automática reservada $pid do PowerShell
  assert.doesNotMatch(
    bridgeCode,
    /foreach\s*\(\$pid\s+in/,
    "Bridge não deve usar $pid como variável de iteração (somente-leitura no PowerShell)"
  );
});

test("Persistência local UX: student-page.jsx diferencia tela inicial, modo livre e contagem real", () => {
  assert.ok(fs.existsSync(studentPagePath), "student-page.jsx deve existir");
  const pageCode = fs.readFileSync(studentPagePath, "utf-8");

  // Modo livre deve explicar claramente que é opção ética e sem questionários
  assert.match(
    pageCode,
    /Modo Livre \(sem coleta de pesquisa\)/,
    "UI deve indicar explicitamente Modo Livre no rodapé"
  );

  // Tela inicial deve indicar aguardo do assentimento em vez de causar alarme falso
  assert.match(
    pageCode,
    /Aguardando início da bancada · Salvamento automático após assentimento/,
    "Tela inicial deve orientar que o salvamento é ativado após o assentimento"
  );

  // FinishedScreen deve receber e utilizar totalSavedCount
  assert.match(
    pageCode,
    /totalSavedCount=\{totalSavedCount\}/,
    "FinishedScreen deve receber a contagem real de registros salvos localmente"
  );
});
