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

test("Bridge Security: validação de JSON e esquema mínimo em /v1/events sem tocar disco em falha", () => {
  const code = fs.readFileSync(bridgePath, "utf-8");

  // Localiza o bloco da rota /v1/events
  const eventsRouteIdx = code.indexOf('$path -eq "/v1/events"');
  assert.ok(eventsRouteIdx !== -1, "Rota /v1/events deve existir");
  const eventsBlock = code.slice(eventsRouteIdx, eventsRouteIdx + 3000);

  // Validação de JSON e campos mínimos
  assert.match(eventsBlock, /ConvertFrom-Json/, "Deve validar JSON via ConvertFrom-Json antes de persistir");
  assert.match(eventsBlock, /event_id/, "Deve exigir campo event_id");
  assert.match(eventsBlock, /session_id/, "Deve exigir campo session_id");
  assert.match(eventsBlock, /-StatusCode\s+400|StatusCode\s*=\s*400/, "Deve retornar 400 Bad Request em JSON inválido ou campos ausentes");

  // Ausência de gravação antes da validação
  const appendCallIdx = eventsBlock.indexOf("AppendAllText");
  const validationIdx = eventsBlock.indexOf("-StatusCode 400");
  assert.ok(validationIdx !== -1, "Deve conter -StatusCode 400 na validação");
  assert.ok(appendCallIdx !== -1, "Deve conter AppendAllText");
  assert.ok(validationIdx < appendCallIdx, "Guarda 400 deve ocorrer ANTES de qualquer AppendAllText em disco");
});

test("Bridge Security: validação de JSON e esquema em /v1/sessions/save sem tocar disco em falha", () => {
  const code = fs.readFileSync(bridgePath, "utf-8");

  const saveRouteIdx = code.indexOf('$path -eq "/v1/sessions/save"');
  assert.ok(saveRouteIdx !== -1, "Rota /v1/sessions/save deve existir");
  const saveBlock = code.slice(saveRouteIdx, saveRouteIdx + 3000);

  assert.match(saveBlock, /ConvertFrom-Json/, "Deve validar JSON em /v1/sessions/save");
  assert.match(saveBlock, /session_id/, "Deve exigir session_id");
  assert.match(saveBlock, /-StatusCode\s+400|StatusCode\s*=\s*400/, "Deve retornar 400 Bad Request se session_id estiver ausente ou JSON inválido");

  const writeCallIdx = saveBlock.indexOf("WriteAllText");
  const validationIdx = saveBlock.indexOf("-StatusCode 400");
  assert.ok(validationIdx !== -1, "Deve conter -StatusCode 400 na validação de save");
  assert.ok(writeCallIdx !== -1, "Deve conter WriteAllText");
  assert.ok(validationIdx < writeCallIdx, "Guarda 400 deve ocorrer ANTES de qualquer WriteAllText em disco");
});

test("Bridge Security: endpoint /v1/sessions/reset exige session_id e purga atomicamente quando não concluída", () => {
  const code = fs.readFileSync(bridgePath, "utf-8");

  const resetRouteIdx = code.indexOf('$path -eq "/v1/sessions/reset"');
  assert.ok(resetRouteIdx !== -1, "Rota /v1/sessions/reset deve existir");
  const nextRouteIdx = code.indexOf('$path -eq "/v1/spike/metrics"', resetRouteIdx);
  const resetBlock = code.slice(resetRouteIdx, nextRouteIdx !== -1 ? nextRouteIdx : resetRouteIdx + 12000);

  // Exigência explícita de session_id
  assert.match(resetBlock, /session_id\s*e\s*obrigatorio|session_id is required/, "Deve exigir session_id explicitamente");
  assert.match(resetBlock, /-StatusCode\s+400|StatusCode\s*=\s*400/, "Deve retornar 400 se session_id não for informado");

  // Preservação de sessão concluída
  assert.match(resetBlock, /status\s*=\s*"preserved"/, "Deve preservar sessão concluída quando acionado para próxima oficina");

  // Remoção atômica em caso de purga/recusa
  assert.match(resetBlock, /sessao_\$safeSessId\.json[\s\S]*Remove-Item.*\$sessFile/, "Deve remover arquivo snapshot da sessão");
  assert.match(resetBlock, /events\.tmp\./, "Deve reescrever events.jsonl atomicamente com arquivo temporário");
  assert.match(resetBlock, /catalogo_sessoes\.tmp\./, "Deve atualizar catálogo atomicamente com arquivo temporário");

  // Limpeza de trackers
  assert.match(resetBlock, /\$script:SyncedEventIds\.Remove/, "Deve remover IDs expurgados do tracker de sincronizados");
  assert.match(resetBlock, /\$script:QuarantinedEventIds\.Remove/, "Deve remover IDs expurgados do tracker de quarentena");

  // Não vazar payload da criança recusante e registrar retirada antes da limpeza.
  assert.match(resetBlock, /Register-SessionWithdrawal/, "Deve registrar tombstone durável antes do expurgo");
  assert.match(resetBlock, /expurgada localmente/, "Deve registrar expurgo sem registrar payload do estudante recusante");
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
