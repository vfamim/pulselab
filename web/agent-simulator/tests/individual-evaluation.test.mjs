import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  isResearchAuthorized,
  downloadSessionData,
  validateFinalTelemetry,
  validateRestoredSession,
  structuralSpikeMetrics
} from "../lib/evaluation.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "../../..");
const studentPagePath = path.join(repoRoot, "web/agent-simulator/app/student-page.jsx");

// ==============================================================================
// 1. CONFIGURAÇÃO FAIL-CLOSED E AUTORIZAÇÃO DE PESQUISA
// ==============================================================================

test("Configuração fail-closed: config ausente ou vazia não autoriza pesquisa", () => {
  assert.equal(isResearchAuthorized(null), false);
  assert.equal(isResearchAuthorized(undefined), false);
  assert.equal(isResearchAuthorized({}), false);
  assert.equal(isResearchAuthorized([]), false);
  assert.equal(isResearchAuthorized("invalid-config"), false);
});

test("Configuração fail-closed: research_collection_enabled=false rejeita pesquisa", () => {
  const cfg = {
    research_collection_enabled: false,
    research_authorization_version: "v2026.1",
    research_authorized_purposes: ["academic_research"],
    group_size: 2
  };
  assert.equal(isResearchAuthorized(cfg), false);
});

test("Configuração fail-closed: string 'true' e truthy genérico rejeitados estritamente", () => {
  const base = {
    research_authorization_version: "v2026.1",
    research_authorized_purposes: ["academic_research"],
    group_size: 2
  };

  // Strings como "true" ou "1" devem ser rejeitadas por fail-closed
  assert.equal(isResearchAuthorized({ ...base, research_collection_enabled: "true" }), false);
  assert.equal(isResearchAuthorized({ ...base, research_collection_enabled: "TRUE" }), false);
  assert.equal(isResearchAuthorized({ ...base, research_collection_enabled: 1 }), false);
  assert.equal(isResearchAuthorized({ ...base, research_collection_enabled: {} }), false);
});

test("Configuração fail-closed: autorização incompleta (versão ou finalidade inválida) rejeitada", () => {
  const validBase = {
    research_collection_enabled: true,
    group_size: 2
  };

  // Versão de autorização ausente, nula ou vazia
  assert.equal(isResearchAuthorized({ ...validBase, research_authorization_version: null, research_authorized_purposes: ["academic_research"] }), false);
  assert.equal(isResearchAuthorized({ ...validBase, research_authorization_version: "", research_authorized_purposes: ["academic_research"] }), false);
  assert.equal(isResearchAuthorized({ ...validBase, research_authorization_version: "   ", research_authorized_purposes: ["academic_research"] }), false);
  assert.equal(isResearchAuthorized({ ...validBase, research_authorization_version: 123, research_authorized_purposes: ["academic_research"] }), false);

  // Finalidades de pesquisa ausentes, vazias ou sem "academic_research"
  assert.equal(isResearchAuthorized({ ...validBase, research_authorization_version: "v2026.1", research_authorized_purposes: [] }), false);
  assert.equal(isResearchAuthorized({ ...validBase, research_authorization_version: "v2026.1", research_authorized_purposes: ["marketing"] }), false);
  assert.equal(isResearchAuthorized({ ...validBase, research_authorization_version: "v2026.1", research_authorized_purposes: "academic_research" }), false);
  assert.equal(isResearchAuthorized({ ...validBase, research_authorization_version: "v2026.1", research_authorized_purposes: null }), false);
});

test("Configuração fail-closed: group_size inválido (< 2 ou > 8 ou não inteiro) rejeitado", () => {
  const validBase = {
    research_collection_enabled: true,
    research_authorization_version: "v2026.1",
    research_authorized_purposes: ["academic_research"]
  };

  // group_size deve ser inteiro entre 2 e 8
  assert.equal(isResearchAuthorized({ ...validBase, group_size: 1 }), false);
  assert.equal(isResearchAuthorized({ ...validBase, group_size: 0 }), false);
  assert.equal(isResearchAuthorized({ ...validBase, group_size: -2 }), false);
  assert.equal(isResearchAuthorized({ ...validBase, group_size: 9 }), false);
  assert.equal(isResearchAuthorized({ ...validBase, group_size: 16 }), false);
  assert.equal(isResearchAuthorized({ ...validBase, group_size: "2" }), false);
  assert.equal(isResearchAuthorized({ ...validBase, group_size: 2.5 }), false);
  assert.equal(isResearchAuthorized({ ...validBase, group_size: null }), false);
});

