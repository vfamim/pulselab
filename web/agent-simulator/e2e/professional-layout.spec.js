import { test, expect } from '@playwright/test';
import { inspectVisuals, expectVisuals } from './helpers/visual-audit.js';

const viewports = [[1280, 720], [1024, 768], [768, 1024], [390, 844]];
async function audit(page, state) { expectVisuals(await inspectVisuals(page), state); }
async function chooseFour(page) { await page.getByRole('button', { name: '4 pessoas', exact: true }).click(); }
async function acceptAll(page) {
  for (const checkbox of await page.locator('.assent-member input').all()) await checkbox.check();
}
async function expectNeutralPending(page) {
  await expect(page.locator('.assent-panel')).toHaveClass(/--pending/);
  const colors = await page.locator('.assent-panel').evaluate((el) => {
    const style = getComputedStyle(el);
    return [style.backgroundColor, style.color, style.borderTopColor].map((value) => value.match(/\d+/g).slice(0, 3).map(Number));
  });
  // A pending decision must not acquire a red/pink surface, text or border.
  for (const [r, , b] of colors) expect(b).toBeGreaterThanOrEqual(r);
}

test.beforeEach(async ({ context, page }) => {
  await context.route('**/*', (route) => new URL(route.request().url()).origin === 'http://127.0.0.1:4173' ? route.continue() : route.abort());
  await page.goto('/alunos/');
});

for (const [width, height] of viewports) {
  test(`professional ${width}x${height}: pending, hover, focus, selected, disabled and disclosures`, async ({ page }) => {
    await page.setViewportSize({ width, height });
    await chooseFour(page);
    await expectNeutralPending(page);
    for (const checkbox of await page.locator('.assent-member input').all()) await expect(checkbox).not.toBeChecked();
    await audit(page, 'four pending');
    const initial = await inspectVisuals(page);
    expect(initial.primaryBottom, 'initial action above fold with FOUR people').toBeLessThanOrEqual(height);
    expect(initial.headingHeight, 'compact hero').toBeLessThanOrEqual(width < 500 ? 160 : 130);
    await page.getByRole('button', { name: '3 pessoas', exact: true }).hover();
    await audit(page, 'option hover');
    const first = page.locator('.assent-member input').first();
    await first.focus();
    await page.keyboard.press('Space');
    await expect(first).toBeChecked();
    await expectNeutralPending(page);
    await audit(page, 'partial assent and keyboard focus');
    await page.keyboard.press('Space');
    await expect(first).not.toBeChecked();
    await page.locator('.research-details summary').focus();
    await page.keyboard.press('Enter');
    await expect(page.locator('.research-details')).toHaveAttribute('open', '');
    await expect(page.locator('.research-details')).toContainText('7 dias');
    await audit(page, 'research detail open');
    await page.keyboard.press('Enter');
    await acceptAll(page);
    const start = page.getByRole('button', { name: 'Começar atividade', exact: true });
    await expect(start).toBeDisabled();
    await audit(page, 'all accepted and disabled start');
    const option = page.getByRole('button', { name: /Primeira vez/ });
    await option.focus();
    await page.keyboard.press('Enter');
    await expect(option).toHaveAttribute('aria-pressed', 'true');
    await expect(start).toBeEnabled();
    await start.hover();
    await audit(page, 'selection and primary hover');
    await start.click();
    const withdrawal = page.getByRole('button', { name: 'Parar de participar e apagar meus dados' });
    await withdrawal.focus();
    await audit(page, 'withdrawal keyboard focus on navy');
    await withdrawal.hover();
    await audit(page, 'withdrawal hover');
    await page.locator('.educator-area summary').click();
    await audit(page, 'educator controls');
    await page.getByRole('button', { name: 'Configurar oficina' }).click();
    await audit(page, 'dialog');
    await page.keyboard.press('Escape');
    await page.getByRole('button', { name: 'Ir para o desafio final' }).click();
    await page.locator('.educator-rubric summary').click();
    const radio = page.locator('input[name="race-result"]').first();
    await radio.focus();
    await page.keyboard.press('Space');
    await expect(radio).toBeChecked();
    await audit(page, 'selected rubric radio');
    await page.keyboard.press('ArrowDown');
    await expect(page.locator('input[name="race-result"]').nth(1)).toBeChecked();
    await audit(page, 'radio keyboard navigation');
  });
}

test('reflow at 320px and 200% text: ethics, options and dialog remain readable', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 844 });
  await chooseFour(page);
  await audit(page, '320px pending');
  await acceptAll(page);
  await page.evaluate(() => { document.documentElement.style.fontSize = '200%'; });
  await audit(page, '200% text');
  await page.locator('.research-details summary').click();
  await audit(page, '200% expanded ethics');
  await page.locator('.educator-area summary').click();
  await page.getByRole('button', { name: 'Configurar oficina' }).click();
  await audit(page, '200% dialog');
  await page.keyboard.press('Escape');
  await expect(page.getByRole('button', { name: 'Configurar oficina' })).toBeFocused();
});

test('real storage error, toast and Free Mode use readable colors', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.evaluate(() => {
    const transaction = IDBDatabase.prototype.transaction;
    IDBDatabase.prototype.transaction = function(stores, mode, ...rest) {
      if (mode === 'readwrite' && (stores === 'sessions' || Array.isArray(stores) && stores.includes('sessions'))) throw new DOMException('Synthetic storage failure', 'QuotaExceededError');
      return transaction.call(this, stores, mode, ...rest);
    };
  });
  await acceptAll(page);
  await page.getByRole('button', { name: /Primeira vez/ }).click();
  await page.getByRole('button', { name: 'Começar atividade', exact: true }).click();
  await expect(page.getByRole('alert')).toBeVisible();
  await audit(page, 'storage error');
  await page.getByRole('button', { name: 'Parar de participar e apagar meus dados' }).click();
  await expect(page.getByText(/Modo Livre: a aula continua/)).toBeVisible();
  await audit(page, 'Free Mode');
  await page.locator('.educator-area summary').click();
  await page.getByRole('button', { name: 'Configurar oficina' }).click();
  await page.getByRole('button', { name: 'Salvar', exact: true }).click();
  await expect(page.locator('.toast')).toBeVisible();
  await audit(page, 'settings toast');
});

test('laboratory disclosure also respects minimum font and contrast', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/alunos/?lab=1');
  await page.locator('.educator-area summary').click();
  await audit(page, 'empty laboratory');
  await acceptAll(page);
  await page.getByRole('button', { name: /Primeira vez/ }).click();
  await page.getByRole('button', { name: 'Começar atividade', exact: true }).click();
  await page.locator('.educator-area summary').click();
  await expect(page.locator('.event-row').first()).toBeVisible();
  await audit(page, 'laboratory with synthetic events');
});
