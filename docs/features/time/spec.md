# SEA-TIME · 世界时间

[主文档中控](../../../GDD_V1.0.md#sea-time) · [独立账本](ledger.md)

设计修订：r2（2026-10-27）。所属系统：生活。世界时间与天气分别拥有独立状态，通过装配层组合显示。

## 设计条款与验收标准

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-TIME-R01 | 昼夜通过公开 daylight 查询影响氛围；天气独立为 SEA-WEATHER。涉及采集、鱼群或作物时必须明确结算语义。 |
| SEA-TIME-R02 | 默认作物按07:00晨次推进，休息与自然时间不得重复结算；未开放的建造和采集暂停。完整开发配置保留旧经营计时。 |
| SEA-TIME-R03 | 世界时间随模块快照保存；旧档默认第1天07:00，离线冻结，不以系统时钟差结算奖励。 |
| SEA-TIME-R04 | 时间服务独立提供 tick、暂停、休息到次日早晨、日历查询和跨日事件；拒绝负数及非有限 delta。 |
| SEA-TIME-R05 | 自然经过07:00与休息共用晨次结算；午夜不结算。午夜后休息到当天早晨，不多跳一天；开始画面不推进日历或天气，无离线补发。 |

| SEA-TIME-R06 | day_schedule.gd唯一声明07:00晨次；WorldClock休息、DailyShipping观察及SaveSchema水位线校验共用常量。默认新游戏第1天07:00，离线不补发。 |

## 所有者、接口与数据

唯一所有者：**WorldClock**。

- [godot/src/time/world_clock.gd](../../../godot/src/time/world_clock.gd)
- [godot/assets/data/world_time.json](../../../godot/assets/data/world_time.json)

`configure(config)` 设置 day_length_seconds（默认1200秒）；`tick(delta)` 推进；`paused` 由会话暂停管理；`rest_to_morning()` 到次日07:00；`query()` 返回 day/hour/text/daylight；`changed(snapshot)` 与 `day_changed(day)` 通知订阅者。

快照 `time` 包含 day（>=1）、seconds（0≤值<86400）、day_length（60–86400）。显示层读取查询；默认由 DailyShipping 观察07:00晨次，通过注入命令推进作物；休息和自然时间共用一次结算。

## 当前实现与待完成边界

基础日历已落地；季节、日期事件、离线收益与时间加速产品界面未实现。本功能基础框架状态为 implemented，仍需目标设备及完整产品体验验收。

## 验收入口

通过统一 runner 执行 `framework-modules framework-integration visual-weather`，自动隔离玩家存档。测试种子准备由 runner 自动配对。真实渲染与逻辑测试分别登记。详见[模块接口约定](../../architecture/module_contracts.md)和[框架交付记录](../../development/2026-10-27_modular_framework.md)。

## 2026-10-27 当前最小循环与开始画面

本节及本轮修改条款优先于下方保留的历史范围。默认发布配置只开放家园生活循环；旧全功能验证须显式 `--full-world`，不能代替最小版本验收。接口、迁移及实测见[交付记录](../../development/2026-10-27_minimum_loop_and_title.md)。

## 2026-10-27 场景点击经营循环

最新规则见本轮新增条款；07:00结算和瓶盖命名优先于历史引用。[交付与实测](../../development/2026-10-27_plot_shipping_loop.md)。

## 2026-10-28 补充契约

| 条款 ID | 规则 |
|---|---|
| SEA-TIME-R07 | 06:00醒来与07:00经营晨次分离；wake_to_morning只推进日历到最近的醒来早晨，23:00睡觉调度归SEA-SLEEP。旧rest_to_morning保留为07:00结算推进接口，不再被玩家睡觉按钮调用。 |

## 2026-10-28 时段槽位

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-TIME-R08 | 八个时段槽位（深夜/黎明前/清晨/上午/正午/下午/夕阳/黑夜）由 `daylight_presets.gd` 的关键帧 label 推导，不另立第二份时段表；`daylight_slots.gd::verify()` 在 label 失配时报错。上午为 07:00–11:00 平顶段，整段共用一个偏移。 |
| SEA-TIME-R09 | 时段偏移按 `smoothstep` 在段边界混合，与昼夜插值共用同一条曲线；时段槽位本身不推进日历，不改变 07:00 晨次与离线冻结语义。 |
| SEA-TIME-R10 | 受时段驱动的表现参数以DaylightRig与面板清单对账为准，覆盖太阳、环境、天空盒和两套水面。日间水面保留原自发光构图；最新夜间使用真实受光ALBEDO/PBR，日光自发光为零，具体归SEA-OCEAN-R18；夜海材质色和粗糙度同样支持时段偏移。 |


时段表是表现层的分组，**不是新的时间所有者**：`WorldClock` 仍是唯一时钟，`daylight_slots.gd` 只做「某一时刻落在哪一段」的查询。

[本轮交付](../../development/2026-10-28_daypart_lighting_panel.md)。
