import { test, expect } from '@playwright/test';
import { inspectVisuals, expectVisuals } from './helpers/visual-audit.js';

const viewports = [[1280, 720], [1024, 768], [768, 1024], [390, 844]];
async function audit(page, state) { expectVisuals(await inspectVisuals(page), state); }

test.beforeEach(async ({ context, page }) => {
  await context.route('**/*', (route) => {
    const url = new URL(route.request().url());
    if (url.origin === 'http://127.0.0.1:4173') return route.continue();
    return route.abort();
  });
  await page.goto('/alunos/');
});

for (const [width, height] of viewports) {
  test(`professional ${width}x${height}: calm, high-contrast, zero technical controls`, async ({ page }) => {
    await page.setViewportSize({ width, height });
    await expect(page.locator('.silent-bench-container')).toBeVisible();
    await expect(page.getByRole('heading', { level: 1 })).toContainText('Oficina de robótica em andamento');
    await expect(page.locator('.silent-bench-guidance')).toContainText('Monte, programe e teste o seu robô na bancada.');
    await expect(page.locator('.silent-bench-status')).toContainText('Oficina pronta');

    // Visual audit: typography, contrast (WCAG AA >= 4.5:1), zero horizontal overflow
    await audit(page, `silent ${width}x${height}`);

    // No buttons to control rhythm or tempt children
    await expect(page.getByRole('button')).toHaveCount(0);
    await expect(page.locator('input, select, textarea')).toHaveCount(0);

    // No technical indicators
    const bodyText = await page.locator('main').innerText();
    expect(bodyText).not.toMatch(/\b\d{2}:\d{2}\b|telemetria|sincroniz|metadados|v2\.2\.3|outbox|quarentena|cronômetro|sessão\s+[a-f\d]{8}/i);
  });
}

test('reflow at 320px: typography and calm container remain readable without horizontal overflow', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 844 });
  await expect(page.locator('.silent-bench-container')).toBeVisible();
  await audit(page, '320px silent');
  const bodyText = await page.locator('main').innerText();
  expect(bodyText).toContain('LEGO SPIKE');
});

test('laboratory mode (?lab=1): diagnostic panel displays cleanly with valid targets and contrast', async ({ page }) => {
  await page.setViewportSize({ width: 1024, height: 768 });
  await page.goto('/alunos/?lab=1');
  await expect(page.locator('.lab-diagnostic')).toBeVisible();
  await expect(page.getByRole('heading', { name: /Modo de Inspeção Sintética/ })).toBeVisible();

  // Targets in lab mode must satisfy touch target min-size (44px)
  const buttons = page.locator('.lab-diagnostic button');
  expect(await buttons.count()).toBeGreaterThanOrEqual(2);
  await audit(page, 'laboratory inspection');
});
