import { expect, test } from "@playwright/test";

const activeKey = "pulselab_student_active_session_v1";

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

test("offline operation: functions smoothly offline without errors interrupting the student", async ({ context, page }) => {
  await context.setOffline(true);
  await page.reload();

  await expect(page.locator(".silent-bench-container")).toBeVisible();
  await expect(page.getByRole("heading", { level: 1 })).toContainText("Oficina de robótica em andamento");
  await expect(page.locator(".silent-bench-status")).toHaveText("Oficina pronta");

  // No error popups or interruptive modals
  await expect(page.locator("[role='alert']")).toHaveCount(0);
});

test("reduced motion: respects prefers-reduced-motion media query", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.reload();

  const container = page.locator(".silent-bench-container");
  await expect(container).toBeVisible();

  const animationDuration = await container.evaluate((el) => getComputedStyle(el).animationDuration);
  expect(animationDuration === "0s" || animationDuration === "0ms" || animationDuration === "").toBe(true);
});

test("enforces 7-day retention cleanup on startup", async ({ page }) => {
  // Pre-seed an expired event in IndexedDB (> 7 days old)
  await page.evaluate(() => new Promise((resolve, reject) => {
    const req = indexedDB.open("pulselab-student-runner", 1);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains("events")) db.createObjectStore("events", { keyPath: "event_id" });
      if (!db.objectStoreNames.contains("sessions")) db.createObjectStore("sessions", { keyPath: "sessionId" });
    };
    req.onsuccess = () => {
      const db = req.result;
      const tx = db.transaction(["events", "sessions"], "readwrite");
      tx.objectStore("events").put({
        event_id: "expired-event-1",
        event_type: "session_started",
        occurred_at: new Date(Date.now() - 9 * 24 * 60 * 60 * 1000).toISOString()
      });
      tx.oncomplete = () => { db.close(); resolve(); };
      tx.onerror = () => reject(tx.error);
    };
  }));

  // Reload the student page to trigger enforceAbsoluteRetention(7)
  await page.reload();

  // Expired event must be purged
  await expect.poll(async () => (await getStoredRecords(page, "events")).length).toBe(0);
});

test("no individual survey fields or individual data structures present", async ({ page }) => {
  await expect(page.locator(".member-evaluations, .member-assents, .likert-scale, .rubric-question")).toHaveCount(0);
  await expect(page.getByRole("checkbox")).toHaveCount(0);
  await expect(page.getByRole("radio")).toHaveCount(0);
});
