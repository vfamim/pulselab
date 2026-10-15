import { test, expect } from '@playwright/test';
import { inspectVisuals, expectVisuals } from './helpers/visual-audit.js';

const viewports = [[1280, 720], [1024, 768], [768, 1024], [390, 844]];
async function audit(page, state) { expectVisuals(await inspectVisuals(page), state); }

const json = (body) => ({ status: 200, headers: { 'Access-Control-Allow-Origin': '*', 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
const current = { research_active: true, paused: false, active: true, session_id: '11111111-2222-4333-8444-555555555555', started_at: '2026-10-14T12:00:00.000Z', elapsed_min: 80 };
const status = { status: 'ok', version: 'test', research_active: true, paused: false, session: { session_id: current.session_id, elapsed_min: 80, telemetry_events: 4 }, spike_environment: { status: 'ok' }, pending_sync: 0 };

test.beforeEach(async ({ context }) => {
  await context.route('**/*', (route) => {
    const url = new URL(route.request().url());
    if (url.origin === 'http://127.0.0.1:4173') return route.continue();
    if (route.request().method() === 'OPTIONS') return route.fulfill(json({}));
    if (url.pathname === '/v1/session/current') return route.fulfill(json(current));
    if (url.pathname === '/v1/session/close') return route.fulfill(json({ status: 'closed', session_id: current.session_id }));
    if (url.pathname === '/v1/status') return route.fulfill(json(status));
    return route.abort();
  });
});

for (const [width, height] of viewports) {
  test(`professional ${width}x${height}: encerramento legível, contraste AA e alvos de toque`, async ({ page }) => {
    await page.setViewportSize({ width, height });
    await page.goto('/alunos/');
    await expect(page.getByRole('heading', { name: 'Encerrar a turma desta bancada?' })).toBeVisible();
    await audit(page, `confirmar ${width}x${height}`);
    await page.getByRole('button', { name: 'Encerrar turma' }).click();
    await expect(page.getByRole('heading', { name: 'Turma encerrada' })).toBeVisible();
    await audit(page, `encerrada ${width}x${height}`);

    // Sem termos técnicos nem identificadores na tela
    const bodyText = await page.locator('main').innerText();
    expect(bodyText).not.toMatch(/telemetria|sincroniz|metadados|outbox|quarentena|cronômetro|[a-f\d]{8}-[a-f\d]{4}/i);
  });
}

test('reflow at 320px: encerramento sem rolagem horizontal', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 844 });
  await page.goto('/alunos/');
  await audit(page, '320px confirmar');
  await page.getByRole('button', { name: 'Encerrar turma' }).click();
  await expect(page.getByRole('heading', { name: 'Turma encerrada' })).toBeVisible();
  await audit(page, '320px encerrada');
});

test('laboratory mode (?lab=1): diagnostic panel displays cleanly with valid targets and contrast', async ({ page }) => {
  await page.setViewportSize({ width: 1024, height: 768 });
  await page.goto('/alunos/?lab=1');
  await expect(page.locator('.lab-diagnostic')).toBeVisible();
  await expect(page.getByRole('heading', { name: /Modo de Inspeção/ })).toBeVisible();
  const buttons = page.locator('.lab-diagnostic button');
  expect(await buttons.count()).toBeGreaterThanOrEqual(2);
  await audit(page, 'laboratory inspection');
});
