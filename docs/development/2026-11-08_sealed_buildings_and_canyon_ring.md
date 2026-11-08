# 水下建筑封闭与回字型深沟高楼环（2026-11-08）

[主文档](../../GDD_V1.0.md#sea-asset) · [资产规范](../features/asset/spec.md) · [资产账本](../features/asset/ledger.md) · [潜水规范](../features/dive/spec.md) · [潜水账本](../features/dive/ledger.md)

## 1. 用户原始要求

1. 保留海上的水下景观组件布局，但组件要改：**破碎可以，楼房必须封闭，不可以有空间进入楼房**，这是对原始文件的修改。
2. 重新导入原始文件替换组件，但**不要调整已经调好的阳光家园海底地图的组件放大和位置布局**。
3. 从设计上放大建筑组件，把海底场景做成**回字型的深沟地形**，两边由楼房组成，所以要用**原来高的楼房（v003）**做组件；把这些高层**结构封闭**（保持破损但不让玩家走进去），做成组件，**以 2 倍大**带进现有水下场景替换掉部分楼房；层次错落要自然，摆好后**由用户手工调整**，先在现有区域**外圈围一圈高的楼房**。

用户在两处选项上明确选择：放大基准 = **严格 2× v003 原生**；封闭范围 = **两套都封**（v005 限高版 + v003 高楼版）。

## 2. 先量清楚的三个数

| 项目 | 数值 | 说明 |
|---|---|---|
| 水面 Y（world） | 51.12 | 11-08 抬升 50 米后的当前水面 |
| 街面 Y（world） | −17.81 | 城市根 43.487442 + 局部 −61.3 |
| 街面上方水柱 | **68.93 m** | 决定楼顶能不能露头 |
| v003 最高楼 | 59.659 m（`slender_tower`） | 未限高原生几何 |
| v005 最高楼 | 13.759 m | 用户此前授权「最高楼 ×0.25」限高版，游戏里现在跑的就是它 |

**2× 的后果必须先说清**：`59.659 × 2 = 119.32 m`，从街面算起比 68.93 m 的水柱高出 50 m。
用户看过这个数字后仍选择「严格 2×」，因此环上楼顶会露出海面 49.8 米，形成「海面上一圈残楼塔尖、海下一道深沟」的同一个造型。这不是缺陷，是本次明确的取舍。

## 3. 封闭怎么做的

### 3.1 判据

组件原本是**空壳**：门口、破窗、缺楼板处能直接游进楼体内部。封闭目标是把壳补成**水密流形**：
每条边界边都被两张面共享（`boundary_edges = 0`），且无三面共边（`nonmanifold_edges = 0`）。
水密闭合曲面在几何上不可能被穿过，因此「玩家进不去」不是靠碰撞挡，而是壳本身没有入口。

### 3.2 算法（`tools/blender/sunken_city/seal_components.py`）

1. 找出所有边界边，按顶点度数串成边界环（度 ≠ 2 的顶点作为断点，避免多条环交汇处串错）。
2. 每个环算平面投影面积，**跳过真正的单面薄板**：判据是「某张相邻面的边集合 == 这条环的边集合」。
   这类环是招牌、玻璃、碎屑片自己的轮廓，补起来只是给薄板加背面，白涨面且没有遮挡意义。
   - 早期用过「面积比较」和「重心投影」两种判据，都会误杀真实窗洞（把整面墙当薄板），已废弃。
3. 其余环建扇形封盖：环上每两个相邻顶点与一个内凹顶点成三角面。
   内凹顶点沿环平均法线向内收 `min(0.35, 0.12 + 0.25×跨度)` 米，**并做内外方向校验**：
   ±法线各试一次，用射线奇偶判定取真正在实体内部的那一侧，且必须仍在原包围盒内。
   - 这一步是必要的：早期版本把顶点推到外侧，把 `canal_housing`／`cinema_ruin`／`roof_garden_shell`
     的包围盒撑大了 0.14 米，等于偷偷改了组件占地。
4. 封盖面的材质槽与 PaletteUV 格沿用相邻面，不新增材质、不新增贴图。

### 3.3 两套结果

| 套件 | 源 | 输出 | 组件 | 处理前 | 处理后 |
|---|---|---|---|---|---|
| 限高版（游戏在用） | `art_source/scenes/sunken_city/v005` | `v006` | 20 栋 | 472,876 面 | 478,425 面 |
| 高楼版（回字型用） | `art_source/scenes/sunken_city/v003` | `v008` | 20 栋 | 1,047,714 面 | 1,062,070 面 |

- **17 栋**处理后 `boundary_edges = 0` 且 `nonmanifold_edges = 0`（完全水密）。
- `frame_construction` 处理前就是水密（0 → 0）。
- `collapsed_residence`、`fallen_hall` 是**废墟块堆**（分别 34,296 / 30,043 条边界环，13 万+ 条边界边），
  补面会让面数翻 5 倍而毫无意义；这两栋判定为「本来就进不去」（玩家检具全方向阻挡）。
  按「不是可进入楼房」保留原状，不假装它们已封闭。
- 材质槽数量、名称，以及顶点包围盒三个轴都逐栋比对一致，**没有移动任何原有几何**。

### 3.4 替换方式

- 限高版：`v006` 的 GLB **原地覆盖**原运行时路径 `godot/assets/models/scenery/sunken_city/<slug>/<slug>.glb`，
  `.import` 不动，50 个组件包装场景不动，实例变换不动。旧 GLB 备份与哈希留在
  `sea-work/sunken_seal_20261108/backup_glb/`。
- 高楼版：新目录 `godot/assets/models/scenery/sunken_city_tall/`，
  新包装 `godot/scenes/components/scenery/sunken_city_tall/<slug>.tscn`（带 `metadata/sealed_interior = true`，
  `asset_version = v008`）。v003 的源与 v003 的运行时导出**完全不碰**。

## 4. 回字型深沟的摆法

脚本：`tools/godot/place_tall_ring.py`（确定性，可重跑，结果幂等）。

**用户否定了第一版圆环，要求「不要环形，沿着边缘直着摆放」。** 回字型的「口」本来就该是方框：

| 参数 | 值 |
|---|---|
| 外框半宽 | 112 m，每边 **7 个**，间距 37.33 m（含角，共 24 个） |
| 内框半宽 | 72 m，每边 **5 个**，间距 36.00 m（含角，共 16 个） |
| 合计 | **40 栋** |
| 沟宽 | 40 m |
| 共线 | 每条边上的楼 X 或 Z **完全相同**，严格直线 |
| 朝向 | 只有 0°/90°/180°/270°，一律朝框内，**不加抖动** |
| 尺度 | 2.0（严格 2× v003 原生） |
| 楼基 Y | 取最近地面组件顶面 |
| 既有实例 | **一栋不删** |

### 为什么从圆环改成方框

第一版用极坐标撒点（外圈 r=112／内圈 r=74），楼的朝向随角度连续变化，读起来是一圈塔。
方框才符合「回字」的语义：四面楼墙 + 四个直角，中间一条矩形深沟。

### 间距是被几何倒推出来的，不是拍的

2× 之后楼的平面宽度是 **28–43 m**，第一版按 32 m 间距排，相邻楼体最多互相插入 **5.8 m**。
按「每边固定数量」反算间距、并把宽楼与窄楼交替排列后：

| 圈 | 每边 | 间距 | 行内最大重叠 |
|---|---|---|---|
| 外框 | 7 | 37.33 m | −3.7 m（有缝） |
| 内框 | 5 | 36.00 m | **+0.83 m** |

全场景最大重叠 **0.83 m**，在废墟墙体上读作咬合，不再是大方块互插。

### 地面支撑核对

地面块 24 m 见方。外框边缘离最近块心最远 **12.6 m**、内框最远 **17.0 m**，
都小于块的半对角线 17.0 m，因此 40 个槽位全部落在真实街面上（`ground_ok 40/40`）。
三个台面高度 −61.9 / −66.7 / −68.1 m 按最近块自动取值，楼脚不悬空、不埋地。

### 高度节奏

沿直线按「高峰 → 低 → 中 → 低 → 高峰」轮换。外框 X=+112 那排的楼顶：
6.4 / 47.2 / 5.8 / 16.6 / 57.4 m —— 锯齿天际线，不是等高墙。
内框整体退一档，从沟底看是「内低外高」两层楼墙。

### 楼顶露出水面

范围 **−22.3 m 至 +49.8 m**（最高为 `slender_tower` ×2 = 119.32 m）。
全部 40 个位置的参考坐标、组件、朝向、露出水面高度逐条记在
`docs/features/world/canyon_ring_reference.md` 与 `sea-work/sunken_seal_20261108/ring_plan.json`。

**这些是参考位，不是验收标准。** 用户手工摆完以编辑器里的 transform 为准（AGENTS 第 12 条）。

## 5. 验收

### 5.1 Blender 源级

`tools/blender/sunken_city/audit_seal.py` 独立重开逐栋量测，两套都 `passed=True problems=0`：

- 面数只增不减（补面），包围盒三轴不变，材质槽不变；
- GLB 三角面数 == 网格三角面数，无内嵌贴图；
- 记录源/封闭 blend 与 GLB 的 SHA-256。
- 报告：`art_source/scenes/sunken_city/v006/seal_report.json`、`v008/seal_report.json`。

### 5.2 Godot 运行

| 检查 | 结果 |
|---|---|
| `sunken-city` | **PASS**，33928 项 0 失败（`20261108-182329-scity-sealed4-f10c7b`） |
| `water-layer` | **PASS**，1613 项 0 失败 |
| `sunroom-underwater` | 83 项，1 失败：生态接地最大漂移 2.4160 m |

那 1 项是**改动前就存在**的：把布局回滚到本次改动之前的快照再跑，同样报 2.4160 m
（`20261108-181727-preexisting-drift-63cb5e`）。根因是用户手工挪过 39 个实例，珊瑚与设施灯的
序列化 Y 值还停在旧支撑面上。本轮没有动它们，也没有把它说成通过。
（第一版「删 13 栋」的方案会把这个漂移放大到 13.439 m，已废弃。）

### 5.3 未做 / 仍 pending

- **美术终审**：40 栋沟壁的层高、朝向、间距只是参考位，等用户手摆。
- **性能**：新增 40 栋合计 6.42M 三角面，整城量级由 2.46M 升到约 8.9M，
  且 `sunroom_region_collision.gd` 对每栋建精确凹面碰撞体，这是本轮最大的运行风险，未做 LOD。
- **参考图商业权属**：仍为 pending，沿用既有登记口径。
- 未改 `main.tscn`，海面旧城仍是**限高+封闭**的 v006；回字型只在「家园海底」这套布局里。

## 6. 改了哪些文件

| 类型 | 路径 |
|---|---|
| 新增工具 | `tools/blender/sunken_city/seal_components.py`、`audit_seal.py`、`verify_traversable.py`、`diag_loops.py`、`diag_leak.py`、`render_probe.py`、`run_seal_all.py` |
| 新增工具 | `tools/godot/place_tall_ring.py`、`tools/register_sealed_sunken.py` |
| 新增源 | `art_source/scenes/sunken_city/v006/`（20 个封闭组件包 + seal_report.json） |
| 新增源 | `art_source/scenes/sunken_city/v008/`（20 个封闭高楼组件包 + seal_report.json） |
| 覆盖运行时 | `godot/assets/models/scenery/sunken_city/<20 个 slug>/<slug>.glb` |
| 新增运行时 | `godot/assets/models/scenery/sunken_city_tall/`（20 个 GLB） |
| 新增场景 | `godot/scenes/components/scenery/sunken_city_tall/*.tscn`（20 个包装） |
| 修改场景 | `godot/scenes/underwater/sunroom_region/sunken_city_layout.tscn`（+40 个高楼节点、+14 条 ext_resource，不删任何原有节点） |
| 修改测试 | `godot/tests/test_sunroom_underwater_region.gd`（节点名对齐 SolarCabinBase2；383 + 40 = 423；记录 39 处手摆与 5 处既有缺口） |
| 修改测试 | `godot/tests/test_sunken_city.gd`（RUNTIME_VERSION v005 → v006，与封闭版清单一致） |
| 修改清单 | `godot/assets/models/scenery/sunken_city/runtime_manifest.json`（20 栋面数与哈希、版本 v006） |
| 修改脚本 | `godot/src/diving/sunroom_region.gd`（沟壁 `tall_*` 不参与生态接地） |
| 修改账本 | `assets/registry/ledgers/scenes.json`（20 条改 v006、20 条新增 sunken_city_tall） |
| 修改清单 | `assets/registry/runtime_resource_inventory.json`（只刷新本轮 84 个资源，其它 drift 不掩盖） |
| 修改视图 | `assets/registry/views/buildings_underwater.json`（`tools/apply_water_layer.py` 重生成） |
| 新增清单 | `art_source/scenes/sunken_city/v008/component_packages/*/asset_manifest.json`（20 份，带 asset_ledger 回链） |
| 版本口径 | `runtime_manifest.json` 与 50 个包装场景的 `asset_version` 统一 v005 → v006，`test_sunken_city.gd` 的 `RUNTIME_VERSION` 同步 |

## 7. 实测记录

### 7.1 Blender 源级

```
blender -b --python tools/blender/sunken_city/audit_seal.py -- \
    --version v005 --sealed v006 --runtime godot/assets/models/scenery/sunken_city
blender -b --python tools/blender/sunken_city/audit_seal.py -- \
    --version v003 --sealed v008 --runtime godot/assets/models/scenery/sunken_city_tall
```

两套均 `AUDIT_COMPLETE passed=True problems=0`。

### 7.2 Godot

```
python3 scripts/run_verification.py --label scity-sealed4 --timeout 420 sunken-city
python3 scripts/run_verification.py --label final-both --timeout 420 sunroom-underwater water-layer
```

- `sunken-city` PASS exit=0，33928 项 0 失败。
- `water-layer` PASS，1613 项 0 失败（同上批次）。
- `sunroom-underwater` 83 项 1 失败（上述既有漂移）。

### 7.3 账本与台账

- `python3 scripts/check_placed_positions.py` → PASS，3 个结构 0 警告（本轮没动 main.tscn）。
- `python3 scripts/check_feature_contracts.py` → 123 项失败，全部为其他并行会话改动的文件哈希漂移
  与派生索引过期，**逐条核对过：没有一条提到本轮新增的 `sunken_city_tall`、`v006`、`v008` 或
  `sunken_city_layout` 之外的组件**。未做 `--sync` 之外的批量刷新。

### 7.4 仍然 pending

- 40 栋沟壁的层高/朝向/间距是参考位，等用户手摆后按实际值更新。
- 三角面预算：新增 40 栋 6.42M 面，整城由约 2.46M 升到约 8.9M，未做 LOD。
  实测该检查轮次（含精确凹面碰撞体构建）总耗时约 20 秒，未见超时或崩溃，但帧率与显存未测。
- 参考图商业权属仍为 pending。

