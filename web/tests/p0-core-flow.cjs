const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true, args: ['--enable-webgl', '--ignore-gpu-blocklist']
  });
  const passed = [], errors = [];
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    page.on('pageerror', e => errors.push(e.message));
    page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
    await page.route('**/index.html', async route => {
      const response = await route.fetch();
      let body = await response.text();
      body = body.replace('    const clock = new THREE.Clock();', '    window.qa = {gameplay, sceneArt, harbor, scene, camera, controls}; window.freezeCore = true;\n    const clock = new THREE.Clock();');
      body = body.replace('      gameplay.updateGameplay(dt, t);', '      if (!window.freezeCore) gameplay.updateGameplay(dt, t);');
      body = body.replace('      sceneArt.update(t);', '      if (!window.freezeCore) sceneArt.update(t);');
      await route.fulfill({ response, body });
    });
    await page.goto((process.env.APP_URL || 'http://localhost:8765') + '/index.html');
    await page.waitForFunction(() => window.qa?.gameplay.economyView);
    await page.waitForTimeout(500);
    await page.evaluate(() => {
      window.simTime = 0;
      window.advance = (seconds = 0.3) => {
        for (let i = 0; i < Math.ceil(seconds / .05); i++) {
          simTime += .05; qa.gameplay.updateGameplay(.05, simTime);
          qa.sceneArt.update(simTime); qa.harbor.update(simTime);
        }
        qa.scene.updateMatrixWorld(true); qa.controls.update();
        qa.gameplay.updateOverlays();
      };
      window.settle = () => {
        for (let i = 0; i < 8000 && qa.gameplay.art.state.workerMode !== 'IDLE_ASHORE'; i++) advance(.05);
        if (qa.gameplay.art.state.workerMode !== 'IDLE_ASHORE') throw Error('state did not settle: ' + qa.gameplay.art.state.workerMode);
        advance(.3);
      };
      advance(.3);
    });
    const state = () => page.evaluate(() => {
      const s = qa.gameplay.art.state;
      return { coins:s.coins, wood:s.wood, parts:s.parts, seeds:s.seeds, food:s.food, fish:s.fish, pearl:s.pearl, shipLevel:s.shipLevel, zone:s.currentZone, mode:s.workerMode };
    });
    const open = async (id) => { await page.evaluate(id => { qa.gameplay.economyView.open(id); advance(.3); }, id); };
    const click = async (action) => { await page.locator(`#economy-panel [data-econ-action="${action}"]`).first().click(); await page.evaluate(() => advance(.3)); };
    const settle = () => page.evaluate(() => settle());
    const build = async (id) => {
      await open(id);
      // 挂机产出攒满 10 枚才会切到"收取"模式，未满时点击直接走升级。
      for (let i = 0; i < 2; i++) {
        const stored = await page.evaluate(id => qa.gameplay.art.buildSites.find(s => s.id === id).storedCoins, id);
        if (stored >= 10) { await click(`build:${id}`); await page.waitForTimeout(750); }
      }
      await click(`build:${id}`); await settle();
    };
    const collect = async (id) => { await open(id); await click(`collect:${id}`); };
    const travelTo = async (zone, via) => { await open(via); await click(`travel:${zone}`); await settle(); };
    assert.deepEqual(await state(), {coins:80,wood:0,parts:0,seeds:3,food:0,fish:0,pearl:0,shipLevel:1,zone:'zone1',mode:'IDLE_ASHORE'});
    assert.equal(await page.locator('.demo-objective-panel').count(), 0);
    assert.equal(await page.locator('#economy-panel').isVisible(), false);
    await page.screenshot({path:'outputs/fusion-start.png'});
    await open('ship');
    assert.equal(await page.locator('[data-econ-action="ship"]').isDisabled(), true);
    passed.push('初始6种资源、按需面板、未满足家园前置不能直接改船');

    await collect('home_crate');
    const collected = await state();
    assert.equal(collected.wood, 3); assert.equal(collected.parts, 1);
    assert.equal(await page.locator('[data-econ-action="collect:home_crate"]').isDisabled(), true);
    const double = await page.evaluate(() => qa.gameplay.economy.collect('home_crate'));
    assert.equal(double.ok, false); assert.deepEqual(await state(), collected);
    passed.push('通过真实面板收集屋顶箱，重复采集被冷却阻止');

    await build('home_cabin');
    assert.equal(await page.evaluate(() => qa.gameplay.art.buildSites.find(s=>s.id==='home_cabin').level), 2);
    assert.equal((await state()).wood, 1);
    await open('home_plot'); await click('plot:home_plot');
    assert.equal((await state()).seeds, 2);
    // 土壤 18 秒就干透，干透后必须浇水才继续长，这是菜箱的核心节奏。
    await page.evaluate(() => advance(18));
    await click('plot:home_plot');
    await page.evaluate(() => advance(16));
    assert.equal((await state()).food, 0, '成熟不得自动进库存');
    await page.screenshot({path:'outputs/fusion-harvest.png'});
    await click('plot:home_plot');
    assert.equal((await state()).food, 2); assert.equal((await state()).seeds, 3);
    passed.push('真实木屋建设扣费、解锁菜箱、干涸浇水后手动收食物并返种');

    await open('salvage'); await click('salvage');
    await build('rooftop_planter');
    assert.equal((await state()).zone, 'zone3');
    await collect('garden_cache');
    assert.equal((await state()).seeds, 5);
    await open('farm_plot'); await click('plot:farm_plot');
    await travelTo('zone2', 'workshop_cache');
    await collect('workshop_cache');
    await build('yokohama_station');
    assert.equal((await state()).zone, 'zone2');
    await travelTo('zone1', 'home_crate');
    await collect('home_crate');
    await open('salvage'); await click('salvage');
    assert.equal((await state()).zone, 'zone1');
    passed.push('从木屋真实跨区建农场、采种子、前往铁道采零件建站台，再返航');

    // Exchange some food for shells, then harvest another batch for the expedition.
    await open('home_plot'); await click('plot:home_plot');
    await page.evaluate(() => advance(18)); await click('plot:home_plot');
    await page.evaluate(() => advance(16)); await click('plot:home_plot');
    await open('trade'); await click('trade');
    assert.equal((await state()).food, 2);
    await open('greenhouse'); await click('facility:greenhouse');
    const costOnce = await state();
    assert.equal(costOnce.mode, 'CRAFTING');
    const duplicate = await page.evaluate(() => qa.gameplay.economy.buildFacility('greenhouse'));
    assert.equal(duplicate.ok, false); assert.deepEqual(await state(), costOnce);
    await settle();
    assert.equal(await page.evaluate(() => qa.gameplay.economy.facilities.greenhouse.level), 1);
    await open('home_plot'); await click('plot:home_plot');
    assert.equal(await page.evaluate(() => qa.gameplay.economy.plots[0].duration), 26);
    await page.evaluate(() => advance(18)); await click('plot:home_plot');
    await page.evaluate(() => advance(8)); await click('plot:home_plot');
    assert.equal((await state()).food, 5);
    passed.push('食物交易、温室6秒建造与单次扣费；新作物26秒成熟、产出3食物');

    // Earn shells through repeatable harvesting, never inject resource balances.
    for(let i=0;i<2;i++) {
      await open('home_plot'); await click('plot:home_plot');
      await page.evaluate(() => advance(18)); await click('plot:home_plot');
      await page.evaluate(() => advance(8)); await click('plot:home_plot');
      await open('trade'); await click('trade');
    }
    await page.evaluate(() => advance(40));
    await collect('home_crate'); await open('salvage'); await click('salvage');
    await open('recycler'); await click('facility:recycler'); await settle();
    await page.evaluate(() => advance(90));
    assert.equal(await page.evaluate(() => qa.gameplay.economy.facilities.recycler.stored.parts), 6);
    const partsBefore = (await state()).parts;
    await click('facility:recycler'); assert.equal((await state()).parts, partsBefore + 6);
    await page.evaluate(() => advance(30)); await collect('home_crate');
    await open('trade'); await click('trade');
    await open('ship');
    const beforeShip = await state();
    assert.ok(beforeShip.coins >= 25 && beforeShip.wood >= 6 && beforeShip.parts >= 4 && beforeShip.food >= 2, JSON.stringify(beforeShip));
    await page.screenshot({path:'outputs/fusion-build.png'});
    await click('ship');
    const afterShip = await state();
    assert.equal(afterShip.coins, beforeShip.coins - 25);
    assert.equal(afterShip.food, beforeShip.food - 2);
    assert.equal(afterShip.shipLevel, 2);
    assert.equal(await page.locator('.far-sea-destination').getAttribute('aria-disabled'), 'false');
    passed.push('回收台存满6零件后手动领取；海贝+木料+零件+食物改船，远海解锁');

    await travelTo('zone4', 'sea_cache');
    assert.equal((await state()).zone, 'zone4');
    await collect('sea_cache'); assert.equal((await state()).pearl, 1);
    await page.screenshot({path:'outputs/fusion-far-sea.png'});
    await travelTo('zone1', 'home_crate');
    // Supply the final optional pool entirely by repeatable resources and trading.
    await collect('home_crate'); await open('salvage'); await click('salvage');
    for(let i=0;i<3;i++) {
      await open('home_plot'); await click('plot:home_plot');
      await page.evaluate(() => advance(18)); await click('plot:home_plot');
      await page.evaluate(() => advance(8)); await click('plot:home_plot');
      await open('trade'); await click('trade');
    }
    await build('shallow_aquaculture');
    assert.equal(await page.evaluate(() => qa.gameplay.art.buildSites.find(s=>s.id==='shallow_aquaculture').level), 1);
    assert.equal((await state()).pearl, 0);
    passed.push('真实远航靠岸采珍珠，再返程用珍珠建设浅水养殖台，无资源/等级注入');

    // Narrow view and focus semantics must remain usable without horizontal overflow.
    await page.setViewportSize({width:390,height:844});
    await open('home_plot');
    await page.screenshot({path:'outputs/fusion-mobile.png'});
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth),390);
    const panelBox = await page.locator('#economy-panel').boundingBox();
    assert.ok(panelBox.x >= 0 && panelBox.x + panelBox.width <= 390);
    await page.keyboard.press('Escape');
    assert.equal(await page.locator('#economy-panel').isVisible(),false);
    assert.equal(await page.evaluate(()=>document.activeElement.id),'economy-toggle');
    assert.deepEqual(errors, []);
    passed.push('390px面板不溢出、Escape关闭恢复焦点、无JS或Shader错误');
    const result = {passed,errors,final:await state(),simulationSeconds:await page.evaluate(()=>simTime)};
    fs.writeFileSync('outputs/p0-core-flow-results.json',JSON.stringify(result,null,2));
    console.log(JSON.stringify(result,null,2));
  } finally { await browser.close(); }
})().catch(e => {console.error(e);process.exitCode=1;});
