# SEA-ENERGY · 体力与疲劳 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-energy) · [功能文档](spec.md)

```json
{
  "feature_id": "SEA-ENERGY",
  "status": "implemented",
  "owner": "EnergyModel",
  "code_paths": [
    "godot/src/energy/energy_service.gd",
    "godot/src/ui/stamina_bar.gd",
    "godot/src/ui/corner_hud.gd",
    "godot/src/economy/economy.gd",
    "godot/src/time/sleep_cycle.gd"
  ],
  "verification": [
    "energy",
    "visual-energy",
    "sleep-cycle",
    "building-base-neighbors"
  ]
}
```

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-ENERGY-R01 | 已实现；100 上限、每日回满、`economy.energy` 进存档且不进 required，旧档读成满体力 | [本轮交付](../../development/2026-11-01_energy_fishery_and_join.md) |
| SEA-ENERGY-R02 | 已实现；播种2/浇水1/收获1/建造4/拆回3/搬移3/采集3/打捞3，均扣在结算成功之后 | 同上（`energy` 39 项） |
| SEA-ENERGY-R03 | 已实现；低于 25% 提一次，同日不重复，次日重置 | 同上 |
| SEA-ENERGY-R04 | 已实现；台词「啊，太累了，今天需要休息了。」→ 黑幕过场，期间输入锁定、重复触发只执行一次 | 同上（含真实渲染图） |
| SEA-ENERGY-R05 | 已实现；强制休息的次日上限 50 并补满，正常入睡恢复 100；`pending_half` 单独存档，读档不叠加 | 同上 |
| SEA-ENERGY-R06 | 已实现；右下角体力条在圆按钮上方，青绿/琥珀/珊瑚三段配色，面板打开与航行时同样可见 | 同上（`energy-half-day.png`） |
| SEA-ENERGY-R07 | 已实现；`farm`/`building`/`gather` 只认可选端口，端口未接照常运行；`farming` 与 `building` 全套仍 0 失败 | [回归批次](#回归批次) |
| SEA-ENERGY-R08 | 已实现；`building-kit`/`building-simulate` 在夹具里回满体力，`energy` 用正式命令撞到 0 并走完强制休息 | 同上 |

## 回归批次

2026-11-01 本轮实跑（统一 runner，隔离存档）：`energy` 39 项 0 失败、`visual-energy` 通过、`building-base-neighbors` 28 项 0 失败、`sleep-cycle` 与 `visual-sleep-cycle` 通过；受影响的既有套件复跑后 `building`、`building-join`、`building-kit`、`building-simulate`、`building-open-rules`、`building-space`、`building-approach`、`walk-on-planters`、`farming`、`modules`、`minimum-loop`、`initial-planters`、`save-seed`、`save-protection`、`framework-integration`、`dock-seed`、`harvest-receive`、`close-hint`、`progress-bars` 均通过。

非本轮引入、复现于改动前的失败：`management` 4 项（仓库门槛与种植床解锁文案）、`building-ocean` 2 项（远海独立地基与船上接近）、`sea-supply` 6 项（`main.tscn` 里未提交的浮店缩放/位移导致甲板高度与泊位断言不符）。三处都在基线（暂存本轮源码改动后）复跑同样失败，未在本轮处理。

## 未做

体力对移动速度/距离的影响、食物回复、上限成长、提醒文案轮换；均未登记为本轮目标。
