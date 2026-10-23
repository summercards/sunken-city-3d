# SEA-UI · HUD 与菜单反馈 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-ui) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-UI",
  "status": "partial",
  "owner": "HUD / UI presenters",
  "code_paths": [
    "godot/src/ui"
  ],
  "verification": [
    "click",
    "management"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-UI-R01 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-UI-R02 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-UI-R03 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |

## 资源与调用入口

- [godot/src/ui](../../../godot/src/ui)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

- `godot/src/ui/hud.gd`：命令/查询 `open_tab(tab: String), toast(text: String, seconds := 2.4), set_diving(on: bool), set_dive_air(ratio: float, lamp_on: bool, found: int, total: int), air_color(ratio: float), set_dive_zone(name: String), set_dive_depth(depth: float), note_zoom(ratio: float)`；事件 `destination_pressed(zone_id: String), dive_pressed, build_pressed, site_focus_requested(id: String), plot_focus_requested(id: String), command_requested(command: String), rest_requested, facility_build_requested(id: String), ship_upgrade_requested`。
- `godot/src/ui/landing_markers.gd`：命令/查询 `build(cam: Camera3D), pick(screen_pos: Vector2, radius: float = 26.0), set_highlight(zone_id: String)`；事件 `无`。
- `godot/src/ui/cozy_ui.gd`：命令/查询 `surface(color: Color, radius: int = 22), button_color(text: String), animate(control: Control, scale_to: float), reveal(control: Control), apply(control: Control), apply_tree(root: Node), apply_instance(instance_id: int)`；事件 `无`。
- `godot/src/ui/ui_font.gd`：命令/查询 `embedded(), make(font_names: PackedStringArray)`；事件 `无`。

## 验证记录

入口：`python3 scripts/run_verification.py click management`。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 click、management 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

- 2026-10-23 真实事件补充：visual-click 退出 1，第二地格点击目标断言失败；拆分前基线同样失败，完整根因待定位。不得以核心 click 通过覆盖此失败。详见[交付记录](../../development/2026-10-23_feature_split.md)。

## 遗留与下一步

部分 UI 仍直接读取业务字段；功能级面板分别由所属功能代码目录管理。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。
