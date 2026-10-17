// 区块配置一致性：zones.js 里写的每一条配置，都要真的落在模型上。
// 增删或搬动区块后跑这一条，就能立刻知道哪里飘了、哪里插进模型了。
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

    const report = await page.evaluate(({ WATER }) => {
      const q = window.qa, T = q.THREE, scene = q.scene, art = q.gameplay.art;
      const zones = q.gameplay.zones;
      const boat = art.boatAnchorGroup, exp = art.explorerGroup;
      scene.updateMatrixWorld(true);

      // 静态可站立面：排除水面、船、角色、不可见物
      const meshes = [];
      scene.traverse(o => {
        if (!o.isMesh || o === undefined || o.name === 'cartoon-water') return;
        for (let p = o; p; p = p.parent) if (!p.visible || p === boat || p === exp) return;
        meshes.push(o);
      });
      // 会挡船的实体：任何高出水面的东西（AABB）
      const solids = [];
      for (const o of meshes) {
        const bb = new T.Box3().setFromObject(o);
        if (isFinite(bb.min.x) && !bb.isEmpty() && bb.max.y > WATER + 0.02) solids.push(bb);
      }

      const ray = new T.Raycaster();
      const down = new T.Vector3(0, -1, 0);
      const nm = new T.Matrix3();
      function surfacesAt(x, z) {
        ray.set(new T.Vector3(x, 60, z), down);
        ray.far = 120;
        const out = [];
        for (const h of ray.intersectObjects(meshes, false)) {
          if (!h.face || h.point.y <= WATER + 0.02) continue;
          nm.getNormalMatrix(h.object.matrixWorld);
          const n = h.face.normal.clone().applyMatrix3(nm).normalize();
          if (n.y < 0.7) continue;
          out.push(h.point.y);
        }
        return out.sort((a, b) => b - a);
      }
      function topIn(span, x, z) {
        const hits = surfacesAt(x, z).filter(y => y >= span[0] && y <= span[1]);
        return hits.length ? hits[0] : null;
      }

      // 船壳真实轮廓（局部未缩放）：船头 +2.85，船尾 -2.4，最宽 1.32
      const SX = 1.12, SZ = 1.16;
      function halfWidth(z) {
        if (z > 2.85 || z < -2.4) return -1;
        if (z > 1.4) return 1.32 * (2.85 - z) / 1.45;
        if (z > -0.6) return 1.22 + 0.1 * ((z + 0.6) / 2.0);
        return 0.95 + 0.27 * ((z + 2.4) / 1.8);
      }
      function hullOverlap({ x, z }, yaw) {
        let hit = 0, total = 0;
        const cs = Math.cos(yaw), sn = Math.sin(yaw);
        for (let lz = -2.3; lz <= 2.8; lz += 0.4) {
          const hw = halfWidth(lz);
          if (hw < 0) continue;
          for (let u = -hw; u <= hw; u += 0.32) {
            total++;
            const wx = x + u * SX * cs - lz * SZ * sn;
            const wz = z + u * SX * sn + lz * SZ * cs;
            for (const bb of solids) {
              if (wx >= bb.min.x && wx <= bb.max.x && wz >= bb.min.z && wz <= bb.max.z) { hit++; break; }
            }
          }
        }
        return total ? hit / total : 1;
      }

      const zonesOut = zones.list.map(zone => {
        const overlap = hullOverlap(zone.boatPark, zone.boatYaw);
        const dockSurfaces = surfacesAt(zone.dockEdge.x, zone.dockEdge.z);
        const standSurfaces = surfacesAt(zone.landStand.x, zone.landStand.z);
        const pick = (list, y) => list.reduce((best, v) => Math.abs(v - y) < Math.abs(best - y) ? v : best, list[0]);

        const regions = zone.regions.map(region => {
          let total = 0, supported = 0;
          const xs = region.maxX - region.minX, zs = region.maxZ - region.minZ;
          for (let x = region.minX + 0.2; x <= region.maxX - 0.2; x += Math.max(0.7, xs / 14)) {
            for (let z = region.minZ + 0.2; z <= region.maxZ - 0.2; z += Math.max(0.7, zs / 14)) {
              if (!region.contains({ x, z })) continue;
              total++;
              if (topIn(region.span, x, z) !== null) supported++;
            }
          }
          return { id: region.id, y: region.y, span: region.span, total, supported, coverage: total ? +(supported / total).toFixed(2) : 0 };
        });

        // 上岸点 → 待机点：沿途每隔 0.3m 都必须踩到真实地面，不许踩空过水
        const span = zone.regions.reduce(
          (acc, r) => [Math.min(acc[0], r.span[0]), Math.max(acc[1], r.span[1])],
          [Infinity, -Infinity]
        );
        const dist = Math.hypot(zone.landStand.x - zone.dockEdge.x, zone.landStand.z - zone.dockEdge.z);
        const steps = Math.max(2, Math.ceil(dist / 0.3));
        let gaps = 0;
        const gapSpots = [];
        for (let i = 0; i <= steps; i++) {
          const t = i / steps;
          const x = zone.dockEdge.x + (zone.landStand.x - zone.dockEdge.x) * t;
          const z = zone.dockEdge.z + (zone.landStand.z - zone.dockEdge.z) * t;
          if (topIn(span, x, z) === null) {
            gaps++;
            if (gapSpots.length < 3) gapSpots.push([+x.toFixed(1), +z.toFixed(1)]);
          }
        }

        return {
          id: zone.id,
          name: zone.name,
          role: zone.role,
          boat: { park: [zone.boatPark.x, zone.boatPark.z], yaw: zone.boatYaw, hullOverlap: +(overlap * 100).toFixed(1) },
          dock: {
            y: +zone.dockEdge.y.toFixed(2),
            surface: dockSurfaces.length ? +pick(dockSurfaces, zone.dockEdge.y).toFixed(2) : null,
            diff: dockSurfaces.length ? +(pick(dockSurfaces, zone.dockEdge.y) - zone.dockEdge.y).toFixed(2) : null
          },
          stand: {
            y: +zone.landStand.y.toFixed(2),
            surface: standSurfaces.length ? +pick(standSurfaces, zone.landStand.y).toFixed(2) : null,
            diff: standSurfaces.length ? +(pick(standSurfaces, zone.landStand.y) - zone.landStand.y).toFixed(2) : null
          },
          regions,
          path: { distance: +dist.toFixed(2), steps: steps + 1, gaps, gapPct: +(gaps / (steps + 1) * 100).toFixed(1), spots: gapSpots }
        };
      });

      // 跨区块重叠：同一块地在两个区块里被声明成不同高度，会互相抢点击
      const overlaps = [];
      const all = [];
      for (const z of zones.list) for (const r of z.regions) all.push({ zone: z.id, region: r });
      for (let i = 0; i < all.length; i++) for (let j = i + 1; j < all.length; j++) {
        const a = all[i], b = all[j];
        if (a.zone === b.zone) continue;
        for (const ra of a.region.rects) for (const rb of b.region.rects) {
          const w = Math.min(ra.maxX, rb.maxX) - Math.max(ra.minX, rb.minX);
          const h = Math.min(ra.maxZ, rb.maxZ) - Math.max(ra.minZ, rb.minZ);
          if (w > 0.5 && h > 0.5) overlaps.push({ a: `${a.zone}/${a.region.id}`, b: `${b.zone}/${b.region.id}`, area: +(w * h).toFixed(1) });
        }
      }

      return { zones: zonesOut, crossOverlaps: overlaps };
    }, { WATER });

    fs.writeFileSync('outputs/zone-config-results.json', JSON.stringify(report, null, 2));

    // ---- 断言 ----
    const failures = [];
    for (const z of report.zones) {
      if (z.boat.hullOverlap > 8) failures.push(`${z.id} 停泊位船壳 ${z.boat.hullOverlap}% 侵入模型（上限 8%）`);
      if (z.dock.surface === null) failures.push(`${z.id} 上岸点下方没有任何可站立面`);
      else if (Math.abs(z.dock.diff) > 0.35) failures.push(`${z.id} 上岸点标高 ${z.dock.y} 与模型 ${z.dock.surface} 差 ${z.dock.diff}`);
      if (z.stand.surface === null) failures.push(`${z.id} 待机点下方没有任何可站立面`);
      else if (Math.abs(z.stand.diff) > 0.35) failures.push(`${z.id} 待机点标高 ${z.stand.y} 与模型 ${z.stand.surface} 差 ${z.stand.diff}`);
      for (const r of z.regions) {
        if (r.coverage < 0.6) failures.push(`${z.id}/${r.id} 可站立覆盖率仅 ${Math.round(r.coverage * 100)}%（配置的矩形大部分是水面或空中）`);
      }
      if (z.path.gapPct > 20) failures.push(`${z.id} 上岸点到待机点有 ${z.path.gapPct}% 的路程踩空（${z.path.spots.map(s => `(${s[0]},${s[1]})`).join(' ')}）`);
    }
    for (const o of report.crossOverlaps) failures.push(`区块重叠：${o.a} 与 ${o.b} 抢占同一片地 ${o.area}m²`);

    console.log('=== 区块配置实测 ===');
    for (const z of report.zones) {
      console.log(`\n${z.id} ${z.name}（${z.role}）`);
      console.log(`  停泊 (${z.boat.park[0]}, ${z.boat.park[1]}) 朝向 ${z.boat.yaw} · 船壳侵入 ${z.boat.hullOverlap}%`);
      console.log(`  上岸 (${z.dock.y}) → 模型 ${z.dock.surface}（差 ${z.dock.diff}）`);
      console.log(`  待机 (${z.stand.y}) → 模型 ${z.stand.surface}（差 ${z.stand.diff}）`);
      for (const r of z.regions) console.log(`  地块 ${r.id.padEnd(16)} 窗口[${r.span}] 覆盖 ${Math.round(r.coverage * 100)}%`);
      console.log(`  上岸→待机 ${z.path.distance}m，踩空 ${z.path.gapPct}%`);
    }
    if (report.crossOverlaps.length) console.log('\n区块重叠:', report.crossOverlaps);
    assert.deepEqual(failures, []);
    assert.deepEqual(errors, []);

    await page.screenshot({ path: 'outputs/zone-config-regression.png' });
    const summary = {
      passed: [
        '每个区块的停泊位船壳不侵入模型',
        '每个区块的上岸点与待机点落在真实表面上',
        '每个区块声明的可站立地块大部分有地面',
        '上岸点到待机点沿途不踩空',
        '区块之间不抢占同一片地'
      ],
      zones: report.zones.map(z => ({ id: z.id, role: z.role, regions: z.regions.map(r => r.id), hullOverlap: z.boat.hullOverlap, pathGapPct: z.path.gapPct })),
      errors
    };
    fs.writeFileSync('outputs/zone-config-summary.json', JSON.stringify(summary, null, 2));
    console.log('\n' + JSON.stringify(summary, null, 2));
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
