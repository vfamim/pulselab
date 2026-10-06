import { expect, test } from "@playwright/test";
import { mkdir, writeFile } from "node:fs/promises";
import { inspectVisuals, expectVisuals } from "./helpers/visual-audit.js";

const artifactDir = "/tmp/pulselab-ux-professional";
const activeKey = "pulselab_student_active_session_v1";
const activityTitle = "Montem, programem e testem o robô";

async function records(page, name) {
  return page.evaluate((name) => new Promise((resolve, reject) => {
    const request = indexedDB.open("pulselab-student-runner", 1);
    request.onsuccess = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(name)) { db.close(); resolve([]); return; }
      const tx = db.transaction(name, "readonly");
      const read = tx.objectStore(name).getAll();
      read.onsuccess = () => resolve(read.result);
      read.onerror = () => reject(read.error);
      tx.oncomplete = () => db.close();
    };
    request.onerror = () => reject(request.error);
  }), name);
}
async function chooseTeam(page, size = 1) {
  await page.getByRole("button", { name: `${size} ${size === 1 ? "pessoa" : "pessoas"}`, exact: true }).click();
}
async function assent(page, size = 1) {
  await chooseTeam(page, size);
  for (const input of await page.locator('.assent-member input').all()) await input.check();
}
async function start(page, size = 1) {
  await assent(page, size);
  await page.getByRole("button", { name: /Primeira vez/ }).click();
  await page.getByRole("button", { name: "Começar atividade", exact: true }).click();
  await expect(page.getByRole("heading", { name: activityTitle })).toBeFocused();
}
async function expectSilent(page) {
  const text = await page.locator("main").innerText();
  expect(text).not.toMatch(/\b\d{2}:\d{2}\b|telemetria|sincroniz|metadados|v2\.2\.1|registros no dispositivo|cronômetro|sessão [a-f\d]{8}|Preencher teste/i);
  await expect(page.locator('.activity-timer, .stage-toolbar, .topbar__session')).toHaveCount(0);
}
async function measure(page, name, screenshot = false) {
  const report = await inspectVisuals(page);
  expectVisuals(report, name);
  if (name.endsWith('-initial')) expect(report.primaryBottom, `${name}: primary action is not fully visible`).toBeLessThanOrEqual(report.viewportHeight);
  await mkdir(artifactDir, { recursive: true });
  await writeFile(`${artifactDir}/${name}.json`, JSON.stringify(report, null, 2));
  if (screenshot) await page.screenshot({ path: `${artifactDir}/${name}.png`, fullPage: true });
}

test.beforeEach(async ({ context, page }) => {
  await context.route("**/*", (route) => new URL(route.request().url()).origin === "http://127.0.0.1:4173" ? route.continue() : route.abort());
  await page.goto("/alunos/");
});

for (const size of [1, 2, 3, 4]) {
  test(`individual assent ${size}: neutral, reversible, no persistence until start`, async ({ page }) => {
    await chooseTeam(page, size);
    await expect(page.locator('.assent-panel')).toHaveClass(/--pending/);
    await expect(page.getByRole('status')).toHaveText('Aguardando a escolha de cada pessoa.');
    const inputs = page.locator('.assent-member input');
    await expect(inputs).toHaveCount(size);
    for (let i = 0; i < size; i++) {
      await expect(inputs.nth(i)).not.toBeChecked();
      await inputs.nth(i).focus();
      await page.keyboard.press('Space');
      await expect(inputs.nth(i)).toBeChecked();
      if (i < size - 1) await expect(page.getByRole('button', { name: 'Começar atividade', exact: true })).toHaveCount(0);
      expect(await records(page, 'events')).toEqual([]);
      expect(await records(page, 'sessions')).toEqual([]);
    }
    await expect(page.getByRole('status')).toHaveText('Todos aceitaram participar.');
    await measure(page, `assent-${size}-accepted`);
    await inputs.last().uncheck();
    await expect(page.locator('.assent-panel')).toHaveClass(/--pending/);
    await page.getByRole('button', { name: 'Começar sem pesquisa', exact: true }).click();
    await expect(page.getByText(/Modo Livre: a aula continua/)).toBeVisible();
    await page.getByRole('button', { name: 'Ir para o desafio final' }).click();
    await expect(page.locator('.member-evaluations, .educator-rubric')).toHaveCount(0);
    await page.getByRole('button', { name: 'Concluir oficina' }).click();
    await expect(page.getByRole('heading', { name: 'Oficina concluída!' })).toBeFocused();
    expect(await records(page, 'events')).toEqual([]);
    expect(await records(page, 'sessions')).toEqual([]);
    expect(await page.evaluate(() => localStorage.length)).toBe(0);
    await expectSilent(page);
  });
}

