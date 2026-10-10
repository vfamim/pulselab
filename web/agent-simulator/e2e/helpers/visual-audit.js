import { expect } from '@playwright/test';

// Audit computed rendering, including inherited styles, alpha backgrounds and closed details.
// This deliberately requires 4.5:1 even for large text and disabled controls.
export async function inspectVisuals(page) {
  return page.evaluate(() => {
    const rgb = (str) => (str.match(/[\d.]+/g) || []).map(Number);
    const mix = (fg, bg) => fg.slice(0, 3).map((x, i) => x * (fg[3] ?? 1) + bg[i] * (1 - (fg[3] ?? 1)));
    const lum = (c) => c.map((x) => x / 255).map((x) => x <= .04045 ? x / 12.92 : ((x + .055) / 1.055) ** 2.4).reduce((s, x, i) => s + x * [.2126, .7152, .0722][i], 0);
    const contrast = (a, b) => (Math.max(lum(a), lum(b)) + .05) / (Math.min(lum(a), lum(b)) + .05);
    const visible = (el) => el.checkVisibility({ checkVisibilityCSS: true, checkOpacity: true }) && !!el.getClientRects().length;
    const background = (el) => {
      const parents = []; for (let p = el; p; p = p.parentElement) parents.unshift(p);
      return parents.reduce((bg, p) => mix(rgb(getComputedStyle(p).backgroundColor), bg), [255, 255, 255]);
    };
    const texts = [];
    const unsupportedBackgrounds = [];
    for (const el of document.querySelectorAll('.student-app, .student-app *')) {
      if (!visible(el) || el.closest('[aria-hidden="true"]')) continue;
      const style = getComputedStyle(el);
      if (style.backgroundImage !== 'none') unsupportedBackgrounds.push(el.className);
      if (![...el.childNodes].some((n) => n.nodeType === Node.TEXT_NODE && n.textContent.trim())) continue;
      const bg = background(el);
      texts.push({ text: el.textContent.trim().slice(0, 75), ratio: contrast(mix(rgb(style.color), bg), bg), size: style.fontSize, lineHeight: style.lineHeight });
    }
    const targets = [...document.querySelectorAll('.student-app button, .student-app summary, .assent-member, .student-app .option-row, .student-app input[type="number"]')].filter(visible).map((el) => {
      const r = el.getBoundingClientRect(); return { text: el.textContent.trim().slice(0, 50), width: r.width, height: r.height };
    });
    const controls = [...document.querySelectorAll('.student-app button, .assent-member, .student-app .option-row, .student-app input[type="number"]')].filter(visible).map((el) => {
      const style = getComputedStyle(el), bg = background(el), outside = background(el.parentElement);
      return { text: el.textContent.trim().slice(0, 50), ratio: Math.max(contrast(bg, outside), contrast(mix(rgb(style.borderTopColor), bg), bg)) };
    });
    const focused = [...document.querySelectorAll('.student-app :focus-visible')].filter((el) => visible(el) && !el.hasAttribute('data-stage-heading') && el.getAttribute('tabindex') !== '-1').map((el) => {
      const style = getComputedStyle(el), bg = background(el.parentElement);
      return { width: parseFloat(style.outlineWidth), style: style.outlineStyle, ratio: contrast(mix(rgb(style.outlineColor), bg), bg) };
    });
    const footerEl = document.querySelector('.flow-card__footer, .silent-bench-container');
    const footer = footerEl ? footerEl.getBoundingClientRect() : { top: 0, bottom: 0 };
    const headingEl = document.querySelector('.flow-card__heading, .silent-bench-message, h1');
    const headingHeight = headingEl ? headingEl.getBoundingClientRect().height : 0;
    return {
      width: document.documentElement.scrollWidth,
      viewport: document.documentElement.clientWidth,
      viewportHeight: innerHeight,
      texts,
      targets,
      controls,
      focused,
      unsupportedBackgrounds,
      primaryY: footer.top + scrollY,
      primaryBottom: footer.bottom + scrollY,
      headingHeight,
      primaryCount: [...document.querySelectorAll('.flow-card .button--primary, .button--primary')].filter(visible).length
    };
  });
}

export function expectVisuals(report, name) {
  expect(report.width, `${name}: horizontal overflow`).toBeLessThanOrEqual(report.viewport);
  expect(report.texts.length, `${name}: audit must inspect rendered text`).toBeGreaterThan(1);
  expect(report.unsupportedBackgrounds, `${name}: gradient/image needs a separate contrast audit`).toEqual([]);
  expect(report.texts.filter((item) => item.ratio < 4.5), `${name}: text contrast`).toEqual([]);
  expect(report.texts.filter((item) => parseFloat(item.size) < 14), `${name}: functional text below 14px`).toEqual([]);
  expect(report.targets.filter((item) => item.width < 44 || item.height < 44), `${name}: touch targets`).toEqual([]);
  expect(report.controls.filter((item) => item.ratio < 3), `${name}: control boundary contrast`).toEqual([]);
  expect(report.focused.filter((item) => item.width < 3 || item.style === 'none' || item.ratio < 3), `${name}: focus contrast`).toEqual([]);
}
