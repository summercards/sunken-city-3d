# SEA-MOVE · 角色移动与上下船

[主文档中控](../../../GDD_V1.0.md#sea-move) · [本功能账本](ledger.md)

设计修订：r1（2026-10-23 工程拆分，未更改玩法数值）。所属系统：3C。
范围来源：主文档保留的全局设计、拆分前文档与当前代码核对；下面明确区分目标与实现边界。

## 功能目的与边界

正式或规划入口：点击陆地和泊位上下船。

本功能以这一玩家行为或工程交付闭环为管理粒度，内部操作作为设计条款逐项承接；不按脚本数量拆功能。跨功能前置和关系由主文档本行统一维护。

## 设计条款与验收标准

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-MOVE-R01 | 角色仅沿合法地面行走，目标不可达时拒绝。现有WalkArea矩形/多边形作为稳定的场景空间声明，必须落在真实甲板及栏杆内侧；GroundSpace由该声明派生物理地板、外缘/洞口阻挡和三维导航，CharacterBody3D胶囊扫掠执行实际位移。点击落点仍按现有body_radius留身影余量；动态平台已内收的角色中心域不得重复内收。 |
| SEA-MOVE-R02 | 上下船使用所属泊位，完成后角色父节点、朝向、模式和动画一致。有多个操作站位的交互物，从船上接近时按当前泊位站立点作为陆路起点；最终仍校验同一地面、船已靠泊且未航行，不能从船座位直接求陆地路径或跨海传送。 |
| SEA-MOVE-R03 | 自动接近只完成一次目标操作，取消后不得继续行走或触发旧目标。 |
| SEA-MOVE-R04 | 采用 enter/exit/tick 生命周期及显式转换表，取消/目标失效/读档清除路径和回调，动画只消费状态不结算业务。 |
| SEA-MOVE-R09 | 陆地行走与自动接近共用角色局部 +Z 正面契约，脸与脚尖朝向实际水平移动方向；转弯保留平滑插值，停止或取消后保持朝向，不改变路径、速度及上下船父节点规则。 |

## 所有者、接口与数据

状态/交付所有者：**ActorController / Character 表现**。正式代码和资源入口：

- [godot/src/player](../../../godot/src/player)
- [godot/src/navigation/walk_area.gd](../../../godot/src/navigation/walk_area.gd)
- [godot/src/navigation/ground_path.gd](../../../godot/src/navigation/ground_path.gd)
- [godot/src/navigation/landing_point.gd](../../../godot/src/navigation/landing_point.gd)

读取上述所有者的公开查询，修改通过其命令或交互入口；事件由拥有该状态的对象发出。具体公开方法、信号和持久化字段见本账本的接口清单。原有稳定 ContentID、场景 ID 和存档键保持不变，重命名须另做迁移。

共享资源的所有权以被依赖功能为准。本功能引用它们，不复制背包数值、资产记录或其他功能规则。规划中的接口尚无实现时必须先补契约再编码。

## 当前实现与待完成边界

角色控制已由 Main 拆到 ActorController；9 个状态、4 个控制动作和7个表现动作分别独立文件。已有行为完成回归；移动端手感、跳跃/战斗等未设计玩法不计完成。

2026-10-27 接口：start_walk / approach / depart / cancel / request_mode / restore_pose / state_id / snapshot；state_changed、mode_changed；状态/动作目录见模块约定。

详细所有权、状态转换与扩展方法见 [模块接口约定](../../architecture/module_contracts.md)；实测范围见 [框架交付记录](../../development/2026-10-27_modular_framework.md)。原目标中尚未实现的内容保持登记，不因架构拆分自动升级完成度。

## 2026-10-28 登陆标记的双向往返

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-MOVE-R06 | 同一个登陆标记按「角色现在在哪」决定方向，不新增第二个按钮：已在岸上点击 → 走回该泊位站立点后上船，角色挂到船下；已在船上且停在该泊位 → 上岸，角色挂回世界并落在 `stand_position()`；船不在该泊位（含别的区块）→ 先航行，**靠妥后自动上岸**，不需要玩家再点一次。 |
| SEA-MOVE-R07 | 「到岸即上岸」是一次性意图：`_ashore_on_arrival` 在产生时置位，被到达回调消费后立即清零；取消动作、改划水面、点漂流物/鱼群、船被岸线挡停、读档恢复都必须清零，任何后续航线不得继承上一次的意图。 |

角色仍在 `ActorController` 的既有状态表内完成：上岸 = `start_walk(landing.ground(), landing.stand_position())`，抵达即 `ashore_idle`；上船 = `depart()` → `boarding` → `boat_idle`。没有新增状态或边。

[本轮交付](../../development/2026-10-28_dock_seed_weather_asset_fix.md)。

## 验收入口

通过主文档定位本功能后执行账本列出的检查。正常、拒绝、取消/重复、存档恢复均按适用范围记录；真实渲染、听验和设备项单列。本次使用统一 runner 的隔离存档项目，不能直接拿玩家存档做测试。

## 来源与交付记录

- [拆分前完整主文档](../../archive/pre_split_20261023/GDD_V1.0.md)
- [拆分前功能计划](../../archive/pre_split_20261023/功能重做计划.md)
- [本次工程拆分记录](../../development/2026-10-23_feature_split.md)
- [godot/CLICK_CONTROLS.md](../../../godot/CLICK_CONTROLS.md)

## 2026-10-28 补充契约

| 条款 ID | 规则 |
|---|---|
| SEA-MOVE-R05 | begin_sleep取消路径和交互后进入独立sleeping状态；该状态不评估行走/交互，醒来经restore_pose恢复ashore_idle。 |

## 2026-10-29 家园建造接入

| 条款 ID | 规则 |
|---|---|
| SEA-MOVE-R08 | 完工木板行走面按承载并集与角色半宽0.22米生成，板间接缝不内收；施工板不可踩。摆件开工预留布局占用，通行只扣除明确阻挡的实体；种植区及蔬菜允许踩踏，使用格内及侧边操作点。修改不得切断平台通路或吞掉角色落脚点，旧边缘档可迁入安全面。 |

[交付与实测](../../development/2026-10-28_building_delivery.md)。

## 2026-10-29 自建平台上下船

| 条款 ID | 规则 |
|---|---|
| SEA-MOVE-R10 | 自建平台派生LandingPoint仍由ActorController执行上岸/返船，不通过传送替代靠泊；当前登陆边在角色岸上时受摆件/拆板保护。登陆ID跟布局稳定重建并随game快照恢复，不另存角色状态机。 |

[本轮交付](../../development/2026-10-29_open_ocean_building.md)。

## 2026-10-29 角色碰撞、三维空间与表现动作改造

本节覆盖此前“人物移动不使用物理碰撞”的实现描述。只改移动与空间执行，不增删正式房间、楼梯、模型或玩法；现有速度2.3m/s、+Z朝向、转向指数12、点击/取消、靠泊与上船体验保持。

碰撞按用途显式配置。蔬菜/植物/纯装饰不因有网格自动挡人，种植模型同样不自动加模型碰撞；ActorCollisionBody.blocks_actor可启停独立简单代理。承载面、布局通路和物体显示分别维护。按同日用户最新要求，固定六格及DIY双尺寸明确允许踩踏，不再扣除种植占地；站格/穿格不触发种植业务，平台外缘仍保护。[通行实测](../../development/2026-10-29_walk_on_planters.md)。

| 条款 ID | 规则 |
|---|---|
| SEA-MOVE-R11 | Character继承独立CharacterMotor（CharacterBody3D），胶囊半径0.22m、高1.30m。人物layer512、地面/人物障碍layer256，船仍用原航行系统。生产只由物理帧驱动ActorController；行走以move_and_collide扫掠，取消/阻挡清路径，上船/潜水关闭陆地碰撞，下船/恢复岸上重新启用；无直接position位移兜底。 |
| SEA-MOVE-R12 | GroundSpace拥有派生物理/导航，不拥有世界或建造布局。WalkArea可声明局部surface_triangles，支持斜面与重叠楼层；按三维位置选地面，跨表面路线必须经实际连通导航，不能以相同XZ跨层。普通楼梯可由未来组件提供连续坡面代理；竖直梯子等特殊动作另行设计，不因接入导航自动完成。 |
| SEA-MOVE-R13 | 角色表现保留原七种动作及农作1.1秒曲线；register_action/play_action/cancel_action、进度快照与开始/完成/取消事件为唯一扩展入口。动作token区分重复请求，取消不可再完成；动画只表现，不结算物品、推进玩法或修改角色根位移。表现接口允许未来收菜、检查、工具等动作接入。 |

所有者与扩展：输入→ActorController命令/状态→WalkAction路线/CharacterMotor执行；Character表现消费状态与显式动作。新增动作仅注册sampler与时长；新增地面声明归场景，旧rects、area_id、landing_id及存档XYZ保持稳定。物理支撑的微小安全余量不计为到达失败，斜坡路线按胶囊接触几何计算站位高度。

专项：character-motor、ground-space、actor-presentation、walk-facing、dock-seed、board-click；真实渲染、集成、存档及未执行项见[交付记录](../../development/2026-10-29_character_physics_framework.md)。
