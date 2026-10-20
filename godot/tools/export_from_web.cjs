/*
 * 把网页版 Three.js 场景烘焙成 Godot 可读的二进制数据。
 *
 * 用法（网页版在 http://127.0.0.1:8765 上跑着）：
 *   NODE_PATH=/Users/summercards/.workbuddy/binaries/node/workspace/node_modules \
 *   node tools/export_from_web.cjs
 *
 * 产物：
 *   assets/baked/scene.json       静态场景元数据 + 贴图索引 + 线框
 *   assets/baked/geoms.bin        所有唯一几何（位置/法线/UV/顶点色/索引）
 *   assets/baked/instances.bin    所有实例的 3x4 矩阵 + RGBA
 *   assets/baked/boat.json/bin    小船（相对船锚）
 *   assets/baked/birds.json       飞鸟模型与盘旋参数
 *   assets/baked/textures/*.png   canvas 贴图
 *
 * 坐标：Three 的矩阵是列主序，导出成 Godot Transform3D 的 12 个 float
 *      （basis.x, basis.y, basis.z, origin）。
 */
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

const OUT = path.resolve(__dirname, '..', 'assets', 'baked');
const TEXDIR = path.join(OUT, 'textures');
fs.mkdirSync(TEXDIR, { recursive: true });

const f32 = [];
const u32 = [];
let fCount = 0, iCount = 0;

