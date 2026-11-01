# 2026-11-01 · 作物按「天」结算（睡一觉就是一天）

对应 SEA-FARM-R14。现场反馈：中午 12:00 浇水，第二天 06:00 醒来看到的还是「今日已浇 · 还需 3 天」，要等到 07:00 之后才翻页，跟牧场物语、《星露谷物语》那种「睡一觉就换天」的手感不一致。

## 根因（两处叠在一起）

用正式场景 + 正式睡觉流程逐小时打点，实测到翻页发生在 **07:02**（游戏内时刻），而不是醒来那一刻：

```
watered    day=10 12:00 | 生菜 · 还需 3 天 · 今日已浇 | water=1 rem=3
woke       day=11 06:01 | 生菜 · 还需 3 天 · 今日已浇 | water=1 rem=3   ← 醒来没换
tick       day=11 06:59 | 生菜 · 还需 3 天 · 今日已浇 | water=1 rem=3
tick       day=11 07:02 | 生菜 · 还需 2 天 · 待浇水   | water=0 rem=2   ← 07:00 结算才换
```

1. **睡觉流程自己的生长调用被挡掉了。** `Main._wake_at_home()` 里写的是 `if not Scope.minimal(): Economy.farm.advance_day()`，而 `Scope.minimal()` 在**不带 `--full-world` 时就是 true** —— 默认配置下这行永远不执行。所以「睡一觉长一天」其实从来没生效过。
2. **唯一还在生长的路径是 07:00 的出货结算。** `DailyShipping.observe()` 在跨过早间水位线时调 `grow`，于是「换天」被绑在了「收货」这个和种植无关的钟点上。玩家在 06:00 到 07:00 之间看到的必然是昨天。

用户说的「要到 12 点才更新」是同一件事的另一个观感：他 12:00 浇完水，若中间没有跨过结算点，就一直是「今日已浇」；下一次跨过才翻页。

## 改法

新增 `FarmModel.advance_to_day(calendar_day)` 作为**唯一换天入口**，自带水位线 `grow_day`：

```gdscript
func advance_to_day(calendar_day: int, accessible_only := false) -> Dictionary:
	if calendar_day <= grow_day:
		return {"day": day, "grew": 0, "ready": 0, "skipped": true}
	grow_day = calendar_day
	return advance_day(accessible_only)
```

- `Main._wake_at_home()` 在全黑段（玩家看不见的时候）用世界时钟的日调用它 —— 醒来睁眼即是新状态。
- `DailyShipping.observe()` 的 `grow` 端口改为 `farm.advance_to_day(day, true)` —— 自然时间跨过 07:00 这条旧路径仍然长一天；两条路径叠加因为水位线而不会长出两天。
- `Economy` 装配：`daily.grow = func(day: int) -> Dictionary: return farm.advance_to_day(day, true)`。

**水位线必须和 `day` 分开存。** `FarmModel.day` 只是日历显示，读档与 `sync_calendar_day` 都会覆盖它。如果拿 `day` 当水位线，「07:00 结算先跑、随后 sync 用同一个日覆盖 `day`」会把当天的生长静默跳过。所以 `grow_day` 只由生长写入，`day` 只由日历写入，存档分别是 `farm.grow_day`（schema v3，不进 required）与 `farm.day`；旧档没有 `grow_day` 时按 `day` 起步，否则读档后第一次换天会把存档那天再长一遍。

## 顺带的文案

- 醒来提示从「早上好 · 07:00 作物生长、出货箱收货」改为「早上好 · 作物已长一天 · 07:00 出货箱收货」。
- 种植页的休息行从「每天07:00生长 · 睡觉后06:00醒来」改为「睡一觉即换天：浇过水的作物醒来长一天，07:00 出货箱收货」。

## 验证

新专项 `farm-day-change`（23 项 0 失败），量的是**时刻**不是数值：

| 断言 | 说明 |
|---|---|
| 醒来即减天 | 06:00 醒来那一帧 `remaining` 3→2、`water` 1→0、状态文案已是「还需 2 天」、可见阶段已进 |
| 07:00 不重复 | 结算走完 `remaining` 不变 |
| 醒来立刻浇水再多结算一次 | 仍不变（水位线挡住） |
| 不睡觉跨过 07:00 | 仍精确长一天（旧路径没坏） |
| 缺水日 | 醒来只清湿度，不扣天数 |
| 读档重进同一天 | 不重长；`grow_day` 已写进存档 |
| 旧档（无 `grow_day`，v2） | 按 `day` 起步，不重长 |

回归：`farming`、`minimum-loop`、`visual-plot-shipping`、`initial-planters`、`walk-on-planters`、`building-integration`、`save-seed`、`framework-integration` 全部通过。

`management` 的 4 项（未建仓库不可入库、第三种植床需船二级、修复后开放第二种植床、船升级开放远海和第三种植床）是**本轮之前就红**的既有失败，与本条无关。

## 文档

- SEA-FARM-R14 新增条款与账本行；R02/R11 中「07:00 生长」的表述由 R14 取代（缺水停长、只长一次这两件事不变，只是时刻提前）。
- SEA-SLEEP-R04 措辞收窄为「只约束卖货仍在 07:00」，生长时刻交给 SEA-FARM-R14。
- `farm` 存档 schema 版本 2→3，新增可选字段 `grow_day`。
