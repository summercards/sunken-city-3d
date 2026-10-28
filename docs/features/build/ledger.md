# SEA-BUILD · 建筑修缮与升级 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-build) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-BUILD",
  "status": "partial",
  "owner": "ConstructionService / BuildSite",
  "code_paths": [
    "godot/src/construction"
  ],
  "verification": [
    "selftest",
    "management",
    "framework-modules"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-BUILD-R01 | 独立支付端口开工；modules 与 management 验证 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-BUILD-R02 | 重复开工不扣费、计时完成后升级；framework-modules | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-BUILD-R03 | 现有升级反馈保留；原绞盘站三级成长内容仍待完成 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-BUILD-R04 | 已实现并专项核验 | [框架交付记录](../../development/2026-10-27_modular_framework.md)；[模块接口约定](../../architecture/module_contracts.md) |

## 资源与调用入口

- [godot/src/construction](../../../godot/src/construction)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

begin_site_upgrade / tick_sites / site_level / site_next_cost；sites_changed、site_work_started、site_work_finished；to_dict/from_dict 包含 site_levels、site_work。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；兼容字段仅供已有调试工具，不作为新增业务写入口。

## 验证记录

当前入口：`python3 scripts/run_verification.py selftest management framework-modules`。

2026-10-23 历史实测结果见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 selftest、management 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

施工状态和费用规则已移入 ConstructionService；BuildSite/BuildField 注入该服务。绞盘站三级成长等原设计内容仍待接入。

## 变更记录

- 2026-10-28：完成海上木板扩建与种植摆件的静态研究，现有固定升级与发布范围不变；自由放置、通用玩法包装、动态空间和布局存档仍待实施。[研究方案](../../development/2026-10-28_buildable_deck_planters_research.md)。本记录不表示新增功能已实现或运行验收通过。

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 2026-10-27 模块框架落地

施工状态和费用规则已移入 ConstructionService；BuildSite/BuildField 注入该服务。绞盘站三级成长等原设计内容仍待接入。

新增条款 SEA-BUILD-R04 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。
