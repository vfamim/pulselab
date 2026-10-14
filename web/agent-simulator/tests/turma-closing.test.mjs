import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { CONFIG_HASH, INSTRUMENT_MANIFEST, INSTRUMENT_VERSION, PROTOCOL_VERSION } from "../lib/contracts.js";
import {
  DEFAULT_RETENTION_DAYS,
  NOT_INFORMED,
  resolveRetentionDays,
  resolveSessionContext
} from "../lib/evaluation.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const pageCode = fs.readFileSync(path.join(__dirname, "../app/student-page.jsx"), "utf-8");
const bridgeCode = fs.readFileSync(path.join(__dirname, "../../../bridge/pulselab-bridge.ps1"), "utf-8");

test("Contexto: marcadores CONFIGURE_* e campos ausentes viram nao_informado, sem valores genéricos", () => {
  const ctx = resolveSessionContext({
    site_id: "PET",
    regional_hub: "Petrolina",
    school_code: "CONFIGURE_ESCOLA",
    workshop_code: "",
    class_code: undefined
  });
  assert.equal(ctx.site_id, "PET");
  assert.equal(ctx.regional_hub, "Petrolina");
  assert.equal(ctx.school_code, NOT_INFORMED);
  assert.equal(ctx.workshop_code, NOT_INFORMED);
  assert.equal(ctx.class_code, NOT_INFORMED);
  assert.deepEqual(ctx.missing, ["school_code", "workshop_code", "class_code"]);

  const empty = resolveSessionContext(null);
  assert.deepEqual(empty.missing, ["site_id", "regional_hub", "school_code", "workshop_code", "class_code"]);
  assert.doesNotMatch(pageCode, /"turma-geral"|"oficina-spike"|: "geral"/, "PWA não deve inventar escola, oficina ou turma");
});

test("Retenção: padrão de 180 dias, limitada a 1..365", () => {
  assert.equal(DEFAULT_RETENTION_DAYS, 180);
  assert.equal(resolveRetentionDays({}), 180);
  assert.equal(resolveRetentionDays({ retention_days: 90 }), 90);
  assert.equal(resolveRetentionDays({ retention_days: 0 }), 180);
  assert.equal(resolveRetentionDays({ retention_days: 400 }), 180);
  assert.equal(resolveRetentionDays({ retention_days: "30" }), 30);
});

test("Instrumento: itens do encerramento em rascunho, versionados e separados entre resultado e apoio", () => {
  assert.equal(INSTRUMENT_MANIFEST.status, "rascunho_pendente_validacao");
  assert.equal(INSTRUMENT_MANIFEST.unit_of_analysis, "bancada");
  assert.match(INSTRUMENT_VERSION, /rascunho/);
  assert.equal(PROTOCOL_VERSION, INSTRUMENT_MANIFEST.protocol_version);
  const { bancada, instrutor } = INSTRUMENT_MANIFEST.items;
  assert.equal(bancada.experiencia.legend, "Como foi a oficina para a sua bancada hoje?");
  assert.equal(bancada.experiencia.options.length, 4);
  assert.ok(bancada.experiencia.action_skip, "Bancada pode preferir não responder");
  assert.deepEqual(instrutor.resultado.options.map((o) => o[0]), [0, 1, 2, 3]);
  assert.deepEqual(instrutor.apoio.options.map((o) => o[0]), ["nenhum", "algum", "muito"]);
  const resultLabels = instrutor.resultado.options.map((o) => o[1]).join(" ");
  assert.doesNotMatch(resultLabels, /ajuda|apoio|autônom/i, "Resultado não pode embutir apoio");
});

