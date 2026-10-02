import { expect, test } from "@playwright/test";

async function prepare(page, size = 2) {
  await page.goto("/alunos/");
  await page
    .getByRole("button", { name: "Preencher contexto fictício" })
    .click();
  await page.getByLabel("Integrantes na bancada").selectOption(String(size));
  await page.getByLabel("Estou testando com dados fictícios").check();
  await page.getByRole("button", { name: "Preparar convite" }).click();
}
async function accept(page, size = 2) {
  for (let i = 0; i < size; i++)
    await page
      .getByLabel(
        "Participante " + String.fromCharCode(65 + i) + " quer participar",
      )
      .check();
  await page
    .getByRole("button", { name: "Todos aceitaram: começar registros" })
    .click();
  await expect(
    page.getByRole("heading", { name: "Antes de começar", exact: true }),
  ).toBeVisible();
}
async function answer(page, skip = false) {
  await expect(page.locator(".pilot-question").first()).toBeVisible();
  for (const question of await page.locator(".pilot-question").all()) {
    await (
      skip
        ? question.getByRole("button", {
            name: "Prefiro não responder",
            exact: true,
          })
        : question.locator(".pilot-options button").first()
    ).click();
  }
  await page.getByRole("button", { name: "Salvar e continuar" }).click();
  // Wait for the durable transaction before testing a reload/offline transition.
  await expect(
    page.getByRole("button", { name: "Salvar e continuar" }),
  ).toHaveCount(0);
}
async function stored(page) {
  return page.evaluate(
    () =>
      new Promise((resolve, reject) => {
        const request = indexedDB.open("pulselab-test-bancada-v2", 1);
        request.onsuccess = () => {
          const db = request.result;
          const tx = db.transaction("sessions", "readonly");
          const rows = tx.objectStore("sessions").getAll();
          rows.onsuccess = () => resolve(rows.result);
          tx.oncomplete = () => db.close();
        };
        request.onerror = () => reject(request.error);
      }),
  );
}
async function checkpoint(page, mark) {
  await page.getByText("Controles do teste: abrir um check-in agora").click();
  await page
    .getByRole("button", { name: "Abrir check-in " + mark, exact: true })
    .click();
  await answer(page);
}
async function finish(page) {
  await page
    .getByRole("button", { name: "Encerrar atividade", exact: true })
    .click();
  await answer(page);
  await page.getByLabel("Execuções bem-sucedidas").selectOption("2");
  await page.getByLabel("Explicação da bancada").selectOption("2");
  await page.getByLabel("Intervenções do instrutor", { exact: true }).fill("3");
  await page.getByLabel("Minutos de preparação").fill("5");
  await page.getByLabel("Principal dificuldade").selectOption("sensor");
  await page
    .getByLabel("Devolutiva e próxima ação")
    .selectOption("repeat_sensor");
  await page.getByRole("button", { name: "Concluir com devolutiva" }).click();
  await expect(
    page.getByRole("heading", { name: "Oficina concluída", exact: true }),
  ).toBeVisible();
}

test("a second tab cannot overwrite the active session", async ({
  page,
  context,
}) => {
  await prepare(page);
  await accept(page);
  await answer(page);
  const second = await context.newPage();
  await second.goto("/alunos/");
  await expect(
    second.getByRole("heading", { name: "Uma bancada já está aberta" }),
  ).toBeVisible();
  await expect(
    second.getByRole("button", { name: "Abrir sessão", exact: true }),
  ).toHaveCount(0);
  expect(await stored(page)).toHaveLength(1);
  await second.close();
});

test("scheduled checkpoints preserve elapsed activity time", async ({
  page,
}) => {
  await prepare(page);
  await accept(page);
  await answer(page);
  await page.clock.install();
  await page.clock.fastForward(20 * 60000);
  await expect(
    page.getByText("Check-in de 20 minutos", { exact: true }),
  ).toBeVisible();
  await answer(page);
  await page.clock.fastForward(20 * 60000);
  await expect(
    page.getByText("Check-in de 40 minutos", { exact: true }),
  ).toBeVisible();
  await answer(page);
  const [s] = await stored(page);
  const prompts = s.events.filter(
    (e) => e.event_type === "checkpoint_prompted",
  );
  expect(prompts.map((e) => e.details.trigger)).toEqual([
    "scheduled",
    "scheduled",
  ]);
  expect(prompts[0].elapsed_ms).toBeGreaterThanOrEqual(20 * 60000);
  expect(prompts[1].elapsed_ms).toBeGreaterThanOrEqual(40 * 60000);
});