for (const [width, height] of [[1280, 720], [1024, 768], [768, 1024], [390, 844]]) {
  test(`viewport ${width}x${height}: contrast, targets, focus and complete silent flow`, async ({ page }) => {
    await page.setViewportSize({ width, height });
    await measure(page, `after-${width}-initial`, true);
    await assent(page, 4);
    await page.locator('.assent-member input').last().uncheck();
    await measure(page, `after-${width}-pending`, true);
    await expectSilent(page);
    await page.locator('.assent-member input').last().check();
    await measure(page, `after-${width}-accepted`, true);
    await page.getByRole('button', { name: /Primeira vez/ }).click();
    await page.getByRole('button', { name: 'Começar atividade', exact: true }).click();
    await expect(page.locator('[data-stage-heading]')).toBeFocused();
    await measure(page, `after-${width}-activity`, true);
    await expectSilent(page);
    await page.getByRole('button', { name: 'Ir para o desafio final' }).click();
    await expect(page.locator('[data-stage-heading]')).toBeFocused();
    await measure(page, `after-${width}-challenge`, true);
    await expectSilent(page);
    for (let member = 0; member < 4; member++) await page.getByRole('button', { name: 'Prefiro não responder', exact: true }).first().click();
    await page.locator('.educator-rubric summary').click();
    await measure(page, `after-${width}-educator`, true);
    await page.locator('.educator-rubric summary').click();
    await page.getByRole('button', { name: 'Concluir oficina' }).click();
    await expect(page.getByRole('heading', { name: 'Oficina concluída!' })).toBeFocused();
    await measure(page, `after-${width}-finished`, true);
    await expectSilent(page);
    await page.locator('.educator-area summary').click();
    await page.getByRole('button', { name: 'Configurar oficina' }).click();
    await measure(page, `after-${width}-dialog`, true);
    await page.keyboard.press('Escape');
  });
}

test('team change clears prior choices; no forgotten consent is reused', async ({ page }) => {
  await assent(page, 4);
  await chooseTeam(page, 1);
  await chooseTeam(page, 4);
  for (const input of await page.locator('.assent-member input').all()) await expect(input).not.toBeChecked();
});

test('keyboard: focus visible, dialog trap/return, reduced motion, educator separated', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await start(page);
  await page.locator('.educator-area summary').focus();
  await page.keyboard.press('Enter');
  const open = page.getByRole('button', { name: 'Configurar oficina' });
  await open.click();
  const dialog = page.getByRole('dialog');
  await expect(dialog).toBeVisible();
  const first = dialog.getByRole('button').first(), last = dialog.getByRole('button').last();
  await first.focus(); await page.keyboard.press('Shift+Tab'); await expect(last).toBeFocused();
  await page.keyboard.press('Tab'); await expect(first).toBeFocused();
  expect(await first.evaluate((el) => getComputedStyle(el).outlineStyle)).toBe('solid');
  await page.waitForTimeout(1200); await expect(first).toBeFocused();
  await page.keyboard.press('Escape'); await expect(open).toBeFocused();
  await expect(dialog).not.toBeVisible();
  await page.locator('.educator-area summary').click();
  await expectSilent(page);
  expect(await page.locator('.student-content .button--primary').evaluate((el) => getComputedStyle(el).transitionDuration)).toBe('0s');
});

test('internal duration survives activity/post reload offline without visible timer or automatic end', async ({ page, context }) => {
  await start(page);
  await page.evaluate(() => navigator.serviceWorker.ready);
  await expect.poll(() => page.evaluate(() => !!navigator.serviceWorker.controller)).toBe(true);
  await page.clock.install();
  await page.clock.fastForward(75 * 60 * 1000);
  await expect(page.getByRole('heading', { name: activityTitle })).toBeVisible();
  await expectSilent(page);
  await context.setOffline(true);
  await page.reload();
  await expect(page.getByRole('heading', { name: activityTitle })).toBeFocused();
  await page.getByRole('button', { name: 'Ir para o desafio final' }).click();
  const elapsed = await page.evaluate((key) => JSON.parse(localStorage.getItem(key)).elapsedMs, activeKey);
  expect(elapsed).toBeGreaterThanOrEqual(75 * 60 * 1000);
  await page.clock.fastForward(10 * 60 * 1000);
  await page.reload();
  await expect(page.getByRole('heading', { name: 'Testem o carrinho na pista' })).toBeVisible();
  const after = await page.evaluate((key) => JSON.parse(localStorage.getItem(key)).elapsedMs, activeKey);
  expect(after).toBe(elapsed);
  await page.getByRole('button', { name: 'Prefiro não responder', exact: true }).click();
  await page.getByRole('button', { name: 'Concluir oficina' }).click();
  await expect(page.getByRole('heading', { name: 'Oficina concluída!' })).toBeVisible();
  const sessions = await records(page, 'sessions');
  expect(sessions[0].duration_seconds).toBe(Math.round(elapsed / 1000));
  expect(sessions[0].telemetry_status).toBe('invalid_or_unavailable');
  await expectSilent(page);
});

