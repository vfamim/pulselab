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
const bridgeCode = fs.readFileSync(path.join(__dirname, "../../../runtime/windows/bridge/pulselab-bridge.ps1"), "utf-8");

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
  assert.match(INSTRUMENT_VERSION, /^bancada-\d+\.\d+\.\d+/);
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

test("Encerramento: só em ?encerrar=1, encerra direto sem formulário e envia a turma certa", () => {
  assert.match(pageCode, /params\.get\("encerrar"\) === "1"/, "Encerramento pela página só com ?encerrar=1");
  assert.match(pageCode, /return <Questionario \/>;/, "Rota padrão mostra o questionário do fim da aula");
  assert.match(pageCode, /bridgePost\("\/v1\/session\/close"/);
  assert.match(pageCode, /session_id: current\?\.session_id \|\| null/, "Envia o id da turma exibida");
  assert.doesNotMatch(pageCode, /answerBancada|step === "bancada"|step === "instrutor"/, "Zero questionários de alunos ou instrutor no PC");
  assert.match(pageCode, /result\.status === 409/, "Turma mudou: recomeça em vez de gravar na turma errada");
});

test("Encerramento no Bridge: eventos da bancada, do instrutor e fim da sessão com motivo e qualidade", () => {
  const idx = bridgeCode.indexOf("function Close-BridgeSession");
  const block = bridgeCode.slice(idx, bridgeCode.indexOf("\nfunction ", idx + 10));
  assert.match(block, /ValidateSet\("instrutor", "tempo", "sem_encerramento", "inatividade"\)/);
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

test("Sessão do Bridge: fecha por inatividade (40 min sem programa salvo no SPIKE) e espera o próximo programa", () => {
  assert.match(bridgeCode, /PULSELAB_SESSION_IDLE_MINUTES" 40/);
  assert.match(bridgeCode, /Add-Member -NotePropertyName last_program_ms/, "Nova versão salva zera o relógio");
  assert.match(bridgeCode, /\[Math\]::Max\(\[int64\]\$Session\.started_at_ms, \[int64\]\$Session\.last_program_ms\)/, "Sem versão salva, conta do início");
  assert.match(bridgeCode, /Close-BridgeSession -EndedBy "inatividade" -EndedAtMs \(Get-BridgeLastActivityMs /);
});

test("Bandeja do Windows: encerramento silencioso, sem abrir formulário de encerramento no navegador", () => {
  const trayPath = path.join(__dirname, "../../../runtime/windows/bridge/pulselab-tray.ps1");
  const tray = fs.readFileSync(trayPath, "utf-8");
  assert.match(tray, /function Close-CurrentTurma/);
  assert.match(tray, /\$itemClose\.add_Click\(\{\s*Close-CurrentTurma\s*\}\)/);
  assert.match(tray, /Invoke-TrayApi "\/v1\/session\/close" "POST"/);
  assert.doesNotMatch(tray, /\$itemClose\.add_Click\(\{\s*Open-ClosingForm\s*\}\)/);
});

test("Encerrar turma mantém o PulseLab ligado; desligar só por \"Fechar PulseLab\"", () => {
  const trayPath = path.join(__dirname, "../../../runtime/windows/bridge/pulselab-tray.ps1");
  const tray = fs.readFileSync(trayPath, "utf-8");
  assert.match(bridgeCode, /\$path -eq "\/v1\/shutdown" -and \$request\.HttpMethod -eq "POST"/);
  assert.match(bridgeCode, /\$script:ShutdownRequested = \$true/);
  assert.doesNotMatch(bridgeCode, /msedge/, "O bridge não encerra o navegador do usuário");
  assert.match(tray, /\$itemExit\.add_Click\(\{[\s\S]*?Exit-PulseLabApp/);
  const closeTurma = tray.slice(tray.indexOf("function Close-CurrentTurma"), tray.indexOf("function Restart-PulseLab"));
  assert.doesNotMatch(closeTurma, /Exit-PulseLabApp/, "Encerrar turma não desliga o PulseLab");
  assert.match(closeTurma, /Não foi possível encerrar a turma agora/, "Falha ao encerrar é mostrada ao instrutor");
  assert.doesNotMatch(tray, /msedge/);
  // Sinal que sobrou de um desligamento anterior não pode derrubar a bandeja na partida seguinte.
  assert.match(tray, /Remove-Item -LiteralPath \$script:SignalFile[^\n]*\r?\n\r?\n\$timer = New-Object/);
  assert.match(tray, /if \(-not \$script:Exiting\) \{ \[System\.Windows\.Forms\.Application\]::Run\(\) \}/);
  assert.doesNotMatch(pageCode, /\/v1\/shutdown/, "A página não desliga o PulseLab ao encerrar a turma");
  assert.match(pageCode, /A próxima turma começará automaticamente/);
});
