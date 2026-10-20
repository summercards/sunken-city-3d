/*
 * 把网页版的水下世界（underwater-art + neighborhood + north-trench）烘焙成 Godot 可读的数据。
 *
 * 用法（网页版在 http://127.0.0.1:8765 上跑着）：
 *   NODE_PATH=... node tools/export_underwater.cjs
 *
 * 产物 assets/baked/underwater/：
 *   scene.json        geoms + batches（每条批次带 region 标签）
 *   geoms.bin         顶点属性（pos3 normal3 uv2）
 *   geoms_idx.bin     索引
 *   instances.bin     每实例 12 个矩阵 float + 4 个 RGBA
 *
 * 与主场景烘焙的差别：水下世界是「一整块独立地图」，但按内容分成了几个可独立维护的
 * 区块（basin / neighborhood / reef / trench）。所以批次键里带上 region，同一份几何
 * 在不同区块各存一条批次，Python 侧就能按区块切出独立 glb。
 */
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

const OUT = path.resolve(__dirname, '..', 'assets', 'baked', 'underwater');
fs.mkdirSync(OUT, { recursive: true });

const f32 = [];
const u32 = [];
let fCount = 0, iCount = 0;
const pushF = v => { f32.push(v); fCount++; };
const pushI = v => { u32.push(v); iCount++; };

