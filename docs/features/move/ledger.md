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
    "walk-facing",
    "visual-walk-facing",
    "surface",
    "click",
    "framework-modules",
    "framework-integration",
    "sleep-cycle"
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
| SEA-MOVE-R09 | 已实现；八方向 × 30/60/120 FPS，专项102项、真实渲染106项通过；旧公式对照复现26项朝向失败 | [朝向修复与实测](../../development/2026-10-29_walk_facing.md) |

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

角色控制已由 Main 拆到 ActorController；9 个状态、4 个控制动作和7个表现动作分别独立文件。已有行为完成回归；移动端手感、跳跃/战斗等未设计玩法不计完成。

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

角色控制已由 Main 拆到 ActorController；9 个状态、4 个控制动作和7个表现动作分别独立文件。已有行为完成回归；移动端手感、跳跃/战斗等未设计玩法不计完成。

新增条款 SEA-MOVE-R04 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-MOVE-R05 | 已实现，自动/主动睡觉验证 | [本轮实测](../../development/2026-10-28_sleep_cycle_delivery.md) |

## 2026-10-28 登陆标记的双向往返

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-MOVE-R06 | 已实现；三种情况均在状态表内完成，无新增状态 | `dock-seed` 5 项断言（上岸/上船/自动上岸/父节点/落点） |
| SEA-MOVE-R07 | 已实现；6 处清零点覆盖取消、改道、拾取、挡停、读档 | `dock-seed` 2 项断言（意图只消费一次、取消后不擅自下船） |

[本轮记录](../../development/2026-10-28_dock_seed_weather_asset_fix.md)。

## 2026-10-29 家园建造接入

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-MOVE-R08 | 已实现；相关专项通过，详细范围以交付记录为准 | [本轮交付](../../development/2026-10-28_building_delivery.md) |

## 2026-10-29 角色正向行走

SEA-MOVE-R09：将偏航计算从局部 +X 对齐改为模型局部 +Z 对齐，保留平滑转向与步速。`walk-facing`（102项）、`visual-walk-facing`（106项）、`board-click`（12项）、`framework-integration`（44项）均退出0。真实渲染近景已目视核对。

`surface`（456项/1失败）、`click`（32项/3失败）退出1；工程外恢复旧朝向公式后的对照运行产生完全相同的4项失败，涉及种植场景路径与拾取/建造流程，未计为本次通过。初次主场景验证遇到HUD类型推断错误，已补bool声明，后续无该编译错误。详细日志、预期对照失败及未执行项见[交付记录](../../development/2026-10-29_walk_facing.md)。