test("Encerramento: formulário envia resposta da bancada (ou recusa) e avaliação para a turma que mostrou", () => {
  assert.match(pageCode, /bridgePost\("\/v1\/session\/close"/);
  assert.match(pageCode, /session_id: current\?\.session_id \|\| null/, "Envia o id da turma exibida");
  assert.match(pageCode, /refused: true/, "Bancada pode preferir não responder");
  assert.match(pageCode, /result\.status === 409/, "Turma mudou: recomeça em vez de gravar na turma errada");
});

test("Encerramento no Bridge: eventos da bancada, do instrutor e fim da sessão com motivo e qualidade", () => {
  const idx = bridgeCode.indexOf("function Close-BridgeSession");
  const block = bridgeCode.slice(idx, bridgeCode.indexOf("\nfunction ", idx + 10));
  assert.match(block, /ValidateSet\("instrutor", "tempo", "sem_encerramento"\)/);
  assert.match(block, /"experience_recorded"[\s\S]*?refused = \$refused/);
  assert.match(block, /"rubric_completed"[\s\S]*?-ParticipantRole "instructor"/);
  assert.match(block, /"session_completed"[\s\S]*?ended_by = \$EndedBy/);
  assert.match(block, /interrupted = \$interrupted/);
  assert.match(block, /data_quality = \$quality/);
  const route = bridgeCode.slice(bridgeCode.indexOf('$path -eq "/v1/session/close"'), bridgeCode.indexOf('$path -eq "/v1/session/pause"'));
  assert.match(route, /\$requestedSessId -ne \$expectedSessId[\s\S]*?StatusCode 409/, "Turma diferente da esperada: 409");
  assert.match(route, /\$expValue -lt 1 -or \$expValue -gt 4/, "Escala da bancada 1..4");
  assert.match(route, /\$resultLevel -lt 0 -or \$resultLevel -gt 3/, "Resultado 0..3");
  assert.match(route, /@\("nenhum", "algum", "muito"\)/, "Apoio nenhum/algum/muito");
});

test("Proveniência do instrumento no Bridge é a mesma do manifesto do PWA", () => {
  assert.match(bridgeCode, new RegExp(`\\$script:ProtocolVersion = "${PROTOCOL_VERSION}"`));
  assert.match(bridgeCode, new RegExp(`\\$script:InstrumentVersion = "${INSTRUMENT_VERSION}"`));
  assert.match(bridgeCode, new RegExp(`\\$script:InstrumentConfigHash = "${CONFIG_HASH}"`));
});

test("Sessão do Bridge: fecha por tempo (3 h) e por computador desligado/suspenso (20 min), e a próxima abre no primeiro programa", () => {
  assert.match(bridgeCode, /PULSELAB_SESSION_MAX_MINUTES" 180/);
  assert.match(bridgeCode, /PULSELAB_RESUME_GAP_MINUTES" 20/);
  assert.match(bridgeCode, /PULSELAB_HEARTBEAT_SECONDS" 300/);
  assert.match(bridgeCode, /Close-BridgeSession -EndedBy "tempo"/);
  assert.match(bridgeCode, /Close-BridgeSession -EndedBy "sem_encerramento" -EndedAtMs \(\[int64\]\$s\.last_alive_ms\)/);
  assert.match(bridgeCode, /Start-BridgeSession -StartMode "atividade_spike"/);
});

test("Bandeja do Windows: encerramento silencioso e passivo sem abrir o navegador", () => {
  const trayPath = path.join(__dirname, "../../../bridge/pulselab-tray.ps1");
  const tray = fs.readFileSync(trayPath, "utf-8");
  assert.match(tray, /function Close-CurrentTurma/);
  assert.match(tray, /\$itemClose\.add_Click\(\{\s*Close-CurrentTurma\s*\}\)/);
  assert.match(tray, /Invoke-TrayApi "\/v1\/session\/close" "POST"/);
  assert.doesNotMatch(tray, /\$itemClose\.add_Click\(\{\s*Open-ClosingForm\s*\}\)/);
});

test("Encerramento completo e fechamento do aplicativo (não persistente)", () => {
  const trayPath = path.join(__dirname, "../../../bridge/pulselab-tray.ps1");
  const tray = fs.readFileSync(trayPath, "utf-8");
  assert.match(bridgeCode, /\$path -eq "\/v1\/shutdown" -and \$request\.HttpMethod -eq "POST"/);
  assert.match(bridgeCode, /"\/v1\/shutdown"/);
  assert.match(bridgeCode, /\$script:ShutdownRequested = \$true/);
  assert.match(tray, /function Exit-PulseLabApp/);
  assert.match(tray, /Fechar PulseLab/);
  assert.match(tray, /Invoke-TrayApi "\/v1\/shutdown" "POST"/);
  assert.match(pageCode, /bridgePost\("\/v1\/shutdown"\)/);
  assert.match(pageCode, /window\.close\(\)/);
});


