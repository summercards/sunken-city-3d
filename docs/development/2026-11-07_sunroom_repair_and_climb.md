# 2026-11-07 阳光房分阶段修缮、攀爬与季节表现

## 目标

按用户要求，把现有阳光房从一次性完整展示拆为「破损 → 修梯 → 攀爬到二楼 → 休整二楼 → 植物/沙发逐步丰富」的闭环，并保持现有 Godot 架构、存档 v4 与功能所有权边界。

## 设计决定

| 项目 | 决定 |
|---|---|
| 初始阶段 | `ruined`，仅显示一株小雏菊；梯子显示破损叠加，不可攀爬 |
| 修梯成本 | 木板×5 |
| 梯子行为 | 独立 `climbing` 状态，沿真实上下端点连续移动，速度 1.35m/s；不复用普通 WalkArea 跨层，不瞬移 |
| 二楼休整成本 | 木板×8、土壤×2、玻璃×1 |
| 二楼内容 | 休整成功后显示二楼沙发、二楼植被并启用二楼行走面 |
| 季节 | 读取既有 WorldClock.day，表现层推导春/夏/秋/冬；季节不自动完成修缮 |
| 童谣 | 现有功能树没有童谣契约；本轮不虚构新系统，将用户语句中的素材消耗落到阳光房修缮材料 |

总木板消耗公式：`wood_total = 5 + 8 = 13`。

## 实现

- `godot/src/facilities/sunroom_service.gd`
  - 唯一拥有 `ruined / ladder_fixed / restored` 状态。
  - 通过 Construction/Warehouse 端口原子支付。
  - 提供 `to_dict/from_dict/validate_snapshot`。
- `godot/src/facilities/sunroom_view.gd`
  - 只消费阶段和季节输入，控制植物、沙发、交互点显隐。
- `godot/src/facilities/sunroom_damage_visual.gd`
  - 在既有梯子 GLB 外叠加裂木、断脚踏板和斜裂板，未替换稳定资产。
- `godot/src/facilities/sunroom_repair_interactable.gd`
  - 修梯交互。
- `godot/src/facilities/sunroom_upper_interactable.gd`
  - 二楼休整交互。
- `godot/src/facilities/sunroom_ladder_interactable.gd`
  - 梯子上下端点交互。
- `godot/src/player/actions/climb_ladder_action.gd`
  - 连续梯子路径执行。
- `godot/src/player/states/climbing.gd`
  - 独立移动状态。
- `godot/src/bootstrap/main.gd`
  - 装配服务、场景状态投影、季节输入和保存 busy 保护。
- `godot/scenes/facilities/solar_cabin_surface.tscn`
  - 挂入破损叠加、修梯点、上下梯点和二楼休整点。
- `godot/scenes/zones/zone1_home_harbor.tscn`
  - 新增 `sunroom_upper_deck` 行走面，默认由服务状态禁用，休整后启用。
- `godot/src/save/save_schema.gd` / `save_game.gd`
  - 根 v4 不变；旧档缺 `economy.sunroom` 时迁移为 `ruined`。
- `scripts/run_verification.py`
  - 登记新专项 `sunroom-repair`。

## 专项验证

执行：

```text
python3 scripts/run_verification.py sunroom-repair
```

实测：`sunroom-repair` 14 checks / 0 failures，退出码 0。

真实运行专项：`sunroom-runtime` 自身报告 14 checks / 0 failures、进程退出码 0；覆盖正式 main 场景装配、破损/修梯/恢复阶段显隐、二楼行走面启用和角色沿梯子端点连续到达二楼支撑面。统一 runner 仍记录 1 条既有水下地图 `push_error`，因此 runner 汇总未标为 clean pass；该错误发生在 `underwater_world.gd` 的旧潜水地图初始化，不在本功能调用链。

覆盖：

1. 新局破损和单花初始状态。
2. 木板不足 / 足额支付边界。
3. 修梯精确扣除木板×5。
4. 重复修梯拒绝且不重复扣料。
5. 二楼材料支付木板×8、土壤×2、玻璃×1。
6. 修缮阶段写入和恢复。
7. 阶段与兼容布尔值矛盾时拒绝。

既有资产专项：`solar-components` 415 checks / 0 failures。

## 当前边界

真实主场景的角色实际走到梯子、连续攀爬、二楼支撑面与状态恢复已由 `sunroom-runtime` 覆盖；下梯往返和整档磁盘读写仍需后续专项补充，不以隔离状态专项替代真实视觉截图验收。

本轮看到的既有回归阻塞保持原样登记：

- `management` 36 checks / 4 failures：既有仓库 / 种植床前置失败，另有 avatar nil 错误。
- `framework-modules` 50 checks / 1 failure：既有 solid/world boundary 失败。

这些失败没有归因到本次阳光房实现，也没有用新测试绿项掩盖。
