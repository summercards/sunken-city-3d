import { MATERIALS, FACILITIES, SHIP_RECIPE } from './economy.js';

const ZONES = { zone1: '晴空水巷', zone2: '横滨铁道', zone3: '圆弧农场', zone4: '远海街町', zone5: '浅水养殖台' };
const POSITIONS = {
  home_crate: [6.8, 2.1, 2.1], garden_cache: [-20.4, 4.2, -6.2],
  workshop_cache: [-31, 2.5, -16.8], sea_cache: [37.8, 1.55, -40.8],
  // 贝床与鱼群贴在浅水面上，压着水线放，俯视时才看得出是"水里的东西"。
  shell_bed: [-6.2, 1.35, 7.4], canal_shoal: [-13.2, 1.3, 9.6], farm_shoal: [-26.5, 4.85, 3.2],
  home_plot: [2, 2.02, 1.8], farm_plot: [-18.4, 4.4, -1.2],
  // 木屋阁楼与斜太阳能屋顶最高约 8 米，温室平台需高于中心屋面。
  greenhouse: [4.4, 7.7, -.4], recycler: [.3, 1.8, 9]
};

export function createEconomyView({ THREE, worldGroup, camera, state, economy, buildSites, activateSite, travel, upgradeShip, performSalvage, syncUI, notify, zones }) {
  // 区块名称与解锁条件以 zones.js 为准，这里只做兜底。
  const zoneLabel = (id) => zones?.label?.(id) || ZONES[id] || id;
  const roots = [];
  const targets = new Map();
  const visuals = [];
  const cards = new Map();
  const tabs = new Map();
  const sections = new Map();
  const siteById = new Map(buildSites.map(site => [site.id, site]));
  let activeTab = 'collect';
  let panelElapsed = 0;

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }
  function text(node, value) {
    const next = String(value ?? '');
    if (node.textContent !== next) node.textContent = next;
  }
  function button(className, label) {
    const node = element('button', className, label);
    node.type = 'button';
    return node;
  }
  function stopSceneEvents(node) {
    for (const type of ['click', 'dblclick', 'pointerdown', 'pointerup', 'pointermove', 'contextmenu', 'wheel', 'touchstart', 'touchmove', 'touchend']) {
      node.addEventListener(type, event => event.stopPropagation(), { passive: true });
    }
  }
  const bundle = values => Object.entries(values || {}).filter(([, amount]) => amount > 0)
    .map(([key, amount]) => `${MATERIALS[key].name} ×${amount}`).join('、') || '无';
  const sources = values => Object.keys(values || {}).map(key => `${MATERIALS[key].name}：${MATERIALS[key].source}`).join(' ');
  const siteName = id => siteById.get(id)?.name || id;
  const siteLevel = id => siteById.get(id)?.level || 0;
  const busy = () => economy.busy || state.workerMode !== 'IDLE_ASHORE';
  const needsBoat = zone => (zones ? !zones.isUnlocked(zone, state) : zone === 'zone4' && !state.farSeaUnlocked);
  function prerequisites(requires = {}) {
    return Object.entries(requires).map(([id, level]) => id === 'boat2'
      ? `船只2级（当前${state.shipLevel || 1}级）`
      : `${siteName(id)}${level}级（当前${siteLevel(id)}级）`).join('；') || '无建筑前置';
  }
  function requirementReason(requires = {}) {
    const unmet = Object.fromEntries(Object.entries(requires).filter(([id, level]) =>
      id === 'boat2' ? (state.shipLevel || 1) < 2 : siteLevel(id) < level));
    return Object.keys(unmet).length ? `前置未满足：${prerequisites(unmet)}` : '';
  }
  function costs(cost) {
    const missing = economy.missing(cost);
    return { cost: bundle(cost), missing: bundle(missing), source: sources(Object.keys(missing).length ? missing : cost) || '无需消耗材料。' };
  }
  function localAction(model, zone) {
    if (needsBoat(zone)) return { ...model, status: '航线锁定', label: '远海尚未解锁', available: false, reason: '请在建造页升级船只，再前往远海。', secondary: { label: '查看改船配方', id: 'ship' } };
    if (state.currentZone === zone) return model;
    return {
      ...model, action: `travel:${zone}`, label: `前往${zoneLabel(zone)}`,
      available: !busy(), reason: busy() ? '旅人忙碌中，请靠岸并等待当前操作结束。' : `需在${zoneLabel(zone)}靠岸后操作。`,
      invoke: () => travel(zone), allowVoid: true, success: `正在前往${zoneLabel(zone)}，抵达后请再次确认操作。`
    };
  }

  const toggle = button('economy-toggle', '物资 / 建造');
  toggle.id = 'economy-toggle';
  toggle.setAttribute('aria-controls', 'economy-panel');
  toggle.setAttribute('aria-expanded', 'false');
  toggle.setAttribute('aria-haspopup', 'dialog');
  const panel = element('section', 'economy-panel');
  panel.id = 'economy-panel';
  panel.hidden = true;
  panel.tabIndex = -1;
  panel.setAttribute('role', 'dialog');
  panel.setAttribute('aria-labelledby', 'economy-title');
  panel.setAttribute('aria-describedby', 'economy-guide');
  const header = element('header', 'economy-header');
  const heading = element('h2', '', '物资与建造');
  heading.id = 'economy-title';
  const closeButton = button('economy-close', '×');
  closeButton.setAttribute('aria-label', '关闭物资与建造面板');
  header.append(heading, closeButton);
  const guide = element('p', 'economy-guide', '收集木料 → 修复屋顶 → 种植食物 → 改船远航');
  guide.id = 'economy-guide';
  const notice = element('p', 'economy-notice', '试玩进度暂不保存');
  const feedback = element('p', 'economy-feedback', '点击场景物件可查看配方，确认操作后才会消耗物资。');
  feedback.id = 'economy-feedback';
  feedback.setAttribute('role', 'status');
  feedback.setAttribute('aria-live', 'polite');
  feedback.setAttribute('aria-atomic', 'true');
  const tabList = element('div', 'economy-tabs');
  tabList.setAttribute('role', 'tablist');
  tabList.setAttribute('aria-label', '物资与建造分类');
  panel.append(header, guide, notice, feedback, tabList);
  for (const [id, label] of [['collect', '采集'], ['grow', '种植'], ['build', '建造']]) {
    const tab = button('economy-tab', label);
    tab.id = `economy-tab-${id}`;
    tab.dataset.econTab = id;
    tab.setAttribute('role', 'tab');
    tab.setAttribute('aria-controls', `economy-section-${id}`);
    const section = element('div', 'economy-section');
    section.id = `economy-section-${id}`;
    section.setAttribute('role', 'tabpanel');
    section.setAttribute('aria-labelledby', tab.id);
    tabs.set(id, tab);
    sections.set(id, section);
    tab.addEventListener('click', () => selectTab(id));
    tab.addEventListener('keydown', event => {
      const ids = [...tabs.keys()];
      let index = ids.indexOf(id);
      if (event.key === 'ArrowRight') index = (index + 1) % ids.length;
      else if (event.key === 'ArrowLeft') index = (index + ids.length - 1) % ids.length;
      else if (event.key === 'Home') index = 0;
      else if (event.key === 'End') index = ids.length - 1;
      else return;
      event.preventDefault();
      selectTab(ids[index]);
      tabs.get(ids[index]).focus();
    });
    tabList.append(tab);
    panel.append(section);
  }
  stopSceneEvents(toggle);
  stopSceneEvents(panel);
  panel.addEventListener('keydown', event => event.stopPropagation());
  document.body.append(toggle, panel);

  function selectTab(id) {
    activeTab = id;
    for (const [key, tab] of tabs) {
      tab.setAttribute('aria-selected', String(key === id));
      tab.tabIndex = key === id ? 0 : -1;
      sections.get(key).hidden = key !== id;
    }
  }
  function close() {
    panel.hidden = true;
    toggle.setAttribute('aria-expanded', 'false');
    toggle.focus({ preventScroll: true });
  }
  function open(id) {
    const card = cards.get(id);
    panel.hidden = false;
    toggle.setAttribute('aria-expanded', 'true');
    selectTab(card?.tab || activeTab);
    refreshPanel();
    panelElapsed = 0;
    for (const entry of cards.values()) entry.root.dataset.selected = String(entry === card);
    if (card) {
      card.root.focus({ preventScroll: true });
      card.root.scrollIntoView({ block: 'nearest', behavior: 'instant' });
    } else closeButton.focus({ preventScroll: true });
  }
  toggle.addEventListener('click', () => panel.hidden ? open() : close());
  closeButton.addEventListener('click', close);
  document.addEventListener('keydown', event => {
    if (panel.hidden) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      close();
    } else if (event.key === 'Tab') {
      const focusable = [...panel.querySelectorAll('button:not(:disabled)')]
        .filter(node => node.tabIndex >= 0 && !node.closest('[hidden]'));
      const current = focusable.indexOf(document.activeElement);
      if (current < 0 || (!event.shiftKey && current === focusable.length - 1) || (event.shiftKey && current === 0)) {
        event.preventDefault();
        (event.shiftKey ? focusable.at(-1) : focusable[0]).focus();
      }
      event.stopPropagation();
    }
  }, true);
  document.addEventListener('focusin', event => {
    if (!panel.hidden && !panel.contains(event.target)) closeButton.focus({ preventScroll: true });
  });

  function report(ok, message) {
    feedback.dataset.result = ok ? 'success' : 'failure';
    text(feedback, message);
    feedback.scrollIntoView({ block: 'nearest', behavior: 'instant' });
    // 长原因只留在面板，不重复触发场景浮字 notify。
  }
  function execute(card) {
    const model = card.read();
    if (!model.available) {
      report(false, model.reason || '当前操作不可用。');
      refreshPanel();
      return;
    }
    let result;
    try {
      result = model.invoke();
      const ok = result === true || result?.ok === true || (result === undefined && model.allowVoid);
      report(ok, ok ? (result?.reward && Object.keys(result.reward).length
        ? `${model.success} 获得${bundle(result.reward)}。` : model.success)
        : result?.reason || card.read().reason || '操作未完成，请稍后重试；未确认成功前请勿重复操作。');
    } catch (error) {
      report(false, `操作未完成：${error instanceof Error ? error.message : '请稍后重试'}`);
    } finally {
      try { syncUI(); }
      catch { report(false, '操作已调用，但界面同步失败，请检查当前库存后再试。'); }
      refreshPanel();
      updateVisuals(0);
      updateOverlays();
    }
  }
  function makeCard(id, tab, name, read) {
    const root = element('article', 'economy-card');
    root.id = `economy-card-${id}`;
    root.dataset.econCard = id;
    root.tabIndex = -1;
    const top = element('div', 'economy-card-top');
    const title = element('h3', '', name);
    title.id = `${root.id}-title`;
    root.setAttribute('aria-labelledby', title.id);
    const status = element('span', 'economy-card-status');
    top.append(title, status);
    const description = element('p', 'economy-description');
    const list = element('dl', 'economy-details');
    const fields = {};
    for (const [key, label] of [['cost', '成本'], ['reward', '收益'], ['requires', '前置'], ['missing', '缺口'], ['source', '来源']]) {
      const row = element('div');
      fields[key] = element('dd');
      row.append(element('dt', '', label), fields[key]);
      list.append(row);
    }
    const progress = element('progress', 'economy-progress');
    progress.max = 1;
    progress.hidden = true;
    progress.setAttribute('aria-label', `${name}进度`);
    const reason = element('p', 'economy-reason');
    reason.id = `${root.id}-reason`;
    const actions = element('div', 'economy-card-actions');
    const action = button('economy-action', '查看');
    action.dataset.econAction = read().action;
    action.setAttribute('aria-describedby', reason.id);
    const secondary = button('economy-secondary', '查看建造');
    secondary.hidden = true;
    actions.append(action, secondary);
    root.append(top, description, list, progress, reason, actions);
    sections.get(tab).append(root);
    const card = { root, tab, status, description, fields, progress, reason, action, secondary, read };
    cards.set(id, card);
    action.addEventListener('click', () => execute(card));
    secondary.addEventListener('click', () => {
      const destination = read().secondary;
      if (destination) open(destination.id);
    });
    return card;
  }
  function refreshPanel() {
    if (panel.hidden) return;
    for (const card of cards.values()) {
      const model = card.read();
      text(card.status, model.status);
      text(card.description, model.description);
      for (const [key, field] of Object.entries(card.fields)) text(field, model[key]);
      text(card.reason, model.reason || '材料与前置已满足，可以操作。');
      text(card.action, model.label);
      card.action.disabled = !model.available;
      card.action.dataset.econAction = model.action;
      card.root.dataset.state = model.state || (model.available ? 'ready' : 'blocked');
      card.progress.hidden = model.progress === undefined;
      if (model.progress !== undefined) {
        card.progress.value = Math.max(0, Math.min(1, model.progress));
        card.progress.setAttribute('aria-valuetext', model.status);
      }
      card.secondary.hidden = !model.secondary;
      if (model.secondary) {
        text(card.secondary, model.secondary.label);
        card.secondary.dataset.econAction = `open:${model.secondary.id}`;
      }
    }
  }

  for (const node of economy.nodes) makeCard(node.id, 'collect', node.name, () => {
    const availability = economy.getCollectionAction(node.id);
    return localAction({
      action: `collect:${node.id}`, ...availability, label: node.left > 0 ? '等待补充' : '收集物资',
      status: node.left > 0 ? `${Math.ceil(node.left)}秒后补充` : '可采集',
      description: `${zoneLabel(node.zone)} · 收集后${node.cooldown}秒补充。`, cost: '免费', reward: bundle(node.reward),
      requires: node.zone === 'zone4' ? '升级船只解锁远海；当前区域空闲靠岸' : '当前区域空闲靠岸',
      missing: economy.canReceive(node.reward) ? '无' : '库存空间不足，请先消耗对应物资',
      source: node.id === 'sea_cache' ? '远海贝匣。珍珠用于浅水养殖：木料 ×3、旧零件 ×2、珍珠 ×1，前置船只2级。' : `${zoneLabel(node.zone)}的${node.name}，点击场景标记可定位本卡。`,
      progress: node.left > 0 ? 1 - node.left / node.cooldown : undefined,
      invoke: () => economy.collect(node.id), success: `${node.name}已收集。`
    }, node.zone);
  });
  makeCard('salvage', 'collect', '家园绞盘打捞', () => {
    const left = state.salvageCooldown || 0;
    const reward = { wood: 3, parts: 2 };
    const reason = busy() ? '旅人忙碌中，请等待当前操作结束。' : left > 0 ? `绞盘冷却中，还需${Math.ceil(left)}秒。`
      : !economy.canReceive(reward) ? '木料或旧零件库存空间不足，请先消耗物资。' : '';
    return localAction({
      action: 'salvage', status: left > 0 ? `${Math.ceil(left)}秒后可用` : '可打捞',
      description: '家园外侧绞盘台，每次打捞后冷却40秒。', cost: '免费', reward: bundle(reward),
      requires: '晴空水巷空闲靠岸', missing: economy.canReceive(reward) ? '无' : '库存空间不足',
      source: '家园绞盘台的漂流物，补充木料与旧零件。', label: '打捞漂流物', available: !reason, reason,
      invoke: performSalvage, success: `打捞成功，获得${bundle(reward)}。`
    }, 'zone1');
  });
  makeCard('trade', 'collect', '食物换海贝', () => {
    const cost = { food: 2 };
    const missing = economy.missing(cost);
    const reason = busy() ? '旅人忙碌中，请等待当前操作结束。' : Object.keys(missing).length ? `还缺${bundle(missing)}，请在种植页播种并收获。`
      : !economy.canReceive({ coins: 12 }) ? '海贝余额无法接收本次收益。' : '';
    return localAction({
      action: 'trade', status: '家园交易', description: '用收获的食物交换建造所需海贝。', ...costs(cost),
      reward: '海贝 ×12', requires: '晴空水巷空闲靠岸', label: '交换12海贝', available: !reason, reason,
      invoke: () => economy.tradeFood(), success: '交易完成，已消耗食物 ×2。'
    }, 'zone1');
  });
  for (const plot of economy.plots) makeCard(plot.id, 'grow', plot.name, () => {
    const availability = economy.getPlotAction(plot.id);
    const unlocked = siteLevel(plot.siteId) >= plot.minLevel;
    const improved = economy.facilities.greenhouse.level >= 1;
    const reward = plot.reward || { food: improved ? 3 : 2, seeds: 1 };
    const growing = plot.phase === 'growing';
    const dry = growing && (plot.moisture ?? 0) <= 0;
    const moisture = Math.round((plot.moisture ?? 0) * 100);
    const duration = improved ? 26 : 34;
    return localAction({
      action: `plot:${plot.id}`, ...availability,
      status: !unlocked ? '待修复'
        : dry ? '土壤干涸 · 需要浇水'
        : growing ? `生长中 · ${Math.ceil(plot.remaining)}秒 · 水分${moisture}%`
        : plot.phase === 'ready' ? '可收获' : '空菜箱',
      description: `${zoneLabel(plot.zone)} · 播种后约${duration}秒成熟，中途土壤会变干，干了必须浇水才会继续长。成熟后需主动收获。`,
      ...costs(plot.phase === 'empty' ? { seeds: 1 } : {}), cost: '每次播种：种子 ×1；浇水与收获免费',
      reward: `${bundle(reward)}（含返还种子 ×1）`, requires: prerequisites({ [plot.siteId]: plot.minLevel }),
      source: MATERIALS.seeds.source, progress: growing ? 1 - plot.remaining / plot.duration : plot.phase === 'ready' ? 1 : undefined,
      state: unlocked ? (dry ? 'dry' : plot.phase) : 'locked',
      secondary: !unlocked ? { label: '去建造页修复', id: plot.siteId } : undefined,
      invoke: () => economy.actPlot(plot.id),
      success: plot.phase === 'ready' ? '收获完成，种子已返还。'
        : growing ? '浇水完成，蔬菜继续生长。'
        : '播种成功，已消耗种子 ×1，土壤已浇透。'
    }, plot.zone);
  });
  for (const site of buildSites) makeCard(site.id, 'build', site.name, () => {
    const maxed = site.level >= site.maxLevel;
    const stage = maxed ? null : site.stages[site.level];
    const cost = stage ? { coins: stage.cost || 0, ...(stage.materials || (site.id === 'shallow_aquaculture' ? { wood: 3, parts: 2, pearl: 1 } : {})) } : {};
    const requires = { ...site.requires, ...stage?.requires, ...(site.id === 'shallow_aquaculture' ? { boat2: 2 } : {}) };
    const stored = Math.floor(site.storedCoins || 0);
    // 攒满阈值才允许收取，少数几枚时热点保持"积累中"，不和升级按钮抢点击。
    const ready = stored >= economy.harvestThreshold;
    const constructing = state.activeJobSite === site || state.activeJobSite?.id === site.id;
    const missing = economy.missing(cost);
    const reason = busy() ? '旅人忙碌中，请等待当前操作结束。'
      : ready ? ''
      : requirementReason(requires) || (Object.keys(missing).length ? `还缺${bundle(missing)}，来源见上方。` : '');
    return {
      action: `build:${site.id}`, status: constructing ? `施工中 · ${Math.round((state.jobProgress || 0) * 100)}%` : `${site.level}/${site.maxLevel}级 · ${ready ? `待收${stored}海贝` : stored > 0 ? `积累${stored}/${economy.harvestThreshold}` : '无待收'}`,
      description: `${stage?.desc || '建筑已修复，定期产出的海贝需要主动收取。'} 挂机产出攒满${economy.harvestThreshold}枚才会亮出收取标志，在此之前可以先继续升级。`,
      ...costs(cost), cost: stage ? `下次升级：${bundle(cost)}；收取免费` : '已完成升级；收取免费',
      reward: `当前每轮产出${site.coinsPerCycle || 0}海贝${stage ? `；升级后每轮增加${stage.rateAdd || 0}海贝` : ''}`,
      requires: `${maxed ? '建筑已完成' : `${site.level}级 → ${site.level + 1}级`}；${prerequisites(requires)}；旅人空闲靠岸`,
      label: ready ? `收取${stored}海贝` : constructing ? '施工中' : maxed ? '已完成升级' : `建造 / 升至${site.level + 1}级`,
      available: !reason, reason, progress: constructing ? state.jobProgress || 0 : undefined,
      invoke: () => activateSite(site), success: ready ? `已收取${stored}海贝，未消耗建造材料。` : `已安排${site.name}升级，旅人将前往施工。`
    };
  });
  for (const [id, recipe] of Object.entries(FACILITIES)) makeCard(id, 'build', recipe.name, () => {
    const facility = economy.facilities[id];
    const job = economy.job?.id === id ? economy.job : null;
    const built = facility.level >= 1;
    const stored = facility.stored.parts || 0;
    const availability = economy.getFacilityAction(id);
    return localAction({
      action: `facility:${id}`, ...availability,
      status: job ? `施工中 · ${Math.ceil(job.remaining)}秒` : !built ? '未建造' : id === 'recycler' ? `暂存${stored}/6零件` : '温室加成生效',
      description: recipe.description, ...costs(built || job ? {} : recipe.cost), cost: `${bundle(recipe.cost)}（一次建造，收取免费）`,
      reward: id === 'recycler' ? `每30秒旧零件 ×2；暂存${stored}/6${built && stored < 6 ? `；下批${Math.ceil(30 - facility.timer)}秒` : ''}` : '后续播种26秒成熟，收获食物 ×3、返还种子 ×1',
      requires: prerequisites(recipe.requires),
      source: sources(recipe.cost), progress: job ? 1 - job.remaining / job.duration : undefined,
      invoke: () => built ? economy.collectFacility(id) : economy.buildFacility(id), success: built ? '设施产物已收取。' : `${recipe.name}已开工，6秒后完工。`
    }, 'zone1');
  });
  makeCard('ship', 'build', '船只改造 · 远海航行', () => {
    const availability = economy.getShipAction();
    const upgraded = state.shipLevel >= 2 || state.farSeaUnlocked;
    return localAction({
      action: 'ship', ...availability, label: upgraded ? '远海已解锁' : '改造船只', status: `船只${state.shipLevel || 1}级`,
      description: '升级后可航向远海收集珍珠。浅水养殖需要木料 ×3、旧零件 ×2、珍珠 ×1，以及船只2级。',
      ...costs(upgraded ? {} : SHIP_RECIPE.cost), cost: bundle(SHIP_RECIPE.cost), reward: '船只升至2级，解锁远海街町及远海贝匣',
      requires: prerequisites(SHIP_RECIPE.requires), source: sources(SHIP_RECIPE.cost),
      invoke: upgradeShip, success: '船只已升级至2级，远海航线与珍珠采集已解锁。'
    }, 'zone1');
  });
  selectTab('collect');

  const boxGeometry = new THREE.BoxGeometry(1, 1, 1);
  const sphereGeometry = new THREE.SphereGeometry(1, 8, 6);
  const ringGeometry = new THREE.CircleGeometry(.68, 24);
  const material = color => new THREE.MeshLambertMaterial({ color });
  const palette = {
    wood: material('#b98b61'), light: material('#f4e7bd'), soil: material('#6b5547'),
    leaf: material('#79a568'), green: material('#aec789'), metal: material('#71979e'),
    blue: material('#486f92'), orange: material('#ecaa58'), shell: material('#dbb6a5'),
    glass: new THREE.MeshBasicMaterial({ color: '#b5e2ce', transparent: true, opacity: .24, depthWrite: false }),
    glow: new THREE.MeshBasicMaterial({ color: '#e7edbe', transparent: true, opacity: .2, depthWrite: false, side: THREE.DoubleSide })
  };
  const transform = new THREE.Object3D();
  // 同材质小部件合并为实例批次，框架与叶片不逐个增加绘制调用。
  function instances(parent, geometry, mat, parts) {
    const mesh = new THREE.InstancedMesh(geometry, mat, parts.length);
    parts.forEach((part, index) => {
      transform.position.set(...part.p);
      transform.scale.set(...part.s);
      transform.rotation.set(...(part.r || [0, 0, 0]));
      transform.updateMatrix();
      mesh.setMatrixAt(index, transform.matrix);
    });
    mesh.instanceMatrix.needsUpdate = true;
    parent.add(mesh);
    return mesh;
  }
  function box(parent, mat, p, s, r) {
    return instances(parent, boxGeometry, mat, [{ p, s, r }]);
  }
  function visualRoot(id, zone, name, height) {
    const root = new THREE.Group();
    root.name = `economy:${id}`;
    root.position.set(...POSITIONS[id]);
    roots.push(root);
    targets.set(root, id);
    worldGroup.add(root);
    // 只作场景标记：不接管指针，避免遮住小船、建筑热点与地面点击。
    // 画面上只留一个图标（无外框、无文字），完整说明放在 aria-label / title 里。
    const marker = element('span', 'economy-marker');
    marker.dataset.econMarker = id;
    marker.tabIndex = -1;
    marker.hidden = true;
    marker.setAttribute('aria-hidden', 'true');
    document.body.append(marker);
    const body = new THREE.Group();
    root.add(body);
    const item = { id, zone, root, body, marker, anchor: new THREE.Vector3(0, height, 0), label: name, icon: '' };
    visuals.push(item);
    return item;
  }
  for (const node of economy.nodes) {
    // 采集标记抬高一点，不压住模型本身（图标下沿刚好落在锚点上）。
    const item = visualRoot(node.id, node.zone, node.name, 1.18);
    item.kind = 'node';
    item.data = node;
    item.icon = node.icon || '🎁';
    box(item.root, palette.wood, [0, .04, 0], [1.05, .08, 1.05]);
    const color = node.id === 'garden_cache' ? palette.green : node.id === 'workshop_cache' ? palette.metal : node.id === 'sea_cache' ? palette.shell : palette.wood;
    box(item.body, color, [0, .53, 0], [.9, .9, .9]);
    instances(item.body, boxGeometry, palette.light, [
      { p: [0, 1, 0], s: [.94, .08, .96] },
      { p: [-.23, .56, .458], s: [.09, .86, .025] }, { p: [.23, .56, .458], s: [.09, .86, .025] },
      { p: [0, 1.05, 0], s: [.13, .025, .92] }
    ]);
    if (node.id === 'garden_cache') instances(item.body, sphereGeometry, palette.leaf, [
      { p: [-.14, 1.15, 0], s: [.23, .055, .13], r: [0, 0, -.4] },
      { p: [.14, 1.15, 0], s: [.23, .055, .13], r: [0, 0, .4] }
    ]);
    if (node.id === 'workshop_cache') instances(item.body, boxGeometry, palette.blue, [
      { p: [-.14, 1.13, 0], s: [.38, .16, .3], r: [0, .4, .12] }, { p: [.18, 1.24, .02], s: [.3, .2, .3], r: [0, -.3, 0] }
    ]);
    if (node.id === 'sea_cache') instances(item.body, sphereGeometry, palette.light, [
      { p: [-.2, 1.09, 0], s: [.25, .12, .27] }, { p: [.14, 1.14, .03], s: [.22, .16, .24] }
    ]);
    item.ring = new THREE.Mesh(ringGeometry, palette.glow);
    item.ring.rotation.x = -Math.PI / 2;
    item.ring.position.y = .085;
    item.root.add(item.ring);
  }
  for (const plot of economy.plots) {
    const item = visualRoot(plot.id, plot.zone, plot.name, 0.9);
    item.kind = 'plot';
    item.data = plot;
    item.icon = '🌱';
    instances(item.body, boxGeometry, palette.wood, [
      { p: [0, .14, -.46], s: [2, .28, .08] }, { p: [0, .14, .46], s: [2, .28, .08] },
      { p: [-.96, .14, 0], s: [.08, .28, .84] }, { p: [.96, .14, 0], s: [.08, .28, .84] }
    ]);
    box(item.body, palette.soil, [0, .1, 0], [1.84, .18, .84]);
    item.plants = new THREE.Group();
    item.plants.position.y = .2;
    item.body.add(item.plants);
    const stems = [], leaves = [], fruits = [];
    for (const x of [-.6, 0, .6]) {
      stems.push({ p: [x, .25, 0], s: [.035, .5, .035] });
      for (const sign of [-1, 1]) leaves.push({ p: [x + sign * .14, .32, 0], s: [.25, .055, .12], r: [0, sign * .35, sign * .4] });
      fruits.push({ p: [x, .4, .13], s: [.13, .15, .13] });
    }
    instances(item.plants, boxGeometry, palette.leaf, stems);
    instances(item.plants, sphereGeometry, palette.leaf, leaves);
    item.fruits = instances(item.plants, sphereGeometry, palette.orange, fruits);
  }
  for (const [id, recipe] of Object.entries(FACILITIES)) {
    const item = visualRoot(id, 'zone1', recipe.name, id === 'greenhouse' ? 1.95 : 1.35);
    item.kind = 'facility';
    item.icon = id === 'greenhouse' ? '🥬' : '⚙';
    box(item.root, palette.wood, [0, .035, 0], [id === 'greenhouse' ? 2.1 : 1.5, .07, 1.3]);
    if (id === 'greenhouse') {
      const frame = [];
      for (const x of [-1, 1]) for (const z of [-.6, .6]) frame.push({ p: [x, .65, z], s: [.075, 1.3, .075] });
      for (const y of [.15, 1.3]) {
        for (const z of [-.6, .6]) frame.push({ p: [0, y, z], s: [2.1, .075, .075] });
        for (const x of [-1, 1]) frame.push({ p: [x, y, 0], s: [.075, .075, 1.25] });
      }
      frame.push({ p: [0, 1.77, 0], s: [2.1, .075, .075] });
      for (const x of [-1, 1]) for (const sign of [-1, 1]) frame.push({ p: [x, 1.54, sign * .3], s: [.075, .075, .78], r: [-sign * .66, 0, 0] });
      instances(item.body, boxGeometry, palette.light, frame);
      box(item.body, palette.glass, [0, .73, 0], [1.98, 1.16, 1.18]);
      instances(item.body, boxGeometry, palette.glass, [-1, 1].map(sign => ({ p: [0, 1.54, sign * .3], s: [2.02, .035, .78], r: [-sign * .66, 0, 0] })));
      instances(item.body, sphereGeometry, palette.leaf, [-.6, 0, .6].map(x => ({ p: [x, .38, 0], s: [.28, .27, .25] })));
    } else {
      instances(item.body, boxGeometry, palette.wood, [
        { p: [-.55, .45, 0], s: [.1, .9, .9] }, { p: [.55, .45, 0], s: [.1, .9, .9] },
        { p: [0, .88, 0], s: [1.5, .12, 1.05] }, { p: [0, .28, 0], s: [1, .5, .8] }
      ]);
      box(item.body, palette.metal, [0, 1.05, -.25], [1.4, .09, .78], [-.35, 0, 0]);
      instances(item.body, boxGeometry, palette.blue, [-.45, 0, .45].map(x => ({ p: [x, 1.105, -.25], s: [.4, .025, .7], r: [-.35, 0, 0] })));
      box(item.body, palette.light, [0, .4, .415], [.27, .09, .025]);
    }
  }

  function updateVisuals(t) {
    for (const item of visuals) {
      if (item.kind === 'node') {
        const ready = item.data.left <= 0;
        item.root.visible = !needsBoat(item.zone);
        item.body.visible = ready;
        item.ring.visible = ready;
        item.ring.scale.setScalar(1 + Math.sin(t * 1.6) * .035);
        // 冷却中不显示标记（只在可采集时出现），所以图标只有一种。
        item.icon = item.data.icon || '🎁';
        item.label = ready ? `${item.data.name} · 可采集` : `${item.data.name} · ${Math.ceil(item.data.left)}秒`;
      } else if (item.kind === 'plot') {
        const plot = item.data;
        item.root.visible = siteLevel(plot.siteId) >= plot.minLevel;
        item.plants.visible = plot.phase !== 'empty';
        const growth = plot.phase === 'ready' ? 1 : Math.max(0, Math.min(1, 1 - plot.remaining / plot.duration));
        const dry = plot.phase === 'growing' && (plot.moisture ?? 0) <= 0;
        // 干透时整株蔫下去一点、果实收回，俯视时一眼能看出"该浇水了"。
        const wilt = dry ? .84 : 1;
        item.plants.scale.set(wilt, (.18 + growth * .82) * wilt, wilt);
        item.fruits.visible = !dry && (plot.phase === 'ready' || growth > .65);
        item.fruits.material = plot.phase === 'ready' ? palette.orange : palette.green;
        // 菜箱的三种状态用同一个图标位表达：成熟→萝卜，干透→水滴，其余→嫩芽。
        item.icon = plot.phase === 'ready' ? '🥕' : dry ? '💧' : '🌱';
        item.label = `${plot.name} · ${plot.phase === 'ready' ? '可收获' : dry ? '需要浇水' : plot.phase === 'growing' ? `${Math.ceil(plot.remaining)}秒` : '播种'}`;
      } else {
        const facility = economy.facilities[item.id];
        const job = economy.job?.id === item.id ? economy.job : null;
        item.body.visible = facility.level >= 1 || Boolean(job);
        item.body.scale.y = job ? Math.max(.06, 1 - job.remaining / job.duration) : 1;
        item.icon = job ? '🔧' : facility.level < 1 ? '🔨' : item.id === 'greenhouse' ? '🥬' : '⚙';
        item.label = `${FACILITIES[item.id].name} · ${job ? `施工${Math.ceil(job.remaining)}秒` : facility.level < 1 ? '待建造' : item.id === 'recycler' ? `零件${facility.stored.parts || 0}/6` : '已建成'}`;
      }
    }
  }
  const projected = new THREE.Vector3();
  const canvas = document.querySelector('canvas');
  function updateOverlays() {
    const rect = canvas ? canvas.getBoundingClientRect() : { left: 0, top: 0, width: window.innerWidth, height: window.innerHeight };
    camera.updateWorldMatrix(true, false);
    for (const item of visuals) {
      // 只给“现在就能互动”的物体加标签：未建成的设施、冷却中的箱子和空菜箱不再堆在画面上。
      const exists = item.kind === 'node' ? item.data.left <= 0
        : item.kind === 'plot' ? item.root.visible
        : item.body.visible;
      let visible = exists && item.root.visible && state.currentZone === item.zone && state.workerMode === 'IDLE_ASHORE' && !needsBoat(item.zone);
      for (let parent = item.root.parent; visible && parent; parent = parent.parent) visible = parent.visible;
      if (visible) {
        item.root.updateWorldMatrix(true, false);
        projected.copy(item.anchor).applyMatrix4(item.root.matrixWorld).project(camera);
        const x = rect.left + (projected.x + 1) * rect.width / 2;
        const y = rect.top + (1 - projected.y) * rect.height / 2;
        // 为整个图标留边距，而不仅仅判断锚点是否在屏幕内。
        visible = projected.z >= -1 && projected.z <= 1 && Number.isFinite(x) && Number.isFinite(y)
          && x >= Math.max(rect.left, 0) + 40 && x <= Math.min(rect.left + rect.width, window.innerWidth) - 40
          && y >= Math.max(rect.top, 0) + 56 && y <= Math.min(rect.top + rect.height, window.innerHeight) - 16;
        if (visible) {
          item.marker.style.left = `${x.toFixed(1)}px`;
          item.marker.style.top = `${y.toFixed(1)}px`;
          // 图标中心（用于屏幕空间命中）：图标下沿贴锚点，所以中心要往上抬半个图标。
          item.marker._sx = x;
          item.marker._sy = y - (item.marker.offsetHeight || 32) / 2;
          text(item.marker, item.icon);
          item.marker.dataset.state = item.kind === 'node' ? 'ready'
            : item.kind === 'plot' ? (item.icon === '💧' ? 'thirsty' : item.icon === '🥕' ? 'ready' : 'growing')
            : item.icon === '🔧' || item.icon === '🔨' ? 'busy' : 'ready';
          const label = item.label;
          item.marker.setAttribute('aria-label', `查看${label}物资卡片`);
          item.marker.title = label;
        }
      }
      item.marker.hidden = !visible;
    }
  }

  // 图标只画一个 emoji、不接管指针，但玩家会直接点图标本体。
  // 所以在屏幕空间里按图标中心做命中（半径 22px），返回和点 3D 物件一样的 economy 目标。
  function markerAt(clientX, clientY) {
    let best = null;
    for (const item of visuals) {
      const el = item.marker;
      if (!el || el.hidden || !Number.isFinite(el._sx)) continue;
      const d = Math.hypot(el._sx - clientX, el._sy - clientY);
      if (d <= 22 && (!best || d < best.d)) best = { d, id: item.id };
    }
    return best ? { type: 'economy', id: best.id } : null;
  }

  // 悬停时把对应图标点亮（鼠标走的是 canvas，图标本身没事件）。
  function setHot(id) {
    for (const item of visuals) item.marker.classList?.toggle('is-hot', Boolean(id) && item.id === id);
  }

  function findTarget(object) {
    let id;
    for (let current = object; current; current = current.parent) {
      if (!current.visible) return null;
      if (targets.has(current)) id = targets.get(current);
    }
    return id ? { type: 'economy', id } : null;
  }
  function handleTarget(target) {
    if (target?.type !== 'economy' || !cards.has(target.id)) return false;
    open(target.id);
    return true;
  }
  function update(dt, t) {
    updateVisuals(t);
    if (panel.hidden) { panelElapsed = 0; return; }
    panelElapsed += dt;
    if (panelElapsed >= .2) {
      panelElapsed %= .2;
      refreshPanel();
    }
  }
  updateVisuals(0);
  return { update, updateOverlays, roots, findTarget, markerAt, setHot, open, handleTarget };
}
