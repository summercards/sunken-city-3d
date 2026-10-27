# SEA-QUALITY · 验证与性能治理 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-quality) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-QUALITY",
  "status": "partial",
  "owner": "隔离验证 runner / 静态架构门禁",
  "code_paths": [
    "scripts",
    "godot/tests",
    "tests"
  ],
  "verification": [
    "structure",
    "framework-modules",
    "framework-integration",
    "save-protection",
    "visual-weather"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-QUALITY-R01 | 每项保留退出码/日志/renderer/user目录；失败历史与未执行项单列 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-QUALITY-R02 | 航路正式代码不引用parity；framework-modules和surface通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-QUALITY-R03 | 真实天气截图另跑；跨平台、设备和性能未签署完成 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-QUALITY-R04 | 已实现并专项核验 | [框架交付记录](../../development/2026-10-27_modular_framework.md)；[模块接口约定](../../architecture/module_contracts.md) |
| SEA-QUALITY-R05 | 已实现并专项核验 | [边界补强记录](../../development/2026-10-27_framework_boundary_hardening.md) |

## 资源与调用入口

- [scripts](../../../scripts)
- [godot/tests](../../../godot/tests)
- [tests](../../../tests)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

scripts/check_architecture.py；scripts/check_feature_contracts.py --sync 后无参数检查；run_verification.py 的 framework-modules/framework-integration/save-protection/visual-weather。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；兼容字段仅供已有调试工具，不作为新增业务写入口。

## 验证记录

入口：`python3 scripts/check_feature_contracts.py`。

2026-10-23 历史实测结果见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 尚无本功能独立运行验收，不将结构通过视为玩法完成。

- 2026-10-23 真实事件补充：visual-click 退出 1，第二地格点击目标断言失败；拆分前基线同样失败，完整根因待定位。不得以核心 click 通过覆盖此失败。详见[交付记录](../../development/2026-10-23_feature_split.md)。

## 遗留与下一步

增加无 Autoload 框架测试、跨进程恢复、坏档保护及真实天气截图。每项用独立用户目录，仅 seed/对应恢复专项有意共享；目标设备/发行测试仍单列。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 2026-10-26 功能与健康审计

SEA-QUALITY-R01/R02/R03：31 项功能各有独立文档和账本。当前专项 modules 28、surface 503（30航路）、click 30、camera 8、management 36 均通过；selftest 530通过/7失败，visual-click 5失败，visual-management 2失败。结构初查 zones.json 哈希漂移。测试副本、预期错误、并发编辑限制及未执行项详见审计记录；整体保持 partial。

[本轮审计与证据](../../development/2026-10-26_feature_architecture_save_3c_audit.md)。本轮只审计和登记，未修改玩法实现。

## 2026-10-27 模块框架落地

增加无 Autoload 框架测试、跨进程恢复、坏档保护及真实天气截图。每项用独立用户目录，仅 seed/对应恢复专项有意共享；目标设备/发行测试仍单列。

新增条款 SEA-QUALITY-R04 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。

2026-10-27 框架收尾：运行13组专项通过，架构边界0问题；最终契约门禁唯一失败为并行修改 water.tres 的运行哈希漂移，未批量接受。详见[最终门禁记录](../../development/2026-10-27_modular_framework.md#最终静态门禁与并发边界)。

## 2026-10-27 查询与恢复边界补强

门禁新增种植/订单内部状态与Main私有调用检查；超长随机数用例首次退出0仍判失败，修复后复测。

[本轮实测记录](../../development/2026-10-27_framework_boundary_hardening.md)。
