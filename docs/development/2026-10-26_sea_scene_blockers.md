# 海上场景阻挡整理与组件自带阻挡（2026-10-26）

所属功能：SEA-WORLD。本轮只处理 zone1 家园区块（海上场景），其余区块保留现状但已接入同一机制。

## 1. 问题复现与量化

用只读探针 `godot/tools/probe_blockers.gd` 把「可见几何」「可行走面」「岸线阻挡」量到同一份报告里：
给每个可见网格临时建三角面碰撞，在阻挡内部与行走矩形内逐 0.5m 采样，向下/向上/水平打射线。

修复前（真实渲染，headless 下 MultiMesh 变换读不出来，结果无效）：

| 位置 | 现象 | 实测 |
|---|---|---|
| 绞盘打捞台 | 模型与节点位置不一致：节点 `(-12, 0, 13)`，几何中心 `(-18.9, 21.7)`，GLB 顶点自带 `(-6.9, 8.7)` 偏移 | `zone1_salvage` 可行走区甲板覆盖 **0.00**（整块悬空走道） |
| 木屋码头 | 行走矩形只到 `x=6.66`，实际平台甲板到 `x=9.5`；北侧 `z<5` 没有地面 | `zone1_home_dock` 甲板覆盖 **0.03** |
| shore.json 第 5 条 | 旧打捞台位置的岸线，模型已移走 | 支撑率 **0.00**，船在空水面上被挡 |
| shore.json 第 1 条 | 旧 unit_01 的 footprint，木屋北墙只到 `z=-3.59` | 支撑率 0.29，北侧约 3.3m 空气墙 |
| shore.json 第 27 条 | 栈桥阻挡 `x 0.93..5.21`，实际桥板 `x 0.30..5.95` | 每侧漏 0.6m，船头能插进桥板 |

根因不是某一条数据写错，而是**阻挡有三份互不相干的来源**：

1. `assets/baked/shore.json` —— 船的水面阻挡，由 `tools/make_shore.py` 从 `zones.json` 的 `walk.rects` 烘焙；
2. 场景里的 `WalkAreas` —— 玩家行走矩形，手工写死在区块 TSCN；
3. 组件 prefab —— 147 个场景里 **0 个** StaticBody3D / CollisionShape3D，完全不声明阻挡。

所以替换模型只改了第 3 份，前两份仍是旧值：模型走了，阻挡留下。

## 2. 改动

### 2.1 组件自带阻挡（新增）

- `godot/src/world/blocker_set.gd`：组件级的阻挡声明节点。
  - `mode=auto` 从自身可见几何派生，只取与「水线 ~ 船高」这一段真正相交的三角形，屋檐/树冠/阳台不会在水面生成空阻挡；
  - 0.4m 栅格化后合并成世界坐标矩形，带「孤立格清理」与「1 格夹缝填充」；
  - `mode=manual` 用本地矩形兜底，`mode=none` 显式声明不参与。
- `godot/src/world/zone_scene.gd`：`_ensure_blockers()` 给 `Models` 下每个可见组件根补一个 `Blockers`；`rebuild_blockers()` 统一派生并汇总成 `water_block_rects`。退休的 `visible=false` 单元不再挡船。
- `godot/src/world/sunny_bloom_visual.gd`：MultiMesh 实例变换同时写入 `instance_transforms` meta。headless 的 dummy renderer 读 `MultiMesh.get_instance_transform()` 一律返回单位矩阵，没有这份 meta 时木屋会全部塌在原点。
- `godot/src/bootstrap/main.gd`：`_water_shapes()` 成为水面阻挡的唯一入口 —— 区块内取各组件派生结果，远景水街区取 `assets/baked/shore_environment.json`（只有烘焙几何、没有组件场景），两者都为空才回退旧 `shore.json`。`_is_open_water` 与 `nav_grid()` 共用同一份数据，并加了 6m 网格索引（阻挡条数从 27 涨到 200+，线性扫会拖慢航路检查）。

### 2.2 海上场景数据

