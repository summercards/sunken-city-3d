# SEA-NAV · 航行与靠泊

[主文档中控](../../../GDD_V1.0.md#sea-nav) · [本功能账本](ledger.md)

设计修订：r1（2026-10-23 工程拆分，未更改玩法数值）。所属系统：3C。
范围来源：主文档保留的全局设计、拆分前文档与当前代码核对；下面明确区分目标与实现边界。

## 功能目的与边界

正式或规划入口：点击水面或选择区块泊位。

本功能以这一玩家行为或工程交付闭环为管理粒度，内部操作作为设计条款逐项承接；不按脚本数量拆功能。跨功能前置和关系由主文档本行统一维护。

## 设计条款与验收标准

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-NAV-R01 | 路线避开岸线和障碍；航线展示与实际航行目标一致。 |
| SEA-NAV-R02 | 航速上限2.6米/秒（原3.4），转向上限1.8弧度/秒（原0.95），保留加减速及靠泊制动，禁止传送替代航行。 |
| SEA-NAV-R03 | 手动输入和新目标能够接管旧航线，30 条有向路线保留回归。 |
| SEA-NAV-R04 | 行动范围先判合法水域，路线解决绕障，真实位移逐段复核；场景形状由 shape_query 注入，几何变更必须 invalidate。 |
| SEA-NAV-R05 | 最小版本合法航区为x[-18,37)、z[-12,36)，同时用于范围检查、导航网格和逐段验证；仅太阳房、家园补给站与浅水平台可抵达。 |

## 所有者、接口与数据

状态/交付所有者：**WaterNavigation / Boat**。正式代码和资源入口：

- [godot/src/navigation/water_navigation.gd](../../../godot/src/navigation/water_navigation.gd)
- [godot/src/navigation/sail_nav.gd](../../../godot/src/navigation/sail_nav.gd)
- [godot/src/navigation/boat.gd](../../../godot/src/navigation/boat.gd)
- [godot/src/navigation/route_ribbon.gd](../../../godot/src/navigation/route_ribbon.gd)

读取上述所有者的公开查询，修改通过其命令或交互入口；事件由拥有该状态的对象发出。具体公开方法、信号和持久化字段见本账本的接口清单。原有稳定 ContentID、场景 ID 和存档键保持不变，重命名须另做迁移。

共享资源的所有权以被依赖功能为准。本功能引用它们，不复制背包数值、资产记录或其他功能规则。规划中的接口尚无实现时必须先补契约再编码。

## 当前实现与待完成边界

正式航路算法位于 src/navigation；WaterNavigation 拥有水域判断、网格和路线验证，Boat 逐步调用 segment_clear。30条路线回归只是样本，不代表全海域穷举。

2026-10-27 接口：is_open_water / plan_route_to / valid_route / segment_clear / invalidate；shape_query；Boat.sail_to / sail_to_point / remaining_route；segment_clear、speed_multiplier 注入；arrived、navigation_blocked。

详细所有权、状态转换与扩展方法见 [模块接口约定](../../architecture/module_contracts.md)；实测范围见 [框架交付记录](../../development/2026-10-27_modular_framework.md)。原目标中尚未实现的内容保持登记，不因架构拆分自动升级完成度。

## 验收入口

通过主文档定位本功能后执行账本列出的检查。正常、拒绝、取消/重复、存档恢复均按适用范围记录；真实渲染、听验和设备项单列。本次使用统一 runner 的隔离存档项目，不能直接拿玩家存档做测试。

## 来源与交付记录

- [拆分前完整主文档](../../archive/pre_split_20261023/GDD_V1.0.md)
- [拆分前功能计划](../../archive/pre_split_20261023/功能重做计划.md)
- [本次工程拆分记录](../../development/2026-10-23_feature_split.md)
- [docs/船体转向与寻路诊断_2026-10-19.md](../../../docs/船体转向与寻路诊断_2026-10-19.md)

## 2026-10-27 当前最小循环与开始画面

本节及本轮修改条款优先于下方保留的历史范围。默认发布配置只开放家园生活循环；旧全功能验证须显式 `--full-world`，不能代替最小版本验收。接口、迁移及实测见[交付记录](../../development/2026-10-27_minimum_loop_and_title.md)。

## 2026-10-28 家园箱子与夜灯修复

| 条款 ID | 规则 |
|---|---|
| SEA-NAV-R06 | 船体、桨、网与细节均接收场景真实灯光，取消旧不受光材质与蓝色/自发光补偿；日光消失且离开局部灯范围时变暗，进入暖色局部灯后重新受光。 |

[本轮交付](../../development/2026-10-28_home_lighting_recovery.md)。

## 2026-10-28 船灯与夜航表现

| 条款 ID | 规则 |
|---|---|
| SEA-NAV-R07 | 船头挂一盏已有灯笼组件，使用真实OmniLight3D照亮船身；灯与船体同步移动和摇摆，灯光强度由SEA-OCEAN的DaylightRig统一按时段控制。暖色水面倒影由渲染器对真实灯直接计算，不另建灯位模拟层。不得改动航速、路线、吃水或碰撞；R06的关灯暗船用例保留，并允许最新夜海的冷色环境光。 |

[本轮交付](../../development/2026-10-28_cozy_daypart_atmosphere.md)。

## 2026-10-28 外舷夜航照水灯

本节替代R07中船灯采用OmniLight3D的硬件类型，原灯笼AssetID、实例ID、时段归属和导航规则保持不变。

| 条款 ID | 规则 |
|---|---|
| SEA-NAV-R08 | 船头左外舷采用短木杆挂灯，真实光源高出静水面约1.17m；有遮光方向的SpotLight3D向下、向外照水，兼顾近船水面可见度并避免照白箱子和整块船板。灯具、灯杆与光源随船移动、转向及摇摆，DaylightRig仍为强度唯一写入者。保留真实阴影、距离衰减；不得用屏幕光斑、水面自发光或灯位模拟代替。上午、中午、傍晚日照和玩家调参不变。 |

[设计与实景验收](../../development/2026-10-28_boat_navigation_lamp.md)。


## 2026-10-28 HUD与笔记表现接线

泊位外观和命中接口由SEA-UI-R38承接：同套手绘船锚，去名称，30→50px靠近放大并变暖金，点击半径26px。稳定zone/landing及双向登船/靠岸、自动登陆语义保留。

对应SEA-UI-R35–R38；[本轮交付](../../development/2026-10-28_corner_hud_notebook.md)。本功能整体状态与玩法边界保留。

## 2026-10-28 航线虚线移除与点击水纹

本节替代 R01 中「航线展示」的表现实现：设计条款仍要求路线与实际航行目标一致，但**不得再在海面上绘制贯穿航路的线性路径**。

| 条款 ID | 规则 |
|---|---|
| SEA-NAV-R09 | 航行时不在海面铺航路虚线或任何贯穿式路径指示；目的地仅以贴浪面的扩散水纹表达（细白弧、从中心外推、循环播放），不得高于水面或脱离浪线漂浮。点击水面立即在落点散开同一套水纹，且一次点击只产生一组，不叠加准星或光环。航行中的方向与绕行由船体本身表达。水纹不得改变航速、转向、碰撞、泊位、寻路与航线数据；路径规划、绕障与移交接口保持原状。 |

[本轮交付](../../development/2026-10-28_route_ripple_replaces_dashed_line.md)。

## 2026-10-28 参考小船替换

| 条款 ID | 规则 |
|---|---|
| SEA-NAV-R09 | Boat通过稳定reference_skiff.tscn加载12类独立组件，船体包围盒和水线沿用旧船；两支正式木桨挂在Model下，沿用单一划桨相位、转向差异与平滑收桨，随船体起伏。既有灯笼实例ID、外舷SpotLight和DaylightRig写入权保留；不改航速、导航、泊位、角色登船锚和存档字段，不把基础船外观替换标成船只升级外观完成。 |

[源、实景与新旧船对照](../../development/2026-10-28_reference_skiff.md)。

## 2026-10-29 可航区扩大为 150m × 150m

本节替代 SEA-NAV-R05 中的「最小版本合法航区」范围，R05 其余内容（同一矩形同时用于范围检查、导航网格与逐段验证）继续有效。R01–R04、R06–R10 不变。

| 条款 ID | 规则 |
|---|---|
| SEA-NAV-R11 | 按海上自由建造最新范围取消固定150m可航矩形与160m几何硬界；默认allowed_area为空，有限的无障碍海面均可航行，HOME_WATER仍只负责补给生成。清水直线航路用解析段校验；有障碍时在本趟起终点周围构建有工作预算的局部网格并逐段验证，不按整个海洋分配网格。显式场景仍可注入allowed_area；旧SAIL_BOUNDS/WORLD_WATER仅历史工具参考。远处合法船位读档不回位，实际建筑仍阻挡 |

[本轮交付](../../development/2026-10-29_sail_bounds_150m.md)。

## 2026-10-29 家园建造接入

| 条款 ID | 规则 |
|---|---|
| SEA-NAV-R10 | 施工开始即预留动态木板水面阻挡、invalidate导航缓存，保护原泊位通道与当前船位置；平台完工后重定位落入阻挡范围的海面目标，既有航线由逐步segment_clear检查。 |

[交付与实测](../../development/2026-10-28_building_delivery.md)。

## 2026-10-29 海上自由建造补充

本轮SEA-NAV-R11覆盖前文“同一固定矩形用于正式航区”的历史范围；R01–R10的实际避障、靠泊与速度契约保留。SEA-BUILDING-R13的派生泊位复用原航行→抵达→上岸流程，不增加第二份权威船位。[本轮交付](../../development/2026-10-29_open_ocean_building.md)。

## 2026-10-31 海上结构物泊位

| 条款 ID | 规则 |
|---|---|
| SEA-NAV-R12 | 结构物泊位复用唯一的「航行 → 抵达 → 上岸」链路（`_select_landing` → `_sail_to_landing` → `boat.sail_to` → `_on_boat_arrived` → `_step_ashore`），不新增第二条靠岸通道，也不写第二份权威船位。锚点三件套必须自洽：`landStand` 落在该结构自己的可行走面上（高度误差 ≤ 0.01 米）、`boatPark` 在该结构水面阻挡之外的开阔水面且与甲板外沿留出船宽、`dockEdge` 位于两者之间。远海可达性用同一套航路规划验证：从当前船位能规划出非空折线才算可停靠。<br>首个实例：`sea_supply` 的 `main` 泊位（船位离中心 9.85 米，在 7.5 米半深甲板之外）。 |

## 2026-11-04 座位与船桨适配

本条按用户最新要求覆盖参考小船R09中“不改角色登船锚”的旧限制；船体、水线、速度及路线仍保持。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-NAV-R13 | 正式reference_skiff.tscn拥有中排座点与双桨装配；现有独立桨组件增加不可见Grip挂点。整支桨沿杆轴缩短至原长82%（约3.164m→2.595m），握柄向舷内延长至桨轴内约0.87m，桨架与转动轴同步移至船局部z=0.36m；固定在船舷上，不随手掌反向移动。停船双桨在可握范围内休息，划动由原单一相位/出力/转向差异驱动，船桨、座位及角色纯表现共用船体摇摆。BladeContact随真实桨叶变换，仍需入水并在回桨抬出水面。Boat只提供boarding_position/rowing_pose只读查询，不接管角色骨骼，不新增船只升级或存档字段。 |

[交付、实景与验证](../../development/2026-11-04_rowing_seat_and_grips.md)。

## 2026-11-04 用户反馈后的桨架前移

| 条款 ID | 规则与验收 |
|---|---|
| SEA-NAV-R14 | 按最新反馈将双桨转轴及桨架沿角色面向的+Z前移：z=0.36→0.55m，转轴y=0.62m、桨架y=0.60m；现有中排坐点不再移动。保持桨长82%，将实例轴向偏移改为±0.210330m、舷内握距约0.96m，摆动幅度0.06rad、倾角0.36±0.14rad，使握点完整周期留在肩前、手臂自然屈伸。桨架仍固定在船舷，BladeContact随真实桨叶入水；保留航行/转向/水线和旧档契约。本条覆盖R13的旧位置/角度参数，不覆盖原资产授权pending。 |

[本轮实景、前后对照与实测](../../development/2026-11-04_rowing_arm_direction.md)。

## 2026-11-05 键盘手动划行

| 条款 ID | 规则与验收 |
|---|---|
| SEA-NAV-R15 | 船上按方向键直接手动划行：方向折算为世界期望航向（船头 -Z），转向复用 `TURN_RATE`，加/减速复用 `ACCEL`/`BRAKE`，并保留 30% 最低推进。位移必须通过 `_clear()` 岸线判定；撞岸立即停、抛 `navigation_blocked`，与自动航线共用同一条边界。松手只清方向，速度按 BRAKE 收敛，**归零才退出手动**，随后由 SEA-MOVE 把状态切回 `boat_idle`。点目标航行（`sail_to`/`place_at`）主动清手动，两者不同时写船位；靠泊与泊位朝向规则不变，手动模式不自动靠泊。 |

[交付与实测](../../development/2026-11-05_keyboard_control.md)。

## 2026-11-05 尺度联动（追加）

| 条款 ID | 规则与验收 |
|---|---|
| SEA-NAV-R16 | 角色放大 1.5× 后重解双桨装配：`RowingSeat` 保持船局部 `(0, 0.6025, 0.32)`（仍是中排座板前半部，座板顶面 0.6025）；桨转轴 `OarL/OarR` 与桨架 `oarlock_038/039` 由 z=0.55 前移到 **z=0.73**（+0.18 m），使握点在肩前 0.309 m、肘在肩前 0.081 m、肘部折叠 107°。桨长、桨叶 `BladeContact`、入水深度（−0.068 m）、航速、转向与靠泊规则均不变。验收必须同时给出握点偏差、手掌前向距离、肘部折叠角与逐相位肘轴连续性，不能只看真实渲染。 |

[交付与实测](../../development/2026-11-05_character_scale_150.md)

## 2026-11-05 手动划行手感：转向惯性、舵效与侧滑

| 条款 ID | 规则与验收 |
|---|---|
| SEA-NAV-R17 | 手动划行的角速度有加速度：`_yaw_rate` 按 `TURN_ACCEL = 4.6 rad/s²` 逼近目标值，满舵 1.8 rad/s 需约 0.39 s；上限随船速缩放 `TURN_RATE × (0.55 + 0.45·v/v_cruise)`（停船 0.99 rad/s）。航迹方向滞后船头，按 `DRIFT_TAU = 0.16 s` 跟随并夹在 `DRIFT_MAX = 0.14 rad`（约 8°）以内；位移仍须通过 `_clear()` 岸线判定，撞岸照旧停住并抛 `navigation_blocked`。松手不瞬间停：角速度自行归零，减速度按 `BRAKE × (0.35 + 0.65·v/v_cruise)` 收尾，速度归零才退出手动；停稳后不得回弹。自动航线（`_steer`）的转向与到站契约不变，点目标航行仍主动清手动。 |

[交付与实测](../../development/2026-11-05_control_feel.md)。


## 2026-11-07 浮动商亭靠泊

| 条款 ID | 规则与验收 |
|---|---|
| SEA-NAV-R18 | 新商亭沿用sea_supply/main和现有航行→靠妥→上岸链路；landStand与dockEdge随真实甲板起伏，boatPark保持实际水线且位于船只阻挡之外；Zones通过支撑变化事件更新公开泊位快照。远海参考摆位只作带入记录，验证正式TSCN下当前航路、上岸、甲板行走、回船及不可穿过船舷。 |

## 2026-11-07 船头顶岸后的手动脱困

用户反馈船头顶岸后不能转向或退开。本节覆盖R15/R17中手动碰撞即结束控制的旧行为，不放开岸线、不改自动航路碰撞处理，也不新增倒车档或传送。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-NAV-R19 | 手动`_drive`与自动航行同样以120Hz子步推进（单帧消费上限0.25s），每段平移必须过`_clear()`。手动撞岸只清该次平移及速度，保留`manual_drive`、输入方向和`_yaw_rate`，玩家可继续摆头，转向合法水面后划开；Main的`navigation_blocked`分支不得把手动状态切回`boat_idle`，已在驾驶时不得误走泊位方向键自动上岸分支。同一轮受阻只反馈一次，直到连续合法划开累计0.1m才重新允许反馈；再次受阻或改变输入方向清已累计距离，不能靠贴边微动刷反馈。松手按原减速/角速度收敛，停稳结束驾驶时清锁存；`stop_drive/place_at/sail_to`同步清锁存与累计距离，自动命令不继承手动航迹。自动路线碰撞仍停止并发出阻挡，不套用手动脱困。手动尾流取实际`travel_direction()`（含侧滑），阻挡零地速不得继续造出航行尾迹；自动模式不消费旧手动方向。 |

最终合批`D:/projects/sea-work/verification/20261107-165822-movement-feel-final-9b7646/report.json`11项全PASS、exit0、unexpected_errors空；其中`boat-unstick`与`visual-boat-unstick`各153459/0。该批visual虽用真实渲染器，但未设shore环境变量，只执行单体、未进入`real_shore`，不得作为正式岸线截图证据。nonheadless直接调用`real_shore`后的`D:/projects/sea-work/verification/20261107-170723-movement-feel-render-final-950cd8/report.json`已完成：`visual-boat-unstick`163769/0真shore、13张PNG，及`visual-keyboard-farm-loop`647/0双PASS/exit0、unexpected_errors空；主任务已用ViewImage目检最新boatsequence，确认转头离岸可见且无教程。渲染验收已收口，不再pending；162541旧岸线图仅作历史，不回写成165822已覆盖岸线。171743兼容批仅actor-presentation PASS，其他五项runner FAIL保留；172123最新facing102/0 PASS说明NPC/dive新装配可启动，新的movement-current-compatible五项另补。[本轮总交付、历史画面与补充边界](../../development/2026-11-07_movement_feel_refinement.md)。近泊位键盘朝向/可达性筛选由SEA-INTERACT-R23承接，浮动商亭R18不改；整体仍`partial`。
