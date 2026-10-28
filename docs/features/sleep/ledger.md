# SEA-SLEEP · 睡觉与次日醒来 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-sleep) · [功能文档](spec.md)

```json
{
  "feature_id": "SEA-SLEEP",
  "status": "implemented",
  "owner": "SleepCycle / SleepCheckpoint",
  "code_paths": [
    "godot/src/time/sleep_cycle.gd",
    "godot/src/time/sleep_checkpoint.gd",
    "godot/src/player/states/sleeping.gd",
    "godot/src/ui/sleep_curtain.gd",
    "godot/shaders/sleep_iris.gdshader"
  ],
  "verification": [
    "sleep-cycle",
    "visual-sleep-cycle",
    "minimum-loop",
    "framework-integration"
  ]
}
```

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-SLEEP-R01 | 已实现，专项与实景回归 | [本轮实测](../../development/2026-10-28_sleep_cycle_delivery.md) |
| SEA-SLEEP-R02 | 已实现，专项与实景回归 | [本轮实测](../../development/2026-10-28_sleep_cycle_delivery.md) |
| SEA-SLEEP-R03 | 已改为圆形收幕/黑幕晨间提示/圆形开幕，保留输入与存档锁定 | [本轮实测](../../development/2026-10-28_sleep_iris.md) |
| SEA-SLEEP-R04 | 已实现，专项与实景回归 | [本轮实测](../../development/2026-10-28_sleep_cycle_delivery.md) |

2026-10-28：独立流程、门口点击、23:00自动睡觉、06:00醒来、过渡存档保护；不新增美术源。

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-SLEEP-R05 | 已实现，真实渲染检查收拢/全黑/晨间/展开阶段及圆心、边角遮黑、UI恢复 | [本轮实测](../../development/2026-10-28_sleep_iris.md) |
