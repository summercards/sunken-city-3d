# SEA-TIME · 世界时间

[主文档中控](../../../GDD_V1.0.md#sea-time) · [独立账本](ledger.md)

设计修订：r2（2026-10-27）。所属系统：生活。世界时间与天气分别拥有独立状态，通过装配层组合显示。

## 设计条款与验收标准

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-TIME-R01 | 昼夜通过公开 daylight 查询影响氛围；天气独立为 SEA-WEATHER。涉及采集、鱼群或作物时必须明确结算语义。 |
| SEA-TIME-R02 | 作物仍按玩家休息推进；建造与采集使用各自剩余秒，日历自然跨日不得重复结算作物。 |
| SEA-TIME-R03 | 世界时间随模块快照保存；旧档默认第1天08:00，离线冻结，不以系统时钟差结算奖励。 |
| SEA-TIME-R04 | 时间服务独立提供 tick、暂停、休息到次日早晨、日历查询和跨日事件；拒绝负数及非有限 delta。 |

## 所有者、接口与数据

唯一所有者：**WorldClock**。

- [godot/src/time/world_clock.gd](../../../godot/src/time/world_clock.gd)
- [godot/assets/data/world_time.json](../../../godot/assets/data/world_time.json)

`configure(config)` 设置 day_length_seconds（默认1200秒）；`tick(delta)` 推进；`paused` 由会话暂停管理；`rest_to_morning()` 到次日08:00；`query()` 返回 day/hour/text/daylight；`changed(snapshot)` 与 `day_changed(day)` 通知订阅者。

快照 `time` 包含 day（>=1）、seconds（0≤值<86400）、day_length（60–86400）。显示层读取查询；种植保持原有 rest_only 策略，日历自然过一天只改变氛围，不自动 advance_day。

## 当前实现与待完成边界

基础日历已落地；季节、日期事件、离线收益与时间加速产品界面未实现。本功能基础框架状态为 implemented，仍需目标设备及完整产品体验验收。

## 验收入口

通过统一 runner 执行 `framework-modules framework-integration visual-weather`，自动隔离玩家存档。测试种子准备由 runner 自动配对。真实渲染与逻辑测试分别登记。详见[模块接口约定](../../architecture/module_contracts.md)和[框架交付记录](../../development/2026-10-27_modular_framework.md)。
