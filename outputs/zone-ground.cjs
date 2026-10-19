// 导出每个区块的真实可站立地面矩形（修正：允许高出水面 0.02 的台面；被树冠/雨棚遮挡的地面也能取到）。
const { chromium } = require('playwright');
const fs = require('node:fs');
const WATER = 1.12;

const AREAS = [
  { id: 'zone1_home_dock', box: [-4, 10, -7, 12], windows: [[1.3, 2.45]] },
  { id: 'zone1_salvage', box: [-16.6, -7.4, 9.4, 16.6], windows: [[1.0, 1.5]] },
  { id: 'zone2_station', box: [-37.5, -19.5, -26.5, -10.5], windows: [[1.1, 3.1]] },
  { id: 'zone3_ground', box: [-23.5, -10.5, -10.5, 3.0], windows: [[2.8, 4.95]] },
  { id: 'zone4_shore', box: [34.5, 39.5, -42, -34.5], windows: [[1.3, 2.15]] },
  { id: 'zone5_aqua', box: [11.8, 20.2, 11.2, 18.8], windows: [[1.0, 1.5]] }
];

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
    args: ['--use-gl=angle', '--use-angle=metal', '--enable-webgl', '--ignore-gpu-blocklist']
  });
  try {
    const page = await browser.newPage({ viewport: { width: 900, height: 600 } });
    page.on('pageerror', e => console.log('PAGEERROR', e.message));
    await page.route('**/index.html', async route => {
      const response = await route.fetch();
      let body = await response.text();
      body = body.replace('    const clock = new THREE.Clock();', '    window.qa={THREE,gameplay,scene,camera,controls};\n    const clock = new THREE.Clock();');
      await route.fulfill({ response, body });
    });
    await page.goto('http://127.0.0.1:8765/index.html');
    await page.waitForFunction(() => window.qa?.gameplay?.art?.state, null, { timeout: 60000 });
    await page.waitForTimeout(2500);

    const out = await page.evaluate(({ WATER, AREAS }) => {
      const q = window.qa, T = q.THREE, scene = q.scene, art = q.gameplay.art;
      const boat = art.boatAnchorGroup, exp = art.explorerGroup;
      scene.updateMatrixWorld(true);
      const meshes = [];
      scene.traverse(o => {
        if (!o.isMesh || o.name === 'cartoon-water') return;
        for (let p = o; p; p = p.parent) if (!p.visible || p === boat || p === exp) return;
        meshes.push(o);
      });
      const ray = new T.Raycaster(), down = new T.Vector3(0, -1, 0), nm = new T.Matrix3();
      function inWindow(x, z, lo, hi) {
        ray.set(new T.Vector3(x, 60, z), down); ray.far = 120;
        for (const h of ray.intersectObjects(meshes, false)) {
          if (!h.face) continue;
          const y = h.point.y;
          if (y <= WATER + 0.02 || y < lo || y > hi) continue;
          nm.getNormalMatrix(h.object.matrixWorld);
          const n = h.face.normal.clone().applyMatrix3(nm).normalize();
          if (n.y >= 0.7) return y;
        }
        return null;
      }
      function toRects(mask, step, x0, z0) {
        const rows = mask.length, cols = mask[0].length;
        const used = mask.map(r => r.map(() => false));
        const rects = [];
        for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
          if (!mask[r][c] || used[r][c]) continue;
          let w = 1;
          while (c + w < cols && mask[r][c + w] && !used[r][c + w]) w++;
          let h = 1;
          outer: while (r + h < rows) {
            for (let k = 0; k < w; k++) if (!mask[r + h][c + k] || used[r + h][c + k]) break outer;
            h++;
          }
          for (let a = 0; a < h; a++) for (let b = 0; b < w; b++) used[r + a][c + b] = true;
          if (w * h < 3) continue;
          rects.push({
            rect: [+(x0 + c * step).toFixed(1), +(x0 + (c + w) * step).toFixed(1), +(z0 + r * step).toFixed(1), +(z0 + (r + h) * step).toFixed(1)],
            cells: w * h
          });
        }
        rects.sort((a, b) => b.cells - a.cells);
        return { rects, cells: mask.flat().filter(Boolean).length };
      }
      return AREAS.map(a => {
        const [bx0, bx1, bz0, bz1] = a.box;
        const [lo, hi] = a.windows[0];
        const step = 0.5;
        const cols = Math.floor((bx1 - bx0) / step), rows = Math.floor((bz1 - bz0) / step);
        const mask = Array.from({ length: rows }, () => new Array(cols).fill(false));
        for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
          const x = bx0 + (c + 0.5) * step, z = bz0 + (r + 0.5) * step;
          if (inWindow(x, z, lo, hi) !== null) mask[r][c] = true;
        }
        const res = toRects(mask, step, bx0, bz0);
        return { id: a.id, window: [lo, hi], cells: res.cells, area: +(res.cells * step * step).toFixed(1), rects: res.rects };
      });
    }, { WATER, AREAS });

    fs.writeFileSync('outputs/zone-ground-export.json', JSON.stringify(out, null, 2));
    for (const a of out) {
      console.log(`\n${a.id}  窗口[${a.window}]  ${a.cells}格 ≈${a.area}m²`);
      for (const r of a.rects.slice(0, 10)) console.log(`   [${r.rect.join(', ')}]  (${r.cells})`);
    }
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
