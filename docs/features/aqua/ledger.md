# SEA-AQUA · 浅水养殖 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-aqua) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-AQUA",
  "status": "partial",
  "owner": "规划：AquacultureService / 渔场升级段：FisheryModel",
  "code_paths": [
    "godot/src/aqua/fishery_service.gd",
    "godot/src/ui/fishery_panel.gd"
  ],
  "verification": [
    "fishery",
    "visual-fishery"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-AQUA-R01 | 规划待实现 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-AQUA-R02 | 规划待实现 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-AQUA-R03 | 规划待实现 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-AQUA-R04 | 已实现；木牌气泡「升级为渔场」，木板 100 + 鱼 50，背包与仓库合并计数扣费，不足禁用、已升级不重复扣 | [本轮交付](../../development/2026-11-01_energy_fishery_and_join.md)（`fishery` 28 项 0 失败） |
| SEA-AQUA-R05 | 已实现；升级后木牌改名「渔场」+ 平台插旗，状态进存档、旧档读成未升级、读档恢复表现 | 同上 |

## 资源与调用入口

- `godot/src/aqua/fishery_service.gd`：`configure({count,pay,missing_text})`、`reason()`、`missing_text()`、`held()`、`can_upgrade()`、`upgrade()`、`to_dict()/from_dict()`、`changed` 信号；成本常量 `COST = {wood:100, fish:50}`。
- `godot/src/ui/fishery_panel.gd`：`build(body, economy, perform)`，与种植页共用行列表。
- 养殖生态（R01–R03）仍无实现。

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

渔场升级段见上「资源与调用入口」；养殖生态尚无正式接口。

## 验证记录

入口：尚无专项实现；先完成设计和测试入口，再进入实现阶段。。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 尚无本功能独立运行验收，不将结构通过视为玩法完成。

## 遗留与下一步

区域和平台种植已存在，但独立鱼类养殖未实现。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 变更记录（续）

- 2026-11-01：家园补给站改造为渔场的第一段（R04/R05）落地并登记；状态由 `planned` 改为 `partial`，`code_paths` 与 `verification` 同步补齐。养殖生态仍为规划，不因本次升级自动升级完成度。
