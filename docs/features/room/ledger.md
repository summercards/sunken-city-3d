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
