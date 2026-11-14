# SEA-ROOM · 室内房间 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-room) · [功能文档](spec.md)

```json
{
  "feature_id": "SEA-ROOM",
  "status": "implemented",
  "owner": "RoomService",
  "code_paths": [
    "godot/src/room/room_service.gd",
    "godot/src/room/room_scene.gd",
    "godot/src/room/room_controller.gd",
    "godot/src/room/room_bed.gd",
    "godot/src/room/room_door.gd",
    "godot/src/room/room_exit_point.gd",
    "godot/src/room/room_cutaway.gd",
    "godot/src/room/room_cutaway.gd",
    "godot/scenes/rooms/bedroom.tscn",
    "godot/scenes/components/room/bed.tscn",
    "godot/scenes/main.tscn",
    "godot/scenes/zones/zone1_home_harbor.tscn",
    "godot/src/ui/hud.gd",
    "godot/src/ui/sleep_curtain.gd",
    "godot/src/camera/orbit_camera.gd",
    "godot/src/save/save_schema.gd",
    "godot/src/save/save_game.gd",
    "godot/src/bootstrap/main.gd",
    "godot/src/core/play_scope.gd"
  ],
  "verification": [
    "room",
    "visual-room",
    "sleep-cycle",
    "visual-sleep-cycle",
    "water-layer",
    "modules",
    "framework-integration",
    "minimum-loop",
    "save-protection",
    "building-simulate",
    "energy"
  ]
}
```

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-ROOM-R01 | 已实现；`Objects/SleepCheckpoint` 改名为 `Objects/RoomDoor`，脚本换成 `room_door.gd`，文案「进入房间」，旧 `sleep_checkpoint.gd` 已删除，全仓无第二份睡觉点 | `room` 85 项断言含「旧睡觉点已移除」「入口文案是进入房间」 |
| SEA-ROOM-R02 | 已实现；复用 `SleepCurtain` 的圆幕，新增 `cover_blank`/`uncover_blank`（不碰 caption），过场期间 `input_blocked()`、存档 `busy_query` 全部视为忙，`busy` 防重入 | `room` 实测「进屋圆幕全程没有文字」「过场期间输入被锁」；`sleep-cycle` 42 项 0 失败（原文字过场语义未变） |
| SEA-ROOM-R03 | 已实现；5.0×5.0 净空、墙高 2.75、地板 0.14、后墙窗 1.5×1.15/窗台 0.95、前墙门洞 1.2×2.06，全部来自 `component_plan.json` 并由建模脚本断言 | Blender 源级断言（13 包、7888 三角面、UV 单格内区）+ `room` 实测站立面高度 |
| SEA-ROOM-R04 | 已实现；前厅 3.44×1.80、外檐 2.34/靠墙 2.80、两侧与正面玻璃 + 斜面玻璃顶 + 顶椽，正面留 1.2 米门洞 | `visual-room` 的 `porch` 与 `inside` 两张真实渲染 |
| SEA-ROOM-R05 | 已实现；`room_cutaway.gd` 按相机方位逐帧决定四面墙显隐。判据是**越过这面墙本身**（`offset` + `FACING_MARGIN` 0.25 米），不是越过房间中心 —— 用中心判会在视点偏移时把相邻两面墙一起收掉。前厅件各自带法线与实际 `offset`（正面 2.70、侧玻璃 1.72），并多一条整体规则：相机局部 z > `PORCH_FRONT_Z`(2.4) 时全部收起 | `room` 含「镜头侧墙看不见」「对面后墙可见」「换到另一侧时藏起来的换成那一侧」「俯视机位天花收起」「绕四个方位都正好三面墙可见」「相机在前厅前侧时前厅构件全部收起」；`visual-room` 的 `cutaway-north`；`visual-room-orbit` 八机位 |
| SEA-ROOM-R06a | 已实现；`bedroom.tscn` 根节点 `scale=1.5`（几何仍 1:1）。剖切判据改到房间局部空间（`to_local`），相机距离与环绕缩放区间按 `uniform_scale()` 推导 | `room` 含「房间整体放大 1.5 倍」「剖切在局部空间判（绕四方位仍三面墙）」「机位按缩放后的距离判」 |
| SEA-ROOM-R06 | 已实现；相机新增 `orbit_only`（与 `pose_lock` 并存）：室内允许右键旋转与滚轮缩放、禁止左键平移与键盘平移；俯仰 26–72°、距离 8–24 米（`orbit_pitch_*` / `orbit_zoom_*`）。默认机位 14.4 米 / 俯角 46°。进出房间保存与恢复原 `target/distance/orbit_dir/fov` | `room` 含「相机接管成室内环绕机位」「右键能把镜头转开」「转镜头不挪视点」「俯仰上下限 72/26 度」「拉太近/太远被室内上限挡住」「室内左键不平移」「退出室内环绕、恢复跟随」；`visual-room-orbit` 的 near/far/low/high 四张实拍 |
| SEA-ROOM-R07 | 已实现；三块矩形（室内 4.84×4.84 + 门槛 1.1×0.34 + 前厅 3.24×1.62）合成一个 `WalkArea`，家具自带盒碰撞、床的碰撞随床移动 | `room` 含「室内中心是可走面」「室内可以走」「角色真的走动了」「走动没有走出房间」 |
| SEA-ROOM-R08 | 已实现；床 `movable=true`、`apply_layout(at, yaw)`、`sleep_requested` → Main `_rest_for_day` → 同一套 `sleep_cycle.request()` | `room` 含「床铺是独立可交互物」「床铺绑定睡觉命令」「床上睡一觉到次日 06:00」 |
| SEA-ROOM-R09 | 已实现；`place_bed` 夹回房间、`_nearest_free` 就近滑位、`_overlap_reason` 给出「这里被床头柜占着」这类原因；`validate_snapshot` 独立复核 | `room` 含夹取、拖到床头柜/门口被挪开、无空位时返回 INF 四条 |
| SEA-ROOM-R10 | 已实现；`_wake_at_home` 按 `room_service.inside` 分叉：屋里醒床边、屋外醒门口 | `room` 含「醒来还在房间里」「醒来站在床边、岸上姿态」；`sleep-cycle` 含「在屋外自动入睡回太阳房门口」 |
| SEA-ROOM-R11 | 已实现；`hud.set_room_mode(on)` 增加右下角「出门」圆钮（新 `exit` 图标），并收起 `corner.toolbar` / `corner.actions` | `room` 含「右下角出现出门按钮」「屋外工具栏在房间里收起」；`visual-room` 的 `inside` |
| SEA-ROOM-R12 | 已实现；schema 新增 `room` 模块（不进 required），`save_game.decode` 给旧档补默认值，版本号仍是 4；屋里存档世界位置记成门口，读档 `resync_inside()` 不播过场 | `room` 含存档往返五条 + `save-protection` 复跑通过 |
| SEA-ROOM-R13 | 已实现；`_unhandled_input` 在 `room_service.inside` 时只走 `_try_walk`，海面/船/登陆标记分支全部跳过 | `room` 含「室内只认房间里的东西」（点击路径断言） |
| SEA-ROOM-R14b | 已实现；房间摆在 `(0,200,0)`，远离海面 1.12 / 屋面 11.89 / 海鸥 14.3–17.7 / 水下。`birds.gd` 新增 `set_interior_hidden`，`visible = 时段 ∧ 非室内`；`room_controller._hide_outdoor` 逐节点调用。进屋收起拆除锤子 | `room` 含「远离室外所有内容」「不再压在太阳房顶上」「进屋后鸟群进入抑制」「屋里到 19:00 / 次日 06:30 仍不可见」「出门解除抑制」 |
| SEA-ROOM-R14 | 已实现；`_outdoor_nodes()` 不再保留 `Water`/`BoatWake`，`room_controller._apply_interior_environment()` 把背景切成纯黑、`_restore_outdoor_environment()` 还原；窗挂 `room_glass.tres`（深灰，后面是黑的）、前厅挂 `room_porch_glass.tres`（近透明冷灰，要绕着看），都用 `interior_glass=true`；`resync_outside()` 兜住「在屋里读屋外档」与「从屋里回标题」 | `room` 含「进屋后海面收起」「背景纯黑」「窗玻璃走室内玻璃」「出门后海面与天空盒恢复」「读屋外档海面与天空盒恢复」；`visual-room` 的 `inside`/`porch`/`night` 三张实拍 |

