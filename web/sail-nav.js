// 水面 / 甲板寻路：把障碍压成栅格，用 A* 找路，再用「拉绳」把折线拉直。
//
// 为什么不用「碰到矩形就绕到它的四个角」那套：拐角法只看下一个障碍，绕完一个又撞下一个，
// 障碍密的地方会走进死角、或者干脆放弃绕行直接穿过去（之前的航线就是从这条路径里穿墙的）。
// 栅格 A* 一次性考虑所有障碍，路径天然是「绕过一整片」而不是「躲开一个再躲下一个」。
//
// 这个模块是纯数据实现，不依赖 THREE，也不碰 DOM，所以能直接用 node --test 跑。
//
// 坐标约定：世界坐标用 {x, z}，栅格把 (bounds.minX, bounds.minZ) 当原点。

export const NAV_CELL = 0.5;

// 矩形 → 阻挡栅格。矩形按 clearance 外扩后再栅格化，且用「格子与矩形有重叠即阻挡」，
// 不用「格子中心落在矩形内」—— 后者会留下半个格子压在障碍里的可通行格，船会擦边。
export function createNavGrid({ rects = [], bounds, cell = NAV_CELL, clearance = 1 }) {
  const cols = Math.max(1, Math.ceil((bounds.maxX - bounds.minX) / cell));
  const rows = Math.max(1, Math.ceil((bounds.maxZ - bounds.minZ) / cell));
  const blocked = new Uint8Array(cols * rows);
  for (const r of rects) {
    const minX = r.minX - clearance;
    const maxX = r.maxX + clearance;
    const minZ = r.minZ - clearance;
    const maxZ = r.maxZ + clearance;
    let i0 = Math.max(0, Math.floor((minX - bounds.minX) / cell));
    let i1 = Math.min(cols - 1, Math.floor((maxX - bounds.minX) / cell));
    let j0 = Math.max(0, Math.floor((minZ - bounds.minZ) / cell));
    let j1 = Math.min(rows - 1, Math.floor((maxZ - bounds.minZ) / cell));
    for (let j = j0; j <= j1; j++) {
      const z0 = bounds.minZ + j * cell;
      if (z0 > maxZ || z0 + cell < minZ) continue;
      const row = j * cols;
      for (let i = i0; i <= i1; i++) {
        const x0 = bounds.minX + i * cell;
        if (x0 > maxX || x0 + cell < minX) continue;
        blocked[row + i] = 1;
      }
    }
  }
  return { cell, cols, rows, bounds: { ...bounds }, blocked, clearance };
}

export function cellOf(grid, x, z) {
  return {
    i: Math.floor((x - grid.bounds.minX) / grid.cell),
    j: Math.floor((z - grid.bounds.minZ) / grid.cell)
  };
}

export function cellCenter(grid, i, j) {
  return {
    x: grid.bounds.minX + (i + 0.5) * grid.cell,
    z: grid.bounds.minZ + (j + 0.5) * grid.cell
  };
}

export function isFreeCell(grid, i, j) {
  if (i < 0 || j < 0 || i >= grid.cols || j >= grid.rows) return false;
  return grid.blocked[j * grid.cols + i] === 0;
}

export function isFree(grid, x, z) {
  const { i, j } = cellOf(grid, x, z);
  return isFreeCell(grid, i, j);
}

// 从给定格子向外一圈圈找最近的可通行格（起点/终点常常压在停泊位边上）。
export function nearestFree(grid, x, z, maxRing = 24) {
  const { i, j } = cellOf(grid, x, z);
  if (isFreeCell(grid, i, j)) return { i, j, ...cellCenter(grid, i, j) };
  for (let ring = 1; ring <= maxRing; ring++) {
    let best = null;
    for (let dj = -ring; dj <= ring; dj++) {
      for (let di = -ring; di <= ring; di++) {
        // 只扫这一圈的边框，避免重复检查内部。
        if (Math.max(Math.abs(di), Math.abs(dj)) !== ring) continue;
        const ni = i + di;
        const nj = j + dj;
        if (!isFreeCell(grid, ni, nj)) continue;
        const d = di * di + dj * dj;
        if (!best || d < best.d) best = { i: ni, j: nj, d };
      }
    }
    if (best) return { i: best.i, j: best.j, ...cellCenter(grid, best.i, best.j) };
  }
  return null;
}

// 两点之间是否全程可通行（按格子采样，步长小于半格，避免穿过薄墙的一角）。
// skipStart：跳过距起点这么远以内的采样 —— 停泊位本身就压在障碍边上，
// 船已经在那儿了，这一小段交给运行时船壳推出兜住，不能让整条航迹因此作废。
export function lineIsClear(grid, a, b, skipStart = 0) {
  const dist = Math.hypot(b.x - a.x, b.z - a.z);
  const steps = Math.max(1, Math.ceil(dist / (grid.cell * 0.4)));
  for (let s = 1; s <= steps; s++) {
    const t = s / steps;
    if (t * dist < skipStart) continue;
    if (!isFree(grid, a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t)) return false;
  }
  return true;
}

