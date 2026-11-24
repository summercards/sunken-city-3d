# 海上结构物手动摆放台账

[主文档](../../../GDD_V1.0.md) · [工程约定第 12 条](../../../AGENTS.md) · [世界功能](../world/spec.md)

**规则（2026-11-06 用户指定）：** 主场景 `godot/scenes/main.tscn` 里用户手动摆放的 `transform` 是位置的唯一真值。
本表「参考位」是初次带入时的建议坐标（同时写在 `zones.json` 的 `origin` 里），只作参考，不是验收标准；
「实测位」是用户在编辑器里摆完之后的实际值，两者不一致属正常，**不得改回参考值**。
本表的唯一职责是让每一处偏差都有据可查，由 `python3 scripts/check_placed_positions.py` 校验：
漏行、实测位与 TSCN 不符、参考位与 `zones.json` 不符才失败。

- 新带入结构 → 先在 `zones.json` 写参考位 origin，在本表加一行，实测位先填参考位；
- 用户摆完 → 只更新「实测位」与本行结语，参考位不动；
- `basis` 出现非均匀缩放（三列长度不等）默认给出 WARN。**用户确认过是有意摆的**，在「缩放确认」列写 `有意`
  并注明来源，脚本就不再报；空着或写 `待确认` 时才 WARN。

| 节点（main.tscn） | 区块 id | 参考位（带入时） | 实测位（用户摆放） | 偏差 | 缩放确认 | 现状与结语 |
|---|---|---|---|---|---|---|
| `World/SeaStructures/rooftop_ranch` | `rooftop_ranch` | `(46, -55.92, -52)` | `(-87.471634, -55.92, 6.712494)` | 145.814 m | 等比（无缩放） | 2026-11-06 用户调整平面位置和朝向。2026-11-23 在同一实例内替换为 v010 整栋楼和设施。 |
| `World/SeaStructures/neon_garden_quarter` | `neon_garden_quarter` | `(156.149682, 1.12, 2.473711)` | `(106.55533, -15.869949, 88.88402)` | 101.069 m | 等比（无缩放） | 2026-11-07 18:58 只按当前TSCN同步用户手摆实测。上一行登记值为`(106.55533, -21.726082, 88.88402)`；参考位保持，未改main.tscn。 |
| `World/SeaStructures/floating_rest_stop` | `retired_marine_rest_stop` | `(6.158, -1.134, 51.813)` | `(69.91094, -18.097904, 46.376625)` | 66.19 m | **有意** —— 用户 2026-11-06 口头确认「我手动调的」 | 位置与三轴缩放 1.386／2.418／1.777 都是用户手动摆的，**按实测为准，不再当缺陷**。可航性不因此成立：甲板落在世界 -12 米量级、船位 Y=-12.4096，`floating-shop` 41 项 5 失败、`sea-supply` 37 项 8 失败（[11-02 清点](ledger.md)）仍如实挂着；用户明确「先不管」，故泊位、行走投影与这些断言**都不按参考位重算**，等实际用到补给站停靠时再按实测标高处理。 2026-11-07 降级为旧驿站景观，原模型及用户完整变换保留；不再拥有sea_supply身份、泊位、行走面或补给交互。 |
| `World/SeaStructures/floating_shop` | `sea_supply` | `(147.571356, 1.12, 143.891356)` | `(147.571356, 1.12, 143.891356)` | 0 m | 等比（无缩放） | 2026-11-07 初次带入参考位：按本轮运行探针测得阳光房主体中心东南方向200米计算。正式TSCN拥有后续摆位；根保持静态参考，内部甲板与支撑竖向浮动。 |
| `World/SeaStructures/water_building_001` | `water_building_001` | `(165.07135, 1.12, 143.89136)` | `(171.76233, -8.024703, 160.89743)` | 20.44 m | **有意** —— 统一缩放 1.29 + 旋转，2026-11-17 用户手动摆放 | 2026-11-09 编号001水上普通建筑首次带入；按水上商店东侧参考位放置，中心间隔约17.5米，约留2米外接包络间隙。2026-11-17 用户手动重摆并放大到 1.29 倍、带旋转，参考位不动，实测为准（commit `2ebe65e3`）。 |
| `World/SeaStructures/water_building_002` | `water_building_002` | `(188.57135, 1.12, 143.89136)` | `(190.24971, -24.078953, 159.75792)` | 29.83 m | 等比（无缩放） | 2026-11-10 编号002水上普通建筑首次带入；位于商店东侧建筑列、001东侧，参考中心间隔23.5米，为放大的树冠预留空间。28组件167实例，沿用v003的18树冠体积调整，不新增细节。2026-11-17 用户手动重摆，标高由 1.12 降到 -24.079，参考位不动，实测为准（commit `2ebe65e3`）。不是可玩区块，不新增zones或交互。 |

