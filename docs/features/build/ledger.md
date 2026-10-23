# SEA-BUILD · 建筑修缮与升级 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-build) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-BUILD",
  "status": "partial",
  "owner": "Economy 建造状态 / BuildSite",
  "code_paths": [
    "godot/src/construction"
  ],
  "verification": [
    "selftest",
    "management"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-BUILD-R01 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-BUILD-R02 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-BUILD-R03 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |

## 资源与调用入口

- [godot/src/construction](../../../godot/src/construction)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

- `godot/src/construction/build_site.gd`：命令/查询 `setup(row: Dictionary), focus_text(), can_interact(), hold_time_for(), blocked_reason(), interact(_actor: Node3D)`；事件 `work_started(site_id: String, site_name: String, seconds: float)`。
- `godot/src/construction/build_field.gd`：命令/查询 `build(path := TABLE), find(id: String), zone_sites(zone_id: String)`；事件 `work_started(id: String, name: String, seconds: float), finished(id: String, level: int)`。

## 验证记录

入口：`python3 scripts/run_verification.py selftest management`。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 selftest、management 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

建造状态和常量仍在 Economy；绞盘站三级成长等原设计尚未全部接入。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。
