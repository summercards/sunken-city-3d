// 水面寻路单测（纯 Node，不需要浏览器）。
//   运行：node --test tests/sail-nav-unit.cjs
//
// 重点验三件事：能绕开一整片障碍（而不是只会躲一个）、绕出来的直线段真的不穿墙、
// 被围住时不假装找到路。
const test = require('node:test');
const assert = require('node:assert/strict');

// sail-nav.js 是 ESM，CommonJS 用动态 import。
const load = () => import('../sail-nav.js');

const BOUNDS = { minX: -20, maxX: 20, minZ: -20, maxZ: 20 };

function segmentClearEverywhere(grid, path, step = 0.2) {
  for (let i = 1; i < path.length; i++) {
    const a = path[i - 1];
    const b = path[i];
    const d = Math.hypot(b.x - a.x, b.z - a.z);
    const n = Math.max(1, Math.ceil(d / step));
    for (let s = 0; s <= n; s++) {
      const t = s / n;
      const x = a.x + (b.x - a.x) * t;
      const z = a.z + (b.z - a.z) * t;
      // 起点 / 终点允许压在障碍边上（船就停在那儿），中段不许。
      const edge = s === 0 && i === 1;
      if (edge) continue;
      if (!isFreeAt(grid, x, z)) return { ok: false, at: [x, z], seg: i };
    }
  }
  return { ok: true };
}

function isFreeAt(grid, x, z) {
  const i = Math.floor((x - grid.bounds.minX) / grid.cell);
  const j = Math.floor((z - grid.bounds.minZ) / grid.cell);
  if (i < 0 || j < 0 || i >= grid.cols || j >= grid.rows) return false;
  return grid.blocked[j * grid.cols + i] === 0;
}

test('空旷水面：直连，长度约等于直线距离', async () => {
  const { createNavGrid, planRoute, pathLength } = await load();
  const grid = createNavGrid({ rects: [], bounds: BOUNDS, cell: 0.5, clearance: 1 });
  const path = planRoute(grid, { x: -10, z: -10 }, { x: 10, z: 10 });
  assert.ok(path && path.length >= 2);
  const straight = Math.hypot(20, 20);
  assert.ok(pathLength(path) <= straight * 1.05, `绕远了：${pathLength(path)} vs ${straight}`);
});

test('一整排障碍：从墙的端点绕过去，而不是穿墙', async () => {
  const { createNavGrid, planRoute, pathLength } = await load();
  // z = 0 处一堵 30m 宽的墙，南端 x=15 处留口。
  const rects = [{ minX: -15, maxX: 15, minZ: -0.6, maxZ: 0.6 }];
  const grid = createNavGrid({ rects, bounds: BOUNDS, cell: 0.5, clearance: 1 });
  const path = planRoute(grid, { x: 0, z: -8 }, { x: 0, z: 8 });
  assert.ok(path, '应该能找到路');
  const check = segmentClearEverywhere(grid, path);
  assert.ok(check.ok, `航迹在 ${JSON.stringify(check)} 穿墙`);
  // 必须真的拐到墙的某一端（|x|>15）去绕过，而不是从中间穿。
  assert.ok(path.some((p) => Math.abs(p.x) > 15), '没有绕到墙的端点');
  const straight = 16;
  assert.ok(pathLength(path) < 60, `绕得太远：${pathLength(path)}`);
});

test('U 形口袋：不会走进死胡同后放弃', async () => {
  const { createNavGrid, planRoute } = await load();
  // 三面包围、开口朝北的口袋，起点在口袋里。
  const rects = [
    { minX: -8, maxX: -6, minZ: -8, maxZ: 6 },
    { minX: 6, maxX: 8, minZ: -8, maxZ: 6 },
    { minX: -8, maxX: 8, minZ: -8, maxZ: -6 }
  ];
  const grid = createNavGrid({ rects, bounds: BOUNDS, cell: 0.5, clearance: 0.8 });
  const path = planRoute(grid, { x: 0, z: -2 }, { x: 0, z: 14 });
  assert.ok(path, '开口朝北时应该能出去');
  assert.ok(segmentClearEverywhere(grid, path).ok, '航迹穿墙');
});

test('完全封死：返回 null，而不是给一条穿墙的直线', async () => {
  const { createNavGrid, findPath } = await load();
  const rects = [
    { minX: -6, maxX: 6, minZ: -6, maxZ: -4 },
    { minX: -6, maxX: 6, minZ: 4, maxZ: 6 },
    { minX: -6, maxX: -4, minZ: -6, maxZ: 6 },
    { minX: 4, maxX: 6, minZ: -6, maxZ: 6 }
  ];
  const grid = createNavGrid({ rects, bounds: BOUNDS, cell: 0.5, clearance: 0.6 });
  const path = findPath(grid, { x: 0, z: 0 }, { x: 14, z: 0 });
  assert.equal(path, null);
});

test('起点压在障碍里：先吸到最近的可通行格', async () => {
  const { createNavGrid, planRoute, nearestFree, isFree } = await load();
  const rects = [{ minX: -2, maxX: 2, minZ: -2, maxZ: 2 }];
  const grid = createNavGrid({ rects, bounds: BOUNDS, cell: 0.5, clearance: 0.5 });
  assert.equal(isFree(grid, 0, 0), false);
  const snapped = nearestFree(grid, 0, 0, 20);
  assert.ok(snapped, '应该能找到最近的空格');
  assert.ok(isFree(grid, snapped.x, snapped.z));
  const path = planRoute(grid, { x: 0, z: 0 }, { x: 12, z: 0 });
  assert.ok(path && path.length >= 2);
});

test('斜向贴着两个障碍的夹角：不许从缝里蹭过去', async () => {
  const { createNavGrid, findPath } = await load();
  // 两个方块在 (0,0) 对角相贴，实际只留下一个针孔。斜向穿过去必须被挡住。
  const rects = [
    { minX: -4, maxX: 0.1, minZ: -4, maxZ: -0.1 },
    { minX: -0.1, maxX: 4, minZ: 0.1, maxZ: 4 }
  ];
  const grid = createNavGrid({ rects, bounds: BOUNDS, cell: 0.5, clearance: 0.5 });
  const path = findPath(grid, { x: 2, z: -2 }, { x: -2, z: 2 });
  assert.ok(path, '绕外面应该还有路');
  assert.ok(segmentClearEverywhere(grid, path).ok, '航迹从夹角里蹭过去了');
});

test('栅格化用重叠判定：半个格子压住障碍也算阻挡', async () => {
  const { createNavGrid, isFree } = await load();
  const rects = [{ minX: 0, maxX: 0.2, minZ: -5, maxZ: 5 }];
  const grid = createNavGrid({ rects, bounds: BOUNDS, cell: 0.5, clearance: 0 });
  // 0..0.5 这一格只有左边 0.2m 是障碍，也必须算阻挡。
  assert.equal(isFree(grid, 0.4, 0), false);
  assert.equal(isFree(grid, 1.2, 0), true);
});
