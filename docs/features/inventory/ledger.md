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
    "visual-corner-notebook",
    "selftest",
    "management",
    "minimum-loop",
    "visual-plot-shipping",
    "visual-pocket-bubbles",
    "visual-pocket-services",
    "pocket-drag-buy",
    "visual-pocket-drag-buy",
    "shop-rules",
    "npc-integration",
    "npc-save"
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


## 2026-10-28 HUD与笔记表现接线

左下显示真实瓶盖、已用格/容量，使用原白色圆体且无背板。背包仍由B/Tab或右上图标进入；背包内“生活手册”改名“海岛笔记”。笔记物产卡读取背包/仓库数量，不复制或写回Inventory。

对应SEA-UI-R35–R38；[本轮交付](../../development/2026-10-28_corner_hud_notebook.md)。本功能整体状态与玩法边界保留。

## 2026-10-29 家园建造接入

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-INVENTORY-R08 | 已实现；相关专项通过，详细范围以交付记录为准 | [本轮交付](../../development/2026-10-28_building_delivery.md) |

## 2026-10-29 背包排列与批量购买

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-INVENTORY-R09 | 已实现：`ordered_ids` / `move_item` / `move_to_end`，`order` 随数量一起存档且进 schema（不进 required） | `pocket-drag-buy` 覆盖互换、可逆还原、挪末尾、多堆相邻、存档往返、**旧档无 order 可读**、脏 order 过滤；[本轮交付](../../development/2026-10-29_pocket_drag_buy.md) |
| SEA-INVENTORY-R10 | 已实现：`material_shop.buy_soil(amount)` / `farm.buy_seed(crop_id, amount)` 总价与余量一起检查，被拒时一分不扣 | `pocket-drag-buy` 覆盖"钱不够买 3 包被拒且不扣不加""背包满买 2 份被拒且不扣不加""买 2 份一起到账并按份扣款" |

`try_pickup` 已于同批删除（见 SEA-PICKUP-R09），本功能接口清单不受影响。存档新增字段只增不改，旧档读取路径有专门断言。

## 2026-10-29 建造材料退款

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-INVENTORY-R11 | 已实现；多材料占用同一剩余格拒绝无变化，未满堆可完整返还；回调重入受建造提交锁保护 | [本轮交付](../../development/2026-10-29_open_ocean_building.md) |

## 2026-11-07 原子交换接口承接

