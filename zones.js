// 海面区块注册表 —— 每个区块独立声明自己的「功能 / 可站立区域 / 上岸点 / 停泊位 / 航线」。
//
// 这份数据是唯一的区块来源：gameplay.js 不再持有任何区块坐标，
// 增删区块、搬动地块、改上岸点都只改这里。改完跑
//   node tests/zone-config.cjs    校验配置是否真的落在模型上
//   node tests/zone-spacing.cjs   校验区块之间留够通航净空
//
// 坐标约定（重要）：
//   - 每个区块的 `origin` 是该区块在世界里的锚点；区块模型（root）会被摆到这个位置。
//   - 区块内所有点位（camera / site / boat / landing / walk.rects / harbor / hover）
//     都写**相对 origin 的偏移**，x、z 会自动加上 origin，y 一律是绝对世界高度。
//   - 因此**搬动一个区块只改 origin 一个数字**，区块内部关系完全不动。
//   - 数组一律 [x, y, z]；y 写 'water' 表示贴水面（由 WATER_LEVEL 填充）。
//   - walk[].rects 每项是 [minX, maxX, minZ, maxZ]（相对），同样自动加 origin。
//
// walk[].span 是「允许站立的真实表面高度窗口」，行走时在这段窗口里取最高的可站立面，
// 所以手写的 y 只是设计意图，实际脚底高度永远跟着模型走。

export const ZONE_DEFS = [
  {
    id: 'zone1',
    name: '晴空水巷',
    role: 'home',
    purpose: '起始据点：太阳能木屋、交易码头、绞盘打捞台',
    status: '木屋码头待机',
    origin: [0, 0, 0],
    camera: [0.45, 1.75, -0.65],
    hover: [4.3, 5.92, -0.4],
    boat: { park: [6.44, 'water', 7.23], yaw: 1.57 },
    landing: { dockEdge: [6.0, 2.1, 4.3], stand: [3.35, 2.15, 3.35] },
    walk: [
      // 木屋四周的木板台面 + 南侧通往交易码头的低栈道；水面与屋顶由高度窗口挡掉。
      { id: 'zone1_home_dock', y: 2.15, span: [1.3, 2.45], rects: [
        [-3.2, 8.4, -7.2, -3.0],
        [0.0, 8.4, -3.0, 4.6],
        [7.8, 9.2, -5.2, 1.8],
        [-2.4, 2.8, 6.4, 11.2]
      ] },
      // 绞盘打捞台：木板甲板 1.33，四周边缘 1.15。
      { id: 'zone1_salvage', y: 1.33, span: [1.0, 1.5], rects: [[-15.2, -8.6, 9.8, 15.9]] }
    ],
    harbor: [
      { kind: 'salvage', label: 'C · 绞盘打捞台', point: [-12, 'water', 13] },
      { kind: 'dock', label: 'D · 交易码头', point: [0.3, 'water', 9] }
    ]
  },
  {
    id: 'zone2',
    name: '横滨铁道',
    role: 'station',
    purpose: '沉没铁道站台与复古电车，可开辟站台花圃、车顶花园、水道睡莲',
    status: '横滨铁道站台待机',
    origin: [-30, 0, -18],
    camera: [0, 1.2, 0],
    hover: [0, 5.32, 0],
    boat: { park: [-3.27, 'water', 4.92], yaw: -0.92 },
    landing: { dockEdge: [-2.6, 1.17, 2.4], stand: [-2.7, 2.83, -0.3] },
    walk: [
      // 站台本体是斜向长条，用几段矩形拼出来；北端栈桥直通登岸点。
      { id: 'zone2_station', y: 2.6, span: [1.1, 3.1], rects: [
        [-3, -2, -5, 2.5],
        [-7, -5.5, -6.5, -2],
        [-4.5, -3, -5.5, -1],
        [-5.5, -4.5, -6, -1],
        [-8, -7, -7, -2],
        [1, 2, -6.5, -2.5],
        [2, 3.5, -0.5, 2.5],
        [3, 4.5, -5.5, -1.5],
        [4.5, 6, -5, -1],
        [6, 7.5, -4.5, -0.5]
      ] }
    ],
    harbor: []
  },
  {
    id: 'zone3',
    name: '圆弧农场',
    role: 'farm',
    purpose: '圆弧屋顶种植园，可在屋顶花池种龟背竹与芭蕉林',
    status: '天台种植园待机',
    origin: [-2.25, 0.3, -36],
    camera: [0, 1.6, 0],
    hover: [0, 5.2, 0],
    boat: { park: [9, 'water', 2], yaw: -3.14 },
    landing: { dockEdge: [5.4, 3.1, 2], stand: [2, 4.31, 1] },
    walk: [
      // 东侧 3.1 露台沿台阶登上 4.3~4.56 的屋顶花池，两段高度放在同一个窗口里。
      { id: 'zone3_ground', y: 4.3, span: [2.8, 4.95], rects: [
        [-2.5, 2.5, -6.5, 6.5],
        [-3.5, -2.5, -6.0, 6.0],
        [2.5, 3.5, -6.0, 6.0],
        [3.5, 4.5, -5.5, 5.5],
        [-4.0, -3.5, -5.5, 5.5],
        [-4.5, -4.0, -5.0, 5.0],
        [4.5, 5.0, -5.0, 5.0],
        [-5.0, -4.5, -4.5, 4.5],
        [5.0, 5.5, -4.5, 4.5]
      ] }
    ],
    harbor: []
  },
  {
    id: 'zone4',
    name: '远海街町',
    role: 'shore',
    purpose: '远海终点：断桥与晾衣生活船所在的海街岸边',
    status: '远海街町待机',
    unlock: 'farSea',
    origin: [39.5, 0, -41.5],
    camera: [0, 1.4, 0],
    boat: { park: [-5.24, 'water', 5.14], yaw: 0 },
    landing: { dockEdge: [-3.3, 1.73, 4.1], stand: [-1.7, 1.66, 0.7] },
    walk: [
      { id: 'zone4_shore', y: 1.65, span: [1.3, 2.15], rects: [[-4.1, -0.9, 0.3, 5.5]] }
    ],
    harbor: []
  },
  {
    id: 'zone5',
    name: '浅水养殖台',
    role: 'aquaculture',
    purpose: '远海珍珠培育的四格浅水池，船只 2 级后开放修建',
    status: '浅水养殖台待机',
    origin: [22, 0, 16],
    site: [0, 0],
    camera: [0, 1.5, 0],
    hover: [0, 2.5, 0],
    boat: { park: [-4.71, 'water', -0.02], yaw: 0 },
    landing: { dockEdge: [-2.8, 1.35, -0.6], stand: [-1, 1.15, 0] },
    walk: [
      // 岛面只有 0.03 露出水面，窗口下限要压到 1.0 才认得到这块地。
      { id: 'zone5_aqua', y: 1.25, span: [1.0, 1.55], rects: [[-3.2, 3.3, -2.8, 2.7]] }
    ],
    harbor: []
  }
];

