# 2026-11-20 · 当前 3C／角色交互结构审计

**审计范围：** 当前工作树 HEAD `ceae1b03cce77935bd674c9374429a183dc28569`，默认 F5 仍为 `res://scenes/main_minimal.tscn`；完整玩法由 `godot/profiles/legacy_main.cfg` 指向 `res://scenes/main.tscn` 和 `Zones/Economy/GameState`。代码和资源未因本审计改动。

## 结构结论

- **陆地角色：** `CharacterBody3D` + `CharacterMotor`。`CharacterMotor.move_ground()` 使用 `move_and_collide()`，胶囊由共享 `AvatarDimensions` 建立；地面层 256、角色层 512。`WalkArea → GroundSpace → NavigationServer3D` 提供 `area_at/surface_point/route`，`ActorController` 只编排状态和公开端口，`WalkAction` / `FreeWalkAction` 消费真实物理执行。不是每帧把玩家坐标按速度写过去。
- **角色状态：** `ActorController` 有 `ashore_idle/walking/strolling/approaching/interacting/boarding/boat_idle/sailing/diving/climbing` 状态转换。输入在 Main 转换成相机相对世界方向后，经 `set_move_intent` 进入状态机；交互经 `Interactor` 的目标、接近、长按和取消链，再由业务服务结算。HUD 不直接改库存或移动状态。
- **地面与动态空间：** `GroundSpace` 运行时生成物理地板、边界碰撞和私有导航图；`BuildingWorld.geometry_changed` 触发重投影，建筑布局、农地、导航和交互仍分开拥有。纯视觉节点不自动生成实体阻挡。
- **上下船：** `depart/board/disembark` 是跨载体事务，只有通过泊位、支撑、距离、停稳、对齐、落脚胶囊净空后才 `reparent` 到船座或地面；这类最终位置赋值是交接动作，不是普通移动模拟。E 提示与安全查询共用同一仲裁。
- **阳光房梯子：** `ClimbLadderAction` 只在端点间按 1.35m/s 连续推进，期间关闭普通地面碰撞，`climbing` 动作表现独立；梯脚和二楼端点由 `WalkArea/GroundSpace` 支撑。它不是普通走面，也不是一帧传送。当前阳光房实体盒迁移仍阻断，见 `2026-11-20_sunroom_collision_handoff.md`。
- **正式完整 Main 的船：** `Boat extends Node3D`，使用 `WaterNavigation.plan_route_to/segment_clear` 规划与逐段检查，`Boat._advance_route/_advance_drive` 按 120Hz 子步推进转向、加减速、侧滑和泊位限速。它是结构化的状态/航路仿真，但**尚非 CharacterBody3D 凸船壳扫掠物理**；完整 Main 目前没有白盒那样的 `HullCollision`。
- **F5 白盒船：** `minimal_skiff.gd extends CharacterBody3D`，`main_minimal.tscn` 含 `ConvexPolygonShape3D` HullCollision，`move_and_collide()` 和 `intersect_shape()` 处理正碰、斜碰、转角净空、贴边脱离和泊位接近。白盒船已达到实体船壳物理结构；迁移到完整 Main 是独立首批工作，不能拿 F5 证据冒充完整 Main。

## 当前隔离实测

证据根：`/Users/zyq/work/sea-work/3c-structure-audit-wNeVZ5/verification/20261120-083241-structure-baseline-5bdba1`。

- `click` 39/0；`keyboard-control` 30/0；`keyboard-travel` 374/0。
- `ground-space` 37/0；`interaction-reach` 36/0；`dock-hotspot` 33/0；`building-integration` 46/0。
- `framework-integration` 52/0；`save-boundaries` 168/0。
- `dive-control` 466/0；`visual-dive-transition` 408/0；`minimal-main` 35/0；`visual-minimal-main` 42/0。
- 以上均使用 `scripts/run_verification.py`，独立 user 数据和副本工程；未写玩家存档。白盒 `minimal-skiff` 本轮由于 runner 在 Godot 真窗口 probe 阶段停滞，已有前一轮实测 `157/0` 作为历史证据，但本轮不将其算作新通过。

## 代码写坐标的边界

生产代码中出现直接位置赋值，但用途可区分：

