// 新布局视觉复核：整体分布 + 各区块停泊近景。
const { chromium } = require('playwright');
const WATER = 1.12;

(async () => {
  const browser = await chromium.launch({
    executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
    args: ['--use-gl=angle', '--use-angle=metal', '--enable-webgl', '--ignore-gpu-blocklist']
  });
  try {
    const page = await browser.newPage({ viewport: { width: 1180, height: 760 } });
    page.on('pageerror', e => console.log('PAGEERROR', e.message));
    await page.route('**/index.html', async route => {
      const response = await route.fetch();
      let body = await response.text();
      body = body.replace('    const clock = new THREE.Clock();', '    window.qa={THREE,gameplay,scene,camera,controls};\n    const clock = new THREE.Clock();');
      await route.fulfill({ response, body });
    });
    await page.goto('http://127.0.0.1:8765/index.html');
    await page.waitForFunction(() => window.qa?.gameplay?.art?.state, null, { timeout: 60000 });
    await page.waitForTimeout(2500);
    await page.addStyleTag({ content: '.hud,.top-bar,#ui-layer,#hover-card,#action-menu,#destination-menu,.resource-bar,.bottom-bar,.minimal-coin-pill,.controls-group{display:none!important}' });

    // 俯视总览
    await page.evaluate(() => {
      const q = window.qa, T = q.THREE, art = q.gameplay.art;
      art.state.manualCamera = true;
      q.scene.fog = new T.Fog(q.scene.fog.color, 400, 900);
      q.camera.far = 1200;
      q.camera.updateProjectionMatrix();
      q.controls.minDistance = 2; q.controls.maxDistance = 2000;
      const t = new T.Vector3(-4, 0, -12);
      q.controls.target.copy(t);
      q.camera.position.set(t.x + 40, t.y + 190, t.z + 165);
      q.camera.lookAt(t);
      q.controls.update();
    });
    await page.waitForTimeout(900);
    await page.screenshot({ path: 'outputs/zone-layout-overview.png' });
    console.log('shot overview');

    // 各区块停泊近景
    for (const id of ['zone1', 'zone2', 'zone3', 'zone5', 'zone4']) {
      await page.evaluate((id) => {
        const q = window.qa, T = q.THREE, art = q.gameplay.art, g = q.gameplay;
        const z = g.zones.get(id);
        art.state.manualCamera = true;
        art.state.workerMode = 'IDLE_ASHORE';
        art.state.currentZone = id;
        art.boatAnchorGroup.position.copy(z.boatPark);
        art.boatAnchorGroup.rotation.y = z.boatYaw;
        art.explorerGroup.position.copy(z.landStand);
        const t = new T.Vector3((z.boatPark.x + z.landStand.x) / 2, 2.0, (z.boatPark.z + z.landStand.z) / 2);
        q.controls.target.copy(t);
        q.camera.position.set(t.x + 10, t.y + 9, t.z + 13);
        q.camera.lookAt(t);
        q.controls.update();
      }, id);
      await page.waitForTimeout(700);
      await page.screenshot({ path: 'outputs/zone-layout-' + id + '.png' });
      console.log('shot', id);
    }
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