| `World/SeaStructures/rooftop_arcade` | `rooftop_arcade` | `(148, 1, 163)` | `(148, 1, 163)` | 0 m | 等比（无缩放） | 2026-11-19 初次带入参考位，礼品商亭南侧；后续以主场景手摆为准。 |

历史撤下记录：2026-11-07 用户要求住所暂不制作，已移除本轮新增 `World/SeaStructures/resident_harbor` 实例及区块绑定（原初期参考位与实测位均为 `(38, 0, -32)`）。源场景保留、不纳入当前摆位表；七名NPC转用既有 `rooftop_ranch/NpcStations` 局部Marker，未移动用户原有建筑。

## 校验

```
python3 scripts/check_placed_positions.py
```

2026-11-10 当前实测输出：6 个结构、0 失败、0 WARN。包含三个区块绑定及旧驿站、001、002三个非区块结构；旧驿站缩放已由用户确认为有意摆放。普通建筑不为位置检查创建虚假区块。

## 2026-11-19 默认 3C 白盒入口 `main_minimal.tscn`

旧 `main.tscn` 的六栋位置不动。本入口不参加 Zones，不为平台或斜坡建虚假区块。这里的参考位只记录初摆，实际摆位以后以白盒 TSCN 为准；坡顶与平台的相对接合另由运行专项核验。

| 节点（白盒场景） | 区块 id | 参考位（初摆） | 实测位（当前 TSCN） | 偏差 | 缩放确认 | 现状与结语 |
|---|---|---|---|---|---|---|
| `main_minimal.tscn#Deck` | — | `(0, 0.82, 0)` | `(0, 0.82, 0)` | 0 m | 等比（无缩放） | 2026-11-19 首次带入，未有人手重摆。 |
| `main_minimal.tscn#Ramp` | — | `(0, 0.82, 3)` | `(0, 0.82, 3)` | 0 m | 等比（无缩放） | 2026-11-19 首次带入，未有人手重摆。 |
| `main_minimal.tscn#Boat` | — | `(3.7, 1.12, 7.85)` | `(3.7, 1.12, 7.85)` | 0 m | 等比（无缩放） | 2026-11-19 首次带入的场景初始摆位，不是实时船位；运行 Y 用海面。 |
| `main_minimal.tscn#Ramp/Berth` | — | `(0, 0.6, 4.85)` | `(0, 0.6, 4.85)` | 0 m | 等比（无缩放） | 2026-11-19 初摆，Ramp 局部位置。 |
| `main_minimal.tscn#Ramp/Berth/Shore` | — | `(1.02, 0, 0)` | `(1.02, 0, 0)` | 0 m | 等比（无缩放） | 2026-11-19 初摆，Berth 局部位置。 |
| `main_minimal.tscn#Ramp/Berth/BoatPark` | — | `(3.70, -0.3, 0)` | `(3.70, -0.3, 0)` | 0 m | 等比（无缩放） | 2026-11-19 初摆，Berth 局部位置；仅供安全校验，不吸船。 |
| `main_minimal.tscn#TimberObstacles/TimberA` | — | `(3.7, 0.8, 19.4)` | `(3.7, 0.8, 19.4)` | 0 m | 等比（无缩放） | 2026-11-19 木块初摆，原泊位后方水域，正碰验证；坐标以 TSCN 为准。 |
| `main_minimal.tscn#TimberObstacles/TimberB` | — | `(11.9, 0.8, 20.3)` | `(11.9, 0.8, 20.3)` | 0 m | 等比（无缩放） | 2026-11-19 木块初摆，与 A 留绕行通道，斜碰验证；坐标以 TSCN 为准。 |
| `main_minimal.tscn#TimberObstacles/TimberC` | — | `(-4.5, 0.8, 16.8)` | `(-4.5, 0.8, 16.8)` | 0 m | 等比（无缩放） | 2026-11-19 木块初摆，坡脚另一侧；初摆偏航 14°；坐标以 TSCN 为准。 |

