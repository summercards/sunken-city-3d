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

## 2026-11-13 B1 共享圆幕互斥与疲劳续接

承接 R03/R04/R05：房间切换期间 Main 不推进 SleepCycle.advance，房间新请求也查询睡眠/疲劳/潜水 busy，避免22:59房间过场与自动入睡争同一幕；不新增睡眠状态或存档字段。疲劳恢复在完整owner恢复之后续接既有request_forced。SleepCurtain只增加可取消的无字圆幕等待代次，睡觉文字/时长不改。

最终sleep-cycle42/0、room163/0、energy40/0、framework52/0、dive-transition501/0与外部组合109/0，均exit0。组合覆盖22:59进屋时钟不推进和同幕不重入；真实渲染、出门22:59全部时序组合、跨进程零体力及资源泄漏归因未验，不继承旧截图。[证据与遗留](../../development/2026-11-13_engine_deep_audit.md#b1-交互生命周期子批实际实施)。

## 2026-11-14 B2 G05/G07 睡眠会话承接

承接SEA-SLEEP-R01/R02/R03/R04：prepare_sleep先调用owned modal真实close/cancel，结束Shop/职业/NPC等逻辑会话并失效旧确认，再隐藏Canvas；醒来仅恢复基础可见性，不复活旧支付/购买按钮。时钟/换日/圆幕时长不变。室内起床与接近共用RoomService四边OBB净空/门路线，旧档无安全床边点时前厅fallback不挪床；不新增睡眠wire。

b2-session51/0覆盖三类22:59自动睡醒后closed、旧回调无库存变化及只换日一次，sleep-cycle42/0、bedside1800/0（133真实胶囊/到门、26正式approach含13绕行）PASS/exit0。当前真实visual-sleep-cycle/room待父最终追加，不沿旧图冒签；登记头implemented原样、不升verified。[B2主记录](../../development/2026-11-13_engine_deep_audit.md#b2-业务事务与空间修复最终回填2026-11-14)。

### B2 最终状态（2026-11-14）· [主记录](../../development/2026-11-13_engine_deep_audit.md#b2-最后复测与签署范围2026-11-14)
- 012421-b2-session-valid-confirm-d25e8b先保证真实可支付及旧确认Callable有效，自动睡醒后旧确认不能扣费/购买/升级，53/0、exit0；005741 sleep42/0、room763/0及005436 bedside1800/0均exit0。
- 010438睡眠视觉产6PNG/exit0，仅目检sleep-wake：玩家在室外太阳房门口、HUD可见且无残留黑幕，不是室内醒来；其余睡眠图未逐图审阅，全库契约仍失败，登记头implemented不升verified。
