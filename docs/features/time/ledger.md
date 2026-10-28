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
    "visual-weather",
    "minimum-loop",
    "visual-plot-shipping",
    "sleep-cycle",
    "visual-home-lighting"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-TIME-R01 | 已实现基础昼夜；生产加成未启用 | [本轮专项记录](../../development/2026-10-27_modular_framework.md) |
| SEA-TIME-R02 | 已改为统一晨次推进，休息与自然时间共用水位线 | [本轮验证](../../development/2026-10-27_minimum_loop_and_title.md) |
| SEA-TIME-R03 | 已实现并核验 | [本轮专项记录](../../development/2026-10-27_modular_framework.md) |
| SEA-TIME-R04 | 已实现并模块核验 | [本轮专项记录](../../development/2026-10-27_modular_framework.md) |
| SEA-TIME-R05 | 本轮实现；正式最小范围与独立专项验证 | [本轮交付](../../development/2026-10-27_minimum_loop_and_title.md) |
| SEA-TIME-R06 | 已实现，场景点击与存读专项验证 | [本轮证据](../../development/2026-10-27_plot_shipping_loop.md) |

## 当前接口清单

`configure(config)` 设置 day_length_seconds（默认1200秒）；`tick(delta)` 推进；`paused` 由会话暂停管理；`rest_to_morning()` 到次日07:00；`query()` 返回 day/hour/text/daylight；`changed(snapshot)` 与 `day_changed(day)` 通知订阅者。

快照 `time` 包含 day（>=1）、seconds（0≤值<86400）、day_length（60–86400）。显示层读取查询；默认种植与出货由DailyShipping观察07:00统一晨次，06:00醒来不结算。

## 资源归属

本次使用程序绘制氛围，未新增或虚构美术 AssetID。后续天气贴图、声音从[资产总入口](../../../assets/registry/README.md)登记相应分账本。

## 遗留与下一步

基础日历已落地；季节、日期事件、离线收益与时间加速产品界面未实现。本功能基础框架状态为 implemented，仍需目标设备及完整产品体验验收。

## 变更记录

- 2026-10-27：从时间/天气规划拆分独立所有者、配置、快照和验证入口；原时间 R01–R03 保持条款承接；新增天气 FeatureID。
- 2026-10-27：模块测试、跨进程存档和真实渲染证据见[交付记录](../../development/2026-10-27_modular_framework.md)。

## 2026-10-27 当前最小循环与开始画面

本节及本轮修改条款优先于下方保留的历史范围。默认发布配置只开放家园生活循环；旧全功能验证须显式 `--full-world`，不能代替最小版本验收。接口、迁移及实测见[交付记录](../../development/2026-10-27_minimum_loop_and_title.md)。

2026-10-27 场景点击循环：07:00收货、瓶盖、木土种植格及码头出货箱；[本轮记录](../../development/2026-10-27_plot_shipping_loop.md)。

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-TIME-R07 | 已实现，保留旧档/晨次兼容 | [本轮实测](../../development/2026-10-28_sleep_cycle_delivery.md) |

## 2026-10-28 家园箱子与夜灯修复

SEA-TIME-R01：家园灯只消费昼夜时刻，无新增时钟或存档字段；黄昏、午夜、清晨与07:00关灯断言通过。

[交付记录](../../development/2026-10-28_home_lighting_recovery.md)。

## 2026-10-28 时段槽位

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-TIME-R08 | 已实现；8段槽位从预设 keyframe label 推导，label 失配与代表时刻反查由 `lighting-params` 静态拦截 | `lighting-params` 181项 |
| SEA-TIME-R09 | 已实现；段间用同一条 `smoothstep` 混合，`daylight` 194项与 `visual-weather` 真实渲染回归通过 | `daylight` + `visual-weather` |
| SEA-TIME-R10 | 已实现；太阳/环境/天空/水面清单对账，夜间新增5项受光与水深参数见SEA-OCEAN-R18/R19 | `lighting-params` 217项 |


时段表只是表现分组，未新增时间所有者、日历字段或存档键；`WorldClock` 的晨次与离线语义未改。

[交付记录](../../development/2026-10-28_daypart_lighting_panel.md)。


## 2026-10-28 氛围修订

SEA-TIME-R01/R08/R09继续由同一WorldClock与预设表驱动。本轮只改SEA-OCEAN拥有的清晨/下午/夜间表现与局部灯，没有改晨次、睡觉、季节或天气状态。详见[本轮实测](../../development/2026-10-28_cozy_daypart_atmosphere.md)。

## 2026-10-28 开始界面时间连续性

开始背景改为读取已恢复的同一WorldClock时刻，不修改存档格式、时间字段或07:00晨次。开始期间继续冻结时钟，入场后恢复计时；白天/夜间/清晨真实存档冷启动验证见[本轮记录](../../development/2026-10-28_title_composition_saved_time.md)。
