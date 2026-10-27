# SEA-MOVE · 角色移动与上下船 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-move) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-MOVE",
  "status": "partial",
  "owner": "ActorController / Character 表现",
  "code_paths": [
    "godot/src/player",
    "godot/src/navigation/walk_area.gd",
    "godot/src/navigation/ground_path.gd",
    "godot/src/navigation/landing_point.gd"
  ],
  "verification": [
    "surface",
    "click",
    "framework-modules",
    "framework-integration"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-MOVE-R01 | 合法地面求路及步进复核；surface503项，非全地图穷举 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-MOVE-R02 | 独立上下船动作与状态转换；surface/selftest通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-MOVE-R03 | 自动接近、模态阻断、完成一次、取消回调；framework-integration通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-MOVE-R04 | 已实现并专项核验 | [框架交付记录](../../development/2026-10-27_modular_framework.md)；[模块接口约定](../../architecture/module_contracts.md) |

## 资源与调用入口

- [godot/src/player](../../../godot/src/player)
- [godot/src/navigation/walk_area.gd](../../../godot/src/navigation/walk_area.gd)
- [godot/src/navigation/ground_path.gd](../../../godot/src/navigation/ground_path.gd)
- [godot/src/navigation/landing_point.gd](../../../godot/src/navigation/landing_point.gd)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

start_walk / approach / depart / cancel / request_mode / restore_pose / state_id / snapshot；state_changed、mode_changed；状态/动作目录见模块约定。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；兼容字段仅供已有调试工具，不作为新增业务写入口。

## 验证记录

当前入口：`python3 scripts/run_verification.py surface click framework-modules framework-integration`。

2026-10-23 历史实测结果见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 surface、click 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

角色控制已由 Main 拆到 ActorController；8 个状态、4 个控制动作和7个表现动作分别独立文件。已有行为完成回归；移动端手感、跳跃/战斗等未设计玩法不计完成。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 太阳能木屋接入影响验证（2026-10-25）

SEA-MOVE-R01/R02：新栈桥、前平台可走区域与 main 登岸点同步，六格菜箱可达；surface 338 检查与 click 30 检查通过。 验证入口：`python3 scripts/run_verification.py surface click management selftest visual-solar-cabin`；[证据](../../development/2026-10-25_solar_cabin_integration.md)。

## 太阳能木屋 v004（2026-10-25）

SEA-MOVE：同步放大后的桥与平台可走矩形、main 登岸点、种植点和交互点；surface、click、management、selftest 本轮全通过。 [当前证据](../../development/2026-10-25_solar_cabin_v004.md)。

## 太阳能木屋 v005（2026-10-25）

SEA-MOVE：桥长增加1.587米，更新主桥可走矩形和登岸点；顶面Y=2.15不变，30航路503检查及537自检通过。 [当前证据](../../development/2026-10-25_solar_cabin_v005.md)。

## 2026-10-26 功能与健康审计

SEA-MOVE-R01/R02/R03：正式surface 30航路503检查及click 30检查通过；Main仍持有行走状态。selftest订单板可行走区域等失败、真实第二地格点击失败仍待按当前场景核对；不宣称全部移动交互验收完成。

[本轮审计与证据](../../development/2026-10-26_feature_architecture_save_3c_audit.md)。本轮只审计和登记，未修改玩法实现。

## 2026-10-27 模块框架落地

角色控制已由 Main 拆到 ActorController；8 个状态、4 个控制动作和7个表现动作分别独立文件。已有行为完成回归；移动端手感、跳跃/战斗等未设计玩法不计完成。

新增条款 SEA-MOVE-R04 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。
