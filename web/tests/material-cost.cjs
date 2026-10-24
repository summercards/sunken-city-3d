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
        '  window.__qa = { buildSites, state, activateSite, getSiteAction, performSalvage, upgradeShip, salvageCooldown: SALVAGE_COOLDOWN, salvageYield: SALVAGE_YIELD };\n  syncCoinUI();\n  return {'
      );
      await route.fulfill({ response, body });
    });

    await page.goto(process.env.APP_URL || 'http://localhost:8765');
    await page.waitForFunction(() => window.__qa && document.querySelector('.resource-mini'));
    await page.waitForTimeout(600);

    const snapshot = () => page.evaluate(() => {
      const home = window.__qa.buildSites.find(s => s.id === 'home_cabin');
      const station = window.__qa.buildSites.find(s => s.id === 'yokohama_station');
      const action = window.__qa.getSiteAction(home);
      return {
        coins: window.__qa.state.coins,
        wood: window.__qa.state.wood,
        parts: window.__qa.state.parts,
        homeLevel: home.level,
        stationLevel: station.level,
        workerMode: window.__qa.state.workerMode,
        missing: action.missing,
        available: action.available
      };
    });

    // 1) 没有木料时，木屋升级必须被挡住，并明确说出缺什么。
    const before = await snapshot();
    assert.equal(before.wood, 0);
    assert.deepEqual(before.missing, { wood: 2 });
    assert.equal(before.available, false);
    passed.push('建造费用包含木料：0 木料时升级不可用，缺口为 2 🪵');

    await page.evaluate(() => {
      const home = window.__qa.buildSites.find(s => s.id === 'home_cabin');
      home.storedCoins = 0; // 排除“收取优先”，本用例只测材料门槛
      window.__qa.activateSite(home);
    });
    await page.waitForTimeout(300);
    const blocked = await snapshot();
    assert.equal(blocked.homeLevel, 1);
    assert.equal(blocked.coins, 80, 'blocked build must not charge coins');
    assert.equal(blocked.workerMode, 'IDLE_ASHORE');
    const tipTexts = await page.locator('.float-tip').allTextContents();
    assert.ok(tipTexts.some(text => /还差 2 🪵/.test(text)), `missing gap tip: ${tipTexts.join(' | ')}`);
    await page.screenshot({ path: 'outputs/material-missing-tip.png' });
    passed.push('点击不可用建筑时场景浮字提示缺口，且不扣海贝');

    // 2) 打捞一次后材料够用，建造同时扣海贝与木料。
    await page.evaluate(() => window.__qa.performSalvage());
    const stocked = await snapshot();
    assert.equal(stocked.wood, 3);
    assert.equal(stocked.parts, 2);
    assert.equal(stocked.available, true);
    assert.deepEqual(stocked.missing, {});

    await page.evaluate(() => {
      const home = window.__qa.buildSites.find(s => s.id === 'home_cabin');
      home.storedCoins = 0;
      window.__qa.activateSite(home);
    });
    await page.waitForTimeout(120);
    const charged = await snapshot();
    assert.equal(charged.coins, 60);
    assert.equal(charged.wood, 1);
    assert.ok(['WALK_TO_SITE', 'BUILDING'].includes(charged.workerMode), `unexpected mode ${charged.workerMode}`);
    passed.push('建造同时扣除 20 🐚 与 2 🪵');

    // 3) 重复点击不会二次扣费（航行途中同样有效）。
    //    先把产出清零，确保这次点击走的是“升级”而不是“收取”（收取优先是另一条已覆盖的规则）。
    await page.evaluate(() => {
      const home = window.__qa.buildSites.find(s => s.id === 'home_cabin');
      home.storedCoins = 0;
      window.__qa.activateSite(home);
      window.__qa.activateSite(home);
    });
    await page.waitForTimeout(150);
    const repeat = await snapshot();
    assert.equal(repeat.coins, 60);
    assert.equal(repeat.wood, 1);
    passed.push('重复点击同一建设点不会重复扣费');

    // 4) 建造完成后木屋 Lv.2，材料只结算一次。
    await page.waitForFunction(() => {
      const home = window.__qa.buildSites.find(s => s.id === 'home_cabin');
      return home.level === 2;
    }, { timeout: 45000 });
    const done = await snapshot();
    assert.equal(done.wood, 1);
    assert.equal(done.coins, 60);
    passed.push('木屋完成 Lv.2，材料余额保持 1 🪵');

    // 5) 站台第一阶段需要 2 木料：1 木料时不可用，补一次打捞后可用。
    //    这里只验证材料门槛；打捞冷却本身由 tests/salvage-cooldown.cjs 覆盖，
    //    所以先把冷却清零，避免两件事耦合在一起。
    const stationBlocked = await page.evaluate(() => {
      const station = window.__qa.buildSites.find(s => s.id === 'yokohama_station');
      const action = window.__qa.getSiteAction(station);
      return { available: action.available, missing: action.missing, stage: action.stage.cost };
    });
    assert.deepEqual(stationBlocked.missing, { wood: 1 });
    assert.equal(stationBlocked.available, false);

    await page.evaluate(() => {
      window.__qa.state.salvageCooldown = 0;
      window.__qa.performSalvage();
    });
    const stationReady = await page.evaluate(() => {
      const station = window.__qa.buildSites.find(s => s.id === 'yokohama_station');
      const action = window.__qa.getSiteAction(station);
      return { available: action.available, wood: window.__qa.state.wood };
    });
    assert.equal(stationReady.available, true);
    assert.equal(stationReady.wood, 4);
    passed.push('站台第一阶段同样受木料约束，补齐后恢复可用');

    // 6) 无障碍标签同步说明费用与缺口（把木料清零后由 UI 重新计算）。
    await page.evaluate(() => { window.__qa.state.wood = 0; });
    await page.waitForTimeout(120);
    const labels = await page.evaluate(() => {
      const orb = document.querySelector('[data-site-id="rooftop_planter"]');
      return { label: orb.getAttribute('aria-label'), disabled: orb.getAttribute('aria-disabled') };
    });
    assert.match(labels.label, /还差 2 🪵/);
    assert.equal(labels.disabled, 'true');
    passed.push('建筑操作点的无障碍标签写明缺少的材料');

    // 7) 经济不变量：20 分钟内的冷却式打捞产出必须覆盖“全部建设 + 船只改造”的材料需求。
    const budget = await page.evaluate(() => {
      const need = { wood: 0, parts: 0, coins: 0 };
      for (const site of window.__qa.buildSites) {
        for (const stage of site.stages) {
          if (!stage.cost) continue;
          need.coins += stage.cost;
          for (const [key, amount] of Object.entries(stage.materials || {})) need[key] += amount;
        }
      }
      need.wood += 6;   // upgradeShip
      need.parts += 4;
      const hauls = Math.floor((20 * 60) / window.__qa.salvageCooldown);
      const supply = {
        wood: hauls * window.__qa.salvageYield.wood,
        parts: hauls * window.__qa.salvageYield.parts,
        coins: 80 + 20 * 10,
        hauls
      };
      return { need, supply };
    });
    assert.ok(budget.supply.wood >= budget.need.wood, `wood supply ${budget.supply.wood} < ${budget.need.wood}`);
    assert.ok(budget.supply.parts >= budget.need.parts, `parts supply ${budget.supply.parts} < ${budget.need.parts}`);
    assert.ok(budget.supply.coins >= budget.need.coins, `coin supply ${budget.supply.coins} < ${budget.need.coins}`);
    passed.push(`经济不变量成立：全部建造需 ${budget.need.wood} 🪵 / ${budget.need.parts} ⚙，20 分钟 ${budget.supply.hauls} 次打捞可得 ${budget.supply.wood} 🪵 / ${budget.supply.parts} ⚙`);

    await page.screenshot({ path: 'outputs/material-cost.png' });

    assert.deepEqual(errors, []);
    const result = { passed, errors, final: await snapshot() };
    fs.writeFileSync('outputs/material-cost-results.json', JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result, null, 2));
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
