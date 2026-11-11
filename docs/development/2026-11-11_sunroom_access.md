# 2026-11-11 阳光房楼梯下方、二楼行走与攀爬表现修订

## 用户反馈

参考图反馈三个问题：

1. 楼梯下面有一块区域走不到。
2. 楼梯需要真的可以爬上去，且角色应有明确的攀爬动作。
3. 二楼需要能够正常行走。

本轮先阅读 `GDD_V1.0.md`、`docs/features/sunroom/{spec,ledger}.md`、`docs/features/move/{spec,ledger}.md` 与 `docs/features/nav/{spec,ledger}.md`，沿用已有的“普通行走走域 + 竖直梯子特殊动作”边界，不把梯子硬塞进普通 GroundSpace，也不新增失败状态、死亡或传送。

## 实施变更

### 1. 下层楼梯下方可达

文件：`godot/scenes/zones/zone1_home_harbor.tscn`

`Walk_zone1_home_dock` 新增一条与现有甲板重叠的通行带：

```text
Rect2(3.5, 2.5, 2.0, 5.2)
```

这条带覆盖当前阳光房楼梯脚附近的真实下层甲板，并与既有区域重叠约 0.2 米，避免出现“看得见甲板但走不到”的断岛。没有放开建筑内部或水面。

### 2. 场景成为阳光房玩法锚点的唯一位置

文件：`godot/scenes/facilities/solar_cabin_surface.tscn`

新增五个 Marker3D：

- `SunroomRepairAnchor`
- `SunroomLadderBottomAnchor`
- `SunroomLadderTopAnchor`
- `SunroomUpperRestoreAnchor`
- `SunroomDamageAnchor`

文件：`godot/src/bootstrap/main.gd`

`_setup_sunroom()` 改为读取这些锚点的世界位置，再注入 `SunroomService` 与 `ActorController`。Bootstrap 不再维护一套脱离场景的硬编码端点/交互坐标。

### 3. 攀爬动作接线

文件：`godot/src/player/character.gd`

`set_climbing(true)` 不再把表现基础动作伪装成 `walking`，改为消费既有 `climbing_action.gd`。手脚交替、身体抬升表现由采样器负责；角色根位仍由 `climb_ladder_action.gd` 按端点连续插值执行。

公式保持不变：

```text
p(t) = lerp(p0, p1, clamp(t + 1.35·Δt / |p1-p0|, 0, 1))
```

其中 `v_climb = 1.35 m/s`。

### 4. 二楼实际行走与上下梯闭环

文件：`godot/tests/test_sunroom_runtime.gd`

专项新增断言：

- 下层目标 → 梯脚 `path_between()` 非空。
- 梯顶 → 二楼内部目标 `path_between()` 非空。
- 角色进入 `climbing` 时动画状态为 `climbing`。
- 上梯后角色进入二楼支撑面。
- 角色在二楼接受真实 `start_walk()` 目标并完成移动。
- 从顶部端点下梯后回到一楼高度。

### 5. 存档坏状态断言

文件：`godot/src/save/save_schema.gd`

在字段结构检查后显式调用：

```text
SunroomService.validate_snapshot(data.economy.sunroom)
```

阶段与兼容布尔字段矛盾时，在任何模块恢复前拒绝；不允许靠 `from_dict()` 的兼容降级绕过坏状态。

## 验证

执行：

```text
python3 scripts/run_verification.py sunroom-repair sunroom-runtime save-protection
```

结果：

- `sunroom-repair`：14 checks / 0 failures，exit 0。
- `sunroom-runtime`：20 checks / 0 failures，exit 0。
- `save-corrupt-seed`：exit 0。
- `save-protection`：exit 0。

最终专项证据目录：

```text
D:\projects\sea-work\verification\20261111-150345-verification-e20c4c
```

本轮只完成正式主场景运行专项；真实截图审阅仍作为独立表现门禁保留 pending，没有用代码专项代替视觉验收。

## 影响边界

- 未修改存档根版本，仍为 v4。
- 未新增角色失败状态、死亡、体力消耗或玩法资源。
- 未修改水面航行逻辑。
- 未把阳光房梯子加入普通 WalkArea 或水面导航。
- 未修改 `godzilla-pet/tv/`，本项目没有该目录。
