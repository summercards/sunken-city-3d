# SEA-RELEASE · 导出与发行 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-release) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-RELEASE",
  "status": "partial",
  "owner": "导出配置 / 发布工具",
  "code_paths": [
    "godot/export_presets.cfg",
    "tools/make_web_dist.py"
  ],
  "verification": [
    "structure"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-RELEASE-R01 | 本轮实际包内容通过 | [PCK 索引审计](../../development/2026-10-23_export_pack_audit.json)，禁止条目 0 |
| SEA-RELEASE-R02 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-RELEASE-R03 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |

## 资源与调用入口

- [godot/export_presets.cfg](../../../godot/export_presets.cfg)
- [tools/make_web_dist.py](../../../tools/make_web_dist.py)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

`python3 scripts/audit_export_pack.py <工程外 PCK 路径> --report <JSON 路径>`：实际读取包索引，检查禁止资源和必要运行入口。

## 验证记录

入口：`python3 scripts/check_feature_contracts.py`。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 尚无本功能独立运行验收，不将结构通过视为玩法完成。

## 遗留与下一步

本轮已完成实际 Web PCK 导出与内容审计：584 项、105,261,300 字节，禁止条目及必要入口缺失均为 0。完整 Web 启动、上传和设备验证未执行。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。
