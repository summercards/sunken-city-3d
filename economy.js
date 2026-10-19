export const MATERIALS = {
  coins: { name: '海贝', capacity: Infinity, source: '浅滩贝床采集，也用2份食物交换12枚海贝。' },
  wood: { name: '木料', capacity: 60, source: '划到海面的漂流木箱/木块旁拾取，绞盘打捞也会补给。' },
  parts: { name: '旧零件', capacity: 60, source: '划到海面的漂流零件桶旁拾取，回收台也会分拣。' },
  seeds: { name: '种子', capacity: 20, source: '圆弧农场的种子箱，菜箱收获时返还种子。' },
  food: { name: '食物', capacity: 40, source: '播种菜箱并按时浇水，成熟后主动收获。' },
  fish: { name: '鱼', capacity: 40, source: '靠近鱼群采集，浅水养殖台投苗。' },
  pearl: { name: '珍珠', capacity: 12, source: '升级船只解锁远海后，拾取远海贝匣。' }
};

// 采集是冷却式的：点一次拿一笔，然后要等物资重新长回来。
// 冷却整体放缓，让 20 分钟 Demo 里的采集次数落在"够用但不刷屏"的区间。
// `icon` 是世界里的采集标记（画面上只显示这一个图标，不带文字框），同一种资源用同一个图标。
// 鱼不在固定采集点里：海面上的鱼群是活的（fish-schools.js），划到旁边现捞现少。
export const COLLECTIONS = [
  { id: 'home_crate', name: '屋顶物资箱', zone: 'zone1', icon: '🪵', reward: { wood: 3, parts: 1 }, cooldown: 34 },
  { id: 'shell_bed', name: '浅滩贝床', zone: 'zone1', icon: '🐚', reward: { coins: 5 }, cooldown: 26 },
  { id: 'garden_cache', name: '农场种子箱', zone: 'zone3', icon: '🌱', reward: { wood: 4, seeds: 2 }, cooldown: 42 },
  { id: 'workshop_cache', name: '铁道回收堆', zone: 'zone2', icon: '⚙', reward: { parts: 3, wood: 1 }, cooldown: 42 },
  { id: 'sea_cache', name: '远海贝匣', zone: 'zone4', icon: '🫧', reward: { pearl: 1, parts: 2 }, cooldown: 60 }
];

// 探索：木料和旧零件不靠"采集点"，而是走出来的。
// 每个区域都有，步行与航行同样累计里程，每走一段掷一次骰子。
export const EXPLORE = {
  step: 7,
  chance: 0.6,
  wood: [1, 2],
  parts: [0, 1]
};

// 挂机建筑攒够这么多份才亮出"可收取"，避免个位数资源把屏幕变成一直闪烁的红点。
export const HARVEST_THRESHOLD = 10;

export const FACILITIES = {
  greenhouse: {
    name: '屋顶温室',
    cost: { coins: 15, wood: 5, parts: 3 },
    requires: { home_cabin: 2, rooftop_planter: 1 },
    description: '蔬菜成熟缩短为26秒，每次收获3份食物。'
  },
  recycler: {
    name: '太阳能回收台',
    cost: { coins: 15, wood: 4, parts: 4 },
    requires: { home_cabin: 2, yokohama_station: 1 },
    description: '每30秒分拣2个旧零件，可暂存6个，需主动收取。'
  }
};

export const SHIP_RECIPE = {
  cost: { coins: 25, wood: 6, parts: 4, food: 2 },
  requires: { home_cabin: 2, rooftop_planter: 1 }
};

const ZONE_NAMES = {
  zone1: '晴空水巷',
  zone2: '横滨铁道',
  zone3: '圆弧农场',
  zone4: '远海街町'
};

const SITE_NAMES = {
  home_cabin: '晴空水巷 · 太阳能木屋花圃',
  rooftop_planter: '圆弧屋顶农场',
  yokohama_station: '横滨沉没铁道 · 站台与电车园圃'
};

