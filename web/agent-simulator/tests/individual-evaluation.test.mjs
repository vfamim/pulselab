import assert from "node:assert/strict";
import test from "node:test";
import {
  downloadSessionData,
  isAllAssented,
  isPostScreenReady,
  resolveMemberExperiences,
  validateFinalTelemetry,
  validateRestoredSession,
  structuralSpikeMetrics
} from "../lib/evaluation.js";

test("Assentimento ético: todos os integrantes 1..teamSize precisam assentir individualmente", () => {
  // Dupla: ambos assentiram
  assert.equal(isAllAssented(2, { 1: true, 2: true }), true);

  // Dupla: membro 2 não assentiu -> bancada inteira vai para Modo Livre
  assert.equal(isAllAssented(2, { 1: true, 2: false }), false);
  assert.equal(isAllAssented(2, { 1: true }), false);

  // Trio: membro 3 não assentiu
  assert.equal(isAllAssented(3, { 1: true, 2: true, 3: false }), false);

  // Quarteto: todos assentiram
  assert.equal(isAllAssented(4, { 1: true, 2: true, 3: true, 4: true }), true);
});

test("Assentimento ético estrito: rejeita strings como 'false', truthy genérico e tamanhos inválidos", () => {
  // Strings como "false" ou "true" não podem ser aceitas por Boolean()
  assert.equal(isAllAssented(2, { 1: true, 2: "false" }), false);
  assert.equal(isAllAssented(2, { 1: true, 2: "true" }), false);
  assert.equal(isAllAssented(2, { 1: true, 2: 1 }), false);
  assert.equal(isAllAssented(2, { 1: true, 2: {} }), false);
  assert.equal(isAllAssented(2, { 1: true, 2: null }), false);

  // teamSize deve ser estritamente inteiro entre 1 e 4
  assert.equal(isAllAssented(0, { 1: true }), false);
  assert.equal(isAllAssented(-1, {}), false);
  assert.equal(isAllAssented(5, { 1: true, 2: true, 3: true, 4: true, 5: true }), false);
  assert.equal(isAllAssented(2.5, { 1: true, 2: true }), false);
  assert.equal(isAllAssented("2", { 1: true, 2: true }), false);

  // memberAssents malformado
  assert.equal(isAllAssented(2, null), false);
  assert.equal(isAllAssented(2, undefined), false);
  assert.equal(isAllAssented(2, [true, true]), false);
});

test("Validação fail-closed de snapshot restaurado: teamSize estrito e descarte de malformados", () => {
  // Snapshot válido
  const validSnap = {
    sessionId: "sess-1",
    startedAt: Date.now(),
    screen: "activity",
    teamSize: 2,
    memberAssents: { 1: true, 2: true }
  };
  const resValid = validateRestoredSession(validSnap);
  assert.ok(resValid);
  assert.equal(resValid.allAssented, true);
  assert.equal(resValid.teamSize, 2);

  // Snapshot com teamSize inválido (ex: 5, 0, "2", negativo) -> descarta retornando null
  assert.equal(validateRestoredSession({ ...validSnap, teamSize: 5 }), null);
  assert.equal(validateRestoredSession({ ...validSnap, teamSize: 0 }), null);
  assert.equal(validateRestoredSession({ ...validSnap, teamSize: "2" }), null);
  assert.equal(validateRestoredSession({ ...validSnap, teamSize: -1 }), null);
  assert.equal(validateRestoredSession({ ...validSnap, teamSize: null }), null);

  // Snapshot com memberAssents malformado ou array -> descarta retornando null
  assert.equal(validateRestoredSession({ ...validSnap, memberAssents: [true, true] }), null);
  assert.equal(validateRestoredSession({ ...validSnap, memberAssents: "corrupted" }), null);

  // Snapshot com membro recusante -> preserva objeto mas allAssented é false
  const refusedSnap = validateRestoredSession({
    ...validSnap,
    memberAssents: { 1: true, 2: false }
  });
  assert.equal(refusedSnap, null);
});

test("downloadSessionData recusa estritamente exportação no modo livre ou sem assentimento", () => {
  const dummySession = { session_id: "s1", events: [] };

  // Modo livre ativado -> recusa
  assert.equal(downloadSessionData(dummySession, { isFreeMode: true, assentAgreed: true }), null);
  assert.equal(downloadSessionData(dummySession, { isFreeMode: true, assentAgreed: false }), null);

  // Sem assentimento acordado -> recusa
  assert.equal(downloadSessionData(dummySession, { isFreeMode: false, assentAgreed: false }), null);

  // Modo pesquisa legítimo -> permite
  const allowed = downloadSessionData(dummySession, { isFreeMode: false, assentAgreed: true });
  assert.ok(allowed);
  assert.equal(allowed.session_id, "s1");
});

test("Modo livre por recusa ética: zero questionário de pesquisa e zero persistência", () => {
  const teamSize = 2;
  const assents = { 1: true, 2: false };
  // Membro 2 recusou: resolveMemberExperiences retorna vazio para pesquisa
  const experiences = resolveMemberExperiences(teamSize, assents, [{ memberIndex: 1, rating: 5 }]);
  assert.deepEqual(experiences, []);
});

test("Avaliação individual: 1 integrante resolve com nota", () => {
  const teamSize = 1;
  const assents = { 1: true };
  const raw = [{ memberIndex: 1, rating: 5, skipped: false }];
  const exp = resolveMemberExperiences(teamSize, assents, raw);

  assert.equal(exp.length, 1);
  assert.equal(exp[0].memberIndex, 1);
  assert.equal(exp[0].rating, 5);
  assert.equal(exp[0].skipped, false);
  assert.equal(isPostScreenReady(teamSize, exp), true);
});

