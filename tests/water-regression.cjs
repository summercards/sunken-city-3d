const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
  });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
    await page.route('**/index.html', async route => {
      const response = await route.fetch();
      let body = await response.text();
      body = body.replace('    const clock = new THREE.Clock();',
        '    window.qa={THREE,waterSystem,gameplay,gridView,scene,camera,controls,renderer};\n    const clock = new THREE.Clock();');
      body = body.replace('gameplay.updateGameplay(dt, t);', 'if (!window.qaFreeze) gameplay.updateGameplay(dt, t);');
      body = body.replace('waterSystem.update(dt, t);', 'if (!window.qaFreeze) waterSystem.update(dt, t);');
      await route.fulfill({ response, body });
    });
    await page.goto((process.env.APP_URL || 'http://127.0.0.1:8765') + '/index.html');
    await page.waitForFunction(() => window.qa?.waterSystem?.uniforms.uSceneDepth.value.image.width > 1);
    await page.waitForTimeout(1200);
    await page.screenshot({ path: 'outputs/water-redesign-overview.png' });

    const initial = await page.evaluate(() => {
      const { waterSystem: w } = qa;
      return { ripples: w.uniforms.uRipples.value.length, wakes: w.uniforms.uWake.value.length,
        resolution: w.uniforms.uResolution.value.toArray(), clicks: w.stats.clicks };
    });
    assert.equal(initial.ripples, 16);
    assert.equal(initial.wakes, 24);
    assert(initial.resolution[0] >= 1440 && initial.resolution[1] >= 1000);

    // Use a clear, visible water patch; hit-testing here rejects roof/boat occlusion.
    const waterPoint = await page.evaluate(() => {
      const { THREE: T, camera, scene, gridView, waterSystem: w } = qa;
      const ray = new T.Raycaster();
      for (const [x, z] of [[-5, -13], [12, 5], [-5, 7], [-4, -10], [10, 12]]) {
        const world = new T.Vector3(x, 1.12, z);
        if (!gridView.isVisible(world)) continue;
        const p = world.clone().project(camera);
        if (Math.abs(p.x) > .8 || Math.abs(p.y) > .7) continue;
        ray.setFromCamera(new T.Vector2(p.x, p.y), camera);
        const dist = ray.ray.origin.distanceTo(world);
        const obstruction = ray.intersectObjects(scene.children, true).find(h => {
          if (h.object === w.surface || h.distance >= dist - .08 || h.point.y < 1.2) return false;
          for (let o = h.object; o; o = o.parent) if (!o.visible) return false;
          return true;
        });
        if (!obstruction) return { x: (p.x * .5 + .5) * innerWidth, y: (-p.y * .5 + .5) * innerHeight };
      }
      throw new Error('No unobstructed test water patch found');
    });
    const coinsBefore = await page.evaluate(() => qa.gameplay.art.state.coins);
    await page.mouse.click(waterPoint.x, waterPoint.y);
    assert.equal(await page.evaluate(() => qa.gameplay.art.state.coins), coinsBefore, 'Water must not activate a submerged building');
    await page.waitForFunction(n => qa.waterSystem.stats.clicks === n + 1, initial.clicks);
    const clicked = await page.evaluate(() => qa.waterSystem.uniforms.uRipples.value.some(r => r.w > 0 && r.z >= 0));
    assert(clicked, 'A water click should populate a ripple at a world-space anchor');
    await page.mouse.move(waterPoint.x, waterPoint.y);
    await page.mouse.down();
    await page.mouse.move(waterPoint.x + 65, waterPoint.y + 30, { steps: 6 });
    await page.mouse.up();
    assert.equal(await page.evaluate(() => qa.waterSystem.stats.clicks), initial.clicks + 1, 'Camera drag must not splash');

    const moving = await page.evaluate(() => {
      window.qaFreeze = true;
      const q = qa, w = q.waterSystem, a = q.gameplay.art;
      a.state.manualCamera = true;
      const fixed = q.gridView.center.clone();
      q.controls.target.x += 6; q.camera.position.x += 6;
      q.gridView.update(w.uniforms.uTime.value);
      const cameraIndependent = fixed.equals(q.gridView.center);
      a.state.workerMode = 'ROWING';
      a.boatAnchorGroup.rotation.y = Math.atan2(-.10, -.045);
      let t = w.uniforms.uTime.value;
      for (let i = 0; i < 90; i++) {
        t += .05;
        a.boatAnchorGroup.position.x -= .10;
        a.boatAnchorGroup.position.z -= .045;
        q.scene.updateMatrixWorld(true);
        w.update(.05, t); q.gridView.update(t);
      }
      q.gridView.update(t + 1);
      q.controls.target.copy(a.boatAnchorGroup.position);
      q.camera.position.copy(q.controls.target).add(new q.THREE.Vector3(-35, 49.5, 35));
      q.controls.update(); q.scene.updateMatrixWorld(true); q.camera.updateMatrixWorld(true);
      const center = q.gridView.center.toArray();
      const position = a.boatAnchorGroup.position.toArray();
      return { cameraIndependent, speed: w.uniforms.uBoat.value.w, stats: { ...w.stats }, center, position,
        liveWakes: w.uniforms.uWake.value.filter(v => v.w > 0 && t - v.z < 5).length };
    });
    assert(moving.cameraIndependent, 'Dragging the camera must leave the character visibility region unchanged');
    assert(moving.speed > 1 && moving.liveWakes > 0);
    assert(moving.stats.oarStrokes >= 2 && moving.stats.wakeSamples >= 5);
    assert(Math.abs(moving.center[0] - moving.position[0]) <= 1.5);
    assert(Math.abs(moving.center[1] - moving.position[2]) <= 1.5);
    await page.waitForTimeout(300);
    await page.screenshot({ path: 'outputs/water-redesign-sailing.png' });

    const stopped = await page.evaluate(() => {
      const q = qa, w = q.waterSystem;
      q.gameplay.art.state.workerMode = 'IDLE_ASHORE';
      let t = w.uniforms.uTime.value;
      for (let i = 0; i < 120; i++) { t += .05; w.update(.05, t); }
      return { speed: w.uniforms.uBoat.value.w, stats: { ...w.stats },
        liveWakes: w.uniforms.uWake.value.filter(v => v.w > 0 && t - v.z < 5).length,
        liveRipples: w.uniforms.uRipples.value.filter(v => v.w > 0 && t - v.z < 3.5).length,
        rippleCount: w.uniforms.uRipples.value.length, wakeCount: w.uniforms.uWake.value.length };
    });
    assert(stopped.speed < .01, 'Bow foam speed must settle after stopping');
    assert.equal(stopped.stats.landings, moving.stats.landings + 1);
    assert.equal(stopped.liveWakes, 0);
    assert.equal(stopped.liveRipples, 0);
    assert.equal(stopped.rippleCount, 16);
    assert.equal(stopped.wakeCount, 24);
    await page.waitForTimeout(250);
    await page.setViewportSize({width: 900,height: 700});
    await page.waitForFunction(() => qa.waterSystem.uniforms.uResolution.value.x === 900);
    await page.evaluate(() => {
      const {camera,controls}=qa;
      camera.position.sub(controls.target).multiplyScalar(.78).add(controls.target);
      camera.updateMatrixWorld(true);
    });
    await page.waitForTimeout(200);
    await page.screenshot({path:'outputs/water-redesign-closeup.png'});
    assert.deepEqual(errors, []);
    const result = { passed: ['Depth/refraction render target initialized', 'Water click emits a world-space ripple',
      'Camera drags do not splash or move visibility center', 'Moving boat leaves historical foam and paddle ripples',
      'Character visibility follows the boat', 'Landing emits one contact ripple', 'Wake and ripples expire in bounded pools',
      'Water clicks do not upgrade submerged buildings', 'Refraction target resizes and zoom renders cleanly', 'No JavaScript or shader errors'], initial, moving, stopped, errors };
    fs.writeFileSync('outputs/water-regression-results.json', JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result, null, 2));
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
