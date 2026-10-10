import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "../../..");
const bridgePath = path.join(repoRoot, "bridge", "pulselab-bridge.ps1");

test("Bridge Store-and-Forward: implementação de Sync-SessionSnapshotsToSupabase e trackers de sessão", () => {
  assert.ok(fs.existsSync(bridgePath), "bridge/pulselab-bridge.ps1 deve existir");
  const code = fs.readFileSync(bridgePath, "utf-8");

  // Função dedicada de sincronização de snapshot de sessões
  assert.match(
    code,
    /function\s+Sync-SessionSnapshotsToSupabase/,
    "Bridge deve implementar a função Sync-SessionSnapshotsToSupabase"
  );

  // Headers seguros e resolução idempotente
  assert.match(
    code,
    /Prefer\s*=\s*["']resolution=ignore-duplicates,return=minimal["']/,
    "Sync-SessionSnapshotsToSupabase deve usar ignore-duplicates e return=minimal"
  );
  assert.match(
    code,
    /rest\/v1\/research_bancada_sessions\?on_conflict=session_id/,
    "Endpoint de sincronização de sessão deve ser research_bancada_sessions com on_conflict=session_id"
  );

  // Trackers de sessão
  assert.match(
    code,
    /\$script:SyncedSessionsTrackerFile\s*=\s*Join-Path\s+\$DataDir\s+["']sessions_synced\.txt["']/,
    "Bridge deve rastrear sessões sincronizadas em sessions_synced.txt"
  );
  assert.match(
    code,
    /\$script:QuarantinedSessionsTrackerFile\s*=\s*Join-Path\s+\$DataDir\s+["']sessions_quarantine\.txt["']/,
    "Bridge deve registrar quarentena de sessões rejeitadas em sessions_quarantine.txt"
  );
});

test("Bridge Store-and-Forward: carregamento de credenciais operacionais de dispositivo (DPAPI / JSON)", () => {
  const code = fs.readFileSync(bridgePath, "utf-8");

  // Carregamento de credencial em device_session.json ou device_session.dat
  assert.match(
    code,
    /device_session\.json/,
    "Bridge deve verificar se há credencial local de dispositivo em device_session.json"
  );
  assert.match(
    code,
    /device_session\.dat/,
    "Bridge deve suportar credencial protegida por DPAPI em device_session.dat"
  );
  assert.match(
    code,
    /installation\.json/,
    "Bridge deve inspecionar installation.json para obter installation_id e site_id"
  );
});

test("Bridge Store-and-Forward: acionamento de sincronização em save e expurgo em reset", () => {
  const code = fs.readFileSync(bridgePath, "utf-8");

  // Chamada no loop periódico
  assert.match(
    code,
    /Sync-EventsToSupabase[\s\S]*?Sync-SessionSnapshotsToSupabase/,
    "Loop periódico deve sincronizar eventos e snapshots de sessão"
  );

  // Chamada ao salvar sessão
  const saveIdx = code.indexOf('$path -eq "/v1/sessions/save"');
  assert.ok(saveIdx !== -1, "Rota /v1/sessions/save deve existir");
  const saveBlock = code.slice(saveIdx, saveIdx + 8000);
  assert.match(
    saveBlock,
    /Sync-SessionSnapshotsToSupabase/,
    "Rota /v1/sessions/save deve invocar Sync-SessionSnapshotsToSupabase após persistência local"
  );

  // Limpeza de tracker em /v1/sessions/reset
  const resetIdx = code.indexOf('$path -eq "/v1/sessions/reset"');
  assert.ok(resetIdx !== -1, "Rota /v1/sessions/reset deve existir");
  const nextRouteIdx = code.indexOf('$path -eq "/v1/spike/metrics"', resetIdx);
  const resetBlock = code.slice(resetIdx, nextRouteIdx !== -1 ? nextRouteIdx : resetIdx + 15000);
  assert.match(
    resetBlock,
    /\$script:SyncedSessionIds\.Remove\(\$reqSessId\)/,
    "Rota /v1/sessions/reset deve purgar session_id do tracker de sessões sincronizadas"
  );
  assert.match(code, /function\s+Invoke-RemoteSessionPurge/, "Bridge deve implementar exclusão remota autenticada");
  assert.match(code, /purge_own_research_session/, "Bridge deve usar RPC restrita para retirada ética");
  assert.match(code, /sessions_withdrawn\.txt/, "Bridge deve manter tombstone persistente contra reenvio");
  assert.match(code, /withdrawals_pending\.txt/, "Bridge deve manter fila durável para retry da exclusão remota");
  assert.match(code, /Sync-PendingWithdrawals/, "Loop deve repetir retiradas remotas pendentes");
  assert.match(code, /WithdrawnSessionIds\.Contains\(\$eventSessionId\)/, "Eventos retirados nunca podem ser reenviados");
  assert.match(code, /WithdrawnSessionIds\.Contains\(\$sid\)/, "Snapshots retirados nunca podem ser reenviados");
});
