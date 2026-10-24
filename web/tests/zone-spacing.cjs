// 区块间距：任意两个区块之间必须留出至少 2 个船身宽的通航净空。
// 船体实际宽约 3.0m（局部 ±1.32 × scale 1.12），所以净空下限 = 6m。
// 同时检查背景遗迹不会挤进区块之间的航道。
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const WATER = 1.12;
const BOAT_BEAM = 3.0;
const MIN_CLEAR = BOAT_BEAM * 2;

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
    args: ['--use-gl=angle', '--use-angle=metal', '--enable-webgl', '--ignore-gpu-blocklist']
  });
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.route('**/index.html', async route => {
      const response = await route.fetch();
      let body = await response.text();
      body = body.replace('    const clock = new THREE.Clock();', '    window.qa={THREE,gameplay,scene,camera,controls};\n    const clock = new THREE.Clock();');
      await route.fulfill({ response, body });
    });
    await page.goto((process.env.APP_URL || 'http://127.0.0.1:8765') + '/index.html');
    await page.waitForFunction(() => window.qa?.gameplay?.art?.state, null, { timeout: 60000 });
    await page.waitForTimeout(2500);

    const report = await page.evaluate(({ WATER, BOAT_BEAM }) => {
      const q = window.qa, T = q.THREE, art = q.gameplay.art, g = q.gameplay;
      const boat = art.boatAnchorGroup, exp = art.explorerGroup;
      q.scene.updateMatrixWorld(true);

      const site = (id) => art.buildSites.find(s => s.id === id);
      // 木屋那栋楼由多个 open-industrial-ruin 组成，全部算进 zone1。
      const ruins = [];
      q.scene.traverse(o => { if (o.isGroup && o.name === 'open-industrial-ruin') ruins.push(o); });
      // 每个区块自己的模型根（改布局时这里要跟着补）
      const roots = {
        zone1: [
          site('home_cabin')?.hitRoots?.[0],
          ...ruins,
          q.scene.getObjectByName('C · 绞盘打捞台'),
          q.scene.getObjectByName('D · 交易码头')
        ],
        zone2: [art.zone2Root, site('yokohama_station')?.hitRoots?.[0], site('yokohama_station')?.hitRoots?.[1]],
        zone3: [site('rooftop_planter')?.hitRoots?.[0], art.zone3Root],
        zone4: [art.zone4Root],
        zone5: [site('shallow_aquaculture')?.hitRoots?.[0]]
      };
      // 背景遗迹（不算玩法区块，但会挡航道）
      const scenery = [];
      q.scene.traverse(o => {
        if (!o.isGroup || !o.name) return;
        if (/^reference-|^peripheral-ruin|^submerged-roof/.test(o.name)) scenery.push(o);
      });

      const STEP = 0.5, MIN = -95, MAX = 95, N = Math.round((MAX - MIN) / STEP);
      function rasterize(rootList) {
        const grid = new Uint8Array(N * N);
        const seen = new Set();
        for (const root of rootList) {
          if (!root || seen.has(root)) continue;
          seen.add(root);
          root.traverse(o => {
            if (!o.isMesh) return;
            for (let x = o; x; x = x.parent) if (!x.visible) return;
            const bb = new T.Box3().setFromObject(o);
            if (!isFinite(bb.min.x) || bb.isEmpty() || bb.max.y <= WATER + 0.02) return;
            const i0 = Math.max(0, Math.floor((bb.min.x - MIN) / STEP)), i1 = Math.min(N - 1, Math.ceil((bb.max.x - MIN) / STEP));
            const j0 = Math.max(0, Math.floor((bb.min.z - MIN) / STEP)), j1 = Math.min(N - 1, Math.ceil((bb.max.z - MIN) / STEP));
            if ((i1 - i0) > 320 || (j1 - j0) > 320) return;
            for (let j = j0; j <= j1; j++) for (let i = i0; i <= i1; i++) grid[j * N + i] = 1;
          });
        }
        return grid;
      }
      function bboxOf(grid, pts) {
        let x0 = 1e9, x1 = -1e9, z0 = 1e9, z1 = -1e9, cells = 0;
        for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) {
          if (!grid[j * N + i]) continue;
          cells++;
          const wx = MIN + (i + 0.5) * STEP, wz = MIN + (j + 0.5) * STEP;
          if (wx < x0) x0 = wx; if (wx > x1) x1 = wx;
          if (wz < z0) z0 = wz; if (wz > z1) z1 = wz;
        }
        return cells ? { x: [+x0.toFixed(1), +x1.toFixed(1)], z: [+z0.toFixed(1), +z1.toFixed(1)], area: +(cells * STEP * STEP).toFixed(0) } : null;
      }
      const cellsOf = (grid) => {
        const out = [];
        for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) if (grid[j * N + i]) out.push([i, j]);
        return out;
      };
      // 两个占据图之间的最小间隙（抽样以控制成本，最小间隙处一定会被取到附近的样本）
      function minGap(a, b) {
        const ca = cellsOf(a), cb = cellsOf(b);
        if (!ca.length || !cb.length) return null;
        let best = Infinity;
        const stride = Math.max(1, Math.floor(Math.sqrt(ca.length * cb.length) / 60000));
        for (let i = 0; i < ca.length; i += stride) {
          for (let j = 0; j < cb.length; j += stride) {
            const dx = ca[i][0] - cb[j][0], dz = ca[i][1] - cb[j][1];
            const d2 = dx * dx + dz * dz;
            if (d2 < best) best = d2;
          }
        }
        return +(Math.sqrt(best) * STEP).toFixed(2);
      }

      const masks = {}, boxes = {};
      for (const [id, list] of Object.entries(roots)) {
        masks[id] = rasterize(list);
        boxes[id] = bboxOf(masks[id]);
      }
      const ids = Object.keys(masks).filter(id => boxes[id]);
      const gaps = [];
      for (let i = 0; i < ids.length; i++) for (let j = i + 1; j < ids.length; j++) {
        gaps.push({ a: ids[i], b: ids[j], gap: minGap(masks[ids[i]], masks[ids[j]]) });
      }
      // 背景遗迹与区块的净距
      const sceneryHits = [];
      for (const s of scenery) {
        const m = rasterize([s]);
        const bb = bboxOf(m);
        if (!bb) continue;
        for (const id of ids) {
          const gap = minGap(m, masks[id]);
          if (gap !== null && gap < 6) sceneryHits.push({ scenery: s.name, zone: id, gap, bb });
        }
      }
      return {
        boxes, gaps: gaps.sort((x, y) => x.gap - y.gap),
        sceneryHits: sceneryHits.sort((x, y) => x.gap - y.gap),
        beam: BOAT_BEAM
      };
    }, { WATER, BOAT_BEAM });

    fs.writeFileSync('outputs/zone-spacing-results.json', JSON.stringify(report, null, 2));

    console.log('=== 区块实体范围 ===');
    for (const [id, b] of Object.entries(report.boxes)) {
      if (!b) { console.log(id + '  (无实体)'); continue; }
      console.log(id + '  x[' + b.x.join(', ') + ']  z[' + b.z.join(', ') + ']  ' + b.area + 'm²');
    }
    console.log('\n=== 区块间距（船身宽 ' + report.beam + 'm，下限 ' + MIN_CLEAR + 'm）===');
    for (const g of report.gaps) console.log('  ' + g.a + ' | ' + g.b + '  ' + g.gap + (g.gap < MIN_CLEAR ? '  <<< 不足' : ''));
    if (report.sceneryHits.length) {
      console.log('\n=== 背景遗迹挤进航道（< 6m）===');
      for (const h of report.sceneryHits) console.log('  ' + h.scenery + ' vs ' + h.zone + '  ' + h.gap);
    }

    const failures = [];
    for (const g of report.gaps) {
      if (g.gap < MIN_CLEAR) failures.push(g.a + ' 与 ' + g.b + ' 只隔 ' + g.gap + 'm（需 ≥ ' + MIN_CLEAR + 'm = 2 船身宽）');
    }
    for (const h of report.sceneryHits) {
      failures.push('背景遗迹 ' + h.scenery + ' 离 ' + h.zone + ' 只有 ' + h.gap + 'm');
    }
    assert.deepEqual(failures, []);
    assert.deepEqual(errors, []);

    await page.screenshot({ path: 'outputs/zone-spacing-regression.png' });
    const min = report.gaps[0];
    console.log('\nPASS: 最窄通道 ' + min.a + ' | ' + min.b + ' = ' + min.gap + 'm（≥ ' + MIN_CLEAR + 'm）');
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
