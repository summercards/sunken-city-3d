# SEA-WORLD · 区块与世界装配 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-world) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-WORLD",
  "status": "partial",
  "owner": "Zones / ZoneScene",
  "code_paths": [
    "godot/src/world",
    "godot/src/navigation/ground_space.gd",
    "godot/src/navigation/actor_collision_body.gd",
    "godot/scenes/zones",
    "godot/scenes/world",
    "godot/assets/data/zones.json"
  ],
  "verification": [
    "water-building-002",
    "visual-water-building-002",
    "shop-sightline",
    "visual-shop-sightline",
    "gift-kiosk-interior",
    "visual-gift-kiosk-interior",
    "roof-reveal-component",
    "roof-reveal",
    "visual-roof-reveal",
    "gift-kiosk",
    "visual-gift-kiosk",
    "water-layer",
    "submerged-neighborhood",
    "visual-submerged-neighborhood",
    "selftest",
    "surface",
    "visual-sea-style",
    "visual-blockers",
    "decorations",
    "visual-decorations",
    "minimum-loop",
    "visual-plot-shipping",
    "visual-home-lighting",
    "sea-supply",
    "sea-supply-probe",
    "fishery-environment",
    "visual-fishery-environment",
    "seabed-scene",
    "visual-sunken-seabed",
    "sunken-city"
  ]
}
```

## 2026-11-04 编辑器与游戏对齐：删除「永远不显示」的建筑几何

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 待核验 |
|---|---|---|
| SEA-WORLD-R08 · 11-04 再修订 | 用户把编辑器里打开的 `main.tscn` 与游戏画面对比后指出：编辑器里那片密集城市在游戏内根本不出现。核查确认有两类「存在但永不显示」的建筑几何，已从场景删除：<br>① `World/Environment/StaticBatch` —— 旧网页版城市烘焙，`bake.json` 记 249136 个实例、141 批次，`assets/world/environment/instances.bin` 15.9MB；默认 minimal 范围每次启动被 `main.gd` 的 `_apply_play_scope()` 直接 `hide()`，只有 `--full-world` 才会亮。删除后 `environment.tscn` 只剩 `Animals`，`load_steps` 4→2。<br>② 家园 zone1 的 `Models/detail`、`unit_01`、`unit_02`、`unit_03` —— 四栋旧海面楼体，TSCN 内自带 `visible = false`，连同 4 条 `ext_resource` 一并移除。<br>**保留**：横滨铁道 zone2（用户明确要求显示）、zone1、zone5、浮店、顶层牧场。<br>**保留且不动**（按运行状态切换，不属于本类）：海底地图 `Underwater`、角色表情与 `DiveMask`、`ClickReticle`／`RouteRibbon`／`SalvageWinch`（minimal 关闭的交互件）、顶层牧场温室／水塔升级态（spec R17 要求默认显示未建造）、未建渔场 `WildFishery`。烘焙源与 GLB 一律保留，可回退。 | 主场景 `godot/scenes/world/environment.tscn`、`godot/scenes/zones/zone1_home_harbor.tscn`。连带修复两处依赖：`godot/tests/test_solar_cabin_asset.gd` 的断言由「四栋旧楼已隐藏」改为「已从场景移除」；`godot/tools/capture_sea_style.gd` 改 `get_node_or_null`，节点缺失时跳过历史烘焙去重检查。<br>**实测**：改前改后 `selftest` 均为 490 passed / 24 failed；`visual-solar-cabin` 均为 703 checks / 4 failures。两组失败逐项对照确认是存量问题，非本次引入。<br>**真实渲染**（隐藏 UI 后截图）：开场镜头、高空全景、俯视、zone2、顶层牧场、浮店六处，删除前后画面一致，保留下来的建筑与水面泡沫无缺失、无破洞。证据在 `sea-work/scope/11_opening_clean.png` 等 6 张。<br>**副作用已确认**：岸线几何切片由 801 段变为 10060 段。原因是 zone1 那四栋隐藏楼体原先仍参与 `_set_shore_uniforms()` 的几何切片（`shore_roots=[zone1,zone5]`），`visible=false` 不使其退出切片；移除后回到 `water_surface.gd` 注释记录的正常量级（约 9950）。删除 `StaticBatch` 与段数变化无关——单独回滚该项后段数不变，已隔离验证。 |


## 2026-11-04 顶层牧场 v006：整楼下沉、原顶部梯段登顶（最新口径）

| 对应设计条款 | 当前实施状态 | 证据 / 待核验 |
|---|---|---|
| SEA-WORLD-R17 · v006 | 已纠正v005误读：所有原消防梯局部变换保持并恢复显示，整楼根Y=-55.92（水面仍1.12），较v005再沉12.24m；原顶部下平台57.30落在世界1.38，经末段57.30→59.80及原入口登顶60.05/世界4.13，屋顶距水面3.01m。低层楼体/楼梯自然沉水。通行按真实GLB修正Z方向、草皮厚度及屋顶实体占地，正式角色可上岸→末段→屋顶→返平台。柱体破损网格/UV保留，不重导GLB。 | 隔离rooftop-ranch、ranch-deck-probe通过；真实visual-rooftop-ranch与minimum-loop/water-layer/click通过（退出0）。源独立重开：14个梯/平台/入口矩阵与v004一致，柱损与全部网格数据和v005一致。详见[本轮纠正与证据](../../development/2026-11-02_ocean_rooftop_farm.md#2026-11-04-v006纠正整楼沉没不移动消防梯)。最终专项61项0失败。工程契约同步仍受源/索引/运行哈希与内容ID共6项阻塞，无参数复核另报派生索引过期；没有批量刷新登记掩盖差异。未复验全工程selftest，升级经济规则/授权/登记仍pending。 |

## 2026-11-04 顶层牧场 v005：大块破败、下沉与单段消防梯（历史误读，被v006取代）

| 对应设计条款 | 当前实施状态 | 证据 / 待核验 |
|---|---|---|
| SEA-WORLD-R17 · v005 | 按用户反馈修订：柱体不再只靠裂纹和小贴片，改为 6 组真实 Boolean 大块缺损，单组约 1.3–1.7m 宽、2.1–3.65m 高，直接从柱体网格挖空；布尔面统一回到 `PaletteUV` 与公共材质，去掉默认 Material 和共面内里盒，避免粉绿调试色、黑白颗粒与 z-fighting。整楼根节点下沉到 `root_y=-43.68`，水面 `y=1.12`，单段消防梯下平台甲板与水面关系：`1.38 - 1.12 = 0.26m`。消防梯只保留水面以上一段：下平台 → 单段斜梯 → 上平台；其余折返梯、屋顶入口和高层平台在源与运行包装中隐藏。WalkArea 只含 3 个面片，角色胶囊实走通过；不再宣称从该段梯直达楼顶。 | Blender 源：`art_source/scenes/ocean_rooftop_farm/v005/ocean_rooftop_farm_v005.blend`；柱体稳定运行 GLB：`godot/assets/models/facilities/rooftop_ranch/components/pier/pier.glb`；运行包装：`godot/scenes/facilities/rooftop_ranch.tscn`、`godot/src/facilities/rooftop_ranch_zone.gd`；专项 `rooftop-ranch`：**PASS**。实拍：`sea`、`single_stair`、`single_stair_side`、`pier_damage_final`、`roof`。**pending**：其余全工程 selftest 仍有历史失败；温室／水塔升级经济规则未实现。 |
 | 默认最小范围的 `zone_enabled` 改为 `zone1`／`zone2`／`zone5`／`sea_supply`／`rooftop_ranch`。横滨铁道从「默认隐藏」转为默认显示；圆弧屋顶农场（zone3）与远海街町（zone4）的实例、以及水下景观六栋与沉没街景十栋，全部从 `main.tscn` 移除。**场景文件、预制体、源、账本与哈希一律保留**，随时可加回，不是删除资产。`World/Zones` 现装三块生活区（家园／横滨／浅水养殖），`World/SeaStructures` 装浮店与顶层牧场。 | 主场景 `godot/scenes/main.tscn`；范围开关 `godot/src/core/play_scope.gd`；`godot/tests/test_minimum_loop.gd`、`godot/tests/integration/selftest.gd` 已同步为「已安装区块＝zone1/zone2/zone5」；水下两套专项在未安装时改为验预制体本身（预算／序列化材质／水下职责），不再要求主场景挂载。**pending**：用户对「移除后水面视野变空」的观感确认。 |
| SEA-WORLD-R01 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-WORLD-R02 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-WORLD-R03 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-WORLD-R05 | 部分实现：zone1 已由组件派生并清理空阻挡；其余区块已接入同一机制，但 zone2/zone3 的行走矩形仍为旧手工数据 | `visual-blockers` 空阻挡 0、漏阻挡 zone1 2.4%；zone4 接缝 12.9% 待区块重做。水下基座改由组件声明 mode=none、水面阻挡只从「海上区域」派生，解除 zone1↔zone5 2.6m 水道的隐形墙（航路 42.7m→11.2m）。 [交付记录](../../development/2026-10-26_sea_scene_blockers.md)、[水下基座](../../development/2026-10-29_submerged_base_water_blocker.md) |
| SEA-WORLD-R17 | 新增区块 `rooftop_ranch`（顶层牧场）：`zones.json` 只留区块身份与取景，`landings`／`walk` 由 `Zones.bind_scene` 在运行时从场景回填；场景 `godot/scenes/facilities/rooftop_ranch.tscn`，摆位于 `World/SeaStructures/rooftop_ranch`，在家园东南约 60 米开阔海面。水面按用户红线标定：保留段最下面那层消防梯平台甲板 44.80 在水面上 0.26 米；船停该平台外沿，沿六段折返梯上行 15.2 米到 60.0 米楼顶。 | 专项 `godot/tests/test_rooftop_ranch.gd`（已登记 `run_verification.py` 的 `rooftop-ranch`）；实拍 `godot/outputs/rooftop_ranch_{sea,boarding,roof}.png`。**pending**：温室／水塔的升级消耗与产出规则（本轮只做互斥视觉切换，不新增经济逻辑）、碰撞与导航的最终美术验收。 |
/2026-10-26_sea_scene_blockers.md)、[水下基座](../../development/2026-10-29_submerged_base_water_blocker.md) |
| SEA-WORLD-R04 | 本轮表现与专项通过 | 环境静态鱼、尾鳍、圆环和点击圆盘退役；漂流物旧透明环退役，桶身金属环保留；源烘焙文件未修改，9 个区块 GLB 仅退役匹配的旧装饰三角索引。 [交付记录](../../development/2026-10-23_sea_visual_style.md) |
| SEA-WORLD-R06 | 区域及导航注入端口保留；本轮增加zone_enabled_query | [模块框架](../../development/2026-10-27_modular_framework.md) |
| SEA-WORLD-R07 | 本批实现并验证 | 15片旧荷叶精确退役840三角面，恢复另9片；独立组件与航路专项见本轮记录 |
| SEA-WORLD-R08 | 本轮实现；正式最小范围与独立专项验证 | [本轮交付](../../development/2026-10-27_minimum_loop_and_title.md) |
| SEA-WORLD-R09 | 已实现，场景点击与存读专项验证 | [本轮证据](../../development/2026-10-27_plot_shipping_loop.md) |
| SEA-WORLD-R12 | 正式区块装配GroundSpace并提供高度查询；建造通过现有geometry_changed刷新投影，水面阻挡未改 | [本轮交付及实测](../../development/2026-10-29_character_physics_framework.md) |

## 2026-11-03 默认世界范围：只保留横滨 + 新增顶层牧场（R08 / R01 修订）

按用户明确要求压缩默认主场景，并接入这一轮新做的海上高层农场。

## 资源与调用入口

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-WORLD-R10 | 六栋纯景观建筑各自独立实例挂在`main.tscn`的`World/UnderwaterScenery`；实景专项95项通过 | [制作与验收](../../development/2026-10-28_submerged_neighborhood.md)、[摆放所有者为main](../../development/2026-10-29_submerged_buildings_main_placement.md)；摆放唯一所有者是main.tscn，`neighborhood.tscn`降级为仅参考不再实例化；zone1不再自带第二份；材质写在每栋PackedScene的`surface_material_override`；MultiMesh基座真实包围盒避让、楼间水道、全屋顶淹没、无互动/碰撞/船阻挡/岸线泡沫 |

- [godot/src/world](../../../godot/src/world)
- [godot/scenes/zones](../../../godot/scenes/zones)
- [godot/scenes/world](../../../godot/scenes/world)
- [godot/assets/data/zones.json](../../../godot/assets/data/zones.json)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

- `godot/src/world/zones.gd`：命令/查询 `get_zone(id: String), label(id: String), landing(zone_id: String, landing_id: String = "main"), landings_of(zone_id: String), is_unlocked(zone_id: String), footprint(zone_id: String), zone_at(point: Vector3, radius: float = 12.0), bind_scene(zone: Node3D)`；事件 `无`。
- `godot/src/world/bake_store.gd`：命令/查询 `ensure_loaded(), geom(index: int), material(tex: int, tint: bool, unlit: bool, alpha: bool, double_side: bool), line_material(), timed_materials()`；事件 `无`。
- `godot/src/world/zone_scene.gd`：命令/查询 `set_geometry_source(src: String), pick_walk(origin: Vector3, dir: Vector3), area_containing(x: float, z: float), floor_height_at(x: float, z: float), set_zone_level(level: int, instant := false), update_time(t: float), landing_points(), landing_point(id: String)`；事件 `无`。
- `godot/src/world/zone_batch.gd`：命令/查询 `build(), update_time(t: float)`；事件 `无`。

- `ZoneBatch.retired_geometries / retired_alpha_geometries`：场景声明的历史批次退役清单；Environment 及五个区块均设置，以覆盖批次回退路径；默认空。烘焙版本升级时必须重新核验几何 ID。每个批次记录 `source_geometry` 便于检查。

## 验证记录

入口：`python3 scripts/run_verification.py selftest surface`。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 selftest、surface 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

新区域仍需完整的内容配置、边界和到达验证。

## 海上场景阻挡整理（2026-10-26）

SEA-WORLD-R05 首次落地。根因是阻挡有三份互不相干的来源（`shore.json` 烘焙岸线、场景 `WalkAreas`、组件 prefab 零阻挡），替换模型只改最后一份。
本轮新增 `BlockerSet`（组件级、几何派生）与 `verify_blockers` 门禁；zone1 修掉 1 条完全空阻挡与 3 条部分空，打捞台节点归位抵消 GLB 顶点偏移，行走甲板覆盖 0.03/0.00 → 0.81/0.85。
验证：`python3 scripts/run_verification.py visual-blockers surface selftest click management camera visual-sea-style` 全部退出 0；selftest 535 passed / 2 failed（背包格容器、zone1 共享材质，均为本轮之前的既有项）。`python3 scripts/check_feature_contracts.py` 0 issues。 [交付记录](../../development/2026-10-26_sea_scene_blockers.md)。

## 变更记录

2026-10-29 SEA-WORLD-R11/R12：种植区可踩踏，投影不再挖培养土洞口，木面外缘及显式实心实体仍阻挡；旧布局恢复无需改格式。[通行实测](../../development/2026-10-29_walk_on_planters.md)。

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

- 2026-10-23 画面优化：环境静态鱼、尾鳍、圆环和点击圆盘退役；漂流物旧透明环退役，桶身金属环保留；源烘焙文件未修改，9 个区块 GLB 仅退役匹配的旧装饰三角索引。 [独立验证与截图记录](../../development/2026-10-23_sea_visual_style.md)。

## 太阳能木屋接入影响验证（2026-10-25）

SEA-WORLD-R01/R02/R03：家园区块定点手工接入太阳能木屋完整 PackedScene；旧四 GLB 节点显式隐藏保留回退，原基座与独立打捞台以稳定包装引用。 验证入口：`python3 scripts/run_verification.py surface click management selftest visual-solar-cabin`；[证据](../../development/2026-10-25_solar_cabin_integration.md)。

## 太阳能木屋 v004（2026-10-25）

SEA-WORLD：稳定太阳能木屋包装内改为四个独立海上分区，海下基座与打捞台保持；真实渲染确认整体1.5倍和后区扩建。 [当前证据](../../development/2026-10-25_solar_cabin_v004.md)。

## 太阳能木屋 v005（2026-10-25）

SEA-WORLD：太阳能木屋四分区稳定包装接入v005；新增绳索与轮胎组件，真实渲染确认柱轴、梯子净空、桥边挂胎。 [当前证据](../../development/2026-10-25_solar_cabin_v005.md)。

## 太阳能木屋v006（2026-10-26）

稳定solar_cabin_submerged_base.tscn已切换为七层新楼体组件，旧四个基座资源退出引用；海上四分区保持。实例脚本新增可配置数据和组件路径供上下部分分别使用。上岸、行走、泊位不变；468实景检查和30航路503检查通过。[本轮证据](../../development/2026-10-26_solar_cabin_v006.md)。

## 太阳能木屋v007（2026-10-26）

SEA-WORLD-R02/R03：稳定组件更新及49组件160实例；保留当前太阳能木屋、区块TSCN与用户海下基座偏移。修复装配脚本既有混合缩进，472实景与30航路503检查通过。[记录](../../development/2026-10-26_solar_cabin_v007.md)。

## 2026-10-27 模块边界

Zones.far_sea_query 为只读资格回调；Main 汇集场景形状并注入 WaterNavigation.shape_query，几何调整后 invalidate。

[模块接口约定](../../architecture/module_contracts.md) · [本轮证据](../../development/2026-10-27_modular_framework.md)。

## 2026-10-27 场景组件细分与动物恢复

见[本轮交付与验证记录](../../development/2026-10-27_scene_component_split.md)及[组件分类目录](../../../assets/registry/SCENE_COMPONENTS.md)。运行验证与素材授权分别登记；交互请求端口不代表玩家摆放编辑器已实现。

最终补验：decorations 1589项通过；visual-decorations 1592项通过（包含独立实例、真实鱼群近景和正常上浮环境恢复）。surface 503项/30航线、自检537项通过；静态契约32功能/426源资产/317运行哈希0问题。旧水下网页同机位测试缺基准未执行，单列在本轮记录。

## 2026-10-27 当前最小循环与开始画面

本节及本轮修改条款优先于下方保留的历史范围。默认发布配置只开放家园生活循环；旧全功能验证须显式 `--full-world`，不能代替最小版本验收。接口、迁移及实测见[交付记录](../../development/2026-10-27_minimum_loop_and_title.md)。

## 2026-10-27 太阳房基座放大与落水贴合

SEA-WORLD-R02/R03：太阳能木屋装配根节点改为带位移与缩放——海上区域整体下移0.30米使平台板底落到水面上0.04米；海下白色基座按X1.450/Z1.431放大并重新居中，顶板16.24×17.77、四边各超出上层建筑0.40米，顶面与平台板底齐平。区块行走面同步下移到1.85，`span_min/span_max`显式写为1.0/2.15；行走矩形、泊位与上岸点XZ范围不变。704实景检查、装饰、组件与最小循环检查通过；surface/click/farming/management 的既有失败经HEAD基线对照确认与本次无关。[记录](../../development/2026-10-27_solar_cabin_base_scale_and_waterline.md)。

2026-10-27 场景点击循环：07:00收货、瓶盖、木土种植格及码头出货箱；[本轮记录](../../development/2026-10-27_plot_shipping_loop.md)。

2026-10-28：zone1/Objects/SleepCheckpoint定位在入口地毯(8.35,1.85,8.75)，复用现有可行走区域；实际从停靠小船点击、上岸接近和醒来位置通过visual-sleep-cycle。[睡觉交付](../../development/2026-10-28_sleep_cycle_delivery.md)。

## 2026-10-28 薄木板接合

SEA-WORLD-R02/R03：海上根Y=-0.77，板底1.16、上岸/行走/出货/睡觉基准1.38；基座出檐与手改布局保留。zones.json查询同步，船泊位维持水面1.12。当前实景与完整世界30航路503检查通过。[记录](../../development/2026-10-28_thin_cabin_and_dayparts.md)。

## 2026-10-28 家园箱子与夜灯修复

SEA-WORLD-R09：箱子直接挂到Objects/ShippingBox，(1.05,1.38,15.15)；实测底面1.38米，旧房屋cooler排除，点击命中与行走面均通过。

[交付记录](../../development/2026-10-28_home_lighting_recovery.md)。

## 2026-10-29 家园建造接入

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-WORLD-R11 | 已实现；相关专项通过，详细范围以交付记录为准 | [本轮交付](../../development/2026-10-28_building_delivery.md) |

## 2026-10-30 区块外海上结构物

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-WORLD-R13 | 已实现；`World/SeaStructures/floating_shop` 自带 BlockerSet，`main._water_shapes()` 收集后浮店中心判为阻挡水域（`floating-shop` 21 项 0 失败） | [浮店接入记录](../../development/2026-10-30_floating_shop_runtime.md) |

## 2026-10-31 结构物作为最小区块（sea_supply）

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-WORLD-R14 | 已实现并接入：`World/SeaStructures/floating_shop` 声明 `zone_id=sea_supply`，`main._setup_scene()` 扫完 `World/Zones` 后再把带 zone_id 的结构物并入同一张 `_zone_nodes`（重复 id 报错）；`zones.json` 只保留身份与取景，`walk`/`landings` 由 `Zones.bind_scene()` 在运行时回填；结构物不带 Plants/StaticBatch/建造等级。`Scope.zone_enabled` 把 `sea_supply` 列入最小游玩范围内。 | `sea-supply` 37 项 0 失败、`sea-supply-probe` 探针记录登记/甲板/泊位实测值；[接入记录](../../development/2026-10-31_sea_supply_station.md) |

## 2026-11-02 渔场空间与存读

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-WORLD-R15 | 已接入候选升级状态、岸坪支持与围网水域投影；39项逻辑/43项真实渲染通过，真实胶囊/原泊位/坏档拒绝及新旧档往返已实测 | [本轮交付](../../development/2026-11-02_wild_fishery.md)；fishery-environment |
| SEA-WORLD-R16 | 新两类职责契约已整理；运行完整验收pending。水上设施承接活动面／泊位／阻挡／功能；水下观赏建筑及海下基座的全部子树不得承担空间或玩法。账本与只读视图已登记；既有water-layer 104项通过仅为旧声明专项，不代签新契约 | [职责规范](../../standards/水层分类与空间职责.md)、[本轮整理](../../development/2026-11-02_building_two_class_contract.md)。后续须补漏声明拒绝、属性／metadata读取、全水下子树无功能及复合设施排除派生；浮店位置／靠泊仍pending |


## 2026-11-02 海上设施装配审计（当前实测）

SEA-WORLD-R01/R08/R13/R14/R15/R16：正式资源中7个独立海上设施地点、8条总成（渔场与打捞台同址分阶段）；默认范围纳入阳光房、打捞台／渔场、浅水台、浮店四处，zone2/3/4保留隐藏。浮店main实例原点(69.91094,-18.097904,46.376625)，带旋转／缩放，与设计位置、水线及行走投影不符；该transform与HEAD一致。当前floating-shop 41项5失败、sea-supply 37项8失败，船位Y=-12.4096；R13/R14已有接口接入，但当前空间可用性不通过。R15的fishery-environment 42项通过。R16通用专项104项通过仍漏检：空水层节点被collect跳过，打捞台空导出属性遮住metadata声明，账本与TSCN角色未对读；真实截图脚本16项通过也未阻止水下浮店画面。以上只登记审计事实，未改正式摆放；详情及未执行项见[本轮清点与证据](../../development/2026-11-02_surface_building_inventory_audit.md)。

## 2026-11-02 建筑职责两类整理（最新口径）

用户最新边界已落实为SEA-WORLD-R16现行契约：水上总成可组合水下视觉件，但不得从水下基座／观赏楼生成行走、登陆、碰撞、导航／船阻挡、交互、产出、玩法状态或岸线。仅整理契约／账本，未移动正式实例、未改模型或业务行为；所有运行缺口保留pending，历史专项结果不自动升级。

详见[本轮整理、静态校验与未执行项](../../development/2026-11-02_building_two_class_contract.md)。

范围补充：本轮仅海上主场景；“水下”只指该场景的观赏楼与基座。独立海底／潜水场景另行处理，不按本契约撤销其功能。43项未确认海上归属的独立塔区参考组件不进入两类视图；范围外不等于第三类建筑。

本轮最终静态验收：同步／复核均0问题；8项非法声明拒绝用例及海底范围排除用例通过，322／129两视图互斥完整。源／运行路径、哈希、阶段、授权保持；2377个运行／源支持文件未变。未运行Godot或真实渲染，新职责运行完整验收仍pending。[结果](../../development/2026-11-02_building_two_class_contract.md)。

## 2026-11-04 顶层牧场装饰悬空纠偏

| 对应条款 | 当前实施与证据 | 边界 |
|---|---|---|
| SEA-WORLD-R17 | 已修复150个装饰实例（24藤蔓/11苔藓/90草丛/25立面破损）origin被scale重复相乘及缩放轴转换错误；定点恢复源布局，650个非目标块、45个GLB及源文件哈希保持。隔离rooftop-ranch **525项0失败**，含实际包络/贴边高度及原正式登顶往返；visual-rooftop-ranch真实渲染退出0，全景/女儿墙近景已查看无红框天空悬浮件。minimum-loop和water-layer当前回归退出0。 | 不改水线、楼梯、上岸点/通行规则，不重导几何、不隐藏装饰；未复验全工程selftest。详见[本轮修复](../../development/2026-11-02_ocean_rooftop_farm.md#2026-11-04-v006-装饰悬空修复)，完整before/after与锁区证据在工程外transform_audit.json。 |

## 2026-11-04 顶层牧场全量悬空自检与栏杆分层校验

| 对应条款 | 当前实施与证据 | 边界 |
|---|---|---|
| SEA-WORLD-R17 | 扫描全部744个Models实例、45个GLB和源实例集合。发现并修正2个非装饰旋转基转换漂移：鸡舍`ORF2_实例_coop`与水下断梯`ORF3_下挂断裂消防梯`，只改两行Transform，未改源/GLB/水线/楼梯。新增主屋顶栏杆与抬高露台栏杆分层检查：主屋顶栏杆检查女儿墙顶部，抬高露台栏杆检查平台实体正面积重叠与外伸方向；序列化栏杆实际43段，全部覆盖。最终隔离`20261104-231319-full-ranch-self-audit-final-6ee970`：牧场**655 checks, 0 failures**；visual-rooftop-ranch、minimum-loop、water-layer均退出0。 | 红框构件实际属于主屋顶/抬高露台两组栏杆，不是同一高度规则；不以屋顶主包络错误判定抬高平台外伸。未复验全工程selftest。旋转修复审计在工程外`rotation_drift_audit.json`。 |


## 2026-11-05 霓虹花园街区东侧接入

| 对应条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-WORLD-R18 | 主场景街区**带入参考位** (156.149682, 1.12, 2.473711)，真实太阳房主体取样测得正东 150 米；该值只作参考，实际以用户手动摆放为准（当前实测 Y=-21.726082，下沉 22.846 m，见[摆放台账](placed_positions.md)）。航线、基础阻挡、街口泊位、真实角色上岸与步行在参考水线下通过，水层及最小流程通过。 | [摆位与运行证据](../../development/2026-11-05_neon_garden_quarter_v003.md) |


## 2026-11-05 霓虹花园街区五组件拆分

| 条款 ID | 当前实施 | 证据 |
|---|---|---|
| SEA-WORLD-R19 | 五件模块已经在正式街区总成装配。当前工作区主场景街区已下沉，实拍保留现有标高，水下街道没有隐形水面阻挡。恢复设计水线的隔离工况中，原街道基础阻挡、泊位、上岸和步行通过。水层及最小流程专项通过。 | [交付与验收](../../development/2026-11-05_neon_garden_quarter_v004.md) |
| SEA-WORLD-R22 | 已按 2026-11-06 位置规则改判：**可上岸性跟随实测标高**。主场景实测 `Y=-21.726082`，街区沉入水下、街口泊位与上岸不可用，记为已接受的运行现状；`Y=1.12` 仅作「恢复水线后可上岸」的隔离对照，不再作为主场景验收口径。原文的 `(156.149682, 1.12, 2.473711)` 已改标为带入参考位 | [摆放台账](placed_positions.md)；`python3 scripts/check_placed_positions.py` 3 结构 0 失败 |

## 2026-11-05 沉没旧城主场景接入

| 对应条款 | 当前实施状态 | 证据 / 待完成 |
|---|---|---|
| SEA-WORLD-R20 | 正式`World/SunkenCity`挂50组件/388实例纯视觉总装；100地坪、3电车、4曲线跨段及v003坡地/断口完整映射。修正真实MeshInstance材质路径、TSCN矩阵转置和水层role缺口；全子树无脚本/碰撞/导航/BlockerSet/WalkArea/交互，不进水面与岸线派生入口。编辑器期间根Y上移38.04888导致26楼越线，经用户确认仅将此根Y恢复0，其余最新场景保存保留。最终33338结构、124真实渲染、1239水层、141最小生活循环0失败，import及各项退出0。 | [正式导入与实测](../../development/2026-11-05_sunken_city_godot_import.md)。近水屋顶可见，约50–60米深的道路/断桥在当前海水吸收下几乎不可辨，视觉可读性待单独调优；无水诊断不冒充隔水效果。未改全局水深、存档或玩法。 |

## 2026-11-05 沉没旧城浅水新版验收

| 对应条款 | 当前实施 | 证据 / 边界 |
|---|---|---|
| SEA-WORLD-R20 | 用户授权统一限高后将街区整体上移45米；真实全几何最高点为电车，仍低于基准水面1.151754米，道路约17–22米水深。388实例、100地坪、3电车、4曲线跨段和断口保持；仅3个减层楼调整接地Z。main仅根Y一处变化，其他字节保留。正式标线路口38米及远景/日夜图保持水面，水下道路为极淡隐约可辨；未改吸收/水色/全局参数。 | [实拍与验收](../../development/2026-11-05_sunken_city_v004.md)。最终33916结构/182真实渲染/1191水层/141生活循环0失败。无水帧明确诊断；纯水下无碰撞/阻挡/导航/交互/存档/岸线职责保持。 |

## 2026-11-06 结构物摆放位置权威链

| 对应条款 | 当前实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-WORLD-R21 | 按用户 2026-11-06 指定落规则：`main.tscn` 手动摆放的 `transform` 是唯一真值，`zones.json` 的 `origin` 与文档坐标降级为**带入参考位**。新建 `docs/features/world/placed_positions.md` 台账逐结构记参考位／实测位／偏差；新增 `scripts/check_placed_positions.py`：台账漏行、台账实测位与 TSCN 不符、台账参考位与 `zones.json` 不符三种情况失败，`basis` 非均匀缩放只 WARN。当前实测 3 个绑定结构：`rooftop_ranch` 与参考位一致、`neon_garden_quarter` 下沉 22.846 m、`floating_shop` 偏离 66.19 m 且非均匀缩放 1.386/2.418/1.777。 | `python3 scripts/check_placed_positions.py` → PASS，3 结构 0 失败 0 WARN。**未改 `main.tscn`、未改 `zones.json` 数值、未刷任何哈希**：本次只落规则与台账，结构调整按用户决定另起。浮店非均匀缩放已由用户 2026-11-06 确认为**有意手动调整**，台账「缩放确认」列记 `有意`，脚本只打 NOTE 不再 WARN。 霓虹花园的上岸改判见本账本 `SEA-WORLD-R22`，`spec.md` R18 坐标已改标参考位，`GDD_V1.0.md` 摘要同步。 |

## 2026-11-06 手动移位后的植被取景

| 条款 ID | 实施状态 | 证据 |
|---|---|---|
| SEA-WORLD-R21 | 主场景保留用户摆位。按实测同步屋顶牧场与霓虹花园的平面位置及朝向，取景和天台空间断言读取设施当前变换。 | [摆放台账](placed_positions.md) 校验 3 个结构通过。当前牧场泊位仍命中几何阻挡，记录在[植被交付](../../development/2026-11-06_vegetation_facility_editing.md)。 |

## 2026-11-06 沉没旧城 v005 连续海床

| 对应条款 | 当前实施 | 证据 / 边界 |
|---|---|---|
| SEA-WORLD-R23 | 用户否定外围追加道路块后，已撤下40个 `edge_ramp_*`；v005恢复原388实例。新增Terrain3D `World/SunkenSeabed`，中心按真实100个ground几何托底，外缘12m平台+96m缓坡至Y=-62m；collision0、不参与水面/岸线/导航。 | [v005制作与验收](../../development/2026-11-06_sunken_city_v005.md)；实际海床129项采样0穿地、0坡度违反、4 region/262144像素通过；用户摆位检查3结构0失败。LOD/性能、商业权属和美术终审pending。 |


## 2026-11-07 礼品商亭替换、摆放与移动支撑

| 对应设计条款 | 当前实施状态 | 证据 / 待核验 |
|---|---|---|
| SEA-WORLD-R24 | 新商亭沿用sea_supply及稳定floating_shop.tscn；参考位按当前阳光房中心东南200米带入，后续认正式TSCN；旧模型完整用户变换保留为navigation_only旧驿站，不重复区块/泊位/补给 | [本轮记录](../../development/2026-11-07_gift_kiosk.md)及[摆放台账](placed_positions.md)。379实例矩阵独立比对、实际行走面/阻挡/泊位/海面日夜和角色承载通过；最终gift-kiosk 7129/0、render53/0、water-layer1594/0均exit0。 |


## 2026-11-07 商亭屋顶围绕角色展开消隐

| 对应设计条款 | 当前实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-WORLD-R25 | 已在正式商亭增量标记78个顶盖及附属根，Main注入实际角色/岸上状态；局部空间柔边圆孔展开、整顶消隐与反向恢复，室内和货物保持。圆角/高度/门边退出缓冲、同设施浮动、共享材质保护已实测。 | [本轮开发与验收](../../development/2026-11-07_gift_kiosk_roof_reveal.md)。专项入口roof-reveal-component、roof-reveal、visual-roof-reveal；最终运行证据在该记录追加；不把有非预期脚本错误的runner结果标为通过。 |


SEA-WORLD-R25最终本轮签署：`20261107-164731-gift-kiosk-roof-final-36558c`中roof-reveal-component127/0、实际主场景roof-reveal364/0、实际渲染74/0、商亭集成7129/0、镜头12/0，五项均exit0/runner PASS。water-layer另为2092/111、exit1，111条全部在并行resident_harbor，保留FAIL，不冒充全世界通过。[完整签署与边界](../../development/2026-11-07_gift_kiosk_roof_reveal.md#最终实测结果)。

## 2026-11-07 海域来源与独立潜水地图边界

| 对应设计条款 | 当前实施状态 | 证据 / 待核验 |
|---|---|---|
| SEA-WORLD-R26 | 源码已改为岸上current_zone、船上已安装且Scope启用区块的实际TSCN泊位XZ最近分区，无半径截断/JSON参考位。Main仅装稳定DiveSession，不挂潜水地图；catalog含9来源，不恢复zone3/4海面实例，不移动现有设施，不改SunkenCity/海床景观。旧整图资源保留、旧生成器限候选 | `Main._dive_source_at / _setup_dive`、`dive_map_catalog.gd`、`scenes/underwater/maps/*.tscn`；`dive-maps / visual-dive-maps`结果 **pending，待父线程补充** |

当前节覆盖R08旧“Underwater常驻按状态隐藏”的历史说明，状态仍partial。初填pending为过程；最终R26：dive-maps312/0、visual322/0，当前已安装泊位/岸上ID来源、9独立场景及原实例返回通过；SunkenSeabed原变换与top_level恢复有逐图断言，正式手摆transform未改。check_placed_positions四结构通过/0warning。全海平面等距和用户后续任意移位组合未穷举，源查询从实时泊位读取；不把规划zone3/4目录当已安装海面。[最终实测与边界](../../development/2026-11-07_dive_map_switch.md#10-最终实测与签署)。


## 2026-11-07 商亭室内柜台与行走动线

| 对应条款 | 实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-WORLD-R27 | 正式floating_shop仅增量加Visual/Interior、柜台交互点及家具扣除后的WalkArea；陈列台和附带5件货品在Godot相对Blender参考位向局部+X调0.3m以保留左侧通道，记录source_position与运行位。既有379个实例变换和屋顶标记不动，main.tscn未由本任务编辑。 | [本轮记录](../../development/2026-11-07_gift_kiosk_interior.md)，实际路径、浮动承载和补给交互验收进行中。 |


SEA-WORLD-R27最终签署：185311统一runner中室内349/0、实拍28/0、原商亭7129/0、屋顶364/0均exit0/runner PASS。真实胶囊到柜台前、包装柜侧和陈列台左过道；新家具不可穿越、原泊位/环廊/浮动/消隐通过，现行独立综合商店打开正常。用户修改的霓虹街区标高仅同步摆放台账，主场景未改。全世界水层仍有111条resident_harbor失败、全局契约有并行问题，完整边界见[本轮记录](../../development/2026-11-07_gift_kiosk_interior.md#相关全局检查与未验边界)。


## 2026-11-07 商亭近侧遮挡椭圆透视

| 对应条款 | 实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-WORLD-R28 | 正式商亭挂独立SightlineReveal表现节点，消费RoofReveal室内判定；Main注入实际角色和Camera3D。屏幕椭圆、世界XZ近侧和视深度双门限限制局部消隐，保留淡轮廓与柔边；地面和原屋顶不重复控制。 | [开发与验收](../../development/2026-11-07_gift_kiosk_sightline.md)。最终运行和实景结果后续追加，不将尚未审阅的渲染自动标为完成。 |


SEA-WORLD-R28最终签署：190758的shop-sightline968/0、实际GPU20/0和191040的roof-reveal364/0、gift-kiosk-interior349/0、camera12/0，五项合计1713/0、全部exit0/runner PASS。实际日夜/中间态/反向镜头及走出恢复已目视审阅，6份运行资源及Main与已验副本一致；60源文件和58GLB未改。全局契约26/27条并行问题另记，摆位4项与diff检查通过。见[最终交付](../../development/2026-11-07_gift_kiosk_sightline.md#最终实测与交付)。

## 2026-11-08 霓虹花园可走面与阻挡

| 对应设计条款 | 当前实施状态 | 本轮证据 |
|---|---|---|
| SEA-WORLD-R29 | implemented；左楼顶/后楼顶/右楼顶/菜园桥四个派生可走面已接入，源为各模块真实几何 | `garden-npc`14/0（主场景实测：菜园桥 42 矩形、surface_y 世界 12.53、豆豆站桥面、5 锚点可解析）；`minimum-loop`112/0、`npc-integration`749/0、`npc-save`702/0 均未回退 |
| SEA-WORLD-R30 | implemented；阻挡改为覆盖三个楼体与桥 | 探针实测 93 ms / 63644 三角形 / 116 实例 / 51 矩形 / 152.3 m²，包围盒 x[-23, 18.5] z[-17.5, 12.5]；逐楼投影抽样左 24% / 后 28% / 右 14% 被挡 |

新增文件：`godot/src/navigation/derived_walk_area.gd`。改动：`godot/scenes/facilities/neon_garden_quarter.tscn`（四个 `WalkAreas` 节点 + `Blockers.target_path` + `NpcStations`）、`godot/src/world/zone_scene.gd`（可走面按能力收集，继承脚本不再被漏掉）。

`main.tscn` 本次无 diff，用户手摆 `transform` 未动；`placed_positions.md` 现有霓虹花园一行仍与 TSCN 一致（`Y=-15.869949`），新增的 `NpcStations` 是它的子节点，不改变该 root 的台账数值。`check_placed_positions.py` PASS（3 结构 0 警告）。

未做：玩家上楼路径（用户明确只让豆豆在楼上）、楼顶种植玩法、三栋楼的独立主场景拆分（用户确认现状「左右独立、后独立」已经符合要求）。

## 2026-11-08 绞盘打捞台朝向与霓虹花园屋顶可活动区

| 对应设计条款 | 当前实施状态 | 本轮证据 |
|---|---|---|
| SEA-WORLD-R31 | implemented；打捞台甲板绕几何中心绕 Y 转 −45°（对齐默认相机屏幕轴），行走面同轴同角，电线杆反向补偿保持世界位姿，野捕渔场与交互点同步 | `visual-walk-deck`：zone1_salvage cover=**1.000**（基线 0.890，提升）；`visual-blockers`：**zone1 OK，44 条矩形、空=0、漏 5.2%**；实拍 `outputs/salvage_angle_top.png` 目视甲板边缘平行画面 |
| SEA-WORLD-R32 | implemented；霓虹花园可活动区改到左楼屋顶（世界 y15.20），设屋顶泊位（船位实际水面 y1.12），撤销水下街口泊位，船老大迁入独立 `RoofNpcStations` | `probe_neon_roof_landing`：屋顶泊位 1 个、站立点 y15.20、船位 y1.12、垂直差 14.08；`residence_dock_workshop` / `_work` / `_social` 三锚点全部 `support_validated=true`；实拍 `outputs/neon_roof.png` 目视船老大站在屋顶面 |

改动文件：`godot/scenes/zones/zone1_home_harbor.tscn`、`godot/scenes/facilities/neon_garden_quarter.tscn`、`godot/scenes/npc/rooftop_npc_stations.tscn`、`godot/src/bootstrap/main.gd`。屋顶牧场 `rooftop_ranch_zone.gd` **未改**（复核结论为一致，中途的错误放宽已回退）。

`walk-deck-fit` PASS exit=0。两项失败（`sunroom_upper_deck` 0.892 vs 基线 1.000、`zone4` 阻挡漏 29.6%）已用 HEAD 版 `zone1_home_harbor.tscn` 临时回退做对照，结果逐行相同，属工作区原有未提交改动，非本轮回归。契约检查 73→69（正好是本轮 4 个文件），未做批量哈希更新，只定向更新自己改过的 4 项并写 `audit_note`。

未做：霓虹花园水面到屋顶的物理通路（用户明确选择「直接上岸到屋顶」，属已知偏离 SEA-MOVE-R10）；屋顶派生面漂移的常态化断言。详见[本轮记录](../../development/2026-11-08_salvage_rotate_and_neon_roof.md)。

## 2026-11-10 编号002普通水上建筑接入

| 对应设计条款 | 当前实施状态 | 本轮证据与边界 |
|---|---|---|
| SEA-WORLD-R13 | 002作为 `navigation_only` 普通水上结构接入 `World/SeaStructures/water_building_002`，不新增Zone、WalkArea、泊位、交互、产出或存档字段。Blockers只扫描Visual/Structure真实水线几何，植物独立且visual_only；派生矩形已被main._water_shapes实际收集。 | 002专项1441/0、水层1794/0，正式导入exit0，真实四视图12/0；商店7129/0、最小流程112/0。专门绕002的端到端航线与性能未做，不冒称已测。 |
| SEA-WORLD-R21 | main只增002资源与节点，原有节点变换零变化。初次参考位 `(188.57135, 1.12, 143.89136)` 位于商店旁建筑列、001东侧，已加入位置台账；后续手改为唯一真值。 | 补齐位置校验对非Zone SeaStructures的覆盖，不靠新增假区块使检查变绿；当前6结构/0失败/0警告。树冠保留v003体积变化，游戏矩阵检查覆盖167实例。 |

001只补原本应有的navigation_only元数据，未移动模型。002全局接缝穷举、用户美术终审、参考图商业授权与性能仍pending。见[制作与游戏接入记录](../../development/2026-11-10_water_building_002.md)。


## 2026-11-10 远景岸线退役

| 对应设计条款 | 当前实施状态 | 本轮证据与边界 |
|---|---|---|
| SEA-WORLD-R05 | 退役 `assets/baked/shore_environment.json` 的 7 条矩形（沉没塔 A–E、圆弧玻璃大厦、阳台住宅）。它们按「旧城仍露出水面」烘焙，沉没旧城接入后整城最高点世界 y=−1.64、水面 1.12，7 条在水面支撑为 0，成为隐形墙（海上凭空报「前方是岸」）。旧城阻挡改由 `World/SunkenCity` 自身的 `BlockerSet` 按可见几何派生：水面之上无三角形即自动放行。远景水街区当前无独立条目，`shapes` 为空并在 note 写明退役原因。 | `visual-blockers` 新增 baked 断言：逐条用环境场景自己派生的水面阻挡算覆盖率，低于 0.35 判 FAIL。反证把 7 条装回后 7/7 支撑 0.00、检查 FAIL（`sea-work/verification/20261110-160623-baked-negative-test-a77ba3`）；退役后 baked 行 PASS，同批 zone1/2/3/5 空阻挡均为 0。zone4 漏阻挡 29% 为既有、非主场景区块，见[本轮记录](../../development/2026-11-10_facility_access_repair.md)。 |

## 2026-11-11无损性能优化第一批

承接 SEA-WORLD-R01/R02/R05/R07 及现有 `ZoneScene.update_time` / BakeStore 接口；仅追加本轮实施事实，登记 JSON、status、原条款及摆放历史保持。

- Main 室内不提交室外 zone/water 表现更新；`water.time` 与 weather 模拟相位仍推进，不新增区块状态所有者或重摆场景。
- BakeStore 对相同 `t` 只推送一次共享时间，避免多个区块重复提交同一时刻。
- 岸线距离图采用版本化单 slot、20 MiB 上限、SHA256 校验的最终 RGF 缓存；分辨率仍为 1536，算法不变，不以降精度换启动收益。真实 1536 冷 1384.704 ms→热 70.763 ms，输出字节相等；后续最终数据由主线程回填。
- `roof_reveal` 与 `shop_sightline` 门控尝试已撤回，不宣称优化或改变 SEA-WORLD-R25/R28 的消隐行为。
- 主线程已提供 `performance-equivalence` 19/0、cache 通过、`ocean` 通过及岸线缓存 headless 单测通过；cache 不填写未经确认的精确项数，本次未新增测试或复跑。

[主记录](../../development/2026-11-11_performance_optimization.md)由主线程建立；最终视觉、存档及经营回归仍处理中，本节不预签，海面收益波动不作承诺。
