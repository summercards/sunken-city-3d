'use strict';

const assert = require('node:assert/strict');
const { test } = require('node:test');

(async () => {
  const economyModule = await import('../economy.js');
  const { MATERIALS, COLLECTIONS, FACILITIES, SHIP_RECIPE, CROP, EXPLORE, HARVEST_THRESHOLD, createEconomy } = economyModule;
  const completeLevels = { home_cabin: 2, rooftop_planter: 1, yokohama_station: 1 };

  function setup(overrides = {}, siteLevels = {}) {
    const state = {
      coins: 80, wood: 0, parts: 0, seeds: 3, food: 0, fish: 0, pearl: 0,
      shipLevel: 1, farSeaUnlocked: false, currentZone: 'zone1',
      workerMode: 'IDLE_ASHORE', activeJobSite: null,
      ...overrides
    };
    const levels = { ...siteLevels };
    return { state, levels, economy: createEconomy(state, (id) => levels[id] ?? 0) };
  }

  function snapshot({ state, economy }) {
    return structuredClone({
      state, nodes: economy.nodes, plots: economy.plots,
      facilities: economy.facilities, job: economy.job
    });
  }

  function unchanged(context, operation) {
    const before = snapshot(context);
    const result = operation();
    assert.deepEqual(snapshot(context), before);
    return result;
  }

  function buildRecycler(overrides = {}) {
    const context = setup({ wood: 10, parts: 10, ...overrides }, completeLevels);
    assert.equal(context.economy.buildFacility('recycler').ok, true);
    context.economy.tick(6);
    return context;
  }

  test('导出配置、名称、容量和配方完全匹配', () => {
    assert.deepEqual(Object.keys(economyModule).sort(),
      ['COLLECTIONS', 'CROP', 'EXPLORE', 'FACILITIES', 'HARVEST_THRESHOLD', 'MATERIALS', 'SHIP_RECIPE', 'createEconomy'].sort());
    assert.deepEqual(Object.fromEntries(Object.entries(MATERIALS).map(([key, value]) => [key, [value.name, value.capacity]])), {
      coins: ['海贝', Infinity], wood: ['木料', 60], parts: ['旧零件', 60],
      seeds: ['种子', 20], food: ['食物', 40], fish: ['鱼', 40], pearl: ['珍珠', 12]
    });
    for (const material of Object.values(MATERIALS)) assert.match(material.source, /[\u4e00-\u9fff]/);
    assert.deepEqual(COLLECTIONS, [
      { id: 'home_crate', name: '屋顶物资箱', zone: 'zone1', reward: { wood: 3, parts: 1 }, cooldown: 34 },
      { id: 'shell_bed', name: '浅滩贝床', zone: 'zone1', reward: { coins: 5 }, cooldown: 26 },
      { id: 'canal_shoal', name: '水巷鱼群', zone: 'zone1', reward: { fish: 2 }, cooldown: 30 },
      { id: 'garden_cache', name: '农场种子箱', zone: 'zone3', reward: { wood: 4, seeds: 2 }, cooldown: 42 },
      { id: 'farm_shoal', name: '农场浅滩鱼群', zone: 'zone3', reward: { fish: 3 }, cooldown: 36 },
      { id: 'workshop_cache', name: '铁道回收堆', zone: 'zone2', reward: { parts: 3, wood: 1 }, cooldown: 42 },
      { id: 'sea_cache', name: '远海贝匣', zone: 'zone4', reward: { pearl: 1, parts: 2 }, cooldown: 60 }
    ]);
    assert.deepEqual(FACILITIES, {
      greenhouse: {
        name: '屋顶温室', cost: { coins: 15, wood: 5, parts: 3 },
        requires: { home_cabin: 2, rooftop_planter: 1 },
        description: '蔬菜成熟缩短为26秒，每次收获3份食物。'
      },
      recycler: {
        name: '太阳能回收台', cost: { coins: 15, wood: 4, parts: 4 },
        requires: { home_cabin: 2, yokohama_station: 1 },
        description: '每30秒分拣2个旧零件，可暂存6个，需主动收取。'
      }
    });
    assert.deepEqual(SHIP_RECIPE, { cost: { coins: 25, wood: 6, parts: 4, food: 2 }, requires: { home_cabin: 2, rooftop_planter: 1 } });
    assert.equal(HARVEST_THRESHOLD, 10);
    assert.deepEqual(EXPLORE, { step: 7, chance: 0.6, wood: [1, 2], parts: [0, 1] });
    assert.equal(CROP.dryDuration, 34);
    assert.equal(CROP.greenhouseDuration, 26);
  });

  test('工厂不初始化或改写外部状态，实例和配置独立', () => {
    const state = {};
    const economy = createEconomy(state, () => 0);
    assert.deepEqual(state, {});
    assert.equal(economy.materials, MATERIALS);
    assert.deepEqual(economy.nodes, COLLECTIONS.map((node) => ({ ...node, left: 0, collections: 0 })));
    assert.deepEqual(economy.plots, [
      { id: 'home_plot', name: '木屋菜箱', zone: 'zone1', siteId: 'home_cabin', minLevel: 2, phase: 'empty', remaining: 0, duration: 34, reward: null, moisture: 0 },
      { id: 'farm_plot', name: '农场菜箱', zone: 'zone3', siteId: 'rooftop_planter', minLevel: 1, phase: 'empty', remaining: 0, duration: 34, reward: null, moisture: 0 }
    ]);
    assert.deepEqual(economy.facilities, { greenhouse: { level: 0, stored: {} }, recycler: { level: 0, stored: {}, timer: 0 } });
    assert.equal(economy.job, null);
    const other = setup().economy;
    economy.nodes[0].reward.wood = 99;
    economy.nodes[0].left = 10;
    economy.facilities.recycler.stored.parts = 6;
    assert.equal(COLLECTIONS[0].reward.wood, 3);
    assert.equal(other.nodes[0].reward.wood, 3);
    assert.equal(other.nodes[0].left, 0);
    assert.deepEqual(other.facilities.recycler.stored, {});
  });

  test('缺口按不存在的余额为0计算，合法收支一次性提交', () => {
    const state = {};
    const economy = createEconomy(state, () => 0);
    assert.deepEqual(economy.missing({ coins: 4, wood: 0, food: 2 }), { coins: 4, food: 2 });
    assert.deepEqual(state, {});
    assert.equal(economy.spend({ coins: 1 }), false);
    assert.deepEqual(state, {});
    assert.equal(economy.canReceive({ wood: 60, seeds: 20 }), true);
    assert.deepEqual(state, {});
    assert.equal(economy.receive({ wood: 60, seeds: 20 }), true);
    assert.deepEqual(state, { wood: 60, seeds: 20 });
    assert.equal(economy.spend({ wood: 3, seeds: 2 }), true);
    assert.deepEqual(state, { wood: 57, seeds: 18 });
    assert.deepEqual(economy.missing({ wood: 60, seeds: 18 }), { wood: 3 });
    assert.equal(economy.receive(Object.assign(Object.create(null), { food: 1 })), true);
    assert.equal(economy.spend({}), true);
    assert.equal(economy.receive({}), true);
    assert.equal(economy.receive({ coins: 1000000000 }), true);
  });

  test('未知键和非法负数、NaN、Infinity、小数、非数字清单均不改变余额', () => {
    const context = setup({ wood: 10, parts: 10 });
    const invalid = [
      null, undefined, 1, 'wood', [], new Date(0),
      { wood: 1, unknown: 2 }, { wood: 1, constructor: 2 },
      JSON.parse('{"wood":1,"__proto__":2}'),
      { wood: 1, [Symbol('未知材料')]: 1 },
      Object.assign(Object.create({ unknown: 1 }), { wood: 1 }),
      Object.defineProperty({ wood: 1 }, 'unknown', { value: 1 })
    ];
    for (const value of [-1, NaN, Infinity, -Infinity, 0.5, '1', null, undefined, true, 1n, Number.MAX_VALUE, Number.MAX_SAFE_INTEGER + 1]) {
      invalid.push({ wood: 1, parts: value });
    }
    for (const bundle of invalid) {
      assert.equal(unchanged(context, () => context.economy.canReceive(bundle)), false);
      assert.equal(unchanged(context, () => context.economy.receive(bundle)), false);
      assert.equal(unchanged(context, () => context.economy.spend(bundle)), false);
      unchanged(context, () => assert.throws(() => context.economy.missing(bundle)));
    }
  });

  test('缺货、各材料容量及海贝安全整数溢出均无部分提交', () => {
    const context = setup({ wood: 10, parts: 10 });
    const { economy, state } = context;
    assert.equal(unchanged(context, () => economy.spend({ wood: 1, parts: 11 })), false);
    for (const [key, material] of Object.entries(MATERIALS)) {
      if (material.capacity === Infinity) continue;
      state[key] = material.capacity;
      assert.equal(unchanged(context, () => economy.receive({ coins: 1, [key]: 1 })), false);
      assert.equal(unchanged(context, () => economy.canReceive({ [key]: 1 })), false);
      assert.equal(economy.spend({ [key]: 1 }), true);
      assert.equal(economy.receive({ [key]: 1 }), true);
    }
    state.coins = Number.MAX_SAFE_INTEGER;
    state.wood = 10;
    assert.equal(unchanged(context, () => economy.receive({ wood: 1, coins: 1 })), false);
    assert.equal(economy.spend({ coins: 1 }), true);
    assert.equal(economy.receive({ coins: 1 }), true);
    for (const invalidBalance of [NaN, Infinity, -1, 0.5, '5', Number.MAX_SAFE_INTEGER + 1]) {
      state.parts = invalidBalance;
      assert.equal(unchanged(context, () => economy.spend({ wood: 1, parts: 1 })), false);
      assert.equal(unchanged(context, () => economy.receive({ wood: 1, parts: 1 })), false);
    }
  });

  test('所有采集点必须位于对应区域，同区但非岸上或忙碌不可拾取', () => {
    const names = { zone1: '晴空水巷', zone2: '横滨铁道', zone3: '圆弧农场', zone4: '远海街町' };
    for (const node of COLLECTIONS) {
      const context = setup({ farSeaUnlocked: true, currentZone: 'elsewhere' });
      const { state, economy } = context;
      assert.deepEqual(economy.getCollectionAction(node.id), { available: false, reason: `先前往${names[node.zone]}靠岸` });
      assert.equal(unchanged(context, () => economy.collect(node.id)).ok, false);
      state.currentZone = node.zone;
      for (const mode of ['SAILING', 'WALKING', 'CRAFTING']) {
        state.workerMode = mode;
        assert.equal(economy.getCollectionAction(node.id).reason, '旅人忙碌中');
        assert.equal(unchanged(context, () => economy.collect(node.id)).ok, false);
      }
      state.workerMode = 'IDLE_ASHORE';
      state.activeJobSite = 'home_cabin';
      assert.equal(economy.getCollectionAction(node.id).reason, '旅人忙碌中');
      assert.equal(unchanged(context, () => economy.collect(node.id)).ok, false);
      state.activeJobSite = null;
      assert.deepEqual(economy.collect(node.id), { ok: true, reason: '', reward: node.reward });
      const initial = { seeds: 3, coins: 80 };
      for (const [key, amount] of Object.entries(node.reward)) assert.equal(state[key], amount + (initial[key] ?? 0));
    }
  });

  test('节点冷却独立，禁止同帧重复，浮点倒计时向上取整显示', () => {
    const context = setup();
    const { economy, state } = context;
    assert.equal(economy.collect('home_crate').ok, true);
    assert.equal(unchanged(context, () => economy.collect('home_crate')).ok, false);
    assert.equal(economy.nodes[0].collections, 1);
    assert.match(economy.getCollectionAction('home_crate').reason, /34秒/);
    economy.tick(1.25);
    assert.equal(economy.nodes[0].left, 32.75);
    assert.match(economy.getCollectionAction('home_crate').reason, /33秒/);
    state.currentZone = 'zone3';
    assert.equal(economy.collect('garden_cache').ok, true);
    economy.tick(32.75);
    assert.equal(economy.nodes[0].left, 0);
    assert.equal(economy.nodes.find((node) => node.id === 'garden_cache').left, 9.25);
    state.currentZone = 'zone1';
    const reward = economy.collect('home_crate').reward;
    reward.wood = 999;
    assert.equal(economy.nodes[0].reward.wood, 3);
    assert.equal(economy.nodes[0].collections, 2);
    economy.tick(1000);
    assert.ok(economy.nodes.every((node) => node.left === 0));
  });

  test('远海锁与满库存阻止整个节点奖励，不启动冷却', () => {
    const context = setup({ currentZone: 'zone4' });
    const { economy, state } = context;
    assert.match(economy.getCollectionAction('sea_cache').reason, /未解锁/);
    assert.equal(unchanged(context, () => economy.collect('sea_cache')).ok, false);
    state.farSeaUnlocked = true;
    state.pearl = 12;
    assert.match(economy.getCollectionAction('sea_cache').reason, /库存已满.*珍珠/);
    assert.equal(unchanged(context, () => economy.collect('sea_cache')).ok, false);
    state.pearl = 11;
    assert.equal(economy.collect('sea_cache').ok, true);
    assert.equal(state.pearl, 12);
    assert.equal(state.parts, 2);
    state.currentZone = 'zone1';
    state.wood = 58;
    assert.equal(unchanged(context, () => economy.collect('home_crate')).ok, false);
    state.wood = 57;
    assert.equal(economy.collect('home_crate').ok, true);
    assert.equal(state.wood, 60);
  });

  test('菜箱动态检查等级、区划、忙碌和缺种来源', () => {
    const context = setup();
    const { economy, state, levels } = context;
    assert.match(economy.getPlotAction('home_plot').reason, /需2级/);
    assert.equal(unchanged(context, () => economy.actPlot('home_plot')).ok, false);
    levels.home_cabin = 2;
    assert.deepEqual(economy.getPlotAction('home_plot'), { available: true, reason: '', label: '播种' });
    assert.match(economy.getPlotAction('farm_plot').reason, /先前往圆弧农场靠岸/);
    state.currentZone = 'zone3';
    assert.match(economy.getPlotAction('farm_plot').reason, /需1级/);
    levels.rooftop_planter = 1;
    state.activeJobSite = 'rooftop_planter';
    assert.equal(economy.getPlotAction('farm_plot').reason, '旅人忙碌中');
    assert.equal(unchanged(context, () => economy.actPlot('farm_plot')).ok, false);
    state.activeJobSite = null;
    state.workerMode = 'SAILING';
    assert.equal(unchanged(context, () => economy.actPlot('farm_plot')).ok, false);
    state.workerMode = 'IDLE_ASHORE';
    state.seeds = 0;
    assert.match(economy.getPlotAction('farm_plot').reason, /种子缺1.*来源/);
    assert.equal(unchanged(context, () => economy.actPlot('farm_plot')).ok, false);
    state.seeds = 1;
    assert.equal(economy.actPlot('farm_plot').ok, true);
    assert.equal(state.seeds, 0);
    assert.equal(economy.plots[1].remaining, 34);
    assert.equal(economy.plots[0].phase, 'empty');
  });

  test('播种只扣一次，土壤干了停止生长，浇水才能走完剩下的时间', () => {
    const context = setup({}, completeLevels);
    const { economy, state } = context;
    const plot = economy.plots[0];
    assert.deepEqual(economy.actPlot('home_plot'), { ok: true, reason: '' });
    assert.equal(state.seeds, 2);
    assert.equal(economy.busy, false);
    assert.equal(plot.duration, 34);
    assert.equal(plot.moisture, 1);
    assert.deepEqual(plot.reward, { food: 2, seeds: 1 });
    // 还湿着的时候再点一次只是补水，不会重复扣种子。
    assert.equal(unchanged(context, () => economy.actPlot('home_plot')).ok, false);

    economy.tick(18);
    assert.equal(plot.moisture, 0);
    assert.equal(plot.remaining, 16);
    // 干透之后完全停止生长，等多久都没用。
    economy.tick(100);
    assert.equal(plot.remaining, 16);
    assert.equal(plot.phase, 'growing');
    assert.deepEqual(economy.getPlotAction('home_plot'), { available: true, reason: '', label: '浇水' });
    assert.equal(state.food, 0);

    assert.deepEqual(economy.actPlot('home_plot'), { ok: true, reason: '' });
    assert.equal(plot.moisture, 1);
    assert.equal(state.seeds, 2);
    economy.tick(16);
    assert.equal(plot.phase, 'ready');
    assert.equal(state.food, 0);
    assert.equal(state.seeds, 2);
    economy.tick(100);
    assert.equal(plot.phase, 'ready');
    assert.deepEqual(economy.getPlotAction('home_plot'), { available: true, reason: '', label: '收获' });
    assert.deepEqual(economy.actPlot('home_plot'), { ok: true, reason: '', reward: { food: 2, seeds: 1 } });
    assert.equal(state.food, 2);
    assert.equal(state.seeds, 3);
    assert.equal(plot.phase, 'empty');
    assert.equal(plot.reward, null);
    assert.equal(plot.remaining, 0);
    assert.equal(plot.moisture, 0);
  });

  test('收获时食物或种子满仓、异地或忙碌均保留ready和完整奖励', () => {
    const context = setup({}, completeLevels);
    const { economy, state } = context;
    economy.actPlot('home_plot');
    economy.tick(18);
    economy.actPlot('home_plot');
    economy.tick(16);
    assert.equal(economy.plots[0].phase, 'ready');
    for (const [key, full, restored] of [['food', 39, 0], ['seeds', 20, 2]]) {
      state[key] = full;
      assert.match(economy.getPlotAction('home_plot').reason, /库存已满/);
      assert.equal(unchanged(context, () => economy.actPlot('home_plot')).ok, false);
      assert.equal(economy.plots[0].phase, 'ready');
      state[key] = restored;
    }
    state.currentZone = 'zone3';
    assert.equal(unchanged(context, () => economy.actPlot('home_plot')).ok, false);
    state.currentZone = 'zone1';
    state.workerMode = 'CRAFTING';
    assert.equal(unchanged(context, () => economy.actPlot('home_plot')).ok, false);
    state.workerMode = 'IDLE_ASHORE';
    assert.equal(economy.actPlot('home_plot').ok, true);
    assert.equal(state.food, 2);
    assert.equal(state.seeds, 3);
  });

  test('温室完工不追溯改变在种作物，新种快照为26秒和3食物', () => {
    const { economy, state } = setup({ wood: 10, parts: 10 }, completeLevels);
    economy.actPlot('home_plot');
    assert.equal(economy.buildFacility('greenhouse').ok, true);
    economy.tick(6);
    assert.equal(economy.facilities.greenhouse.level, 1);
    // 已在长的作物保留旧快照：34 秒总长，施工 6 秒里一直是湿的。
    assert.equal(economy.plots[0].duration, 34);
    assert.equal(economy.plots[0].remaining, 28);
    assert.deepEqual(economy.plots[0].reward, { food: 2, seeds: 1 });
    economy.tick(12);
    assert.equal(economy.plots[0].moisture, 0);
    assert.equal(economy.plots[0].remaining, 16);
    economy.actPlot('home_plot');
    economy.tick(16);
    assert.deepEqual(economy.actPlot('home_plot').reward, { food: 2, seeds: 1 });
    economy.actPlot('home_plot');
    assert.equal(economy.plots[0].duration, 26);
    assert.deepEqual(economy.plots[0].reward, { food: 3, seeds: 1 });
    state.currentZone = 'zone3';
    economy.actPlot('farm_plot');
    assert.equal(economy.plots[1].duration, 26);
    economy.tick(18);
    economy.actPlot('farm_plot');
    economy.tick(8);
    assert.deepEqual(economy.actPlot('farm_plot').reward, { food: 3, seeds: 1 });
    state.currentZone = 'zone1';
    economy.tick(8);
    economy.actPlot('home_plot');
    economy.tick(18);
    assert.deepEqual(economy.actPlot('home_plot').reward, { food: 3, seeds: 1 });
    assert.equal(state.food, 8);
    assert.equal(state.seeds, 3);
  });

  test('设施动态前置、精确材料缺口和来源，异地或不足不扣任何成本', () => {
    const context = setup({ coins: 14, wood: 3, parts: 2 });
    const { economy, levels, state } = context;
    assert.match(economy.getFacilityAction('greenhouse').reason, /需2级.*需1级/);
    assert.equal(unchanged(context, () => economy.buildFacility('greenhouse')).ok, false);
    levels.home_cabin = 2;
    levels.rooftop_planter = 1;
    const reason = economy.getFacilityAction('greenhouse').reason;
    assert.match(reason, /海贝缺1/);
    assert.match(reason, /木料缺2/);
    assert.match(reason, /旧零件缺1/);
    assert.match(reason, /来源/);
    assert.equal(unchanged(context, () => economy.buildFacility('greenhouse')).ok, false);
    assert.match(economy.getFacilityAction('recycler').reason, /横滨.*需1级/);
    levels.yokohama_station = 1;
    assert.match(economy.getFacilityAction('recycler').reason, /木料缺1.*旧零件缺2/);
    state.coins = 80;
    state.wood = 10;
    state.parts = 10;
    for (const id of ['greenhouse', 'recycler']) {
      state.currentZone = 'zone2';
      assert.equal(economy.getFacilityAction(id).reason, '先前往晴空水巷靠岸');
      assert.equal(unchanged(context, () => economy.buildFacility(id)).ok, false);
      state.currentZone = 'zone1';
      state.activeJobSite = 'home_cabin';
      assert.equal(economy.getFacilityAction(id).reason, '旅人忙碌中');
      assert.equal(unchanged(context, () => economy.buildFacility(id)).ok, false);
      state.activeJobSite = null;
    }
  });

  test('设施扣完整成本一次，施工6秒并锁定全部主动操作，完工禁止重复建造', () => {
    const context = setup({ wood: 30, parts: 20, food: 4 }, completeLevels);
    const { economy, state } = context;
    assert.deepEqual(economy.buildFacility('greenhouse'), { ok: true, reason: '' });
    assert.deepEqual([state.coins, state.wood, state.parts], [65, 25, 17]);
    assert.deepEqual(economy.job, { id: 'greenhouse', remaining: 6, duration: 6 });
    assert.equal(state.workerMode, 'CRAFTING');
    assert.equal(economy.busy, true);
    assert.equal(economy.getFacilityAction('greenhouse').label, '施工中');
    state.workerMode = 'IDLE_ASHORE';
    assert.equal(economy.busy, true);
    const operations = [
      () => economy.collect('home_crate'), () => economy.actPlot('home_plot'),
      () => economy.buildFacility('greenhouse'), () => economy.buildFacility('recycler'),
      () => economy.upgradeShip(), () => economy.tradeFood(), () => economy.collectFacility('recycler')
    ];
    for (const operation of operations) assert.equal(unchanged(context, operation).reason, '旅人忙碌中');
    state.workerMode = 'CRAFTING';
    economy.tick(5.5);
    assert.equal(economy.job.remaining, 0.5);
    assert.equal(economy.facilities.greenhouse.level, 0);
    economy.tick(0.5);
    assert.equal(economy.job, null);
    assert.equal(economy.facilities.greenhouse.level, 1);
    assert.equal(state.workerMode, 'IDLE_ASHORE');
    assert.equal(economy.busy, false);
    assert.equal(unchanged(context, () => economy.buildFacility('greenhouse')).ok, false);
  });

  test('完工仅恢复仍处于CRAFTING的状态，不覆盖外部模式和任务', () => {
    for (const mode of ['SAILING', 'WALKING', 'IDLE_ASHORE']) {
      const { economy, state } = setup({ wood: 10, parts: 10 }, completeLevels);
      economy.buildFacility('recycler');
      state.workerMode = mode;
      state.activeJobSite = 'home_cabin';
      economy.tick(6);
      assert.equal(state.workerMode, mode);
      assert.equal(state.activeJobSite, 'home_cabin');
      assert.equal(economy.job, null);
      assert.equal(economy.facilities.recycler.level, 1);
      assert.equal(economy.busy, true);
    }
  });

  test('回收台每30秒存2零件、最多6，必须主动领取且不会自动入库', () => {
    const context = buildRecycler();
    const { economy, state } = context;
    const recycler = economy.getFacility('recycler');
    assert.equal(recycler, economy.facilities.recycler);
    assert.equal(state.parts, 6);
    assert.deepEqual(recycler.stored, {});
    assert.equal(economy.getFacilityAction('recycler').available, false);
    economy.tick(29.5);
    assert.deepEqual(recycler.stored, {});
    assert.equal(recycler.timer, 29.5);
    economy.tick(0.5);
    assert.deepEqual(recycler.stored, { parts: 2 });
    assert.equal(state.parts, 6);
    assert.deepEqual(economy.getFacilityAction('recycler'), { available: true, reason: '', label: '收取零件' });
    assert.equal(unchanged(context, () => economy.buildFacility('recycler')).ok, false);
    economy.tick(60);
    assert.deepEqual(recycler.stored, { parts: 6 });
    economy.tick(10000);
    assert.deepEqual(recycler.stored, { parts: 6 });
    assert.equal(recycler.timer, 0);
    assert.equal(state.parts, 6);
    assert.deepEqual(economy.collectFacility('recycler'), { ok: true, reason: '', reward: { parts: 6 } });
    assert.equal(state.parts, 12);
    assert.deepEqual(recycler.stored, {});
    assert.equal(unchanged(context, () => economy.collectFacility('recycler')).ok, false);
    economy.tick(29);
    assert.deepEqual(recycler.stored, {});
    economy.tick(1);
    assert.deepEqual(recycler.stored, { parts: 2 });
  });

  test('回收暂存满库存、异地或忙碌时不丢产物，零件不足空间不能部分领取', () => {
    const context = buildRecycler();
    const { state, economy } = context;
    economy.tick(90);
    state.parts = 55;
    assert.match(economy.getFacilityAction('recycler').reason, /库存已满.*旧零件/);
    assert.equal(unchanged(context, () => economy.collectFacility('recycler')).ok, false);
    state.parts = 54;
    state.currentZone = 'zone3';
    assert.equal(unchanged(context, () => economy.collectFacility('recycler')).reason, '先前往晴空水巷靠岸');
    state.currentZone = 'zone1';
    state.workerMode = 'SAILING';
    assert.equal(unchanged(context, () => economy.collectFacility('recycler')).reason, '旅人忙碌中');
    state.workerMode = 'IDLE_ASHORE';
    state.activeJobSite = 'home_cabin';
    assert.equal(unchanged(context, () => economy.collectFacility('recycler')).reason, '旅人忙碌中');
    state.activeJobSite = null;
    assert.equal(economy.collectFacility('recycler').ok, true);
    assert.equal(state.parts, 60);
    assert.equal(economy.collectFacility('greenhouse').ok, false);
  });

  test('大步tick正确切分施工与生产，分帧推进和一次推进一致', () => {
    for (const [dt, stored, timer] of [[6, 0, 0], [30, 0, 24], [35, 0, 29], [36, 2, 0], [65, 2, 29], [96, 6, 0], [Number.MAX_VALUE, 6, 0]]) {
      const { economy } = setup({ wood: 10, parts: 10 }, completeLevels);
      economy.buildFacility('recycler');
      economy.tick(dt);
      assert.equal(economy.job, null);
      assert.equal(economy.facilities.recycler.stored.parts ?? 0, stored);
      assert.equal(economy.facilities.recycler.timer, timer);
    }
    const once = setup({ wood: 10, parts: 10 }, completeLevels);
    const split = setup({ wood: 10, parts: 10 }, completeLevels);
    once.economy.buildFacility('recycler');
    split.economy.buildFacility('recycler');
    once.economy.tick(65);
    for (const dt of [2, 3, 1, 0.5, 29.5, 29]) split.economy.tick(dt);
    assert.deepEqual(snapshot(once), snapshot(split));
  });

  test('已有回收台在温室施工期间继续生产', () => {
    const { economy, state } = buildRecycler();
    economy.tick(29);
    assert.equal(economy.buildFacility('greenhouse').ok, true);
    economy.tick(1);
    assert.deepEqual(economy.facilities.recycler.stored, { parts: 2 });
    assert.equal(economy.job.remaining, 5);
    economy.tick(5);
    assert.equal(state.workerMode, 'IDLE_ASHORE');
    assert.equal(economy.facilities.recycler.timer, 5);
  });

  test('船只动态建筑前置、全材料尤其食物不足均不可免费解锁', () => {
    const context = setup({ wood: 6, parts: 4 });
    const { economy, levels, state } = context;
    assert.match(economy.getShipAction().reason, /前置建筑不足/);
    assert.equal(unchanged(context, () => economy.upgradeShip()).ok, false);
    Object.assign(levels, completeLevels);
    assert.match(economy.getShipAction().reason, /食物缺2.*来源/);
    assert.equal(unchanged(context, () => economy.upgradeShip()).ok, false);
    assert.equal(state.farSeaUnlocked, false);
    assert.equal(state.shipLevel, 1);
    state.food = 1;
    assert.match(economy.getShipAction().reason, /食物缺1/);
    assert.equal(unchanged(context, () => economy.upgradeShip()).ok, false);
    state.food = 2;
    for (const [key, required] of Object.entries(SHIP_RECIPE.cost)) {
      const original = state[key];
      state[key] = required - 1;
      assert.equal(unchanged(context, () => economy.upgradeShip()).ok, false);
      state[key] = original;
    }
    assert.deepEqual(economy.upgradeShip(), { ok: true, reason: '' });
    assert.deepEqual([state.coins, state.wood, state.parts, state.food], [55, 0, 0, 0]);
    assert.equal(state.shipLevel, 2);
    assert.equal(state.farSeaUnlocked, true);
    assert.equal(unchanged(context, () => economy.upgradeShip()).ok, false);
    assert.match(economy.getShipAction().reason, /已升级/);
    state.currentZone = 'zone4';
    assert.equal(economy.collect('sea_cache').ok, true);
  });

  test('船只异地、航行、其他任务中不能升级', () => {
    const context = setup({ wood: 6, parts: 4, food: 2 }, completeLevels);
    const { economy, state } = context;
    for (const zone of ['zone2', 'zone3', 'zone4']) {
      state.currentZone = zone;
      assert.equal(economy.getShipAction().reason, '先前往晴空水巷靠岸');
      assert.equal(unchanged(context, () => economy.upgradeShip()).ok, false);
    }
    state.currentZone = 'zone1';
    state.workerMode = 'SAILING';
    assert.equal(unchanged(context, () => economy.upgradeShip()).reason, '旅人忙碌中');
    state.workerMode = 'IDLE_ASHORE';
    state.activeJobSite = 'home_cabin';
    assert.equal(unchanged(context, () => economy.upgradeShip()).reason, '旅人忙碌中');
  });

  test('交易必须同区岸上不忙，食物不足或海贝溢出不扣食物', () => {
    const context = setup({ food: 1 });
    const { economy, state } = context;
    assert.equal(unchanged(context, () => economy.tradeFood()).ok, false);
    state.food = 2;
    state.currentZone = 'zone3';
    assert.equal(unchanged(context, () => economy.tradeFood()).reason, '先前往晴空水巷靠岸');
    state.currentZone = 'zone1';
    state.workerMode = 'SAILING';
    assert.equal(unchanged(context, () => economy.tradeFood()).reason, '旅人忙碌中');
    state.workerMode = 'IDLE_ASHORE';
    state.activeJobSite = 'home_cabin';
    assert.equal(unchanged(context, () => economy.tradeFood()).reason, '旅人忙碌中');
    state.activeJobSite = null;
    state.coins = Number.MAX_SAFE_INTEGER - 11;
    assert.equal(unchanged(context, () => economy.tradeFood()).ok, false);
    state.coins = Number.MAX_SAFE_INTEGER - 12;
    assert.deepEqual(economy.tradeFood(), { ok: true, reason: '', reward: { coins: 12 } });
    assert.equal(state.coins, Number.MAX_SAFE_INTEGER);
    assert.equal(state.food, 0);
    assert.equal(unchanged(context, () => economy.tradeFood()).ok, false);
  });

  test('初始材料经采集、播种、返种、交易、建造和升级形成闭环', () => {
    const { economy, state } = setup({}, completeLevels);
    economy.collect('home_crate');
    state.currentZone = 'zone2';
    economy.collect('workshop_cache');
    state.currentZone = 'zone3';
    economy.collect('garden_cache');
    state.currentZone = 'zone1';
    const initialSeeds = state.seeds;
    for (let cycle = 0; cycle < 3; cycle += 1) {
      assert.equal(economy.actPlot('home_plot').ok, true);
      economy.tick(18);
      assert.equal(economy.actPlot('home_plot').ok, true);
      assert.equal(economy.plots[0].moisture, 1);
      economy.tick(16);
      assert.equal(economy.actPlot('home_plot').ok, true);
      assert.equal(state.seeds, initialSeeds);
      assert.equal(economy.tradeFood().ok, true);
      assert.equal(state.food, 0);
      assert.equal(state.coins, 80 + (cycle + 1) * 12);
    }
    assert.equal(economy.buildFacility('greenhouse').ok, true);
    economy.tick(6);
    economy.collect('home_crate');
    state.currentZone = 'zone2';
    economy.collect('workshop_cache');
    state.currentZone = 'zone1';
    economy.actPlot('home_plot');
    economy.tick(18);
    economy.actPlot('home_plot');
    economy.tick(8);
    assert.deepEqual(economy.actPlot('home_plot').reward, { food: 3, seeds: 1 });
    assert.equal(economy.upgradeShip().ok, true);
    assert.equal(state.farSeaUnlocked, true);
    assert.equal(state.food, 1);
    assert.equal(state.coins, 76);
    assert.equal(state.seeds, initialSeeds);
  });

  test('所有查询无副作用，未知ID和原型键安全失败', () => {
    const context = setup({}, completeLevels);
    const { economy } = context;
    unchanged(context, () => {
      economy.getCollectionAction('home_crate');
      economy.getPlotAction('home_plot');
      economy.getFacilityAction('greenhouse');
      economy.getFacility('recycler');
      economy.getShipAction();
      economy.missing(SHIP_RECIPE.cost);
      economy.canReceive({ wood: 1 });
      assert.equal(economy.busy, false);
      assert.equal(economy.job, null);
    });
    for (const id of ['unknown', '__proto__', 'constructor', '', undefined]) {
      assert.equal(economy.getCollectionAction(id).available, false);
      assert.equal(economy.getPlotAction(id).available, false);
      assert.equal(economy.getFacilityAction(id).available, false);
      assert.equal(economy.getFacility(id), null);
      for (const operation of [() => economy.collect(id), () => economy.actPlot(id), () => economy.buildFacility(id), () => economy.collectFacility(id)]) {
        const result = unchanged(context, operation);
        assert.equal(result.ok, false);
        assert.match(result.reason, /未知/);
      }
    }
  });

  test('探索按里程掷骰子，只产出木料与旧零件，与所在区域无关', () => {
    const state = { coins: 80, wood: 0, parts: 0, seeds: 3, food: 0, fish: 0, pearl: 0,
      shipLevel: 1, farSeaUnlocked: false, currentZone: 'zone1', workerMode: 'IDLE_ASHORE', activeJobSite: null };
    // 固定 random=0：每次判定必中，且落在 wood 分支、数量取下限 1。
    const economy = createEconomy(state, () => 0, { random: () => 0 });
    const shortWalk = economy.explore(6.9);
    assert.equal(shortWalk.ok, false);
    assert.deepEqual(shortWalk.reward, {});
    assert.equal(shortWalk.pending, 6.9);

    const first = economy.explore(0.2);
    assert.equal(first.ok, true);
    assert.deepEqual(first.reward, { wood: 1 });
    assert.equal(first.finds, 1);
    assert.ok(Math.abs(first.pending - 0.1) < 1e-9);

    // 连走 21 米 = 三次判定，每次都必中，木料累加。
    const many = economy.explore(21);
    assert.equal(many.ok, true);
    assert.equal(many.finds, 3);
    assert.deepEqual(many.reward, { wood: 3 });
    assert.equal(state.wood, 4);

    // 换到别的区域照样探索，探索本身不看 currentZone。
    state.currentZone = 'zone4';
    assert.equal(economy.explore(7).ok, true);
    assert.equal(state.wood, 5);

    // 从不命中时只是累计里程，不产生任何资源。
    const idle = createEconomy({ ...state, wood: 0 }, () => 0, { random: () => 0.99 });
    assert.equal(idle.explore(70).ok, false);
    assert.equal(idle.explore(3).pending, 3);

    // 非法里程被拒绝且不改变状态。
    for (const bad of [-1, NaN, Infinity, '7', null, undefined, {}]) {
      const before = economy.exploredDistance;
      assert.equal(economy.explore(bad).ok, false);
      assert.equal(economy.exploredDistance, before);
    }
  });

  test('tick拒绝非法时间且不推进任何状态，零时间不变并支持大步推进', () => {
    const context = setup({ wood: 20, parts: 20 }, completeLevels);
    const { economy } = context;
    economy.collect('home_crate');
    economy.actPlot('home_plot');
    economy.buildFacility('recycler');
    for (const dt of [-1, NaN, Infinity, -Infinity, '6', null, undefined, true, {}, 1n]) {
      unchanged(context, () => assert.throws(() => economy.tick(dt), RangeError));
    }
    unchanged(context, () => economy.tick(0));
    economy.tick(Number.MAX_VALUE);
    assert.equal(economy.nodes[0].left, 0);
    // 一次极大的 tick 也只吃掉一次湿润期：土壤干了蔬菜就停住，不会凭空成熟。
    assert.equal(economy.plots[0].phase, 'growing');
    assert.equal(economy.plots[0].moisture, 0);
    assert.equal(economy.plots[0].remaining, 16);
    assert.equal(economy.job, null);
    assert.deepEqual(economy.facilities.recycler.stored, { parts: 6 });
    assert.equal(Number.isFinite(economy.facilities.recycler.timer), true);
  });
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
