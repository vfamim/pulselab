import { expect, test } from "@playwright/test";
import fs from "node:fs";
import path from "node:path";
import { inspectVisuals, expectVisuals } from "./helpers/visual-audit.js";

// Questionário do fim da aula (rota padrão /alunos/), com o bridge simulado.
const BRIDGE = "http://127.0.0.1:43128";
const SHOTS = process.env.PULSELAB_SCREENSHOTS_DIR || "";
const json = (body, status = 200) => ({
  status,
  headers: { "Access-Control-Allow-Origin": "*", "Content-Type": "application/json" },
  body: JSON.stringify(body)
});

const Q = {
  1: "O carrinho de vocês seguiu a linha preta até o fim da pista?",
  2: "Como foi a corrida?",
  3: "No jogo de perguntas, vocês acertaram...",
  4: "Eu gostei da aula de robótica.",
  5: "Eu queria ter outra aula de robótica.",
  6: "Antes da aula, eu achava que conseguia programar um robô.",
  7: "Agora, eu acho que consigo programar um robô.",
  8: "Na minha bancada, eu consegui ajudar a montar ou programar."
};
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

async function mockBridge(context, { estado = { coleta_ativa: true, motivo: null, bancada_respondida: false }, resposta = { status: "gravado" } } = {}) {
  const posts = [];
  const state = { estado: { ...estado } };
  await context.route("**/*", (route) => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.origin === "http://127.0.0.1:4173") return route.continue();
    if (url.origin !== BRIDGE) return route.abort();
    if (request.method() === "OPTIONS") return route.fulfill(json({}));
    if (url.pathname === "/v1/questionario/estado") return route.fulfill(json(state.estado));
    if (url.pathname === "/v1/questionario/bancada" || url.pathname === "/v1/questionario/crianca") {
      const body = JSON.parse(request.postData() || "{}");
      posts.push({ rota: url.pathname, body });
      if (url.pathname.endsWith("/bancada") && resposta.status === "gravado") state.estado.bancada_respondida = true;
      return route.fulfill(json(resposta));
    }
    if (url.pathname.startsWith("/v1/session/")) return route.fulfill(json({ error: "não usado pela criança" }, 500));
    return route.fulfill(json({ error: "not found" }, 404));
  });
  return { posts, state };
}

async function shot(page, name) {
  if (!SHOTS) return;
  fs.mkdirSync(SHOTS, { recursive: true });
  await page.screenshot({ path: path.join(SHOTS, `${name}.png`) });
}

const heading = (page) => page.getByRole("heading", { level: 1 });

// Toques logo depois de a pergunta aparecer são ignorados (duplo toque): espera a trava passar.
async function answer(page, numero, label, { tap = false } = {}) {
  await expect(heading(page)).toHaveText(Q[numero]);
  await page.waitForTimeout(450);
  const button = page.getByRole("button", { name: label, exact: true });
  if (tap) await button.tap();
  else await button.click();
}

async function start(page, { tap = false } = {}) {
  await expect(heading(page)).toHaveText("Questionário do fim da aula");
  const button = page.getByRole("button", { name: "Começar" });
  if (tap) await button.tap();
  else await button.click();
}

