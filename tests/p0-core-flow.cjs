const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

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
        '  window.__qa = { buildSites, state, boatAnchorGroup, performSalvage, upgradeShip };\n  syncCoinUI();\n  return {'
      );
      await route.fulfill({ response, body });
    });

    await page.goto(process.env.APP_URL || 'http://localhost:8765');
    await page.waitForFunction(() => window.__qa && document.querySelector('.resource-mini'));

    assert.equal(await page.locator('.resource-mini').count(), 1);
    assert.equal(await page.locator('#min-wood-val').textContent(), '🪵 0');
    assert.equal(await page.locator('#min-parts-val').textContent(), '⚙ 0');
    assert.equal(await page.locator('.demo-objective-panel').count(), 0);
    assert.equal(await page.locator('.hover-context-card').evaluate(e => getComputedStyle(e).display), 'none');
    passed.push('HUD 仅显示资源数值，任务面板与悬停说明卡已移除');

    await page.evaluate(() => { window.__qa.performSalvage(); window.__qa.performSalvage(); });
    assert.deepEqual(await page.evaluate(() => ({
      wood: window.__qa.state.wood,
      parts: window.__qa.state.parts,
      runs: window.__qa.state.salvageRuns
    })), { wood: 6, parts: 4, runs: 2 });
    passed.push('打捞两次获得 6 木料与 4 旧零件');

    await page.evaluate(() => { window.__qa.upgradeShip(); });
    assert.deepEqual(await page.evaluate(() => ({
      level: window.__qa.state.shipLevel,
      unlocked: window.__qa.state.farSeaUnlocked,
      wood: window.__qa.state.wood,
      parts: window.__qa.state.parts
    })), { level: 2, unlocked: true, wood: 0, parts: 0 });
    assert.equal(await page.locator('#min-ship-val').textContent(), '⛵ 2');
    assert.equal(await page.locator('.far-sea-destination').getAttribute('aria-disabled'), 'false');
    passed.push('材料消耗、木船升级至 Lv.2，并解锁远海目的地');

    assert.deepEqual(errors, []);
    const result = { passed, errors, state: await page.evaluate(() => ({ ...window.__qa.state })) };
    fs.writeFileSync('outputs/p0-core-flow-results.json', JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result, null, 2));
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
