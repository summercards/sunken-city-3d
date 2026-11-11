# SEA-SUNROOM · 阳光房分阶段修缮、攀爬与季节表现 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-sunroom) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-SUNROOM",
  "status": "partial",
  "owner": "SunroomService / ActorController / SunroomView",
  "code_paths": [
    "godot/src/facilities/sunroom_service.gd",
    "godot/src/facilities/sunroom_view.gd",
    "godot/src/facilities/sunroom_repair_interactable.gd",
    "godot/src/facilities/sunroom_upper_interactable.gd",
    "godot/src/facilities/sunroom_ladder_interactable.gd",
    "godot/src/player/actions/climb_ladder_action.gd",
    "godot/src/player/states/climbing.gd",
    "godot/scenes/facilities/solar_cabin_surface.tscn",
    "godot/scenes/zones/zone1_home_harbor.tscn"
  ],
  "verification": [
    "sunroom-repair",
    "sunroom-runtime",
    "solar-components",
    "visual-solar-cabin",
    "save-protection"
  ]
}
```

## 2026-11-07 初始状态拆分与攀爬实现

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-SUNROOM-R01 | 已实现状态所有者 `SunroomService`，阶段为 `ruined / ladder_fixed / restored`，操作单调前进且重复拒绝。 | `godot/src/facilities/sunroom_service.gd`；`sunroom-repair` |
| SEA-SUNROOM-R02 | 已实现原子材料检查与扣除：修梯 `wood×5`；二楼 `wood×8 + soil×2 + glass×1`；统一走仓储 Construction 端口。 | `SunroomService.repair_ladder/restore_upper`；`sunroom-repair` 14 checks / 0 failures |
| SEA-SUNROOM-R03 | 已实现 `climbing` 状态与端点线性连续攀爬；关闭普通地面碰撞和输入，完成后回 `ashore_idle`。 | `actor_controller.gd`、`climb_ladder_action.gd`、`states/climbing.gd`；需补正式主场景真实攀爬专项 |
| SEA-SUNROOM-R04 | 已实现二楼休整交互、二楼沙发显隐和 `sunroom_upper_deck` 行走面启停。 | `sunroom_upper_interactable.gd`、`sunroom_view.gd`、`zone1_home_harbor.tscn`；需补真实角色上下往返专项 |
| SEA-SUNROOM-R05 | 已实现初始单花、破损叠加、阶段化下层植物、二楼沙发和完整植物集合显隐；未写入 Farm。 | `sunroom_view.gd`、`sunroom_damage_visual.gd`；资产回归 `solar-components` 415 / 0 |
| SEA-SUNROOM-R06 | 已实现读取 `WorldClock.day` 的季节推导：春/夏/秋/冬仅影响表现；不自动修缮。 | `SunroomService.season()`；需补季节真实渲染取证 |
| SEA-SUNROOM-R07 | 已实现根 v4 不变、旧档缺少 `economy.sunroom` 时迁移为破损初始态、阶段旗标一致性校验。 | `save_game.gd`、`save_schema.gd`、`SunroomService.validate_snapshot`；需补整档 runner 读写 |
| SEA-SUNROOM-R08 | 已按职责拆分：修缮状态归 SunroomService，材料归 Inventory/Warehouse，攀爬执行归 ActorController，表现归 SunroomView。 | 代码静态边界；`framework-modules` 仍有既有 1 项无关失败，不能代签本条全部完成 |
| SEA-SUNROOM-R09 | 已实现：下层 WalkArea 增加楼梯脚下真实甲板通行带，与主甲板重叠接通，不放开建筑内部或水面。 | `zone1_home_harbor.tscn`；`sunroom-runtime` 梯脚路径断言通过 |
| SEA-SUNROOM-R10 | 已实现：修梯、上下梯端点、二楼休整、破损表现锚点均由 `solar_cabin_surface.tscn` 保存，Bootstrap 仅注入服务/角色命令。 | `solar_cabin_surface.tscn`、`main.gd`；运行时锚点存在断言通过 |
| SEA-SUNROOM-R11 | 已实现：`climbing` 状态消费 `climbing_action.gd` 手脚交替表现，根位仍由 `climb_ladder_action.gd` 连续执行。 | `character.gd`、`climbing_action.gd`、`climb_ladder_action.gd`；`sunroom-runtime` 动作状态断言通过 |
| SEA-SUNROOM-R12 | 已实现：二楼从梯顶到内部目标有真实路线，角色可在二楼移动并从顶部下梯回到一楼。 | `test_sunroom_runtime.gd` 20 checks / 0 failures；证据见 `docs/development/2026-11-11_sunroom_access.md` |

## 资源与调用入口

- 修缮状态：[sunroom_service.gd](../../../godot/src/facilities/sunroom_service.gd)
- 场景表现：[sunroom_view.gd](../../../godot/src/facilities/sunroom_view.gd)
- 阳光房总成：[solar_cabin_surface.tscn](../../../godot/scenes/facilities/solar_cabin_surface.tscn)
- 家园行走面：[zone1_home_harbor.tscn](../../../godot/scenes/zones/zone1_home_harbor.tscn)
- 攀爬执行：[climb_ladder_action.gd](../../../godot/src/player/actions/climb_ladder_action.gd)

资产仍引用既有稳定阳光房梯子、沙发、植物和公共材质，不新增或改名 AssetID；破损效果为运行时表现叠加，不替换原梯子 GLB。

## 当前接口清单

```text
SunroomService.repair_ladder()
SunroomService.restore_upper()
SunroomService.ladder_repaired()
SunroomService.upper_restored()
SunroomService.query()
SunroomService.to_dict()/from_dict()
SunroomService.validate_snapshot()
ActorController.climb_ladder(start, end, subject)
```

## 验证记录

新增隔离专项：

```text
python3 scripts/run_verification.py sunroom-repair
```

2026-11-07 实测：`sunroom-repair` 14 checks / 0 failures，退出码 0；覆盖新局破损、精确材料支付、重复拒绝、阶段迁移、坏阶段拒绝。

真实运行专项：`sunroom-runtime` 自身报告 14 checks / 0 failures、进程退出码 0；覆盖正式 main 场景装配、阶段显隐、二楼行走面启用和角色沿梯子端点连续到达二楼支撑面。统一 runner 仍记录 1 条既有水下地图 `push_error`，因此 runner 汇总未标为 clean pass；该错误发生在 `underwater_world.gd` 的旧潜水地图初始化，不在本功能调用链。

资产专项：`solar-components` 415 checks / 0 failures，退出码 0。

`visual-solar-cabin` 当前仍被既有资产专项的「四个直接语义模块」断言阻塞：运行时 helper 不能作为第四个直接子模块挂在阳光房总成下，因此本轮保持 helper 归入既有场景子树的架构决定，真实视觉截图不宣称通过。该失败不是把业务状态写错，而是历史资产测试尚未适配本次运行时辅助节点边界。

本轮未把历史 `management` / `framework-modules` 的既有失败冒充为阳光房失败：

- management：36 checks / 4 failures，涉及既有仓库/种植床前置；另有 avatar nil 错误。
- framework-modules：50 checks / 1 failure，涉及既有 solid/world boundary。

2026-11-11 通行修订：按参考图反馈修复楼梯下方断路、二楼实际行走与攀爬动作缺失。`solar_cabin_surface.tscn` 新增五个场景锚点（修梯、上下梯、二楼休整、破损表现），`main.gd` 改为读取锚点的世界位置，不再维护第二套玩法坐标；`zone1_home_harbor.tscn` 下层 WalkArea 增加真实甲板通行带 `Rect2(3.5, 2.5, 2.0, 5.2)`，与既有区域重叠0.2米以接回梯脚，不开放建筑内部或水面；`Character.set_climbing()` 改为消费 `climbing_action`，角色攀爬时手脚交替，根位仍归 `climb_ladder_action`。

本轮 `sunroom-runtime` 已扩为 20 项：场景锚点、下层梯脚可达、二楼走域从梯顶到内部目标可达、上梯、攀爬动作状态、二楼实际移动、下梯回一楼全部通过；`sunroom-repair` 14/0、`save-protection` 与 `save-corrupt-seed` 均 exit 0。最终证据：`D:/projects/sea-work/verification/20261111-151325-verification-ae19ef`。

`visual-solar-cabin` 本轮仍未通过：退出码 124，且历史断言在 `tests/test_solar_cabin_asset.gd:44` 读取没有 `asset_component` 元数据的节点，报「four independent semantic modules」；这属于既有资产视觉专项与运行时 helper/场景节点边界不兼容，不把它归因成通行修复通过。最新记录：`D:/projects/sea-work/verification/20261111-151534-verification-b60437`。因此真实截图验收继续 pending。

存档契约同时补强：`save_schema.gd` 在字段结构检查后显式调用 `SunroomService.validate_snapshot()`，阶段与兼容旗标矛盾时在恢复前拒绝，避免 `from_dict()` 的兼容降级绕过坏状态断言。

当前仍未宣称真实截图验收；本轮验证是正式主场景运行专项，截图审阅仍是独立表现门禁。
