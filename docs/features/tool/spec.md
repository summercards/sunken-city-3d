# SEA-TOOL · 测试工具（P 面板「测试」页）

[主文档中控](../../../GDD_V1.0.md#sea-tool) · [独立账本](ledger.md)

设计修订：r1（2026-11-02）。所属系统：工程。P 键调试面板新增第四页「测试」，用来在不改代码、不动存档的前提下，把游戏推到某个状态再看表现：加货币与资源、跳时间、换天气、回体力。

## 目标与边界

这一页是**给人做验证用的**，不是玩法入口，所以它不拥有任何状态：

- 资源归 SEA-INVENTORY（写入经 `Economy.give` → `Inventory`）；
- 世界时间归 SEA-TIME（`WorldClock`）；
- 天气归 SEA-WEATHER（`WeatherService`）；
- 体力归 SEA-ENERGY（`EnergyModel`）。

它只做两件事：把「现在是什么状态」读出来显示，把「用户按的那一下」转成对上述所有者的既有调用。任何一条做不到，就禁用那一组并写明原因 —— 不静默失败，也不自己造一份平行状态。

## 设计条款与验收标准

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-TOOL-R01 | 「测试」页挂在 P 面板第四页（滤镜 / 光照 / 水面 / 测试），默认仍停在滤镜页。测试工具不新增玩法状态、不新增存档字段、不改任何规则所有者；正式玩法闭环不得依赖它。 |
| SEA-TOOL-R02 | 加货币与资源必须走 `Economy.give` → `Inventory`，容量、堆叠、溢出提示规则不变；资源格子从 `assets/data/items.json` 派生，不在代码里写死清单。货币（`stack = 0`）单列一行，不混进材料格子。 |
| SEA-TOOL-R03 | 改时间只写 `WorldClock` 已经公开的 `day` / `seconds` 并广播既有的 `changed` / `day_changed`；07:00 晨次、睡觉推进、离线冻结语义不变；`day` 不得被压到 0（存档契约 `day >= 1`）。跨午夜要把天数带过去。 |
| SEA-TOOL-R04 | 天气切换只调 `WeatherService.set_weather`；非法 id 被拒且状态不变；不得绕过服务直接改画面表现或天气表现层。 |
| SEA-TOOL-R05 | 体力回满只调 `EnergyModel.refill()`；不直接改 `current`。 |
| SEA-TOOL-R06 | 页面能力全部由 `bind()` 注入的端口提供，页面本身不认识 Economy / Main / HUD；端口缺失时整页只读并说明。测试页打开期间必须放开昼夜预览（`DaylightRig.clear_preview`），切回调色页恢复锁定，关面板同样放开。 |
| SEA-TOOL-R07 | 验收入口 `test-tools` 覆盖四类动作与预览锁定；版面本身由 `visual-*` 另行核对，逻辑通过不能代替真实渲染证据。 |

## 所有者、接口与数据

面板不拥有数据，只有**装配**：

- [godot/src/debug/test_tools_page.gd](../../../godot/src/debug/test_tools_page.gd) —— 页面控件与四个动作出口（`add_item` / `add_all` / `shift_*` / `jump_to_hour` / `set_weather` / `refill_energy`），只认端口。
- [godot/src/rendering/color_grade_panel.gd](../../../godot/src/rendering/color_grade_panel.gd) —— 第四页的挂载、`set_test_ports()`、页签与预览锁定的切换。
- [godot/src/bootstrap/main.gd](../../../godot/src/bootstrap/main.gd) —— `_setup_grade()` 注入端口；`_debug_set_clock()` 是唯一的时间写入口，`_debug_catalog()` 从物品表生成清单。

端口契约（全部可选）：

```
catalog()               -> Array[{id, label}]
count(id)               -> int
give(amounts)           -> void               # Dictionary{id: 数量}
clock()                 -> {day, hour, text}
set_time(day, seconds)  -> void
weather()               -> String
set_weather(id)         -> bool
energy()                -> {current, maximum}
refill_energy()         -> void
```

## 交互

| 组 | 控件 | 行为 |
|---|---|---|
| 货币 | `+10` / `+100` / `+1000` | 瓶盖按步长加 |
| 资源 | 每个物品一格，左键 `+10`、右键 `+100` | 走同一个 `add_item`，步长不同 |
| 资源 | `全部 +10` / `全部 +50` | 物品表里每一项各加一次 |
| 时间 | `−1 时` / `+1 时` / `−1 天` / `+1 天` | 叠在当前时刻上，跨午夜带天数 |
| 时间 | 深夜 / 黎明前 / 清晨 / 上午 / 正午 / 下午 / 夕阳 / 黑夜 | 跳到该时段首帧时刻，日期不动（时刻表来自 `daylight_slots.gd`）。4 列两行 —— 一行八格时每格只剩 68 px，「黎明前」会被纸边截断 |
| 天气 | 晴 / 多云 / 雨 | 改游戏真实天气；当前那一种高亮 |
| 体力 | 回满 | `EnergyModel.refill()` |

页面用奶油药丸风格并打 `island_label` 标记，让 Cozy 主题整棵跳过 —— 否则每个按钮会被顶到 44 px，五组控件能把面板撑出屏幕。

## 当前实现与待完成边界

四类动作与预览锁定已实现，`test-tools` 覆盖 23 项；1600×1000 与 1280×800 两档真实渲染已核对（面板整块在屏幕内、无行被截断）。待补：面板开着时游戏继续跑的长时段观感记录。测试工具不进发布玩法口径，`SEA-UI-R19` 的最小范围限制不受影响。

## 验收入口

`python3 scripts/run_verification.py test-tools`（隔离用户目录，不碰玩家槽位）。

## 2026-11-02 首版

P 面板从三页变四页；页面代码独立在 `src/debug/`，面板只负责挂载与转交端口。为什么分开：调色三页改的是「画面参数」，这一页改的是「游戏状态」，混在一个文件里，「面板只管画面」这条职责就没了。交付与实测见[记录](../../development/2026-11-02_test_tools_panel.md)。
