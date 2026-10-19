// 海面鱼群回归：撒点位置 / 只在靠过去后出图标 / 点图标捞鱼 / 捞完散群再重生。
//
// 用户要求（原话）：
//   「场景的其他地方，也要有鱼群，有鱼群的地方，可以划到那个位置，
//     划过去后就会有鱼群可以收获的图标，点击后就能收获鱼的资源，然后变少。」
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
    args: ['--use-gl=angle', '--use-angle=metal', '--enable-webgl', '--ignore-gpu-blocklist']
  });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    await page.route('**/index.html', async (route) => {
      const response = await route.fetch();
      let body = await response.text();
      body = body.replace('    const clock = new THREE.Clock();', '    window.qa={THREE,gameplay,scene,camera,controls};\n    const clock = new THREE.Clock();');
      await route.fulfill({ response, body });
    });
    await page.goto((process.env.APP_URL || 'http://127.0.0.1:8765') + '/index.html');
    await page.waitForFunction(() => window.qa?.gameplay?.art?.state, null, { timeout: 60000 });
    await page.waitForTimeout(2800);
    const passed = [];

    // —— 1) 鱼群撒在可航水面上，不挡船 ——
    const schools = await page.evaluate(() => {
      const g = window.qa.gameplay;
      g.probe.refreshBlockers();
      const blockers = g.probe.boatBlockers();
      return {
        count: g.fishSchools.items.length,
        noBlock: g.fishSchools.root.userData.noSailBlock === true,
        items: g.fishSchools.items.map((it) => ({
          n: it.fishCount,
          at: [+it.base.x.toFixed(1), +it.base.z.toFixed(1)],
          inBlocker: blockers.some((r) => it.base.x >= r.minX && it.base.x <= r.maxX && it.base.z >= r.minZ && it.base.z <= r.maxZ)
        }))
      };
    });
    assert.ok(schools.count >= 5, `鱼群数量偏少：${schools.count}`);
    assert.ok(schools.noBlock, '鱼群必须标 noSailBlock（不能挡船）');
    assert.ok(schools.items.every((s) => !s.inBlocker), '有鱼群落在障碍矩形里');
    assert.ok(schools.items.every((s) => s.n >= 3), `鱼群初始数量异常：${JSON.stringify(schools.items)}`);
    passed.push(`水面上有 ${schools.count} 群鱼，都不挡船`);

    // —— 2) 远处的鱼群不出图标；点鱼群本体（水面圆盘）能规划航线 ——
    const far = await page.evaluate(() => [...document.querySelectorAll('.fish-school-marker')].filter((e) => !e.hidden).length);
    assert.equal(far, 0, `还没划过去就出现了 ${far} 个收获图标`);
    passed.push('没靠过去时没有任何 🐟 收获图标');

    const pick = await page.evaluate(() => {
      const q = window.qa, T = q.THREE, g = q.gameplay;
      for (const it of g.fishSchools.items) {
        const p = new T.Vector3(it.base.x, it.base.y + 0.06, it.base.z).project(q.camera);
        if (Math.abs(p.x) > 0.9 || Math.abs(p.y) > 0.9) continue;
        const x = (p.x * 0.5 + 0.5) * innerWidth;
        const y = (-p.y * 0.5 + 0.5) * innerHeight;
        const hit = g.probe.targetAt(x, y);
        if (hit?.type === 'fish') return { id: it.id, x, y, n: it.fishCount };
      }
      return null;
    });
    assert.ok(pick, '默认视角里点不到任何鱼群（水面圆盘热区没生效）');
    await page.mouse.click(pick.x, pick.y);
    await page.waitForTimeout(400);
    const planned = await page.evaluate(() => {
      const a = window.qa.gameplay.art.state;
      return { mode: a.workerMode, intent: a.sailIntent };
    });
    assert.equal(planned.intent, 'fish', `点鱼群没进入捕鱼意图：${JSON.stringify(planned)}`);
    passed.push(`点鱼群 → ${planned.mode}（自动上船/划过去）`);

    // —— 3) 划到鱼群旁边：出现 🐟 图标，点一下鱼 -1 ——
    await page.waitForFunction(() => window.qa.gameplay.art.state.workerMode === 'BOAT_IDLE', null, { timeout: 150000 });
    await page.waitForTimeout(500);
    const near = await page.evaluate((id) => {
      const g = window.qa.gameplay;
      const it = g.fishSchools.items.find((x) => x.id === id);
      const el = [...document.querySelectorAll('.fish-school-marker')].find((e) => e.dataset.fishId === String(id));
      const boat = g.art.boatAnchorGroup.position;
      if (!el) return { marker: false };
      const r = el.getBoundingClientRect();
      const x = r.x + r.width / 2, y = r.y + r.height / 2;
      return {
        marker: !el.hidden,
        dist: it ? +Math.hypot(it.base.x - boat.x, it.base.z - boat.z).toFixed(2) : null,
        left: it ? it.fishCount : 0,
        x, y,
        hit: g.probe.targetAt(x, y)
      };
    }, pick.id);
    assert.ok(near.marker, '靠到鱼群旁边了，但 🐟 图标没出现');
    assert.ok(near.dist <= 7.2, `船离鱼群太远（${near.dist}m）`);
    assert.equal(near.hit?.type, 'fish', `点 🐟 图标没命中鱼群：${JSON.stringify(near.hit)}`);

    const before = await page.evaluate(() => window.qa.gameplay.art.state.fish);
    await page.mouse.click(near.x, near.y);
    await page.waitForTimeout(500);
    const after = await page.evaluate(({ id, left }) => {
      const g = window.qa.gameplay;
      const it = g.fishSchools.items.find((x) => x.id === id);
      return { fish: g.art.state.fish, left: it ? it.fishCount : 0, expect: left - 1 };
    }, { id: pick.id, left: near.left });
    assert.equal(after.fish, before + 1, `鱼资源没到账：${before} → ${after.fish}`);
    assert.equal(after.left, after.expect, `鱼群数量没减少：${near.left} → ${after.left}`);
    passed.push(`点 🐟 图标 → 鱼 +1，鱼群 ${near.left} → ${after.left} 条`);

    // —— 4) 捞完散群，并在别处重新聚一群 ——
    const respawn = await page.evaluate((id) => {
      const g = window.qa.gameplay;
      const it = g.fishSchools.items.find((x) => x.id === id);
      if (!it) return { missing: true };
      let guard = 0;
      while (it.fishCount > 0 && guard++ < 20) g.fishSchools.harvest(it, g.economy);
      const countAfterDeplete = g.fishSchools.items.length;
      g.fishSchools.spawn();
      return { countAfterDeplete, countAfterSpawn: g.fishSchools.items.length };
    }, pick.id);
    assert.ok(!respawn.missing, '鱼群提前消失了');
    assert.equal(respawn.countAfterSpawn, respawn.countAfterDeplete + 1, '捞完后没有重新聚群');
    passed.push(`捞完一群 → 散群（${respawn.countAfterDeplete} 群）→ 别处重新聚一群（${respawn.countAfterSpawn} 群）`);

    await page.screenshot({ path: 'outputs/fish-schools.png' });
    fs.writeFileSync('outputs/fish-schools.json', JSON.stringify({ schools, pick, near, after, respawn, passed, errors }, null, 2));
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({ passed, errors }, null, 2));
    console.log('\nPASS: 鱼群撒点 / 靠近才出图标 / 点图标捞鱼 / 捞完重聚');
  } finally { await browser.close(); }
})().catch((e) => { console.error(e); process.exitCode = 1; });