// 名字前缀 → 区块。顺序很重要，先匹配到的胜出。
const REGION_RULES = [
  ['neighborhood', ['submerged-residence', 'submerged-streetlamp', 'submerged-car',
    'submerged-delivery-van', 'collapsed-bridge-abutment', 'fallen-bridge-deck']],
  ['trench', ['north-trench-continuous-seabed', 'north-trench-escarpment',
    'trench-descent-remnant', 'trench-attached-stratum', 'tilted-pirate-brig',
    'tattered-brig-sail', 'giant-trench-coral']],
  ['reef', ['reef-coral', 'ribbon-kelp']],
];

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
    args: ['--enable-webgl', '--ignore-gpu-blocklist']
  });
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  page.on('pageerror', e => console.log('PAGEERR:', e.message));
  // 关掉 underwater-art.js 末尾的自动合批。
  // batch() 会把同几何+同材质的网格跨区块合并成一个 InstancedMesh 挂到 root 上，
  // 合并之后「这属于哪栋楼/哪片珊瑚」的信息就丢了，没法再按区块切分。
  await page.route('**/underwater-art.js', async route => {
    const res = await route.fetch();
    const body = (await res.text()).replace(
      'batch(root);swaying.forEach(s=>batch(s.g));',
      '/* batching disabled for export */'
    );
    await route.fulfill({ response: res, body, headers: { 'content-type': 'application/javascript' } });
  });

  await page.route('**/index.html', async route => {
    const res = await route.fetch();
    const body = (await res.text()).replace(
      '    animate();',
      '    window.__export = { THREE, scene, camera, renderer, diving, gameplay };\n    animate();'
    );
    await route.fulfill({ response: res, body });
  });

  await page.goto(process.env.APP_URL || 'http://127.0.0.1:8765/index.html', { waitUntil: 'load' });
  await page.waitForFunction(() => window.__export, null, { timeout: 90000 });
  await page.waitForTimeout(2000);

  const data = await page.evaluate((rules) => {
    const E = window.__export;
    const T = E.THREE;
    const root = E.scene.getObjectByName('underwater-city');
    if (!root) return { error: 'underwater-city not found' };

    const regionOf = (name) => {
      for (const [region, prefixes] of rules) {
        for (const p of prefixes) {
          if (name.startsWith(p)) return region;
        }
      }
      return 'basin';
    };

    // 最近的具名祖先决定区块。根自己叫 underwater-city，按 basin 算。
    function regionFor(obj) {
      let n = obj;
      while (n && n !== root) {
        if (n.name) return regionOf(n.name);
        n = n.parent;
      }
      return 'basin';
    }

    const geoms = [];
    const geomByKey = new Map();
    function geomIndex(g) {
      if (geomByKey.has(g.uuid)) return geomByKey.get(g.uuid);
      const pos = g.attributes.position;
      const nor = g.attributes.normal;
      const uv = g.attributes.uv;
      const col = g.attributes.color;
      const p = [], n = nor ? [] : null, t = uv ? [] : null, c = col ? [] : null;
      for (let i = 0; i < pos.count; i++) {
        p.push(pos.getX(i), pos.getY(i), pos.getZ(i));
        if (nor) n.push(nor.getX(i), nor.getY(i), nor.getZ(i));
        if (uv) t.push(uv.getX(i), uv.getY(i));
        if (col) c.push(col.getX(i), col.getY(i), col.getZ(i));
      }
      const indices = g.index ? Array.from(g.index.array) : null;
      const rec = { p, n, t, c, i: indices };
      geoms.push(rec);
      geomByKey.set(g.uuid, geoms.length - 1);
      return geoms.length - 1;
    }

    const materials = new Map();
    function materialKey(m) {
      if (materials.has(m.uuid)) return materials.get(m.uuid);
      const emissive = m.emissive && m.emissive.getHex() !== 0
        ? [m.emissive.r, m.emissive.g, m.emissive.b, m.emissiveIntensity == null ? 1 : m.emissiveIntensity]
        : null;
      const rec = {
        color: m.color ? [m.color.r, m.color.g, m.color.b] : [1, 1, 1],
        opacity: m.opacity == null ? 1 : m.opacity,
        flat: !!m.flatShading,
        doubleSide: m.side === T.DoubleSide,
        transparent: !!m.transparent,
        vertexColors: !!m.vertexColors,
        emissive,
        unlit: m.type === 'MeshBasicMaterial',
      };
      const key = JSON.stringify(rec);
      materials.set(m.uuid, key);
      return key;
    }

    // 具名组 → 单元。与 tools/build_underwater.py 的 unit_of() 必须一致。
    // 珊瑚和海草的组名不带序号（都叫 reef-coral / ribbon-kelp），
    // 所以按「遇到顺序」分桶：生成是确定性的，桶号可复现。
    const CORAL_PER_UNIT = 32, KELP_PER_UNIT = 28;
    const groupUnit = new Map();
    let coralSeq = 0, kelpSeq = 0;
    function unitOf(name, node) {
      const tail = (n) => parseInt(n.slice(n.lastIndexOf('-') + 1), 10) || 0;
      if (name === 'reef-coral' || name === 'ribbon-kelp') {
        if (!groupUnit.has(node)) {
          const per = name === 'reef-coral' ? CORAL_PER_UNIT : KELP_PER_UNIT;
          const n = name === 'reef-coral' ? coralSeq++ : kelpSeq++;
          groupUnit.set(node, (name === 'reef-coral' ? 'coral_' : 'kelp_')
            + String(Math.floor(n / per)).padStart(2, '0'));
        }
        return groupUnit.get(node);
      }
      if (name.startsWith('submerged-residence-')) return 'house_' + String(tail(name)).padStart(2, '0');
      if (name.startsWith('submerged-streetlamp')) return 'lamps';
      if (name.startsWith('submerged-car') || name.startsWith('submerged-delivery-van')) return 'vehicles';
      if (name.startsWith('collapsed-bridge') || name.startsWith('fallen-bridge-deck')) return 'bridge';
      if (name.startsWith('trench-descent-remnant')) return 'trench_stairs';
      if (name.startsWith('tilted-pirate-brig') || name.startsWith('tattered-brig-sail')) return 'brig';
      if (name.startsWith('north-trench') || name.startsWith('trench-attached-stratum')
        || name.startsWith('giant-trench-coral')) return 'trench_shell';
      if (name.startsWith('reef-terrace')) return 'terraces';
      return 'shell';
    }

    function unitFor(obj) {
      let n = obj;
      while (n && n !== root) {
        if (n.name) return unitOf(n.name, n);
        n = n.parent;
      }
      return 'shell';
    }

    const batches = new Map();
    function batchFor(geom, matKey, region, unit) {
      const key = geom + '|' + matKey + '|' + region + '|' + unit;
      let b = batches.get(key);
      if (!b) {
        const m = JSON.parse(matKey);
        b = {
          geom, region, unit,
          tex: -1, tint: false, unlit: m.unlit,
          alpha: m.transparent && m.opacity < 0.999,
          doubleSide: m.doubleSide, flat: m.flat,
          color: m.color, opacity: m.opacity, emissive: m.emissive,
          vertexColors: m.vertexColors,
          count: 0, transforms: [], colors: [],
        };
        batches.set(key, b);
      }
      return b;
    }

    const skipped = [];
    // 只烘静态网格：
    //   · 根下无名 Group 是鱼群（每帧改 transform），跳过；
    //   · Points / ShaderMaterial 是微粒、光柱、水面、背景，由运行时重建；
    //   · MeshPhysicalMaterial 的气泡同理。
    function isFishGroup(o) {
      return o.isGroup && o.parent === root && !o.name;
    }

    root.updateWorldMatrix(true, true);
    const tmp = new T.Matrix4();
    root.traverse(o => {
      if (!o.isMesh) return;
      if (o.material && o.material.isShaderMaterial) { skipped.push(o.name || 'shader'); return; }
      if (o.material && o.material.isMeshPhysicalMaterial) { skipped.push(o.name || 'physical'); return; }
      let p = o.parent;
      while (p && p !== root) {
        if (isFishGroup(p)) { skipped.push('fish'); return; }
        p = p.parent;
      }
      const gi = geomIndex(o.geometry);
      const key = materialKey(o.material);
      const region = regionFor(o);
      const unit = unitFor(o);
      const b = batchFor(gi, key, region, unit);


      // batch() 会把重复几何合成 InstancedMesh（珊瑚、楼体构件、海沟岩层都是这么来的），
      // 这些实例必须逐个展开，否则整片珊瑚和房子都会丢。
      if (o.isInstancedMesh) {
        for (let i = 0; i < o.count; i++) {
          o.getMatrixAt(i, tmp);
          tmp.premultiply(o.matrixWorld);
          const e = tmp.elements;
          b.transforms.push(e[0], e[4], e[8], e[12], e[1], e[5], e[9], e[13], e[2], e[6], e[10], e[14]);
          b.colors.push(1, 1, 1, 1);
          b.count++;
        }
        return;
      }

      const e = o.matrixWorld.elements;
      b.transforms.push(e[0], e[4], e[8], e[12], e[1], e[5], e[9], e[13], e[2], e[6], e[10], e[14]);
      b.colors.push(1, 1, 1, 1);
      b.count++;
    });

    return {
      geoms,
      batches: Array.from(batches.values()),
      skipped: skipped.length,
      skippedKinds: Array.from(new Set(skipped)),
    };
  }, REGION_RULES);

  // ---- 游动/交互数据：碰撞体、台地、宝箱、鱼群、海沟剖面 ----
  const swim = await page.evaluate(async () => {
    const E = window.__export;
    const art = E.diving && E.diving.art;
    const trenchMod = await import('/north-trench.js');
    const chests = (E.diving && E.diving.chests ? E.diving.chests : []).map((c, i) => ({
      id: i,
      name: c.name,
      pos: [c.g.position.x, c.g.position.y, c.g.position.z],
      reward: c.reward,
    }));
    const fish = (art && art.schools ? art.schools : []).map((s, i) => ({
      center: [s.center.x, s.center.y, s.center.z],
      phase: s.phase,
      color: ['#ffc55c', '#f19c4a', '#66dcf2', '#cd8fea'][i % 4],
      members: s.members.length,
    }));
    return {
      solids: art ? art.solidBuildings : [],
      terraces: art ? art.terraces : [],
      chests,
      fish,
      trenchProfile: trenchMod.TRENCH_PROFILE,
      trench: { minY: -225, maxZ: -26, minZ: -172 },
    };
  });
  fs.writeFileSync(path.join(OUT, 'swim.json'), JSON.stringify(swim));

  await browser.close();

  if (data.error) {
    console.error(data.error);
    process.exit(1);
  }

  // ---- 写几何 ----
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
      vcount: g.p.length / 3, pOff, nOff, tOff, cOff,
      icount: g.i ? g.i.length : 0, iOff,
    });
  }

  // ---- 写实例 ----
  const batchMeta = [];
  const inst = [];
  let off = 0;
  for (const b of data.batches) {
    batchMeta.push({
      geom: b.geom, region: b.region, unit: b.unit, tex: b.tex, tint: b.tint,
      unlit: b.unlit, alpha: b.alpha, doubleSide: b.doubleSide,
      flat: b.flat, color: b.color, opacity: b.opacity, emissive: b.emissive,
      vertexColors: b.vertexColors,
      count: b.count, instOff: off,
    });
    for (let i = 0; i < b.count; i++) {
      for (let k = 0; k < 12; k++) inst.push(b.transforms[i * 12 + k]);
      inst.push(b.colors[i * 4], b.colors[i * 4 + 1], b.colors[i * 4 + 2], b.colors[i * 4 + 3]);
    }
    off += b.count;
  }

  fs.writeFileSync(path.join(OUT, 'geoms.bin'), Buffer.from(Float32Array.from(f32).buffer));
  fs.writeFileSync(path.join(OUT, 'geoms_idx.bin'), Buffer.from(Uint32Array.from(u32).buffer));
  fs.writeFileSync(path.join(OUT, 'instances.bin'), Buffer.from(Float32Array.from(inst).buffer));

  const regions = {};
  for (const b of batchMeta) {
    regions[b.region] = (regions[b.region] || 0) + b.count;
  }

  const meta = {
    meta: {
      waterLevel: 1.12,
      source: 'underwater-city',
      note: '按 region 分块的静态几何；动态内容（鱼群/气泡/光柱/水膜/宝箱）由运行时重建',
      skipped: data.skipped,
    },
    textures: [],
    geoms: geomMeta,
    batches: batchMeta,
    lines: [],
    regions,
  };
  fs.writeFileSync(path.join(OUT, 'scene.json'), JSON.stringify(meta));

  console.log('geoms', geomMeta.length, 'batches', batchMeta.length, 'instances', off);
  console.log('regions', JSON.stringify(regions));
  console.log('skipped', data.skipped, data.skippedKinds);
})();
