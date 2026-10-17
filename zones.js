// 海面区块注册表 —— 每个区块独立声明自己的「功能 / 可站立区域 / 上岸点 / 停泊位 / 航线」。
//
// 这份数据是唯一的区块来源：gameplay.js 不再持有任何区块坐标，
// 增删区块、搬动地块、改上岸点都只改这里。改完跑 `node tests/zone-config.cjs`
// 就会逐条校验配置是否真的落在模型上（船有没有插进栈桥、脚有没有悬空）。
//
// 坐标约定：数组一律 [x, y, z]；y 写 'water' 表示贴水面，由 WATER_LEVEL 填充。
// walk[].span 是「允许站立的真实表面高度窗口」，行走时在这段窗口里取最高的可站立面，
// 所以手写 y 只是设计意图，实际脚底高度永远跟着模型走。

export const ZONE_DEFS = [
  {
    id: 'zone1',
    name: '晴空水巷',
    role: 'home',
    purpose: '起始据点：太阳能木屋、交易码头、绞盘打捞台',
    status: '木屋码头待机',
    camera: [0.45, 1.75, -0.65],
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
    origin: [-28, 0, -18],
    camera: [-28, 1.2, -18],
    boat: { park: [-31.27, 'water', -13.08], yaw: -0.92 },
    landing: { dockEdge: [-30.6, 1.17, -15.6], stand: [-30.7, 2.83, -18.3] },
    walk: [
      // 站台本体是斜向长条，用几段矩形拼出来；北端栈桥直通登岸点。
      { id: 'zone2_station', y: 2.6, span: [1.1, 3.1], rects: [
        [-31.0, -30.0, -23.0, -15.5],
        [-35.0, -33.5, -24.5, -20.0],
        [-32.5, -31.0, -23.5, -19.0],
        [-33.5, -32.5, -24.0, -19.0],
        [-36.0, -35.0, -25.0, -20.0],
        [-27.0, -26.0, -24.5, -20.5],
        [-26.0, -24.5, -18.5, -15.5],
        [-25.0, -23.5, -23.5, -19.5],
        [-23.5, -22.0, -23.0, -19.0],
        [-22.0, -20.5, -22.5, -18.5]
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
    origin: [-18, 0.3, -4],
    camera: [-18, 1.6, -4],
    boat: { park: [-9.0, 'water', -2.0], yaw: -3.14 },
    landing: { dockEdge: [-12.6, 3.1, -2.0], stand: [-16, 4.31, -3] },
    walk: [
      // 东侧 3.1 露台沿台阶登上 4.3~4.56 的屋顶花池，两段高度放在同一个窗口里。
      { id: 'zone3_ground', y: 4.3, span: [2.8, 4.95], rects: [
        [-20.5, -15.5, -10.5, 2.5],
        [-21.5, -20.5, -10.0, 2.0],
        [-15.5, -14.5, -10.0, 2.0],
        [-14.5, -13.5, -9.5, 1.5],
        [-22.0, -21.5, -9.5, 1.5],
        [-22.5, -22.0, -9.0, 1.0],
        [-13.5, -13.0, -9.0, 1.0],
        [-23.0, -22.5, -8.5, 0.5],
        [-13.0, -12.5, -8.5, 0.5]
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
    camera: [39.5, 1.4, -41.5],
    boat: { park: [34.26, 'water', -36.36], yaw: 0 },
    landing: { dockEdge: [36.2, 1.73, -37.4], stand: [37.8, 1.66, -40.8] },
    walk: [
      { id: 'zone4_shore', y: 1.65, span: [1.3, 2.15], rects: [[35.4, 38.6, -41.2, -36.0]] }
    ],
    harbor: []
  },
  {
    id: 'zone5',
    name: '浅水养殖台',
    role: 'aquaculture',
    purpose: '远海珍珠培育的四格浅水池，船只 2 级后开放修建',
    status: '浅水养殖台待机',
    site: [16, 15],
    camera: [16, 1.5, 15],
    boat: { park: [11.29, 'water', 14.98], yaw: 0 },
    landing: { dockEdge: [13.2, 1.35, 14.4], stand: [15, 1.15, 15] },
    walk: [
      // 岛面只有 0.03 露出水面，窗口下限要压到 1.0 才认得到这块地。
      { id: 'zone5_aqua', y: 1.25, span: [1.0, 1.55], rects: [[12.8, 19.3, 12.2, 17.7]] }
    ],
    harbor: []
  }
];

// 航线航点（[x, z]，y 统一贴水面）。未列出的组合走直线，再由 gameplay 的
// 障碍绕行补齐 —— 所以新增区块可以先不写航线，能跑通再补。
export const SAIL_ROUTES = {
  'zone1>zone2': [[-0.6, 1.8], [-2.2, -5.8], [-8.8, -12.0], [-16.8, -14.8], [-22.2, -15.2]],
  'zone2>zone1': [[-22.2, -15.2], [-16.8, -14.8], [-8.8, -12.0], [-2.2, -5.8], [-0.6, 1.8]],
  'zone1>zone3': [[-1.2, 7.8], [-5.5, 10.4], [-10.2, 11.9]],
  'zone3>zone1': [[-10.2, 11.9], [-5.5, 10.4], [-1.2, 7.8]],
  'zone3>zone2': [[-18.5, 4.0], [-22.5, -2.2], [-25.2, -8.8]],
  'zone2>zone3': [[-25.2, -8.8], [-22.5, -2.2], [-18.5, 4.0]],
  'zone1>zone4': [[3.5, -5.0], [10.0, -11.0], [14.0, -13.0]],
  'zone4>zone1': [[14.0, -13.0], [10.0, -11.0], [3.5, -5.0]],
  'zone1>zone5': [[-1.2, 7.8], [4.0, 11.0]],
  'zone5>zone1': [[4.0, 11.0], [-1.2, 7.8]]
};

export function createZoneRegistry({ THREE, WATER_LEVEL, defs = ZONE_DEFS, routes = SAIL_ROUTES }) {
  const vec = (a) => new THREE.Vector3(a[0], a[1] === 'water' ? WATER_LEVEL : a[1], a[2]);

  function makeRegion(zoneId, spec) {
    const rects = spec.rects.map(([minX, maxX, minZ, maxZ]) => ({ minX, maxX, minZ, maxZ }));
    const contains = rects.length === 1
      ? (p) => p.x >= rects[0].minX && p.x <= rects[0].maxX && p.z >= rects[0].minZ && p.z <= rects[0].maxZ
      : (p) => rects.some((r) => p.x >= r.minX && p.x <= r.maxX && p.z >= r.minZ && p.z <= r.maxZ);
    return {
      id: spec.id,
      zone: zoneId,
      y: spec.y,
      span: spec.span || [spec.y - 0.4, spec.y + 0.6],
      rects,
      contains,
      minX: Math.min(...rects.map((r) => r.minX)),
      maxX: Math.max(...rects.map((r) => r.maxX)),
      minZ: Math.min(...rects.map((r) => r.minZ)),
      maxZ: Math.max(...rects.map((r) => r.maxZ))
    };
  }

  const list = defs.map((d) => {
    const zone = {
      ...d,
      boatPark: vec(d.boat.park),
      boatYaw: d.boat.yaw ?? 0,
      dockEdge: vec(d.landing.dockEdge),
      landStand: vec(d.landing.stand),
      origin: vec(d.origin || [0, 0, 0]),
      camera: d.camera ? vec(d.camera) : null,
      harbor: (d.harbor || []).map((h) => ({ ...h, point: vec(h.point) })),
      regions: d.walk.map((spec) => makeRegion(d.id, spec))
    };
    return zone;
  });

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
    // 区块内的建造点（buildSites 用 zone 字段挂靠）。
    sitesIn(id, sites) {
      return (sites || []).filter((s) => s.zone === id);
    }
  };
}
