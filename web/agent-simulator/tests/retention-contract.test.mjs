import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "../../..");
const storePath = path.join(repoRoot, "web/agent-simulator/lib/student-store.js");
const studentPagePath = path.join(repoRoot, "web/agent-simulator/app/student-page.jsx");
const bridgeScriptPath = path.join(repoRoot, "bridge/pulselab-bridge.ps1");

test("Retenção absoluta 7 dias: student-store.js implementa enforceAbsoluteRetention", () => {
  assert.ok(fs.existsSync(storePath), "student-store.js deve existir");
  const storeContent = fs.readFileSync(storePath, "utf-8");

  assert.match(
    storeContent,
    /export async function enforceAbsoluteRetention\s*\(\s*maxAgeDays\s*=\s*7\s*\)/,
    "Deve exportar enforceAbsoluteRetention com padrão de 7 dias"
  );

  // Prazo absoluto sem extensão por retomada
  assert.match(
    storeContent,
    /thresholdMs\s*=\s*Date\.now\(\)\s*-\s*maxAgeDays\s*\*\s*24\s*\*\s*60\s*\*\s*60\s*\*\s*1000/,
    "Deve calcular o threshold estrito de 7 dias"
  );
  assert.match(
    storeContent,
    /sessionTime\s*=\s*new Date\s*\(\s*session\.created_at \|\| session\.startedAt \|\| session\.started_at/,
    "Deve usar a data original de criação/início da sessão, sem extensão por retomada"
  );

  // Expurgo conjunto de sessões e todos os eventos associados
  assert.match(
    storeContent,
    /belongsToExpiredSession\s*\|\|\s*isOrphanExpired/,
    "Deve expurgar eventos pertencentes a sessões expiradas ou eventos órfãos expirados"
  );

  // pruneDeliveredEvents delega para enforceAbsoluteRetention
  assert.match(
    storeContent,
    /export async function pruneDeliveredEvents[\s\S]*?enforceAbsoluteRetention/,
    "pruneDeliveredEvents deve delegar para enforceAbsoluteRetention"
  );
});

test("Retenção absoluta 7 dias: student-page.jsx executa expurgo periódico e no mount", () => {
  assert.ok(fs.existsSync(studentPagePath), "student-page.jsx deve existir");
  const pageContent = fs.readFileSync(studentPagePath, "utf-8");

  assert.match(
    pageContent,
    /enforceAbsoluteRetention\(7\)\.catch\(\(\)\s*=>\s*\{\}\)/,
    "Deve executar enforceAbsoluteRetention(7) no mount do componente"
  );
  assert.match(
    pageContent,
    /setInterval\(\(\)\s*=>\s*\{\s*enforceAbsoluteRetention\(7\)\.catch\(\(\)\s*=>\s*\{\}\);\s*\},\s*60\s*\*\s*60\s*\*\s*1000\)/,
    "Deve agendar expurgo periódico de hora em hora"
  );
});

test("Zero persistência antes do assentimento: student-page.jsx protege localStorage", () => {
  const pageContent = fs.readFileSync(studentPagePath, "utf-8");

  // getInstallationId não grava no localStorage
  const getInstallationIdMatch = pageContent.match(/function getInstallationId\([^)]*\)\s*\{[\s\S]*?\n\}/);
  assert.ok(getInstallationIdMatch, "function getInstallationId deve ser encontrada");
  assert.doesNotMatch(
    getInstallationIdMatch[0],
    /localStorage\.setItem/,
    "getInstallationId NÃO deve chamar localStorage.setItem em seu corpo"
  );

  // No mount, limpa resquício se não assentido
  assert.match(
    pageContent,
    /if \(!savedSession \|\| !isAllAssented\(savedSession\.teamSize, savedSession\.memberAssents\)\)[\s\S]*?localStorage\.removeItem\(INSTALLATION_KEY\)/,
    "Deve remover INSTALLATION_KEY no mount se não houver sessão assentida"
  );

  // Grava SOMENTE ao submeter pré-oficina com assentimento
  assert.match(
    pageContent,
    /function submitPre\(\)[\s\S]*?if\s*\(assentAgreedRef\.current\)[\s\S]*?localStorage\.setItem\(INSTALLATION_KEY,\s*installationId\)/,
    "Deve gravar INSTALLATION_KEY exclusivamente no submitPre após assentimento unânime"
  );

  // Remove em recusa (handleDeclinePre e handleDeclinePost)
  assert.match(
    pageContent,
    /async function handleDeclinePre\(\)[\s\S]*?localStorage\.removeItem\(INSTALLATION_KEY\)/,
    "Deve remover INSTALLATION_KEY em handleDeclinePre"
  );
  assert.match(
    pageContent,
    /async function resetToPre\(\)[\s\S]*?localStorage\.removeItem\(INSTALLATION_KEY\)/,
    "Deve remover INSTALLATION_KEY em resetToPre"
  );
  assert.match(
    pageContent,
    /async function prepareNextWorkshop\(\)[\s\S]*?localStorage\.removeItem\(INSTALLATION_KEY\)/,
    "Deve remover INSTALLATION_KEY em prepareNextWorkshop"
  );
});

test("Retenção absoluta 7 dias: pulselab-bridge.ps1 possui rotina Invoke-BridgeRetentionCleanup", () => {
  assert.ok(fs.existsSync(bridgeScriptPath), "pulselab-bridge.ps1 deve existir");
  const bridgeContent = fs.readFileSync(bridgeScriptPath, "utf-8");

  assert.match(
    bridgeContent,
    /function Invoke-BridgeRetentionCleanup/,
    "Bridge deve conter a função Invoke-BridgeRetentionCleanup"
  );
  assert.match(
    bridgeContent,
    /\$MaxAgeDays\s*=\s*7/,
    "Deve usar retenção padrão de 7 dias"
  );
  assert.match(
    bridgeContent,
    /events_synced\.txt/,
    "Deve expurgar registros do events_synced.txt"
  );
  assert.match(
    bridgeContent,
    /events_quarantine\.txt/,
    "Deve expurgar registros do events_quarantine.txt"
  );
  assert.match(
    bridgeContent,
    /events_quarantine\.jsonl/,
    "Deve expurgar também os payloads completos de events_quarantine.jsonl"
  );
  assert.match(
    bridgeContent,
    /active_schedule\.json/,
    "Deve considerar sessões interrompidas existentes apenas na agenda ativa"
  );
  assert.match(
    bridgeContent,
    /\$activeCreatedUtc\s*-lt\s*\$cutoffUtc/,
    "Deve expurgar agenda ativa expirada pelo prazo absoluto"
  );
  assert.match(
    bridgeContent,
    /events\.jsonl/,
    "Deve expurgar eventos de sessões expiradas de events.jsonl"
  );
});