// 最小二叉堆（按 f 排序）。路径点数量级在千以内，够用且比每次 sort 便宜。
function createHeap(capacity) {
  const nodes = new Int32Array(capacity);
  let size = 0;
  const score = new Float32Array(capacity);
  return {
    get size() { return size; },
    push(idx, f) {
      let n = size++;
      nodes[n] = idx;
      score[n] = f;
      while (n > 0) {
        const p = (n - 1) >> 1;
        if (score[p] <= score[n]) break;
        [nodes[p], nodes[n]] = [nodes[n], nodes[p]];
        [score[p], score[n]] = [score[n], score[p]];
        n = p;
      }
    },
    pop() {
      if (!size) return -1;
      const top = nodes[0];
      size--;
      if (size > 0) {
        nodes[0] = nodes[size];
        score[0] = score[size];
        let n = 0;
        for (;;) {
          const l = n * 2 + 1;
          const r = l + 1;
          let m = n;
          if (l < size && score[l] < score[m]) m = l;
          if (r < size && score[r] < score[m]) m = r;
          if (m === n) break;
          [nodes[m], nodes[n]] = [nodes[n], nodes[m]];
          [score[m], score[n]] = [score[n], score[m]];
          n = m;
        }
      }
      return top;
    }
  };
}

const DIRS = [
  [1, 0, 1], [-1, 0, 1], [0, 1, 1], [0, -1, 1],
  [1, 1, Math.SQRT2], [1, -1, Math.SQRT2], [-1, 1, Math.SQRT2], [-1, -1, Math.SQRT2]
];

// A*。返回世界坐标点列（含起终点附近的可通行格中心），找不到返回 null。
export function findPath(grid, start, end, { maxExpansions = 240000 } = {}) {
  const cols = grid.cols;
  const rows = grid.rows;
  const total = cols * rows;

  const s = nearestFree(grid, start.x, start.z, 24);
  const e = nearestFree(grid, end.x, end.z, 24);
  if (!s || !e) return null;

  const startIdx = s.j * cols + s.i;
  const goalIdx = e.j * cols + e.i;
  // 起终点落在同一格：直接给一条短直线。
  if (startIdx === goalIdx) return [{ x: start.x, z: start.z }, { x: end.x, z: end.z }];

  const gScore = new Float32Array(total).fill(Infinity);
  const fScore = new Float32Array(total).fill(Infinity);
  const from = new Int32Array(total).fill(-1);
  const closed = new Uint8Array(total);
  const heap = createHeap(total);

  const h = (i, j) => {
    const dx = Math.abs(i - e.i);
    const dy = Math.abs(j - e.j);
    return (dx + dy) + (Math.SQRT2 - 2) * Math.min(dx, dy);
  };

  gScore[startIdx] = 0;
  fScore[startIdx] = h(s.i, s.j);
  heap.push(startIdx, fScore[startIdx]);

  let expansions = 0;
  let found = false;
  while (heap.size) {
    const cur = heap.pop();
    if (cur === goalIdx) { found = true; break; }
    if (closed[cur]) continue;
    closed[cur] = 1;
    if (++expansions > maxExpansions) break;
    const ci = cur % cols;
    const cj = (cur - ci) / cols;
    for (const [di, dj, cost] of DIRS) {
      const ni = ci + di;
      const nj = cj + dj;
      if (!isFreeCell(grid, ni, nj)) continue;
      // 斜走不许从两个障碍的夹角里蹭过去。
      if (di && dj) {
        if (!isFreeCell(grid, ci + di, cj) || !isFreeCell(grid, ci, cj + dj)) continue;
      }
      const nIdx = nj * cols + ni;
      if (closed[nIdx]) continue;
      // 贴着障碍的格子加一点代价，让船走在水道中间而不是贴着墙。
      let blockedAround = 0;
      if (!isFreeCell(grid, ni + 1, nj)) blockedAround++;
      if (!isFreeCell(grid, ni - 1, nj)) blockedAround++;
      if (!isFreeCell(grid, ni, nj + 1)) blockedAround++;
      if (!isFreeCell(grid, ni, nj - 1)) blockedAround++;
      const tentative = gScore[cur] + cost * (1 + blockedAround * 0.42);
      if (tentative >= gScore[nIdx]) continue;
      gScore[nIdx] = tentative;
      fScore[nIdx] = tentative + h(ni, nj);
      from[nIdx] = cur;
      heap.push(nIdx, fScore[nIdx]);
    }
  }
  if (!found) return null;

  const cells = [];
  for (let idx = goalIdx; idx !== -1; idx = from[idx]) {
    const i = idx % cols;
    cells.push(cellCenter(grid, i, (idx - i) / cols));
    if (idx === startIdx) break;
  }
  cells.reverse();
  // 用真实起终点替换首尾（首尾格中心可能被 closest-free 挪开了一两米）。
  cells[0] = { x: start.x, z: start.z };
  cells[cells.length - 1] = { x: end.x, z: end.z };
  return cells;
}

// 拉绳平滑：从当前锚点尽量往后找「直线可达」的最远点，把 A* 的阶梯折线拉成直航段。
export function smoothPath(grid, points) {
  if (!points || points.length <= 2) return points || [];
  const out = [points[0]];
  let anchor = 0;
  while (anchor < points.length - 1) {
    let next = points.length - 1;
    while (next > anchor + 1) {
      const a = points[anchor];
      const b = points[next];
      // 起点那一小段可能压在停泊位边上，跳过前 1.6m 的判定。
      if (lineIsClear(grid, a, b, anchor === 0 ? 1.6 : 0)) break;
      next--;
    }
    out.push(points[next]);
    anchor = next;
  }
  return out;
}

// 一次搞定：A* + 平滑。找不到返回 null，调用方自己决定退化成什么。
export function planRoute(grid, start, end) {
  const raw = findPath(grid, start, end);
  if (!raw || raw.length < 2) return null;
  return smoothPath(grid, raw);
}

export function pathLength(points) {
  let sum = 0;
  for (let i = 1; i < points.length; i++) {
    sum += Math.hypot(points[i].x - points[i - 1].x, points[i].z - points[i - 1].z);
  }
  return sum;
}
