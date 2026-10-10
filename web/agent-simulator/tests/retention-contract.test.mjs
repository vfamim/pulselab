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

test("Zero persistência antes da autorização: student-page.jsx protege localStorage", () => {
  const pageContent = fs.readFileSync(studentPagePath, "utf-8");

  // getInstallationId não grava no localStorage
  const getInstallationIdMatch = pageContent.match(/function getInstallationId\([^)]*\)\s*\{[\s\S]*?\n\}/);
  assert.ok(getInstallationIdMatch, "function getInstallationId deve ser encontrada");
  assert.doesNotMatch(
    getInstallationIdMatch[0],
    /localStorage\.setItem/,
    "getInstallationId NÃO deve chamar localStorage.setItem em seu corpo"
  );

  // Sem autorização válida ou config inválida, ativa Modo Livre sem apagar indiscriminadamente sessões ativas vigentes
  assert.match(
    pageContent,
    /if \(!authorized\)[\s\S]*?setIsFreeMode\(true\)[\s\S]*?return;/,
    "Deve ativar Modo Livre e retornar sem apagar indiscriminadamente ACTIVE_SESSION_KEY se a configuração não for autorizada"
  );
  const unauthBlockMatch = pageContent.match(/if \(!authorized\)[\s\S]*?return;/);
  assert.ok(unauthBlockMatch, "Bloco if (!authorized) deve ser encontrado");
  assert.doesNotMatch(
    unauthBlockMatch[0],
    /localStorage\.removeItem\(ACTIVE_SESSION_KEY\)/,
    "if (!authorized) NÃO deve apagar indiscriminadamente ACTIVE_SESSION_KEY sem decisão explícita"
  );

  // Grava SOMENTE após autorização estrita da configuração e inicialização da sessão coletiva
  assert.match(
    pageContent,
    /if \(!sessionStartedEmittedRef\.current\)[\s\S]*?localStorage\.setItem\(INSTALLATION_KEY,\s*installationId\)/,
    "Deve gravar INSTALLATION_KEY exclusivamente após autorização válida na inicialização da sessão"
  );

  // Remove em retirada/revogação (withdrawSession)
  assert.match(
    pageContent,
    /async function withdrawSession\(broadcast = true\)[\s\S]*?localStorage\.removeItem\(INSTALLATION_KEY\)/,
    "Deve remover INSTALLATION_KEY em withdrawSession"
  );
  assert.match(
    pageContent,
    /async function withdrawSession\(broadcast = true\)[\s\S]*?localStorage\.removeItem\(ACTIVE_SESSION_KEY\)/,
    "Deve remover ACTIVE_SESSION_KEY em withdrawSession"
  );
});

test("Sincronização fail-closed: student-page.jsx impede flush incondicional antes da autorização", () => {
  assert.ok(fs.existsSync(studentPagePath), "student-page.jsx deve existir");
  const pageContent = fs.readFileSync(studentPagePath, "utf-8");

  // runSync não pode executar antes de a configuração do Bridge ser resolvida nem fora do modo autorizado
  const runSyncMatch = pageContent.match(/async function runSync\(\)\s*\{[\s\S]*?\n  \}/);
  assert.ok(runSyncMatch, "Função runSync deve existir");
  const runSyncBody = runSyncMatch[0];

  assert.match(
    runSyncBody,
    /!configResolvedRef\.current/,
    "runSync não pode executar antes de a configuração do Bridge ter sido resolvida"
  );
  assert.match(
    runSyncBody,
    /!isResearchActiveRef\.current/,
    "runSync não pode executar quando pesquisa não estiver autorizada/ativa"
  );
  assert.match(
    runSyncBody,
    /isFreeModeRef\.current/,
    "runSync não pode executar quando estiver em Modo Livre"
  );
  assert.match(
    runSyncBody,
    /isWithdrawnRef\.current/,
    "runSync não pode executar após retirada/revogação da sessão"
  );

  // O useEffect de sincronização NÃO pode ter dependências vazias [] (evita flush incondicional no mount)
  assert.doesNotMatch(
    pageContent,
    /useEffect\(\(\)\s*=>\s*\{[\s\S]*?void\s+runSync\(\);[\s\S]*?\},\s*\[\]\)/,
    "useEffect de sincronização NÃO pode ter dependências vazias [] nem disparar flush incondicional no mount"
  );

  // O useEffect de sincronização deve depender de [configResolved, isResearchActive, isFreeMode]
  assert.match(
    pageContent,
    /useEffect\(\(\)\s*=>\s*\{[\s\S]*?handleOnline[\s\S]*?\},\s*\[configResolved,\s*isResearchActive,\s*isFreeMode\]\)/,
    "useEffect de sincronização deve depender estritamente de [configResolved, isResearchActive, isFreeMode]"
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