test("fluxo completo de duas crianças: bancada uma vez, depois uma rodada por criança", async ({ context, page }) => {
  const { posts } = await mockBridge(context);
  await page.goto("/alunos/");
  await expect(page.getByAltText("Robô do PulseLab")).toBeVisible();
  await expect(page.getByText("Responda quando o instrutor avisar")).toBeVisible();
  await expect(page.getByText(/opcional/)).toBeVisible();
  await expect(page.getByText(/nome/)).toBeVisible();
  await expect(page.getByRole("button")).toHaveCount(1);
  await start(page);

  await expect(page.getByText("Pergunta da bancada: respondam juntos")).toBeVisible();
  await answer(page, 1, "Sim");
  // A escolha não aparece: a próxima tela não marca nada nem repete a resposta
  await expect(heading(page)).toHaveText(Q[2]);
  await expect(page.locator(".is-selected, [aria-pressed='true']")).toHaveCount(0);
  // O cursor continua sobre o cartão tocado antes: nenhum cartão pode ficar com aparência diferente.
  await page.waitForTimeout(450);
  const aparencias = await page.locator(".quiz-option").evaluateAll((els) => new Set(els.map((el) => {
    const s = getComputedStyle(el);
    return `${s.backgroundColor}|${s.borderColor}|${s.boxShadow}|${s.transform}`;
  })).size);
  expect(aparencias).toBe(1);
  await answer(page, 2, "Terminamos, mas não ganhamos");
  await answer(page, 3, "Metade");

  await expect(page.getByText("Pergunta só sua")).toBeVisible();
  await answer(page, 4, "Sim");
  await answer(page, 5, "Mais ou menos");
  await answer(page, 6, "Não");
  await answer(page, 7, "Sim");
  await answer(page, 8, "Mais ou menos");
  await expect(heading(page)).toHaveText("Obrigado! Chame o próximo colega.");
  await expect(page.getByAltText("Robô do PulseLab")).toBeVisible();
  await expect(page.locator("main")).not.toContainText("Mais ou menos");
  await expect(page.getByRole("button")).toHaveCount(1);

  // Próxima criança: volta para a pergunta 4 (a bancada já respondeu nesta aula)
  await page.getByRole("button", { name: "Próximo colega" }).click();
  await answer(page, 4, "Não");
  await answer(page, 5, "Sim");
  await answer(page, 6, "Mais ou menos");
  await answer(page, 7, "Mais ou menos");
  await answer(page, 8, "Sim");
  await expect(heading(page)).toHaveText("Obrigado! Chame o próximo colega.");

  expect(posts.map((p) => p.rota)).toEqual(["/v1/questionario/bancada", "/v1/questionario/crianca", "/v1/questionario/crianca"]);
  expect(posts[0].body.answers).toEqual([
    { item_id: "bancada_linha_v1", value: "sim" },
    { item_id: "bancada_corrida_v1", value: "terminamos_sem_ganhar" },
    { item_id: "bancada_quiz_v1", value: "metade" }
  ]);
  expect(posts[1].body.answers.map((a) => a.value)).toEqual(["sim", "mais_ou_menos", "nao", "sim", "mais_ou_menos"]);
  expect(posts[2].body.answers.map((a) => a.value)).toEqual(["nao", "sim", "mais_ou_menos", "mais_ou_menos", "sim"]);
  const ids = posts.map((p) => p.body.submission_id);
  for (const id of ids) expect(id).toMatch(UUID);
  expect(new Set(ids).size).toBe(3);
  // Nenhum campo além do envio e das respostas
  for (const p of posts) expect(Object.keys(p.body).sort()).toEqual(["answers", "submission_id"]);
});

test("\"Não quero responder\" em todas as telas, com o mesmo destaque das respostas", async ({ context, page }) => {
  const { posts } = await mockBridge(context);
  await page.goto("/alunos/");
  await start(page);
  for (let n = 1; n <= 8; n += 1) {
    await expect(heading(page)).toHaveText(Q[n]);
    const skip = page.getByRole("button", { name: "Não quero responder", exact: true });
    await expect(skip).toBeVisible();
    const first = await page.locator(".quiz-option").first().boundingBox();
    const box = await skip.boundingBox();
    expect(Math.abs(box.height - first.height)).toBeLessThanOrEqual(2);
    expect(Math.abs(box.width - first.width)).toBeLessThanOrEqual(2);
    const [skipFont, firstFont] = await Promise.all([
      skip.evaluate((el) => getComputedStyle(el).fontSize),
      page.locator(".quiz-option").first().evaluate((el) => getComputedStyle(el).fontSize)
    ]);
    expect(skipFont).toBe(firstFont);
    await answer(page, n, "Não quero responder");
  }
  await expect(heading(page)).toHaveText("Obrigado! Chame o próximo colega.");
  expect(posts).toHaveLength(2);
  expect(posts[0].body.answers.every((a) => a.value === "recusou")).toBe(true);
  expect(posts[1].body.answers.every((a) => a.value === "recusou")).toBe(true);
  expect(posts[1].body.answers).toHaveLength(5);
});

test("bancada já respondida nesta aula: pula direto para as perguntas individuais", async ({ context, page }) => {
  const { posts } = await mockBridge(context, { estado: { coleta_ativa: true, motivo: null, bancada_respondida: true } });
  await page.goto("/alunos/");
  await start(page);
  await expect(heading(page)).toHaveText(Q[4]);
  await expect(page.getByText("Pergunta só sua")).toBeVisible();
  await expect(page.getByText("Pergunta 1 de 5")).toBeVisible();
  for (const n of [4, 5, 6, 7, 8]) await answer(page, n, "Sim");
  await expect(heading(page)).toHaveText("Obrigado! Chame o próximo colega.");
  expect(posts.map((p) => p.rota)).toEqual(["/v1/questionario/crianca"]);
});

