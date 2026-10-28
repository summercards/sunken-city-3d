# 2026-10-29 作物独立化与四阶段正式资产

功能：SEA-CROP（新建）· 关联 SEA-FARM / SEA-ASSET · 主文档 [功能表](../../GDD_V1.0.md#sea-crop)

## 起因

三作物此前只有数值：`godot/assets/data/crops.json` 管三个 id，形态写死在 `godot/src/farming/farm_plot.gd::_build_plant()` 里——茎是 `CylinderMesh`、叶是 `BoxMesh`、果是 `SphereMesh`，三种作物**共用同一套几何**，只靠 `crops.json` 的 `color` 给果实换色。资产账本只有一条 `SEA-FARM-SOIL-CELL`（木框培养土），作物本身没有 AssetID、没有制作源、没有独立验收。

结论：看起来是三种作物，实际是同一株模型换颜色。这不是"没做完"，是**规格里就没有这一层**。

## 本轮做了什么

| 层 | 变化 |
|---|---|
| 功能 | 新建 SEA-CROP「作物品种与四阶段形态」，主文档功能表新增一行；SEA-FARM 前置加 SEA-CROP |
| 文档 | 新建 `docs/features/crop/spec.md`（R01–R10）与 `ledger.md`；SEA-FARM 加 R11 划清「木箱 vs 作物」；SEA-ASSET 加 R30 建立 crops 资产域 |
| 代码 | 新建 `godot/src/crops/`：`crop_stage.gd`（四阶段常量与映射）、`crop_catalog.gd`（品种目录）、`crop_view.gd`（表现装配）。`farm_plot.gd` 删掉全部作物几何（约 110 行），只留木箱 + CropView 容器；`farm.gd` 改由 CropCatalog 取定义 |
| 美术 | `tools/blender/crops/build.py` 一次生成 3 品种 × 4 阶段；制作源 `art_source/crops/<id>/v001/*.blend`；导出 12 个 GLB 到 `godot/assets/models/crops/<id>/`；装配 3 个场景 `godot/scenes/crops/<id>.tscn` |
| 账本 | 新建 `assets/registry/ledgers/crops.json`，3 条主记录；`ledger_index.json` 增 crops 域；12 个 GLB 进运行清单；`content_index.json` 的 crops.json 所有权转 SEA-CROP |

## 四阶段定义

`grow_days=3` 时，`progress = 1 - remaining/total`：

| 剩余天 | progress | 阶段 | 节点 | 生菜 | 番茄 | 南瓜 |
|---|---|---|---|---|---|---|
| 3 | 0.000 | seed 种子 | `Stage0Seed` | 三撮翻土 + 种子粒 | 同 | 同（奶白扁平种） |
| 2 | 0.333 | sprout 发芽 | `Stage1Sprout` | 两片子叶破土 | 细幼茎 + 子叶 | 圆钝子叶贴地 |
| 1 | 0.667 | leaf 二次发芽 | `Stage2Leaf` | 六片本叶放射 | 直立主茎分层复叶 | 匍匐藤蔓 + 四片大叶 |
| 0 | 1.000 | harvest 收成 | `Stage3Harvest` | 外叶莲座 + 菜心 | 主茎 + 两颗红果 | 藤叶 + 沟槽橙南瓜 |

映射公式在 `CropStage.stage_for_progress`：`ready → 3`；`p ≤ 0.001 → 0`；`p < 0.5 → 1`；否则 `2`。地格视图只转交，不自己算阈值。

`leaf` 阶段三品种轮廓已可分辨：番茄最高（直立主茎约 0.34 m）、生菜居中（贴地约 0.16 m）、南瓜最矮（匍匐约 0.08 m）。这一条由 `crops` 测试的高度比较断言盯着。

## 面数与预算

每品种每阶段整格（3 株）三角面，预算 900：

| 品种 | seed | sprout | leaf | harvest |
|---|---|---|---|---|
| 生菜 | 360 | 336 | 576 | 624 |
| 番茄 | 360 | 420 | 636 | 732 |
| 南瓜 | 360 | 336 | 576 | 780 |

首轮构建超预算 4 项（生菜收成 960、番茄 leaf 924、番茄收成 1500、南瓜收成 1140），降细分与果数后全部落入预算，未抬预算凑数据。

美术规范沿用 SEA-ASSET-R05/R06：外链唯一 `sea_cozy_8x8_512` 色板，逐面 PaletteUV 落格并留单格安全区，花叶用平滑曲面无硬边。GLB 内嵌该色板 PNG，不依赖外部贴图。

## 验证

| 项 | 命令 | 结果 |
|---|---|---|
| 作物专项 | `python3 scripts/run_verification.py crops` | exit 0，`[crops] 60 checks, 0 failed` |
| 作物真实渲染 | `python3 scripts/run_verification.py visual-crops` | exit 0，12 阶段 + 正/俯视图 |
| 种植回归 | `python3 scripts/run_verification.py farming` | exit 0 |
| 地格视觉回归 | `python3 scripts/run_verification.py visual-plot-shipping` | exit 0，`[plot-shipping] 0 failures` |
| 模块隔离 | `python3 scripts/run_verification.py modules` | exit 0 |
| 契约与结构 | `python3 scripts/check_feature_contracts.py` | PASS：35 features / 459 source assets / 0 issues |

`crops` 是不加载 `main.tscn`、不依赖 Economy 的隔离测试，本身就是 SEA-CROP-R05「品种与表现可单独运行」的证据。

调试过程中修掉的两个真问题（记录下来，避免下次重犯）：

1. `CropView._apply_tint` 在非缺水时也写了 `material_override`，导致「解除缺水」永远恢复不到资产材质。改为非缺水直接置 `null`。
2. 测试的模型根节点按「第一个加载的品种」取，切到第二个品种后仍在读第一个模型的阶段节点，误报「阶段切换失败」。改为按可见性取根。

## 真实渲染证据

`godot/tools/capture_crops.gd` 建独立舞台（不加载 `main.tscn`），三品种 × 四阶段全部实例化，
每格只让目标阶段可见，出两张图：

- [正视图](../development/evidence/2026-10-29_crop/crops_stage_grid.png)：三列（生菜 / 番茄 / 南瓜），四行（种子 / 发芽 / 二次发芽 / 收成）
- [俯视图](../development/evidence/2026-10-29_crop/crops_stage_ortho.png)：验证三株是水平三角分布，不是叠成一条线

抓图环境必须与游戏一致，否则颜色评审是假的：环境光取 `world_env.tres` 的 `0.36`、`tonemap_mode = 3`（ACES）、`exposure 1.17`。第一版抓图用了 FILMIC + 环境光 0.9，色板被洗成一片浅绿，看着像资产配色错，实际是舞台错。

## 三个必须记住的坑（都花了返工）

1. **Blender 是 Z-up。** `Vector(x, y, z)` 的第三分量是高度，不是深度。我把簇的深度写进 z，三株被叠成上下三层，俯视只剩一条窄带。深度必须写 y。
2. **绕 Y 旋转是竖直翻滚，不是水平铺叶。** 叶子要绕 Z 轴（Blender 上轴）旋转才能向四周展开。第一版所有叶都压在 X 轴一条线上，整棵读作"三颗小球"。
3. **别手删 GLB 的旁挂 `.import` 和抽出的 PNG。** Godot 从 GLB 内嵌贴图抽出 `<glb名>_<色板名>.png` 是导入产物的组成部分，删掉会中断导入，后续表现成"节点 vanished / 阶段节点缺失"这种完全不指向根因的报错。要重导就在主工程跑 `godot --headless --path godot --import`，不要在验证运行中途删文件。

另外，`crops` 测试里取模型根节点必须按**可见性**取：CropView 缓存已加载品种，只有当前品种 visible，按"第一个有阶段节点的孩子"取会一直读到第一个品种。

## 未执行与保留

- **源级「保存后重开 + 四视图渲染」未执行。** 资产阶段只到 `runtime_component_verified`，不写成已验收。
- 缺水目前统一压黄，没有按品种做枯萎形态；要分品种先加条款。
- 品种扩展、季节性耐性、品质分级、工具对形态的影响仍为规划，未因本轮拆分自动升级。
- SEA-CROP 整体状态记 `implemented`（已实现待完整验收），不记 `verified`。

## 五处同步清单（新增作物必查）

`crops.json` 一行 → `art_source/crops/<id>/v001` 制作源 → `godot/scenes/crops/<id>.tscn` → `ledgers/crops.json` 一行 → `runtime_resource_inventory.json` 四条 GLB。缺任一处，`crops` 与 `structure` 会失败。
