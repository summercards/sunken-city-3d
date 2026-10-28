# SEA-DIVE · 潜水探索与宝箱

[主文档中控](../../../GDD_V1.0.md#sea-dive) · [本功能账本](ledger.md)

设计修订：r1（2026-10-23 工程拆分，未更改玩法数值）。所属系统：探索。
范围来源：主文档保留的全局设计、拆分前文档与当前代码核对；下面明确区分目标与实现边界。

## 功能目的与边界

正式或规划入口：潜水入口进入海底四区，探索发现宝箱。

本功能以这一玩家行为或工程交付闭环为管理粒度，内部操作作为设计条款逐项承接；不按脚本数量拆功能。跨功能前置和关系由主文档本行统一维护。

## 设计条款与验收标准

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-DIVE-R01 | 氧气随深度、运动与头灯消耗，归零强制上浮并恢复冷却，不扣已有资源。 |
| SEA-DIVE-R02 | 宝箱先发现再交互，未发现不显示可点击目标；搜索完成才给奖励。 |
| SEA-DIVE-R03 | 存档记录宝箱发现/开启状态，恢复采用全量复位；读档回到海面而非恢复中途潜水。 |
| SEA-DIVE-R04 | 潜入、游泳、上浮使用公共状态机生命周期；搜索、移动、镜头、姿态各自独立动作，不直接访问经济全局。 |
| SEA-DIVE-R05 | 海底鱼群复用场景装饰/动物组件，由潜水表现层注入时间与深度材质；不接管鱼类资源、宝箱或存档。 |

## 所有者、接口与数据

状态/交付所有者：**UnderwaterWorld / DiveAir / 阶段状态机**。正式代码和资源入口：

- [godot/src/diving](../../../godot/src/diving)
- [godot/scenes/underwater](../../../godot/scenes/underwater)

读取上述所有者的公开查询，修改通过其命令或交互入口；事件由拥有该状态的对象发出。具体公开方法、信号和持久化字段见本账本的接口清单。原有稳定 ContentID、场景 ID 和存档键保持不变，重命名须另做迁移。

共享资源的所有权以被依赖功能为准。本功能引用它们，不复制背包数值、资产记录或其他功能规则。规划中的接口尚无实现时必须先补契约再编码。

## 当前实现与待完成边界

潜水已拆为 surface/enter/swim/exit 状态及7个独立动作；UnderwaterWorld 保留几何与内容装配，奖励回调注入。真实深度、透明渲染和设备性能仍需专项 GPU 验收。

2026-10-27 接口：dive / surface / swim_to / cancel_navigation / to_dict / from_dict；phase_machine；exited、air_changed；give_resource 注入。

详细所有权、状态转换与扩展方法见 [模块接口约定](../../architecture/module_contracts.md)；实测范围见 [框架交付记录](../../development/2026-10-27_modular_framework.md)。原目标中尚未实现的内容保持登记，不因架构拆分自动升级完成度。

## 验收入口

通过主文档定位本功能后执行账本列出的检查。正常、拒绝、取消/重复、存档恢复均按适用范围记录；真实渲染、听验和设备项单列。本次使用统一 runner 的隔离存档项目，不能直接拿玩家存档做测试。

## 来源与交付记录

- [拆分前完整主文档](../../archive/pre_split_20261023/GDD_V1.0.md)
- [拆分前功能计划](../../archive/pre_split_20261023/功能重做计划.md)
- [本次工程拆分记录](../../development/2026-10-23_feature_split.md)
- [godot/UNDERWATER_RENDERING.md](../../../godot/UNDERWATER_RENDERING.md)

2026-10-27 接口收口：公开头灯与诊断入口：toggle_lamp / uses_underwater_environment。
