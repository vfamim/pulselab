import { expect, test } from "@playwright/test";

const activeKey = "pulselab_student_active_session_v1";
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Prefer, apikey, Authorization",
  "Content-Type": "application/json"
};

async function getStoredRecords(page, storeName) {
  return page.evaluate((name) => new Promise((resolve) => {
    const request = indexedDB.open("pulselab-student-runner", 1);
    request.onsuccess = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(name)) { db.close(); resolve([]); return; }
      const tx = db.transaction(name, "readonly");
      const read = tx.objectStore(name).getAll();
      read.onsuccess = () => resolve(read.result || []);
      read.onerror = () => resolve([]);
      tx.oncomplete = () => db.close();
    };
    request.onerror = () => resolve([]);
  }), storeName);
}

test.beforeEach(async ({ context, page }) => {
  await context.route("**/*", (route) => {
    const url = new URL(route.request().url());
    if (url.origin === "http://127.0.0.1:4173") return route.continue();
    // Default: fail-closed (block or abort unmocked external network)
    return route.abort();
  });
  await page.goto("/alunos/");
  await page.evaluate(async () => {
    localStorage.clear();
    sessionStorage.clear();
    await new Promise((resolve) => {
      const req = indexedDB.deleteDatabase("pulselab-student-runner");
      req.onsuccess = () => resolve();
      req.onerror = () => resolve();
      req.onblocked = () => resolve();
    });
  });
  await page.reload();
});

test("silent student flow: zero forms, zero rhythm buttons, calm guidance and discrete ready status", async ({ page }) => {
  await expect(page.locator(".silent-bench-container")).toBeVisible();
  await expect(page.getByRole("heading", { level: 1 })).toContainText("Oficina de robótica em andamento");
  await expect(page.locator(".silent-bench-guidance")).toContainText("Monte, programe e teste o seu robô na bancada.");
  await expect(page.locator(".silent-bench-status")).toContainText("Oficina pronta");

  // Zero inputs or buttons in normal student screen
  await expect(page.getByRole("button")).toHaveCount(0);
  await expect(page.locator("input, select, textarea, [role='checkbox']")).toHaveCount(0);

  // Technical terms and meters must not appear
  const bodyText = await page.locator("main").innerText();
  expect(bodyText).not.toMatch(/\b\d{2}:\d{2}\b|telemetria|sincroniz|metadados|v2\.2\.3|outbox|quarentena|cronômetro|sessão\s+[a-f\d]{8}/i);
});

test("fail-closed default: unauthorized bridge configuration maintains Free Mode with zero persistence", async ({ page }) => {
  // Bridge mock returns unauthorized configuration (research disabled)
  await page.route("**/v1/config", (route) =>
    route.fulfill({
      status: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        research_collection_enabled: false,
        research_authorization_version: null,
        research_authorized_purposes: [],
        group_size: 2
      })
    })
  );

  await page.reload();
  await page.waitForTimeout(500);

  // IndexedDB must have zero stored events or sessions
  const events = await getStoredRecords(page, "events");
  const sessions = await getStoredRecords(page, "sessions");
  expect(events).toEqual([]);
  expect(sessions).toEqual([]);

  // localStorage must not retain active research session
  const rawActive = await page.evaluate((k) => localStorage.getItem(k), activeKey);
  expect(rawActive).toBeNull();
});

