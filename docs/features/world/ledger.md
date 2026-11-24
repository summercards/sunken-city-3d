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
    "godot/assets/data/zones.json",
    "godot/addons/scene_assembly",
    "godot/tests/test_scene_assembly_editor.gd",
    "godot/tests/test_building_attachments_editor.gd"
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
    "sunken-city",
    "editor-scene-assembly",
    "editor-building-attachments",
    "editor-workshop-attachments",
    "formal-facility-berths"
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

当前入口为 `python3 scripts/run_verification.py formal-facility-berths visual-formal-surface-handoff`。

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

## 2026-11-13 候选空间与菜园NPC深审（未修复）

承接现行派生空间/位置权威/R29/R32及存档世界适配。用户主场景Transform零改动、位置检查6/0。真实Main两个稳定采样确认菜园Walk active/built、36矩形，但5 Marker均高于派生面0.737953m，0/5锚点、总聚合35/40；豆豆可见但home_fallback到天台(G04)。左屋顶5/5、天台25/25、浮店5/5正常。该失败不同于已接受下沉街口，不抬根/恢复街口/放宽0.05门槛；先测原几何土面，再判Marker或派生选层/压平归属。

候选sunroom修缮状态未进整档位置上下文，误收/误拒二楼(S01)已复现；水层/位置checker覆盖缺口R14/R15、旧surface单面断言与过时NPC迁址fixture另列，不能改用户摆位凑绿。菜园探针exit1、8检查/3失败、marker完成且无脚本异常；本轮未修。完整方案与证据见[深审记录](../../development/2026-11-13_engine_deep_audit.md)。

## 2026-11-13 B2 G04 菜园桥 NPC 锚点修复

根因是桥面真实几何的候选带代表层为局部约 27.662，而菜园 `NpcStations` 的作者站台高度为局部 28.4，五个 Marker 统一产生 0.737953m 的 height mismatch。未改 `main.tscn` 用户根 Transform、旧街口或资产；未放宽 `SUPPORT_TOLERANCE=0.05`。最小修复仅把 `NpcStations/residence_garden_bridge` 的本地 Y 对齐到派生 WalkGardenDeck 实际代表层 `27.662`，保持其 X/Z、五个 Marker、模型和桥面派生参数不变。

新增 `garden-npc` 与 `npc-integration` 的高度/支撑专项断言。正式 `garden-npc` 复跑 `exit=0`，5/5 菜园锚点有效、聚合40、豆豆按日程落位且不 fallback；`npc-integration` 仍受当前工作区既有天台站位/路径失败并超时 `exit=124`，`npc-save-seed` 也因既有天台/恢复前置真实 `exit=1`，均不归因于 G04；未运行 restart。证据目录：`/Users/zyq/work/sea-work/verification/20261113-183346-b2-g04-garden-final-assertions-e70d71`、`/Users/zyq/work/sea-work/verification/20261113-182405-b2-g04-npc-integration-170faf`、`/Users/zyq/work/sea-work/verification/20261113-183556-b2-g04-npc-save-seed-77f9cc`。

## 2026-11-14 B2 G04/G07 空间修复承接

承接SEA-WORLD-R12/R21/R29/R32：G04保持用户main根Transform/模型/派生参数/SUPPORT_TOLERANCE，唯一场景修复是菜园NpcStations本地高度对齐实际WalkGardenDeck代表层，五Marker相对关系不变；不重开zone3或已退街口，不制造玩家上楼路径。当前garden-npc26/0、5/5菜园锚点/聚合40/豆豆不fallback，npc-integration853/0、seed527/0、restart280/0 PASS/exit0补齐上节早批124/1的集成占位，旧失败仍保留。

G07由RoomService拥有床布局/四边OBB净空与安全门路线，World/GroundSpace仅提供派生支撑/可达查询；RoomBed可选approach_path将同一路线交正式ApproachAction，保留start_walk准备。bedside1800/0含133真实胶囊布局、133真实move_ground到门、26正式approach含13绕行；旧档无安全床边点前厅fallback，不挪床/场景或新增位置真值。

