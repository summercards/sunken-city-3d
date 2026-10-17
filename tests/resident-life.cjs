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
        '  window.__qa = { buildSites, state, activateSite, resident, windowGlow, lanternGroup, houseGroupRef };\n  syncCoinUI();\n  return {'
      );
      await route.fulfill({ response, body });
    });

    await page.goto(process.env.APP_URL || 'http://localhost:8765');
    await page.waitForFunction(() => window.__qa && document.querySelector('.resource-mini'));

    const initial = await page.evaluate(() => {
      const home = window.__qa.buildSites.find(s => s.id === 'home_cabin');
      return {
        level: home.level,
        residentVisible: window.__qa.resident.group.visible,
        glowVisible: window.__qa.windowGlow.parent.visible,
        lanternVisible: window.__qa.lanternGroup.parent.visible
      };
    });
    assert.deepEqual(initial, {
      level: 1,
      residentVisible: false,
      glowVisible: false,
      lanternVisible: false
    });
    passed.push('初始状态：木屋 Lv.1，无居民与暖灯');

    await page.evaluate(() => {
      const home = window.__qa.buildSites.find(s => s.id === 'home_cabin');
      window.__qa.activateSite(home);
    });

    await page.waitForFunction(() => {
      const home = window.__qa.buildSites.find(s => s.id === 'home_cabin');
      return home.level >= 2 && window.__qa.resident.group.visible;
    }, { timeout: 45000 });
    await page.waitForTimeout(1200);

    const arrived = await page.evaluate(() => {
      const home = window.__qa.buildSites.find(s => s.id === 'home_cabin');
      const resident = window.__qa.resident.group;
      const house = window.__qa.houseGroupRef;
      const worldPos = resident.getWorldPosition(new (resident.position.constructor)());
      const housePos = house.getWorldPosition(new (resident.position.constructor)());
      return {
        level: home.level,
        residentVisible: resident.visible,
        scale: resident.scale.x,
        glowVisible: window.__qa.windowGlow.parent.visible,
        lanternVisible: window.__qa.lanternGroup.parent.visible,
        aboveWater: worldPos.y > 1.5,
        distanceToHouse: Math.hypot(worldPos.x - housePos.x, worldPos.z - housePos.z),
        coins: window.__qa.state.coins,
        workerMode: window.__qa.state.workerMode
      };
    });
    assert.equal(arrived.level, 2);
    assert.equal(arrived.residentVisible, true);
    assert.ok(arrived.scale > 0.9, `resident scale ${arrived.scale} should reach 1`);
    assert.equal(arrived.glowVisible, true);
    assert.equal(arrived.lanternVisible, true);
    assert.equal(arrived.aboveWater, true, 'resident should stand above the water line');
    assert.ok(arrived.distanceToHouse < 5, `resident ${arrived.distanceToHouse} should stay on the cabin deck`);
    assert.equal(arrived.coins, 60);
    assert.equal(arrived.workerMode, 'IDLE_ASHORE');
    passed.push('木屋升级至 Lv.2 后居民出现在码头，窗灯与挂灯点亮');

    await page.waitForFunction(
      () => Math.abs(window.__qa.resident.arms[1].rotation.z) > 1.2,
      { timeout: 15000 }
    );
    passed.push('居民挥手待机动画持续更新');

    await page.screenshot({ path: 'outputs/resident-life.png' });

    assert.deepEqual(errors, []);
    const result = { passed, errors, arrived };
    fs.writeFileSync('outputs/resident-life-results.json', JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result, null, 2));
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