function bundleEntries(bundle) {
  if (bundle === null || typeof bundle !== 'object' || Array.isArray(bundle)) return null;
  const prototype = Object.getPrototypeOf(bundle);
  if (prototype !== Object.prototype && prototype !== null) return null;
  const entries = [];
  for (const key of Reflect.ownKeys(bundle)) {
    if (typeof key !== 'string' || !Object.hasOwn(MATERIALS, key)) return null;
    const amount = bundle[key];
    // 安全整数限制同时防止海贝在无限容量下出现浮点溢出或数量丢失。
    if (!Number.isSafeInteger(amount) || amount < 0) return null;
    entries.push([key, amount]);
  }
  return entries;
}

// 菜箱参照牧场物语的节奏：播种后土壤会慢慢变干，干透就停止生长，得再浇一次水。
// 完整浇一次可维持 18 秒湿润；成熟时间刻意长于一次浇水，保证中途至少要回来照看一次。
export const CROP = { drainPerSecond: 1 / 18, dryDuration: 34, greenhouseDuration: 26 };

export function createEconomy(state, getSiteLevel, options = {}) {
  const random = typeof options.random === 'function' ? options.random : Math.random;
  const nodes = COLLECTIONS.map((node) => ({ ...node, reward: { ...node.reward }, left: 0, collections: 0 }));
  const plots = [
    { id: 'home_plot', name: '木屋菜箱', zone: 'zone1', siteId: 'home_cabin', minLevel: 2, phase: 'empty', remaining: 0, duration: CROP.dryDuration, reward: null, moisture: 0 },
    { id: 'farm_plot', name: '农场菜箱', zone: 'zone3', siteId: 'rooftop_planter', minLevel: 1, phase: 'empty', remaining: 0, duration: CROP.dryDuration, reward: null, moisture: 0 }
  ];
  const facilities = {
    greenhouse: { level: 0, stored: {} },
    recycler: { level: 0, stored: {}, timer: 0 }
  };
  let job = null;
  let exploredDistance = 0;

  function busy() {
    return state.workerMode !== 'IDLE_ASHORE' || Boolean(state.activeJobSite) || job !== null;
  }

  function balance(key) {
    return state[key] ?? 0;
  }

  function planTransaction(cost, reward) {
    const costs = bundleEntries(cost);
    const rewards = bundleEntries(reward);
    if (costs === null || rewards === null) return null;
    const debit = new Map(costs);
    const credit = new Map(rewards);
    const changes = [];
    for (const key of new Set([...debit.keys(), ...credit.keys()])) {
      const current = balance(key);
      const amount = debit.get(key) ?? 0;
      if (!Number.isSafeInteger(current) || current < amount || current < 0) return null;
      const next = current - amount + (credit.get(key) ?? 0);
      if (!Number.isSafeInteger(next) || (credit.has(key) && next > MATERIALS[key].capacity)) return null;
      changes.push([key, next]);
    }
    return changes;
  }

  function transact(cost, reward) {
    const changes = planTransaction(cost, reward);
    if (changes === null) return false;
    for (const [key, amount] of changes) state[key] = amount;
    return true;
  }

  function missing(cost) {
    const entries = bundleEntries(cost);
    if (entries === null) throw new TypeError('材料清单必须只含已知材料和非负安全整数。');
    const result = {};
    for (const [key, amount] of entries) {
      const current = balance(key);
      if (!Number.isSafeInteger(current) || current < 0) throw new RangeError('材料余额必须是非负安全整数。');
      if (amount > current) result[key] = amount - current;
    }
    return result;
  }

  function canReceive(reward) {
    return planTransaction({}, reward) !== null;
  }

  function spend(cost) {
    return transact(cost, {});
  }

  function receive(reward) {
    return transact({}, reward);
  }

  function accessReason(zone) {
    if (state.currentZone !== zone) return `先前往${ZONE_NAMES[zone]}靠岸`;
    if (busy()) return '旅人忙碌中';
    return '';
  }

  function requirementReason(requires) {
    const unmet = [];
    for (const [id, level] of Object.entries(requires)) {
      const current = getSiteLevel(id) ?? 0;
      if (!(current >= level)) unmet.push(`${SITE_NAMES[id]}需${level}级（当前${current}级）`);
    }
    return unmet.length ? `前置建筑不足：${unmet.join('；')}` : '';
  }

  function materialReason(cost) {
    const deficits = Object.entries(missing(cost));
    return deficits.length
      ? `材料不足：${deficits.map(([key, amount]) => `${MATERIALS[key].name}缺${amount}（来源：${MATERIALS[key].source}）`).join('；')}`
      : '';
  }

  function capacityReason(reward) {
    if (canReceive(reward)) return '';
    const full = Object.entries(reward)
      .filter(([key, amount]) => !Number.isSafeInteger(balance(key) + amount) || balance(key) + amount > MATERIALS[key].capacity)
      .map(([key]) => MATERIALS[key].name);
    return `库存已满或余额异常${full.length ? `：${full.join('、')}` : ''}，请先腾出空间`;
  }

  function action(reason, label) {
    return label === undefined ? { available: !reason, reason } : { available: !reason, reason, label };
  }

  function getCollectionAction(id) {
    const node = nodes.find((entry) => entry.id === id);
    if (!node) return action('未知采集点');
    const reason = (id === 'sea_cache' && !state.farSeaUnlocked ? '远海尚未解锁，请先升级船只' : '')
      || accessReason(node.zone)
      || (node.left > 0 ? `物资补充中，还需${Math.ceil(node.left)}秒` : '')
      || capacityReason(node.reward);
    return action(reason);
  }

  function collect(id) {
    const availability = getCollectionAction(id);
    if (!availability.available) return { ok: false, reason: availability.reason, reward: {} };
    const node = nodes.find((entry) => entry.id === id);
    const reward = { ...node.reward };
    if (!receive(reward)) return { ok: false, reason: capacityReason(reward), reward: {} };
    node.left = node.cooldown;
    node.collections += 1;
    return { ok: true, reason: '', reward };
  }

  function getPlotAction(id) {
    const plot = plots.find((entry) => entry.id === id);
    if (!plot) return action('未知菜箱', '不可用');
    const label = plot.phase === 'ready' ? '收获' : plot.phase === 'growing' ? '浇水' : '播种';
    let reason = accessReason(plot.zone) || requirementReason({ [plot.siteId]: plot.minLevel });
    if (!reason) {
      if (plot.phase === 'growing') {
        // 土壤还有一点湿气时允许提前补水，干透则是必须浇水才能继续长。
        if (plot.moisture >= 1) reason = `土壤湿润，蔬菜生长中，还需${Math.ceil(plot.remaining)}秒`;
      } else if (plot.phase === 'ready') reason = capacityReason(plot.reward);
      else reason = materialReason({ seeds: 1 });
    }
    return action(reason, label);
  }

  function waterPlot(id) {
    const availability = getPlotAction(id);
    if (!availability.available) return { ok: false, reason: availability.reason };
    const plot = plots.find((entry) => entry.id === id);
    if (plot.phase !== 'growing') return { ok: false, reason: '菜箱还没有播种' };
    plot.moisture = 1;
    return { ok: true, reason: '' };
  }

  function actPlot(id) {
    const availability = getPlotAction(id);
    if (!availability.available) return { ok: false, reason: availability.reason };
    const plot = plots.find((entry) => entry.id === id);
    if (plot.phase === 'growing') return waterPlot(id);
    if (plot.phase === 'ready') {
      const reward = { ...plot.reward };
      if (!receive(reward)) return { ok: false, reason: capacityReason(reward) };
      plot.phase = 'empty';
      plot.remaining = 0;
      plot.reward = null;
      plot.moisture = 0;
      return { ok: true, reason: '', reward };
    }
    if (!spend({ seeds: 1 })) return { ok: false, reason: materialReason({ seeds: 1 }) };
    const improved = facilities.greenhouse.level >= 1;
    plot.duration = improved ? CROP.greenhouseDuration : CROP.dryDuration;
    plot.remaining = plot.duration;
    plot.moisture = 1;
    plot.reward = { food: improved ? 3 : 2, seeds: 1 };
    plot.phase = 'growing';
    return { ok: true, reason: '' };
  }

  function getFacility(id) {
    return Object.hasOwn(facilities, id) ? facilities[id] : null;
  }

  function facilityCollectionReason(id) {
    const facility = getFacility(id);
    if (!facility) return '未知设施';
    return accessReason('zone1')
      || (facility.level < 1 ? '设施尚未建成' : '')
      || (id !== 'recycler' ? '该设施没有可收取的产物' : '')
      || (!(facility.stored.parts > 0) ? '暂无旧零件，每30秒分拣2个' : '')
      || capacityReason(facility.stored);
  }

  function getFacilityAction(id) {
    const facility = getFacility(id);
    if (!facility) return action('未知设施', '不可用');
    if (facility.level >= 1) {
      return id === 'recycler'
        ? action(facilityCollectionReason(id), '收取零件')
        : action('设施已建造', '已建造');
    }
    const recipe = FACILITIES[id];
    return action(
      accessReason('zone1') || requirementReason(recipe.requires) || materialReason(recipe.cost),
      job?.id === id ? '施工中' : '建造'
    );
  }

  function buildFacility(id) {
    const facility = getFacility(id);
    if (!facility) return { ok: false, reason: '未知设施' };
    if (facility.level >= 1) return { ok: false, reason: '设施已建造' };
    const availability = getFacilityAction(id);
    if (!availability.available) return { ok: false, reason: availability.reason };
    if (!spend(FACILITIES[id].cost)) return { ok: false, reason: materialReason(FACILITIES[id].cost) };
    job = { id, remaining: 6, duration: 6 };
    state.workerMode = 'CRAFTING';
    return { ok: true, reason: '' };
  }

  function collectFacility(id) {
    const reason = facilityCollectionReason(id);
    if (reason) return { ok: false, reason, reward: {} };
    const facility = getFacility(id);
    const reward = { ...facility.stored };
    if (!receive(reward)) return { ok: false, reason: capacityReason(reward), reward: {} };
    facility.stored = {};
    return { ok: true, reason: '', reward };
  }

  function getShipAction() {
    return action(accessReason('zone1')
      || (state.shipLevel >= 2 || state.farSeaUnlocked ? '船只已升级，远海已解锁' : '')
      || requirementReason(SHIP_RECIPE.requires)
      || materialReason(SHIP_RECIPE.cost));
  }

  function upgradeShip() {
    const availability = getShipAction();
    if (!availability.available) return { ok: false, reason: availability.reason };
    if (!spend(SHIP_RECIPE.cost)) return { ok: false, reason: materialReason(SHIP_RECIPE.cost) };
    state.shipLevel = 2;
    state.farSeaUnlocked = true;
    return { ok: true, reason: '' };
  }

  function tradeFood() {
    const reward = { coins: 12 };
    const reason = accessReason('zone1') || materialReason({ food: 2 }) || capacityReason(reward);
    if (reason) return { ok: false, reason, reward: {} };
    if (!transact({ food: 2 }, reward)) return { ok: false, reason: '交易余额异常', reward: {} };
    return { ok: true, reason: '', reward };
  }

  // 探索产出：四个区域都算，步行和航行同样累计里程。
  // 每走 EXPLORE.step 米掷一次骰子，命中时从漂流木/零件里挑一样带回去。
  function explore(distance) {
    if (typeof distance !== 'number' || !Number.isFinite(distance) || distance < 0) {
      return { ok: false, reward: {}, finds: 0, pending: exploredDistance };
    }
    exploredDistance += distance;
    const reward = {};
    let finds = 0;
    while (exploredDistance >= EXPLORE.step) {
      exploredDistance -= EXPLORE.step;
      if (random() > EXPLORE.chance) continue;
      const kind = random() < 0.62 ? 'wood' : 'parts';
      const [min, max] = EXPLORE[kind];
      const amount = min + Math.floor(random() * (max - min + 1));
      if (amount <= 0) continue;
      reward[kind] = (reward[kind] ?? 0) + amount;
      finds += 1;
    }
    if (finds === 0) return { ok: false, reward: {}, finds, pending: exploredDistance };
    if (!receive(reward)) return { ok: false, reward: {}, finds: 0, pending: exploredDistance };
    return { ok: true, reward, finds, pending: exploredDistance };
  }

  function tick(dt) {
    if (typeof dt !== 'number' || !Number.isFinite(dt) || dt < 0) {
      throw new RangeError('dt必须是非负有限秒数。');
    }
    for (const node of nodes) node.left = Math.max(0, node.left - dt);
    for (const plot of plots) {
      if (plot.phase !== 'growing') continue;
      const moisture = plot.moisture;
      // 只在一帧里"还湿着"的那段时间长个儿，剩下的时间土壤是干的，蔬菜停住。
      // 这样一次大步 tick 也不会把湿润期整个吞掉。
      const wetSeconds = Math.min(dt, moisture / CROP.drainPerSecond);
      if (wetSeconds > 0) plot.remaining = Math.max(0, plot.remaining - wetSeconds);
      const nextMoisture = moisture - CROP.drainPerSecond * dt;
      // 累减会留下 1e-16 量级的残差，直接归零，免得"干了"和"还有一丁点水"分不清。
      plot.moisture = nextMoisture <= 1e-9 ? 0 : nextMoisture;
      if (plot.remaining === 0) plot.phase = 'ready';
    }

    const recycler = facilities.recycler;
    let recyclerTime = recycler.level >= 1 ? dt : 0;
    if (job) {
      const constructionTime = job.remaining;
      job.remaining = Math.max(0, constructionTime - dt);
      if (job.remaining === 0) {
        facilities[job.id].level = 1;
        // 本帧先扣除施工时间，回收台只获得完工后的剩余时间。
        if (job.id === 'recycler') recyclerTime = dt - constructionTime;
        job = null;
        if (state.workerMode === 'CRAFTING') state.workerMode = 'IDLE_ASHORE';
      }
    }
    if (recycler.level >= 1 && recyclerTime > 0) {
      const stored = recycler.stored.parts ?? 0;
      if (stored >= 6) {
        recycler.timer = 0;
        return;
      }
      // 最多生产三批即可满仓；满仓停工，不囤积下一次收取后的生产时间。
      const elapsed = recycler.timer + Math.min(recyclerTime, 90);
      const batches = Math.floor(elapsed / 30);
      const next = Math.min(6, stored + batches * 2);
      if (batches > 0) recycler.stored.parts = next;
      recycler.timer = next >= 6 ? 0 : elapsed % 30;
    }
  }

  return {
    materials: MATERIALS,
    nodes,
    plots,
    facilities,
    harvestThreshold: HARVEST_THRESHOLD,
    get job() { return job; },
    get busy() { return busy(); },
    get exploredDistance() { return exploredDistance; },
    missing,
    canReceive,
    spend,
    receive,
    explore,
    getCollectionAction,
    collect,
    getPlotAction,
    actPlot,
    waterPlot,
    getFacility,
    getFacilityAction,
    buildFacility,
    collectFacility,
    getShipAction,
    upgradeShip,
    tradeFood,
    tick
  };
}
