# 2026-10-30 海上悬浮商铺接入正式场景

承接 SEA-ASSET-R35 / SEA-WORLD-R13。用户要求：把 `art_source/scenes/floating_shop/v002` 带进游戏，放进 `main`，归海上，账本等级记为商店，位置在阳光房南面 50 米。

## 一、做了什么

| 层 | 结果 |
|---|---|
| 导出 | `tools/blender/floating_shop/export_runtime.py` 打开 v002 源（**只读，不保存**），把 248 个 Collection Instance 按四个材质角色烘合并成四块网格，倒角在导出前由 depsgraph 求值，写出单一 GLB |
| 运行资源 | `godot/assets/models/facilities/floating_shop/floating_shop.glb`，50 420 360 字节，669 345 三角面，`textures=0 / images=None` |
| 材质 | `godot/assets/materials/floating_shop/{matte,metal,gloss,emission}.tres`，共用 `sea_cozy_8x8_512.png`，**序列化**在预制体上（不靠脚本补色） |
| 预制体 | `godot/scenes/facilities/floating_shop.tscn`，`asset_id=SEA-SCENE-FSH-ASSEMBLY`，`role=shop`，带 `Blockers`（`mode=auto`） |
| 摆放 | `main.tscn` 新增 `World/SeaStructures`，其下 `floating_shop` 一个实例；坐标为 `(6.158, -1.134, 51.813)` |
| 船体阻挡 | 新增 `godot/src/world/sea_structure.gd`；`main._water_shapes()` 抽出 `_collect_water_shapes()`，区块之后**再收一遍** `World/SeaStructures` |

## 二、位置是怎么算的

「阳光房南面 50 米」不能拿场景原点当基准 —— 阳光房根节点在原点，但主体几何偏在 `x≈6.16 / z≈1.81`（后部方形建筑 + 前部倾斜太阳能房合并包络 `(-0.94,-0.77,-3.76) ~ (13.26,10.38,7.39)`）。用它的**占地中心**当基准，向南（Godot +Z）推 50 米：

- 落点 = `(6.158, 51.813)`
- 验证断言：`|dx| ≤ 0.6`、`|dz − 50| ≤ 0.6`，实测 `dx = 0.00`、`dz = 50.00`

竖向按「浮在水面上」对齐：水面 1.12，家园甲板站立面 1.38，即甲板顶面高出水面 0.26。模型自身甲板顶面在局部 `z=2.514`，所以实例 `y = 1.12 + 0.26 − 2.514 = −1.134`。甲板板底（局部 2.04）落在 `y=0.906`，低于水面 —— 板体、推进器和浮舱在水下，不会悬空。

## 三、踩到的两个坑

**1. 导出器把 .blend 的每个场景都写进 GLB。** 第一次导出（3 分 32 秒）出来的文件里除了四块 `FSH_SEA_*`，还有一个 `Cube`（默认启动场景）和 `展示背景地面`（展示场景的背景板）。它们在 Godot 里就是两块多余几何。修法：导出前把除运行场景外的 scene 全部 remove —— 因为脚本从不保存源文件，这一步碰不到 `.blend`。

**2. 区块外的结构没人扫阻挡。** `ZoneScene.rebuild_blockers()` 只扫自己 `Models` 子树，而 `_water_shapes()` 只遍历 `World/Zones`。浮店放在 `World/SeaStructures` 下，如果没有第二步收集，船会直接从店里穿过去 —— 画面正确、物理全错，属于那种「看一眼没问题、开船才发现」的故障。测试里专门有一条 `boat cannot sail through the shop center` 盯着它。

## 四、账本与门禁

- `scenes.json` 的 `SEA-SCENE-FSH-ASSEMBLY` 行：`stage` 从 `source_verified_runtime_pending` 改为 `source_runtime_verified_provenance_pending`，补 `runtime_path` / `runtime_sha256` / `prefab` / `prefab_sha256` / `triangles` / `classification{category:building, subcategory:shop, level:商店}` / `placement_owner:main` / `runtime_instances` / `footprint` / `height` / `collision` / `interactive:false`。
- `runtime_resource_inventory.json`：新增 GLB、预制体、4 个材质条目，刷新 `godot/src/bootstrap/main.gd` 哈希（该文件在清单里本来就有基线）。
- 功能条款：`SEA-ASSET-R35`（导出与摆放契约）、`SEA-WORLD-R13`（区外结构阻挡收集），spec 与账本同步。
- `assets/registry/SCENE_COMPONENTS.md` 增加「建筑 / 商店（海上结构物）」一行。
- `python -X utf8 scripts/check_feature_contracts.py --sync` 与无参检查：`35 features, 553 source assets, 465 runtime resource hashes; 0 issues`。

## 五、验证

| 检查 | 结果 |
|---|---|
| `floating-shop`（headless，21 项） | exit 0，0 失败：预制体 4 网格、4 条材质覆盖、正南 50 米、甲板高水面 +0.26、板底入水、不压其它区块、中心判为阻挡水域 |
| `visual-floating-shop`（真实渲染） | exit 0，三张 1280×800：`floating-shop-{approach,deck,from-home}.png` |
| `modules` / `island-atlas` / `landing-markers` / `boat-water-contact` / `ocean` / `sail-bounds` | 全部 exit 0 |
| `submerged-neighborhood` | exit 1，12 项失败 —— **与本次无关的既有失败**：把 `main.tscn` 与 `main.gd` revert 到 HEAD 后重跑，同样是这 12 项（`UnderwaterScenery` 下多出的 `flat_annex2` 使子节点数为 7，六栋实例的 transform 里带缩放，`node.scale == ONE` 断言不成立）。按「不改别人的东西」原则未处理，另行记录。 |

渲染证据在 `D:\projects\sea-work\verification\20261030-201851-floating-shop-visual-9525f4\project\outputs\`；导出清单 `art_source/scenes/floating_shop/v002/export/v001/export_manifest.json`。

## 六、明确未做

- **没有行走面、泊位与商店交易界面。** 环廊和甲板现在只是几何：玩家不能靠泊上岸，点它也没有商店气泡。要做就得给浮店加 WalkArea + LandingPoint + 商店交互，那是另一轮（数值、库存、UI 都要接），本轮没有替用户决定。
- 没有为浮店做面数/材质优化削减。669 345 三角面是 v002 源的原样展开，单件独立建筑量级偏大，若同屏还要进更多海上建筑，需要另做低模。
- 没有核验参考图商业授权，也没有取得用户最终美术验收。
- 浮店不在航海图（`island_atlas`）上显示 —— 它只画区块 footprint。
- 海上地图与浮木生成会自动避开它（浮木用 `navigation.is_open_water` 判点），这条是白得的好处，没有改任何生成规则。
