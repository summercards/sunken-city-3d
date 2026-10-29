# SEA-SAVE · 存档与恢复 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-save) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-SAVE",
  "status": "partial",
  "owner": "SaveGame / SnapshotRegistry / 各模块快照",
  "code_paths": [
    "godot/src/save"
  ],
  "verification": [
    "selftest",
    "management",
    "framework-modules",
    "framework-integration",
    "save-protection",
    "minimum-loop",
    "visual-plot-shipping",
    "sleep-cycle"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-SAVE-R01 | tmp读回、有效备份、旧版迁移/未来版保护；跨进程专项通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-SAVE-R02 | 全量模块恢复/相对冷却，旧内容按所属模块过滤；selftest与拾取恢复通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-SAVE-R03 | 潜水/收线拒绝中途档；Autoload前隔离，selftest/runner通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-SAVE-R04 | SaveGame只访问注册表；恢复与UI刷新经公开适配接口 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-SAVE-R05 | 已实现并专项核验 | [框架交付记录](../../development/2026-10-27_modular_framework.md)；[模块接口约定](../../architecture/module_contracts.md) |
| SEA-SAVE-R06 | 已实现并专项核验 | [边界补强记录](../../development/2026-10-27_framework_boundary_hardening.md) |
| SEA-SAVE-R07 | 本轮实现；正式最小范围与独立专项验证 | [本轮交付](../../development/2026-10-27_minimum_loop_and_title.md) |
| SEA-SAVE-R08 | 已实现，场景点击与存读专项验证 | [本轮证据](../../development/2026-10-27_plot_shipping_loop.md) |

## 资源与调用入口

- [godot/src/save](../../../godot/src/save)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

encode / write / read / decode / restore；SnapshotRegistry.register / capture / validate / restore / clear；restored；ok/reason/recovered/future 结果。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；兼容字段仅供已有调试工具，不作为新增业务写入口。

## 验证记录

当前入口：`python3 scripts/run_verification.py selftest management framework-modules framework-integration save-protection`。

2026-10-23 历史实测结果见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 selftest、management 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

SaveGame 仅依赖 host.save_registry；版本2全模块先验证后恢复，启动读默认档，损坏回退上个有效备份，未来版本保护不覆盖。真实断电、磁盘故障及发行平台文件系统尚未实测。

## 变更记录

SEA-SAVE-R08初始六格修订：首次快照显式包含六格，旧单格档补齐空格且保留作物字段；玩家档只读副本通过正式decode/restore后逐格可达、接近并取消，固定及DIY作物记录不变。schema/version/恢复顺序不改，未写入玩家档。[实测](../../development/2026-10-29_initial_six_planters.md)。

2026-10-29 SEA-SAVE-R08：只在世界姿态适配层改为按XYZ选层吸附，SaveGame/SnapshotRegistry及存档格式未改。动态建造恢复、坏档/跨进程专项见[本轮交付](../../development/2026-10-29_character_physics_framework.md)。

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 2026-10-26 功能与健康审计

SEA-SAVE-R01/R02/R03/R04：selftest 存档子段24项通过，但隔离跨进程复现默认重启未读档、自动存档将98765瓶盖覆盖为80；空JSON被迁移接受，恢复将12345瓶盖清零；负船级/负容量/未知建筑键被接受。恢复仍访问Main/HUD私有字段。列为P1修复项，不能判健康；最终观测退出0仅表示复现完成。

[本轮审计与证据](../../development/2026-10-26_feature_architecture_save_3c_audit.md)。本轮只审计和登记，未修改玩法实现。

## 2026-10-27 模块框架落地

SaveGame 仅依赖 host.save_registry；版本2全模块先验证后恢复，启动读默认档，损坏回退上个有效备份，未来版本保护不覆盖。真实断电、磁盘故障及发行平台文件系统尚未实测。

新增条款 SEA-SAVE-R05 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。

## 2026-10-27 查询与恢复边界补强

SnapshotRegistry.event_sources、is_restoring 与 restored；结构/语义坏档、未来备份、事件观察一致性与重入存盘专项通过。

[本轮实测记录](../../development/2026-10-27_framework_boundary_hardening.md)。

## 2026-10-27 当前最小循环与开始画面

本节及本轮修改条款优先于下方保留的历史范围。默认发布配置只开放家园生活循环；旧全功能验证须显式 `--full-world`，不能代替最小版本验收。接口、迁移及实测见[交付记录](../../development/2026-10-27_minimum_loop_and_title.md)。

2026-10-27 场景点击循环：07:00收货、瓶盖、木土种植格及码头出货箱；[本轮记录](../../development/2026-10-27_plot_shipping_loop.md)。

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-SAVE-R09 | 已实现，写盘与往返验证 | [本轮实测](../../development/2026-10-28_sleep_cycle_delivery.md) |

## 2026-10-28 开始界面时间连续性

开始背景改为读取已恢复的同一WorldClock时刻，不修改存档格式、时间字段或07:00晨次。开始期间继续冻结时钟，入场后恢复计时；白天/夜间/清晨真实存档冷启动验证见[本轮记录](../../development/2026-10-28_title_composition_saved_time.md)。

## 2026-10-29 家园建造接入

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-SAVE-R10 | 已实现；65实例含带作物搬移的独立海上平台70+8项跨进程恢复，旧档边缘迁移5+11项通过 | [本轮交付](../../development/2026-10-29_open_ocean_building.md) |