test("Modo Livre: a página só agradece e não mostra perguntas", async ({ context, page }) => {
  const { posts } = await mockBridge(context, { estado: { coleta_ativa: false, motivo: "modo_livre", bancada_respondida: false } });
  await page.goto("/alunos/");
  await expect(heading(page)).toHaveText("Obrigado!");
  await expect(page.getByText("Hoje não há questionário neste computador.")).toBeVisible();
  await expect(page.getByRole("button")).toHaveCount(0);
  await shot(page, "05-modo-livre");
  expect(posts).toHaveLength(0);
});

test("aula pausada no meio das respostas: o bridge não grava e a página agradece", async ({ context, page }) => {
  const { posts } = await mockBridge(context, { resposta: { status: "nao_gravado", motivo: "pausado" } });
  await page.goto("/alunos/");
  await start(page);
  await answer(page, 1, "Não");
  await answer(page, 2, "Ganhamos");
  await answer(page, 3, "Quase todas");
  await expect(heading(page)).toHaveText("Obrigado!");
  await expect(page.getByText("Hoje não há questionário neste computador.")).toBeVisible();
  expect(posts).toHaveLength(1);
});

test("bridge fora do ar: pede para avisar o instrutor e tenta de novo", async ({ context, page }) => {
  await context.route("**/*", (route) => {
    const url = new URL(route.request().url());
    return url.origin === "http://127.0.0.1:4173" ? route.continue() : route.abort();
  });
  await page.goto("/alunos/");
  await expect(heading(page)).toHaveText("O questionário não abriu");
  await expect(page.getByRole("button", { name: "Tentar de novo" })).toBeVisible();
});

const telas = [
  { size: [1024, 768] },
  { size: [1280, 720] },
  { size: [1366, 768] },
  { size: [800, 1280], touch: true }
];

for (const { size: [width, height], touch } of telas) {
  test.describe(`${width}x${height}${touch ? " (toque)" : ""}`, () => {
    if (touch) test.use({ hasTouch: true, isMobile: false });
    test(`auditoria visual: contraste AA, alvos de toque e tudo visível sem rolar`, async ({ context, page }) => {
      await page.setViewportSize({ width, height });
      await mockBridge(context);
      await page.goto("/alunos/");
      const nome = `${width}x${height}`;
      const audit = async (estado) => {
        const report = await inspectVisuals(page);
        expectVisuals(report, `${estado} ${nome}`);
        expect(report.targets.filter((t) => t.width < 48 || t.height < 48), `${estado}: alvos de 48 px`).toEqual([]);
        const fora = await page.evaluate(() => [...document.querySelectorAll("main button")].filter((b) => b.getBoundingClientRect().bottom > innerHeight).length);
        expect(fora, `${estado}: botões abaixo da dobra`).toBe(0);
      };
      await expect(heading(page)).toHaveText("Questionário do fim da aula");
      await audit("entrada");
      await shot(page, `01-entrada-${nome}`);
      await start(page, { tap: touch });
      await expect(heading(page)).toHaveText(Q[1]);
      await audit("pergunta 1 (bancada)");
      await shot(page, `02-bancada-${nome}`);
      await answer(page, 1, "Em parte", { tap: touch });
      await expect(heading(page)).toHaveText(Q[2]);
      await audit("pergunta 2 (cinco cartões)");
      await shot(page, `02b-bancada-cinco-opcoes-${nome}`);
      await answer(page, 2, "Ganhamos", { tap: touch });
      await answer(page, 3, "Poucas", { tap: touch });
      await expect(heading(page)).toHaveText(Q[4]);
      await audit("pergunta 4 (individual)");
      await shot(page, `03-individual-${nome}`);
      for (const n of [4, 5, 6, 7, 8]) await answer(page, n, "Mais ou menos", { tap: touch });
      await expect(heading(page)).toHaveText("Obrigado! Chame o próximo colega.");
      await audit("fim");
      await shot(page, `04-fim-${nome}`);
    });
  });
}