test("refusal starts no collection and remains free after checkpoint time", async ({
  page,
}) => {
  const external = [];
  await page.route("**/*", (route) => {
    if (new URL(route.request().url()).origin !== "http://127.0.0.1:4173") {
      external.push(route.request().url());
      return route.abort();
    }
    return route.continue();
  });
  await prepare(page);
  await expect(
    page.getByLabel("Participante A quer participar"),
  ).not.toBeChecked();
  await expect(
    page.getByRole("button", { name: "Todos aceitaram: começar registros" }),
  ).toBeDisabled();
  await page.getByRole("button", { name: "Continuar sem registros" }).click();
  await expect(
    page.getByRole("heading", { name: "Podem continuar a oficina" }),
  ).toBeVisible();
  await page.clock.install();
  await page.clock.fastForward(45 * 60000);
  expect(await stored(page)).toHaveLength(0);
  await expect(
    page.getByRole("heading", { name: "Podem continuar a oficina" }),
  ).toBeVisible();
  expect(external).toEqual([]);
});

test("complete journey exports group-level evidence, rubric, actual times and no cloud writes", async ({
  page,
}) => {
  const posts = [];
  page.on("request", (request) => {
    if (request.method() === "POST") posts.push(request.url());
  });
  await prepare(page);
  await accept(page);
  await answer(page);
  await checkpoint(page, 20);
  await checkpoint(page, 40);
  await finish(page);
  const [session] = await stored(page);
  expect(session.environment).toBe("test");
  expect(session.group_size).toBe(2);
  expect(
    new Set(Object.values(session.responses).map((r) => r.group_id)).size,
  ).toBe(1);
  expect(
    session.events
      .filter((e) => e.event_type === "checkpoint_prompted")
      .every((e) => e.elapsed_ms < 1200000),
  ).toBe(true);
  const exportReady = page.waitForEvent("download");
  await page.getByRole("button", { name: "Exportar dados de teste" }).click();
  const download = await exportReady;
  expect(download.suggestedFilename()).toContain("TESTE");
  expect(posts).toEqual([]);
});

test("withdrawal deletes the entire session and cannot resurrect after reload", async ({
  page,
}) => {
  await prepare(page);
  await accept(page);
  await answer(page);
  expect(await stored(page)).toHaveLength(1);
  page.on("dialog", (dialog) => dialog.accept());
  await page
    .getByRole("button", { name: "Parar registros e apagar sessão" })
    .click();
  await expect(
    page.getByRole("heading", { name: "Podem continuar a oficina" }),
  ).toBeVisible();
  expect(await stored(page)).toHaveLength(0);
  await page.reload();
  await expect(
    page.getByRole("heading", {
      name: "Uma oficina, perguntas com propósito.",
    }),
  ).toBeVisible();
  expect(await stored(page)).toHaveLength(0);
});

test("resumes the same session and confirmed roles without rewriting identity", async ({
  page,
}) => {
  await prepare(page);
  await accept(page);
  await answer(page);
  await page.getByText("Área do instrutor: ajuda e papéis").click();
  await page
    .getByRole("combobox", { name: /Participante A/ })
    .selectOption("assembly");
  await page.getByRole("button", { name: "Confirmar papéis atuais" }).click();
  const [before] = await stored(page);
  await page.reload();
  await page.getByRole("button", { name: "Abrir sessão", exact: true }).click();
  const [after] = await stored(page);
  expect(after.group_id).toBe(before.group_id);
  expect(after.roles[0].role).toBe("assembly");
  expect(after.activity_started_at).toBe(before.activity_started_at);
});

