// 从网页版直接取水面岸线轮廓，写进 assets/baked/shore.json。
//
// 为什么不在 GDScript / Python 里重算：网页版 shoreOutline() 用的是 zone.regions
// （可能和 zones.json 的 walk.rects 不是同一份数据，圆楼那块尤其明显），
// 自己重算会出现水纹和建筑错位——水面波纹整片漂在空水域上。
//
// 用法：先在 sea/ 起静态服务（python3 -m http.server 8765），然后
//   NODE_PATH=~/.workbuddy/binaries/node/workspace/node_modules \
//   node tools/capture_shore.cjs
const path = require('node:path');
const fs = require('node:fs');
const { chromium } = require('playwright');

const OUT = path.join(__dirname, '..', 'assets', 'baked', 'shore.json');
const URL = process.env.APP_URL || 'http://localhost:8765/index.html';

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
  });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(URL);
  await page.waitForFunction(() => window.__shoreOutline, { timeout: 90000 });
  const data = await page.evaluate(() => ({
    waterLevel: window.WATER_LEVEL ?? 1.12,
    shapes: window.__shoreOutline.map((s) => ({
      x: +s.x.toFixed(3),
      z: +s.z.toFixed(3),
      hx: +s.hx.toFixed(3),
      hz: +s.hz.toFixed(3),
      round: !!s.round,
    })),
  }));
  await browser.close();
  if (errors.length) {
    console.error('页面报错：', errors.slice(0, 3));
    process.exit(1);
  }
  fs.writeFileSync(OUT, JSON.stringify(data, null, 1));
  const round = data.shapes.filter((s) => s.round).length;
  console.log(`shapes: ${data.shapes.length}（圆形 ${round}） → ${path.relative(process.cwd(), OUT)}`);
  if (data.shapes.length > 32) {
    console.warn(`[warn] ${data.shapes.length} 个形状超过 shader 的 32 槽位，末尾会被丢掉。`);
  }
})();