// 航线航点（世界坐标 [x, z]，y 统一贴水面）。未列出的组合走直线，再由 gameplay 的
// 障碍绕行补齐 —— 所以新增区块可以先不写航线，能跑通再补。
// 注意：航线是世界坐标、不属于任何区块，搬动区块后要回来核对（zone-spacing 会校验）。
export const SAIL_ROUTES = {
  // zone1 的楼体南界 z = -12.8，zone3 北界 z ≈ -27.7，中间是唯一的东西向走廊，
  // 中线取 z = -16.5（净空 ~4m 到楼、~11m 到 zone3）。所有航线都从这里过，不再从楼里穿。
  'zone1>zone2': [[12.5, 5], [14, -4], [14, -14], [10, -16.5], [0, -16.5], [-10, -16.5], [-18, -14], [-26, -12]],
  'zone2>zone1': [[-26, -12], [-18, -14], [-10, -16.5], [0, -16.5], [10, -16.5], [14, -14], [14, -4], [12.5, 5]],
  'zone1>zone3': [[12.5, 5], [14, -4], [14, -14], [10, -20], [10, -28]],
  'zone3>zone1': [[10, -28], [10, -20], [14, -14], [14, -4], [12.5, 5]],
  'zone3>zone2': [[10, -28], [10, -20], [13, -17], [10, -16.5], [0, -16.5], [-10, -16.5], [-18, -14], [-26, -12]],
  'zone2>zone3': [[-26, -12], [-18, -14], [-10, -16.5], [0, -16.5], [10, -16.5], [13, -17], [10, -20], [10, -28]],
  'zone1>zone4': [[12.5, 5], [14, -4], [14, -14], [16, -20]],
  'zone4>zone1': [[16, -20], [14, -14], [14, -4], [12.5, 5]],
  // 远海往返：沿东侧水道南下，绕开 x≈28~35 的废墟塔
  'zone5>zone4': [[16, 8], [14, 0], [14, -14], [16, -22], [24, -30], [28, -32]],
  'zone4>zone5': [[28, -32], [24, -30], [16, -22], [14, -14], [14, 0], [16, 8]],
  // zone5 在东侧，沿 zone1 与 zone5 之间的南北水道近岸
  'zone1>zone5': [[12.5, 4], [14, 0], [16, 8]],
  'zone5>zone1': [[16, 8], [14, 0], [12.5, 4]]
};