按现有最大R11稳定追加 [SEA-INVENTORY-R12](spec.md#2026-11-07-npc--shop-原子交换接口追加)；不改R01–R11、旧接口快照、登记头顺序或历史结论，整体status继续 `partial`，不因NPC/Shop交付升级整个背包系统。

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-INVENTORY-R12 | 已实现真实Inventory.exchange的双边预校验、costs足额/最终候选容量、同物品净差、单owner先提交数量/排列后发信号；失败不改现场。业务有效项要求有限正整数，当前底层兼容0和整值float的差异如实保留，不称严格正整数拒绝已通过 | 221054 `shop-rules`259/0是fake规则/输入证据；214439正式 `npc-integration`668/0、`npc-save`618/0及重启证据另列，不把fake替代生产原子性或声称所有边界独立测完 |

### 公开端口与所有者

[inventory.gd](../../../godot/src/inventory/inventory.gd)新增 `exchange(costs: Dictionary, gains: Dictionary) -> Dictionary`，返回 `{ok, reason}`。两边逐项校验String且ItemDB存在的ID、有限整数数值及每项≤1000000000；候选单物品最终计数同受该上限保护。当前允许0无数量效果，空costs/gains可表示纯奖励/纯消耗；业务提交只使用正整数有效项，不虚构零值拒绝。非整值float、负数、bool、字符串、NaN/Inf、未知ID均拒绝。

先足额扣costs，再合gains，不能拿本次所得抵扣原本不足的costs；同ID最终只发一次非零净差changed，容量按最终候选/堆叠算（货币不占格）。成功一次替换counts并登记新增非货币物品order，再发changed及capacity_changed；拒绝不改数量/排列、不发这两类信号。库存仍只有Inventory写入，不新增存档字段，不取代双库存InventoryTransfer。Shop/NPC的去重、剧情、礼物关系与请求状态各归其服务，本端口不承诺跨进程exactly-once。

[ShopService](../../../godot/src/shop/shop_service.gd) / [NpcService](../../../godot/src/npc/npc_service.gd)只消费注入命令，不以pay/add/remove+退款拼原子性；规则详见[Shop](../shop/spec.md)与[NPC](../resident/spec.md)，不在本账本复制一份商品/余额/关系记录。

### 已执行证据分层

| 证据 / 日志 | 实测结果 | 适用范围 |
|---|---|---|
| [221054最新回归报告](../../../../sea-work/verification/20261107-221054-npc-final-regression-bc8a22/report.json) / [shop-rules.log](../../../../sea-work/verification/20261107-221054-npc-final-regression-bc8a22/shop-rules.log) | shop-rules259/0，exit0/PASS；整批11项均PASS/exit0、unexpected_errors空 | fake原子库存上的商店规则/UI输入与有限token，不单独证明真实Inventory；此前[213213报告](../../../../sea-work/verification/20261107-213213-shop-input-final-638cdf/report.json)同为259/0，历史不替换最新 |
| [214439正式天台报告](../../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/report.json) / [npc-integration.log](../../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/npc-integration.log) | npc-integration668/0，exit0/PASS | 正式Main→NPC/Shop→真实Inventory交易、礼物/请求及拒绝/恢复链；不是只靠fake或住所版历史结果 |
| 同报告 / [npc-save.log](../../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/npc-save.log) | npc-save618/0、seed408/0、restart202/0，均exit0/PASS | 当前天台坏档不改现场、库存联合持久化与跨进程恢复，具体覆盖以测试/日志为准 |

214439五项还含visual-npc-release381/0，总2277/0，全部PASS/exit0、completion_marker=true、unexpected_errors=[]；完整命令、head/working_tree、隔离数据与快照见报告。该总数是联合交付范围，不是新增2277条Inventory原子边界断言。上述生产通过不签零值拒绝、全部极值/监听重入或背包所有旧条款已完整独测；既有R01–R03待核及其他未验继续保留。

本次只核对现有证据并补接口文档；未重跑Godot/global sync/最终门禁，后者由主线程统一负责，不写全产品验收通过。

## 2026-11-14 B2 原子收支与重入承接

承接SEA-INVENTORY-R02/R03/R05/R09/R10/R11/R12（S15/S16/G03）：pay/add_all/exchange以整体候选提交后发实际变化，发布期is_busy拒绝重入修改；InventoryTransfer.exchange双端预检/静默提交，目标失败回滚两端counts/order与原屏蔽状态、零退款事件；成功两端busy后各发实际差量/容量。单项add原部分接收语义不被扩大成复合奖励保证。正式Farm/Orders、salvage与SeaProps接原子端口，业务owner锁跨支付到自身状态，Main统一拒绝中间保存。

b2-transactions103/0、b2-pickup-transactions191/0、真实会话51/0均PASS/exit0，覆盖双端完成态、异命令/失败回滚、复合奖励0/1/2格等实际范围；不据此签全部数量上限/容量历史政策或所有并发场景，wire不增日志。登记头partial保持，视觉/最终契约待父。[B2主记录与精确证据](../../development/2026-11-13_engine_deep_audit.md#b2-业务事务与空间修复最终回填2026-11-14)。

### B2 最终状态（2026-11-14）· [主记录](../../development/2026-11-13_engine_deep_audit.md#b2-最后复测与签署范围2026-11-14)
- 005436 transactions103/0、pickup191/0均PASS/exit0；012421-b2-session-valid-confirm-d25e8b强化真实可支付且旧确认Callable有效的前置后53/0、exit0，睡醒后旧确认不扣费/购买/升级。
- 仅签实际原子收支、重入与会话覆盖，不扩为全部容量政策或并发写保证；全库契约仍失败，登记头partial保持，视觉及冻结证据边界按主记录。

## 2026-11-14 B3 ItemDB 查询边界承接

`ItemDB.get_item`现返回递归副本；物品表内部加载、顺序、容量、标签、堆叠和售价权威不变。`b3-query-copy`覆盖修改返回字典及嵌套数组后再次查询不污染内部定义，exit0；该项不解决D01统一内容schema、D02超容旧档政策或全局资产门禁，登记头partial保持。
