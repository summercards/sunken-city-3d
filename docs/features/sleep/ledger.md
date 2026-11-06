# SEA-SLEEP · 睡觉与次日醒来 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-sleep) · [功能文档](spec.md)

```json
{
  "feature_id": "SEA-SLEEP",
  "status": "implemented",
  "owner": "SleepCycle / RoomBed",
  "code_paths": [
    "godot/src/time/sleep_cycle.gd",
    "godot/src/room/room_bed.gd",
    "godot/src/room/room_controller.gd",
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
| SEA-SLEEP-R04 | 已实现，专项与实景回归；卖货仍在07:00，生长自2026-11-01起改为醒来即换天（SEA-FARM-R14） | [本轮实测](../../development/2026-10-28_sleep_cycle_delivery.md) |

2026-10-28：独立流程、门口点击、23:00自动睡觉、06:00醒来、过渡存档保护；不新增美术源。（「门口点击」已由 2026-11-05 的室内床迁移取代，见本页末节；此处保留历史口径。）

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-SLEEP-R05 | 已实现，真实渲染检查收拢/全黑/晨间/展开阶段及圆心、边角遮黑、UI恢复 | [本轮实测](../../development/2026-10-28_sleep_iris.md) |

## 2026-11-01 黑幕文字停留

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-SLEEP-R06 | 已实现；入睡文字淡入0.45秒/停2.4秒/淡出0.45秒，起床文字淡入0.45秒/停2.6秒/淡出0.45秒，实测全黑后1.6秒仍完整可见 | [本轮交付](../../development/2026-11-01_energy_fishery_and_join.md) |

## 2026-11-05 睡觉入口迁到室内床（2026-11-06 补记）

入口从太阳房门口的月亮检查点迁到室内床，属于 R01 的实施变更。当时只在 SEA-ROOM 的交付记录里写清了事实，
本功能账本没有承接，登记头的 owner 还指向已删除的 `SleepCheckpoint`。

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-SLEEP-R01 · 11-05 迁移 | `godot/src/time/sleep_checkpoint.gd` **已删除**；太阳房入口原「睡觉」按钮改为「进入房间」。睡觉走 `room_bed.gd` 发 `sleep_requested` → Main `_rest_for_day` → 既有 `sleep_cycle.request()`。醒来位置按 `room_service.inside` 分叉：屋里醒床边、屋外醒太阳房门口。23:00 自动入睡、06:00 醒来、圆幕过场、过渡期间输入与存档锁定、体力惩罚调用点均未变 | `room` 105 项 0 失败、`visual-room` 6 机位 0 失败；`sleep-cycle`／`minimum-loop`／`energy` 复跑通过；[迁移事实与实测](../../development/2026-11-05_bedroom_room.md) |
