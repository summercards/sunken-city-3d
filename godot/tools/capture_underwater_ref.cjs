// 截网页版水下（对照基准）。
//
// 用途：潜水场景的「物件闪动 / 建筑破碎」这类问题必须先有个基准，
// 否则只能凭感觉改。机位与 Godot 的 `--dive`（不传 --uwat）一致：
// 网页版入水后潜水员在 (0, waterLevel-?, 12)，相机被 diving.js 摆在
// (0, ~0.7, 22) 俯看下方，正好对上 Godot 的默认下潜机位。
//
// 用法（先起静态服务）：
//   NODE_PATH=~/.workbuddy/binaries/node/workspace/node_modules \
//   node tools/capture_underwater_ref.cjs [outPrefix] [waitMs]
const path = require('node:path');
const fs = require('node:fs');
const { chromium } = require('playwright');

const OUT_DIR = path.join(__dirname, '..', 'outputs');
const URL = process.env.APP_URL || 'http://localhost:8765/index.html';
const PREFIX = process.argv[2] || 'uwref';
const WAIT = parseInt(process.argv[3] || '4500', 10);

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
    args: ['--enable-webgl', '--ignore-gpu-blocklist', '--use-gl=angle'],
  });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });
  page.on('console', (m) => { if (m.type() === 'error') console.log('[page]', m.text()); });
  // 入口补丁：把 gameplay / diving 挂到 window（只改本地副本，不动源文件）。
  await page.route('**/index.html', async (route) => {
    const res = await route.fetch();
    const body = (await res.text()).replace(
      '    animate();',
      '    window.__ref = { gameplay, diving, camera, renderer, scene };\n    animate();'
    );
    await route.fulfill({ response: res, body });
  });
  await page.goto(URL, { waitUntil: 'load' });
  await page.waitForFunction(() => window.__ref, null, { timeout: 90000 });
  await page.waitForTimeout(2200);

  const info = await page.evaluate(async () => {
    const btn = document.getElementById('dive-button');
    if (!btn) return 'no dive button';
    btn.click();
    await new Promise((r) => setTimeout(r, 150));
    const d = window.__ref.diving;
    return { active: d ? d.active : null, phase: d ? d.phase : null, canDive: d ? !!d.canDive : null };
  });
  console.log('dive:', JSON.stringify(info));
  await page.waitForTimeout(WAIT);
  // 等真正进入 swim 阶段：enter 阶段相机还在水面，截到的不是水下视角。
  await page.waitForFunction(() => {
    const d = window.__ref && window.__ref.diving;
    return !!(d && d.phase === 'swim');
  }, null, { timeout: 30000 }).catch(() => console.log('warn: 未进入 swim'));
  await page.waitForTimeout(900);

  const cam = await page.evaluate(() => {
    const g = window.__ref.gameplay;
    const c = window.__ref.camera;
    return { pos: [c.position.x, c.position.y, c.position.z].map((v) => +v.toFixed(2)),
             fov: c.fov, near: c.near, far: c.far };
  });
  console.log('camera:', JSON.stringify(cam));

  await page.screenshot({ path: path.join(OUT_DIR, `${PREFIX}-overview.png`) });
  const poses = [
    ['neighborhood', [-14, -6, 20]],
    ['reef', [8, -14, -22]],
    ['trench', [-2, -200, -120]],
  ];
  const cameras = {};
  for (const [name, pos] of poses) {
    await page.evaluate(pos => {
      window.__ref.gameplay.art.explorerGroup.position.set(...pos);
    }, pos);
    await page.waitForTimeout(1800);
    cameras[name] = await page.evaluate(() => {
      const { camera: c, gameplay } = window.__ref;
      return { position: c.position.toArray(), quaternion: c.quaternion.toArray(),
        fov: c.fov, diver: gameplay.art.explorerGroup.position.toArray() };
    });
    console.log(name, JSON.stringify(cameras[name]));
    await page.screenshot({ path: path.join(OUT_DIR, `${PREFIX}-${name}.png`) });
  }
  fs.writeFileSync(path.join(OUT_DIR, `${PREFIX}-cameras.json`), JSON.stringify(cameras, null, 2));

  await browser.close();
  console.log('done');
})();
