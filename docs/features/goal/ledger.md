# SEA-GOAL · 小目标追踪与引导 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-goal) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-GOAL",
  "status": "partial",
  "owner": "Economy 目标追踪 / HUD",
  "code_paths": [
    "godot/src/economy/economy.gd",
    "godot/src/ui/hud.gd"
  ],
  "verification": [
    "management"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-GOAL-R01 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-GOAL-R02 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-GOAL-R03 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |

## 资源与调用入口

- [godot/src/economy/economy.gd](../../../godot/src/economy/economy.gd)
- [godot/src/ui/hud.gd](../../../godot/src/ui/hud.gd)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

- `godot/src/economy/economy.gd`：命令/查询 `can_salvage(now: float), salvage_cooldown_left(now: float), commit_salvage(now: float, haul: Dictionary), do_salvage(now: float), give(rewards: Dictionary), add_resource(key: String, amount: int), count(id: String), has(cost: Dictionary), missing(cost: Dictionary), pay(cost: Dictionary), missing_text(cost: Dictionary), cost_text(cost: Dictionary), site_level(id: String), site_next_cost(id: String), site_maxed(id: String), site_build_seconds(id: String), is_building(id: String), site_work_left(id: String), site_work_progress(id: String), begin_site_upgrade(id: String), tick_sites(delta: float), facility_unlocked(id: String), facility_requirement_text(id: String), can_build_facility(id: String), build_facility(id: String), can_upgrade_ship(), upgrade_ship(), to_dict(), from_dict(data: Dictionary), construction_count(id: String), construction_has(cost: Dictionary), construction_pay(cost: Dictionary), construction_missing_text(cost: Dictionary), construction_progress(cost: Dictionary), deposit_materials(), withdraw_material(id: String), ship_cost(), goal_complete(id: String), goal_info(), track_goal(id: String)`；事件 `resources_changed, sites_changed, site_work_started(id: String, seconds: float), site_work_finished(id: String, level: int), salvage_ready, overflow(id: String, amount: int), item_gained(id: String, amount: int)`。
- `godot/src/ui/hud.gd`：命令/查询 `open_tab(tab: String), toast(text: String, seconds := 2.4), set_diving(on: bool), set_dive_air(ratio: float, lamp_on: bool, found: int, total: int), air_color(ratio: float), set_dive_zone(name: String), set_dive_depth(depth: float), note_zoom(ratio: float)`；事件 `destination_pressed(zone_id: String), dive_pressed, build_pressed, site_focus_requested(id: String), plot_focus_requested(id: String), command_requested(command: String), rest_requested, facility_build_requested(id: String), ship_upgrade_requested`。

## 验证记录

入口：`python3 scripts/run_verification.py management`。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 management 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

已有小目标不是完整首局教学；分步引导与真人节奏验收待做。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。
