import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "../../..");
const bridgePath = path.join(repoRoot, "runtime", "windows", "bridge", "pulselab-bridge.ps1");

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

test("Bridge Store-and-Forward: envio só no ciclo periódico, linha corrompida não trava a fila e retirada não volta", () => {
  const code = fs.readFileSync(bridgePath, "utf-8");
  assert.match(code, /Sync-EventsToSupabase[\s\S]*?Sync-SessionSnapshotsToSupabase/, "Loop periódico sincroniza eventos e snapshots");
  const loop = code.slice(code.indexOf("# 6. Loop de Atendimento Resiliente"));
  assert.doesNotMatch(loop, /Sync-EventsToSupabase|Sync-SessionSnapshotsToSupabase/, "Rotas não esperam a rede");
  const sync = code.slice(code.indexOf("function Sync-EventsToSupabase"), code.indexOf("function Sync-SessionSnapshotsToSupabase"));
  assert.match(sync, /if \(-not \$ev -or -not \$ev\.event_id\) \{ continue \}/, "Linha ilegível é pulada, não interrompe o envio");
  assert.match(sync, /Save-BridgeTextAtomic -Path \$eventsFile/, "Compactação por arquivo temporário");
  assert.match(code, /function Repair-BridgeEventsFile/, "Linhas cortadas são separadas na inicialização");
  const purge = code.slice(code.indexOf("function Remove-BridgeSessionData"));
  assert.match(purge, /\$script:SyncedSessionIds\.Remove\(\$reqSessId\)/);
  assert.match(code, /function\s+Invoke-RemoteSessionPurge/);
  assert.match(code, /purge_own_research_session/);
  assert.match(code, /sessions_withdrawn\.txt/);
  assert.match(code, /withdrawals_pending\.txt/);
  assert.match(code, /Sync-PendingWithdrawals/);
  assert.match(code, /WithdrawnSessionIds\.Contains\(\$eventSessionId\)/);
  assert.match(code, /WithdrawnSessionIds\.Contains\(\$sid\)/);
  const snap = code.slice(code.indexOf("function Sync-SessionSnapshotsToSupabase"));
  assert.doesNotMatch(snap.slice(0, 6000), /Polo-Nordeste|10000000-0000-4000-8000-000000000001|Guid\]::Empty/, "Sem identidades inventadas");
  assert.match(snap, /\$sessRecord\["ended_by"\][\s\S]*?\$sessRecord\["interrupted"\][\s\S]*?\$sessRecord\["data_quality"\]/);
});