- 绞盘打捞台节点 `(-12, 0, 13)` → `(-5.0, 0, 4.15)`：抵消 GLB 顶点偏移，让几何回到设计位置 `(-11.9, 12.85)`。一处修正后，`WalkAreas` / `landings` / 岸线三份数据同时对齐，不靠改数据迁就错误模型。
- `zone1_home_dock` 行走矩形改为按实测甲板：`(-1,5)-(4.5,11.5)`、`(4.5,7.5)-(9.5,11.5)`、`(0,11.5)-(6.5,18)`，覆盖平台东侧 3m 原本走不到的甲板。
- `zone1_salvage` 行走矩形改为实测甲板 `x -16.5..-9.0, z 10.2..13.5`。
- `zones.json` 同步以上矩形；zone5 泊位外移 0.5m（`x 17.27 → 16.77`），新派生阻挡比旧烘焙岸线更贴近柱子，原泊位与安全边距只剩 0.08m。
- 订单板由 `tools/place_trade_board.py` 重新求解：`(-9.5,1.33,14.1)` → `(-0.2,2.15,10.7)`。旧位置随打捞台移走已成悬空板。

### 2.3 校验

- `godot/tools/verify_blockers.gd`：两条断言。
  1. 每条面积 ≥1m² 的阻挡矩形内部，必须有跨水实体（空阻挡）；
  2. 每个可见组件的 AABB 内侧 0.5m 范围内，跨水有实体就必须被阻挡覆盖（漏阻挡）。
- 接入 `scripts/run_verification.py` 为 `visual-blockers`（必须真实渲染，不能 headless）。

### 2.4 成本

五个区块阻塞派生合计约 555ms（zone1 332 / zone2 67 / zone3 103 / zone4 32 / zone5 22）。放在 `_ready` 之后一帧预热（`_warm_water_shapes`），不落在第一次点水面上。
阻断形状从 27 条涨到 170 条，`_is_open_water` 加了 6m 网格索引，航路检查不受影响（surface 20 条航路仍全通过）。

## 3. 验证

`python scripts/run_verification.py visual-blockers surface selftest click management camera`

| 检查 | 结果 |
|---|---|
| visual-blockers | PASS exit=0，五个区块 空阻挡 0，漏阻挡 zone1 0.2% / zone2 3.5% / zone3 1.2% / zone4 12.9% / zone5 0% |
| surface | PASS exit=0（20 条航路，463 项） |
| selftest | 535 passed, 2 failed（与改动前同一组） |
| click / management / camera | PASS exit=0 |
| visual-sea-style | PASS exit=0 |

`zone1_home_dock` 甲板覆盖 0.03 → 0.81，`zone1_salvage` 0.00 → 0.85（剩余差值来自矩形边缘与甲板上的家具）。

既有失败（本轮之前就存在，未改动）：
- `背包页有格子容器`（UI）；
- `zone1 每张面都有共享材质 18/24 缺材质`（太阳能木屋 v007 遗留）。

## 4. 已知残留

- zone4 远海街町漏阻挡 12.9%：4 个 unit 拼接的废墟群，AABB 内侧边缘 0.1~0.5m 存在接缝。栅格 0.4m 精度不足以覆盖，需要该区块重做时按组件拆分。
- zone2/zone3 的 `WalkAreas` 仍是旧手工矩形（甲板覆盖 0.72 / 0.36），本轮只整理海上场景，未动。
- `assets/baked/shore.json` 保留为离线兜底，不再参与正式运行；已在文件头与生成脚本标注。

## 5. 相关文件

- 新增：`godot/src/world/blocker_set.gd`、`godot/tools/probe_blockers.gd`、`godot/tools/probe_deck_map.gd`、`godot/tools/verify_blockers.gd`、`godot/assets/baked/shore_environment.json`
- 修改：`godot/src/world/zone_scene.gd`、`godot/src/world/sunny_bloom_visual.gd`、`godot/src/bootstrap/main.gd`、`godot/scenes/zones/zone1_home_harbor.tscn`、`godot/scenes/zones/zone5_aqua_platform.tscn`、`godot/assets/data/zones.json`、`godot/assets/data/trade_board.json`、`scripts/run_verification.py`
- 工具：`godot/tools/place_trade_board.py`（重跑）
