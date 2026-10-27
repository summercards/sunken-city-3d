# SEA-WAREHOUSE · 材料仓储

[主文档中控](../../../GDD_V1.0.md#sea-warehouse) · [本功能账本](ledger.md)

设计修订：r1（2026-10-23 工程拆分，未更改玩法数值）。所属系统：经营。
范围来源：主文档保留的全局设计、拆分前文档与当前代码核对；下面明确区分目标与实现边界。

## 功能目的与边界

正式或规划入口：建仓后背包页一键存材料、按物品取回。

本功能以这一玩家行为或工程交付闭环为管理粒度，内部操作作为设计条款逐项承接；不按脚本数量拆功能。跨功能前置和关系由主文档本行统一维护。

## 设计条款与验收标准

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-WAREHOUSE-R01 | 仓库提供 48 格，仅接受 material 类；货币、种子和作物留在背包。 |
| SEA-WAREHOUSE-R02 | 存取不丢数量：仓满留在背包，包满留在仓库。 |
| SEA-WAREHOUSE-R03 | 建设先使用背包再使用仓库，订单不能自动消费仓库；旧档缺仓库时补空仓。 |
| SEA-WAREHOUSE-R04 | 仓库只经注入的资源和设施端口交换数据，持久化唯一归属 WarehouseService。 |

## 所有者、接口与数据

状态/交付所有者：**WarehouseService / 独立 Inventory**。正式代码和资源入口：

- [godot/src/warehouse/warehouse_service.gd](../../../godot/src/warehouse/warehouse_service.gd)

读取上述所有者的公开查询，修改通过其命令或交互入口；事件由拥有该状态的对象发出。具体公开方法、信号和持久化字段见本账本的接口清单。原有稳定 ContentID、场景 ID 和存档键保持不变，重命名须另做迁移。

共享资源的所有权以被依赖功能为准。本功能引用它们，不复制背包数值、资产记录或其他功能规则。规划中的接口尚无实现时必须先补契约再编码。

## 当前实现与待完成边界

仓储规则已独立到 WarehouseService，通过设施资格端口及注入的背包实例存取；暂无独立仓库建筑模型。

2026-10-27 接口：deposit_materials / withdraw_material / construction_pay / construction_count / construction_has；resources_changed；to_dict/from_dict 保存 capacity、counts。

详细所有权、状态转换与扩展方法见 [模块接口约定](../../architecture/module_contracts.md)；实测范围见 [框架交付记录](../../development/2026-10-27_modular_framework.md)。原目标中尚未实现的内容保持登记，不因架构拆分自动升级完成度。

## 验收入口

通过主文档定位本功能后执行账本列出的检查。正常、拒绝、取消/重复、存档恢复均按适用范围记录；真实渲染、听验和设备项单列。本次使用统一 runner 的隔离存档项目，不能直接拿玩家存档做测试。

## 来源与交付记录

- [拆分前完整主文档](../../archive/pre_split_20261023/GDD_V1.0.md)
- [拆分前功能计划](../../archive/pre_split_20261023/功能重做计划.md)
- [本次工程拆分记录](../../development/2026-10-23_feature_split.md)
- [godot/MANAGEMENT_LOOP.md](../../../godot/MANAGEMENT_LOOP.md)