test("authorized research: automatic silent background session and spike polling without child interaction", async ({ page }) => {
  // Bridge mock returns valid authorization
  await page.route("**/v1/config", (route) =>
    route.fulfill({
      status: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        research_collection_enabled: true,
        research_authorization_version: "v2026.1-institucional",
        research_authorized_purposes: ["academic_research"],
        group_size: 3,
        site_id: "Polo-Nordeste",
        workshop_code: "oficina-spike-01"
      })
    })
  );

  await page.route("**/v1/spike/metrics", (route) =>
    route.fulfill({
      status: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        executable_blocks: 12,
        top_level_stacks: 2,
        uses_motor: true,
        uses_sensor: false,
        project_saved: true
      })
    })
  );

  await page.route("**/v1/sessions**", (route) => route.fulfill({ status: 200, headers: corsHeaders, body: JSON.stringify({ ok: true }) }));
  await page.route("**/v1/events**", (route) => route.fulfill({ status: 200, headers: corsHeaders, body: JSON.stringify({ ok: true }) }));

  await page.reload();

  // Wait for session_started event to be saved in IndexedDB
  await expect.poll(async () => {
    const list = await getStoredRecords(page, "events");
    return list.find((e) => e.event_type === "session_started");
  }, { timeout: 10_000 }).toBeTruthy();

  const events = await getStoredRecords(page, "events");
  const startEvent = events.find((e) => e.event_type === "session_started");
  expect(startEvent.details.group_size).toBe(3);
  expect(startEvent.details.collective_unit).toBe("bancada");

  // Child screen stays silent: the only control is the instructor's "Encerrar turma"
  await expect(page.getByRole("button")).toHaveCount(1);
  await expect(page.getByRole("button", { name: "Encerrar turma" })).toBeVisible();
  await expect(page.locator(".silent-bench-status")).toHaveText("Oficina pronta");
});

test("encerrar turma: bancada responde, instrutor avalia e a próxima turma começa", async ({ page }) => {
  await page.route("**/v1/config", (route) =>
    route.fulfill({
      status: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        research_collection_enabled: true,
        research_authorization_version: "12345678.9.0000.1234",
        research_authorized_purposes: ["academic_research"],
        group_size: 3,
        site_id: "PET",
        regional_hub: "Petrolina",
        school_code: "CONFIGURE_ESCOLA",
        installation_id: "11111111-2222-4333-8444-555555555555",
        machine_label: "PET-LAB1-PC03"
      })
    })
  );
  await page.route("**/v1/spike/metrics", (route) => route.fulfill({ status: 200, headers: corsHeaders, body: JSON.stringify({ project_saved: false }) }));
  await page.route("**/v1/sessions**", (route) => route.fulfill({ status: 200, headers: corsHeaders, body: JSON.stringify({ ok: true, purged: false }) }));
  await page.route("**/v1/events**", (route) => route.fulfill({ status: 200, headers: corsHeaders, body: JSON.stringify({ ok: true }) }));
  await page.reload();

  await expect.poll(async () => (await getStoredRecords(page, "events")).filter((e) => e.event_type === "session_started").length).toBe(1);

  await page.getByRole("button", { name: "Encerrar turma" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Encerrar turma" }).click();
  await expect(page.getByRole("heading", { name: "Como foi a oficina para a sua bancada hoje?" })).toBeVisible();
  await page.getByRole("button", { name: /Gostamos/ }).first().click();

  const register = page.getByRole("button", { name: "Registrar" });
  await expect(register).toBeDisabled();
  await page.getByRole("button", { name: "Concluiu a missão" }).click();
  await page.getByRole("button", { name: "Algum" }).click();
  await register.click();
  await expect(page.getByText("Turma encerrada.")).toBeVisible();

  await expect.poll(async () => (await getStoredRecords(page, "events")).filter((e) => e.event_type === "session_started").length).toBe(2);
  const events = await getStoredRecords(page, "events");
  const [first, second] = events.filter((e) => e.event_type === "session_started").sort((a, b) => a.occurred_at.localeCompare(b.occurred_at));
  const experience = events.find((e) => e.event_type === "experience_recorded");
  const rubric = events.find((e) => e.event_type === "rubric_completed");
  const completed = events.find((e) => e.event_type === "session_completed");

  expect(experience.session_id).toBe(first.session_id);
  expect(experience.details).toMatchObject({ item_id: "experiencia_bancada_v1", value: 3, refused: false });
  expect(rubric.details).toMatchObject({ result_level: 2, support_level: "algum", skipped: false });
  expect(completed.session_id).toBe(first.session_id);
  expect(second.session_id).not.toBe(first.session_id);
  expect(second.details.start_mode).toBe("apos_encerramento");
  expect(first.details.start_mode).toBe("abertura_app");
  expect(first.installation_id).toBe("11111111-2222-4333-8444-555555555555");
  expect(first.computer_id).toBe("PET-LAB1-PC03");
  expect(first.school_code).toBe("nao_informado");
  expect(first.details.context_missing).toContain("school_code");

  const sessions = await getStoredRecords(page, "sessions");
  const closed = sessions.find((s) => (s.session_id || s.sessionId) === first.session_id);
  expect(closed.status).toBe("completed");
});

