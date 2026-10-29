# SEA-BOOT · 启动与会话装配 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-boot) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-BOOT",
  "status": "partial",
  "owner": "Main 装配 / ActorController 模式 / GameState 投影",
  "code_paths": [
    "godot/src/bootstrap",
    "godot/project.godot",
    "godot/scenes/main.tscn"
  ],
  "verification": [
    "visual-title-screen-day",
    "visual-title-screen-night",
    "visual-title-screen-dawn",
    "selftest",
    "framework-integration",
    "save-protection"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-BOOT-R01 | 装配通过；selftest537项覆盖正式主场景 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-BOOT-R02 | 控制器输出模式；潜水 enter/swim/exit 与读档复位已测 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-BOOT-R03 | runner 在 Autoload 前隔离，专项配对单独共享存档 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-BOOT-R04 | 已实现并专项核验 | [框架交付记录](../../development/2026-10-27_modular_framework.md)；[模块接口约定](../../architecture/module_contracts.md) |

## 资源与调用入口

- [godot/src/bootstrap](../../../godot/src/bootstrap)
- [godot/project.godot](../../../godot/project.godot)
- [godot/scenes/main.tscn](../../../godot/scenes/main.tscn)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

Main._setup_save_registry 装配模块快照；capture_world_state / restore_world_state / validate_world_state 为世界适配接口。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；兼容字段仅供已有调试工具，不作为新增业务写入口。

## 验证记录

当前入口：`python3 scripts/run_verification.py selftest framework-integration save-protection`。

2026-10-23 历史实测结果见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 selftest 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。
- 2026-10-24 验证：SEA-BOOT-R01 的装配顺序缺陷（`_unhandled_input` 在 HUD 建成前读 `hud._panel_open`）已修；`run_verification.py selftest ocean parity` 三项 exit=0，证据见[启动报错修复记录](../../development/2026-10-24_bootstrap_startup_input_guard.md)。

## 遗留与下一步

Main 保留场景装配、输入路由、跨功能流程及兼容转发；行走、航路、奖励、状态机和存储规则由独立服务拥有。GameState.mode 仅作兼容投影，正式模式由 ActorController 驱动。

## 变更记录

2026-10-29角色物理接入：Main只增加唯一物理帧驱动与空间/高度适配；原Explorer节点路径与Transform保留，原生类型改为CharacterBody3D，其它内容不变。[角色框架交付](../../development/2026-10-29_character_physics_framework.md)。

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。
- 2026-10-24：`_unhandled_input` 增加 HUD 存在性早退，`cam_panel` / `grade` / 船靠岸提示的 `hud` 访问补空判断。装配顺序与玩法数值未变。

## 2026-10-26 功能与健康审计

SEA-BOOT-R01/R03：Main仍合并移动、交互与存档协调。隔离双进程复现默认启动不自动读档而开启120秒自动存档，会覆盖旧槽。需先完成继续/新局与自动保存门禁。

[本轮审计与证据](../../development/2026-10-26_feature_architecture_save_3c_audit.md)。本轮只审计和登记，未修改玩法实现。

## 2026-10-27 模块框架落地

Main 保留场景装配、输入路由、跨功能流程及兼容转发；行走、航路、奖励、状态机和存储规则由独立服务拥有。GameState.mode 仅作兼容投影，正式模式由 ActorController 驱动。

新增条款 SEA-BOOT-R04 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。

## 2026-10-28 开始构图与存档时刻

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-BOOT-R05 | 已实现；保持角度的房屋上移、按钮右移、三分辨率原生布局，白天/夜间/清晨存档冷启动与实际点击入场光照连续核验 | [本轮交付](../../development/2026-10-28_title_composition_saved_time.md) |

开始机位只在TitleCamera临时接管，不改变玩家存档姿态；未修改光照时段参数、资产资源或存档格式。当前整体功能状态保持原状，目标设备等边界见交付记录。