## 2026-11-20 正式家园临时试坡

历史记录（已撤下）。临时试坡于 2026-11-20 首次布置，局部参考位与当时实测位均为 `(2.65, 1.38, 6.2)`，偏差 0 m。2026-11-22 改挂阳光房场景后按反馈撤下。

## 2026-11-20 阳光房往返锚点

- `Landing_main/Arrival` 新旅人和落水返回共用标记。局部初摆参考位及 TSCN 实测位均为 `(0.083375, 0, -5.6845)`，偏差 0 m。
- `SunroomLadderTopAnchor` 对齐木板顶面。局部参考位 `(4.66225, 7.016335, 2.708127)`，TSCN 实测位 `(4.66225, 7.2363, 2.708127)`，向上约 0.220 m。
- `SunroomUpperRestoreAnchor` 随二楼未休整时的梯顶落脚面调整。局部参考位 `(6.83575, 7.016335, -0.814)`，TSCN 实测位 `(6.5, 7.2363, 2.2)`，偏差约 3.04 m。

## 2026-11-20 阳光房栈桥下船区域

- `Landing_main/DockEdge/DockingArea` 相对 DockEdge 的初摆参考位及 TSCN 实测位均为 `(0, 0, 1.15)`，偏差 0 m。区域尺寸由场景碰撞形状保存。

## 2026-11-21 阳光房 1.6 梯脚与附属表现

以下均为 `solar_cabin_surface.tscn` 中的局部位置，参考列为换版前的初摆参考，实测列取当前场景。阳光房总成沿用已有手摆。

- `SunroomRepairAnchor` 与 `SunroomLadderBottomAnchor` 的参考位为 `(4.66225, 2.15, 2.708127)`，实测 `(4.66225, 2.15, 3.08)`，偏差 0.372 m。
- `SunroomDamageAnchor` 的参考位为 `(4.66225, 2.15, 2.708127)`，实测 `(4.66225, 2.15, 3.04)`，偏差 0.332 m。
- `VegetationTurf/Regions/upper_roof_meadow` 的参考位为 `(6.835, 10.847, -0.815)`，实测 `(6.835, 10.834, -0.815)`，偏差 0.013 m。
- `VegetationTurf/Regions/left_parapet` 的参考位为 `(0.04, 7.895, -0.2)`，实测 `(0.37, 7.236, -0.2)`，偏差 0.737 m。
- `VegetationTurf/Regions/front_parapet` 的参考位为 `(1.9, 7.895, 2.725)`，实测 `(1.9, 7.236, 2.31)`，偏差 0.779 m。

## 2026-11-21 设施泊位子节点

下表记录 Marker 在各自父节点坐标系中的位置。正式设施根沿用 Main 手摆。

