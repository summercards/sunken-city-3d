# 2026-11-05 角色整体放大 50% 与划船装配回算

[返回主文档](../../GDD_V1.0.md#sea-avatar) · [角色表现契约](../character-visuals.md) · [avatar 规格](../features/avatar/spec.md) · [MOVE 规格](../features/move/spec.md) · [NAV 规格](../features/nav/spec.md) · [CAMERA 规格](../features/camera/spec.md) · [PICKUP 规格](../features/pickup/spec.md) · [ROOM 规格](../features/room/spec.md)

## 需求

主人要求：先 Git 存档一份，再把角色整体尺寸放大 50% 左右，并且**连带处理**受影响的装配 —— 明确点到
「划船那块位置的船桨、人的位置、座位」。

存档：`0a213171 chore(checkpoint): 角色尺寸放大前存档 2026-11-05`（含当日全部未提交改动，可整体回滚）。

## 一、单一开关：`avatar_dimensions.gd` 的 `SCALE`

原来所有尺寸是散落的参考米值。现在只有一个常量：

```
const SCALE := 1.5
```

推导：参考身形站立发顶 1.26 m（礼帽 1.35 m），×1.5 → 发顶 **1.869 m**、礼帽 **2.050 m**。
它按「谁的坐标系」分两类消费，**不得二次相乘**：

| 消费位置 | 是否已含 SCALE | 写法 |
|---|---|---|
| 骨骼关节（肩/髋/肘/膝/手/脚）、`THIGH`/`SHIN`/`UPPER_ARM`/`LOWER_ARM`/`HIP_X`/`HIP_Y`/`HEAD_CENTER` | 已含 | 常量本体 `×SCALE` |
| 体型因子派生量（`hip_y`、`shirt_center`、`shoulder`、`hip`） | 已含 | 在 `factors()` 里乘一次 |
| `AvatarHead` / `AvatarHat` / 躯干球、礼帽、脸部、发型 | 不含（这些节点自己缩放） | 父节点 `HEAD_SCALE×SCALE` 或 `_m()`，子节点保持参考尺寸 |
| 四肢蒙皮剖面（`_profile` 的半径与纵向偏移） | 不含 | `_scaled()` 统一乘一次；关节位置先 `/SCALE` 折回参考系 |
| 获物动画、坐姿间隙、相机瞄准高度、进度条锚点 | 不含 | 各自取 `SCALE` 显式相乘 |

`character_motor.gd` 与 `ground_space.gd` 改为从 `avatar_dimensions.gd` 读同一个体积常量，避免胶囊与
导航 agent 半径各写一份。

## 二、连带修改清单

| 位置 | 改了什么 | 原因（不这么改会怎样） |
|---|---|---|
| `scenes/props/reference_skiff.tscn` | `OarL`/`OarR`、`oarlock_038/039` 的 z 从 0.55 前移到 **0.73**（+0.18 m） | 手臂变长 50%，握点落在身后：改前实测最小手掌前向距离只有 0.309 m 但肘在肩后 −0.073 m，握柄位置相对身体太近，手臂折叠到 136.5° |
| `src/player/animation/rowing_action.gd` | 座面→骨盆间隙 `0.05×SCALE`；无接触回退目标 `×SCALE` | 间隙写死 5 cm，放大后骨盆陷进座板 |
| `src/player/animation/item_receive.gd` | 举物路径、挎包、背带、肩部抬起、手腕偏移全部 `×SCALE` | 否则物件停在胸口、包带穿身体 |
| `src/player/character.gd` | 潜水气瓶、面罩、手脚锚点偏移 `×SCALE` | 气瓶缩在缩小位置、鞋底锚点错位 |
| `src/onboarding/arrival_camera.gd` | 肖像中心点、距离、横向偏移 `×SCALE` | 到达/捏人取景会裁掉头 |
| `src/camera/states/follow.gd`、`orbit_camera.gd`、`bootstrap/main.gd`（3 处）、`room/room_controller.gd` | 跟随瞄准高度 `0.7 → 0.7×SCALE = 1.05 m` | 角色长高而镜头仍盯 0.7 m，头部被推到画面上沿 |
| `src/pickups/pickup_progress.gd` | 头顶进度条抬升 `1.35 → 1.35×SCALE = 2.025 m` | 发顶已到 1.869 m，写死 1.35 会把条压进头发里 |
| `src/avatar/avatar_limb_skinning.gd` | 剖面 `_scaled()`、权重过渡带、UV、区域查询阈值随缩放 | 关节过渡带固定 4.5 cm，放大后弯折起皱、UV 错位 |
| `src/avatar/avatar_visual.gd`、`avatar_morphology.gd` | 头部/礼帽/躯干球/衣领/骨盆截面、下潜面具、安全距离 `×SCALE` | 头部比身体小一圈、衣领悬空 |

## 三、实测数据

统一 runner、Autoload 前隔离用户数据；未修改玩家存档。`rowing-scale-probe` 是本次新增的只读标尺入口。

### 坐姿与握桨（`rowing-fit`，76631 项断言）

| 指标 | 放大前（SCALE=1.0，桨 z=0.55） | 放大后（SCALE=1.5，桨 z=0.73） |
|---|---|---|
| 手掌与握柄最大偏差 | 2.188 mm | **0.0004 mm** |
| 手掌最小前向距离（肩前为正） | +127.6 mm | **+309.1 mm** |
| 肘部最小前向距离 | **−72.6 mm**（在肩后） | **+80.9 mm**（在肩前） |
| 肘部最大折叠角 | 136.50° | **107.00°** |
| 前臂共同肘轴误差 | 2.42e-7 | 2.46e-7 |
| 臀部与座板最大间隙 | 6.56 mm | 9.84 mm |
| 腿部穿座板顶点数 | 0 | **0** |
| 桨叶接水 y 范围 | −0.0678 … +0.330 m | −0.0678 … +0.330 m |

座位本体没动：`RowingSeat = (0, 0.6025, 0.32)`，仍在中排座板（`bench_020` 顶面 0.6025）前半部。
船底 `floor_board` 顶面 0.203 m；坐姿脚踝 0.423 m、鞋底约 0.31 m，脚离船底约 0.11 m（放大前约 0.08 m），
维持原设计里脚不落地踩板的姿态，未加脚踏件。

### 站姿与净高（`rowing-scale-probe`）

| 项 | 数值 |
|---|---|
| 胶囊半径 / 高度 | 0.220 / 1.300 m（**未随 SCALE 变**，见下节） |
| 肩关节高 | 1.240 m |
| 头部中心高 | 1.650 m |
| 发顶 | 1.869 m |
| 礼帽顶（默认头大小） | 2.050 m |
| 最坏组合：礼帽 + 头大 1.12 | **2.154 m** |
| 房间门洞净高（SEA-ROOM-R03） | 2.06 m |
| 室内净高 / 床长 | 2.75 m / 2.03 m |

## 四、胶囊与导航半径**没有**跟着放大（实测依据）

第一版把胶囊与 `ground_space.ACTOR_RADIUS` 一起放大到 0.33/1.95，理由是「代理人应包住身体」。实测结果：

- `surface`：新增失败「木桥连接可达」——从泊位走到菜箱的路径在 2000 帧内没走完。
- `landing-markers`：3 项失败。

导航网格的 `agent_radius` 从 0.22 涨到 0.33 后，木桥与几处窄栈桥的可行走面被挖空。这是**玩法可达性**，
不是视觉问题。因此改回：胶囊与导航半径保持 0.22/1.30 的既有契约，只放大视觉身体。
代价是极近距离贴墙时身体可能轻微压进墙里；在 77.8 m 俯视机位下不可见，优先级低于「路走得通」。

对照验证：把 `SCALE` 临时改回 1.0 重跑 `surface`/`landing-markers`，失败项与放大版**完全相同**
（`上岸高度与地面一致`、`种植物件是独立场景`；`landing-markers` 的 3 项），说明这两项是既有问题，
不是本轮引入。本轮唯一由胶囊引起的新增失败是「木桥连接可达」，已随胶囊回退消失。

## 五、已知限制

1. **门楣**：礼帽 + 头大 1.12 时发顶 2.154 m，比 2.06 m 门洞高 9.4 cm，进门瞬间帽顶会穿门楣。
   默认外观（发顶 1.869 / 礼帽 2.050）在门洞内还剩 1 cm。未改门洞资产
   （`SEA-SCENE-BDR-003` 前墙、`SEA-SCENE-BDR-008` 门框需要重跑 Blender 管线）。两条备选：
   门洞加高到 2.30 m；或把礼帽冠高按 `SCALE` 收 10%。
2. **脚不落地**：坐姿鞋底离船底 0.11 m。放大前就有 0.08 m，本轮不是新增缺陷；如要踩实需加脚踏横杆件。
3. **肩宽 vs 胶囊**：视觉肩跨 0.486 m 而胶囊直径 0.44 m，贴墙站会露出一点肩膀在墙内。

## 五之二、资产登记与哈希刷新（逐条审阅，不做批量掩盖）

`check_feature_contracts.py` 在改前报 21 项，其中 5 项是本轮角色源码导致的**源哈希漂移**
（`SEA-CHAR-AVATAR-001` / `RIG-001` / `SHAPE-001` / `RECEIVE-001`）。逐条核对 `git diff` 后刷新：

| 登记项 | 变更 | 处理 |
|---|---|---|
| `characters.json` 四条 | 源码确为本轮改动；`previous_source_sha256` 保留旧值，`version` 各进位一档，`verification` 指向本文件，新增 `scale_contract {scale:1.5, source:avatar_dimensions.gd}` | 刷新 |
| `art_source/characters/avatar/v002/rig_contract.json` | 21 骨 `rest_origin` 原为参考尺度；全部 ×1.5 并新增 `reference_scale` / `scale` / `scale_source`，`collider` 注明胶囊**有意不放大**的原因 | 重算 |
| `art_source/characters/avatar/v006/shoulder_contract.json` | 米制目标保持参考尺度，新增 `runtime_scale=1.5` 与换算说明（0.145→0.2175 m、0.741→1.1115 m），避免后人以为目标值失效 | 追加字段 |
| `runtime_resource_inventory.json` | 本轮改动的 10 个运行文件（含 `reference_skiff.tscn`、`orbit_camera.gd`）逐条刷新哈希，保留 `previous_sha256` 并写明原因 | 刷新 |
| `current_source_index.json` | 4 条角色源哈希 + 按账本顺序重排（原索引在沉船城追加后已失序） | 重建 |

**没有刷新的**（不属于本轮，且不批量更新以免掩盖其他轮的变更）：`SEA-SCENE-ORF-ASSEMBLY` 源哈希、
`ocean_sky.tres`、`poster_atlas.png.import`、`test_sunken_city.gd`、`walk_action.gd`、`bootstrap/main.gd`
（后者在工作区里同时叠着键盘控制轮未提交的 `BOAT_KEY_REACH` 改动）。

网关结果：改前 21 项 → 改后 **7 项**，其中 0 项由本轮功能承接的条款、路径、链接或已审阅哈希引起。

## 六、当前验证

全部经统一 runner，Autoload 前隔离用户数据。

| 入口 | 结果 | 备注 |
|---|---|---|
| `rowing-fit`（= `visual-rowing-fit`） | PASS，76631 项，exit0 | 9 组体型 / 30-60-120 FPS / 站位-停船-转向 / 24 相位 |
| `rowing-scale-probe` | PASS，exit0 | 新增只读标尺：胶囊、站姿身高、座板、桨架、握点、关节 |
| `visual-rowing-game` | PASS，exit0 | 正式 main 的拉桨/中段/回桨/返回/停船/侧视/手臂近景，已逐图目视 |
| `avatar` / `avatar-skinning` / `avatar-proportions` / `avatar-graphic` | PASS，exit0 | 骨骼、蒙皮、参考比例、独立滑杆 |
| `avatar-customization` | PASS，exit0 | 需把 `--timeout` 提到 3000 s（默认 900 s 会超时，不是失败） |
| `character-motor` / `surface` / `click` / `board-click` / `walk-facing` / `walk-deck-fit` | PASS，exit0 | |
| `camera` / `room` / `visual-room` / `onboarding` / `progress-bars` | PASS，exit0 | |
| `reference-skiff` / `visual-reference-skiff` | PASS，exit0 | 桨轴前移后装配合同仍成立 |
| `harvest-receive` / `visual-harvest-receive` | PASS，exit0 | 举物净空阈值改为 `×SCALE`（1.5/1.35/0.29/0.23/1.60 五处）后全绿 |
| `avatar` + `avatar-restart`（必须成组） | PASS，exit0 | 单独跑 `avatar-restart` 会因没有前一步写入的存档而 6 项失败，属 runner 分组契约 |
| `actor-presentation` / `save-protection` / `save-corrupt-seed` | PASS，exit0 | 存档格式未变 |
| `modules` / `minimum-loop` / `framework-integration` / `walk-on-planters` / `character-space-save` | PASS，exit0 | `character-space-save` 的楼层跟随断言改为 `12.0 + CAMERA_FOCUS` |
| `unreachable-menu` / `wood-bundles` / `interact-focus` / `pick-mesh` | PASS，exit0 | 热区与点击不受体型影响 |
| `surface` / `landing-markers` | 各 2/3 项既有失败 | 与 `SCALE=1.0` 对照结果一致，非本轮引入 |

## 六之二、需要主人拍板的两件（本轮只记录，未擅自动）

**1. 坐姿的双脚离船底 0.11 m（改前 0.08 m）。** 不是这次放大引入的新缺陷，但放大后更显眼。
几何上无法靠调姿势解决：

- 座板顶面 0.6025 m、船底板顶面 0.203 m，落差 0.40 m；
- 髋 0.678 m，大腿 + 小腿共 0.578 m，想踩到底必须把大腿下压 ~30°；
- 但座板只有 0.524 m 深、角色坐在前半部，大腿一旦下压，在 z=0.412（座板前缘）处
  大腿下沿会掉到 0.575 m，直接穿进 0.6025 m 的板面 —— `rowing-fit` 的「腿部不穿座板」立刻失败。

三条路，都要主人选：
① 加一根脚踏横杆（改 `reference_skiff.tscn`，46→48 件，要重跑装配登记）；
② 把中排座板降低或做薄（动的是小船资产本体）；
③ 维持现状，接受脚尖悬空 —— 划艇坐姿里脚本来也踩着桨架横档，视觉上不算错。

**2. 门楣净高 2.06 m 只剩 1 cm 余量。** 默认外观（发顶 1.869 / 礼帽 2.050）刚好过；
`礼帽 + 头大小滑杆拉到 1.12` 时 2.154 m，会穿门楣 9.4 cm。要么把门洞加高到 2.30 m
（`SEA-SCENE-BDR-003` / `BDR-008` 重跑 Blender 管线），要么给礼帽冠高加一个按 `SCALE` 的上限。

证据目录：`D:/projects/sea-work/verification/`，本轮关键批次
`20261105-220250-scale-visual-3-ac4150`（实拍）、`20261105-220536-scale-probe-5-1f88da`（标尺）、
`20261105-212448-scale-probe-2-0eb69e`（划船拟合首次全绿）。

## 七、未执行

- 触摸/手柄、发行包、长时间设备性能。
- 全部外观组合的目视：本轮实拍固定在默认外观 + 礼帽，密集组合由 `avatar-customization` 断言覆盖。
- 水下场景与潜水动作的逐机位实拍（游泳动作按比例自动生效，未单独出图）。
- 门洞/家具资产重做（见「已知限制」）。
