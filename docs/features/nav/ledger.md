# SEA-NAV · 航行与靠泊 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-nav) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-NAV",
  "status": "partial",
  "owner": "WaterNavigation / Boat",
  "code_paths": [
    "godot/src/navigation/water_navigation.gd",
    "godot/src/navigation/sail_nav.gd",
    "godot/src/navigation/boat.gd",
    "godot/src/navigation/route_ribbon.gd"
  ],
  "verification": [
    "reference-skiff",
    "visual-reference-skiff",
    "boat-water-contact",
    "visual-boat-water-contact",
    "visual-corner-notebook",
    "surface",
    "selftest",
    "framework-modules",
    "minimum-loop",
    "visual-home-lighting",
    "visual-atmosphere",
    "visual-boat-lamp",
    "visual-route-ripple",
    "sail-bounds"
  ]
}
```

## 2026-10-29 可航区扩大为 150m × 150m

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-NAV-R11 | 已实现；可航区 150×150，五个泊位在界内，四角可规划，边界内外判定正确 | [本轮交付](../../development/2026-10-29_sail_bounds_150m.md)。`sail-bounds` 20 项通过；`surface` 30 条航路 456 项仅剩既有种植 Prefab 失败。 |

范围常量只保留一份：`play_scope.gd` 的 `SAIL_BOUNDS`。几何硬界 `WORLD_WATER`（160m）与相机 `pan_bounds`（154m）都改为包住它，`_safe_nav` 兜底网格不再写死 144×136。家园生活区 `HOME_WATER`（55×48）语义不变。

## 2026-10-29 吃水碎浪与桨叶水花

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-NAV-R09 | 本轮补齐接水表现；桨叶入水点改由组件挂点驱动 | [交付记录](../../development/2026-10-29_boat_water_contact.md)。`OarL`/`OarR` 下新增 `BladeContact` 挂点，与桨叶 GLB 外下角对齐；`boat-water-contact` 与 `visual-boat-water-contact` 双方案真实渲染通过，小船专项与装饰/模块回归无新增失败。 |

## 2026-10-28 参考小船替换

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-NAV-R09 | 已接入；包络、原点、桨动画、灯具和真实渲染专项通过 | [交付及基线对照](../../development/2026-10-28_reference_skiff.md)。全世界30条航路完成；surface的种植Prefab断言1项和selftest4项失败与旧Boat一致，保留既有问题，不改无关玩法。 |

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-NAV-R01 | 正式WaterNavigation查询/求路/验段；绕障模块和surface通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-NAV-R02 | 本轮实现；正式最小范围与独立专项验证 | [本轮交付](../../development/2026-10-27_minimum_loop_and_title.md) |
| SEA-NAV-R03 | 30条有向航路全部通过，旧路接管由click/surface覆盖 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-NAV-R04 | 已实现并专项核验 | [框架交付记录](../../development/2026-10-27_modular_framework.md)；[模块接口约定](../../architecture/module_contracts.md) |
| SEA-NAV-R05 | 本轮实现；正式最小范围与独立专项验证 | [本轮交付](../../development/2026-10-27_minimum_loop_and_title.md) |

## 资源与调用入口

- [godot/src/navigation/water_navigation.gd](../../../godot/src/navigation/water_navigation.gd)
- [godot/src/navigation/sail_nav.gd](../../../godot/src/navigation/sail_nav.gd)
- [godot/src/navigation/boat.gd](../../../godot/src/navigation/boat.gd)
- [godot/src/navigation/route_ribbon.gd](../../../godot/src/navigation/route_ribbon.gd)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

is_open_water / plan_route_to / valid_route / segment_clear / invalidate；shape_query；Boat.sail_to / sail_to_point / remaining_route；segment_clear、speed_multiplier 注入；arrived、navigation_blocked。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；兼容字段仅供已有调试工具，不作为新增业务写入口。

## 验证记录

当前入口：`python3 scripts/run_verification.py surface selftest framework-modules`。

2026-10-23 历史实测结果见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 surface、selftest 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

正式航路算法位于 src/navigation；WaterNavigation 拥有水域判断、网格和路线验证，Boat 逐步调用 segment_clear。30条路线回归只是样本，不代表全海域穷举。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 太阳能木屋接入影响验证（2026-10-25）

SEA-NAV：main 泊位随新栈桥移动，打捞台泊位保留；新增平台岸线范围，30 条跨泊位航路通过。 验证入口：`python3 scripts/run_verification.py surface click management selftest visual-solar-cabin`；[证据](../../development/2026-10-25_solar_cabin_integration.md)。

## 太阳能木屋 v004（2026-10-25）

SEA-NAV：同步新桥泊位及扩展岸线，30条航路本轮通过；未改变独立绞盘台泊位。 [当前证据](../../development/2026-10-25_solar_cabin_v004.md)。

## 太阳能木屋 v005（2026-10-25）

SEA-NAV：主桥泊位、登岸点及岸线随桥端向+Z延伸1.587米；30条跨区路线本轮通过，其他泊位不变。 [当前证据](../../development/2026-10-25_solar_cabin_v005.md)。

## 2026-10-26 功能与健康审计

SEA-NAV-R01/R02/R03：surface 30条有向航路503项通过，含30/60/120FPS抵达一致性；selftest岛心/绕行/泊位航线等另有失败，几何判据与正式专项冲突，需要核对当前场景，不能直接认定全部穿模或豁免。

[本轮审计与证据](../../development/2026-10-26_feature_architecture_save_3c_audit.md)。本轮只审计和登记，未修改玩法实现。

## 2026-10-27 模块框架落地

正式航路算法位于 src/navigation；WaterNavigation 拥有水域判断、网格和路线验证，Boat 逐步调用 segment_clear。30条路线回归只是样本，不代表全海域穷举。

新增条款 SEA-NAV-R04 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。

## 2026-10-27 航行指令提示静默

按用户要求，划船移动不再弹提示条：删除「划向那里」「启航 · <区块>」「启航 · <区块> · <上岸点>」「驶向鱼群」「驶向<漂流物>」五处发出指令时的复述（`godot/src/bootstrap/main.gd`）。移动意图改由航线丝带与落点准星表达。

保留「抵达」「已停船」等结果提示与「无法到达」「这里没有可通行航路」等拒绝原因；`hud.toast` 本体与纸条样式未改。

SEA-NAV-R01/R02/R03 实现未改动，本轮回归 click、surface、selftest 均退出 0：[记录](../../development/2026-10-27_sail_toast_silence.md) · `sea-work/verification/20261027-111208-verification-83e9e6`。真实窗口目视复核未执行，文案已按源码检索确认清除。

## 2026-10-27 当前最小循环与开始画面

本节及本轮修改条款优先于下方保留的历史范围。默认发布配置只开放家园生活循环；旧全功能验证须显式 `--full-world`，不能代替最小版本验收。接口、迁移及实测见[交付记录](../../development/2026-10-27_minimum_loop_and_title.md)。

## 2026-10-28 家园箱子与夜灯修复

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-NAV-R06 | 已实现；真实渲染和相关集成检查通过，设备边界单列 | [本轮实测](../../development/2026-10-28_home_lighting_recovery.md) |

[交付记录](../../development/2026-10-28_home_lighting_recovery.md)。

## 2026-10-28 船灯与夜航表现

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-NAV-R07 | 已实现；复用SEA-SCENE-SBR-LANTERN，局部光和水面倒影随船同步，白天熄灭；移动与生活循环回归见本轮记录 | [交付与实测](../../development/2026-10-28_cozy_daypart_atmosphere.md) |

R06的旧“完全黑船”断言更新为关闭船灯后仅受冷色月光；局部光的增量颜色必须偏暖。灯的Light3D范围包围盒不再混进船模型像素测量。

## 2026-10-28 外舷夜航照水灯

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-NAV-R08 | 已实现；外舷短杆与下照暖色实灯，双方案纯水区域开关差分、远近衰减与随船转向/离开验证 | [设计与本轮验收](../../development/2026-10-28_boat_navigation_lamp.md) |

船灯由Omni改为Spot，捕获按Light3D基类筛选home_lamps/boat_lamps分组；仍只有一个船灯，未新增灯光强度写入者。沿用原灯笼资产与boat/furnishing/bow_lantern实例ID；木杆为Boat运行包装内置几何配件。未改灯笼制作源、GLB或授权pending状态。


## 2026-10-28 HUD与笔记表现接线

泊位外观和命中接口由SEA-UI-R38承接：同套手绘船锚，去名称，30→50px靠近放大并变暖金，点击半径26px。稳定zone/landing及双向登船/靠岸、自动登陆语义保留。

对应SEA-UI-R35–R38；[本轮交付](../../development/2026-10-28_corner_hud_notebook.md)。本功能整体状态与玩法边界保留。

## 2026-10-28 航线虚线移除与点击水纹

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-NAV-R09 | 已实现；航路虚线整条删除，终点改贴浪扩散水纹，点击落点复用同一套；真实渲染 4 相位与点击回归通过 | [本轮交付](../../development/2026-10-28_route_ripple_replaces_dashed_line.md) |

`route_ribbon.gd` 保留 `show_route(points, water_y)` 签名，只取航路末点；`debug_band_count()` 恒 0 供断言盯着航段不回潮。`click_reticle.gd` 还原为岸上走位落点环；`_try_sail_to` / `_select_landing` 不再叠加准星。新增着色器 `godot/shaders/water_ripple.gdshader`。航速、转向、碰撞、泊位、寻路与 30 条航线数据未改动。

验证入口：`python3 scripts/run_verification.py visual-route-ripple click --full-world`。`click` 的三条跨区用例依赖 `--full-world`，属既有前提差异。

## 2026-10-29 家园建造接入

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-NAV-R10 | 已实现；相关专项通过，详细范围以交付记录为准 | [本轮交付](../../development/2026-10-28_building_delivery.md) |
