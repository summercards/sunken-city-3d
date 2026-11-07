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
    "visual-corner-notebook",
    "framework-modules",
    "framework-integration",
    "visual-weather",
    "minimum-loop",
    "visual-plot-shipping",
    "sleep-cycle",
    "npc-clock",
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


## 2026-10-28 HUD与笔记表现接线

原日期Label移动到HUD左下文字区域，Main继续组合WorldClock/Weather查询显示。笔记通过注入calendar_query读取同一时间；开始画面与睡觉显隐、恢复时刻、晨次和快照契约保留。

对应SEA-UI-R35–R38；[本轮交付](../../development/2026-10-28_corner_hud_notebook.md)。本功能整体状态与玩法边界保留。


## 2026-10-28 月日派生显示

| 对应条款 | 实施状态 | 证据 |
|---|---|---|
| SEA-TIME-R11 | 已实现；累计日不变，纯查询派生月日，无快照迁移；月末/跨年/午夜/恢复专项覆盖 | [本轮交付](../../development/2026-10-28_hud_date_camera_lock.md) |

当前新增公开查询字段month/day_of_month与静态calendar_date；快照仍仅day/seconds/day_length。显示从1月1日起按365日循环，不引入闰年或新年份状态。

## 2026-11-07 单推进修复与最新证据

| 对应设计条款 | 当前实施状态 | 证据 / 验证边界 |
|---|---|---|
| SEA-TIME-R12 | 已实现；Main第二次clock.tick已移除，仅sleep_cycle.advance内部至多推进一次并cap到23:00；06:00醒/07:00晨次不变；clock.changed只轻量notify，不同步解析NPC | npc-clock 301/0、sleep-cycle 42/0，均exit0/PASS；[主时钟报告](../../../../sea-work/verification/20261107-212152-npc-clock-once-cc6ca7/report.json)。force恢复保留；全量天台integration/save/seed/restart/visual已由214439五项2277/0独立通过，设备发行/持续性能不签完整 |

真实渲染函数探针sleep median 0.017ms、clock 0.012ms；仅为对应隔离工作树五次调用，不等于每帧固定耗时。完整命令、快照版本、性能与未验项见[本轮修复记录](../../development/2026-11-07_npc_performance_fix.md)。登记头JSON及原implemented状态保持，不将单项通过扩大为整工程验收。

## 最终天台联合签署补充

[214439最终报告](../../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/report.json)五项668/618/408/202/381 checks均0失败，总2277/0，exit0/PASS且unexpected_errors空。R12单推进与既有301/0+sleep42/0结论保留；shop最终259/0已解决七项UI失败。14PNG已产出；后续主线程原图/联系图补审与最新回归见下。当前设备59.943FPS不等于发行包/其他设备/持续性能验收。

主线程最终[221054回归](../../../../sea-work/verification/20261107-221054-npc-final-regression-bc8a22/report.json)再次覆盖npc-clock301/0、sleep42/0，11专项全部PASS；[222551正式存档复验](../../../../sea-work/verification/20261107-222551-npc-final-live-worktree-6eb68a/report.json)集成/存档/跨进程均PASS。当前全局合同sync17/check18问题未擅改哈希，详[最终性能记录](../../development/2026-11-07_npc_performance_fix.md#9-主线程最终回归视觉审阅与门禁)。
