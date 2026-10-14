import { expect, test } from "@playwright/test";
import { inspectVisuals, expectVisuals } from "./helpers/visual-audit.js";

// Desde a 2.4.0 a página só abre pela bandeja ("Encerrar turma...") e registra o encerramento no Bridge.
const BRIDGE = "http://127.0.0.1:43128";
const SESSION_ID = "11111111-2222-4333-8444-555555555555";
const json = (body, status = 200) => ({
  status,
  headers: { "Access-Control-Allow-Origin": "*", "Content-Type": "application/json" },
  body: JSON.stringify(body)
});

async function mockBridge(context, { current, closeStatus = 200 } = {}) {
  const posts = [];
  await context.route("**/*", (route) => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.origin === "http://127.0.0.1:4173") return route.continue();
    if (url.origin !== BRIDGE) return route.abort();
    if (request.method() === "OPTIONS") return route.fulfill(json({}));
    if (url.pathname === "/v1/session/current") return route.fulfill(json(current));
    if (url.pathname === "/v1/session/close") {
      posts.push(JSON.parse(request.postData() || "{}"));
      return route.fulfill(json(closeStatus === 200 ? { status: "closed", session_id: SESSION_ID } : { error: "Conflict" }, closeStatus));
    }
    return route.fulfill(json({ error: "not found" }, 404));
  });
  return posts;
}

const activeSession = { research_active: true, paused: false, active: true, session_id: SESSION_ID, started_at: "2026-10-14T12:00:00.000Z", elapsed_min: 80 };

test("encerramento: bancada responde, instrutor avalia e o Bridge recebe a turma certa", async ({ context, page }) => {
  const posts = await mockBridge(context, { current: activeSession });
  await page.goto("/alunos/");
  await expect(page.getByRole("heading", { name: "Encerrar a turma desta bancada?" })).toBeVisible();
  await expectVisuals(await inspectVisuals(page), "confirmar");
  await page.getByRole("button", { name: "Encerrar turma" }).click();

  await expect(page.getByRole("heading", { name: "Como foi a oficina para a sua bancada hoje?" })).toBeVisible();
  await expectVisuals(await inspectVisuals(page), "bancada");
  await page.getByRole("button", { name: /Gostamos/ }).click();

  await expect(page.getByRole("heading", { name: "Como foi esta bancada?" })).toBeVisible();
  const register = page.getByRole("button", { name: "Registrar" });
  await expect(register).toBeDisabled();
  await page.getByRole("button", { name: "Concluiu a missão" }).click();
  await page.getByRole("button", { name: "Algum" }).click();
  await register.click();

  await expect(page.getByRole("heading", { name: "Turma encerrada" })).toBeVisible();
  expect(posts).toEqual([{
    session_id: SESSION_ID,
    experience: { value: 3, label: "Gostamos", refused: false },
    rubric: { skipped: false, result_level: 2, support_level: "algum" }
  }]);
});

test("encerramento: bancada pode preferir não responder e instrutor pode pular", async ({ context, page }) => {
  const posts = await mockBridge(context, { current: activeSession });
  await page.goto("/alunos/");
  await page.getByRole("button", { name: "Encerrar turma" }).click();
  await page.getByRole("button", { name: "Preferimos não responder" }).click();
  await page.getByRole("button", { name: "Pular avaliação" }).click();
  await expect(page.getByRole("heading", { name: "Turma encerrada" })).toBeVisible();
  expect(posts[0]).toEqual({ session_id: SESSION_ID, experience: { value: null, label: null, refused: true }, rubric: { skipped: true } });
});

test("turma mudou enquanto o formulário estava aberto: recomeça em vez de gravar na turma errada", async ({ context, page }) => {
  const posts = await mockBridge(context, { current: activeSession, closeStatus: 409 });
  await page.goto("/alunos/");
  await page.getByRole("button", { name: "Encerrar turma" }).click();
  await page.getByRole("button", { name: /Adoramos/ }).click();
  await page.getByRole("button", { name: "Pular avaliação" }).click();
  await expect(page.getByRole("heading", { name: "Encerrar a turma desta bancada?" })).toBeVisible();
  await expect(page.getByText("A turma deste computador mudou")).toBeVisible();
  expect(posts).toHaveLength(1);
});

test("sem coleta de pesquisa (Modo Livre) permite encerramento, e turma pausada nao exibe botoes", async ({ context, page }) => {
  await mockBridge(context, { current: { research_active: false, paused: false, active: false, session_id: null } });
  await page.goto("/alunos/");
  await expect(page.getByRole("heading", { name: "Encerrar oficina (Modo Livre)?" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Encerrar turma" })).toBeVisible();

  await context.unrouteAll({ behavior: "ignoreErrors" });
  await mockBridge(context, { current: { research_active: true, paused: true, active: false, session_id: null } });
  await page.reload();
  await expect(page.getByRole("heading", { name: "Esta turma não está sendo registrada" })).toBeVisible();
  await expect(page.getByRole("button")).toHaveCount(0);
});

test("Bridge fora do ar: orienta abrir de novo pela bandeja", async ({ context, page }) => {
  await context.route("**/*", (route) => {
    const url = new URL(route.request().url());
    return url.origin === "http://127.0.0.1:4173" ? route.continue() : route.abort();
  });
  await page.goto("/alunos/");
  await expect(page.getByRole("heading", { name: "O PulseLab não está respondendo" })).toBeVisible();
});

test("dados de versões antigas guardados no navegador são apagados ao abrir", async ({ context, page }) => {
  await mockBridge(context, { current: activeSession });
  await page.goto("/alunos/");
  await page.evaluate(() => new Promise((resolve) => {
    localStorage.setItem("pulselab_student_active_session_v1", "{}");
    const req = indexedDB.open("pulselab-student-runner", 1);
    req.onupgradeneeded = () => req.result.createObjectStore("events", { keyPath: "event_id" });
    req.onsuccess = () => { req.result.close(); resolve(); };
  }));
  await page.reload();
  await expect(page.getByRole("heading", { name: "Encerrar a turma desta bancada?" })).toBeVisible();
  await expect.poll(() => page.evaluate(async () => {
    const dbs = await indexedDB.databases();
    return { legacyKey: localStorage.getItem("pulselab_student_active_session_v1"), hasDb: dbs.some((d) => d.name === "pulselab-student-runner") };
  })).toEqual({ legacyKey: null, hasDb: false });
});