## 回归批次

2026-11-05 本轮实跑（统一 runner，隔离存档）：

- 新增专项：`room` 85 项 0 失败、`visual-room` 6 机位 0 失败。
- 受影响复跑：`sleep-cycle` 42 项 0 失败、`visual-sleep-cycle` 通过、`water-layer` 通过
  （房间声明 `water_layer=surface / role=part`，按「部件跟随宿主」处理，不额外要求水面阻挡与可走面派生）。
- 更广回归：`modules`、`framework-integration`、`minimum-loop`、`save-protection`、
  `building-simulate`、`initial-planters`、`energy`、`camera-follow` 见交付记录汇总。

## 未做

- 「布置」功能本体：本轮只做床的可搬动接口（`place_bed` + 状态存档 + 场景落地），
  没有做拖拽 UI、预览虚影与旋转手势。仓库里既有的建造/搬移流程尚未接入房间。
- 房间多层、窗户开合、帘子、更多家具位与家具目录。
- 夜间窗光投射到室内地面与墙面（现在只有两盏室内灯，窗外是纯黑）。
- 真实手柄/触屏、超宽屏构图与帧率实测。

## 2026-11-05 · 尺度联动

| 对应设计条款 | 当前实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-ROOM-R15 | 已登记为已知限制；门洞 2.06 m 对放大后的默认外观仍成立（发顶 1.869、礼帽 2.050），礼帽+头大 1.12 的 2.154 m 会穿门楣 9.4 cm，本轮不重做资产 | `room`、`visual-room` 6 机位 exit0；`rowing-scale-probe` 给出 2.154 / 2.06 的实测差值。[本轮交付](../../development/2026-11-05_character_scale_150.md) |

