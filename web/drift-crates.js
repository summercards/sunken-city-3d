// 海面漂浮物资：随机刷在水道里的小木箱与木块。
//
// 两条硬规则（都是玩法要求，别改回去）：
//   1) **不挡船**。它们属于物资，不是障碍 —— 组上打 userData.noSailBlock，
//      航迹栅格和船壳碰撞都会跳过它，船可以直接压过去。
//   2) **必须真的开过去才收**。不再按里程随机掉落；只有船（或走上木栈道的人）
//      贴近到 pickupRadius 内才结算，而且只在「目标就是它」或「停着船」的时候收，
//      避免顺路划过去把整条水道扫干净。

const KINDS = {
  crate: {
    reward: { wood: 2, parts: 1 },
    label: '漂流物资箱'
  },
  planks: {
    reward: { wood: 3 },
    label: '漂流水料'
  },
  barrel: {
    reward: { parts: 2, wood: 1 },
    label: '漂流零件桶'
  }
};

export function createDriftCrates({
  THREE,
  worldGroup,
  waterLevel,
  makeMaterial,
  count = 9,
  pickupRadius = 1.6,
  respawnDelay = [4, 9],
  random = Math.random,
  isWaterPoint = () => true,
  spawnBounds = null,
  onCollect = null
}) {
  const root = new THREE.Group();
  root.name = 'drift-crates';
  root.userData.noSailBlock = true; // 整棵子树都不参与航行碰撞
  worldGroup.add(root);

  const geo = {
    box: new THREE.BoxGeometry(1, 1, 1),
    cyl: new THREE.CylinderGeometry(1, 1, 1, 9),
    torus: new THREE.TorusGeometry(1, 0.08, 6, 18)
  };
  const matCache = new Map();
  function mat(color) {
    if (!matCache.has(color)) {
      matCache.set(color, makeMaterial ? makeMaterial(color) : new THREE.MeshStandardMaterial({ color, roughness: 0.85 }));
    }
    return matCache.get(color);
  }
  function piece(parent, type, x, y, z, sx, sy, sz, color) {
    const mesh = new THREE.Mesh(geo[type], mat(color));
    mesh.position.set(x, y, z);
    mesh.scale.set(sx, sy, sz);
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    parent.add(mesh);
    return mesh;
  }

  const items = [];
  let pendingRespawns = [];

  function buildMesh(kind) {
    const g = new THREE.Group();
    g.name = 'drift-crate';
    g.userData.noSailBlock = true;
    g.userData.kind = kind;
    if (kind === 'planks') {
      for (let i = 0; i < 3; i++) {
        piece(g, 'cyl', (i - 1) * 0.26, 0.04 + i * 0.02, 0, 0.12, 1.5 - i * 0.18, 0.12, i % 2 ? '#b98b61' : '#cba97c').rotation.x = Math.PI / 2;
      }
      piece(g, 'box', 0, 0.13, 0.45, 0.9, 0.05, 0.08, '#8d7a5a');
      piece(g, 'box', 0, 0.13, -0.45, 0.9, 0.05, 0.08, '#8d7a5a');
    } else if (kind === 'barrel') {
      piece(g, 'cyl', 0, 0.30, 0, 0.30, 0.62, 0.30, '#a9764c');
      piece(g, 'torus', 0, 0.30, 0, 0.31, 0.31, 1, '#7d6a4c').rotation.x = Math.PI / 2;
      piece(g, 'cyl', 0, 0.60, 0, 0.27, 0.05, 0.27, '#d9c39a');
    } else {
      piece(g, 'box', 0, 0.24, 0, 0.62, 0.48, 0.52, '#c8a06a');
      piece(g, 'box', 0, 0.49, 0, 0.66, 0.06, 0.56, '#e2c79a');
      piece(g, 'box', 0, 0.24, 0, 0.66, 0.09, 0.56, '#8f7550');
      piece(g, 'box', 0, 0.30, 0.28, 0.20, 0.12, 0.03, '#f2e2bb');
    }
    // 水面上的一圈浅色浮标光，俯视时更容易看见。
    const ring = new THREE.Mesh(geo.torus, new THREE.MeshBasicMaterial({
      color: '#eaf6d8', transparent: true, opacity: 0.5, depthWrite: false
    }));
    ring.name = 'drift-crate-ring';
    ring.rotation.x = Math.PI / 2;
    ring.position.y = 0.02;
    ring.scale.set(0.78, 0.78, 0.78);
    g.add(ring);
    g.userData.ring = ring;
    return g;
  }

  function randomWaterPoint(tries = 240) {
    const b = spawnBounds || { minX: -60, maxX: 60, minZ: -70, maxZ: 30 };
    for (let i = 0; i < tries; i++) {
      const x = b.minX + random() * (b.maxX - b.minX);
      const z = b.minZ + random() * (b.maxZ - b.minZ);
      if (!isWaterPoint(x, z)) continue;
      if (items.some((it) => Math.hypot(it.base.x - x, it.base.z - z) < 7)) continue;
      return { x, z };
    }
    return null;
  }

  function spawn(kind) {
    const point = randomWaterPoint();
    if (!point) return null;
    const type = kind || (random() < 0.5 ? 'crate' : random() < 0.6 ? 'planks' : 'barrel');
    const group = buildMesh(type);
    group.position.set(point.x, waterLevel, point.z);
    root.add(group);
    const item = {
      id: items.length + 1,
      kind: type,
      group,
      base: new THREE.Vector3(point.x, waterLevel, point.z),
      phase: random() * Math.PI * 2,
      yaw: random() * Math.PI * 2
    };
    items.push(item);
    return item;
  }

  function spawnAll() {
    while (items.length < count) {
      if (!spawn()) break;
    }
  }

  function remove(item) {
    const idx = items.indexOf(item);
    if (idx >= 0) items.splice(idx, 1);
    item.group.parent?.remove(item.group);
    const [lo, hi] = respawnDelay;
    pendingRespawns.push(performance.now() + (lo + random() * (hi - lo)) * 1000);
  }

  // 收集：只有真的靠过去才结算。economy 收不下（仓储满）就留在水面上。
  function collect(item, economy) {
    const spec = KINDS[item.kind] || KINDS.crate;
    if (economy && economy.canReceive && !economy.canReceive(spec.reward)) {
      return { ok: false, reason: '仓库已满', reward: {} };
    }
    if (economy && !economy.receive(spec.reward)) {
      return { ok: false, reason: '仓库已满', reward: {} };
    }
    const worldPos = item.group.getWorldPosition(new THREE.Vector3());
    remove(item);
    if (onCollect) onCollect({ ...spec.reward }, worldPos, spec.label);
    return { ok: true, reward: { ...spec.reward }, label: spec.label };
  }

  function nearestTo(pos, radius = pickupRadius) {
    let best = null;
    for (const item of items) {
      const d = Math.hypot(item.group.position.x - pos.x, item.group.position.z - pos.z);
      if (d <= radius && (!best || d < best.d)) best = { item, d };
    }
    return best ? best.item : null;
  }

  function findTarget(object) {
    for (let node = object; node; node = node.parent) {
      if (node === root) return null;
      const item = items.find((it) => it.group === node);
      if (item) return item;
    }
    return null;
  }

  function update(dt, elapsed, { boatPos = null, walkerPos = null, shouldPickup = false } = {}, economy = null) {
    const wantPickup = typeof shouldPickup === 'function' ? shouldPickup() : !!shouldPickup;
    for (const item of items) {
      const { base, phase } = item;
      item.group.position.set(
        base.x + Math.sin(elapsed * 0.24 + phase) * 0.45,
        waterLevel + Math.sin(elapsed * 1.15 + phase) * 0.07,
        base.z + Math.cos(elapsed * 0.19 + phase) * 0.45
      );
      item.group.rotation.y = item.yaw + Math.sin(elapsed * 0.3 + phase) * 0.35;
      item.group.rotation.z = Math.sin(elapsed * 0.9 + phase) * 0.05;
      const ring = item.group.userData.ring;
      if (ring) ring.material.opacity = 0.34 + Math.sin(elapsed * 1.6 + phase) * 0.14;
    }

    // 到点补货，保持水面上始终有物资可捡。
    const now = performance.now();
    for (let i = pendingRespawns.length - 1; i >= 0; i--) {
      if (now >= pendingRespawns[i]) {
        pendingRespawns.splice(i, 1);
        spawn();
      }
    }

    // 只有「正要去捡它」或「船停着」才算碰到，顺路划过去不算。
    if (!wantPickup) return null;
    const hitBoat = boatPos ? nearestTo(boatPos) : null;
    if (hitBoat) return collect(hitBoat, economy);
    const hitWalker = walkerPos ? nearestTo(walkerPos) : null;
    if (hitWalker) return collect(hitWalker, economy);
    return null;
  }

  return {
    root,
    items,
    KINDS,
    spawnAll,
    spawn,
    collect,
    nearestTo,
    findTarget,
    update,
    get count() { return items.length; }
  };
}