test("tracks acknowledgement, start and resolution separately", async ({
  page,
}) => {
  await prepare(page);
  await accept(page);
  await answer(page);
  await page.getByRole("button", { name: "Precisamos de ajuda" }).click();
  await page.getByText("Área do instrutor: ajuda e papéis").click();
  for (const name of [
    "Confirmar que vi o pedido",
    "Iniciar atendimento",
    "Registrar resolução",
  ])
    await page.getByRole("button", { name, exact: true }).click();
  const [session] = await stored(page);
  expect(session.help[0].status).toBe("resolved");
  for (const field of [
    "requested_at",
    "acknowledged_at",
    "started_at",
    "resolved_at",
  ])
    expect(session.help[0][field]).toBeGreaterThan(0);
});

test("retention removes snapshots, responses, events and outcomes together", async ({
  page,
}) => {
  await prepare(page);
  await accept(page);
  await answer(page);
  await page.evaluate(
    () =>
      new Promise((resolve) => {
        const req = indexedDB.open("pulselab-test-bancada-v2", 1);
        req.onsuccess = () => {
          const db = req.result,
            tx = db.transaction("sessions", "readwrite"),
            store = tx.objectStore("sessions"),
            rows = store.getAll();
          rows.onsuccess = () =>
            rows.result.forEach((s) =>
              store.put({ ...s, expires_at: Date.now() - 1 }),
            );
          tx.oncomplete = () => {
            db.close();
            resolve();
          };
        };
      }),
  );
  await page.reload();
  await expect(
    page.getByRole("button", { name: "Preencher contexto fictício" }),
  ).toBeEnabled();
  expect(await stored(page)).toHaveLength(0);
});

test("individual mode omits group collaboration and does not force answers", async ({
  page,
}) => {
  await prepare(page, 1);
  await accept(page, 1);
  await answer(page, true);
  await page.getByText("Controles do teste: abrir um check-in agora").click();
  await page
    .getByRole("button", { name: "Abrir check-in 20", exact: true })
    .click();
  await expect(
    page.getByText("Desde a última pergunta, todos tiveram oportunidade"),
  ).toHaveCount(0);
  await expect(
    page.getByRole("button", { name: "Não chegamos a uma resposta conjunta" }),
  ).toHaveCount(0);
  await answer(page, true);
  const [session] = await stored(page);
  expect(
    Object.values(session.responses.checkpoint_20.answers).every(
      (v) => v === null,
    ),
  ).toBe(true);
});

test("completed activity needs a rubric, while unanswered checkpoints remain visible", async ({
  page,
}) => {
  await prepare(page);
  await accept(page);
  await answer(page);
  await page
    .getByRole("button", { name: "Encerrar atividade", exact: true })
    .click();
  await answer(page);
  await expect(
    page.getByRole("button", { name: "Concluir com devolutiva" }),
  ).toBeDisabled();
  const [session] = await stored(page);
  expect(session.completed_at).toBeNull();
  expect(session.rubric).toBeNull();
});

test("app and existing local records work offline after initial cache", async ({
  page,
  context,
}) => {
  await prepare(page);
  await accept(page);
  await answer(page);
  await page.evaluate(() => navigator.serviceWorker.ready);
  await page.reload();
  await context.setOffline(true);
  await page.reload({ waitUntil: "domcontentloaded" });
  await page.getByRole("button", { name: "Abrir sessão", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "O projeto está com vocês." }),
  ).toBeVisible();
  expect(await stored(page)).toHaveLength(1);
  await context.setOffline(false);
});

test("explicit artifact selection stores structure only and rejects unsupported content", async ({
  page,
}) => {
  await prepare(page);
  await accept(page);
  await answer(page);
  await page.getByText("Ler estrutura de um projeto salvo (opcional)").click();
  await page.getByLabel("Confirmei que este é o projeto").check();
  await page.getByLabel("Arquivo SPIKE ou Scratch").setInputFiles({
    name: "private-child.json",
    mimeType: "application/json",
    buffer: Buffer.from(
      JSON.stringify({
        targets: [
          {
            name: "private",
            blocks: { a: { opcode: "spike_motor_run", shadow: false } },
          },
        ],
      }),
    ),
  });
  await expect(page.getByRole("status")).toContainText("Estrutura lida");
  const [session] = await stored(page);
  expect(session.artifacts).toHaveLength(1);
  expect(JSON.stringify(session.artifacts)).not.toContain("private");
  expect(session.artifacts[0].inferred_stage).toBeUndefined();
});
