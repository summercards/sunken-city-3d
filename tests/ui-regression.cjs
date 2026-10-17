const { chromium } = require('playwright');
const assert = require('node:assert/strict');

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
    args: ['--enable-webgl', '--ignore-gpu-blocklist']
  });
  const passed = [];
  const errors = [];
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
    page.on('pageerror', error => errors.push(error.message));
    await page.route('**/gameplay.js', async route => {
      const response = await route.fetch();
      const body = (await response.text()).replace(
        '  syncCoinUI();\n  return {',
        '  window.__qa = { camera, controls, buildSites, state, explorerGroup, boatAnchorGroup, performSalvage, upgradeShip };\n  syncCoinUI();\n  return {'
      );
      await route.fulfill({ response, body });
    });

    await page.goto(process.env.APP_URL || 'http://localhost:8765');
    await page.waitForFunction(() => window.__qa && document.querySelector('.resource-mini'));
    await page.waitForTimeout(900);

    assert.equal(await page.locator('.demo-objective-panel').count(), 0);
    assert.equal(await page.locator('.hover-context-card').evaluate(e => getComputedStyle(e).display), 'none');
    assert.equal(await page.locator('.action-wheel-label').count(), 1);
    assert.equal(await page.locator('.action-wheel-label').evaluate(e => getComputedStyle(e).display), 'none');
    assert.equal(await page.locator('.destination-btn small').count(), 0);
    assert.equal(await page.locator('.resource-mini').count(), 1);
    passed.push('移除任务面板、悬停卡片和目的地文字标签');

    assert.equal(await page.locator('#min-coin-val').textContent(), '80');
    assert.equal(await page.locator('#min-wood-val').textContent(), '🪵 0');
    assert.equal(await page.locator('#min-parts-val').textContent(), '⚙ 0');
    assert.equal(await page.locator('#min-ship-val').textContent(), '⛵ 1');
    passed.push('顶部 HUD 只保留海贝、木料、零件和船只等级数值');

    await page.evaluate(() => { window.__qa.performSalvage(); });
    assert.equal(await page.locator('#min-wood-val').textContent(), '🪵 3');
    assert.equal(await page.locator('#min-parts-val').textContent(), '⚙ 2');
    assert.equal(await page.locator('.float-tip').count() > 0, true);
    passed.push('打捞反馈使用场景上方数值浮字');

    assert.equal(await page.locator('#bp-label').count(), 0);
    assert.equal(await page.locator('.bp-bar').count(), 1);
    passed.push('建设中只保留进度条，不显示额外标签');

    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(300);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth), 390);
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({ passed, errors }, null, 2));
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
