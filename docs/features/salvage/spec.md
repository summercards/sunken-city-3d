# SEA-SALVAGE · 绞盘打捞

[主文档中控](../../../GDD_V1.0.md#sea-salvage) · [本功能账本](ledger.md)

设计修订：r1（2026-10-23 工程拆分，未更改玩法数值）。所属系统：探索。
范围来源：主文档保留的全局设计、拆分前文档与当前代码核对；下面明确区分目标与实现边界。

## 功能目的与边界

正式或规划入口：世界绞盘进入下钩与收线小游戏。

本功能以这一玩家行为或工程交付闭环为管理粒度，内部操作作为设计条款逐项承接；不按脚本数量拆功能。跨功能前置和关系由主文档本行统一维护。

## 设计条款与验收标准

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-SALVAGE-R01 | 下钩深度、收线张力和准确度决定结果；断线和主动取消有明确结束语义。 |
| SEA-SALVAGE-R02 | 奖励与冷却只在结算点提交，反复触发不能领取多次。 |
| SEA-SALVAGE-R03 | 没有种子和海贝时仍可用打捞获取基础建设材料。 |
| SEA-SALVAGE-R04 | 结算冷却由独立服务拥有；恢复相对剩余时间，不在表现层重复发奖。 |

## 所有者、接口与数据

状态/交付所有者：**SalvageModel / SalvageRewards**。正式代码和资源入口：

- [godot/src/salvage](../../../godot/src/salvage)

读取上述所有者的公开查询，修改通过其命令或交互入口；事件由拥有该状态的对象发出。具体公开方法、信号和持久化字段见本账本的接口清单。原有稳定 ContentID、场景 ID 和存档键保持不变，重命名须另做迁移。

共享资源的所有权以被依赖功能为准。本功能引用它们，不复制背包数值、资产记录或其他功能规则。规划中的接口尚无实现时必须先补契约再编码。

## 当前实现与待完成边界

玩法模型与结算服务独立；SalvageRewards 拥有冷却与奖励提交，通过 give 端口入账，绞盘注入该服务。

2026-10-27 接口：commit_salvage / can_salvage / salvage_cooldown_left / to_dict / from_dict；salvage_ready；快照 salvage.left。

详细所有权、状态转换与扩展方法见 [模块接口约定](../../architecture/module_contracts.md)；实测范围见 [框架交付记录](../../development/2026-10-27_modular_framework.md)。原目标中尚未实现的内容保持登记，不因架构拆分自动升级完成度。

## 验收入口

通过主文档定位本功能后执行账本列出的检查。正常、拒绝、取消/重复、存档恢复均按适用范围记录；真实渲染、听验和设备项单列。本次使用统一 runner 的隔离存档项目，不能直接拿玩家存档做测试。

## 来源与交付记录

- [拆分前完整主文档](../../archive/pre_split_20261023/GDD_V1.0.md)
- [拆分前功能计划](../../archive/pre_split_20261023/功能重做计划.md)
- [本次工程拆分记录](../../development/2026-10-23_feature_split.md)

## 2026-11-14 B2 G03 原子奖励现行覆盖

承接SEA-SALVAGE-R02/R04，覆盖历史“通过give端口入账”：结算只接受整笔receive_all（或add_all），接入方保证成功全量提交、失败零入账；旧give单独配置不再被结算接受，无原子端口明确拒绝，不能逐项can_receive/give或事后退款拼成原子事务。configure仍能保存旧键不等于旧give继续可用。

commit_salvage_result(now,haul)返回详情 `{ok,added,overflow,reason}`；last_result返回副本，overflow为整笔未入账奖励，不是允许部分丢弃。receive_all回调可返回bool或含ok/reason字典；这里不是要求Inventory.add_all改返回类型。只在整笔入账成功后提交16秒冷却并发salvage_ready，拒绝不耗冷却；is_busy覆盖入账→冷却→事件，阻止同步重入和中间保存。旧caller可继续commit_salvage，仅返回实际added，拒绝为空；生产NPC反馈取详细结果，不按预期奖励虚报。

SeaProps复合箱使用自己的receive_all和目标提交锁，单资源legacy give兼容边界不能混称为salvage旧give被接受。根v4/salvage.left不变，状态不升级；0/1/2格、复合奖励及未决证据见[B2主记录](../../development/2026-11-13_engine_deep_audit.md#b2-业务事务与空间修复最终回填2026-11-14)。