| 节点（场景与路径） | 区块 id | 参考位 | 实测位 | 偏差 | 缩放确认 | 说明 |
|---|---|---|---|---|---|---|
| `facilities/salvage_station.tscn#Walk_zone1_salvage/Landing_salvage` | zone1 | `(-11.6, 1.33, 12.6)` | `(-11.84749, 1.33, 12.84749)` | 0.350 m | 等比 | 2026-11-23 迁入打捞台，走域局部坐标系与原摆放对应。 |
| `zones/zone2_yokohama_station.tscn#Models/unit_03/Walk_zone2_station/Landing_main` | zone2 | `(2.8, 2.78, 3.807)` | `(2.8, 2.78, 3.457)` | 0.350 m | 等比 | 2026-11-23 换算到西站台局部空间。 |
| `facilities/rooftop_ranch.tscn#WalkAreas/Walk_rooftop_ranch_access/Landing_main` | rooftop_ranch | `(26.4, 57.3, -2.1)` | `(18.36, 57.35, 6.28)` | 11.613 m | 等比 | 2026-11-23 换用新版楼体的木码头。参考位为旧楼原泊位。 |
| `facilities/rooftop_ranch.tscn#WalkAreas/Walk_rooftop_ranch_access/Landing_main/BoatPark` | rooftop_ranch | `(0, -0.30, 1.82)` | `(0, -0.31, 2.65)` | 0.830 m | 等比 | 2026-11-23 相对落脚点，停船位根据真实船壳外移。 |
| `facilities/neon_garden_quarter.tscn#Visual/StairFoot/WalkLeftFloat/Landing_main` | neon_garden_quarter | `(6.613068, 14.11, 2.882)` | `(-0.45, 0, 0.1)` | 16.02 m | 等比 | 2026-11-23 迁入检修浮台。参考位为原屋顶标记换算至浮台局部。 |
| `facilities/rooftop_arcade.tscn#WalkAreas/WalkWestDeck/Landing_main` | rooftop_arcade | `(-1.8, 0.42, -0.76)` | `(-0.75, 0.42, -1.11)` | 1.107 m | 等比 | 2026-11-21 西侧甲板落脚。 |
| `facilities/rooftop_arcade.tscn#WalkAreas/WalkWestDeck/Landing_main/BoatPark` | rooftop_arcade | `(-3.65, -0.30, 0)` | `(-5.45, -0.30, 0.35)` | 1.834 m | 等比 | 2026-11-21 船位随甲板边沿调整。 |
| `facilities/floating_shop.tscn#WalkAreas/Walk_sea_supply_deck/Landing_main/BoatPark` | sea_supply | `(0, -0.3, 4.3)` | `(0, -0.3, 3)` | 1.300 m | 等比 | 2026-11-21 船位随码头边沿调整，运行时船仍处于水线。 |
| `zones/zone5_aqua_platform.tscn#WorkshopStarter` | zone5 | `(0, 1.48, 0)` | `(0, 1.48, 0)` | 0 m | 等比 | 2026-11-23 起始组件接替旧养殖台，泊位随码头组件。 |
| `buildables/workshop_starter.tscn#DeckNW` | zone5 | `(-2.5, 0, 5.075)` | `(0.725, 0, 4.925)` | 3.228 m | 等比 | 2026-11-23 右移一板并向外错开一排。 |
| `buildables/workshop_starter.tscn#DeckNE` | zone5 | `(2.5, 0, 5.075)` | `(5.725, 0, 4.925)` | 3.228 m | 等比 | 2026-11-23 北边与存档内的自建木台相接。 |
| `buildables/workshop_starter.tscn#DeckSW` | zone5 | `(-2.5, 0, 10.075)` | `(0.725, 0, 9.925)` | 3.228 m | 等比 | 2026-11-23 接左侧码头。 |
| `buildables/workshop_starter.tscn#DeckSE` | zone5 | `(2.5, 0, 10.075)` | `(5.725, 0, 9.925)` | 3.228 m | 等比 | 2026-11-23 随固定起始区平移。 |
| `buildables/workshop_starter.tscn#Dock` | zone5 | `(-2.5, 0, 13.825)` | `(0.725, 0, 13.675)` | 3.228 m | 等比 | 2026-11-23 左前侧，靠船边布置四只护舷。 |
| `buildables/kit/workshop_dock.tscn#DockWalk/Berth/BoatPark` | zone5 | `(0, -0.36, 2.48)` | `(0, -0.36, 2.55)` | 0.070 m | 等比 | 2026-11-23 给轮胎留出船壳净空。 |