1. `BoardAction`：上船时把角色放到船座，是跨载体交接；
2. `DisembarkAction`：下船放到已验证支撑点，是跨载体交接；
3. `ClimbLadderAction`：沿已授权场景端点连续动作，是特殊梯子状态；
4. `Save/restore`、调试传送和场景装配：恢复或工具入口；
5. 普通移动和正式船航行则分别通过 `move_and_collide` / `GroundSpace` 或 `WaterNavigation` 和船的推进器执行。

因此当前不能简单说“全部都没有坐标写入”，也不能把这些受控交接动作误判成普通移动硬编码。准确结论是：**角色陆地、交互、状态机和白盒船壳属于正常运行时结构；正式完整 Main 船目前是航路/水域阻挡仿真，仍待实体船壳迁移和完整 Main 回归。**

## 2026-11-20 晚间 · 正式 Main 现状复核

本节以晚间工作树为准，更新早间记录中的入口和船体状态。正式 F5 已指向 `main.tscn`，装配 Zones、Economy 和 GameState。本轮审计只追加文档与验证证据。

- **陆地键盘。** Main 把镜头相对方向交给 ActorController。FreeWalkAction 每步先查 WalkArea 的脚下曲面、台阶差和边缘净空，再分轴放行并交给 CharacterMotor 扫掠胶囊。地面登记缺失的地方会在扫掠前停住。ZoneScene 以 WalkArea 的矩形或三角片创建 GroundSpace，运行时生成 GroundFloor、GroundBoundary 和导航网格。家园临时试坡复用这套三角支撑。甲板扫掠实测接地命中 GroundFloor，临水外缘命中 GroundBoundary，朝窗前实墙斜扫命中场景的 SurfaceCollision/FrontWallLeft。
- **陆地点击。** Main.pick_walk_at 交给 ZoneScene.pick_walk，仍由 WalkArea 求命中点并内收矩形边缘落点。WalkAction 沿 GroundSpace 路径推进，每步查支撑并扫掠胶囊。
- **手动划船。** Main 中的 Boat 已是带凸形 HullCollision 的 CharacterBody3D。FormalHullMotion 在物理帧检查旋转净空、扫掠平移并检查末端重叠。当前运行的 World 树上，与船掩码 4096 匹配的物理体只有家园木栈桥的 BoardHullContact。该船壳在直接扫掠时确实命中栈桥。
- **水域查询仍控制手动位移。** FormalHullMotion 的通过条件同时包含船壳结果与 Main._formal_water_step。后者调用 WaterNavigation.can_enter_raw_water，从相同的 BlockerSet、烘焙岸线、渔场和建造投影取得轮廓，对每一步的目标船中心做未经缓冲的禁入判断。正式场景探针测得一次被该查询拒绝、但船壳扫掠没有命中的位移。点水面、远泊位等自动航行入口已停用，只有未配置正式船壳的旧实例仍能执行旧船推进分支。

### 当前验证

| 批次 | 证据 | 退出码 |
|---|---|---|
| [当前树正式专项](../../../sea-work/verification/20261120-182418-main-3c-current-audit-818e02/report.json) | 无头 ground-space 37 项全过、sunroom-surface-collision 14 项全过。Metal 实窗试坡 18 项全过并保存三帧。窗前甲板 19 项中 3 项失败，手动划船 12 项中 1 项失败，交接 12 项中 2 项失败。 | 前三项引擎 0，后三项引擎 1，runner 1 |
| [窗口失焦诊断](../../../sea-work/verification/20261120-182805-main-3c-focus-audit-247519/report.json) | 仅在工程外副本加日志。系统窗口失焦切断模拟输入，重新聚焦时持续按键仍等待松开。记录了甲板、划船及靠泊阶段的输入中断。 | 三项引擎 1，runner 1 |
| [正式场景碰撞探针](../../../sea-work/verification/20261120-183008-main-3c-collision-probe-r2-67b4ec/main-collision-audit.log) | 无头直接扫掠复核船壳与栈桥相撞，以及另一处旧轮廓禁入而物理无接触。家园地板和外缘生成体同时在场。 | 引擎与 runner 0 |

临时探针首轮因诊断脚本编译错误，Godot 返回 0，runner 按错误日志与缺失完成标记返回 1。上表采用修正后批次。本轮未做全岛实体覆盖、全地图点击寻路或人工进泊验收。

契约同步与只读检查均退出 1，分别报 586、587 项。只读问题集合与审计前一致，包含历史证据链接、资产哈希和内容 ID 漂移。
