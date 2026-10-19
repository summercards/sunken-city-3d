// 海面鱼群：到处游的小鱼群，划过去就能捞。
//
// 玩法约定（用户要求）：
//   1) 鱼群散在场景各处水面，不是固定采集点；只在玩家附近才亮出 🐟 收获图标。
//   2) **必须把船划到鱼群旁边**才收得到（图标出现 = 已经靠上了）。
//   3) 每捞一次鱼群少一条，捞完鱼群散掉，过一段时间在别处重新聚一群。
//   4) 不挡船：整棵子树 userData.noSailBlock，航迹栅格与船壳碰撞都会跳过。

const DEFAULTS = {
  count: 6,           // 同时存在几群
  perSchool: [3, 6],  // 每群初始鱼数
  harvestRadius: 3.2, // 船离鱼群多近才能捞
  showRadius: 7.0,    // 多近才亮出收获图标
  respawnDelay: [14, 30]
};

export function createFishSchools({
  THREE,
  worldGroup,
  waterLevel,
  makeMaterial,
  count = DEFAULTS.count,
  perSchool = DEFAULTS.perSchool,
  harvestRadius = DEFAULTS.harvestRadius,
  showRadius = DEFAULTS.showRadius,
  respawnDelay = DEFAULTS.respawnDelay,
  random = Math.random,
  isWaterPoint = () => true,
  spawnBounds = null,
  onHarvest = null
}) {
  const root = new THREE.Group();
  root.name = 'fish-schools';
  root.userData.noSailBlock = true;
  worldGroup.add(root);

  const geo = {
    body: new THREE.SphereGeometry(1, 8, 6),
    tail: new THREE.ConeGeometry(0.16, 0.34, 5),
    ring: new THREE.TorusGeometry(1, 0.06, 6, 22)
  };
  const matCache = new Map();
  function mat(color, opacity = 1) {
    const key = `${color}:${opacity}`;
    if (!matCache.has(key)) {
      const material = makeMaterial
        ? makeMaterial(color)
        : new THREE.MeshStandardMaterial({ color, roughness: 0.6 });
      if (opacity < 1 && material) {
        const clone = material.clone();
        clone.transparent = true;
        clone.opacity = opacity;
        clone.depthWrite = false;
        matCache.set(key, clone);
        return clone;
      }
      matCache.set(key, material);
    }
    return matCache.get(key);
  }

  const items = [];
  let nextId = 1;
  const pendingRespawns = [];
  const COLORS = ['#7fd6c9', '#9ae0c9', '#6cc3b8', '#a8e3d2', '#5fb6ae'];

  function buildFish(color) {
    const g = new THREE.Group();
    const body = new THREE.Mesh(geo.body, mat(color));
    body.scale.set(0.17, 0.11, 0.30);
    g.add(body);
    const tail = new THREE.Mesh(geo.tail, mat(color));
    tail.rotation.x = -Math.PI / 2;
    tail.position.z = -0.30;
    tail.scale.setScalar(0.9);
    g.add(tail);
    const eye = new THREE.Mesh(geo.body, mat('#2b4a52'));
    eye.scale.setScalar(0.035);
    eye.position.set(0.09, 0.035, 0.17);
    g.add(eye);
    return g;
  }

  function buildSchool(fishCount) {
    const g = new THREE.Group();
    g.name = 'fish-school';
    g.userData.noSailBlock = true;
    const fish = [];
    for (let i = 0; i < fishCount; i++) {
      const f = buildFish(COLORS[i % COLORS.length]);
      f.userData.phase = random() * Math.PI * 2;
      f.userData.radius = 0.45 + random() * 0.75;
      f.userData.speed = 0.55 + random() * 0.5;
      f.userData.depth = 0.015 + random() * 0.05;
      g.add(f);
      fish.push(f);
    }
    // 水面涟漪 + 一点浅色反光，俯视时能看出"这里有一群鱼"。
    const ring = new THREE.Mesh(geo.ring, new THREE.MeshBasicMaterial({
      color: '#e4fff6', transparent: true, opacity: 0.5, depthWrite: false
    }));
    ring.rotation.x = Math.PI / 2;
    ring.position.y = 0.02;
    ring.scale.setScalar(1.35);
    g.add(ring);
    const ring2 = new THREE.Mesh(geo.ring, new THREE.MeshBasicMaterial({
      color: '#d2f7ea', transparent: true, opacity: 0.22, depthWrite: false
    }));
    ring2.rotation.x = Math.PI / 2;
    ring2.position.y = 0.01;
    ring2.scale.setScalar(2.2);
    g.add(ring2);
    // 点击热区：鱼是绕着群心游的，群心其实是空水面，直接点"鱼群中心"什么也点不到。
    // 放一块几乎全透明的水面圆盘接住点击（raycaster 只认 visible，不认 opacity）。
    const pad = new THREE.Mesh(
      new THREE.CircleGeometry(1.7, 20),
      new THREE.MeshBasicMaterial({ color: '#d8fff2', transparent: true, opacity: 0.001, depthWrite: false })
    );
    pad.rotation.x = -Math.PI / 2;
    pad.position.y = 0.08;
    g.add(pad);
    g.userData.ring = ring;
    g.userData.ring2 = ring2;
    g.userData.pad = pad;
    return { group: g, fish };
  }

  function randomWaterPoint(tries = 260) {
    const b = spawnBounds || { minX: -60, maxX: 60, minZ: -70, maxZ: 30 };
    for (let i = 0; i < tries; i++) {
      const x = b.minX + random() * (b.maxX - b.minX);
      const z = b.minZ + random() * (b.maxZ - b.minZ);
      if (!isWaterPoint(x, z)) continue;
      if (items.some((it) => Math.hypot(it.base.x - x, it.base.z - z) < 9)) continue;
      return { x, z };
    }
    return null;
  }

  function spawn(fishCount) {
    const point = randomWaterPoint();
    if (!point) return null;
    const total = fishCount || (perSchool[0] + Math.floor(random() * (perSchool[1] - perSchool[0] + 1)));
    const { group, fish } = buildSchool(total);
    // 鱼群贴着水面游（水下的部分会被水面挡住，俯视时完全看不见）。
    group.position.set(point.x, waterLevel + 0.04, point.z);
    root.add(group);
    const item = {
      id: nextId++,
      group,
      fish,
      fishCount: total,
      maxFish: total,
      base: new THREE.Vector3(point.x, waterLevel, point.z),
      phase: random() * Math.PI * 2
    };
    items.push(item);
    return item;
  }

  function spawnAll() {
    let guard = 0;
    while (items.length < count && guard++ < count * 4) {
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

  function nearestTo(pos, radius = harvestRadius) {
    if (!pos) return null;
    let best = null;
    for (const item of items) {
      if (item.fishCount <= 0) continue;
      const d = Math.hypot(item.base.x - pos.x, item.base.z - pos.z);
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

  // 捞一条：鱼群少一条，捞完就散群（稍后在别处重新聚一群）。
  function harvest(item, economy) {
    if (!item || item.fishCount <= 0) return { ok: false, reason: '这群鱼已经游走了', reward: {} };
    const reward = { fish: 1 };
    if (economy && economy.canReceive && !economy.canReceive(reward)) {
      return { ok: false, reason: '鱼篓已满', reward: {} };
    }
    if (economy && !economy.receive(reward)) return { ok: false, reason: '鱼篓已满', reward: {} };
    item.fishCount -= 1;
    // 视觉上少一条鱼：把最外侧那条藏起来。
    const victim = item.fish[item.fishCount];
    if (victim) victim.visible = false;
    const worldPos = item.group.getWorldPosition(new THREE.Vector3());
    const depleted = item.fishCount <= 0;
    if (depleted) remove(item);
    if (onHarvest) onHarvest(reward, worldPos, depleted);
    return { ok: true, reward, depleted, left: item.fishCount };
  }

  const markers = new Map();
  function ensureMarker(item) {
    let el = markers.get(item.id);
    if (el) return el;
    el = document.createElement('span');
    el.className = 'fish-school-marker';
    el.dataset.fishId = String(item.id);
    el.textContent = '🐟';
    document.body.appendChild(el);
    markers.set(item.id, el);
    return el;
  }
  function dropMarker(id) {
    const el = markers.get(id);
    if (el) el.remove();
    markers.delete(id);
  }

  const projected = new THREE.Vector3();
  // 只有船靠到 showRadius 内才亮出 🐟（"划过去后就会有可收获的图标"）。
  function updateMarkers(boatPos, activeId) {
    if (!cameraRef) return;
    for (const item of items) {
      const el = ensureMarker(item);
      const near = boatPos && Math.hypot(item.base.x - boatPos.x, item.base.z - boatPos.z) <= showRadius;
      projected.set(item.base.x, waterLevel + 0.42, item.base.z).project(cameraRef);
      const onScreen = projected.z > -1 && projected.z < 1
        && Math.abs(projected.x) < .99 && Math.abs(projected.y) < .99;
      const show = Boolean(near) && onScreen;
      el.hidden = !show;
      if (!show) continue;
      const sx = (projected.x * .5 + .5) * window.innerWidth;
      const sy = (-projected.y * .5 + .5) * window.innerHeight;
      el._sx = sx;
      // 图标 CSS 是 translate(-50%,-100%)：元素底边贴锚点，命中要按「图标中心」算，
      // 否则鼠标点图标本体时判定点其实低了半个图标高度（这就是热区对不上的原因）。
      el._sy = sy - (el.offsetHeight || 30) / 2;
      el.style.left = `${sx.toFixed(1)}px`;
      el.style.top = `${sy.toFixed(1)}px`;
      const label = `鱼群 · 还能捞 ${item.fishCount} 条`;
      if (el.title !== label) { el.title = label; el.setAttribute('aria-label', label); }
      el.classList.toggle('is-target', item.id === activeId);
    }
    // 已经散群的鱼群把图标一起收走。
    for (const id of [...markers.keys()]) {
      if (!items.some((it) => it.id === id)) dropMarker(id);
    }
  }

  let cameraRef = null;
  function setCamera(camera) { cameraRef = camera; }

  // 屏幕空间命中：图标不接管指针，点击由 gameplay 统一路由到这里。
  function markerAt(clientX, clientY, radius = 22) {
    let best = null;
    for (const [id, el] of markers) {
      if (el.hidden || !Number.isFinite(el._sx)) continue;
      const d = Math.hypot(el._sx - clientX, el._sy - clientY);
      if (d <= radius && (!best || d < best.d)) best = { d, id };
    }
    return best ? items.find((it) => it.id === best.id) || null : null;
  }

  function update(dt, elapsed) {
    for (const item of items) {
      // 整群慢慢漂，鱼各自绕群心转圈。
      item.base.x += Math.sin(elapsed * 0.21 + item.phase) * 0.12 * dt;
      item.base.z += Math.cos(elapsed * 0.18 + item.phase) * 0.12 * dt;
      item.group.position.set(item.base.x, waterLevel, item.base.z);
      for (const f of item.fish) {
        if (!f.visible) continue;
        const a = elapsed * f.userData.speed + f.userData.phase;
        f.position.set(
          Math.cos(a) * f.userData.radius,
          0.03 + Math.sin(a * 1.7) * 0.02 + f.userData.depth,
          Math.sin(a) * f.userData.radius * 0.8
        );
        f.rotation.y = Math.atan2(
          -Math.sin(a) * f.userData.radius,
          Math.cos(a) * f.userData.radius * 0.8
        ) + Math.PI;
      }
      const ring = item.group.userData.ring;
      if (ring) {
        ring.scale.setScalar(1.35 + Math.sin(elapsed * 1.5 + item.phase) * 0.09);
        ring.material.opacity = 0.38 + Math.sin(elapsed * 1.5 + item.phase) * 0.14;
      }
      const ring2 = item.group.userData.ring2;
      if (ring2) {
        ring2.scale.setScalar(2.2 + Math.sin(elapsed * 1.1 + item.phase + 1.2) * 0.16);
        ring2.material.opacity = 0.16 + Math.sin(elapsed * 1.1 + item.phase + 1.2) * 0.08;
      }
    }
    const now = performance.now();
    for (let i = pendingRespawns.length - 1; i >= 0; i--) {
      if (now >= pendingRespawns[i]) {
        pendingRespawns.splice(i, 1);
        spawn();
      }
    }
  }

  return {
    root,
    items,
    spawnAll,
    spawn,
    harvest,
    nearestTo,
    findTarget,
    markerAt,
    update,
    updateMarkers,
    setCamera,
    get count() { return items.length; },
    harvestRadius
  };
}