test("Avaliação individual: 2 integrantes com mistura de nota e recusa voluntária na resposta", () => {
  const teamSize = 2;
  const assents = { 1: true, 2: true };
  // Membro 1 deu nota 4 (escala 1..5), Membro 2 optou por pular voluntariamente
  const raw = [
    { memberIndex: 1, rating: 4, skipped: false },
    { memberIndex: 2, rating: null, skipped: true }
  ];
  const exp = resolveMemberExperiences(teamSize, assents, raw);

  assert.equal(exp.length, 2);
  assert.equal(exp[0].rating, 4);
  assert.equal(exp[1].rating, null);
  assert.equal(exp[1].skipped, true);
  assert.equal(isPostScreenReady(teamSize, exp), true);
});

test("Avaliação individual: bloqueia conclusão se algum membro está pendente (sem nota e sem skip)", () => {
  const teamSize = 3;
  const assents = { 1: true, 2: true, 3: true };
  // Membro 1 e 2 responderam, Membro 3 ainda não clicou em nada
  const raw = [
    { memberIndex: 1, rating: 3, skipped: false },
    { memberIndex: 2, rating: 5, skipped: false }
  ];
  const exp = resolveMemberExperiences(teamSize, assents, raw);

  assert.equal(exp.length, 3);
  assert.equal(exp[2].memberIndex, 3);
  assert.equal(exp[2].rating, null);
  assert.equal(exp[2].skipped, false);
  assert.equal(isPostScreenReady(teamSize, exp), false);
});

test("Avaliação individual: 4 integrantes com posições únicas e ordenadas 1..4", () => {
  const teamSize = 4;
  const assents = { 1: true, 2: true, 3: true, 4: true };
  const raw = [
    { memberIndex: 4, rating: 2, skipped: false },
    { memberIndex: 2, rating: null, skipped: true },
    { memberIndex: 1, rating: 5, skipped: false },
    { memberIndex: 3, rating: 4, skipped: false }
  ];
  const exp = resolveMemberExperiences(teamSize, assents, raw);

  assert.equal(exp.length, 4);
  assert.deepEqual(exp.map((m) => m.memberIndex), [1, 2, 3, 4]);
  assert.equal(new Set(exp.map((m) => m.memberIndex)).size, 4);
  assert.equal(isPostScreenReady(teamSize, exp), true);
});

test("Telemetria final: captura final válida substitui telemetria intermediária", () => {
  const previous = { executable_blocks: 5, uses_motor: true };
  const finalMetrics = {
    executable_blocks: 18,
    top_level_stacks: 2,
    uses_motor: true,
    uses_sensor: true,
    project_saved: true
  };

  const { effectiveTelemetry, technicalStatus } = validateFinalTelemetry(finalMetrics, previous);
  assert.equal(technicalStatus, "ok");
  assert.equal(effectiveTelemetry.executable_blocks, 18);
});

test("Telemetria final inválida: preserva última válida e registra estado técnico", () => {
  const previous = {
    executable_blocks: 12,
    top_level_stacks: 1,
    uses_motor: true,
    uses_sensor: false
  };

  // Cenário 1: project_saved: false
  const unsavedMetrics = { project_saved: false };
  const resUnsaved = validateFinalTelemetry(unsavedMetrics, previous);
  assert.equal(resUnsaved.technicalStatus, "project_not_saved");
  assert.deepEqual(resUnsaved.effectiveTelemetry, previous);
  assert.equal(resUnsaved.effectiveTelemetry.executable_blocks, 12);

  // Cenário 2: objeto vazio ou inválido
  const invalidMetrics = {};
  const resInvalid = validateFinalTelemetry(invalidMetrics, previous);
  assert.equal(resInvalid.technicalStatus, "invalid_or_unavailable");
  assert.deepEqual(resInvalid.effectiveTelemetry, previous);

  // Cenário 3: erro de conexão / null
  const resNull = validateFinalTelemetry(null, previous);
  assert.equal(resNull.technicalStatus, "invalid_or_unavailable");
  assert.deepEqual(resNull.effectiveTelemetry, previous);
});


test("Snapshot: retenção absoluta rejeita sete dias, futuro, ausência de idade e modo livre", () => {
  const valid = { sessionId: "synthetic-session", screen: "activity", startedAt: Date.now() - 1000, teamSize: 1, memberAssents: { 1: true } };
  assert.ok(validateRestoredSession(valid));
  for (const patch of [
    { startedAt: Date.now() - 7 * 24 * 60 * 60 * 1000 },
    { startedAt: Date.now() + 60_000 }, { startedAt: undefined },
    { isFreeMode: true }, { screen: "finished" }, { memberAssents: { 1: false } }
  ]) assert.equal(validateRestoredSession({ ...valid, ...patch }), null);
});


test("SPIKE: apenas contagens estruturais, sem nomes ou inferência", () => {
  assert.deepEqual(structuralSpikeMetrics({ executable_blocks: 7, project_saved: true,
    inferred_stage: "synthetic-inference", file_name: "synthetic-name.llsp3", code: "synthetic-code", uses_motor: true }),
    { executable_blocks: 7, project_saved: true, uses_motor: true });
  assert.equal(structuralSpikeMetrics(null), null);
});
