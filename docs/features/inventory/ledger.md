# SEA-INVENTORY · 资源与背包 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-inventory) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-INVENTORY",
  "status": "partial",
  "owner": "Inventory / ItemDB",
  "code_paths": [
    "godot/src/inventory",
    "godot/assets/data/items.json"
  ],
  "verification": [
    "selftest",
    "management",
    "minimum-loop",
    "visual-plot-shipping",
    "visual-pocket-bubbles",
    "visual-pocket-services"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-INVENTORY-R01 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-INVENTORY-R02 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-INVENTORY-R03 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-INVENTORY-R04 | 已实现；详见本轮框架专项 | [交付记录](../../development/2026-10-27_modular_framework.md) |
| SEA-INVENTORY-R05 | 已实现；最小循环覆盖仓储、出货及满包拒绝 | [本轮交付](../../development/2026-10-27_minimum_loop_and_title.md) |
| SEA-INVENTORY-R06 | 已实现，场景点击与存读专项验证 | [本轮证据](../../development/2026-10-27_plot_shipping_loop.md) |

## 资源与调用入口

- [godot/src/inventory](../../../godot/src/inventory)
- [godot/assets/data/items.json](../../../godot/assets/data/items.json)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

- `godot/src/inventory/inventory.gd`：命令/查询 `count(id: String), all(), slots_of(id: String), slots_used(), capacity(), slots_free(), room_for(id: String), add(id: String, amount: int), can_add(id: String, amount: int), remove(id: String, amount: int), set_count(id: String, amount: int), has_all(costs: Dictionary), missing(costs: Dictionary), pay(costs: Dictionary), expand(extra_slots: int), to_dict(), from_dict(data: Dictionary), clear()`；事件 `changed(id: String, delta: int), capacity_changed(used: int, capacity: int)`。
- `godot/src/inventory/backpack_grid.gd`：命令/查询 `setup(font: Font, inventory: RefCounted), refresh()`；事件 `无`。
- `godot/src/inventory/item_db.gd`：命令/查询 `ensure_loaded(), capacity(), has(id: String), get_item(id: String), all_ids(), ids_in(category: String), label(id: String), icon(id: String), color(id: String), stack_limit(id: String), sell_price(id: String), is_currency(id: String)`；事件 `无`。

## 验证记录

入口：`python3 scripts/run_verification.py selftest management`。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 selftest、management 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

Economy 兼容属性仍存在；功能账本不重复保存玩家库存。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 2026-10-27 模块边界

Inventory.to_dict/from_dict；save_schema.inventory 为容量和计数契约；Economy 为兼容门面，具体数量仍由 Inventory 唯一写入。

[模块接口约定](../../architecture/module_contracts.md) · [本轮证据](../../development/2026-10-27_modular_framework.md)。

2026-10-27 场景点击循环：07:00收货、瓶盖、木土种植格及码头出货箱；[本轮记录](../../development/2026-10-27_plot_shipping_loop.md)。

## 2026-10-28 场景气泡与口袋界面

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-INVENTORY-R07 | 已实现；实际渲染与输入专项通过；设备/授权边界单列 | [交付记录](../../development/2026-10-28_pocket_action_bubbles.md) |

本轮运行结果、过程失败、退出码与未执行项集中记在交付记录。旧记录保留为历史，整体状态仍partial。

2026-10-28 服务界面补齐：R07扩展为存取1件或所选整叠；所有权和原子容量拒绝不变。见[本轮记录](../../development/2026-10-28_service_pockets.md)。

2026-10-28 恢复验收（request ID `21726f14-a5f7-438f-9db2-83ed622dd271`）：当前源码重新通过服务口袋、实体出货箱全流程、场景气泡三项真实渲染专项及最小循环/模块检查；完整世界3项可行走面失败单列，不签署全工程通过。见[本轮记录](../../development/2026-10-28_service_pockets.md)与[机器证据](../../development/2026-10-28_service_pockets.json)。
