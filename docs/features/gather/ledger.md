# SEA-GATHER · 岸边采集 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-gather) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-GATHER",
  "status": "partial",
  "owner": "GatherField / GatherSpot",
  "code_paths": [
    "godot/src/gathering",
    "godot/assets/data/gather_spots.json"
  ],
  "verification": [
    "selftest",
    "framework-integration"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-GATHER-R01 | 稳定采集点配置，建筑前置注入；selftest通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-GATHER-R02 | GatherField持有剩余冷却序列化；selftest存档段通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-GATHER-R03 | 溢出反馈经经济适配器；selftest通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-GATHER-R04 | 已实现并专项核验 | [框架交付记录](../../development/2026-10-27_modular_framework.md)；[模块接口约定](../../architecture/module_contracts.md) |

## 资源与调用入口

- [godot/src/gathering](../../../godot/src/gathering)
- [godot/assets/data/gather_spots.json](../../../godot/assets/data/gather_spots.json)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

GatherField.to_dict / from_dict；GatherSpot.interact / seconds_left；collected；建设前置 construction 注入。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；兼容字段仅供已有调试工具，不作为新增业务写入口。

## 验证记录

当前入口：`python3 scripts/run_verification.py selftest framework-integration`。

2026-10-23 历史实测结果见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 selftest 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

采集节点注入 ConstructionService 查询等级，GatherField 独立保存相对冷却。节点内的规则与程序造型可继续按美术需求拆分。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 2026-10-27 模块框架落地

采集节点注入 ConstructionService 查询等级，GatherField 独立保存相对冷却。节点内的规则与程序造型可继续按美术需求拆分。

新增条款 SEA-GATHER-R04 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。
