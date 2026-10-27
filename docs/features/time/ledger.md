# SEA-TIME · 世界时间 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-time) · [功能文档](spec.md)

## 登记头

```json
{
  "feature_id": "SEA-TIME",
  "status": "implemented",
  "owner": "WorldClock",
  "code_paths": [
    "godot/src/time/world_clock.gd",
    "godot/assets/data/world_time.json"
  ],
  "verification": [
    "framework-modules",
    "framework-integration",
    "visual-weather"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-TIME-R01 | 已实现基础昼夜；生产加成未启用 | [本轮专项记录](../../development/2026-10-27_modular_framework.md) |
| SEA-TIME-R02 | 已实现并核验 | [本轮专项记录](../../development/2026-10-27_modular_framework.md) |
| SEA-TIME-R03 | 已实现并核验 | [本轮专项记录](../../development/2026-10-27_modular_framework.md) |
| SEA-TIME-R04 | 已实现并模块核验 | [本轮专项记录](../../development/2026-10-27_modular_framework.md) |

## 当前接口清单

`configure(config)` 设置 day_length_seconds（默认1200秒）；`tick(delta)` 推进；`paused` 由会话暂停管理；`rest_to_morning()` 到次日08:00；`query()` 返回 day/hour/text/daylight；`changed(snapshot)` 与 `day_changed(day)` 通知订阅者。

快照 `time` 包含 day（>=1）、seconds（0≤值<86400）、day_length（60–86400）。显示层读取查询；种植保持原有 rest_only 策略，日历自然过一天只改变氛围，不自动 advance_day。

## 资源归属

本次使用程序绘制氛围，未新增或虚构美术 AssetID。后续天气贴图、声音从[资产总入口](../../../assets/registry/README.md)登记相应分账本。

## 遗留与下一步

基础日历已落地；季节、日期事件、离线收益与时间加速产品界面未实现。本功能基础框架状态为 implemented，仍需目标设备及完整产品体验验收。

## 变更记录

- 2026-10-27：从时间/天气规划拆分独立所有者、配置、快照和验证入口；原时间 R01–R03 保持条款承接；新增天气 FeatureID。
- 2026-10-27：模块测试、跨进程存档和真实渲染证据见[交付记录](../../development/2026-10-27_modular_framework.md)。
