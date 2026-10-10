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

  // Verify child screen remained completely silent throughout
  await expect(page.getByRole("button")).toHaveCount(0);
  await expect(page.locator(".silent-bench-status")).toHaveText("Oficina pronta");
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