export function createZoneRegistry({ THREE, WATER_LEVEL, defs = ZONE_DEFS, routes = SAIL_ROUTES }) {
  const num = (v) => (v === 'water' ? WATER_LEVEL : v);

  function createZone(d) {
    const ox = d.origin?.[0] ?? 0;
    const oy = d.origin?.[1] ?? 0;
    const oz = d.origin?.[2] ?? 0;
    // 相对坐标 → 世界坐标（x/z 加 origin，y 是绝对高度）
    const vec = (a) => a && new THREE.Vector3(a[0] + ox, num(a[1]), a[2] + oz);
    const rectsOf = (spec) => spec.rects.map(([minX, maxX, minZ, maxZ]) => ({
      minX: minX + ox, maxX: maxX + ox, minZ: minZ + oz, maxZ: maxZ + oz
    }));

    const regions = d.walk.map((spec) => {
      const rects = rectsOf(spec);
      const contains = rects.length === 1
        ? (p) => p.x >= rects[0].minX && p.x <= rects[0].maxX && p.z >= rects[0].minZ && p.z <= rects[0].maxZ
        : (p) => rects.some((r) => p.x >= r.minX && p.x <= r.maxX && p.z >= r.minZ && p.z <= r.maxZ);
      return {
        id: spec.id,
        zone: d.id,
        y: spec.y,
        span: spec.span || [spec.y - 0.4, spec.y + 0.6],
        rects,
        contains,
        minX: Math.min(...rects.map((r) => r.minX)),
        maxX: Math.max(...rects.map((r) => r.maxX)),
        minZ: Math.min(...rects.map((r) => r.minZ)),
        maxZ: Math.max(...rects.map((r) => r.maxZ))
      };
    });

    return {
      ...d,
      origin: new THREE.Vector3(ox, oy, oz),
      camera: d.camera ? vec(d.camera) : null,
      hoverAnchor: d.hover ? vec(d.hover) : null,
      site: d.site ? vec([d.site[0], 0, d.site[1]]) : null,
      boatPark: vec(d.boat.park),
      boatYaw: d.boat.yaw ?? 0,
      dockEdge: vec(d.landing.dockEdge),
      landStand: vec(d.landing.stand),
      harbor: (d.harbor || []).map((h) => ({ ...h, point: vec(h.point) })),
      regions
    };
  }

  const list = defs.map(createZone);
  const byId = Object.fromEntries(list.map((z) => [z.id, z]));
  const walkRegions = list.flatMap((z) => z.regions);

  function get(id) {
    return byId[id] || null;
  }

  // 航线：显式配置优先，反向自动复用；都没有就返回 null 走直线。
  function routePoints(from, to) {
    if (from === to) return null;
    return routes[`${from}>${to}`] || null;
  }

  function isUnlocked(id, state) {
    const zone = get(id);
    if (!zone) return false;
    if (zone.unlock === 'farSea') return !!state.farSeaUnlocked;
    return true;
  }

  return {
    list,
    byId,
    ids: list.map((z) => z.id),
    walkRegions,
    get,
    routePoints,
    isUnlocked,
    label: (id) => get(id)?.name || id,
    role: (id) => get(id)?.role || null,
    serviceZones: (kind) => list.filter((z) => (z.harbor || []).some((h) => h.kind === kind)).map((z) => z.id),
    harborPoint(kind) {
      for (const zone of list) {
        const hit = (zone.harbor || []).find((h) => h.kind === kind);
        if (hit) return hit.point;
      }
      return null;
    },
    // 区块的模型包围盒（由可站立地块 + 点位估算），用于校验区块间距。
    footprint(id) {
      const zone = get(id);
      if (!zone) return null;
      const xs = [], zs = [];
      for (const r of zone.regions) { xs.push(r.minX, r.maxX); zs.push(r.minZ, r.maxZ); }
      for (const p of [zone.boatPark, zone.dockEdge, zone.landStand]) { xs.push(p.x); zs.push(p.z); }
      for (const h of zone.harbor) { xs.push(h.point.x); zs.push(h.point.z); }
      if (zone.site) { xs.push(zone.site.x); zs.push(zone.site.z); }
      return { minX: Math.min(...xs), maxX: Math.max(...xs), minZ: Math.min(...zs), maxZ: Math.max(...zs) };
    },
    // 区块内的建造点（buildSites 用 zone 字段挂靠）。
    sitesIn(id, sites) {
      return (sites || []).filter((s) => s.zone === id);
    }
  };
}
