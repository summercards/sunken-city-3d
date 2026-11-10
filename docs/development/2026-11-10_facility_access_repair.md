# 2026-11-10 设施可达性与泊位校准

起因两条：① 主人报「在海上航行被阻挡，提示前方是岸」；② 要求对当前全部设施做一次可行走面、上岸点、建筑阻挡的体检，并按结果修复。

体检工具已入库：`scripts/audit_facility_access.py` + `godot/tools/audit_facility_access.gd`，在隔离工程副本里加载真实 `main.tscn`，逐格比对可见几何、`WalkArea`、`LandingPoint`、`BlockerSet`，输出 JSON 与俯视叠加图。

## 一、海上「前方是岸」：7 条过期烘焙岸线

`godot/assets/baked/shore_environment.json` 里 7 条矩形（沉没塔 A–E、圆弧玻璃大厦、阳台住宅）是按「旧城仍露出水面」烘焙的。沉没旧城接入主场景后整城最高点 `y = -1.64`，水面 `y = 1.12` —— 旧城在水下 2.76 m，388 个实例没有一块碰水线，7 条矩形在水面上支撑为 0，成为隐形墙。时间线：该文件最后提交 2026-10-27，沉没旧城 v004 是 11-05 接入的，城沉了、岸线没重烘。

处理：7 条全部退役，`shapes` 置空并写明退役原因。旧城阻挡改由 `World/SunkenCity` 组件自身的 `BlockerSet` 按可见几何派生 —— 水面之上没有三角形，自然放行。

防回归：`tools/verify_blockers.gd` 增加 baked 校验，逐条用「环境场景自己派生的水面阻挡」算覆盖率，低于 `MIN_SUPPORT = 0.35` 判 FAIL。反证：把 7 条装回去后 7/7 支撑 `0.00`、检查 FAIL（`sea-work/verification/20261110-160623-baked-negative-test-a77ba3`）；退役后 `shapes=0` 时 PASS。

## 二、走域比甲板小

| 位置 | 体检发现 | 处理 |
|---|---|---|
| 家园 zone1 码头 | 东侧 `x=9.5..11.4` 有 1.38 m 甲板，走域只到 9.5 | `Walk_zone1_home_dock` 第二块矩形宽 5 → 6.9（x 到 11.4）。走域 77.5 → 84.5 m²，仍单岛连通，悬空 1.1% |
| 霓虹花园菜园桥 | 走域 47.5 m² 碎成 15 块、14 块不可达，47.9% 悬空 | 桥上 106 个作物/藤架件（herb/cabbage/tomato/trellis/vine/flowers）标 `metadata/visual_only = true`；派生不再把它们当遮挡。走道 67.4 m²、8 块、悬空 3.9%，主岛占 86% |
| 霓虹花园街口 | 19 m² 走域 100% 落在开阔水面（整街区沉到 −15.87） | `WalkStreetLanding` 置 `active = false`（保留节点，回退重建街区时改回即可） |

## 三、泊位锚点

| 泊位 | 改前 | 改后 |
|---|---|---|
| zone1 绞盘打捞台 | `park` 距阻挡 0.40 m，落在船体 0.9 m 缓冲内（每次靠岸都可能「无法到达」） | 沿离岸方向外移 1.1 m，gap 1.64 m，`park_in_blocker` / `park_too_close` 全部消失 |
| zone5 浅水养殖台 | `park` 距甲板 1.27 m（船贴着平台） | 外移 0.35 m，gap 1.61 m |

回归：`dock-hotspot` 首跑 1 处失败——测试取样半径从 1.6 m 起，正好压在 `DOCK_SETTLE_TOLERANCE = 1.6` 的「已靠妥」边界上，泊位挪远后船不漂就恒判失败。把取样半径提到 1.7 m（容差之外），`dock-hotspot` 恢复 PASS。`dock-seed` 同批 PASS。

## 四、体检工具本身的三个口径错误（顺手修正）

1. **`flat_y` 平面假设**：band 模式的坡面桥铺满整条站立带，用 `surface_y±0.35` 找几何会把低半段整片滤掉，菜园桥因此被判 100% 悬空。改为按走域自己声明的 `span_min..span_max` 收面，band 模式不做平面过滤。
2. **五个区块共用一个物理空间**：`verify_blockers` 原来一次加载 5 个 zone 再逐条打射线，射线会命中隔壁区块的几何（zone2 的导航地面 `GroundFloor` 把 zone4 的采样点全判成有实体）。改为逐区块独立检查，只给 `Models` 子树建物理体。
3. **漏阻挡射线起点**：原来从船顶之上 0.6 m 起打，会把架空屋顶（zone4 实测 2.78 m，船顶 2.72 m）算成该有阻挡的地方。

## 未做

- **zone2 横滨铁道 4 个走域岛互不连通**：岛之间是水面加水下废墟（实测 `y = 0.52..0.96`），站台本身断开，不是走域数据漏盖。要连通需加木桥/舷梯几何，属玩法改动，未擅自添加。
- **霓虹花园泊位落差 14.08 m**：屋顶在世界 15.2 m、船在 1.12 m，是「直接上岸到屋顶」的既有偏离（SEA-MOVE-R10），补梯子或升降机未做。
- **`visual-blockers` 的 zone4 漏阻挡 29%**：zone4 已从主场景移除（SEA-WORLD-R08），玩家不可达。根因是 `BlockerSet` 对悬挑屋顶的 XZ 投影退化（竖直/薄面不生成阻挡），修它要改核心派生逻辑并重跑全部靠泊与航行验证，留给独立一轮。
- **5 处落点贴甲板边沿**（`stand_clearance` 0.00–0.36 m < 角色半径 0.38）：落点确实落在甲板面上（`drop` 0.21–1.48 m 正常），只是贴外沿；移动 `Landing` 会连带 `BoatPark`，回归面大，本轮不动。
- 契约检查的 runtime hash 漂移：本轮改动的 5 个文件在漂移清单里，其余为既有漂移（见 asset 账本 2026-11-10 节），按项目惯例不批量刷哈希。

## 证据

- 体检工具与基线：`scripts/audit_facility_access.py`（`python scripts/audit_facility_access.py <label>`）
- 最终体检 JSON：`D:\projects\sea-work\diag\20261110-163315-step4\facility-access-audit.json`
- 阻挡校验：`visual-blockers` 逐区块 OK（zone1 44 / zone2 58 / zone3 40 / zone5 3 条，空阻挡 0），baked `shapes=0` PASS
- 靠泊：`dock-hotspot`、`dock-seed` PASS
- 反证：`D:\projects\sea-work\verification\20261110-160623-baked-negative-test-a77ba3`
