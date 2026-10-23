# SEA-GATHER · 岸边采集 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-gather) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-GATHER",
  "status": "partial",
  "owner": "GatherSpot / GatherField",
  "code_paths": [
    "godot/src/gathering",
    "godot/assets/data/gather_spots.json"
  ],
  "verification": [
    "selftest"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-GATHER-R01 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-GATHER-R02 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-GATHER-R03 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |

## 资源与调用入口

- [godot/src/gathering](../../../godot/src/gathering)
- [godot/assets/data/gather_spots.json](../../../godot/assets/data/gather_spots.json)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

- `godot/src/gathering/gather_field.gd`：命令/查询 `build(path := TABLE), zone_spots(zone_id: String), find(id: String)`；事件 `collected(kind: String, amount: int, label: String, spot: Node3D), blocked(reason: String)`。
- `godot/src/gathering/gather_spot.gd`：命令/查询 `setup(data: Dictionary), can_interact(), blocked_reason(), interact(_actor: Node3D), debug_advance(seconds: float), seconds_left(), restore_cooldown(seconds: float)`；事件 `harvested(kind: String, amount: int, label: String)`。

## 验证记录

入口：`python3 scripts/run_verification.py selftest`。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 selftest 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

规则和程序造型仍在同一节点，需要表现替换时继续拆分。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。
