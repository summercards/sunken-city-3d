# SEA-TOOL · 测试工具 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-tool) · [功能文档](spec.md)

## 登记头

```json
{
  "feature_id": "SEA-TOOL",
  "status": "implemented",
  "owner": "ColorGradePanel（入口）/ TestToolsPage（页面）；状态仍归 SEA-INVENTORY、SEA-TIME、SEA-WEATHER、SEA-ENERGY",
  "code_paths": [
    "godot/src/debug/test_tools_page.gd",
    "godot/src/rendering/color_grade_panel.gd",
    "godot/src/bootstrap/main.gd",
    "godot/tests/test_test_tools.gd"
  ],
  "verification": [
    "test-tools"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-TOOL-R01 | 已实现；P 面板第四页，默认页仍是滤镜 | `test-tools`：默认 `_tab == filter`、「测试」页可切换并显示 |
| SEA-TOOL-R02 | 已实现；走 `Economy.give`，格子由物品表生成 | `test-tools`：木板/瓶盖单项与「全部 +10」都落到 Inventory |
| SEA-TOOL-R03 | 已实现；只写 `day`/`seconds` 并广播既有事件 | `test-tools`：±1 时、跳时段、±1 天、跨午夜带天数、`day >= 1` |
| SEA-TOOL-R04 | 已实现；只调 `set_weather` | `test-tools`：雨/多云生效，非法天气被拒且状态不变 |
| SEA-TOOL-R05 | 已实现；只调 `refill()` | `test-tools`：3 → 满 |
| SEA-TOOL-R06 | 已实现；端口注入 + 预览放开 | `test-tools`：测试页 `is_previewing() == false`，切回光照页重新锁定，关面板放开 |
| SEA-TOOL-R07 | 验收入口已接入统一 runner | `python3 scripts/run_verification.py test-tools` |

## 当前接口清单

- `ColorGradePanel.set_test_ports(ports: Dictionary)` —— 主场景注入；缺项即禁用对应分组。
- `ColorGradePanel.test_tools()` —— 把页面交出去，验收脚本按用户点击的同一条路走。
- `TestToolsPage.add_item(id, amount)` / `add_all(amount)` / `shift_hours(h)` / `shift_days(d)` / `jump_to_hour(h)` / `set_weather(id)` / `refill_energy()`。
- `Main._debug_set_clock(day, seconds)` —— 唯一的时间写入口，只改 `WorldClock` 公开字段并广播 `changed`（跨日再补一次 `day_changed`）。
- `Main._debug_catalog()` —— 从 `assets/data/items.json` 生成可加物品清单。

## 资源归属

不新增美术资产，不新增 AssetID。页面用程序绘制的药丸控件，配色沿用面板现有的奶油色板。

## 遗留与下一步

- 真实渲染下的版面核对（1280×800 / 1600×1000）未做；当前只保证逻辑与挂载，`visual-*` 另开。
- 测试工具不进发布玩法口径；`SEA-UI-R19` 的最小范围限制与 `play_scope.gd` 未改。

## 变更记录

- 2026-11-02：新增 SEA-TOOL。P 面板第四页，页面代码独立到 `godot/src/debug/`，主场景改为注入端口。见[交付记录](../../development/2026-11-02_test_tools_panel.md)。

## 2026-11-10 楼房工坊入口承接

SEA-TOOL 不拥有楼房工坊状态；本轮只记录它作为工程验证入口的承接关系。暂停菜单的「楼房工坊」命令由 Main 薄接线转给 `WorkshopHost`，工坊内部仍由 SEA-WORKSHOP 的 `WorkshopSession`、`WorkshopStore` 与独立预览负责。工具侧不得把 `user://building_workshop/<id>/revision_NNNN` 候选文件误写成玩家存档或 SEA-TOOL 状态。

- 入口：`godot/src/ui/island_menu.gd` → `building_workshop` 命令 → `godot/src/bootstrap/main.gd` → `godot/src/workshop/host.gd`。
- 验证：工坊专项 runner 见 [SEA-WORKSHOP 账本](../workshop/ledger.md)；主集成测试因旧的 `LineEdit Ctrl+Z` 文本假设已发现失败，待主线程修正测试后重跑，不在本条签全通过。
