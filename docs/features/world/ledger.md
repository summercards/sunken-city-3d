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
    "godot/scenes/zones",
    "godot/scenes/world",
    "godot/assets/data/zones.json"
  ],
  "verification": [
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
    "visual-home-lighting"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-WORLD-R01 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-WORLD-R02 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-WORLD-R03 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-WORLD-R05 | 部分实现：zone1 已由组件派生并清理空阻挡；其余区块已接入同一机制，但 zone2/zone3 的行走矩形仍为旧手工数据 | `visual-blockers` 空阻挡 0、漏阻挡 zone1 0.2%；zone4 接缝 12.9% 待区块重做。 [交付记录](../../development/2026-10-26_sea_scene_blockers.md) |
| SEA-WORLD-R04 | 本轮表现与专项通过 | 环境静态鱼、尾鳍、圆环和点击圆盘退役；漂流物旧透明环退役，桶身金属环保留；源烘焙文件未修改，9 个区块 GLB 仅退役匹配的旧装饰三角索引。 [交付记录](../../development/2026-10-23_sea_visual_style.md) |
| SEA-WORLD-R06 | 区域及导航注入端口保留；本轮增加zone_enabled_query | [模块框架](../../development/2026-10-27_modular_framework.md) |
| SEA-WORLD-R07 | 本批实现并验证 | 15片旧荷叶精确退役840三角面，恢复另9片；独立组件与航路专项见本轮记录 |
| SEA-WORLD-R08 | 本轮实现；正式最小范围与独立专项验证 | [本轮交付](../../development/2026-10-27_minimum_loop_and_title.md) |
| SEA-WORLD-R09 | 已实现，场景点击与存读专项验证 | [本轮证据](../../development/2026-10-27_plot_shipping_loop.md) |

## 资源与调用入口

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-WORLD-R10 | 六栋纯景观建筑独立接入zone1；当前实景专项核验 | [制作与验收](../../development/2026-10-28_submerged_neighborhood.md)；正式TSCN持有摆位，MultiMesh基座真实包围盒避让、楼间水道、全屋顶淹没、无互动/碰撞/船阻挡/岸线泡沫 |

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
