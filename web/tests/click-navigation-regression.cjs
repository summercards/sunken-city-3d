const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

(async () => {
  const browser = await chromium.launch({ executablePath: process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.route('**/index.html', async route => {
      const response = await route.fetch();
      let body = await response.text();
      body = body.replace('    const clock = new THREE.Clock();', '    window.qa={THREE,gameplay,scene,camera,controls};\n    const clock = new THREE.Clock();');
      await route.fulfill({ response, body });
    });
    await page.goto((process.env.APP_URL || 'http://127.0.0.1:8765') + '/index.html');
    await page.waitForFunction(() => window.qa?.gameplay?.art?.state);
    await page.evaluate(() => { qa.gameplay.art.state.manualCamera = false; });

    const boatPoint = await page.evaluate(() => {
      const q = qa, T = q.THREE, p = q.gameplay.art.boatAnchorGroup.getWorldPosition(new T.Vector3()).add(new T.Vector3(0, 0.4, 0)).project(q.camera);
      return { x: (p.x * .5 + .5) * innerWidth, y: (-p.y * .5 + .5) * innerHeight };
    });
    await page.mouse.click(boatPoint.x, boatPoint.y);
    await page.waitForFunction(() => qa.gameplay.art.state.workerMode === 'BOAT_IDLE');
    assert.equal(await page.evaluate(() => qa.gameplay.art.state.workerMode), 'BOAT_IDLE');

    const start = await page.evaluate(() => qa.gameplay.art.boatAnchorGroup.position.toArray());
    // 停泊位会随区块配置变化，所以这里按真实场景找一块「屏幕内且确实没有露出水面的实体」的水面。
    const waterPoint = await page.evaluate(() => {
      const q = qa, T = q.THREE;
      q.scene.updateMatrixWorld(true);
      const meshes = [];
      q.scene.traverse(o => {
        if (!o.isMesh || o.name === 'cartoon-water') return;
        for (let p = o; p; p = p.parent) {
          if (!p.visible || p === q.gameplay.art.boatAnchorGroup || p === q.gameplay.art.explorerGroup) return;
        }
        meshes.push(o);
      });
      const ray = new T.Raycaster();
      const down = new T.Vector3(0, -1, 0);
      const clearAt = (x, z) => {
        ray.set(new T.Vector3(x, 30, z), down);
        ray.far = 60;
        return !ray.intersectObjects(meshes, false).some(h => h.point.y > 1.15);
      };
      const boat = q.gameplay.art.boatAnchorGroup.position;
      const found = [];
      for (let r = 5; r <= 14 && found.length < 4; r += 1.4) {
        for (let a = 0; a < 32; a++) {
          const ang = (a / 32) * Math.PI * 2;
          const x = boat.x + Math.cos(ang) * r, z = boat.z + Math.sin(ang) * r;
          if (!clearAt(x, z)) continue;
          const p = new T.Vector3(x, 1.12, z).project(q.camera);
          if (Math.abs(p.x) < .75 && Math.abs(p.y) < .72) found.push({ x: (p.x * .5 + .5) * innerWidth, y: (-p.y * .5 + .5) * innerHeight });
        }
      }
      if (!found.length) throw new Error('no test water point');
      return found.slice(0, 4);
    });
    // 镜头还在缓动，偶尔会点到船身；逐点重试直到真的划起来。
    for (const point of waterPoint) {
      await page.mouse.click(point.x, point.y);
      await page.waitForTimeout(260);
      if (await page.evaluate(() => qa.gameplay.art.state.workerMode) === 'ROWING') break;
    }
    await page.waitForTimeout(900);
    const moved = await page.evaluate(() => ({ mode: qa.gameplay.art.state.workerMode, pos: qa.gameplay.art.boatAnchorGroup.position.toArray() }));
    assert.equal(moved.mode, 'ROWING');
    assert(Math.hypot(moved.pos[0] - start[0], moved.pos[2] - start[2]) > .2);

    await page.reload();
    await page.waitForFunction(() => window.qa?.gameplay?.art?.state);
    await page.evaluate(() => {
      qa.gameplay.art.state.workerMode = 'IDLE_ASHORE';
      qa.gameplay.art.state.currentZone = 'zone1';
      qa.gameplay.art.state.manualCamera = false;
      qa.gameplay.art.state.camLockMode = 'zone1';
      qa.gameplay.art.explorerGroup.position.set(3.35, 2.02, 3.35);
      qa.controls.target.set(.45, 1.75, -.65);
      qa.camera.position.set(-53.55, 78.12, 53.35);
      qa.controls.update();
      qa.scene.updateMatrixWorld(true);
      qa.camera.updateProjectionMatrix();
      qa.camera.updateMatrixWorld(true);
    });
    await page.waitForTimeout(120);
    const walkPoint = await page.evaluate(() => {
      const q = qa, T = q.THREE, world = new T.Vector3(4.5, 2.02, 3.7), p = world.project(q.camera);
      return { x: (p.x * .5 + .5) * innerWidth, y: (-p.y * .5 + .5) * innerHeight };
    });
    await page.mouse.click(walkPoint.x, walkPoint.y);
    await page.waitForTimeout(180);
    assert.equal(await page.evaluate(() => qa.gameplay.art.state.workerMode), 'WALK_TO_POINT');
    await page.waitForTimeout(2600);
    assert.equal(await page.evaluate(() => qa.gameplay.art.state.workerMode), 'IDLE_ASHORE');

    const blocked = await page.evaluate(() => {
      const q = qa, T = q.THREE, p = new T.Vector3(-20, 2.02, 3.35).project(q.camera);
      return { x: (p.x * .5 + .5) * innerWidth, y: (-p.y * .5 + .5) * innerHeight };
    });
    await page.mouse.click(blocked.x, blocked.y);
    await page.waitForTimeout(300);
    assert.equal(await page.evaluate(() => qa.gameplay.art.state.workerMode), 'IDLE_ASHORE');

    await page.screenshot({ path: 'outputs/click-navigation-regression.png' });
    assert.deepEqual(errors, []);
    const result = { passed: ['点击船只后角色自动上船', '船上点击海面后划向目标点', '不可达地块点击不会穿越阻隔', '无运行时错误'], start, moved, errors };
    fs.writeFileSync('outputs/click-navigation-results.json', JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result, null, 2));
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
