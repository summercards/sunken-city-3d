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
    "boat-unstick",
    "visual-boat-unstick",
    "facing-interaction",
    "visual-facing-interaction",
    "gift-kiosk",
    "control-feel",
    "keyboard-control",
    "rowing-fit",
    "visual-rowing-fit",
    "visual-rowing-game",
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
    "sail-bounds",
    "sea-supply"
  ]
}
```

## 2026-10-29 可航区扩大为 150m × 150m

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-NAV-R11 | 已实现；开放海域、远处段校验与显式场景边界专项通过 | [本轮交付](../../development/2026-10-29_open_ocean_building.md) |

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

## 2026-10-30 自建上岸提示收敛

本轮只调整SEA-BUILDING-R17 / SEA-UI-R38的提示密度与展示生命周期；所有外露合法边的landing_data、动态泊位ID与原航行/自动登岸/返船命令保留。当前返船入口不受普通候选采样挤掉，提示隐藏时仍可点击实际板面登陆。[本轮验证](../../development/2026-10-30_sparse_landing_markers.md)。

## 2026-10-31 结构物泊位

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-NAV-R12 | 已实现；`sea_supply` 的 `main` 泊位复用唯一「航行→抵达→上岸」链路，站立点 y=1.38 落在甲板、船位 y=1.12 在甲板外 2.35 米开阔水面（该点 `_is_open_water` 为真）、靠岸边在两者之间；从家园起航可规划出 6 点折线。 | `sea-supply` 专项与 `sea-supply-probe` 实测；[接入记录](../../development/2026-10-31_sea_supply_station.md) |

## 2026-11-04 · 座位与双桨适配

| 对应设计条款 | 当前实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-NAV-R13 | 已实现；中排座板坐姿、屈膝避板、双手消费真实握点、按体型真实臂长与船体摇摆同步；停船、取消、上下船和恢复共用同一座点 | `rowing-fit`、`visual-rowing-fit`、`visual-rowing-game`及相关回归；[当前实测与原生画面](../../development/2026-11-04_rowing_seat_and_grips.md)。触摸/手柄与全部外观组合未执行，整体功能状态不因本次局部修复上调。 |

最终实测：6入口19028项、0失败，exit均0；正式场景22项与两套海面57项为真实渲染。全局文档门禁仍因范围外既有登记问题exit1，未强行同步索引；详见本轮交付记录。

## 2026-11-04 · 用户反馈后将船桨前移

| 对应设计条款 | 当前实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-NAV-R14 | 已实现；两桨及桨架从z=0.36前移至0.55m，握柄向舷内补9cm，配合缩小摆幅和抬桨范围，坐点与桨长保持。真实BladeContact仍入水、停船不再溅水。R13原坐姿与手掌到点结果仅为历史基线，不能覆盖本次手臂扭转反馈。 | [本轮实测、近景及旧版负向对照](../../development/2026-11-04_rowing_arm_direction.md)；`visual-rowing-fit` / `visual-rowing-game` / `boat-water-contact`。原始Blend/GLB和商业授权pending保持。 |

## 2026-11-05 键盘手动划行

| 对应设计条款 | 当前实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-NAV-R15 | 已实现；`Boat.set_drive/release_drive/stop_drive` 驱动方向与速度，位移仍过 `_clear()`，撞岸停住并抛 `navigation_blocked`，松手减速到零后退出手动、由 SEA-MOVE 切回 `boat_idle`；点目标航行主动清手动，两者不同时写船位 | `keyboard-control`（划行、松手停稳、撞岸仍在开阔水面、待机↔航行切换）；`rowing-fit` 76631 项、`board-click`、`dock-seed` 复跑通过；[本轮交付](../../development/2026-11-05_keyboard_control.md)。手动模式不自动靠泊，靠岸仍需点登陆标记或按 E。 |

## 2026-11-05 · 尺度联动

| 对应设计条款 | 当前实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-NAV-R16 | 已实现；桨轴与桨架前移 0.18 m 到船局部 z=0.73，`RowingSeat` 保持 (0,0.6025,0.32)，桨长/入水/航速/靠泊不变 | `rowing-fit`：手掌-握柄偏差 0.0004 mm、手掌前向 +309.1 mm、肘前向 +80.9 mm（改前为 −72.6 mm）、肘折叠 107.0°（改前 136.5°）、肘轴误差 2.46e-7、桨叶 y −0.0678…+0.330；`visual-rowing-game` 8 机位逐图目视。[本轮交付](../../development/2026-11-05_character_scale_150.md) |


## 2026-11-05 手动划行手感

| 对应设计条款 | 当前实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-NAV-R17 | 已实现；`_yaw_rate` 按 4.6 rad/s² 建立、舵效随船速缩放、航迹按 0.16 s 滞后并夹在 8° 内、低速软收尾；位移仍过 `_clear()`，撞岸停住 | `control-feel`（首帧 0.077 → 0.2 s 0.92 rad/s、侧滑 6.9°、滑行 1.48 m、不回弹）；`ocean`、`boat-water-contact`、`rowing-fit`、`keyboard-control` 复跑通过；[本轮交付](../../development/2026-11-05_control_feel.md)。自动航线的转向与到站契约未改。 |


## 2026-11-07 浮动商亭靠泊

| 对应设计条款 | 当前实施状态 | 证据 / 待核验 |
|---|---|---|
| SEA-NAV-R18 | 复用sea_supply/main与既有靠泊上岸链路；stand/edge跟甲板、boatPark锁实际水线；Zones以支撑事件更新公开快照，旧驿站仅保留R13几何航路避让 | [本轮记录](../../development/2026-11-07_gift_kiosk.md)。家园至泊位4点合法航路、泊位不压阻挡、实际靠妥上岸/补给/回船与船上脱离支撑通过；最终7129/0、真实渲染53/0，board-click/minimum-loop回归exit0。 |

## 2026-11-07 顶岸手动脱困

| 对应设计条款 | 当前实施状态 | 最终实测证据 / 边界 |
|---|---|---|
| SEA-NAV-R19 | 已实现并通过最终单体合批及真实shore渲染；120Hz子步，碰撞只停平移/速度、保留manual/yaw，Main不退出驾驶；锁存至合法划开0.1m或驾驶结束，stop/place/sail清理。尾流取实际航迹方向，自动碰撞仍停 | `D:/projects/sea-work/verification/20261107-165822-movement-feel-final-9b7646/report.json`11项全PASS，boat及visual各153459/0但该批visual仅单体；`D:/projects/sea-work/verification/20261107-170723-movement-feel-render-final-950cd8/report.json`的`visual-boat-unstick`163769/0真shore、13PNG，与visualfarm647/0双PASS/exit0、unexpected_errors空。主任务已ViewImage目检最新boatsequence，转头离岸可见、无教程；不再待渲染。[总交付与证据分层](../../development/2026-11-07_movement_feel_refinement.md)。 |

165822的visual未设shore环境变量、仅单体；nonheadless直接调用`real_shore`修正后的170723已补齐真实岸线，不倒改旧批覆盖。163769包含单体153459，不重复相加。172123最新smoke的facing102/0 PASS证明NPC/dive新装配可启动，不等于五项兼容全过；171743六compat仅actor-presentation PASS，click32/3、board12/0、dock22/0、save10/0、water41/0均runner FAIL（当时潜水并发重构、本地WorldEnvironment缺失），新版Main接DiveSession后的172517-movement-current-compatible-8e5f98五项已全部runner PASS（board12/0、dock22/0、save10/0、boat-water-contact41/0、shift56/0），exit0且无unexpected_errors；旧click潜水三项本轮不代签。功能保持`partial`，R18不改；主任务已执行sync20 issues/普通check21，未强刷哈希，placed positions4项PASS/0warnings及本轮diffcheck通过，详见总交付。GDD由主任务维护，此回填不改生产/registry/hash/TSCN。

## 2026-11-09 规划器端点容差

| 对应设计条款 | 当前实施状态 | 最终实测证据 / 边界 |
|---|---|---|
| SEA-NAV-R20 | implemented；`nearest_open_water()` + 起点/落点容差写入 `water_navigation.gd`；起点越界最多抬 2.6 m、落点最多抬 1.8 m，抬不出去仍如实返回空 | `dock-hotspot` 31/0 PASS（`D:/projects/sea-work/verification/20261109-171130-dock-hotspot-r6-f1015c/report.json`；终版复跑 `D:/projects/sea-work/verification/20261109-181016-final-regress-b44d74/report.json`，同批 `camera`、`dock-seed`、`board-click`、`interaction-reach`、`interact-focus` 亦全 PASS）；同一用例在改动前 11 项失败、含「无法到达该泊位」（`.../20261109-171040-dock-hotspot-baseline3-836e50/report.json`）。`ocean`、`board-click`、`sea-supply`、`interaction-reach`、`interact-focus`、`dock-seed` 复跑 PASS；`building-ocean` 的「recipe available aboard」为改动前既有失败（已用暂存还原验证）。[本轮交付](../../development/2026-11-09_dock_hotspot_and_zoom_range.md)。 |
