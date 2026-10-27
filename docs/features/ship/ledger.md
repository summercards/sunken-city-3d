# SEA-SHIP · 船只升级与区域解锁 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-ship) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-SHIP",
  "status": "partial",
  "owner": "ShipService / 航速与区域资格适配",
  "code_paths": [
    "godot/src/ship/ship_service.gd",
    "godot/src/navigation/boat.gd"
  ],
  "verification": [
    "management",
    "surface",
    "framework-modules"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-SHIP-R01 | 升级支付与等级由ShipService拥有；模块/经营专项通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-SHIP-R02 | 升级事件投影远海资格、Boat查询航速；经营/表面移动专项通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-SHIP-R03 | 仍待内容：船型、运输及更深探索没有冒充已实现 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-SHIP-R04 | 已实现并专项核验 | [框架交付记录](../../development/2026-10-27_modular_framework.md)；[模块接口约定](../../architecture/module_contracts.md) |

## 资源与调用入口

- [godot/src/ship/ship_service.gd](../../../godot/src/ship/ship_service.gd)
- [godot/src/navigation/boat.gd](../../../godot/src/navigation/boat.gd)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

upgrade_ship / ship_cost / to_dict / from_dict；upgraded、resources_changed；ship_level。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；兼容字段仅供已有调试工具，不作为新增业务写入口。

## 验证记录

当前入口：`python3 scripts/run_verification.py management surface framework-modules`。

2026-10-23 历史实测结果见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 management、surface 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

船级由 ShipService 唯一拥有，升级事件由装配层投影远海资格，Boat 注入航速查询。船型变化、运输和更深探索仍待内容制作。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 2026-10-27 模块框架落地

船级由 ShipService 唯一拥有，升级事件由装配层投影远海资格，Boat 注入航速查询。船型变化、运输和更深探索仍待内容制作。

新增条款 SEA-SHIP-R04 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。
