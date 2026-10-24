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
        '  window.__qa = { state, performSalvage, SALVAGE_COOLDOWN, SALVAGE_YIELD, get gauge() { return salvageGauge; } };\n  syncCoinUI();\n  return {'
      );
      await route.fulfill({ response, body });
    });

    await page.goto(process.env.APP_URL || 'http://localhost:8765');
    await page.waitForFunction(() => window.__qa && window.__qa.gauge);
    await page.waitForTimeout(700);

    const read = () => page.evaluate(() => {
      const q = window.__qa;
      return {
        cooldown: +q.state.salvageCooldown.toFixed(2),
        runs: q.state.salvageRuns,
        wood: q.state.wood,
        parts: q.state.parts,
        ringColor: q.gauge.ringMat.color.getHexString(),
        ringOpacity: +q.gauge.ringMat.opacity.toFixed(2),
        pipScale: +q.gauge.pip.scale.x.toFixed(3)
      };
    });

    // 1) 起始就绪：绞盘环是暖色、充能盘满格。
    const ready = await read();
    assert.equal(ready.cooldown, 0);
    assert.equal(ready.ringColor, 'ffd479');
    assert.ok(ready.pipScale > 0.45, `ready pip ${ready.pipScale}`);
    assert.ok(ready.ringOpacity > 0.6);
    passed.push('起始绞盘就绪：暖色环 + 满格充能盘');

    // 2) 打捞一次：拿到 3 木料 2 旧零件，进入冷却。
    const haul = await page.evaluate(() => window.__qa.performSalvage());
    assert.equal(haul, true);
    const cooling = await read();
    assert.equal(cooling.wood, 3);
    assert.equal(cooling.parts, 2);
    assert.equal(cooling.runs, 1);
    assert.ok(cooling.cooldown > 38 && cooling.cooldown <= 40, `cooldown ${cooling.cooldown}`);
    assert.equal(cooling.ringColor, '8fb0b6', 'cooling ring should turn cool');
    assert.ok(cooling.pipScale < 0.1, `cooling pip should be empty, got ${cooling.pipScale}`);
    passed.push('打捞产出 3 🪵 / 2 ⚙，并进入 40 秒冷却（环转为冷色、充能盘清空）');

    // 3) 冷却中再点：拒绝且不产出，并给出剩余秒数。
    const blocked = await page.evaluate(() => window.__qa.performSalvage());
    assert.equal(blocked, false);
    const afterBlocked = await read();
    assert.deepEqual(
      { wood: afterBlocked.wood, parts: afterBlocked.parts, runs: afterBlocked.runs },
      { wood: 3, parts: 2, runs: 1 }
    );
    const blockTips = await page.locator('.float-tip').allTextContents();
    assert.ok(
      blockTips.some(text => /绞盘冷却中 · \d+ 秒/.test(text)),
      `missing cooldown tip: ${blockTips.join(' | ')}`
    );
    passed.push('冷却期间重复打捞被拒绝，浮字显示剩余秒数');

    // 4) 充能进度随冷却推进：半程时充能盘明显长起来。
    await page.evaluate(() => { window.__qa.state.salvageCooldown = 20; });
    await page.waitForTimeout(220);
    const half = await read();
    assert.ok(half.pipScale > 0.2 && half.pipScale < 0.4, `half pip ${half.pipScale}`);
    passed.push('冷却过半时充能盘走到约一半，进度可见');

    // 5) 冷却结束自动就绪：出现提示，并可以再次打捞。
    await page.evaluate(() => { window.__qa.state.salvageCooldown = 0.2; });
    await page.waitForFunction(() => window.__qa.state.salvageCooldown === 0, { timeout: 5000 });
    await page.waitForTimeout(120);
    const tips = await page.locator('.float-tip').allTextContents();
    assert.ok(tips.some(text => text.includes('绞盘已就绪')), `missing ready tip: ${tips.join('|')}`);
    const refilled = await read();
    assert.equal(refilled.ringColor, 'ffd479');
    assert.ok(refilled.pipScale > 0.45);

    const second = await page.evaluate(() => window.__qa.performSalvage());
    assert.equal(second, true);
    const twice = await read();
    assert.deepEqual({ wood: twice.wood, parts: twice.parts, runs: twice.runs }, { wood: 6, parts: 4, runs: 2 });
    passed.push('冷却结束自动就绪并提示，可再次打捞');

    // 6) 20 分钟节奏：冷却式产出必须够跑完首个 Demo 的材料需求（17 木料 / 9 零件）。
    const budget = await page.evaluate(() => {
      const q = window.__qa, duration = q.SALVAGE_COOLDOWN, y = q.SALVAGE_YIELD;
      const hauls = Math.floor(20 * 60 / duration);
      return { hauls, wood: hauls * y.wood, parts: hauls * y.parts };
    });
    assert.ok(budget.wood >= 17, `wood ${budget.wood} < 17`);
    assert.ok(budget.parts >= 9, `parts ${budget.parts} < 9`);
    passed.push(`20 分钟可打捞约 ${budget.hauls} 次（${budget.wood} 🪵 / ${budget.parts} ⚙），足够覆盖全部建造与船只改造`);

    await page.screenshot({ path: 'outputs/salvage-cooldown.png' });

    assert.deepEqual(errors, []);
    const result = { passed, errors, budget };
    fs.writeFileSync('outputs/salvage-cooldown-results.json', JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result, null, 2));
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
