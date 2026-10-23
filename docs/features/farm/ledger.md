# SEA-FARM · 种植与日常照料 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-farm) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-FARM",
  "status": "partial",
  "owner": "FarmModel",
  "code_paths": [
    "godot/src/farming",
    "godot/assets/data/crops.json",
    "godot/scenes/props/farm_plot.tscn",
    "godot/scenes/props/farm_cell.tscn"
  ],
  "verification": [
    "farming",
    "management",
    "modules"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-FARM-R01 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-FARM-R02 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-FARM-R03 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-FARM-R04 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-FARM-R05 | 注入边界已实现并专项验证 | modules 无 Autoload/无 Main 通过；farming 与真实渲染种植闭环通过；地格表现层仍经 Economy 入口 |

## 资源与调用入口

- [godot/src/farming](../../../godot/src/farming)
- [godot/assets/data/crops.json](../../../godot/assets/data/crops.json)
- [godot/scenes/props/farm_plot.tscn](../../../godot/scenes/props/farm_plot.tscn)
- [godot/scenes/props/farm_cell.tscn](../../../godot/scenes/props/farm_cell.tscn)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

- `godot/src/farming/farm_field.gd`：命令/查询 `build(), find(plot_id: String)`；事件 `acted(plot_id: String, event: String, payload: Dictionary)`。
- `godot/src/farming/farm_plot.gd`：命令/查询 `setup(data: Dictionary), focus_text(), blocked_reason(), interact(_actor: Node3D)`；事件 `acted(plot_id: String, event: String, payload: Dictionary)`。
- `godot/src/farming/farm.gd`：命令/查询 `configure(boundary: RefCounted), select_crop(crop_id: String), spec(plot_id: String), crop_def(crop_id: String), state(plot_id: String), crop_of(plot_id: String), is_empty(plot_id: String), phase(plot_id: String), is_dry(plot_id: String), progress(plot_id: String), grow_days(crop_id: String), yield_of(crop_id: String), crop_name(crop_id: String), action_label(plot_id: String), blocked_reason(plot_id: String), status_text(plot_id: String), interact(plot_id: String, crop_id: String = ""), plant(plot_id: String, crop_id: String), water(plot_id: String), harvest(plot_id: String), tick(_delta: float), advance_day(), refill(), buy_seed(crop_id: String), exchange_seed(), sell_produce(), to_dict(), from_dict(data: Dictionary)`；事件 `planted(plot_id: String, crop_id: String), watered(plot_id: String), harvested(plot_id: String, rewards: Dictionary), became_ready(plot_id: String, crop_id: String), plots_changed, day_changed(day: int)`。

`farming_ports.gd` 在入树前注入 inventory、pay、give、has_greenhouse、access_reason；设施/解锁由宿主适配，作物状态由 FarmModel 持有。

## 验证记录

入口：`python3 scripts/run_verification.py farming management modules`。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 farming、management、modules 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

地格表现仍经 Economy.farm 兼容入口；土地开垦、工具升级、品质和季节为规划。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。
