import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "../../..");
const bridgePath = path.join(repoRoot, "bridge", "pulselab-bridge.ps1");

test("Bridge Security: guards de Content-Length e leitura limitada de corpo a 5MB", () => {
  assert.ok(fs.existsSync(bridgePath), "bridge/pulselab-bridge.ps1 deve existir");
  const code = fs.readFileSync(bridgePath, "utf-8");

  // Rejeição estrita de ContentLength64 < 0
  assert.match(
    code,
    /\$request\.ContentLength64\s*-lt\s*0/,
    "Deve rejeitar requisições com ContentLength64 < 0 (Length Required)"
  );
  assert.match(code, /\$response\.StatusCode\s*=\s*411/, "Deve retornar 411 para ContentLength64 < 0");

  // Limite estrito de 5MB
  assert.match(
    code,
    /\$request\.ContentLength64\s*-gt\s*5242880/,
    "Deve rejeitar requisições maiores que 5MB (5242880 bytes)"
  );
  assert.match(code, /\$response\.StatusCode\s*=\s*413/, "Deve retornar 413 para corpo excessivo");

  // Leitor incremental limitado (Read-BoundedRequestBody)
  assert.match(
    code,
    /function\s+Read-BoundedRequestBody/,
    "Deve implementar função de leitura incremental delimitada"
  );
  assert.match(
    code,
    /\$stream\.Read\(\$buffer,\s*0,\s*\$buffer\.Length\)/,
    "Deve ler em buffer incrementalmente sem ReadToEnd irrestrito"
  );
  assert.match(
    code,
    /if\s*\(\$totalRead\s*-gt\s*\$MaxBytes\)/,
    "Deve interromper e abortar com 413 se total lido exceder o limite"
  );
});

test("Bridge Security: /v1/session/close valida JSON, turma e escala antes de gravar qualquer coisa", () => {
  const code = fs.readFileSync(bridgePath, "utf-8");
  const start = code.indexOf('$path -eq "/v1/session/close"');
  assert.ok(start !== -1, "Rota /v1/session/close deve existir");
  const block = code.slice(start, code.indexOf('$path -eq "/v1/session/pause"', start));
  assert.match(block, /Read-BoundedRequestBody -Request \$request -MaxBytes 65536/);
  assert.match(block, /ConvertFrom-Json/);
  const closeIdx = block.indexOf("Close-BridgeSession");
  for (const guard of ["-StatusCode 400", "-StatusCode 409"]) {
    const idx = block.indexOf(guard);
    assert.ok(idx !== -1 && idx < closeIdx, `${guard} deve vir antes de gravar`);
  }
});

test("Bridge Security: Não registrar esta turma apaga com tombstone antes de qualquer arquivo", () => {
  const code = fs.readFileSync(bridgePath, "utf-8");
  const idx = code.indexOf("function Remove-BridgeSessionData");
  assert.ok(idx !== -1, "Remove-BridgeSessionData deve existir");
  const block = code.slice(idx, code.indexOf("\nfunction ", idx + 10));
  const tombstone = block.indexOf("Register-SessionWithdrawal");
  assert.ok(tombstone !== -1 && tombstone < block.indexOf("Remove-Item"), "Tombstone durável antes do expurgo");
  assert.match(block, /events\.tmp\./, "Reescreve events.jsonl com arquivo temporário");
  assert.match(block, /catalogo_sessoes\.tmp\./, "Atualiza catálogo com arquivo temporário");
  assert.match(block, /\$script:SyncedEventIds\.Remove/);
  assert.match(block, /\$script:QuarantinedEventIds\.Remove/);
  assert.match(block, /expurgada localmente/);
  const pause = code.slice(code.indexOf("function Suspend-BridgeCollection"));
  assert.match(pause, /Remove-BridgeSessionData -SessionId \$sessionId -Reason "nao_registrar_turma"/);
});

test("Bridge Security: rotas da página aberta durante a aula não existem mais", () => {
  const code = fs.readFileSync(bridgePath, "utf-8");
  for (const route of ["/v1/events", "/v1/sessions/save", "/v1/sessions/reset", "/v1/alert", "/v1/spike/metrics", "checkpoints"]) {
    assert.ok(!code.includes(`"${route}`) && !code.includes(`/${route}/`), `Rota antiga ${route} deve ter sido removida`);
  }
  assert.doesNotMatch(code, /pulselab-toast|Show-NativeCheckpointAlert/, "Sem alertas na tela durante a aula");
});

test("Bridge Security: rota /v1/config expõe explicitamente campos de autorização fail-closed", () => {
  const code = fs.readFileSync(bridgePath, "utf-8");

  const configRouteIdx = code.indexOf('$path -eq "/config" -or $path -eq "/v1/config"');
  assert.ok(configRouteIdx !== -1, "Rota /v1/config deve existir");
  const configBlock = code.slice(configRouteIdx, configRouteIdx + 2500);

  assert.match(
    configBlock,
    /research_collection_enabled\s*=\s*\$false/,
    "Deve definir research_collection_enabled como $false por padrão"
  );
  assert.match(
    configBlock,
    /research_authorization_version\s*=\s*\$null/,
    "Deve definir research_authorization_version como $null por padrão"
  );
  assert.match(
    configBlock,
    /research_authorized_purposes\s*=\s*@\(\)/,
    "Deve definir research_authorized_purposes como array vazio por padrão"
  );
  assert.match(
    configBlock,
    /\$publicConfig\.research_collection_enabled\s*=\s*\$cfg\.research_collection_enabled/,
    "Deve repassar research_collection_enabled do arquivo de configuração"
  );
  assert.match(
    configBlock,
    /\$publicConfig\.research_authorization_version\s*=\s*\$cfg\.research_authorization_version/,
    "Deve repassar research_authorization_version do arquivo de configuração"
  );
  assert.match(
    configBlock,
    /\$publicConfig\.research_authorized_purposes\s*=\s*\$cfg\.research_authorized_purposes/,
    "Deve repassar research_authorized_purposes do arquivo de configuração"
  );
});