## 2026-11-11无损性能优化第一批

承接 SEA-ROOM-R06a/R06/R10/R14；登记 JSON、status、原房间/相机条款与历史保持。

- Main 室内不提交室外 zone/water 表现更新，但 `water.time` 与 weather 模拟相位仍推进；这是隐藏表现裁减，不是冻结世界模拟或改写睡觉结算。
- 旧测试 `orbit_zoom_max < outdoor zoom_max` 的前提已失效：2026-11-09 室外 `zoom_max=35.14`，室内依既有 `scale=1.5` 派生上限 `1.5×24=36`。本轮测试口径改为校验 room 派生上下限（`8×scale` / `24×scale`），不修改相机实现，也不强迫室内上限小于室外。
- 主线程已提供 `room` 112/0、sleep 42/0、`performance-equivalence` 19/0。本次只回填，不新增测试或本地复跑；旧视觉结果不代替本轮最终画面验收。
- 串行两轮室内耗时为 6.222→4.782 ms、5.236→4.458 ms；仅记录这两轮，不外推到所有设备或海面，海面收益波动不承诺。

[主记录](../../development/2026-11-11_performance_optimization.md)由主线程建立并回填最终数据；最终视觉、存档及经营回归仍处理中，本节不预签完整验收。

## 2026-11-11 · 门口出门热区（SEA-ROOM-R16）

承接 SEA-ROOM-R01/R11/R13；登记 JSON、status、原条款与历史保持，仅追加本节。

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-ROOM-R16 | 已实现；新增 `godot/src/room/room_exit_point.gd`（`id="room_exit"`、`verb="离开房间"`、`focus_radius=1.6`、`auto_radius=false`、`focus_anchor="node"`，无视觉几何），挂在 `bedroom.tscn` 根下 `ExitPoint`（局部 `(0, 0, 4.25)`，前厅可走面到 `z=4.32`）。`main._setup_room` 把它接到已有的 `room_exit` 命令，圆幕/世界显隐/存档语义不另做一份；`room_scene.set_active` 沿用既有 `_interactables` 开关，屋外自动退组。近距图标与气泡图标都走 `back` 图（`hover_card.show_near_focus`、`main._open_spot_bubbles`） | `room` 119 项 0 失败，含「屋里门口有独立的出门交互点」「屋外时出门热区不在交互组」「屋里时出门热区进交互组且可见」「站在前厅门洞选中『离开房间』热区」「出门热区的动作文案是离开房间」「按交互键从门口触发出门过场」「出门后门口热区退出交互组」；`visual-room` 新增 `exit` 机位实拍（人物头顶出现返回图标）；`keyboard-farm-loop` 复跑通过 |

## 2026-11-11 · 剖切看角色在哪一侧（SEA-ROOM-R17）

承接 SEA-ROOM-R05/R06a；登记 JSON、status、原条款与历史保持，仅追加本节。

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-ROOM-R17 | 已实现；`room_cutaway.gd` 新增 `actor_query`（`func() -> Node3D`）、`ACTOR_WALL_MARGIN=0.25` 与 `_actor_near_room()` 包围盒守卫。收墙条件改为「相机越过该墙 **且** 角色不在这面墙外侧」——只对人真正会撞到的**墙**生效，玻璃前厅那排构件仍按 `PORCH_FRONT_Z` 整排收。`room_scene` 新增 `set_actor_query()` 并转给剖切；`main._setup_room` 注入 `func(): return player` | `room` 125 项 0 失败，含「进屋时角色站在前厅」「人还在前厅时 +Z 前墙必须可见，不能收成空气墙」「人还在前厅时玻璃/门框/裙墙照旧整排收起」「走进室内后角色局部 z < 2.5」「走进室内后 +Z 前墙按剖切收起」「走进室内后前厅整排收起」；`visual-room` 8 机位 0 失败（`inside`/`exit` 两图可见带门洞的前墙）；`sleep-cycle`、`keyboard-farm-loop` 复跑通过 |

## 2026-11-13 B1 过场存档与代次修复

