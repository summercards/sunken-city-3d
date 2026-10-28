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
    "framework-integration",
    "minimum-loop",
    "visual-plot-shipping",
    "visual-pocket-services",
    "visual-home-lighting"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-ORDER-R01 | 本轮实现；正式最小范围与独立专项验证 | [本轮交付](../../development/2026-10-27_minimum_loop_and_title.md) |
| SEA-ORDER-R02 | 背包整笔扣货及奖励试装规则保留；modules/management通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-ORDER-R03 | 单次交付与补位快照；selftest/management通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-ORDER-R04 | 保留原规划历史身份；本次未改订单玩法数值 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-ORDER-R05 | 已实现并专项核验 | [框架交付记录](../../development/2026-10-27_modular_framework.md)；[模块接口约定](../../architecture/module_contracts.md) |
| SEA-ORDER-R06 | 已实现并专项核验 | [边界补强记录](../../development/2026-10-27_framework_boundary_hardening.md) |
| SEA-ORDER-R07 | 本轮实现；正式最小范围与独立专项验证 | [本轮交付](../../development/2026-10-27_minimum_loop_and_title.md) |
| SEA-ORDER-R08 | 本轮实现；正式最小范围与独立专项验证 | [本轮交付](../../development/2026-10-27_minimum_loop_and_title.md) |
| SEA-ORDER-R09 | 已实现，场景点击与存读专项验证 | [本轮证据](../../development/2026-10-27_plot_shipping_loop.md) |

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

## 2026-10-27 当前最小循环与开始画面

本节及本轮修改条款优先于下方保留的历史范围。默认发布配置只开放家园生活循环；旧全功能验证须显式 `--full-world`，不能代替最小版本验收。接口、迁移及实测见[交付记录](../../development/2026-10-27_minimum_loop_and_title.md)。

2026-10-27 场景点击循环：07:00收货、瓶盖、木土种植格及码头出货箱；[本轮记录](../../development/2026-10-27_plot_shipping_loop.md)。

## 2026-10-28 服务界面补齐

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-ORDER-R10 | 已实现；真实GUI存取、商店购买与三分辨率专项 | [实测记录](../../development/2026-10-28_service_pockets.md) |

DailyShipping.query新增capacity/slots_used只读字段；存档结构、结算时刻与售价保持不变。

2026-10-28 恢复验收（request ID `21726f14-a5f7-438f-9db2-83ed622dd271`）：当前源码重新通过服务口袋、实体出货箱全流程、场景气泡三项真实渲染专项及最小循环/模块检查；完整世界3项可行走面失败单列，不签署全工程通过。见[本轮记录](../../development/2026-10-28_service_pockets.md)与[机器证据](../../development/2026-10-28_service_pockets.json)。

## 2026-10-28 家园箱子与夜灯修复

SEA-ORDER-R09/R10：稳定出货箱模型与交互同锚点；当前实体点击专项及出货、取回、07:00结算流程通过。

[交付记录](../../development/2026-10-28_home_lighting_recovery.md)。
