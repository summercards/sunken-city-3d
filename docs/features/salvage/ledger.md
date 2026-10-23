# SEA-SALVAGE · 绞盘打捞 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-salvage) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-SALVAGE",
  "status": "partial",
  "owner": "SalvageModel / 结算冷却协调",
  "code_paths": [
    "godot/src/salvage"
  ],
  "verification": [
    "selftest",
    "management",
    "modules"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-SALVAGE-R01 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-SALVAGE-R02 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-SALVAGE-R03 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |

## 资源与调用入口

- [godot/src/salvage](../../../godot/src/salvage)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

- `godot/src/salvage/salvage_panel.gd`：命令/查询 `cancel(), begin(), is_open()`；事件 `finished(haul: Dictionary, success: bool)`。
- `godot/src/salvage/salvage_winch.gd`：命令/查询 `setup(data: Dictionary), can_interact(), blocked_reason(), focus_text(), interact(_actor: Node3D), play_reel(turns := 2.0), play_snap()`；事件 `opened(winch: Node3D)`。
- `godot/src/salvage/salvage.gd`：命令/查询 `start(), press(), update(delta: float, holding: bool), is_active(), is_finished(), accuracy(), tension_offset(), haul(), summary()`；事件 `无`。

## 验证记录

入口：`python3 scripts/run_verification.py selftest management modules`。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 selftest、management、modules 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

冷却与奖励提交仍在 Economy；规则模型已独立。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。
