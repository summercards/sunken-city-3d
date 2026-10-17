// 真实走一遍：从木屋出发，逐个区块航行 → 上岸 → 走到待机点。
// 断言落脚点始终踩在模型表面上（不悬空、不陷进去），并且最终停在区块配置的待机点附近。
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const TARGETS = ['zone2', 'zone3', 'zone5', 'zone4'];
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
    page.on('pageerror', e => errors.push(e.message));
    await page.route('**/index.html', async route => {
      const response = await route.fetch();
      let body = await response.text();
      body = body.replace('    const clock = new THREE.Clock();', '    window.qa={THREE,gameplay,scene,camera,controls};\n    const clock = new THREE.Clock();');
      await route.fulfill({ response, body });
    });
    await page.goto((process.env.APP_URL || 'http://127.0.0.1:8765') + '/index.html');
    await page.waitForFunction(() => window.qa?.gameplay?.art?.state, null, { timeout: 60000 });
    await page.waitForTimeout(2000);

    // 直接给足资源与远海权限，免得被经济条件挡住航行
    await page.evaluate(() => {
      const g = window.qa.gameplay;
      g.art.state.farSeaUnlocked = true;
      g.economy.receive?.({ wood: 60, parts: 40, pearl: 10 });
    });

    const groundProbe = () => {
      const q = window.qa, T = q.THREE, art = q.gameplay.art;
      const meshes = [];
      q.scene.updateMatrixWorld(true);
      q.scene.traverse(o => {
        if (!o.isMesh || o.name === 'cartoon-water') return;
        for (let p = o; p; p = p.parent) if (!p.visible || p === art.boatAnchorGroup || p === art.explorerGroup) return;
        meshes.push(o);
      });
      return { meshes, T };
    };

    // 记录航行轨迹（船位 + 朝向），到站后用射线逐点检查有没有把船开进建筑。
    await page.evaluate(() => {
      const art = window.qa.gameplay.art;
      window.__trail = [];
      window.__trailTimer = setInterval(() => {
        const p = art.boatAnchorGroup.position, s = art.state.workerMode;
        if (s === 'ROWING' || s === 'BOATING') window.__trail.push([p.x, p.z, art.boatAnchorGroup.rotation.y]);
      }, 100);
    });

    const results = [];
    for (const zoneId of TARGETS) {
      await page.evaluate(() => { window.__trail = []; });
      const started = await page.evaluate((id) => {
        const g = window.qa.gameplay;
        g.art.state.manualCamera = false;
        return g.travel(id, null);
      }, zoneId);
      assert.notEqual(started, false, `无法前往 ${zoneId}`);

      await page.waitForFunction(() => {
        const s = window.qa.gameplay.art.state;
        return s.workerMode === 'IDLE_ASHORE';
      }, null, { timeout: 90000 });
      await page.waitForTimeout(600);

      const out = await page.evaluate(({ id, WATER }) => {
        const q = window.qa, T = q.THREE, art = q.gameplay.art, g = q.gameplay;
        const state = art.state;
        const zone = g.zones.get(id);
        const pos = art.explorerGroup.position.clone();
        const boat = art.boatAnchorGroup.position.clone();

        const meshes = [];
        q.scene.updateMatrixWorld(true);
        q.scene.traverse(o => {
          if (!o.isMesh || o.name === 'cartoon-water') return;
          for (let p = o; p; p = p.parent) if (!p.visible || p === art.boatAnchorGroup || p === art.explorerGroup) return;
          meshes.push(o);
        });
        // 按该区块地块的 span 窗口取最高可站立面，和游戏运行时的判定完全一致。
        const span = (g.zones.walkRegions.find(r => r.zone === id && r.contains(pos)) || { span: [1.15, 6] }).span;
        const ray = new T.Raycaster(new T.Vector3(pos.x, 30, pos.z), new T.Vector3(0, -1, 0), 0, 60);
        const nm = new T.Matrix3();
        let surface = null;
        for (const h of ray.intersectObjects(meshes, false)) {
          if (!h.face || h.point.y <= WATER + 0.02) continue;
          if (h.point.y < span[0] || h.point.y > span[1]) continue;
          nm.getNormalMatrix(h.object.matrixWorld);
          const n = h.face.normal.clone().applyMatrix3(nm).normalize();
          if (n.y < 0.7) continue;
          if (surface === null || h.point.y > surface) surface = h.point.y;
        }

        return {
          zone: id,
          currentZone: state.currentZone,
          mode: state.workerMode,
          pos: pos.toArray().map(v => +v.toFixed(2)),
          surface: surface === null ? null : +surface.toFixed(2),
          footDelta: surface === null ? null : +(pos.y - surface).toFixed(2),
          boat: boat.toArray().map(v => +v.toFixed(2)),
          parkConfig: [zone.boatPark.x, zone.boatPark.z],
          boatGap: +Math.hypot(boat.x - zone.boatPark.x, boat.z - zone.boatPark.z).toFixed(2),
          standGap: +Math.hypot(pos.x - zone.landStand.x, pos.z - zone.landStand.z).toFixed(2),
          onRegion: g.zones.walkRegions.some(r => r.id === state.walkRegionId)
        };
      }, { id: zoneId, WATER });

      const trail = await page.evaluate(({ WATER }) => {
        const q = window.qa, T = q.THREE, art = q.gameplay.art;
        const pts = window.__trail.slice();
        if (!pts.length) return { samples: 0, blocked: 0, blockedPct: 0, worst: [] };
        q.scene.updateMatrixWorld(true);
        const meshes = [];
        q.scene.traverse(o => {
          if (!o.isMesh || o.name === 'cartoon-water') return;
          for (let x = o; x; x = x.parent) {
            if (!x.visible || x === art.boatAnchorGroup || x === art.explorerGroup) return;
          }
          meshes.push(o);
        });
        const ray = new T.Raycaster();
        const down = new T.Vector3(0, -1, 0);
        // 船壳轮廓上的取样点（局部 x, z）
        const probes = [[0, 2.3], [0.9, 1.2], [-0.9, 1.2], [1.2, -0.3], [-1.2, -0.3], [0, -1.9]];
        const blockedSpots = [];
        let blocked = 0, counted = 0;
        const startPt = pts[0], endPt = pts[pts.length - 1];
        for (const [px, pz, yaw] of pts) {
          // 起终点附近允许正常靠岸接触，只考核水道中的航段。
          if (Math.hypot(px - startPt[0], pz - startPt[1]) < 12) continue;
          if (Math.hypot(px - endPt[0], pz - endPt[1]) < 12) continue;
          counted++;
          const cs = Math.cos(yaw), sn = Math.sin(yaw);
          let hit = false;
          for (const [lx, lz] of probes) {
            // THREE 的 rotation.y：局部 (x,z) → 世界 (x·cos + z·sin, -x·sin + z·cos)
            const wx = px + lx * cs + lz * sn;
            const wz = pz - lx * sn + lz * cs;
            ray.set(new T.Vector3(wx, 30, wz), down);
            ray.far = 60;
            // 只认船体高度带内的实体；头顶高处的悬空废墟不算挡路。
            // 下限抬到船体吃水线以上：浮叶、水草这类贴水装饰不算挡路。
            const hits = ray.intersectObjects(meshes, false).filter(h => h.point.y > WATER + 0.45 && h.point.y < WATER + 2.4);
            if (hits.length) {
              hit = true;
              if (blockedSpots.length < 5) {
                const nm = (o) => { const c = []; for (let x = o; x; x = x.parent) if (x.name) c.push(x.name); return c.slice(0, 2).join(' < ') || o.geometry?.type || 'mesh'; };
                blockedSpots.push({ at: [+px.toFixed(1), +pz.toFixed(1)], probe: [lx, lz], y: +hits[0].point.y.toFixed(2), who: nm(hits[0].object) });
              }
              break;
            }
          }
          if (hit) blocked++;
        }
        return { samples: pts.length, counted, blocked, blockedPct: counted ? +(blocked / counted * 100).toFixed(1) : 0, worst: blockedSpots };
      }, { WATER });
      out.trail = trail;
      results.push(out);
      console.log(`${zoneId}: 到站=${out.currentZone} 落脚y=${out.pos[1]} 表面=${out.surface} 差=${out.footDelta} 离待机点=${out.standGap} 离停泊位=${out.boatGap} 航迹${trail.samples}点/贴模型${trail.blockedPct}%`);
    }

    fs.writeFileSync('outputs/zone-travel-results.json', JSON.stringify({ results, errors }, null, 2));

    const failures = [];
    for (const r of results) {
      if (r.currentZone !== r.zone) failures.push(`${r.zone} 没有真的到站（当前 ${r.currentZone}）`);
      if (r.surface === null) failures.push(`${r.zone} 落脚点下方没有地面`);
      else if (Math.abs(r.footDelta) > 0.2) failures.push(`${r.zone} 落脚高度与模型差 ${r.footDelta}m（悬空或陷入）`);
      if (r.boatGap > 0.8) failures.push(`${r.zone} 船停在配置停泊位 ${r.boatGap}m 之外`);
      if (r.standGap > 2.0) failures.push(`${r.zone} 小人停在待机点 ${r.standGap}m 之外`);
      if (r.trail && r.trail.counted > 10 && r.trail.blockedPct > 5) {
        failures.push(`${r.zone} 航行途中 ${r.trail.blockedPct}% 的航迹贴进了模型（${r.trail.worst.map(p => `(${p.at[0]},${p.at[1]})→${p.who}`).join(' ')}）`);
      }
    }
    assert.deepEqual(failures, []);
    assert.deepEqual(errors, []);

    await page.evaluate(() => clearInterval(window.__trailTimer));
    await page.screenshot({ path: 'outputs/zone-travel-regression.png' });
    console.log('\nPASS: 逐区块航行、上岸、走到待机点，落脚高度全部贴合模型，无运行时错误');
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
