# SEA-SUNROOM · 阳光房分阶段修缮、攀爬与季节表现

[主文档中控](../../../GDD_V1.0.md#sea-sunroom) · [本功能账本](ledger.md)

设计修订：r1（2026-11-07）。所属系统：世界 / 经营 / 3C / 表现。

## 功能目的与边界

阳光房不是一次性完成的静态布景，而是一个由修缮状态驱动的生活空间。玩家先看到受损的梯子和稀疏植被；支付木材修好梯子后，才能执行真实的竖直攀爬；二楼休憩区和二楼植被还要再次消耗材料休整后才出现。

本功能拥有阳光房的修缮阶段、材料支付意图和季节表现输入，不拥有：

- 作物地格、生长、收获或 Farm 存档；
- 家园拼接建筑布局；
- 世界时间本体；
- 角色的通用行走状态；
- 童谣内容、音频或 NPC 对话。

本轮用户原话中的“童谣消耗素材”按上下文解释为“修缮消耗素材”：本轮实现修缮材料消耗，不凭空新增童谣系统。

## 设计条款与验收标准

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-SUNROOM-R01 | 阳光房修缮由 `ruined → ladder_fixed → restored` 三阶段组成，状态单调前进；重复操作拒绝且不重复扣料。 |
| SEA-SUNROOM-R02 | 梯子修理原子消耗 `wood×5`；二楼休整原子消耗 `wood×8 + soil×2 + glass×1`；材料不足时库存与状态均不改变。 |
| SEA-SUNROOM-R03 | 修好梯子后开放上下端点交互；角色沿真实端点连续攀爬，不通过普通 WalkArea 跨楼层、不用瞬移伪造。 |
| SEA-SUNROOM-R04 | 二楼休整必须在 `ladder_fixed` 阶段执行；成功后开放二楼沙发、二楼行走面和二楼植被。 |
| SEA-SUNROOM-R05 | 初始只显示一株小花；破损叠加、少量下层植被、沙发和完整植被集合随阶段显隐；环境植物不进入 Farm 存档。 |
| SEA-SUNROOM-R06 | 植物表现读取唯一 WorldClock 推导的季节输入；季节只改变表现，不自动推进修缮。 |
| SEA-SUNROOM-R07 | 根存档版本保持 v4；`economy.sunroom` 可选迁移，旧档缺失按 `ruined` 恢复；阶段矛盾、非法照料次数和坏状态在恢复前拒绝。 |
| SEA-SUNROOM-R08 | SunroomService 拥有修缮状态，Inventory/Warehouse 拥有材料，ActorController 拥有攀爬执行，SunroomView 只消费状态表现。 |

## 状态模型

唯一状态所有者是 `SunroomService`。状态集合：

| 状态 | 进入条件 | 可见 / 可用内容 |
|---|---|---|
| `ruined` | 新局默认；旧 v4 存档缺少阳光房字段时迁移到此 | 仅 1 株小雏菊；梯子保留破损视觉但不可攀爬；二楼沙发、二楼植被隐藏 |
| `ladder_fixed` | 消耗木板修梯成功 | 梯子上下交互可用；下层出现少量被照料的植物；二楼休整点出现；二楼沙发和二楼植被仍隐藏 |
| `restored` | 消耗材料完成二楼休整 | 二楼沙发与二楼植被出现；阳光房植物恢复到当前季节允许的完整集合 |

状态单调前进，不提供失败状态、不提供扣回或死亡路径。重复修缮只返回明确拒绝，不重复扣料。

## 数值与材料公式

### 梯子修理

```text
cost_ladder = { wood: 5 }
```

木材支付统一走 Construction/Warehouse 的 `construction_pay` 端口；背包与材料仓储沿用既有统一口径。

### 二楼休整

```text
cost_upper = { wood: 8, soil: 2, glass: 1 }
```

总材料消耗：

```text
wood_total = 5 + 8 = 13
soil_total = 2
glass_total = 1
```

两次支付均采用“先检查全部材料，再一次性扣除”的原子语义。材料不足时返回缺口文案，状态和库存都不改变。

## 梯子攀爬

梯子不是普通 `WalkArea`，也不通过把角色瞬间写到二楼来伪造通行。

- 梯子上下端点由阳光房场景保存；当前端点来自梯子实例的真实局部位置与楼板实际可站面高度，顶部行走面由 `sunroom_upper_deck` 声明，不拿模型包围盒顶部冒充站立面。
- 攀爬速度：`v_climb = 1.35 m/s`。
- 每帧沿端点线性插值：`p(t) = lerp(p0, p1, clamp(t + v_climb·Δt / |p1-p0|, 0, 1))`。
- 攀爬期间关闭角色地面碰撞和普通行走输入，使用独立 `climbing` 状态；取消、读档、过场和保存会阻止在中间状态写入快照。
- 到达端点后回到 `ashore_idle`，角色仍在真实二楼行走面上；后续移动由既有 GroundSpace 处理。
- 攀爬只在 `ladder_fixed` / `restored` 可用，损坏梯子只提供修理交互。

## 视觉拆分

表现层通过 `SunroomView` 接收 `SunroomService.stage + season`，不读 Economy 内部字典：

- `ruined`：保持原有设施结构，隐藏大多数附件，只显示 `daisy_158` 对应的 1 株小花；增加 3 组斜裂木板和 1 块断裂脚踏板作为破损叠加层。
- `ladder_fixed`：破损叠加隐藏；保留梯子；显示下层少量小花 / 嫩芽 / 叶簇；二楼沙发与二楼植被不显示。
- `restored`：显示 `roof_sofa` 及二楼植物；恢复阳光房原有植物集合。
- 季节只影响视觉显隐，不自动推进修缮状态。月份由既有 `WorldClock.day` 推导：春 3–5 月、夏 6–8 月、秋 9–11 月、冬 12–2 月。
- 环境植物继续属于 SEA-AMBIENT 表现，不写入 `economy.farm.plots`。

## 存档契约

根存档版本保持 v4，不增加根必填字段。`economy.sunroom` 是向后兼容的可选模块：

```json
{
  "version": 1,
  "stage": "ruined | ladder_fixed | restored",
  "ladder_repaired": false,
  "upper_restored": false,
  "seasonal_care": 0
}
```

旧 v4 档缺少 `sunroom` 时，迁移为 `ruined`；已有修缮状态不得被迁移重置。校验拒绝“二楼已恢复但梯子未修”“阶段与兼容布尔值不一致”“超范围照料次数”，且在任何模块恢复前拒绝坏记录。

## 所有权与接口

- 状态：`godot/src/facilities/sunroom_service.gd`
- 视觉：`godot/src/facilities/sunroom_view.gd`
- 交互：`sunroom_repair_interactable.gd`、`sunroom_upper_interactable.gd`、`sunroom_ladder_interactable.gd`
- 攀爬：`godot/src/player/actions/climb_ladder_action.gd`、`godot/src/player/states/climbing.gd`
- 场景装配：`godot/scenes/facilities/solar_cabin_surface.tscn`、`godot/scenes/zones/zone1_home_harbor.tscn`

公开命令 / 查询：

```text
SunroomService.repair_ladder() -> Dictionary
SunroomService.restore_upper() -> Dictionary
SunroomService.ladder_repaired() -> bool
SunroomService.upper_restored() -> bool
SunroomService.query() -> Dictionary
SunroomService.to_dict() / from_dict(data)
SunroomService.validate_snapshot(data)
ActorController.climb_ladder(start, end, subject) -> Dictionary
```

## 验收标准

1. 新局只有 1 株小花，二楼沙发和植被不显示。
2. 木材不足时修梯被拒绝，库存不变化。
3. 精确 `5` 木板后修梯成功，破损叠加消失，梯子交互可用。
4. 角色沿真实梯子端点连续爬升，不瞬移、不通过普通地面导航跨楼层。
5. 未修梯时不能直接触发二楼休整。
6. 精确 `8` 木板、`2` 土壤、`1` 玻璃后，二楼沙发与植被出现。
7. 重复修梯 / 重复休整均拒绝且不重复扣料。
8. 阳光房状态写盘、读盘、旧 v4 缺字段迁移和坏状态拒绝均通过。
9. 植物状态不进入 Farm 地格存档；季节变化只改变表现，不自动完成修缮。

## 2026-11-11 通行修订：楼梯下方、二楼行走与攀爬表现

本次按参考图反馈修正三个可达性缺陷：楼梯下方不能走到、楼梯虽有移动逻辑但角色没有明确的攀爬表现、二楼只“启用”走域但未锁定从梯顶到二楼内部的实际路线。

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-SUNROOM-R09 | 阳光房下层走域必须覆盖楼梯脚及楼梯下方实际甲板，并与主甲板保持连通；只补真实甲板带，不放开建筑内部、水面或不可见空间。 |
| SEA-SUNROOM-R10 | 梯子上下端点、修梯点、二楼休整点和破损表现锚点由 `solar_cabin_surface.tscn` 保存；Bootstrap 只注入服务与 `ActorController.climb_ladder`，禁止重新写一套脱离场景的玩法坐标。 |
| SEA-SUNROOM-R11 | `climbing` 状态必须同时驱动连续端点移动和 `climbing_action.gd` 手脚交替表现；移动根位仍由攀爬动作执行，表现采样器不得结算业务或拥有根位移。 |
| SEA-SUNROOM-R12 | `restored` 后二楼走域必须存在从梯顶到二楼内部目标的真实路线；上下梯均可执行，返回下层后角色回到一楼合法支撑面。 |

通行与表现参数保持原契约：攀爬速度 `v_climb = 1.35 m/s`，端点插值仍为 `p(t) = lerp(p0, p1, clamp(t + v_climb·Δt / |p1-p0|, 0, 1))`；本轮不新增失败状态、死亡或传送。
