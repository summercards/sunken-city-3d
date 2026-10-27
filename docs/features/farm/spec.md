# SEA-FARM · 种植与日常照料

[主文档中控](../../../GDD_V1.0.md#sea-farm) · [本功能账本](ledger.md)

设计修订：r1（2026-10-23 工程拆分，未更改玩法数值）。所属系统：经营。
范围来源：主文档保留的全局设计、拆分前文档与当前代码核对；下面明确区分目标与实现边界。

## 功能目的与边界

正式或规划入口：岸上种植菜单及地格交互。

本功能以这一玩家行为或工程交付闭环为管理粒度，内部操作作为设计条款逐项承接；不按脚本数量拆功能。跨功能前置和关系由主文档本行统一维护。

## 设计条款与验收标准

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-FARM-R01 | 播种、浇水、休息推进、成熟收获和再种构成同一经营功能；18 格各自持有作物状态。 |
| SEA-FARM-R02 | 每天已浇水的生长格推进一日；缺水只停长，现实时间不推进作物；水壶 12 份可免费补满。 |
| SEA-FARM-R03 | 买种先检查容量与余额，收获满包保留作物，番茄三茬后清空。 |
| SEA-FARM-R04 | 地格/作物 ID 稳定；保留 farm v2 快照与旧秒制存档迁移，旧已种作物可继续照料。 |
| SEA-FARM-R05 | 规则通过注入端口查询库存、设施和解锁资格，可在无 Main、无 Economy Autoload 的测试中执行。 |
| SEA-FARM-R06 | 场景层使用 register_plot / clear_plot_specs 注册地块；世界日历自然跨日不暗中重复推进作物，休息仍显式调用 advance_day。 |
| SEA-FARM-R07 | 查询返回独立副本且无副作用；修改须走模块命令，调试生长调整也使用明确命令入口。 |

## 所有者、接口与数据

状态/交付所有者：**Farm / FarmField 场景适配**。正式代码和资源入口：

- [godot/src/farming](../../../godot/src/farming)
- [godot/assets/data/crops.json](../../../godot/assets/data/crops.json)
- [godot/scenes/props/farm_plot.tscn](../../../godot/scenes/props/farm_plot.tscn)
- [godot/scenes/props/farm_cell.tscn](../../../godot/scenes/props/farm_cell.tscn)

读取上述所有者的公开查询，修改通过其命令或交互入口；事件由拥有该状态的对象发出。具体公开方法、信号和持久化字段见本账本的接口清单。原有稳定 ContentID、场景 ID 和存档键保持不变，重命名须另做迁移。

共享资源的所有权以被依赖功能为准。本功能引用它们，不复制背包数值、资产记录或其他功能规则。规划中的接口尚无实现时必须先补契约再编码。

## 当前实现与待完成边界

Farm 的规则端口保留；FarmField/FarmPlot 显式注入 Farm，不再访问全局 Economy。开垦、工具升级、品质和季节仍为规划。

2026-10-27 接口：configure；plant / water / harvest / advance_day / access_reason；register_plot / clear_plot_specs；plots_changed；farm v2 to_dict/from_dict。

详细所有权、状态转换与扩展方法见 [模块接口约定](../../architecture/module_contracts.md)；实测范围见 [框架交付记录](../../development/2026-10-27_modular_framework.md)。原目标中尚未实现的内容保持登记，不因架构拆分自动升级完成度。

## 验收入口

通过主文档定位本功能后执行账本列出的检查。正常、拒绝、取消/重复、存档恢复均按适用范围记录；真实渲染、听验和设备项单列。本次使用统一 runner 的隔离存档项目，不能直接拿玩家存档做测试。

## 来源与交付记录

- [拆分前完整主文档](../../archive/pre_split_20261023/GDD_V1.0.md)
- [拆分前功能计划](../../archive/pre_split_20261023/功能重做计划.md)
- [本次工程拆分记录](../../development/2026-10-23_feature_split.md)
- [godot/FARMING_DESIGN.md](../../../godot/FARMING_DESIGN.md)
- [godot/MANAGEMENT_LOOP.md](../../../godot/MANAGEMENT_LOOP.md)

## 2026-10-27 查询与恢复边界补强

state/spec/crop_def/plot_specs/crop_definitions 深副本；debug_set_growth 仅截图调试使用；modules31项覆盖。

[本轮实测记录](../../development/2026-10-27_framework_boundary_hardening.md)。
