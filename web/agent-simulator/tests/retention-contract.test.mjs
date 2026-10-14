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

test("Formulário final não guarda nada no navegador e apaga o que versões antigas deixaram", () => {
  const pageContent = fs.readFileSync(studentPagePath, "utf-8");
  assert.doesNotMatch(pageContent, /localStorage\.setItem|sessionStorage\.setItem/, "Nenhuma gravação em localStorage/sessionStorage");
  assert.doesNotMatch(pageContent, /saveEvent|saveSession|flushPendingEvents|syncSingleEvent/, "Nenhuma fila de eventos no navegador");
  assert.match(pageContent, /deleteLocalStore\(\)/, "Apaga o IndexedDB das versões até 2.3.x");
  assert.match(pageContent, /localStorage\.removeItem\(key\)/, "Apaga as chaves antigas de sessão");
});

test("Sessão só abre com provisionamento válido do polo (fail-closed no Bridge)", () => {
  const code = fs.readFileSync(bridgeScriptPath, "utf-8");
  const ctxIdx = code.indexOf("function Get-BridgeResearchContext");
  assert.ok(ctxIdx !== -1, "Get-BridgeResearchContext deve existir");
  const ctx = code.slice(ctxIdx, code.indexOf("\nfunction ", ctxIdx + 10));
  assert.match(ctx, /research_collection_enabled -is \[bool\]/, "Exige booleano estrito");
  assert.match(ctx, /research_authorization_version/, "Exige versão de autorização (CAAE)");
  assert.match(ctx, /"academic_research"/, "Exige finalidade academic_research");
  assert.match(ctx, /\$groupSize -lt 2 -or \$groupSize -gt 8/, "group_size entre 2 e 8");
  const startIdx = code.indexOf("function Start-BridgeSession");
  const start = code.slice(startIdx, code.indexOf("\nfunction ", startIdx + 10));
  assert.match(start, /Test-BridgeCollectionPaused/, "Turma pausada não abre sessão");
  assert.match(start, /\$ctx = Get-BridgeResearchContext[\s\S]*?if \(-not \$ctx\) \{ return \$false \}/, "Sem autorização não abre sessão");
});

test("Retenção configurável (padrão 180 dias): pulselab-bridge.ps1 possui rotina Invoke-BridgeRetentionCleanup", () => {
  assert.ok(fs.existsSync(bridgeScriptPath), "pulselab-bridge.ps1 deve existir");
  const bridgeContent = fs.readFileSync(bridgeScriptPath, "utf-8");

  assert.match(
    bridgeContent,
    /function Invoke-BridgeRetentionCleanup/,
    "Bridge deve conter a função Invoke-BridgeRetentionCleanup"
  );
  assert.match(
    bridgeContent,
    /\$MaxAgeDays\s*=\s*180/,
    "Deve usar retenção padrão de 180 dias"
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