function pushF(v) { f32.push(v); fCount++; }
function pushI(v) { u32.push(v); iCount++; }

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
    args: ['--enable-webgl', '--ignore-gpu-blocklist']
  });
  const page = await browser.newPage({ viewport: { width: 1600, height: 1000 } });
  page.on('pageerror', e => console.log('PAGEERR:', e.message));
  await page.route('**/index.html', async route => {
    const res = await route.fetch();
    const body = (await res.text()).replace(
      '    animate();',
      '    window.__export = { THREE, scene, worldGroup, camera, renderer, boatAnchorGroup, boatMeshGroup, waterSystem, gameplay, birdsList, fishList };\n    animate();'
    );
    await route.fulfill({ response: res, body });
  });

  await page.goto(process.env.APP_URL || 'http://127.0.0.1:8765/index.html', { waitUntil: 'load' });
  await page.waitForFunction(() => window.__export, null, { timeout: 90000 });
  await page.waitForTimeout(1800);

  // 烘焙「建成态」：living-harbor 的爬藤 / 花丛 / 屋顶花园都挂在建造等级上，
  // 等级不到就 visible=false。直接烘初始态会把满墙绿植全丢掉，只剩光秃秃的盒子。
  const lifted = await page.evaluate(async () => {
    const E = window.__export;
    const art = E.gameplay && E.gameplay.art ? E.gameplay.art : null;
    if (!art || !art.buildSites) return { ok: false };
    for (const s of art.buildSites) {
      s.level = s.maxLevel != null ? s.maxLevel : Math.max(2, s.level || 0);
    }
    if (art.facilities) {
      for (const k of Object.keys(art.facilities)) art.facilities[k].level = 1;
    }
    // 等两帧，让 polishHarbor 的 layer 更新把 visible/scale 打开
    await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
    await new Promise(r => setTimeout(r, 400));
    return { ok: true, sites: art.buildSites.map(s => s.id + ':' + s.level) };
  });
  console.log('lifted build state:', JSON.stringify(lifted));
  await page.waitForTimeout(600);

  // 只把原始数组取回 Node，编码在 Node 侧做，避免浏览器内存翻倍。
  const data = await page.evaluate(() => {
    const E = window.__export;
    const T = E.THREE;

    const textures = [];
    const texByUuid = new Map();
    function texIndex(material) {
      const map = material && material.map;
      if (!map || !map.image) return -1;
      if (texByUuid.has(map.uuid)) return texByUuid.get(map.uuid);
      const img = map.image;
      let dataUrl = null;
      try {
        if (typeof img.toDataURL === 'function') dataUrl = img.toDataURL('image/png');
        else if (img.width && img.height) {
          const c = document.createElement('canvas');
          c.width = img.width; c.height = img.height;
          c.getContext('2d').drawImage(img, 0, 0);
          dataUrl = c.toDataURL('image/png');
        }
      } catch (e) { dataUrl = null; }
      if (!dataUrl) return -1;
      const idx = textures.length;
      textures.push({ name: `tex_${idx}.png`, dataUrl });
      texByUuid.set(map.uuid, idx);
      return idx;
    }

    const geoms = [];
    const geomByKey = new Map();
    function geomIndex(geometry, groupIndex) {
      const key = `${geometry.uuid}:${groupIndex}`;
      if (geomByKey.has(key)) return geomByKey.get(key);
      const pos = geometry.attributes.position;
      const uv = geometry.attributes.uv;
      const nor = geometry.attributes.normal;
      const col = geometry.attributes.color;
      let indices = null;
      if (geometry.index) {
        const arr = geometry.index.array;
        if (groupIndex >= 0 && geometry.groups.length) {
          const g = geometry.groups[groupIndex];
          const out = [];
          for (let i = 0; i < g.count; i++) out.push(arr[g.start + i]);
          indices = out;
        } else {
          indices = Array.from(arr);
        }
      } else if (groupIndex >= 0 && geometry.groups.length) {
        const g = geometry.groups[groupIndex];
        indices = [];
        for (let i = 0; i < g.count; i++) indices.push(g.start + i);
      }
      const p = new Float32Array(pos.count * 3);
      const n = nor ? new Float32Array(pos.count * 3) : null;
      const t = uv ? new Float32Array(pos.count * 2) : null;
      const c = col ? new Float32Array(pos.count * 3) : null;
      for (let i = 0; i < pos.count; i++) {
        p[i * 3] = pos.getX(i); p[i * 3 + 1] = pos.getY(i); p[i * 3 + 2] = pos.getZ(i);
        if (nor) { n[i * 3] = nor.getX(i); n[i * 3 + 1] = nor.getY(i); n[i * 3 + 2] = nor.getZ(i); }
        if (uv) { t[i * 2] = uv.getX(i); t[i * 2 + 1] = uv.getY(i); }
        if (col) { c[i * 3] = col.getX(i); c[i * 3 + 1] = col.getY(i); c[i * 3 + 2] = col.getZ(i); }
      }
      const rec = {
        p: Array.from(p),
        n: n ? Array.from(n) : null,
        t: t ? Array.from(t) : null,
        c: c ? Array.from(c) : null,
        i: indices
      };
      geoms.push(rec);
      geomByKey.set(key, geoms.length - 1);
      return geoms.length - 1;
    }

    const batches = new Map();
    function batchAccum(geom, tex, tint, unlit, doubleSide, alpha) {
      const key = `${geom}|${tex}|${tint ? 1 : 0}|${unlit ? 1 : 0}|${doubleSide ? 1 : 0}|${alpha ? 1 : 0}`;
      let b = batches.get(key);
      if (!b) {
        b = { geom, tex, tint, unlit, doubleSide, alpha, transforms: [], colors: [] };
        batches.set(key, b);
      }
      return b;
    }

    function materialFlags(m) {
      const src = m && m.onBeforeCompile ? m.onBeforeCompile.toString() : '';
      return {
        tint: src.indexOf('uWaterLevel') >= 0,
        unlit: !!(m && m.isMeshBasicMaterial),
        doubleSide: !!(m && m.side === T.DoubleSide),
        alpha: !!(m && m.transparent && (m.opacity == null || m.opacity < 0.999))
      };
    }

    function pushMesh(mesh, matrixWorld) {
      if (!mesh.geometry || !mesh.material) return;
      const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
      const groups = (Array.isArray(mesh.material) && mesh.geometry.groups.length)
        ? mesh.geometry.groups
        : [{ start: 0, count: mesh.geometry.index ? mesh.geometry.index.count : mesh.geometry.attributes.position.count, materialIndex: 0 }];
      for (let g = 0; g < groups.length; g++) {
        const m = mats[groups[g].materialIndex] || mats[0];
        if (!m) continue;
        const geoIdx = geomIndex(mesh.geometry, groups.length > 1 ? g : -1);
        const f = materialFlags(m);
        const b = batchAccum(geoIdx, texIndex(m), f.tint, f.unlit, f.doubleSide, f.alpha);
        const e = matrixWorld.elements;
        b.transforms.push(e[0], e[4], e[8], e[12], e[1], e[5], e[9], e[13], e[2], e[6], e[10], e[14]);
        const col = m.color || { r: 1, g: 1, b: 1 };
        b.colors.push(col.r, col.g, col.b, m.opacity == null ? 1 : m.opacity);
      }
    }

    const lines = new Map();
    function pushLine(line, matrixWorld) {
      if (!line.geometry || !line.material) return;
      const pos = line.geometry.attributes.position;
      if (!pos) return;
      const m = line.material;
      const key = `${m.color ? m.color.getHexString() : 'ffffff'}|${m.opacity == null ? 1 : m.opacity}`;
      let b = lines.get(key);
      if (!b) {
        b = {
          color: m.color ? [m.color.r, m.color.g, m.color.b] : [1, 1, 1],
          alpha: m.opacity == null ? 1 : m.opacity,
          pos: []
        };
        lines.set(key, b);
      }
      const v = new T.Vector3();
      for (let i = 0; i < pos.count; i++) {
        v.fromBufferAttribute(pos, i).applyMatrix4(matrixWorld);
        b.pos.push(+v.x.toFixed(3), +v.y.toFixed(3), +v.z.toFixed(3));
      }
    }

    function visibleInScene(o, root) {
      let n = o;
      while (n && n !== root) {
        if (n.visible === false) return false;
        n = n.parent;
      }
      return true;
    }

    E.worldGroup.updateMatrixWorld(true);
    E.worldGroup.traverse(o => {
      if (!visibleInScene(o, E.worldGroup)) return;
      if (o.isMesh) {
        if (o.userData && o.userData.skipExport) return;
        if (o.isInstancedMesh) {
          const inst = new T.Matrix4();
          for (let i = 0; i < o.count; i++) {
            o.getMatrixAt(i, inst);
            pushMesh(o, new T.Matrix4().multiplyMatrices(o.matrixWorld, inst));
          }
        } else {
          pushMesh(o, o.matrixWorld);
        }
      } else if (o.isLineSegments || o.isLine) {
        pushLine(o, o.matrixWorld);
      }
    });

    // ---- 小船：船锚局部坐标 ----
    const boatRoot = E.boatAnchorGroup;
    boatRoot.updateMatrixWorld(true);
    const boatInv = new T.Matrix4().copy(boatRoot.matrixWorld).invert();
    const boatGeoms = [];
    const boatGeomByKey = new Map();
    const boatBatches = new Map();
    boatRoot.traverse(o => {
      if (!o.isMesh || !o.geometry || !o.material) return;
      const mats = Array.isArray(o.material) ? o.material : [o.material];
      const groups = (Array.isArray(o.material) && o.geometry.groups.length)
        ? o.geometry.groups
        : [{ start: 0, count: o.geometry.index ? o.geometry.index.count : o.geometry.attributes.position.count, materialIndex: 0 }];
      for (let g = 0; g < groups.length; g++) {
        const m = mats[groups[g].materialIndex] || mats[0];
        if (!m) continue;
        const gk = `${o.geometry.uuid}:${groups.length > 1 ? g : -1}`;
        let gi = boatGeomByKey.get(gk);
        if (gi == null) {
          const pos = o.geometry.attributes.position;
          const nor = o.geometry.attributes.normal;
          const uv = o.geometry.attributes.uv;
          let idx = o.geometry.index ? Array.from(o.geometry.index.array) : null;
          if (groups.length > 1 && o.geometry.index) {
            const grp = groups[g];
            idx = [];
            for (let i = 0; i < grp.count; i++) idx.push(o.geometry.index.array[grp.start + i]);
          }
          const p = [], n = [], t = [];
          for (let i = 0; i < pos.count; i++) {
            p.push(+pos.getX(i).toFixed(3), +pos.getY(i).toFixed(3), +pos.getZ(i).toFixed(3));
            if (nor) n.push(+nor.getX(i).toFixed(3), +nor.getY(i).toFixed(3), +nor.getZ(i).toFixed(3));
            if (uv) t.push(+uv.getX(i).toFixed(4), +uv.getY(i).toFixed(4));
          }
          boatGeoms.push({ p, n: n.length ? n : null, t: t.length ? t : null, c: null, i: idx });
          gi = boatGeoms.length - 1;
          boatGeomByKey.set(gk, gi);
        }
        const f = materialFlags(m);
        const key = `${gi}|${f.tint ? 1 : 0}|${f.unlit ? 1 : 0}|${f.alpha ? 1 : 0}|${f.doubleSide ? 1 : 0}`;
        let b = boatBatches.get(key);
        if (!b) {
          b = { geom: gi, tex: -1, tint: f.tint, unlit: f.unlit, alpha: f.alpha, doubleSide: f.doubleSide, transforms: [], colors: [] };
          boatBatches.set(key, b);
        }
        const local = new T.Matrix4().multiplyMatrices(boatInv, o.matrixWorld);
        const e = local.elements;
        b.transforms.push(e[0], e[4], e[8], e[12], e[1], e[5], e[9], e[13], e[2], e[6], e[10], e[14]);
        const col = m.color || { r: 1, g: 1, b: 1 };
        b.colors.push(col.r, col.g, col.b, 1);
      }
    });

    // ---- 飞鸟 ----
    const birds = [];
    for (const b of (E.birdsList || [])) {
      const g = b.group;
      g.updateMatrixWorld(true);
      const inv = new T.Matrix4().copy(g.matrixWorld).invert();
      const parts = [];
      g.traverse(o => {
        if (!o.isMesh || !o.geometry || !o.material) return;
        const pos = o.geometry.attributes.position;
        const nor = o.geometry.attributes.normal;
        const p = [], n = [];
        for (let i = 0; i < pos.count; i++) {
          p.push(+pos.getX(i).toFixed(3), +pos.getY(i).toFixed(3), +pos.getZ(i).toFixed(3));
          if (nor) n.push(+nor.getX(i).toFixed(3), +nor.getY(i).toFixed(3), +nor.getZ(i).toFixed(3));
        }
        const local = new T.Matrix4().multiplyMatrices(inv, o.matrixWorld);
        const e = local.elements;
        const col = o.material.color || { r: 1, g: 1, b: 1 };
        parts.push({
          p, n: n.length ? n : null,
          i: o.geometry.index ? Array.from(o.geometry.index.array) : null,
          t: [e[0], e[1], e[2], e[4], e[5], e[6], e[8], e[9], e[10], e[12], e[13], e[14]],
          c: [col.r, col.g, col.b],
          unlit: !!o.material.isMeshBasicMaterial
        });
      });
      birds.push({
        center: [b.center.x, b.baseY, b.center.z],
        radiusX: b.radiusX, radiusZ: b.radiusZ, baseY: b.baseY,
        speed: b.speed, phase: b.phase, flapSpeed: b.flapSpeed || 6,
        parts
      });
    }

    return {
      meta: {
        waterLevel: 1.12,
        camPos: E.camera.position.toArray(),
        camTarget: [0.45, 1.75, -0.65],
        fov: E.camera.fov,
        background: '#176d9a',
        fogNear: 200,
        fogFar: 520
      },
      textures,
      geoms,
      batches: [...batches.values()],
      lines: [...lines.values()],
      boat: { geoms: boatGeoms, batches: [...boatBatches.values()] },
      birds
    };
  });

  // ---- 编码几何 ----
  const geomMeta = [];
  for (const g of data.geoms) {
    const pOff = fCount;
    for (const v of g.p) pushF(v);
    let nOff = -1, tOff = -1, cOff = -1;
    if (g.n) { nOff = fCount; for (const v of g.n) pushF(v); }
    if (g.t) { tOff = fCount; for (const v of g.t) pushF(v); }
    if (g.c) { cOff = fCount; for (const v of g.c) pushF(v); }
    let iOff = -1;
    if (g.i) { iOff = iCount; for (const v of g.i) pushI(v); }
    geomMeta.push({
      vcount: g.p.length / 3,
      pOff, nOff, tOff, cOff,
      icount: g.i ? g.i.length : 0,
      iOff
    });
  }

  // ---- 编码实例 ----
  const batchMeta = [];
  let instOff = 0;
  for (const b of data.batches) {
    const count = b.colors.length / 4;
    batchMeta.push({
      geom: b.geom, tex: b.tex, tint: b.tint, unlit: b.unlit,
      doubleSide: b.doubleSide, alpha: b.alpha,
      count, instOff,
      transforms: b.transforms,
      colors: b.colors
    });
    instOff += count;
  }

  // 实例数据写成独立 Float32 数组（12 变换 + 4 颜色）
  const inst = new Float32Array(instOff * 16);
  let cursor = 0;
  for (const b of batchMeta) {
    for (let i = 0; i < b.count; i++) {
      const t = b.transforms, c = b.colors;
      for (let k = 0; k < 12; k++) inst[(cursor + i) * 16 + k] = t[i * 12 + k];
      inst[(cursor + i) * 16 + 12] = c[i * 4];
      inst[(cursor + i) * 16 + 13] = c[i * 4 + 1];
      inst[(cursor + i) * 16 + 14] = c[i * 4 + 2];
      inst[(cursor + i) * 16 + 15] = c[i * 4 + 3];
    }
    cursor += b.count;
  }

  fs.writeFileSync(path.join(OUT, 'geoms.bin'), Buffer.from(Float32Array.from(f32).buffer));
  fs.writeFileSync(path.join(OUT, 'geoms_idx.bin'), Buffer.from(Uint32Array.from(u32).buffer));
  fs.writeFileSync(path.join(OUT, 'instances.bin'), Buffer.from(inst.buffer));

  // ---- 小船二进制 ----
  const bf = [], bi = [];
  const bGeomMeta = [];
  for (const g of data.boat.geoms) {
    const pOff = bf.length; for (const v of g.p) bf.push(v);
    let nOff = -1, tOff = -1;
    if (g.n) { nOff = bf.length; for (const v of g.n) bf.push(v); }
    if (g.t) { tOff = bf.length; for (const v of g.t) bf.push(v); }
    let iOff = -1;
    if (g.i) { iOff = bi.length; for (const v of g.i) bi.push(v); }
    bGeomMeta.push({ vcount: g.p.length / 3, pOff, nOff, tOff, icount: g.i ? g.i.length : 0, iOff });
  }
  const bInst = [];
  const bBatchMeta = [];
  let bOff = 0;
  for (const b of data.boat.batches) {
    const count = b.colors.length / 4;
    bBatchMeta.push({ geom: b.geom, tex: b.tex, tint: b.tint, unlit: b.unlit, doubleSide: b.doubleSide, alpha: b.alpha, count, instOff: bOff });
    for (let i = 0; i < count; i++) {
      for (let k = 0; k < 12; k++) bInst.push(b.transforms[i * 12 + k]);
      bInst.push(b.colors[i * 4], b.colors[i * 4 + 1], b.colors[i * 4 + 2], b.colors[i * 4 + 3]);
    }
    bOff += count;
  }
  fs.writeFileSync(path.join(OUT, 'boat_geoms.bin'), Buffer.from(Float32Array.from(bf).buffer));
  fs.writeFileSync(path.join(OUT, 'boat_geoms_idx.bin'), Buffer.from(Uint32Array.from(bi).buffer));
  fs.writeFileSync(path.join(OUT, 'boat_instances.bin'), Buffer.from(Float32Array.from(bInst).buffer));

  data.textures.forEach((t, i) => {
    fs.writeFileSync(path.join(TEXDIR, t.name), Buffer.from(t.dataUrl.split(',')[1], 'base64'));
  });

  const sceneOut = {
    meta: data.meta,
    textures: data.textures.map(t => `textures/${t.name}`),
    geoms: geomMeta,
    batches: batchMeta.map(b => ({
      geom: b.geom, tex: b.tex, tint: b.tint, unlit: b.unlit,
      doubleSide: b.doubleSide, alpha: b.alpha, count: b.count, instOff: b.instOff
    })),
    lines: data.lines
  };
  fs.writeFileSync(path.join(OUT, 'scene.json'), JSON.stringify(sceneOut));

  const boatOut = {
    geoms: bGeomMeta,
    batches: bBatchMeta
  };
  fs.writeFileSync(path.join(OUT, 'boat.json'), JSON.stringify(boatOut));
  fs.writeFileSync(path.join(OUT, 'birds.json'), JSON.stringify(data.birds));

  const size = (p) => (fs.statSync(path.join(OUT, p)).size / 1048576).toFixed(2);
  console.log(JSON.stringify({
    geoms: data.geoms.length,
    batches: data.batches.length,
    instances: instOff,
    lines: data.lines.length,
    lineVerts: data.lines.reduce((a, b) => a + b.pos.length / 3, 0),
    boatBatches: data.boat.batches.length,
    boatInstances: bOff,
    birds: data.birds.length,
    textures: data.textures.length,
    MB: { scene: size('scene.json'), geoms: size('geoms.bin'), instances: size('instances.bin'), boat: size('boat_instances.bin') }
  }, null, 2));
  await browser.close();
})();