本批未动main.tscn、生产资产、用户根Transform或正式user档；共享workshop/plant_authoring变化不归B2。父已有摆位6/0不等于本次复跑；当前视觉-room/garden/sleep与最终契约待父最终追加，不借旧图/历史门禁，登记头partial不改。[B2主记录](../../development/2026-11-13_engine_deep_audit.md#b2-业务事务与空间修复最终回填2026-11-14)。

### B2 最终状态（2026-11-14）· [主记录](../../development/2026-11-13_engine_deep_audit.md#b2-最后复测与签署范围2026-11-14)
- 005741 NPC853/0、seed527/0、restart280/0及005436 bedside1800/0均exit0；012647 management按当前安装内容区分zone3退役后37/0、exit0，不恢复生产，旧36/1保留；摆位6/0仅承接既有证据。
- 010438三视觉18PNG/exit0（room8/garden4/sleep6），只目检room-inside/garden-bubble-single/sleep-wake；菜园遮下半身不能签足底美术，醒来图是室外太阳房非室内。uniform索引/agent_radius/zone2glass警告保留；契约sync532/check533 issues均exit1，未写派生/刷hash，登记头partial不变，不签全工程绿。

## 2026-11-14 B3 查询与摆位治理承接

`Zones.get_zone/landing/landings_of`公开查询现返回递归副本，`bind_scene`仍是内部场景绑定唯一写入端；摆位检查器统一支持有限科学计数法、显式正号、`.25`及严格12数Transform3D，并按basis列计算非均匀缩放告警。当前`b3-query-copy`、`management`默认/minimal与`--full-world`、摆位检查及架构检查均exit0；仅登记查询/解析治理，不改用户main根Transform、位置台账或资产源。R15更完整Interior/闭包和全局资产门禁仍待后续，登记头partial保持。

## 2026-11-15 编辑器场景装配交付

本轮装配闭环归 SEA-WORLD，登记头继续 partial，不新增 FeatureID。两工坊配方/版本所有权不变；本次收尾仅文档、定点运行清单、记忆与交付预览，不再改生产代码。

| 对应设计条款 | 当前实施状态 | 证据 / 未签边界 |
|---|---|---|
| SEA-WORLD-R33 | implemented；已保存候选真实缩略图库、建筑/静态树/动态树条目、世界 Y 平面拖放到当前 Node3D 场景；旋转缩放父节点转换正确；空树库只提示保存。 | editor-scene-assembly 70/0；建筑与动态树通过实际 GUI 输入链，静态树和同源第二栋为直接 insert_candidate 调用。非表面吸附，不自动灌样例。 |
| SEA-WORLD-R34 | implemented；无脚本 Placement + 外链 Asset；选择路由与显式原工坊按钮、原生 gizmo、插入/换版 undo redo、隔离场景保存后真实 Editor 重开四实例。 | owner、metadata、外链一致；截图可见原生 gizmo，但未拖测 gizmo 轴。测试直接赋 transform 核对保持，不称人工移动旋转缩放验收。 |
| SEA-WORLD-R35 | implemented；成功打开 token 绑定、脏确认取消/坏路径/保存失败保护、另选不改绑定、只换当前目标 Asset 且保当前 transform。 | 同源另一栋及树兄弟不变、旧 revision hash 不变；动态目标不被静态保存降级；目标删除、外部换版、场景重载后拒绝陈旧目标，保留已保存新版本并反馈未更新。 |
| SEA-WORLD-R36 | implemented（作者装配链）；无 Main/Autoload 隔离 editor 验收，不签正式游戏接入。 | 未做 WalkArea、航行/水面阻挡接线、潜水适配、正式资产登记；不新增 AssetID。四分屏只首视口实测，人工全流程/其余视口/gizmo 轴拖动未测。 |

### 最终原始证据与使用入口

- 外层报告：`/Users/zyq/work/sea-work/verification/20261115-142031-scene-assembly-delivery-74cfc2/report.json`。editor-scene-assembly **70/0**、editor-plant **2271/0**、editor-workshop-upgrade **991/0**，三项均 exit0、passed=true、unexpected_errors=[]；asset-import exit0、unexpected_errors=[]。这是已完成批次，本次文档收尾未重新运行 Godot。
- 内层报告：同批 `project/outputs/scene_assembly_report.json`，checks=70、failures=[]、enginehint=true；真实链为 `Input.parse_input_event + warp_mouse → ItemList._get_drag_data → Control._can_drop_data/_drop_data → EditorUndoRedoManager`。自动事件驱动不是人工鼠标验收；工坊按钮/保存/历史部分由测试直接调用或 emit 信号。
- 两张最终实拍：同批 `project/outputs/scene_assembly_assembled.png`、`scene_assembly_reopened.png`；本次已目检候选库、楼房/树与重开场景，未见错误弹窗。测试摆放有模型重叠，仅证明隔离装配状态，不签美术场景排布。
- [浅色使用说明与证据](../../../outputs/scene_assembly_review_20261115/index.html) 同目录保留两张原图、outer/inner 及两工坊 inner JSON。操作为先保存候选→打开 Node3D 场景→刷新库→按世界 Y 平面拖入→原生 gizmo 摆放→选中并点原工坊编辑→保存新 revision→手动保存场景。动态树须点保存动态风版本。
- 生产 `godot/scenes/main.tscn` SHA256 前后均为 `f246ee6aa3bd474ec20979783e0f0c9e606f99de1dcfe899400ccb686e8b1291`；Main 不自动保存，既有摆位未改。源码范围13文件：scene_assembly六件、两工坊各plugin/editor_screen四件、project.godot、装配测试、统一runner；字节与归属审计见交付目录 `closeout_audit.json`。运行清单只登记这13件，不重签其他漂移或分配AssetID；全库检查结果另行追加，不以专项通过代签。

### 本次收尾的全库实测结果

`python3 scripts/check_feature_contracts.py --sync` 实际 **exit1 / 488 issues**；无参数正式检查 **exit1 / 489 issues**，均统计 **46 features / 1073 source assets / 1560 runtime resource hashes**。两次共同有421项runtime hash drift、14项source hash drift、51条断链、SEA-ASSET条款账本集合问题及`plant_authoring/store.gd`候选根`scenes/workshop_plants`缺资源扫描问题；正式检查另有derived feature index stale。因全库错误，sync未写派生索引；不创建空候选目录、不修改其他hash或条款凑绿。SEA-WORLD、SEA-WORKSHOP、SEA-PLANT-EDITOR均无条款/入口错误，不能据此称全库通过。

完整exit与每条issue：`outputs/scene_assembly_review_20261115/contracts_results.json`；原始日志同目录`contracts_sync.log`、`contracts_check.log`。定点13项SHA/bytes一致、其他运行记录及顶层元数据不变；两工坊既有code_paths已覆盖各自桥接文件，未重复登记。本轮HTML本地链接/图片存在性与`git diff --check`通过；未运行浏览器布局验收。未提交、未push、未调用present_files。

## 2026-11-16 工坊新默认与交互调整后的装配回归

归R33–R36，不增加产品插件或FeatureID；本轮只加强 `test_scene_assembly_editor.gd` 的真实GUI输入准备与证据：窗口置顶、实际window_id、源点warp后等两帧、每次独立reset及断言can_drop/drop。保原70条业务断言、增加8条输入断言；建筑/动态树仍走真实ItemList→Control drop→EditorUndoRedoManager链，未用直接insert冒充两次GUI拖放。相关因素为桌面遮挡与输入时序，未做单变量唯一根因证明，不声称OS焦点激活、人工拖放或gizmo手感已验。

最终同批 `/Users/zyq/work/sea-work/verification/20261116-015632-workshop-defaults-delivery-90bc20/report.json` 串行楼房编辑器1453/0、装配78/0、调整内核357/0，import及各项exit0、unexpected_errors=[]。78/0内层报告为同批 `project/outputs/scene_assembly_report.json`，保存/重载/回编/仅目标换版与同源实例变换保护均通过。先前fullsrc无Autoload扫描批529条意外错误、minimal首drop12/1及其他失败保留，不改签历史通过；本次产品装配plugin/drop_surface无diff。

Main、bootstrap/main.gd、project.godot保持当前HEAD，Main SHA256仍 `f246ee6aa3bd474ec20979783e0f0c9e606f99de1dcfe899400ccb686e8b1291`。未在生产Main实际拖入或自动保存，不签WalkArea/航行/潜水/正式登记；当前回归随建筑工坊交付 `outputs/workshop_defaults_review_20261116/index.html`。运行清单仅刷新本轮明确测试字节，不发AssetID。

## 2026-11-16 独立建筑外挂计划与挂载职责承接

保留登记头 `partial`、原code_paths/verification和全部历史；本轮只追加设计承接，不因本节写入未经hook注册的验证名。32type×3condition=96项已冻结于[组件计划](../../../art_source/scenes/building_attachments/v001/component_plan.json)，其正式asset_id全部null、planned_key唯一，不是资产登记表。

| 对应设计条款 | 当前实施状态 | 已知实现 / 待验边界 |
|---|---|---|
| SEA-WORLD-R37 | implemented_pending_current_verification | 现有scene_assembly新增attachment_panel/gallery，四分类/搜索/真实缩略图源码已存在；交接时图库condition仍有dropdown，三按钮及少dropdown目标待UI代理落实和实测，不签可用性或缩略图全绿。 |
| SEA-WORLD-R38 | implemented_pending_current_verification | attachment_surface/controller已有真实三角射线、wall/roof、锚点与逆矩阵补偿；当前点面/拖放/上下文锁定在实施，不以旧Y平面拖放78/0或core逻辑代替本轮editor。 |
| SEA-WORLD-R39 | implemented_pending_current_verification | controller已写Attachments兄弟层与undo/redo、独立候选、宿主换版提示；当前全部transform保护、陈旧上下文拒绝、失败原子性、重开及真实gizmo尚待当前editor hook执行。房屋core与旧screen仅记录既有diff基线，不由本任务编辑。 |
| SEA-WORLD-R40 | implemented_pending_current_verification | 独立native生成器声明静态scriptfree/显式256层碰撞/世界派生排除与水下拒绝true；r6仍有脚本错误与字镜像，不签96静态交付、真实碰撞、无功能全子树或正式接入。 |

证据为只读 `/Users/zyq/work/sea-work/verification/20261116-032945-attachments-frozen-r6-1b18e2/report.json`：building-attachments **7712项/10失败，exit1、passed=false**（三类自定义曲面九项闭合失败与F前轴镜像，typed Array proxy脚本异常仍在）；build-attachment-library **96 records、exit0、inner passed=true，但9条SCRIPT ERROR、outer passed=false**；visual-building-attachments **484/0、exit0、13条unexpected、passed=false**。不是合格批次。任务交接时editor尚无hook、未执行；本轮未补跑也未目检新图，不借旧工坊1453/0或装配78/0签外挂。

本任务只写GDD、三个现有feature的spec/ledger、新计划和指定[开发记录](../../development/2026-11-16_building_attachments.md)；不改code/runtime/registry/memory、用户transform或Main，不跑Godot/Blender/runner/contracts。并行内核与UI后续修复须由主线程绑定新源码/报告追加，不追改r6失败史。

## 2026-11-16 r10b最终当前签署（R37–R40）

本节承接最终已完成实现，更新上节pending/未hook的当前结论，r6及中间失败保持原样；登记头全局partial不变，不新增FeatureID。本任务只读报告，不执行引擎/contracts或改code/registry/Blender。

| 对应设计条款 | 当前实施状态 | 当前实测 / 限制 |
|---|---|---|
| SEA-WORLD-R37 | implemented_verified_in_scope | 中文四分类、三状态按钮、搜索与真实图库，单击选中保drag源、双击/编辑组件进入编辑，非法文字保输入与状态/参数上下文；当前editor328/0覆盖。 |
| SEA-WORLD-R38 | implemented_verified_in_scope | 材质cull真实面、双面normaltowardobserver、多脚/背部2mm实际tri薄带profile，12mm外偏/4mm支撑门槛；117case=96+21any另一面actualprofile/foot/collision通过。自动GUI真drag damaged/offset0.03/angle7及墙牌/roof箱surfaceclick；宽屋顶正例、边缘/窄梁/脚洞/邻墙穿透拒绝分列，不用AABB替支点。 |
| SEA-WORLD-R39 | implemented_verified_in_scope | 输入变更取消arm保输入，selected/hostrev/geometry变stale拒，any跨wall/roof apply拒须reproject；宿主换版后旧Assetfree引用刷新、Attachments兄弟及当前transform保持、提示不auto重投，undo/reference恢复旧节点而非regen。候选hash+JSON重生成，不执行外部候选TSCN。 |
| SEA-WORLD-R40 | implemented_verified_in_scope | 静态库96冷load+96隔离user重存重载/脚本安全通过，显式256/mask0代理共441、默认15状态。12物理case真实人物0.22半径/1.3高撞实体及脚间可通；细管用小胶囊，不写人物通管。水下禁止true、无Walk/岸线/船/潜水/Main职责，building_class=null与none/none非自动水上建筑。 |

当前最终外层 `/Users/zyq/work/sea-work/verification/20261116-064110-attachments-production-library-r10b-c8e894/report.json`：同一minimal工程串行 **verify-attachment-library12103/0、building-attachments11122/0、editor-building-attachments328/0、editor-scene-assembly78/0、editor-workshop-upgrade1453/0**。导入和各项均exit0，completion=true、unexpected=[]、source_consistent=true，source_changed_during_run=false；生产库322文件前后hash一致。核心NaN负例有JSON warning，不能称零warnings。r9j分开editor/scene只作历史，非最终签署源；这次房屋1453/0/装配78/0是同批实跑，不借旧报告。

当前视觉另绑定r9c `20261116-052700-attachments-v2-support-r9c-a4e161/report.json` **507/0、131PNG**；当前支撑几何与r10b一致，早期八个悬空bug修闭，完整contacts/style/用户艺术未签。GUI是Input.parse_input_event+warp_mouse自动链，矩阵/部分负例及房屋回编用直接调用，不称人工；仅首3D视口，gizmo轴未测，生产Main未运行。8件房屋core与旧screen的冻结文件/hash/diff均保持，Main SHA仍 `f246ee6aa3bd474ec20979783e0f0c9e606f99de1dcfe899400ccb686e8b1291`。

候选Store早期WRITE临时备份产生.tscn-random/ERR_FILE_UNRECOGNIZED=15，当前READ_WRITE+get_path/close修复；Python3 O_NOFOLLOW/O_EXCL原子写、manifest-last和base/id/rev/file真实symlink负例已过。无Python拒绝独立候选导出，但Ctrl+S场景保存不依赖Python。内部embedded_support不是宿主普通clearance，局部例外及未签完整审计见[v002实测补充](../../../art_source/scenes/building_attachments/v002/delivery_validation.json)。用户步骤已追加[spec](spec.md)，审阅[交付页](../../../outputs/building_attachments_review_20261116/index.html)及[开发记录](../../development/2026-11-16_building_attachments.md)。全库sync/check由主线程实跑后另追加，不预填历史数字。

### 主线程最终门禁与交付范围

最终实跑同步 **489 issues / exit1**、无参数正式检查 **490 issues / exit1**，46功能、1105源资产、1873运行资源。新32个BAT AssetID的职责分类为null/none/none且没有分类/主记录/源索引错误；315个明确源码与运行目标SHA/bytes一致，不改其他漂移。仍有421运行hash漂移、14源hash漂移、51历史断链、SEA-ASSET条款集合、候选写入根扫描与派生索引问题；本轮新增 `scenes/workshop_attachments` 是用户首次另存才创建的输出根，被通用res引用扫描当缺输入。未创建空目录或样例凑绿，也不把该条掩饰为已修复，静态保存与真实候选另存已由r10b实测通过。

原始日志与退出码 `/Users/zyq/work/sea-work/building_attachments_release/contracts_{sync,check}.log`、`contracts_results.json`。外层汇总进程exit0仅代表记录完成，不能替代两个内部exit1。主线程实际审阅v2原生八张组件墙、关键支撑近景、最终1280编辑器及房屋装配示例；图库与参数分层、文字正向和原八个悬空缺陷修正可见，不签全部接缝/用户美术/人工手感。交付HTML和两个ZIP真实存在，均CRC与哈希核验；未提交推送、未改Main及冻结8件房屋内核。

## 2026-11-17 双工坊重建与装配桥接重连（R35、R36）

本次用户授权工坊故障排查，不属于前次外挂冻结改动。scene_assembly按plugin+screen双实例跟踪回编连接；相关节点上线合并延迟发现、请求前刷新，退出从原始信号源断开。旧screen释放只清对应工坊pending/binding，陈旧回调及另一工坊同token不能串绑，不每帧整树扫描。Placement当前transform、只换Asset、动态旁车和用户手动保存边界保持。

新增 `test_scene_assembly_editor.gd` 重建/两工坊禁用重启/失效pending/旧回调/幂等/卸载断连断言。早批 `/Users/zyq/work/sea-work/verification/20261117-185513-workshop-switch-integration-0dc248/report.json` 实际装配159/0、房屋1499/0、各exit0，但source_changed_during_run=true，不能签最终源码；串行当前最终与图像/未测项见[本轮深检](../../development/2026-11-17_workshop_switch_deep_check.md)。未修改Main、原用户摆位或生产候选，不新增正式资产/WalkArea/航行/潜水职责。

最终 `20261117-201128-workshop-switch-integration-accepted-8cf925/report.json`：装配159/0、房屋1499/0，import/两项/runner均exit0、completion=true、unexpected=[]、source_consistent=true，source_changed_during_run=false；新增重建/启停/旧回调/跨工坊相同token与卸载断连均执行。当前产品/测试与隔离快照一致。另树2289/0、真实切换336/0，均exit0。原gizmo轴/其余视口/生产Main边界不因本轮扩大。最终全库sync540/check541 issues、均exit1，其他漂移/断链/输出根扫描保留，不签全库通过；本轮14条明确源码/测试登记无漂移。

## 2026-11-18 外挂内嵌建筑工坊与场景双域回编（R35、R37–R39）

用户新指令覆盖旧独立dock编辑主路径，保留R37及11/16历史原文，不新增FeatureID。全局partial/owner保持；登记头只加已存在的 `editor-workshop-attachments` 验证名，scene_assembly目录与旧test路径已有覆盖，不重复列目录或把SEA-QUALITY runner改归本功能。

| 对应既有条款 | 当前状态 | 当前实施与边界 |
|---|---|---|
| SEA-WORLD-R37 | implemented_verified_in_scope | dock主路径「到建筑工坊编辑外挂」→公开show_attachment_page直达。内嵌分类/三态gallery、style/text/buttons为推荐编辑路径；旧controller/panel内部API继续维护兼容，不要求独立页编辑。 |
| SEA-WORLD-R38 | implemented_verified_in_scope | 同SubViewport原生drag/arm点击wall/roof、actual mesh pick/本栋列表、沿面XYZ0.01..1m步移重投支撑；沿用绿红ghost真实三角面算法。普通Control receiver用于SC target-control原生drop链，DRAG_END查gui_is_drag_successful，不用直接insert冒充。无fake native gizmo，不签人工轴拖。 |
| SEA-WORLD-R35 | implemented_verified_in_scope | 请求传当前scene layer context snapshot，非disk旧；双域prepare后成功打开才token/plugin+screen双实例绑定，保11/17陈旧回调防串。保存前对比现场fp，并发变更保新revision并报“新revision已保存，实例未更新”，不误更新现场。 |
| SEA-WORLD-R39 | implemented_verified_in_scope | 新work候选带兄弟外挂；snapshot同只换Asset，保原layer及全部子node身份/当前transform；实际changed含metadata才双层同一undo换版。不重复append、不auto-reproject，Placement保存瞬间transform/其他同款/历史revision保留，Main仍用户手动保存。 |

完整作品的八件同.tmp→manifest→rename、schema/anchor/JSON-safe/ID/finite变换与≤256限制、严格JSON1e-9与native transform float32分域、坏新旁车拒空降级/legacy五件empty、外部JSON只可信重建、输入apply/discard与双域草稿/历史规则归[WORKSHOP-R93–R95](../workshop/spec.md)。房屋src/workshop的Recipe/Session/Generator/Store/shell及独立外挂Generator不改，32类96态v002不重制，R40静态无Script/256层碰撞/水下及世界派生排除职责不变。

隐藏DockTab仍参与minimum，长note/status在17px窄宽wrap使scene_assembly content2864高；只在本地加ScrollContainer min-height160隔断，1920×969原生窗口screen2779→836、preview2548→605，sidebar只rightExpand。不降52%宽/60%高、18/16字号或图库160下限，不声称OSfocus已测。

### 当前真实证据与输入域

五项同minimal工程串行外层 `/Users/zyq/work/sea-work/verification/20261118-024220-workshop-embedded-attachments-reviewed-b8df68/report.json`：

| 入口 | checks / failures | 本轮签署范围 |
|---|---:|---|
| editor-workshop-attachments | 323 / 0 | 内嵌Editor原生GUI链与直接事务/现场context分列 |
| workshop-attachments | 129 / 0 | 逻辑、严格快照/损坏负例、八件保存，直接调用 |
| editor-workshop-upgrade | 1506 / 0 | 当前房屋/颜色/槽/导航兼容 |
| editor-scene-assembly | 159 / 0 | 当前装配/双实例桥接兼容 |
| editor-building-attachments | 328 / 0 | 旧内部独立API兼容，不恢复为推荐入口 |

import/各项exit0、passed=true、completion_marker=true、unexpected_errors=[]、source_consistent=true。另 `/Users/zyq/work/sea-work/verification/20261118-025131-workshop-embedded-attachments-reviewed-switch-af2d96/report.json`：switch336/0，import/editor exit0、completion_marker=true、unexpected_errors=[]；65项GDS交接一致性有完整隔离副本81/80个GDS当前逐字节比对补强，均无差异，计数域不混用。

内层实际Glob为同批 `project/outputs/workshop_attachments_editor_report.json` / `workshop_attachments_logic_report.json`，不是 `workshop_attachments_report.json`。七PNG为embedded_live一张，加layout/gallery各1280x800、1000x700、860x600三档；请求尺寸与真实Control/native窗口分列。新GUI用Window.push_input+warp_mouse同步ack/native drag query，不是人工/Input.parse/OSfocus；参数直接准备/read-only pick、logic/matrix/scenecontext直接调用分别登记，不称每条全GUI。旧328只修identity引用、不改旧断言。

失败简史保留typedPanel/anchor/JSON equality、preview split/sidebar/rightDock minimum、旧Input.parse motion未ack改定向WindowGUI、review两个P2（同值手调误判undo/已删缓存误阻保存）与fixture invalidrefs/退出泄漏清理后重跑；旧失败不删、不改签绿。人工全轴/其它viewport/OSfocus、生产Main、性能、license/art未签；未运行生产Main或关闭PID4359。本任务仅改授权六文档，不改code/registry/art_source/memory/currentruntime，不跑contracts/Godot。运行清单15目标归另一任务，当前sync/check数字待主线程实跑后追加，不预填旧值。[既有开发记录11/18节](../../development/2026-11-16_building_attachments.md)；审阅页 `outputs/workshop_attachments_embedded_review_20261118/index.html` 由另一代理制作，本任务不代做或签已验。

### 主线程最终回填

15项定点运行字节登记全部一致、1868非目标entry字节未动；当前五项323/129/1506/159/328均0失败、exit0、unexpected=[]、source_consistent=true，独立switch336/0。主线程已目检同批1280图库与860编辑图，工坊同预览整楼及外挂可见；自动窗口GUI与人工手感边界不变。房屋内核/Main/project无diff，未提交推送。

全库实际sync539/check540 issues、均exit1（46功能、1105源、1883运行资源），不因专项通过签全工程绿。候选输出根 `scenes/workshop_attachments` 首次另存前不存在的扫描问题仍保留，未造空目录；本轮World/Workshop条款与入口无新增错误，其他hash漂移和历史断链未批量重签。原始门禁日志在工程外 `sea-work/workshop_attachments_embedded_20261118/`。交付为 `outputs/workshop_attachments_embedded_review_20261118/index.html` 及同名ZIP，源图报告hash与ZIP完整性已静态核验，不代签浏览器实测、人工物理输入或生产Main运行。

## 2026-11-19 海上总平面图的设计基线

| 对应设计条款 | 当前状态 | 证据 / 待核验 |
|---|---|---|
| SEA-WORLD-R41 | SEA–01 / V01 底图已归档，供后续重新设计；世界功能状态不变 | [GDD 当前版](../../../GDD_V1.0.md#sea-surface-plan) · [V01 SVG](sea-surface-plan/v01/sea-surface-plan.svg) · [V01 PNG](sea-surface-plan/v01/sea-surface-plan.png)。家园扩建浮台和外海中途泊点仍为提案；本次未改主场景、摆位、导航或运行资源，未做通航验收。核验见[交付记录](../../development/2026-11-19_sea_surface_plan.md)。 |

## 海上屋顶街机维修铺 · 运行接入

| 对应设计条款 | 当前状态 | 证据 / 待核验 |
|---|---|---|
| SEA-WORLD-R42 | 已接入完整玩法场景 `main.tscn`；当前 F5 最小白盒不包含此建筑。西侧甲板可从既有泊位交互链上岸、步行并返船；没有经营交互。 | `rooftop-arcade` / `visual-rooftop-arcade`；[运行记录](../../development/2026-11-19_rooftop_arcade_runtime.md)。室内和阁楼不开放，摆放以 TSCN 为准。 |


## 2026-11-19 独立海面通行白盒

| 对应设计条款 | 当前实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-WORLD-R43 | 最小入口范围内已实现并验证；既有功能条款状态不变 | 平台、楔坡和坡脚的碰撞与通行：`minimal-main` 35/0，真实渲染 42/0；两个组件初摆已登记，参考位不是硬规则。 [开发与证据](../../development/2026-11-19_minimal_main.md)。 |


## 2026-11-19 最小海面入口：海上 3C

| 对应设计条款 | 当前实施与证据 |
|---|---|
| SEA-WORLD-R44 | 专项走过坡脚至泊位，实碰 Ramp 后脱离，回泊下船；位置另见 [摆放台账](placed_positions.md)。 |

[开发与验证](../../development/2026-11-19_minimal_sea_3c.md)。


## 2026-11-19 现成划桨复用与固定木块补充

| 条款 ID | 当前实施与证据 |
|---|---|
| SEA-WORLD-R45 | 默认三个固定木块均核对可见包络与实际阻挡，碰撞及绕行证据见交付。 |

[开发与复验](../../development/2026-11-19_minimal_sea_3c.md#补充复验现成划桨与海面木块)。

## 2026-11-20 正式世界总集成门禁

R05/R07/R44–R45：正式摆位和既有场景未改。候选只试接栈桥与完工平台船体接触实体；未接入、未退役 BlockerSet、GroundSpace 派生或水域查询。 部署状态不变，结果及未验边界见[开发与证据](../../development/2026-11-20_formal_world_integration.md)。

## 2026-11-20 阳光房实体阻挡迁移门禁

R05/R07：正式阳光房无自带碰撞体，派生岸线及水下纯景观边界保留；其他区块暂缓。 详见[实测](../../development/2026-11-20_sunroom_collision_handoff.md)。

## 2026-11-20 正式家园临时试坡（已接入）

| 条款 ID | 当前实施与证据 |
|---|---|
| SEA-WORLD-R46 | `zone1_home_harbor.tscn` 的 `WalkAreas/TemporaryHomeRamp` 已实际接入正式 F5。单实例拥有可见坡体、标识和三角支撑，视觉件不另挡角色。默认启动及实窗试玩 exit 0，18/0；不是旧的内存夹具。没有移动原实例，没修改船、存档或阳光房碰撞盒。[路线、拆除与证据](../../development/2026-11-20_formal_home_ramp.md)。 |

## 2026-11-20 窗前甲板局部支撑

R05/R07：`Walk_zone1_home_dock` 按可见铺板补一个连接段，不移动模型，也不废弃 `GroundBoundary`、`GroundFloor` 或水域 BlockerSet。原内部边线不再拦人，临水外缘仍实碰；见[同机位对照](../../development/2026-11-20_formal_sunroom_deck.md)。


## 2026-11-20 正式 Main 手动海上 3C

R05/R44：原家园栈桥下挂手工可编辑 `BoardHullContact`，随原组件变换走、不依渲染 Mesh 生成。临水窗前保持阶段性局部支撑修复；不替换 BlockerSet 或其他岛屿的数据。 [实窗、碰撞来源和未覆盖范围](../../development/2026-11-20_formal_manual_sea.md)。

## 2026-11-20 晚间正式 Main 复核

R05/R07/R12/R46：GroundSpace 仍从正式场景的 WalkArea 派生地板和外缘体，家园试坡走同一支撑体系。正式场景运行确认船的物理掩码只匹配家园栈桥实体，其余旧轮廓仍参与船中心禁入。证据见[正式 Main 复核](../../development/2026-11-20_3c_structure_audit.md#2026-11-20-晚间--正式-main-现状复核)。

## 2026-11-20 家园场景碰撞接入

| 对应设计条款 | 实施与证据 |
|---|---|
| SEA-WORLD-R47 | 阳光房甲板、庭院、栈桥和试坡具有随场景摆放的实体碰撞。阳光房脚下和主泊位均查无旧层地板。墙体与实体支撑专项 17 项全过，试坡实窗 18 项全过。[运行记录](../../development/2026-11-20_native_home_roundtrip.md)。 |

## 2026-11-20 阳光房栈桥下船区域

| 对应设计条款 | 实施与证据 |
|---|---|
| SEA-WORLD-R48 | 主泊位的 `DockEdge/DockingArea` 已接入，实窗验证区域识别实际船体且船上角色位置变化不影响结果。[验证记录](../../development/2026-11-20_home_docking_hull.md)。 |

## 2026-11-21 建筑组装动画接入

| 条款 ID | 当前实施与证据 |
|---|---|
| SEA-WORLD-R49 | 阳光房提供显式播放入口，正式 Main 仍直接装配完工态。主场景和家园区块场景的摆放保持原文件字节，补墙使用阳光房原碰撞树。实窗回归验证手动航行和上下船。其他建筑接入及正式事件待定。[接入记录](../../development/2026-11-21_sunroom_godot_animation.md)。 |

## 2026-11-21 正式设施碰撞和泊位

| 条款 ID | 当前实施与证据 |
|---|---|
| SEA-WORLD-R50 | 八个固定泊位、升级渔场和三栋景观建筑的船壳扫掠合计 28 项通过。卧室进出与行走 761 项通过。各设施间完整航程和内部路线待验。 [开发与验证](../../development/2026-11-21_main_native_facilities.md)。 |

## 2026-11-22 建筑组件与独立设施归属

| 条款 ID | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-WORLD-R51 | 已实现。`ZoneScene` 递归登记建筑子树中的 WalkArea/LandingPoint，阳光房主甲板、上层、主泊位和 DockingArea 已从 zone1 拆出并挂入 `solar_cabin.tscn`。 | `godot/src/world/zone_scene.gd`、`godot/scenes/facilities/solar_cabin.tscn`；`sunroom-runtime`、`sunroom-surface-collision` exit 0 |
| SEA-WORLD-R52 | 已实现。阳光房 `Facilities` 子树独立拥有菜箱、出货箱、房间入口和带 `facility=solar_cabin` 归属的采集点，各物件继续使用统一 Interactable Area3D 热区；Main 通过建筑实例查找公开设施，不再读取 `zone1/Objects` 旧路径。 | `godot/scenes/facilities/solar_cabin.tscn`、`godot/src/gathering/gather_field.gd`、`godot/src/bootstrap/main.gd`；海上/岸上上下文隔离仍由 `Interactor` 统一过滤。 |

## 2026-11-22 运动中进入泊位并归位

| 条款 ID | 当前实施与证据 |
|---|---|
| SEA-NAV-R33 | 正式泊位交接继续读取船体 `HullCollision` 与 `DockingArea` 的实际重叠。船在推进中进入触发区即可出现“上岸”，按 E 后船体归位至场景 `BoatPark`，没有重新引入中心点或自动航线判定。 |

## 2026-11-22 家园临时试坡撤下

SEA-WORLD-R46 的正式场景试坡已撤下。碰撞专项确认原坡道位置为正常平甲板，旧试坡专项入口已退役，原摆位留作历史记录。[开发与验证](../../development/2026-11-22_sunroom_bridge_collision.md)。

## 2026-11-22 正式设施碰撞与归属复核

SEA-WORLD-R50–R52：固定泊位专项 36/0，主场景探针与泊位专项均退出 0。霓虹花园三座屋顶与花园桥存在导航标为可走、可见模型存在、但无角色碰撞支撑的采样点。打捞台与渔场共用的泊位、收鱼点、绞盘和升级牌仍分挂区块或 Main。横滨与浅水养殖台按整个区块跟随，模型子件、合并网格与泊位仍分开归属。本次盘点保留场景摆位与功能状态。[设施明细与证据](../../development/2026-11-22_main_facility_collision_audit.md)。

## 2026-11-23 正式设施组件归属与实体碰撞

| 条款 ID | 当前实施与证据 |
|---|---|
| SEA-WORLD-R53 | 打捞台、养殖台、横滨、霓虹花园的实体和泊位归入服务组件。固定八泊位与三个景观船壳扫掠通过。三座屋顶和菜园桥的十二处原漏点均命中实体。 |
| SEA-WORLD-R54 | 正式区块的旧模型切换、聚合碰撞和运行时采集摆放入口已撤。场景摆位、逐设施实测和抽样余项见[开发记录](../../development/2026-11-23_facility_scene_alignment.md)。 |

## 2026-11-23 制造区替换旧养殖台

| 条款 ID | 当前实施与证据 |
|---|---|
| SEA-WORLD-R55 | 正式区块已装配新版起始甲板和初始码头，旧总成与其碰撞、固定种植和采集节点退出场景。 [交付及验证](../../development/2026-11-23_workshop_dock.md)。 |

## 2026-11-23 起始种植区与四轮胎护舷

| 条款 ID | 当前实施与证据 |
|---|---|
| SEA-WORLD-R56 | 场景及参考配置已更新，位置台账记录五件固定初始组件与停船标记。 [交付和验证](../../development/2026-11-23_workshop_dock.md#起始种植区与四轮胎护舷)。 |

## 2026-11-23 顶层牧场小屋与分件阻挡

| 条款 ID | 当前实施与证据 |
|---|---|
| SEA-WORLD-R57 | 正式 Main 加载 v010 小屋。墙段和门板实体随相应部件，破损门洞可通，完工门板阻挡。岸上交互实测、屋顶导航、NPC 站位查询与泊位回归通过。小屋修复状态为当前场景会话状态。[交付与证据](../../development/2026-11-23_rooftop_restoration_v010.md)。 |

## 2026-11-23 顶层牧场整套替换

| 条款 ID | 当前实施与证据 |
|---|---|
| SEA-WORLD-R58 | 正式 Main 以 v010 整体替换旧牧场，包括右后方的蓝墙红顶工具棚。区块和手摆根保持原位，新码头供船靠泊，双段折返梯通往八处修复入口。25 个 NPC 站位落在保留铺面上。无窗口专项 1305/0，实窗 1311/0，固定泊位回归 43/0。[交付与证据](../../development/2026-11-23_rooftop_ranch_full.md)。 |

## 2026-11-24 顶层牧场主楼结构深化

| 条款 ID | 当前实施与证据 |
|---|---|
| SEA-WORLD-R59 | 正式场景使用 v011 主楼，继承原码头、梯段、屋面和设施动画。船壳实测、八处修复、落装与 25 个站位通过。无窗口 1426/0，实窗 1434/0，固定泊位 43/0。[交付与证据](../../development/2026-11-24_rooftop_ranch_structure.md)。 |

## 2026-11-24 顶层牧场入口与落装

| 条款 ID | 当前实施与证据 |
|---|---|
| SEA-WORLD-R60 | v012 破损态可登顶，完工后胶囊可从前沿走回接板。搬开的花圃及两株植物在同一新位置落装。八段区域修复、共用落装、温室石基分段阻挡及固定泊位通过。 [交付与证据](../../development/2026-11-24_rooftop_ranch_roof_joints.md)。 |

## 2026-11-24 顶层牧场破损态野生植被

| 条款 ID | 当前实施与证据 |
|---|---|
| SEA-WORLD-R61 | 八区植被随各自修复清理，破损登顶通路、角色往返和完工设施通过实测。无窗口 1529/0、实窗 1539/0、泊位 43/0。 [交付与证据](../../development/2026-11-24_rooftop_ranch_wild_growth.md)。 |

## 2026-11-24 顶层牧场新水线与登顶

| 条款 ID | 当前实施与证据 |
|---|---|
| SEA-WORLD-R62 | 正式牧场楼体下移 1.8 米，码头和停船标记留在原海面交接标高。新梯上下通行、旧档落脚、分区修复和完整落装通过。无窗口 2229/0，实窗 2239/0，正式泊位 43/0。水层专项剩九项均在范围外。[交付与证据](../../development/2026-11-24_rooftop_ranch_submerged.md)。 |