test("Configuração fail-closed: autorização válida com group_size 2..8 autoriza pesquisa", () => {
  // Dupla (group_size: 2)
  assert.equal(isResearchAuthorized({
    research_collection_enabled: true,
    research_authorization_version: "v2026.1-cep",
    research_authorized_purposes: ["academic_research"],
    group_size: 2
  }), true);

  // Bancada de 4 integrantes
  assert.equal(isResearchAuthorized({
    research_collection_enabled: true,
    research_authorization_version: "v2026.1-cep",
    research_authorized_purposes: ["academic_research", "pedagogical_review"],
    group_size: 4
  }), true);

  // Bancada de 8 integrantes
  assert.equal(isResearchAuthorized({
    research_collection_enabled: true,
    research_authorization_version: "protocolo-aprovado",
    research_authorized_purposes: ["academic_research"],
    group_size: 8
  }), true);
});

// ==============================================================================
// 2. ROTA NORMAL SILENCIOSA: ZERO COMPONENTES INFANTIS
// ==============================================================================

test("Rota silenciosa de alunos: zero componentes infantis, formulários ou perguntas", () => {
  assert.ok(fs.existsSync(studentPagePath), "student-page.jsx deve existir");
  const code = fs.readFileSync(studentPagePath, "utf-8");

  // Não deve conter componentes de telas ou questionários direcionados a crianças
  assert.doesNotMatch(code, /function PreScreen/, "student-page.jsx não deve conter PreScreen");
  assert.doesNotMatch(code, /function PostScreen/, "student-page.jsx não deve conter PostScreen");
  assert.doesNotMatch(code, /function ActivityScreen/, "student-page.jsx não deve conter ActivityScreen");
  assert.doesNotMatch(code, /function ScaleQuestion/, "student-page.jsx não deve conter ScaleQuestion");
  assert.doesNotMatch(code, /function RubricQuestion/, "student-page.jsx não deve conter RubricQuestion");
  assert.doesNotMatch(code, /<form\b/, "student-page.jsx não deve conter formulários");

  // Rota normal de alunos renderiza apenas o fallback não interativo
  assert.match(
    code,
    /Oficina de robótica em andamento\. Use o aplicativo LEGO SPIKE\./,
    "Deve conter a mensagem não interativa de fallback para os alunos"
  );
  assert.match(
    code,
    /if \(!labMode\)[\s\S]*?student-app--silent[\s\S]*?Oficina de robótica em andamento/,
    "Rota normal de alunos deve retornar exclusivamente a tela silenciosa"
  );
});

// ==============================================================================
// 3. MODELO COLETIVO DE BANCADA: ZERO CAMPOS INDIVIDUAIS
// ==============================================================================

