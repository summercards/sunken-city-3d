// 上岸桩 + 漂浮物资的玩法回归。
//
// 三个要求（用户原话）：
//   1) 每个区域都有可以点的上岸点，点了自动寻路过去、角色上岸；
//   2) 海上的小木箱/木块不挡船（它们是物资，不是障碍）；
//   3) 只有真的开过去才收，不再"边划船边收集"（旧的按里程随机掉落已删除）。
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const WATER = 1.12;

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
    args: ['--use-gl=angle', '--use-angle=metal', '--enable-webgl', '--ignore-gpu-blocklist']
  });
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
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
    await page.waitForTimeout(2600);

    const passed = [];

    // —— 1) 五个区块都有上岸桩，且都带 noSailBlock（不挡船） ——
    const markers = await page.evaluate(() => {
      const out = [];
      window.qa.scene.traverse((o) => {
        if (o.name && o.name.startsWith('landing-')) {
          out.push({ zone: o.name.replace('landing-', ''), noBlock: !!o.userData.noSailBlock, y: +o.position.y.toFixed(2) });
        }
      });
      return out;
    });
    // zone1 有主码头 + 绞盘打捞台两个上岸点，其余四区各一个。
    assert.equal(markers.length, 6, `上岸桩数量应为 6，实际 ${markers.length}`);
    assert.ok(markers.every((m) => m.noBlock), '上岸桩必须标 noSailBlock');
    // 每个桩上方还要有一个可点的 ⚓️ 图标（纯图标、无外框；不接管指针，点击穿透给 canvas 路由）。
    const anchorIcons = await page.evaluate(() => [...document.querySelectorAll('.landing-marker')].map((el) => ({
      zone: el.dataset.landingZone,
      text: el.textContent,
      title: el.title,
      hidden: el.hidden,
      pointerEvents: getComputedStyle(el).pointerEvents,
      noBorder: getComputedStyle(el).borderTopWidth === '0px',
      transparentBg: getComputedStyle(el).backgroundColor === 'rgba(0, 0, 0, 0)',
      // 作者样式有 display:block，隐藏必须是真的 display:none（否则图标会永远钉在屏幕上）。
      hiddenByDisplay: getComputedStyle(el).display === 'none',
      hasSize: el.getBoundingClientRect().width > 20
    })));
    assert.equal(anchorIcons.length, 6, `⚓️ 图标数量应为 6，实际 ${anchorIcons.length}`);
    assert.ok(anchorIcons.every((a) => a.text.includes('⚓')), `图标内容不是锚：${JSON.stringify(anchorIcons.map((a) => a.text))}`);
    assert.ok(anchorIcons.every((a) => /上岸|未开放/.test(a.title)), `图标缺少上岸提示：${JSON.stringify(anchorIcons.map((a) => a.title))}`);
    assert.ok(anchorIcons.every((a) => a.pointerEvents === 'none'), '⚓️ 图标不能接管指针（会挡住小船与物资的点击）');
    assert.ok(anchorIcons.every((a) => a.noBorder && a.transparentBg), '⚓️ 图标不应有边框或底板');
    assert.ok(anchorIcons.every((a) => (a.hidden ? a.hiddenByDisplay : a.hasSize)), `⚓️ 图标显示/尺寸异常：${JSON.stringify(anchorIcons.map((a) => [a.zone, a.hidden, a.hiddenByDisplay, a.hasSize]))}`);
    passed.push('五个区块共 6 个可点的 ⚓️ 上岸图标（含绞盘打捞台，无外框、不挡其它点击）');

    // —— 2) 物资不挡船：船体高度带里没有任何矩形罩住箱子 ——
    const crateCheck = await page.evaluate(() => {
      const g = window.qa.gameplay;
      g.probe.refreshBlockers();
      const blockers = g.probe.boatBlockers();
      const crates = g.driftCrates.items.map((it) => {
        const p = it.group.position;
        const covered = blockers.some((r) => p.x >= r.minX && p.x <= r.maxX && p.z >= r.minZ && p.z <= r.maxZ);
        return { kind: it.kind, x: +p.x.toFixed(1), z: +p.z.toFixed(1), covered, hullClear: g.probe.hullClear(p.x, p.z, 0) };
      });
      return { count: g.driftCrates.count, crates };
    });
    assert.ok(crateCheck.count >= 8, `物资数量偏少：${crateCheck.count}`);
    assert.ok(crateCheck.crates.every((c) => !c.covered), `有物资被当成障碍：${JSON.stringify(crateCheck.crates.filter((c) => c.covered))}`);
    passed.push(`海上 ${crateCheck.count} 份漂浮物资都不进碰撞栅格（船可以直接开到箱子上）`);

    // —— 2.5) 同区块的第二块平台（绞盘打捞台）也要能上去 ——
    const salvageClick = await page.evaluate(() => {
      const el = document.querySelector('.landing-marker[data-landing-zone="zone1"][data-landing-spot="salvage"]');
      if (!el || el.hidden) return { onScreen: false };
      const r = el.getBoundingClientRect();
      const x = r.x + r.width / 2, y = r.y + r.height / 2;
      return { onScreen: true, x, y, hit: window.qa.gameplay.probe.targetAt(x, y) };
    });
    assert.ok(salvageClick.onScreen, '绞盘打捞台的 ⚓️ 没进画面');
    assert.equal(salvageClick.hit?.type, 'landing', `点打捞台图标没命中：${JSON.stringify(salvageClick.hit)}`);
    await page.mouse.click(salvageClick.x, salvageClick.y);
    await page.waitForFunction(() => {
      const s = window.qa.gameplay.art.state;
      return s.workerMode === 'IDLE_ASHORE' && s.currentZone === 'zone1' && s.landingId === 'salvage';
    }, null, { timeout: 150000 });
    const onSalvage = await page.evaluate(() => {
      const g = window.qa.gameplay;
      const spot = g.zones.landing('zone1', 'salvage');
      const p = g.art.explorerGroup.position;
      return {
        landing: g.art.state.landingId,
        gap: +Math.hypot(p.x - spot.landStand.x, p.z - spot.landStand.z).toFixed(2),
        region: g.probe.region('zone1_salvage')?.id || null
      };
    });
    assert.equal(onSalvage.landing, 'salvage');
    assert.ok(onSalvage.gap < 1.4, `没走到打捞台待机点（差 ${onSalvage.gap}m）`);
    passed.push(`同区块换平台：点绞盘打捞台 ⚓️ → 自动靠泊并走上甲板（离待机点 ${onSalvage.gap}m）`);

    // —— 3) 点上岸桩：岸上 → 上船 → 航行 → 靠岸 → 走上岸 ——
    const startZone = await page.evaluate(() => window.qa.gameplay.art.state.currentZone);
    assert.equal(startZone, 'zone1');
    // 把镜头对到 zone2 的上岸点，用真实鼠标点⚓️图标（玩家路径）。
    let picked = await page.evaluate(() => {
      const q = window.qa, g = q.gameplay;
      const z = g.zones.get('zone2');
      const target = z.dockEdge.clone();
      g.art.state.manualCamera = true;
      q.controls.target.copy(target);
      q.camera.position.set(target.x + 9, target.y + 14, target.z + 13);
      q.camera.lookAt(target);
      q.controls.update();
      q.scene.updateMatrixWorld(true);
      q.camera.updateMatrixWorld(true);
      return { x: 0, y: 0 };
    });
    await page.waitForTimeout(220);
    picked = await page.evaluate(() => {
      const q = window.qa, g = q.gameplay;
      const el = document.querySelector('.landing-marker[data-landing-zone="zone2"][data-landing-spot="main"]');
      if (!el || el.hidden) return { onScreen: false };
      const r = el.getBoundingClientRect();
      const x = r.x + r.width / 2, y = r.y + r.height / 2;
      return { x, y, onScreen: true, hit: g.probe.targetAt(x, y) };
    });
    assert.ok(picked.onScreen, '⚓️ 图标没进画面');
    assert.equal(picked.hit?.type, 'landing', `点图标没有命中上岸目标：${JSON.stringify(picked.hit)}`);
    await page.mouse.click(picked.x, picked.y);
    await page.waitForTimeout(250);
    const afterClick = await page.evaluate(() => ({ mode: window.qa.gameplay.art.state.workerMode, intent: window.qa.gameplay.art.state.sailIntent, target: window.qa.gameplay.art.state.targetZone }));
    assert.ok(['WALK_TO_BOAT', 'BOARDING', 'ROWING'].includes(afterClick.mode), `点上岸桩没开始出发：${afterClick.mode}`);
    assert.equal(afterClick.target, 'zone2');
    passed.push(`点击 zone2 上岸桩 → ${afterClick.mode}（目标 zone2）`);

    await page.waitForFunction(() => {
      const s = window.qa.gameplay.art.state;
      return s.currentZone === 'zone2' && s.workerMode === 'IDLE_ASHORE';
    }, null, { timeout: 180000 });
    const arrived = await page.evaluate(() => {
      const g = window.qa.gameplay, s = g.art.state;
      const z = g.zones.get('zone2');
      const boat = g.art.boatAnchorGroup.position;
      return {
        zone: s.currentZone,
        standGap: +Math.hypot(g.art.explorerGroup.position.x - z.landStand.x, g.art.explorerGroup.position.z - z.landStand.z).toFixed(2),
        boatGap: +Math.hypot(boat.x - z.boatPark.x, boat.z - z.boatPark.z).toFixed(2)
      };
    });
    assert.equal(arrived.zone, 'zone2');
    assert.ok(arrived.standGap < 1.0, `角色没走到待机点（差 ${arrived.standGap}m）`);
    assert.ok(arrived.boatGap < 0.8, `船没停进泊位（差 ${arrived.boatGap}m）`);
    passed.push(`自动航行到 zone2 并上岸：角色离待机点 ${arrived.standGap}m，船离泊位 ${arrived.boatGap}m`);

    // —— 4) 顺路航行不再白送物资（旧的按里程掉落已移除） ——
    const before = await page.evaluate(() => {
      const s = window.qa.gameplay.art.state;
      return { wood: s.wood, parts: s.parts };
    });
    await page.evaluate(() => window.qa.gameplay.travel('zone3', null));
    await page.waitForFunction(() => window.qa.gameplay.art.state.currentZone === 'zone3' && window.qa.gameplay.art.state.workerMode === 'IDLE_ASHORE', null, { timeout: 180000 });
    const afterSail = await page.evaluate(() => {
      const s = window.qa.gameplay.art.state;
      return { wood: s.wood, parts: s.parts };
    });
    assert.deepEqual(afterSail, before, `一趟航行自己长出了物资：${JSON.stringify(before)} → ${JSON.stringify(afterSail)}`);
    passed.push('整段航行不会自动产出物资（只有真的开到箱子旁才收）');

    // —— 5) 点物资：划过去才收，收完箱子消失 ——
    const cratePlan = await page.evaluate(() => {
      const q = window.qa, T = q.THREE, g = q.gameplay;
      const s = g.art.state;
      // 先回船上（点船 → 上船）
      s.targetZone = s.currentZone;
      s.sailIntent = 'board';
      s.sailTargetPos = null;
      s.walkTargetPos.copy(g.zones.get(s.currentZone).dockEdge);
      s.walkRegionId = g.probe.region('zone3_ground')?.id || null;
      s.workerMode = 'WALK_TO_BOAT';
      return { zone: s.currentZone };
    });
    await page.waitForFunction(() => window.qa.gameplay.art.state.workerMode === 'BOAT_IDLE', null, { timeout: 60000 });

    const crateInfo = await page.evaluate(() => {
      const q = window.qa, T = q.THREE, g = q.gameplay;
      const boat = g.art.boatAnchorGroup.position;
      const nearest = g.driftCrates.items
        .map((it) => ({ it, d: Math.hypot(it.group.position.x - boat.x, it.group.position.z - boat.z) }))
        .sort((a, b) => a.d - b.d)[0];
      const target = nearest.it.group.position.clone();
      g.art.state.manualCamera = true;
      q.controls.target.copy(target);
      q.camera.position.set(target.x + 7, target.y + 12, target.z + 10);
      q.camera.lookAt(target);
      q.controls.update();
      q.scene.updateMatrixWorld(true);
      q.camera.updateMatrixWorld(true);
      const p = target.clone().add(new T.Vector3(0, 0.25, 0)).project(q.camera);
      return {
        kind: nearest.it.kind,
        id: nearest.it.id,
        reward: g.driftCrates.KINDS[nearest.it.kind].reward,
        x: (p.x * 0.5 + 0.5) * innerWidth, y: (-p.y * 0.5 + 0.5) * innerHeight,
        onScreen: Math.abs(p.x) < 1 && Math.abs(p.y) < 1,
        total: g.driftCrates.count
      };
    });
    assert.ok(crateInfo.onScreen, '物资没进画面');
    const stockBefore = await page.evaluate(() => ({ ...window.qa.gameplay.art.state }));
    // 物资在水面上下浮动 ±0.45m，先算好的坐标点下去可能刚好错过箱子（偶发点空）。
    // 点之前按当前帧重新投影，直到命中 crate 为止。
    let crateClick = null;
    for (let attempt = 0; attempt < 6; attempt++) {
      crateClick = await page.evaluate((id) => {
        const q = window.qa, T = q.THREE, g = q.gameplay;
        const it = g.driftCrates.items.find((x) => x.id === id);
        if (!it) return null;
        const p = it.group.position.clone().add(new T.Vector3(0, 0.25, 0)).project(q.camera);
        const x = (p.x * 0.5 + 0.5) * innerWidth;
        const y = (-p.y * 0.5 + 0.5) * innerHeight;
        return { x, y, hit: g.probe.targetAt(x, y)?.type || null };
      }, crateInfo.id);
      if (crateClick?.hit === 'crate') break;
      await page.waitForTimeout(180);
    }
    assert.equal(crateClick?.hit, 'crate', `点物资没命中箱子：${JSON.stringify(crateClick)}`);
    await page.mouse.click(crateClick.x, crateClick.y);
    await page.waitForTimeout(300);
    const intent = await page.evaluate(() => window.qa.gameplay.art.state.sailIntent);
    assert.equal(intent, 'crate', `点物资没有进入拾取航线（intent=${intent}）`);
    await page.waitForFunction((id) => !window.qa.gameplay.driftCrates.items.some((it) => it.id === id), crateInfo.id, { timeout: 120000 });
    const stockAfter = await page.evaluate(() => ({ ...window.qa.gameplay.art.state }));
    for (const [key, amount] of Object.entries(crateInfo.reward)) {
      assert.ok(stockAfter[key] >= stockBefore[key] + amount, `${key} 没有到账（${stockBefore[key]} → ${stockAfter[key]}，应 +${amount}）`);
    }
    passed.push(`点物资 → 自动划过去拾取，${JSON.stringify(crateInfo.reward)} 到账，箱子消失`);

    // —— 6) 在船上点当前水域的上岸桩：直接靠岸下船 ——
    const dockClick = await page.evaluate(() => {
      const q = window.qa, T = q.THREE, g = q.gameplay;
      const zoneId = g.art.state.currentZone;
      const marker = q.scene.getObjectByName('landing-' + zoneId);
      const t = marker.getWorldPosition(new T.Vector3()).add(new T.Vector3(0, 0.9, 0));
      g.art.state.manualCamera = true;
      q.controls.minDistance = 1;
      q.controls.target.copy(t);
      q.camera.position.set(t.x + 6, t.y + 12, t.z + 9);
      q.camera.lookAt(t);
      q.controls.update();
      q.scene.updateMatrixWorld(true);
      q.camera.updateMatrixWorld(true);
      const p = t.clone().project(q.camera);
      return { zone: zoneId, x: (p.x * 0.5 + 0.5) * innerWidth, y: (-p.y * 0.5 + 0.5) * innerHeight, hit: g.probe.targetAt((p.x * 0.5 + 0.5) * innerWidth, (-p.y * 0.5 + 0.5) * innerHeight) };
    });
    assert.equal(dockClick.hit?.type, 'landing', `船上没点中上岸桩：${JSON.stringify(dockClick.hit)}`);
    await page.mouse.click(dockClick.x, dockClick.y);
    await page.waitForFunction(() => window.qa.gameplay.art.state.workerMode === 'IDLE_ASHORE', null, { timeout: 120000 });
    const beached = await page.evaluate(() => {
      const g = window.qa.gameplay, s = g.art.state;
      return { zone: s.currentZone, onFoot: g.art.explorerGroup.parent === window.qa.scene };
    });
    assert.equal(beached.zone, dockClick.zone);
    assert.ok(beached.onFoot, '角色没有走回岸上（还挂在船上）');
    passed.push(`船上点 ${dockClick.zone} 上岸桩 → 自动靠岸并下船`);

    await page.screenshot({ path: 'outputs/landing-and-crates.png' });
    fs.writeFileSync('outputs/landing-and-crates.json', JSON.stringify({
      markers, crateCount: crateCheck.count, arrived, afterClick, crate: crateInfo, passed, errors
    }, null, 2));
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({ passed, errors }, null, 2));
    console.log('\nPASS: 上岸桩点击寻路 / 物资不挡船 / 只有开到箱子旁才收');
  } finally { await browser.close(); }
})().catch((e) => { console.error(e); process.exitCode = 1; });
