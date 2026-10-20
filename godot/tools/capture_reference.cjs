// 截一张「网页版 · 建成态」参考图，给 Godot 画面调色/对比用。
//
// 为什么必须拉满建造等级：Godot 的烘焙资产取自建成态（living-harbor 的爬藤/花丛/
// 屋顶花园按等级控制 visible）。直接截网页初始态，圆楼顶上会是一片空地，
// 拿它当基准会把「本来就该有的绿植」当成 Godot 多画的。
//
// 用法：先起静态服务，然后
//   NODE_PATH=~/.workbuddy/binaries/node/workspace/node_modules \
//   node tools/capture_reference.cjs
const path = require('node:path');
const { chromium } = require('playwright');

const OUT = path.join(__dirname, '..', 'outputs', 'reference-web.png');
const URL = process.env.APP_URL || 'http://localhost:8765/index.html';

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
    args: ['--enable-webgl', '--ignore-gpu-blocklist'],
  });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });
  await page.route('**/index.html', async (route) => {
    const res = await route.fetch();
    const body = (await res.text()).replace(
      '    animate();',
      '    window.__ref = { gameplay };\n    animate();'
    );
    await route.fulfill({ response: res, body });
  });
  await page.goto(URL, { waitUntil: 'load' });
  await page.waitForFunction(() => window.__ref, null, { timeout: 90000 });
  await page.waitForTimeout(1800);

  const lifted = await page.evaluate(async () => {
    const art = window.__ref.gameplay.art;
    if (!art || !art.buildSites) return { ok: false };
    for (const s of art.buildSites) s.level = s.maxLevel != null ? s.maxLevel : Math.max(2, s.level || 0);
    if (art.facilities) for (const k of Object.keys(art.facilities)) art.facilities[k].level = 1;
    await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
    await new Promise((r) => setTimeout(r, 500));
    return { ok: true };
  });
  console.log('建成态:', lifted.ok);

  // 屏幕上的 emoji 标记不属于画面本身，先摘掉再截。
  await page.evaluate(() => {
    document.querySelectorAll('.marker,.landing-marker,.fish-school-marker').forEach((e) => e.remove());
  });
  await page.waitForTimeout(500);
  await page.screenshot({ path: OUT });
  await browser.close();
  console.log('→', path.relative(process.cwd(), OUT));
})();
