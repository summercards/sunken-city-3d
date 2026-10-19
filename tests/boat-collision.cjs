// 航行碰撞回归：船壳（3.3m 长、1.5m 宽）在整段航行里都不许插进任何高出水面的实体。
//
// 以前的实现只做了「航迹绕行包围盒」，而且一旦膨胀后的矩形包含起点/终点就直接豁免，
// 于是贴着停泊位的大平台完全不参与计算 —— 肉眼看到的就是船直接从设施里穿过去。
// 现在有两层保障（gameplay.js）：
//   1) getSailObstacleRects 只豁免小件（系缆桩/浮标），大平台一律绕；
//   2) ROWING 每帧用真实船壳轮廓对实体做刚体推出。
//
// 判定分两段：
//   - 水道航段（离起点/终点 > 12m）：命中率必须为 0；
//   - 靠离泊段：允许 ≤ 3%（区块内部水巷只有 3~4m 宽，船壳贴着码头边缘是已知取舍）。
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const WATER = 1.12;
const LEGS = ['zone2', 'zone1', 'zone5', 'zone1', 'zone3', 'zone1', 'zone4', 'zone1'];
const BERTH_LIMIT_PCT = 3;

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
    args: ['--use-gl=angle', '--use-angle=metal', '--enable-webgl', '--ignore-gpu-blocklist']
  });
  try {
    const page = await browser.newPage({ viewport: { width: 1180, height: 760 } });
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
    await page.waitForTimeout(2000);

    await page.evaluate(() => {
      const g = window.qa.gameplay;
      g.art.state.farSeaUnlocked = true;
      g.economy.receive?.({ wood: 60, parts: 40, pearl: 10 });
      const art = g.art;
      window.__trail = [];
      window.__trailTimer = setInterval(() => {
        const p = art.boatAnchorGroup.position;
        if (art.state.workerMode === 'ROWING') window.__trail.push([p.x, p.z, art.boatAnchorGroup.rotation.y]);
      }, 60);
    });

    const results = [];
    for (const zoneId of LEGS) {
      await page.evaluate(() => { window.__trail = []; });
      await page.evaluate((id) => {
        window.qa.gameplay.art.state.manualCamera = false;
        return window.qa.gameplay.travel(id, null);
      }, zoneId);
      await page.waitForFunction(() => window.qa.gameplay.art.state.workerMode === 'IDLE_ASHORE', null, { timeout: 180000 });
      await page.waitForTimeout(400);

      const out = await page.evaluate(({ WATER }) => {
        const q = window.qa, T = q.THREE, art = q.gameplay.art;
        const pts = window.__trail.slice();
        q.scene.updateMatrixWorld(true);
        const meshes = [];
        q.scene.traverse((o) => {
          if (!o.isMesh || o.name === 'cartoon-water') return;
          for (let x = o; x; x = x.parent) {
            // 漂浮物资与上岸桩是「可穿过」的物件（userData.noSailBlock），不算障碍。
            if (!x.visible || x === art.boatAnchorGroup || x === art.explorerGroup || x.userData?.noSailBlock) return;
          }
          meshes.push(o);
        });
        const ray = new T.Raycaster();
        const down = new T.Vector3(0, -1, 0);
        const SX = 1.12, SZ = 1.16;
        const halfWidth = (z) => {
          if (z > 2.85 || z < -2.4) return -1;
          if (z > 1.4) return 1.32 * (2.85 - z) / 1.45;
          if (z > -0.6) return 1.22 + 0.1 * ((z + 0.6) / 2.0);
          return 0.95 + 0.27 * ((z + 2.4) / 1.8);
        };
        const nameOf = (o) => { const c = []; for (let x = o; x; x = x.parent) if (x.name) c.push(x.name); return c.slice(0, 2).join(' < ') || o.geometry?.type || 'mesh'; };
        const startPt = pts[0], endPt = pts[pts.length - 1];
        const bad = { open: [], berth: [] };
        const counts = { open: 0, berth: 0 };
        const badCounts = { open: 0, berth: 0 };
        for (const [px, pz, yaw] of pts) {
          const nearStart = startPt && Math.hypot(px - startPt[0], pz - startPt[1]) < 12;
          const nearEnd = endPt && Math.hypot(px - endPt[0], pz - endPt[1]) < 12;
          const phase = nearStart || nearEnd ? 'berth' : 'open';
          counts[phase]++;
          const cs = Math.cos(yaw), sn = Math.sin(yaw);
          let hit = null;
          for (let lz = -2.3; lz <= 2.8 && !hit; lz += 0.5) {
            const hw = halfWidth(lz);
            if (hw < 0) continue;
            for (let u = -hw; u <= hw; u += 0.4) {
              // THREE 的 rotation.y：局部 (x,z) → 世界 (x·cos + z·sin, -x·sin + z·cos)
              const wx = px + u * SX * cs + lz * SZ * sn;
              const wz = pz - u * SX * sn + lz * SZ * cs;
              ray.set(new T.Vector3(wx, WATER + 30, wz), down);
              ray.far = 60;
              // 只认船体高度带（水面 +0.15 ~ +1.25）：更高的悬挑屋檐船是从底下过去的。
              const h = ray.intersectObjects(meshes, false).find((it) => it.point.y > WATER + 0.15 && it.point.y < WATER + 1.25);
              if (h) { hit = { at: [+px.toFixed(1), +pz.toFixed(1)], x: +wx.toFixed(1), z: +wz.toFixed(1), y: +h.point.y.toFixed(2), who: nameOf(h.object) }; break; }
            }
          }
          if (hit) {
            badCounts[phase]++;
            if (bad[phase].length < 5) bad[phase].push(hit);
          }
        }
        const zone = q.gameplay.zones.get(q.gameplay.art.state.currentZone);
        return {
          zone: zone.id,
          frames: pts.length,
          openPct: counts.open ? +(badCounts.open / counts.open * 100).toFixed(1) : 0,
          berthPct: counts.berth ? +(badCounts.berth / counts.berth * 100).toFixed(1) : 0,
          openBad: bad.open,
          berthBad: bad.berth
        };
      }, { WATER });

      results.push(out);
      console.log(`${zoneId}: 航段 ${out.openPct}% 贴模（${out.frames} 帧）· 靠离泊 ${out.berthPct}%`);
    }

    // 停泊位本身不许压进模型（和 zone-config 的口径一致）
    const berths = await page.evaluate(({ WATER }) => {
      const q = window.qa, T = q.THREE;
      q.scene.updateMatrixWorld(true);
      const solids = [];
      q.scene.traverse((o) => {
        if (!o.isMesh || o.name === 'cartoon-water') return;
        for (let x = o; x; x = x.parent) {
          if (!x.visible || x === q.gameplay.art.boatAnchorGroup || x === q.gameplay.art.explorerGroup || x.userData?.noSailBlock) return;
        }
        const bb = new T.Box3().setFromObject(o);
        if (isFinite(bb.min.x) && !bb.isEmpty() && bb.max.y > WATER + 0.02) solids.push(bb);
      });
      const SX = 1.12, SZ = 1.16;
      const halfWidth = (z) => {
        if (z > 2.85 || z < -2.4) return -1;
        if (z > 1.4) return 1.32 * (2.85 - z) / 1.45;
        if (z > -0.6) return 1.22 + 0.1 * ((z + 0.6) / 2.0);
        return 0.95 + 0.27 * ((z + 2.4) / 1.8);
      };
      return q.gameplay.zones.list.map((zone) => {
        let hit = 0, total = 0;
        const cs = Math.cos(zone.boatYaw), sn = Math.sin(zone.boatYaw);
        for (let lz = -2.3; lz <= 2.8; lz += 0.4) {
          const hw = halfWidth(lz);
          if (hw < 0) continue;
          for (let u = -hw; u <= hw; u += 0.32) {
            total++;
            const wx = zone.boatPark.x + u * SX * cs + lz * SZ * sn;
            const wz = zone.boatPark.z - u * SX * sn + lz * SZ * cs;
            for (const bb of solids) {
              if (wx >= bb.min.x && wx <= bb.max.x && wz >= bb.min.z && wz <= bb.max.z) { hit++; break; }
            }
          }
        }
        return { id: zone.id, pct: total ? +(hit / total * 100).toFixed(1) : 0 };
      });
    }, { WATER });

    await page.evaluate(() => clearInterval(window.__trailTimer));
    await page.screenshot({ path: 'outputs/boat-collision-regression.png' });
    fs.writeFileSync('outputs/boat-collision-results.json', JSON.stringify({ results, berths, errors }, null, 2));

    const failures = [];
    for (const r of results) {
      if (r.frames < 20) failures.push(`${r.zone} 航迹只采到 ${r.frames} 帧（航行没有真的发生）`);
      if (r.openPct > 0) failures.push(`${r.zone} 水道航段 ${r.openPct}% 的帧船壳插进模型：${r.openBad.map((b) => `(${b.at})→${b.who}@${b.y}`).join(' ')}`);
      if (r.berthPct > BERTH_LIMIT_PCT) failures.push(`${r.zone} 靠离泊段 ${r.berthPct}% 的帧压进模型（上限 ${BERTH_LIMIT_PCT}%）`);
    }
    for (const b of berths) {
      if (b.pct > 0) failures.push(`${b.id} 停泊位船壳仍压进模型 ${b.pct}%`);
    }
    assert.deepEqual(failures, []);
    assert.deepEqual(errors, []);

    console.log('\nPASS: 全程航行船壳不穿模，五个停泊位船壳 0 侵入');
  } finally { await browser.close(); }
})().catch((e) => { console.error(e); process.exitCode = 1; });
