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
    boat: { park: [6.97, 'water', 7.92], yaw: -1.05 },
    landing: { dockEdge: [6.0, 2.1, 4.3], stand: [3.35, 2.15, 3.35] },
    // 除主码头外，浮在西南面的绞盘打捞台也得能上去（船可以从它东侧靠泊）。
    // 每个 extra landing 都有自己的上岸边缘、待机点与停泊位，互不影响。
    extraLandings: [
      {
        id: 'salvage',
        name: '绞盘打捞台',
        // 甲板东缘在 x≈-8.9，船侧靠（船头朝 ±z）停在外面 1.7m 处；
        // 以前船头朝 +x 停在 -6.6，3.3m 长的船尾会插进甲板里（实测推出量 3.96m）。
        dockEdge: [-9.0, 1.33, 13.0],
        stand: [-11.6, 1.33, 12.6],
        park: [-7.2, 'water', 13.9],
        yaw: 0
      }
    ],
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
    boat: { park: [-3.51, 'water', 5.78], yaw: -1.57 },
    // 上岸边原来落在低栈道两块木板之间的缝里（射线打下去只有水面），
    // 往前挪半块板，保证角色下船第一脚就踩在木板上。
    landing: { dockEdge: [-2.2, 1.17, 2.3], stand: [-2.7, 2.83, -0.3] },
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
    boat: { park: [9.9, 'water', 2], yaw: -2.62 },
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
    boat: { park: [-6.44, 'water', 4.94], yaw: 2.36 },
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
    boat: { park: [-4.73, 'water', -0.08], yaw: 0 },
    landing: { dockEdge: [-2.8, 1.35, -0.6], stand: [-1, 1.15, 0] },
    walk: [
      // 岛面只有 0.03 露出水面，窗口下限要压到 1.0 才认得到这块地。
      { id: 'zone5_aqua', y: 1.25, span: [1.0, 1.55], rects: [[-3.2, 3.3, -2.8, 2.7]] }
    ],
    harbor: []
  }
];

// 航线不再手写航点：gameplay 会把「高出水面的实体」压成 0.5m 栅格做 A*（sail-nav.js），
// 路径按船体半宽自动留净空。搬动区块、加建筑之后不用回来改任何航线坐标。

export function createZoneRegistry({ THREE, WATER_LEVEL, defs = ZONE_DEFS }) {
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

    // 一个区块可以有多个上岸点：主码头 + 若干独立平台（打捞台、养殖台…）。
    // 主码头沿用 d.boat / d.landing，额外平台写在 extraLandings 里，结构一致。
    const landings = [
      {
        id: 'main',
        name: d.name,
        boatPark: vec(d.boat.park),
        boatYaw: d.boat.yaw ?? 0,
        dockEdge: vec(d.landing.dockEdge),
        landStand: vec(d.landing.stand)
      },
      ...(d.extraLandings || []).map((l) => ({
        id: l.id,
        name: l.name || d.name,
        boatPark: vec(l.park),
        boatYaw: l.yaw ?? 0,
        dockEdge: vec(l.dockEdge),
        landStand: vec(l.stand)
      }))
    ];

    return {
      ...d,
      origin: new THREE.Vector3(ox, oy, oz),
      camera: d.camera ? vec(d.camera) : null,
      hoverAnchor: d.hover ? vec(d.hover) : null,
      site: d.site ? vec([d.site[0], 0, d.site[1]]) : null,
      // boatPark / boatYaw / dockEdge / landStand 仍然指向主码头，保持旧调用处可用。
      boatPark: landings[0].boatPark,
      boatYaw: landings[0].boatYaw,
      dockEdge: landings[0].dockEdge,
      landStand: landings[0].landStand,
      landings,
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
    isUnlocked,
    // 取某个上岸点（不传 landingId 就取主码头）。
    landing(zoneId, landingId) {
      const zone = get(zoneId);
      if (!zone) return null;
      if (!landingId || landingId === 'main') return zone.landings[0];
      return zone.landings.find((l) => l.id === landingId) || zone.landings[0];
    },
    landingsOf(zoneId) {
      return get(zoneId)?.landings || [];
    },
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
