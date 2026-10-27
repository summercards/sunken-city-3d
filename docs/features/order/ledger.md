# SEA-ORDER · 交易与订单 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-order) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-ORDER",
  "status": "partial",
  "owner": "OrderBoard / 注入式交易展示",
  "code_paths": [
    "godot/src/orders",
    "godot/assets/data/orders.json",
    "godot/assets/data/trade_board.json"
  ],
  "verification": [
    "management",
    "selftest",
    "modules",
    "framework-integration"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-ORDER-R01 | 保持当前三槽长期订单配置；management通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-ORDER-R02 | 背包整笔扣货及奖励试装规则保留；modules/management通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-ORDER-R03 | 单次交付与补位快照；selftest/management通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-ORDER-R04 | 保留原规划历史身份；本次未改订单玩法数值 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-ORDER-R05 | 已实现并专项核验 | [框架交付记录](../../development/2026-10-27_modular_framework.md)；[模块接口约定](../../architecture/module_contracts.md) |
| SEA-ORDER-R06 | 已实现并专项核验 | [边界补强记录](../../development/2026-10-27_framework_boundary_hardening.md) |

## 资源与调用入口

- [godot/src/orders](../../../godot/src/orders)
- [godot/assets/data/orders.json](../../../godot/assets/data/orders.json)
- [godot/assets/data/trade_board.json](../../../godot/assets/data/trade_board.json)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

configure / fulfill / reroll / tick / to_dict / from_dict；changed、fulfilled；orders.slots 保留订单和补位剩余时间。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；兼容字段仅供已有调试工具，不作为新增业务写入口。

## 验证记录

当前入口：`python3 scripts/run_verification.py management selftest modules framework-integration`。

2026-10-23 历史实测结果见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 management、selftest、modules 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

订单规则保持纯端口注入；TradeBoard 注入 Orders，OrderPanel 注入 Inventory。额外交易品类和商人实体尚未扩展。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 2026-10-27 模块框架落地

订单规则保持纯端口注入；TradeBoard 注入 Orders，OrderPanel 注入 Inventory。额外交易品类和商人实体尚未扩展。

新增条款 SEA-ORDER-R05 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。

## 2026-10-27 查询与恢复边界补强

交易牌、面板与样式适配器已接查询；modules 验证返回副本和越界。

[本轮实测记录](../../development/2026-10-27_framework_boundary_hardening.md)。
