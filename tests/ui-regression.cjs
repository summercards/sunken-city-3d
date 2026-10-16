const { chromium } = require('playwright');
const assert = require('node:assert/strict');

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
    args: ['--enable-webgl', '--ignore-gpu-blocklist'],
  });
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
    const errors = [];
    const passed = [];
    page.on('pageerror', error => errors.push(error.message));
    // Expose state only in the intercepted test response; production has no test API.
    await page.route('**/gameplay.js', async route => {
      const response = await route.fetch();
      const body = (await response.text()).replace('slowCoinTimer += safeDt;', 'if (!window.__pauseProduction) slowCoinTimer += safeDt;').replace(
        '  syncCoinUI();\n  return {',
        '  window.__qa = { camera, controls, buildSites, state, explorerGroup, boatAnchorGroup, positionHoverCardForTarget };\n  syncCoinUI();\n  return {'
      );
      await route.fulfill({ response, body });
    });
    await page.goto(process.env.APP_URL || 'http://localhost:8765');
    await page.waitForFunction(() => window.__qa && document.querySelector('[data-site-id="home_cabin"].in-view'));
    await page.waitForTimeout(1000);
    const orb = page.locator('[data-site-id="home_cabin"]');
    const card = page.locator('.hover-context-card');
    const content = page.locator('.hc-content');
    assert.equal(await page.locator('.resource-orb').count(), 3);
    assert.equal(await page.locator('.focus-worker-btn').count(), 0);
    assert.equal(await page.locator('.controls-group').isVisible(), false);
    assert.equal(await page.locator('.worker-state-dot').boundingBox().then(b => b.width), 1);
    assert.equal(await card.locator('button').count(), 0);
    assert.equal(await orb.getAttribute('data-mode'), 'upgrade');
    assert.equal(await orb.getAttribute('aria-disabled'), 'false');
    passed.push('One shared action per building; no bottom toolbar or card action button');

    await page.mouse.move(749, 372);
    await page.waitForTimeout(90);
    assert(await card.evaluate(e => e.classList.contains('visible')));
    assert(await content.evaluate(e => e.getAnimations().length > 0));
    await page.waitForTimeout(400);
    const title = await page.locator('#hc-title').textContent();
    await orb.hover();
    assert.equal(await page.locator('#hc-title').textContent(), title);
    const size = await card.boundingBox();
    assert(size.width <= 220 && size.height <= 82);
    const alpha = await content.evaluate(e => getComputedStyle(e).backgroundColor);
    assert(alpha.includes('0.78'));
    await page.screenshot({ path: 'outputs/ui-compact-upgrade.png' });
    passed.push('Building and icon share a compact, translucent, animated tooltip');

    await page.mouse.move(1180, 620);
    await page.waitForTimeout(145);
    const fading = await content.evaluate(e => Number(getComputedStyle(e).opacity));
    assert(fading > 0 && fading < 1);
    await page.waitForTimeout(250);
    assert.equal(await content.evaluate(e => Number(getComputedStyle(e).opacity)), 0);
    passed.push('Tooltip animates on entry and exit');

    await page.waitForFunction(() => document.querySelector('[data-site-id="home_cabin"]').dataset.mode === 'harvest');
    await page.evaluate(() => { window.__pauseProduction = true; });
    await orb.hover();
    await page.waitForTimeout(450);
    await page.screenshot({ path: 'outputs/ui-compact-harvest.png' });
    const before = await page.evaluate(() => ({
      coins: window.__qa.state.coins,
      gain: Math.floor(window.__qa.buildSites.find(s => s.id === 'home_cabin').storedCoins),
      x: document.querySelector('[data-site-id="home_cabin"]').style.left,
      y: document.querySelector('[data-site-id="home_cabin"]').style.top,
    }));
    await orb.evaluate(e => { e.click(); e.click(); });
    // A rapid second activation during collection may not purchase an upgrade.
    await orb.evaluate(e => e.click());
    await page.waitForTimeout(750);
    assert.equal(await page.locator('#min-coin-val').textContent(), String(before.coins + before.gain));
    assert.equal(await orb.getAttribute('data-mode'), 'upgrade');
    assert.equal(await orb.getAttribute('aria-disabled'), 'false');
    const after = await orb.evaluate(e => ({ x: e.style.left, y: e.style.top, icon: e.textContent }));
    assert(Math.abs(parseFloat(after.x) - parseFloat(before.x)) < .1);
    assert(Math.abs(parseFloat(after.y) - parseFloat(before.y)) < .1);
    assert.equal(after.icon, '↑');
    await page.screenshot({ path: 'outputs/ui-compact-after-collect.png' });
    passed.push('Harvest takes priority, settles once, then reveals an arrow at the identical position');

    const balance = await page.evaluate(() => window.__qa.state.coins);
    await page.evaluate(() => { window.__qa.state.coins = 0; });
    await page.waitForTimeout(100);
    assert.equal(await orb.getAttribute('aria-disabled'), 'true');
    assert.equal(await orb.evaluate(e => e.classList.contains('available')), false);
    await orb.hover();
    assert((await page.locator('#hc-summary').textContent()).includes('还差'));
    await orb.click({ force: true });
    assert.equal(await page.evaluate(() => window.__qa.state.workerMode), 'IDLE_ASHORE');
    await page.screenshot({ path: 'outputs/ui-compact-unavailable.png' });
    await page.evaluate(value => { window.__qa.state.coins = value; }, balance);
    await page.waitForTimeout(100);
    passed.push('Insufficient funds show a grey arrow and cannot start an upgrade');

    await orb.click();
    assert.equal(await page.locator('#min-coin-val').textContent(), String(balance - 20));
    await page.waitForFunction(() => window.__qa.state.workerMode === 'BUILDING', null, { timeout: 20000 });
    assert.equal(await orb.getAttribute('aria-disabled'), 'true');
    assert.equal(await page.locator('.build-progress-pill').isVisible(), true);
    await page.waitForFunction(() => window.__qa.buildSites.find(s => s.id === 'home_cabin').level === 2, null, { timeout: 20000 });
    passed.push('Upgrade deducts once, shows busy state and progress, then completes');

    // Collect any yield accrued during construction, then a maxed building stays grey.
    if (await orb.getAttribute('data-mode') === 'harvest') {
      await orb.click();
      await page.waitForTimeout(380);
    }
    assert.equal(await orb.getAttribute('aria-disabled'), 'true');
    await orb.hover();
    assert.equal(await page.locator('#hc-summary').textContent(), '已满级');
    passed.push('Max level uses the same grey arrow with a one-line explanation');

    // Sample world anchoring between production ticks for both marker and tooltip.
    const projectionErrors = await page.evaluate(async () => {
      const q = window.__qa;
      q.state.manualCamera = true;
      const errors = [];
      for (let i = 0; i < 8; i++) {
        q.camera.position.x += .2;
        q.controls.target.x += .2;
        await new Promise(requestAnimationFrame);
        await new Promise(requestAnimationFrame);
        const anchor = q.buildSites.find(s => s.id === 'home_cabin').hoverAnchor.clone();
        anchor.y += .6;
        anchor.project(q.camera);
        const x = (anchor.x * .5 + .5) * innerWidth;
        errors.push(Math.abs(parseFloat(document.querySelector('[data-site-id="home_cabin"]').style.left) - x));
        errors.push(Math.abs(parseFloat(document.querySelector('.hover-context-card').style.left) - x));
      }
      return errors;
    });
    assert(Math.max(...projectionErrors) < .02);
    passed.push('Shared icon and tooltip remain anchored during camera movement');

    await page.keyboard.press('Escape');
    await page.waitForTimeout(300);
    assert.equal(await content.evaluate(e => Number(getComputedStyle(e).opacity)), 0);
    // The boat now provides destination selection because the bottom navigation is gone.
    const boatPoint = await page.evaluate(() => {
      const q = window.__qa;
      const p = q.boatAnchorGroup.position.clone();
      p.y += .5;
      p.project(q.camera);
      return { x: (p.x * .5 + .5) * innerWidth, y: (-p.y * .5 + .5) * innerHeight };
    });
    await page.mouse.click(boatPoint.x, boatPoint.y);
    await page.waitForTimeout(450);
    assert(await page.locator('.destination-wheel').evaluate(e => e.classList.contains('visible')));
    await page.screenshot({ path: 'outputs/ui-compact-destinations.png' });
    await page.keyboard.press('Escape');
    passed.push('Boat still opens destination selection; Escape closes contextual UI');

    await page.evaluate(() => {
      const q = window.__qa;
      q.camera.position.set(200, 30, 200);
      q.controls.target.set(300, 30, 300);
    });
    await page.waitForTimeout(300);
    assert.equal(await orb.evaluate(e => e.classList.contains('in-view')), false);
    assert.equal(await orb.getAttribute('tabindex'), '-1');
    passed.push('Offscreen hotspots are hidden and removed from keyboard navigation');

    await page.setViewportSize({ width: 390, height: 844 });
    await page.evaluate(() => { window.__qa.state.manualCamera = false; window.__qa.state.camLockMode = 'zone1'; });
    await page.waitForTimeout(1800);
    await orb.hover();
    await page.waitForTimeout(450);
    await page.screenshot({ path: 'outputs/ui-compact-mobile.png' });
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth), 390);
    passed.push('390px layout keeps the bottom clear without horizontal overflow');
    assert.deepEqual(errors, []);
    passed.push('No JavaScript runtime errors');
    console.log(JSON.stringify({ passed, maxProjectionError: Math.max(...projectionErrors) }, null, 2));
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
