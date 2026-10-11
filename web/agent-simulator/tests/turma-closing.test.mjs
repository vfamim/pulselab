import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { INSTRUMENT_MANIFEST, INSTRUMENT_VERSION, PROTOCOL_VERSION } from "../lib/contracts.js";
import {
  DEFAULT_RETENTION_DAYS,
  NOT_INFORMED,
  resolveRetentionDays,
  resolveSessionContext
} from "../lib/evaluation.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const pageCode = fs.readFileSync(path.join(__dirname, "../app/student-page.jsx"), "utf-8");

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

test("Encerramento: registra resposta da bancada (ou recusa), avaliação do instrutor e fim da sessão", () => {
  assert.match(pageCode, /emitTimeline\("experience_recorded"[\s\S]*?refused: !option/);
  assert.match(pageCode, /emitTimeline\("rubric_completed"[\s\S]*?result_level: skipped \? null : assessment\.result[\s\S]*?support_level: skipped \? null : assessment\.support/);
  assert.match(pageCode, /emitTimeline\("session_completed"[\s\S]*?ended_by: "instrutor"/);
  assert.match(pageCode, /buildSnapshot\(finalTimeline, "completed"/, "Snapshot final sai como concluído");
  assert.match(pageCode, /resetBridgeSession\(closedSessionId, \{ completed: true, reason: "prepare_next" \}\)/, "Bridge preserva a sessão concluída");
  assert.match(pageCode, /beginSession\("apos_encerramento"\)/, "Próxima turma começa em seguida");
  assert.match(pageCode, /start_mode: startMode/);
  assert.match(pageCode, /context_missing: ctx\.missing/);
});

test("Snapshot carrega proveniência própria para o Bridge não preencher por padrão", () => {
  assert.match(pageCode, /protocol_version: PROTOCOL_VERSION,\s*instrument_version: INSTRUMENT_VERSION,\s*config_hash: CONFIG_HASH/);
  assert.match(pageCode, /phase: status === "completed" \? "completed" : "in_progress"/);
});