test("idempotent in-tab reload vs discard of old session for a new group", async ({ page }) => {
  // 1. Authorize session
  await page.route("**/v1/config", (route) =>
    route.fulfill({
      status: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        research_collection_enabled: true,
        research_authorization_version: "v2026.1",
        research_authorized_purposes: ["academic_research"],
        group_size: 4
      })
    })
  );
  await page.route("**/v1/sessions**", (route) => route.fulfill({ status: 200, headers: corsHeaders, body: JSON.stringify({ ok: true }) }));
  await page.route("**/v1/events**", (route) => route.fulfill({ status: 200, headers: corsHeaders, body: JSON.stringify({ ok: true }) }));
  await page.route("**/v1/spike/metrics", (route) => route.fulfill({ status: 200, headers: corsHeaders, body: JSON.stringify(null) }));

  await page.reload();
  await expect.poll(async () => (await getStoredRecords(page, "events")).length).toBeGreaterThanOrEqual(1);

  const firstSessionId = await page.evaluate((k) => JSON.parse(localStorage.getItem(k)).sessionId, activeKey);

  // In-tab reload (F5) within ongoing workshop preserves existing session idempotently
  await page.reload();
  const reloadedSessionId = await page.evaluate((k) => JSON.parse(localStorage.getItem(k))?.sessionId, activeKey);
  expect(reloadedSessionId).toBe(firstSessionId);

  // Still exactly 1 session_started event (not duplicated!)
  const eventsAfterReload = await getStoredRecords(page, "events");
  const startedEvents = eventsAfterReload.filter((e) => e.event_type === "session_started");
  expect(startedEvents.length).toBe(1);

  // 2. Simulate opening for a new group (sessionStorage cleared, and stale session)
  await page.evaluate(() => sessionStorage.clear());
  // Stale savedAt from an earlier group (> 30 min ago)
  await page.evaluate((k) => {
    const data = JSON.parse(localStorage.getItem(k));
    data.savedAt = new Date(Date.now() - 45 * 60 * 1000).toISOString();
    localStorage.setItem(k, JSON.stringify(data));
  }, activeKey);

  await page.reload();

  // The stale session must NOT be restored for the new group! A new session is started with a different ID
  await expect.poll(async () => {
    return page.evaluate((k) => JSON.parse(localStorage.getItem(k))?.sessionId, activeKey);
  }).not.toBe(firstSessionId);
});

test("laboratory mode (?lab=1): ethical withdrawal purges storage and resets session", async ({ page }) => {
  await page.route("**/v1/config", (route) =>
    route.fulfill({
      status: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        research_collection_enabled: true,
        research_authorization_version: "v2026.1",
        research_authorized_purposes: ["academic_research"],
        group_size: 2
      })
    })
  );
  await page.route("**/v1/sessions**", (route) => route.fulfill({ status: 200, headers: corsHeaders, body: JSON.stringify({ ok: true }) }));
  await page.route("**/v1/events**", (route) => route.fulfill({ status: 200, headers: corsHeaders, body: JSON.stringify({ ok: true }) }));
  await page.route("**/v1/sessions/reset", (route) => route.fulfill({ status: 200, headers: corsHeaders, body: JSON.stringify({ ok: true, purged: true }) }));

  await page.goto("/alunos/?lab=1");
  await expect(page.locator(".lab-diagnostic")).toBeVisible();

  // Click ethical withdrawal button in laboratory inspection panel
  const withdrawBtn = page.getByRole("button", { name: "Testar Retirada Ética" });
  await expect(withdrawBtn).toBeVisible();
  await withdrawBtn.click();

  // Storage purged and active session removed
  await expect.poll(async () => (await getStoredRecords(page, "events")).length).toBe(0);
  await expect.poll(async () => (await getStoredRecords(page, "sessions")).length).toBe(0);
  const activeAfterWithdraw = await page.evaluate((k) => localStorage.getItem(k), activeKey);
  expect(activeAfterWithdraw).toBeNull();
});
