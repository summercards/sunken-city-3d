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
| SEA-MOVE-R01 | 角色仅沿合法地面行走，目标不可达时拒绝，不穿越水域或建筑。 |
| SEA-MOVE-R02 | 上下船使用所属泊位，完成后角色父节点、朝向、模式和动画一致。 |
| SEA-MOVE-R03 | 自动接近只完成一次目标操作，取消后不得继续行走或触发旧目标。 |
| SEA-MOVE-R04 | 采用 enter/exit/tick 生命周期及显式转换表，取消/目标失效/读档清除路径和回调，动画只消费状态不结算业务。 |

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