test("Modelo coletivo de bancada: zero campos individuais e ausência de memberAssents/memberExperiences", () => {
  const code = fs.readFileSync(studentPagePath, "utf-8");

  // Zero campos individuais no fluxo ou payload
  assert.doesNotMatch(code, /\bmemberAssents\b/, "Não deve conter memberAssents");
  assert.doesNotMatch(code, /\bmemberExperiences\b/, "Não deve conter memberExperiences");
  assert.doesNotMatch(code, /\bmember_index\b/, "Não deve conter member_index");
  assert.doesNotMatch(code, /\bresolveMemberExperiences\b/, "Não deve conter resolveMemberExperiences");
  assert.doesNotMatch(code, /\bisAllAssented\b/, "Não deve conter isAllAssented");
  assert.doesNotMatch(code, /\bisPostScreenReady\b/, "Não deve conter isPostScreenReady");

  // Bancada coletiva como unidade analítica
  assert.match(code, /collective_unit:\s*["']bancada["']/, "Eventos devem registrar bancada coletiva");
  assert.match(code, /group_size:\s*cfg\.group_size|group_size:\s*groupSize/, "Sessão deve registrar group_size coletivo");
});

test("Validação fail-closed de snapshot restaurado: group_size estrito 2..8 e retenção", () => {
  const validSnap = {
    sessionId: "sess-1",
    groupId: "grp-1",
    startedAt: Date.now() - 1000,
    group_size: 3
  };
  const restored = validateRestoredSession(validSnap);
  assert.ok(restored);
  assert.equal(restored.group_size, 3);
  assert.equal(restored.sessionId, "sess-1");

  // Rejeita group_size inválido (< 2 ou > 8)
  assert.equal(validateRestoredSession({ ...validSnap, group_size: 1 }), null);
  assert.equal(validateRestoredSession({ ...validSnap, group_size: 9 }), null);
  assert.equal(validateRestoredSession({ ...validSnap, group_size: "3" }), null);
  assert.equal(validateRestoredSession({ ...validSnap, group_size: null }), null);

  // Rejeita status completed ou withdrawn
  assert.equal(validateRestoredSession({ ...validSnap, status: "completed" }), null);
  assert.equal(validateRestoredSession({ ...validSnap, status: "withdrawn" }), null);
  assert.equal(validateRestoredSession({ ...validSnap, isCompleted: true }), null);

  // Rejeita Modo Livre ou expirado (> 7 dias)
  assert.equal(validateRestoredSession({ ...validSnap, isFreeMode: true }), null);
  assert.equal(validateRestoredSession({ ...validSnap, startedAt: Date.now() - 8 * 24 * 60 * 60 * 1000 }), null);
  assert.equal(validateRestoredSession({ ...validSnap, startedAt: Date.now() + 60_000 }), null);

  // Respeita maxAgeMs customizado (ex: 30 minutos)
  assert.equal(validateRestoredSession({ ...validSnap, startedAt: Date.now() - 40 * 60 * 1000 }, { maxAgeMs: 30 * 60 * 1000 }), null);
  assert.ok(validateRestoredSession({ ...validSnap, startedAt: Date.now() - 10 * 60 * 1000 }, { maxAgeMs: 30 * 60 * 1000 }));
});

test("Superfície infantil: ausência total de controles de ritmo, painéis técnicos, IDs e contadores", () => {
  const code = fs.readFileSync(studentPagePath, "utf-8");

  // Rota normal não deve expor controles tentadores
  assert.doesNotMatch(code, /<button[^>]*>[\s\S]*?(Avançar|Próxima|Finalizar|Concluir oficina|Começar atividade)/i, "Não deve expor botões de controle de fluxo");
  assert.doesNotMatch(code, /checkpoint/i, "Não deve expor checkpoints na rota infantil");

  // Não deve expor IDs ou versão no markup da rota normal
  const normalRouteMatch = code.match(/if \(!labMode\)\s*\{\s*return\s*\(\s*<main[\s\S]*?<\/main>\s*\);\s*\}/);
  assert.ok(normalRouteMatch, "Bloco if (!labMode) de renderização deve ser encontrado");
  const normalMarkup = normalRouteMatch[0];

  assert.doesNotMatch(normalMarkup, /sessionId|session_id|installation_id|client_version|protocol_version/, "Markup normal não deve renderizar IDs ou versão");
  assert.doesNotMatch(normalMarkup, /cronômetro|timer|outbox|quarentena|pendente/i, "Markup normal não deve renderizar contadores ou cronômetro");
  assert.match(normalMarkup, /Oficina pronta/, "Deve conter o estado discreto de oficina pronta");
  assert.match(normalMarkup, /Monte, programe e teste o seu robô na bancada\./, "Deve conter orientação curta e útil");

  // Descarte seguro de sessões antigas para novos grupos
  assert.match(code, /sessionStorage\.getItem\("pulselab_tab_session_id"\)/, "Deve verificar identificador de sessão da aba");
  assert.match(code, /localStorage\.removeItem\(ACTIVE_SESSION_KEY\)/, "Deve descartar chave ativa se a sessão for antiga ou de outro grupo");
});

// ==============================================================================
// 4. EXPORTAÇÃO E TELEMETRIA ESTRUTURAL DO SPIKE
// ==============================================================================

test("downloadSessionData recusa estritamente exportação no Modo Livre ou sem autorização institucional", () => {
  const dummySession = { session_id: "s1", events: [] };

  // Modo Livre -> recusa sempre
  assert.equal(downloadSessionData(dummySession, { isFreeMode: true, researchAuthorized: true }), null);
  assert.equal(downloadSessionData(dummySession, { isFreeMode: true, researchAuthorized: false }), null);

  // Sem autorização -> recusa
  assert.equal(downloadSessionData(dummySession, { isFreeMode: false, researchAuthorized: false }), null);
  assert.equal(downloadSessionData(dummySession, {}), null);
  assert.equal(downloadSessionData(dummySession), null);

  // Rejeição de compatibilidade permissiva por assentAgreed (um clique infantil não substitui autorização institucional)
  assert.equal(downloadSessionData(dummySession, { isFreeMode: false, researchAuthorized: false, assentAgreed: true }), null);
  assert.equal(downloadSessionData(dummySession, { assentAgreed: true }), null);

  // Autorizada e fora do Modo Livre -> permite
  const allowed = downloadSessionData(dummySession, { isFreeMode: false, researchAuthorized: true });
  assert.ok(allowed);
  assert.equal(allowed.session_id, "s1");
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

  // project_saved: false
  const unsavedMetrics = { project_saved: false };
  const resUnsaved = validateFinalTelemetry(unsavedMetrics, previous);
  assert.equal(resUnsaved.technicalStatus, "project_not_saved");
  assert.deepEqual(resUnsaved.effectiveTelemetry, previous);

  // objeto vazio ou nulo
  const resNull = validateFinalTelemetry(null, previous);
  assert.equal(resNull.technicalStatus, "invalid_or_unavailable");
  assert.deepEqual(resNull.effectiveTelemetry, previous);
});

test("SPIKE: apenas contagens estruturais coletivas, sem nomes ou inferência", () => {
  assert.deepEqual(structuralSpikeMetrics({
    executable_blocks: 7,
    project_saved: true,
    inferred_stage: "synthetic-inference",
    file_name: "synthetic-name.llsp3",
    code: "synthetic-code",
    uses_motor: true
  }), {
    executable_blocks: 7,
    project_saved: true,
    uses_motor: true
  });
  assert.equal(structuralSpikeMetrics(null), null);
});