test('retention clock starts only when the assented research session starts', async ({ page }) => {
  await page.clock.install();
  await page.clock.fastForward(3 * 24 * 60 * 60 * 1000);
  await start(page);
  const snapshot = await page.evaluate((key) => JSON.parse(localStorage.getItem(key)), activeKey);
  const now = await page.evaluate(() => Date.now());
  expect(now - snapshot.startedAt).toBeLessThan(2_000);
  expect(snapshot.elapsedMs).toBeLessThan(2_000);
  await page.clock.fastForward(6 * 24 * 60 * 60 * 1000);
  await expect(page.getByRole('heading', { name: activityTitle })).toBeVisible();
  await expect.poll(async () => (await records(page, 'sessions')).length).toBe(1);
});

test('withdrawal purges both open tabs and rejects a delayed Bridge response', async ({ page, context }) => {
  let resolveMetrics;
  const metricRequested = new Promise((resolve) => { resolveMetrics = resolve; });
  await page.route('**/v1/spike/metrics', async (route) => {
    resolveMetrics();
    await new Promise((resolve) => setTimeout(resolve, 600));
    await route.fulfill({ json: { executable_blocks: 9, project_saved: true } }).catch(() => {});
  });
  await start(page);
  const second = await context.newPage(); await second.goto('/alunos/');
  await expect(second.getByRole('heading', { name: activityTitle })).toBeVisible();
  await metricRequested;
  await page.getByRole('button', { name: 'Parar de participar e apagar meus dados' }).click();
  for (const tab of [page, second]) {
    await expect(tab.getByText(/Modo Livre: a aula continua/)).toBeVisible();
    await expect(tab.getByRole('heading', { name: activityTitle })).toBeFocused();
  }
  await page.waitForTimeout(1800);
  expect(await records(page, 'events')).toEqual([]);
  expect(await records(page, 'sessions')).toEqual([]);
  expect(await page.evaluate((key) => localStorage.getItem(key), activeKey)).toBeNull();
});

test('expired local snapshot cannot resurrect research after reload', async ({ page }) => {
  await start(page);
  await page.evaluate((key) => {
    const snapshot = JSON.parse(localStorage.getItem(key));
    snapshot.startedAt = Date.now() - 8 * 24 * 60 * 60 * 1000;
    localStorage.setItem(key, JSON.stringify(snapshot));
  }, activeKey);
  await page.reload();
  await expect(page.getByRole('heading', { name: 'Vamos montar e programar?' })).toBeVisible();
  await expect.poll(async () => (await records(page, 'events')).length).toBe(0);
  expect(await records(page, 'sessions')).toEqual([]);
  expect(await page.evaluate((key) => localStorage.getItem(key), activeKey)).toBeNull();
});

test('save failure stays visible and never claims all data were safely saved', async ({ page }) => {
  await page.evaluate(() => {
    const transaction = IDBDatabase.prototype.transaction;
    IDBDatabase.prototype.transaction = function(stores, mode, ...rest) {
      if (mode === 'readwrite' && (stores === 'sessions' || Array.isArray(stores) && stores.includes('sessions'))) throw new DOMException('Synthetic storage failure', 'QuotaExceededError');
      return transaction.call(this, stores, mode, ...rest);
    };
  });
  await start(page);
  await expect(page.getByRole('alert')).toContainText('Não foi possível guardar');
  await page.getByRole('button', { name: 'Ir para o desafio final' }).click();
  await page.getByRole('button', { name: 'Pular avaliação e concluir' }).click();
  await expect(page.getByRole('heading', { name: 'Oficina concluída!' })).toBeVisible();
  await expect(page.getByRole('alert')).toContainText('Não foi possível guardar');
  expect(await page.locator('main').innerText()).not.toMatch(/salvas com segurança|salvos com segurança/);
});


