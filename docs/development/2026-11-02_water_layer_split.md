# 水上与水下：把描述性说法变成可判定的水层

> 这是五值装配字段迁移的历史记录。现行建筑职责只有水上功能／水下观赏两类，见[最新规范](../standards/水层分类与空间职责.md)及[本轮整理](2026-11-02_building_two_class_contract.md)；旧专项绿项不代表新契约完整验收。

[SEA-ASSET-R40](../features/asset/spec.md) · [SEA-WORLD-R16](../features/world/spec.md) · [规范](../standards/水层分类与空间职责.md)

## 问题

「水上设施」和「水下景观」此前只是文档里的说法，没有任何字段能判定：

| 当时有什么 | 当时缺什么 |
|---|---|
| `classification.subcategory = underwater_buildings` 能认出六栋水下建筑 | 水上没有任何对应值，只能靠"不是水下"反推 |
| 浮店带 `placement_layer: above_water` | 只有一个值，且**全仓没有任何代码读它** —— 写它的只有两个浮店专用注册脚本 |
| `Blockers.mode` / `blocks_water` 能看出谁挡船 | 没有一条规则说"水下不许挡、水上必须挡" |

后果是义务靠人记：水下六栋的"零碰撞零阻挡"由 `test_submerged_neighborhood.gd` 里一个写死六栋名字的 `const KEYS` 守着。主场景后来扩到八栋实例（`flat_annex2`、`rear_slab2`），名字表不会跟着变 —— 新加的两栋既不受管，`child_count() == 6` 反而变红。实测该专项当时挂 12 项。

## 判据

> **水上的东西占空间 —— 有人能站上去，船必须绕开。水下的东西只占像素 —— 不许挡路，不许有功能。**

## 做法

### 1. 账本字段

`assets/registry/ledgers/scenes.json` 567 行全部登记：

| `water_layer` | 行数 | 含义 |
|---|---|---|
| `surface` | 15 entity / 205 part | 整体在水面以上，参与玩法 |
| `amphibious` | 9 entity / 110 part | 跨水线（上段可走、下段沉水） |
| `submerged` | 8 entity / 23 part | 整体在水下，纯景观 |
| `backdrop` | 82 entity / 43 part | 远景烘焙，不挡船不参与玩法 |
| `none` | 72 | 植物、摆件、装饰生物、船件、色板 |

取值**不在账本里手填**，由 `tools/apply_water_layer.py` 的家族前缀表决定。跑一次 `python tools/apply_water_layer.py` 全量重写，幂等；家族没入表就报错，新增资产因此必须先登记水层。

顺带清掉了 `placement_layer`（52 行）—— 它的语义被 `water_layer: amphibious` 完整覆盖。

### 2. 场景节点声明

账本写着不算数，场景里的节点也得能自证。`scene_component.gd`、`zone_scene.gd`、`fishery_visual.gd` 各加两个导出属性；没有脚本的根节点（远景 `environment.tscn`）用 `metadata/water_layer`。45 个场景根节点由 `tools/apply_water_layer_scenes.py` 写入，运行时检查读属性或 metadata 任一。

### 3. 两个门禁

| 门禁 | 位置 | 抓什么 |
|---|---|---|
| `check_feature_contracts.py` | 结构检查 | 字段存在性、`none` 与 `none` 对齐、旧 `placement_layer` 复活、**账本值与家族表不一致**（手改账本会被抓） |
| `water-layer` 专项 | `godot/tests/test_water_layer.gd` | 在 `main.tscn` 上按节点声明实测义务 |

### 4. 义务怎么判

| 层 | 必须有 | 必须没有 |
|---|---|---|
| `surface` / `amphibious` | 活动区域（自身或所在区块的 `walk_areas`、`LandingPoint`）+ 影响航线的水面占用 | — |
| `submerged` | 整体包围盒顶面低于水面 0.25 m | 阻挡、`CollisionObject3D`、`interactable` |
| `backdrop` | — | 阻挡、物理 |

「水面占用」有两条合法出口：`BlockerSet`（`mode != none` 且 `blocks_water`）或自身实现 `water_shapes()`。渔场走后者 —— 围网在不在取决于 `upgraded`，写死一个 `BlockerSet` 会让未升级的平台凭空挡一片水。

`part` 不承担义务：种植土格按 `SEA-BUILDING-R16` 就是"能踩、不挡船"，行走面与阻挡都由宿主区块派生。要求每个构件自带 `BlockerSet` 会得到几十份互相重叠的假阻挡。

## 结果

```
[water-layer] 104 checks, 0 failures; {"amphibious":8,"backdrop":1,"submerged":8,"surface":0}
```

8 个 `amphibious` 实体（zone1–5、阳光房、浮店、渔场）各有活动区域与水面占用；8 个水下实例（六栋 + 两栋复制）零碰撞零阻挡零交互且整体低于水面；远景 1 处不挡船。

同时退役了水下专项里两条过时断言：写死的六栋数量改成逐个子节点核分类；`scale == ONE` 删掉（实例本来就带手工缩放与旋转做疏密），换成交叠体积占比 < 60% 来判穿模 —— 轴对齐包围盒在旋转下天然互相压住，纯相交判定会把"斜着相邻"误报成"穿模"。

## 本轮同时发现的既有问题（未修，需决定）

1. **浮店整体沉在水下 16.7 米。** `main.tscn` 里它的 transform 是 `Transform3D(-0.208,0,-1.757, -0.139,2.405,0.027, 1.364,0.246,-0.265, 69.91,-18.10,46.38)` —— Y 轴缩放 2.4、带旋转、位置 y=-18.1。`floating-shop` 5 项、`sea-supply` 8 项因此红（`deck top is 0.26m above water (got -15.584)`）。已确认 HEAD 里就是这个值，不是本轮改的。
2. **两栋复制的水下建筑原来共用 `instance_id`**（`flat_annex2` 与 `flat_annex` 都是 `home_submerged/flat_annex`）。同一 AssetID 摆多次合法，实例 ID 撞车不合法 —— 已改为 `_2` 后缀，`decorations` 的 2 项红消失。
3. **鱼群总数 10 → 12 未同步**：渔场接入后 zone1 的 `FisherySchools` 多了 West/East 两群，断言仍写 10。已按实际构成改为 12 并注明来源。
4. **水下布局两条位置断言仍红**（"背景楼退在阳光房之后"、"前景屋顶高度错落"）。这两条是美术布局判断，涉及坐标，不在本轮范围。

## 检查点

```bash
python tools/apply_water_layer.py --dry-run     # 账本取值与家族表的差量
python tools/apply_water_layer_scenes.py        # 场景根节点声明（幂等）
python scripts/check_feature_contracts.py       # 结构 + 账本一致性
python scripts/run_verification.py water-layer  # 运行时义务
```
