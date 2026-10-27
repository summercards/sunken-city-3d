# SEA-FARM · 种植与日常照料 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-farm) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-FARM",
  "status": "partial",
  "owner": "Farm / FarmField 场景适配",
  "code_paths": [
    "godot/src/farming",
    "godot/assets/data/crops.json",
    "godot/scenes/props/farm_plot.tscn",
    "godot/scenes/props/farm_cell.tscn"
  ],
  "verification": [
    "farming",
    "management",
    "modules",
    "framework-integration"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-FARM-R01 | 18格经营规则保留；farming31项与selftest通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-FARM-R02 | 休息推进；自然世界日历不暗中推进，集成专项通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-FARM-R03 | 容量、余额及多茬逻辑；farming/management通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-FARM-R04 | farm v2与旧秒制迁移；farming/selftest通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-FARM-R05 | 无Autoload modules通过；场景显式注入Farm | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-FARM-R06 | 已实现并专项核验 | [框架交付记录](../../development/2026-10-27_modular_framework.md)；[模块接口约定](../../architecture/module_contracts.md) |
| SEA-FARM-R07 | 已实现并专项核验 | [边界补强记录](../../development/2026-10-27_framework_boundary_hardening.md) |

## 资源与调用入口

- [godot/src/farming](../../../godot/src/farming)
- [godot/assets/data/crops.json](../../../godot/assets/data/crops.json)
- [godot/scenes/props/farm_plot.tscn](../../../godot/scenes/props/farm_plot.tscn)
- [godot/scenes/props/farm_cell.tscn](../../../godot/scenes/props/farm_cell.tscn)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

configure；plant / water / harvest / advance_day / access_reason；register_plot / clear_plot_specs；plots_changed；farm v2 to_dict/from_dict。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；兼容字段仅供已有调试工具，不作为新增业务写入口。

## 验证记录

当前入口：`python3 scripts/run_verification.py farming management modules framework-integration`。

2026-10-23 历史实测结果见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 farming、management、modules 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

Farm 的规则端口保留；FarmField/FarmPlot 显式注入 Farm，不再访问全局 Economy。开垦、工具升级、品质和季节仍为规划。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 2026-10-27 模块框架落地

Farm 的规则端口保留；FarmField/FarmPlot 显式注入 Farm，不再访问全局 Economy。开垦、工具升级、品质和季节仍为规划。

新增条款 SEA-FARM-R06 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。

## 2026-10-27 查询与恢复边界补强

state/spec/crop_def/plot_specs/crop_definitions 深副本；debug_set_growth 仅截图调试使用；modules31项覆盖。

[本轮实测记录](../../development/2026-10-27_framework_boundary_hardening.md)。