test('Bridge local contract: no notifications, empty scheduled marks, structural metrics and completed copy', async ({ page }) => {
  const calls = [];
  await page.route('**/v1/**', async (route) => {
    const path = new URL(route.request().url()).pathname;
    calls.push({ path, data: route.request().postDataJSON() });
    const json = path === '/v1/spike/metrics'
      ? { executable_blocks: 12, project_saved: true, uses_motor: true, file_name: 'synthetic-name.llsp3', inferred_stage: 'synthetic-inference' }
      : path === '/v1/sessions/reset'
        ? { status: 'purged', purged: true, remote_pending: false }
        : { status: 'ok' };
    await route.fulfill({ json });
  });
  await page.evaluate(() => {
    window.notificationRequests = 0;
    Notification.requestPermission = () => { window.notificationRequests++; return Promise.resolve('denied'); };
  });
  await assent(page);
  expect(calls.filter((call) => call.data)).toEqual([]);
  await page.getByRole('button', { name: /Primeira vez/ }).click();
  await page.getByRole('button', { name: 'Começar atividade', exact: true }).click();
  await expect(page.getByRole('heading', { name: activityTitle })).toBeVisible();
  await page.getByRole('button', { name: 'Ir para o desafio final' }).click();
  await page.getByRole('button', { name: /Muito boa/ }).click();
  await page.getByRole('button', { name: 'Concluir oficina' }).click();
  await expect.poll(() => calls.filter((call) => call.path === '/v1/sessions/save').length).toBe(1);
  const started = calls.find((call) => call.path === '/v1/sessions');
  expect(started.data.marks).toEqual([]);
  const completed = calls.find((call) => call.path === '/v1/sessions/save').data;
  expect(completed.status).toBe('completed');
  expect(completed.spike_telemetry.executable_blocks).toBe(12);
  expect(JSON.stringify(completed)).not.toMatch(/synthetic-name|synthetic-inference|MEMBER-/);
  expect(completed.post_answers.quizCompleted).toBeNull();
  expect(await page.evaluate(() => window.notificationRequests)).toBe(0);
  await page.getByRole('button', { name: 'Parar de participar e apagar meus dados' }).click();
  await expect.poll(() => calls.filter((call) => call.path === '/v1/sessions/reset').length).toBe(1);
  expect(calls.find((call) => call.path === '/v1/sessions/reset').data.purge).toBe(true);
  expect(await records(page, 'sessions')).toEqual([]);
});

test('skipping the final evaluation discards partially entered answers', async ({ page }) => {
  await start(page, 2);
  await page.getByRole('button', { name: 'Ir para o desafio final' }).click();
  await page.getByRole('button', { name: /Muito boa/ }).first().click();
  await page.getByRole('button', { name: 'Pular avaliação e concluir' }).click();
  await expect(page.getByRole('heading', { name: 'Oficina concluída!' })).toBeVisible();
  const sessions = await records(page, 'sessions');
  expect(sessions[0].post_answers.memberExperiences).toEqual([]);
  expect(sessions[0].events.filter((event) => event.event_type === 'post')[0].response_status).toBe('declined');
});


test('laboratory tools require explicit URL and mark sessions synthetic', async ({ page }) => {
  await page.locator('.educator-area summary').click();
  await expect(page.getByRole('button', { name: 'Preencher teste' })).toHaveCount(0);
  await page.goto('/alunos/?lab=1');
  await start(page);
  const snapshot = await page.evaluate((key) => JSON.parse(localStorage.getItem(key)), activeKey);
  expect(snapshot.isSyntheticSession).toBe(true);
  await page.locator('.educator-area summary').click();
  await expect(page.getByRole('button', { name: 'Preencher teste' })).toBeVisible();
  await expect.poll(async () => (await records(page, 'events')).length).toBeGreaterThan(0);
  expect((await records(page, 'events')).every((event) => event.is_synthetic === true)).toBe(true);
});

test('an open session expires at seven days and cannot keep rewriting data', async ({ page }) => {
  await page.clock.install();
  await start(page);
  await page.clock.fastForward(7 * 24 * 60 * 60 * 1000);
  await expect(page.getByText(/Modo Livre: a aula continua/)).toBeVisible();
  await expect.poll(async () => (await records(page, 'sessions')).length).toBe(0);
  await page.clock.fastForward(60_000);
  expect(await records(page, 'events')).toEqual([]);
  expect(await page.evaluate((key) => localStorage.getItem(key), activeKey)).toBeNull();
});