## 2026-11-22 阳光房菜箱摆位

| 节点（场景与路径） | 区块 id | 参考位 | 实测位 | 偏差 | 缩放确认 | 说明 |
|---|---|---|---|---|---|---|
| `facilities/solar_cabin.tscn#Facilities/home_plot` | zone1 | `(-0.52, 1.38, 8.35)` | `(0.05, 1.38, 8.35)` | 0.57 m | 等比 | 2026-11-22 在阳光房局部空间沿甲板内侧移开护栏。 |

## 2026-11-23 菜园桥 NPC 站位

| 节点（场景与路径） | 区块 id | 参考位 | 实测位 | 偏差 | 缩放确认 | 说明 |
|---|---|---|---|---|---|---|
| `facilities/neon_garden_quarter.tscn#Visual/GardenBridge/NpcStations/residence_garden_bridge` | neon_garden_quarter | `(-5.5, 4.362, 0.4325)` | `(-5.5, 5.05752, 0.4325)` | 0.696 m | 等比 | 2026-11-23 五个站位随桥，根站位抬至土面。 |
| `facilities/neon_garden_quarter.tscn#Visual/GardenBridge/NpcStations/residence_garden_bridge/Work` | neon_garden_quarter | `(0, 0, 0.4)` | `(0, -0.19527, 0.4)` | 0.195 m | 等比 | 2026-11-23 工作站位匹配坡度。 |
| `facilities/neon_garden_quarter.tscn#Visual/GardenBridge/NpcStations/residence_garden_bridge/Door` | neon_garden_quarter | `(3.2, 0, -0.4)` | `(3.2, 0, 0)` | 0.400 m | 等比 | 2026-11-23 出入口锚点移入桥面。 |

## 2026-11-23 顶层牧场小屋摆位

| 节点（场景与路径） | 区块 id | 参考位 | 实测位 | 偏差 | 缩放确认 | 说明 |
|---|---|---|---|---|---|---|
| `facilities/rooftop_ranch.tscn#Models/House_Shell_298` | rooftop_ranch | `(-11.289909, 10.5, -2.879624)` | `(-11.289909, 10.5, -2.879624)` | 0 m | 等比 | 2026-11-23 新版整组模型内，小屋破损帧的局部位姿。原独立小屋实例已由整组部件替换。 |
| `components/facilities/rooftop_ranch/house/v010/rooftop_house.tscn#RepairPrompt` | rooftop_ranch | `(2, 0.07, 3.15)` | `(2, 0.02, 3.85)` | 0.702 m | 等比 | 2026-11-23 复测后移至屋前通道，随小屋移动。 |
## 2026-11-24 顶层牧场入口花圃

| 节点（场景与路径） | 区块 id | 参考位 | 实测位 | 偏差 | 缩放确认 | 说明 |
|---|---|---|---|---|---|---|
| `facilities/rooftop_ranch.tscn#Models/Planter_006_366` | rooftop_ranch | `(14.40, 13.286337, 4.10)` | `(13.12, 13.286337, 4.30)` | 1.296 m | 等比 | 2026-11-24 将落装的花圃和两株植物一起移向入口侧边。本表记录 TSCN 初始隐藏关键帧，完工落点同向移动。 |

## 2026-11-24 顶层牧场下沉装配

| 节点（场景与路径） | 区块 id | 参考位 | 实测位 | 偏差 | 缩放确认 | 说明 |
|---|---|---|---|---|---|---|
| `facilities/rooftop_ranch.tscn#Models` | rooftop_ranch | `(0, 52.04, 0)` | `(0, 50.24, 0)` | 1.800 m | 等比 | 2026-11-24 按截图调整水线。参考位为 v013 模型层局部位置。 |
| `facilities/rooftop_ranch.tscn#SubmergedLevels` | rooftop_ranch | `(0, 50.24, 0)` | `(0, 50.24, 0)` | 0 m | 等比 | 2026-11-24 七层观赏部分首次装配，使用与楼体一致的局部基准。 |