承接 R02/R12/R14：修正历史账本声称 busy 已统一但实际遗漏的问题。Main busy_query 现包含 room.busy；进出 closing/closed/opening 共六边界直接 capture/write/restore/reset 均拒绝，不依赖输入黑幕。RoomController 增 generation、cancel_transition 与互斥 busy_query，SleepCurtain 无字圆幕可取消，旧 await 不再覆盖恢复现场；resync_outside 还原室内相机，重复室内恢复不覆盖原室外显隐备份。

`room`163/0、save-protection PASS、framework52/0、sleep42/0、energy40/0，均exit0。工程外 b1-lifecycle109/0覆盖真实 Main 自动存档已到期/22:59进屋不共幕、进出六边界、cover/opening取消与旧等待隔离；首轮109/1发现 opening 取消未恢复相机，已修并复跑。最终小批room163/0与当前六个核心脚本逐字节一致。未改main.tscn、Transform、房间资产或根v4；真实渲染本批未执行。[完整证据](../../development/2026-11-13_engine_deep_audit.md#b1-交互生命周期子批实际实施)。

## 2026-11-13 B2 · G06 床位提交与快照一致性

承接 R08/R09/R12：`place_bed` 先归一化 yaw，以同一朝向算占地/夹回/滑位，最终候选经 `validate_snapshot` 后才写状态、发 changed；滑位与快照共用有限闭区间及 `1e-6` 局部米容差，固定陈设重叠不放宽。成功位置不向内偷偷挪 epsilon，恢复已校验 X/Z 不再二次夹回；默认床与存档版本不变。保留 B0/B1 已有改动，不改 RoomController、Main、SaveGame 核心、主场景、资产或用户摆位。

正式 runner 最终合批 `/Users/zyq/work/sea-work/verification/20261113-175647-b2-g06-final-6b72dd/report.json`：room **763/0**、save-boundaries **168/0**、framework-integration **52/0**、自动前置 save-seed PASS；每项及总命令均 **exit0**，completion_marker=true、unexpected_errors=[]。新增覆盖默认、8 组朝向的四边四角/夹回/滑位、提交观察者、有限输入、容差内外、恢复不夹改，以及每个成功布局的正式 write/read 往返。反例首轮 room675/95 exit1；修复后首轮682/82 exit1主要是测试使用 Dictionary 精确比较 JSON 双精度末位舍入，测试纠正为 Vector3 精确比较、yaw 仅 `1e-12` 序列化误差后763/0，不改生产位置来迎合测试。

未覆盖：本轮全 headless，无真实渲染/截图；导航 agent_radius 量化及既有采集点吸附警告仍在，不签零警告。G07 仍待验：例如 yaw=PI/2、床中心在自身右后边界附近，bedside_point 的 +X 候选夹回后可落入床体；本批未改站位策略，未验证真实胶囊净空及到门路线，不能以布局可保存宣称醒来安全。静态全局门禁结果见[本批记录](../../development/2026-11-13_engine_deep_audit.md#b2-g06-床位一致性子批)。

## 2026-11-14 B2 G06/G07 最终承接

承接SEA-ROOM-R07/R08/R09/R10/R12：G06沿用闭区间1e-6局部米、归一化yaw、提交前validate与恢复不二次挪位；当前room763/0。S10缺room统一迁移在B1已实现，本批复用。G07覆盖上节“未改/待验”的阶段描述：四边床局部OBB候选按实际胶囊/房间scale检查墙/家具/walk净空和门路线；Controller注入真实GroundSpace并经同一bedside_path向RoomBed.approach_path交付世界路线，正式ApproachAction保留start_walk准备但不覆盖净空路径。新布置无安全点拒绝，旧档不挪床，必要时前厅安全fallback并提示；root v4/room v1保持。

当前b2-bedside1800/0（130合法布局、133真实胶囊布局/133真实move_ground到门、26正式approach含13绕行）PASS/exit0，不声称连续角度穷举或真实视觉已验。视觉-room/sleep、memento修订后跨进程重置和最终契约待父最终追加；登记头/status不改、不升级verified。[B2主记录](../../development/2026-11-13_engine_deep_audit.md#b2-业务事务与空间修复最终回填2026-11-14)。

### B2 最终状态（2026-11-14）· [主记录](../../development/2026-11-13_engine_deep_audit.md#b2-最后复测与签署范围2026-11-14)
- 005436 bedside1800/0、005741 room763/0与sleep42/0均PASS/exit0；010438 visual-room产8张PNG、visual-sleep-cycle产6张，入口均exit0。
- 本轮相关目检仅room-inside与sleep-wake；前者家具/人物可见，后者是室外太阳房门口、不是室内醒来。未逐图审完，不签全房间美术；全库契约仍失败，登记头不变、不升verified。
