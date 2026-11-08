# 2026-11-08 霓虹花园：可走面绑定模型、楼顶种菜与头顶招呼

[主文档](../../GDD_V1.0.md#sea-world) · [世界设计](../features/world/spec.md) · [世界账本](../features/world/ledger.md) · [NPC 设计](../features/resident/spec.md) · [NPC 账本](../features/resident/ledger.md)

用户要求：「修改这个楼房的行动范围，之前有说过这个改成 3 个建筑；阻挡要先制作，然后楼顶和种植的屋顶为可到达区域。豆豆会在上面种植（NPC 的 AI 行为），玩家的船经过的时候会打招呼，这时要增加角色头上的对话框，每天触发一次。需要和下方对话框同一个风格的角色头顶对话框，带有箭头的。每天的话不一样。」

追加澄清（本轮）：**可行走区域要绑定模型，不要额外制作**；**只让豆豆在楼上，有一个斜坡在种植的地方**；**左右中间是一个独立的，后是独立的**。

## 1. 三栋楼的既有结构（核对结果）

`godot/scenes/facilities/neon_garden_quarter.tscn` 在 v004 拆成五个可独立打开/实例化的模块，主场景只需挂一个实例：

| 模块 | 局部位置 | 说明 |
|---|---|---|
| `left_building` | (-15.81, 0.30, 0.62) | 左楼，六层 + 屋顶 |
| `rear_building` | (0.00, 0.30, -12.38) | 后楼，五层屋顶农园 |
| `right_building` | (13.08, 0.30, 0.72) | 右楼，七层圆弧窗湾 |
| `garden_bridge` | (0.00, 23.30, 1.27) | 双坡菜园桥，跨接左右两楼 |
| `street_ground` | (-2.15, 0.10, -2.35) | 街道地面 |

用户说的「左右中间是一个独立的，后是独立的」，与现状一致：左右两楼各自独立，后楼独立，桥是连接体。所以三栋楼的分组**不需要再拆**，只在各自根上加可走面与阻挡。

用户手动把整栋摆到 `(106.55533, -15.869949, 88.88402)` 并转了约 72°（`main.tscn:123`）。按 AGENTS 第 12 条，这是唯一真值，本次未动。

## 2. 实测层高（几何探针，只读）

用一次性探针从真实网格量出来的水平层：

| 部位 | 局部 y | 水平面积 | 说明 |
|---|---:|---:|---|
| 左楼顶 | 31.10 | 198.8 m² | 女儿墙内侧，被楼梯间/水箱占去一部分 |
| 后楼顶 | 26.00 | 95.9 m² | 五层屋顶农园平台 |
| 右楼顶 | 36.20 | 191.2 m² | 七层 |
| 菜园桥种植土面 | 25.60–28.72 | 约 693 m² 计 | 双坡，土面最高 28.60、菜床顶 28.71 |
| 街道地面 | 0.30 | 679.8 m² | 现状唯一已登记的可行走面 |

菜床（`crop_bed_*`）共 7 个，全部落在桥面上 `top=28.707`；`roof_soil_395` 跨 -10.60…10.60 × -0.89…5.29，`top=28.600`。

## 3. 实现

### 3.1 新增 `DerivedWalkArea`：可走面从模型派生

`godot/src/navigation/derived_walk_area.gd`（继承 `walk_area.gd`）。给一个几何源节点，运行时从真实三角形里算出「哪里能站」：

1. 收集源节点下所有 `MeshInstance3D` / `MultiMeshInstance3D` 的世界三角形（只判「有没有网格」，**不看运行期可见性**——派生发生在 `_ready`，那时 `PlayScope` 还没跑完，`is_visible_in_tree()` 会把整栋判成隐藏，实测整片楼顶 rects=0）。
2. 按高度聚层，`select` 决定取哪层：`largest` / `highest` / `nearest`（配 `target_y`）。
3. 只保留坡度可走的面（`max_slope_deg`）。**按 `absf(normal.y)` 判断，不看绕序正负**：这批模块的板面绕序不统一（屋顶板多为背面朝上、材质双面渲染），用有符号判据会把整片楼顶误杀，只剩女儿墙内侧那点面积。
4. 栅格化（默认 0.5 m），再逐格查站立净空：该格上方 0.06–1.75 m 内有没有**穿过 0.35 m 以上**的几何。低于 0.35 m 的槽沿是能跨过去的边，不该把整片种植土判死。
5. 可站格按 8 邻域内收一圈（≈ body_radius 0.38），再合并成矩形写回 `rects` / `surface_y` / `span_min` / `span_max`。

模型移动、旋转、改版后下一次重建按签名自动重算，场景数据不用改。派生结果只写在运行期字段上，不回写 TSCN。

坐标系是三处坑，全部用 `to_local` / `to_global` 而不是「世界坐标减原点」：

- `target_y` 是**相对模型根**的高度（和建模时看到的层高一致），三角形是世界坐标，比较前要加 `global_position.y`。这栋楼摆在 y=-15.87，不换算整条带子取空。
- 格号必须走 `to_local`：楼体被转了 72°，用世界减原点会把整片楼顶算到别处（实测 rects 全挤到后楼那边）。
- 高度场贴片的角点要「局部 XZ + 世界 y」再转回世界（`_world_corner`）。

### 3.2 场景配置

`neon_garden_quarter.tscn` 的 `WalkAreas` 下新增四个派生面：

| 节点 | 源 | 模式 | 实测结果 |
|---|---|---|---|
| `WalkLeftRoof` | `Visual/LeftBuilding` | `nearest` 31.10 | 18 矩形，可站 469 格 |
| `WalkRearRoof` | `Visual/RearBuilding` | `nearest` 26.00 | 10 矩形，可站 168 格 |
| `WalkRightRoof` | `Visual/RightBuilding` | `nearest` 36.20 | 21 矩形，可站 440 格 |
| `WalkGardenDeck` | `Visual/GardenBridge` | `band` 27.4 ±1.35 | 42 矩形，可站 213 格，surface_y 27.40 |

原 `WalkStreetLanding`（街口上岸点）保持不变，仍是唯一手写面。

`ZoneScene._register()` 原先用 `walk.get_script() == WalkArea` 收集可走面，继承脚本会被漏掉；改成按能力判定（`has_method("surface_faces") and has_method("outlines")`）。

### 3.3 船体阻挡

`Blockers` 的 `target_path` 从 `../Visual/Foundation/GroundMesh` 改成 `../Visual`——原来只挡街道底下那块地面，三栋楼的水面轮廓完全没挡，船能穿楼。

实测（水线 1.12、船高 1.6）：93 ms，63644 三角形、116 实例、51 矩形、152.3 m²，总包围盒 x[-23, 18.5] z[-17.5, 12.5]。逐楼投影抽样：左楼 24%、后楼 28%、右楼 14% 的格被挡——比例不高是正常的，`cell=0.5` 的栅格只在水线到船高那一段取三角形，楼体是大空腔。

### 3.4 豆豆迁到菜园桥

`godot/assets/data/npc/npcs.json` 只改豆豆一行的日程锚点与 `activity_anchor`（`home_anchor` 不能动：`npc_catalog.gd:223` 硬校验它必须等于 `residence_id`，而住所仍 deferred）：

| 原锚点 | 新锚点 | 用途 |
|---|---|---|
| `anchor_planter` | `residence_garden_bridge_work` | 6–17 点看苗、理种子 |
| `residence_sunroom_greenhouse` | `residence_garden_bridge_rest` | 17–21.5 晾叶、雨天盖盘 |
| `anchor_solar_room` | `residence_garden_bridge_social` | 好感 500 分享笔记 |

`neon_garden_quarter.tscn` 新增 `NpcStations`（`npc_site_anchors.gd`），参考位 `(-5.5, 28.4, 1.7)`，五个 Marker：Home / Work / Social / Rest / Door。锚点解析实测 `residence_garden_bridge_work = (106.2377, 12.52529, 83.00532)`，全部 5 个 id 可解析。`main.gd` 的 `anchor_hub.configure` 加入第三个 provider。

`NpcWorldPresenter._sync_npc` 原先遇到「寻路为空」直接判原地停止——天台草地与海上结构之间没有连通陆地，改过日程的居民会永远留在旧场地。现在：**只在当前站立点不在目标可走面内时**直接落位到目标支撑点，同一区块内仍坚持真实寻路（不把「无路可达」悄悄变成瞬移）。

### 3.5 头顶招呼气泡

`godot/src/ui/speech_bubble.gd`：与底部对话框同一张 `Cozy.surface(#fbf6e8, 28)` 奶白纸面 + 底部小三角，字体取同一个 `Cozy.ui_font()`。三角的横向位置跟随角色屏幕投影，角色偏在一侧时尾巴跟过去——否则「带箭头的对话框」只是贴了个三角、指不到人。

尺寸直接量 `font.get_multiline_string_size()`，不用 `Label.reset_size()`：未进容器时它的最小尺寸要等一帧才稳，那一帧里 size 还是 0，气泡会被夹到屏幕底边（实测尾巴落在 y=790）。

台词表 `godot/assets/data/npc/greetings.json`：豆豆 12 句，按游戏日轮换（`posmod(day-1, n)`），同一天只喊一次。触发在 `main.gd:_tick_garden_greeting`：玩家与豆豆的**水平** XZ 距离 ≤ 32 m（初版 16 m，当晚按反馈放宽，见第 12 节）（她在 28 米高，用三维距离会让船正好从楼底经过时反而「太远」），且当前没有 NPC 模态。

**「今天已喊过」不持久化。** NPC 存档有严格字段校验（`npc_save_codec.validate` 拒绝未知字段），加新字段会让旧档加载失败；存档是核心资产，宁可读档后当天可再喊一次。这是明知的取舍。

## 4. 验收

均经 `scripts/run_verification.py` 在 Autoload 前隔离用户目录。

| 专项 | 检查数 / 失败 | 退出码 | 报告目录 |
|---|---|---|---|
| **garden-npc**（新增） | 14 / 0 | 0 | `20261108-171730-ng-garden-final-e48655` |
| **visual-garden-bubble**（新增） | 13 / 0 | 0 | `20261108-173745-ng-bubble-final-302821` |
| npc-rules | 655 / 0 | 0 | `20261108-171531-ng-rules6-cd586d` |
| npc-world | 135 / 0 | 0 | `20261108-171523-ng-world6-acd448` |
| npc-integration | 749 / 0 | 0 | `20261108-173055-ng-int3-285ff4` |
| npc-save | 702 / 0 | 0 | `20261108-173853-ng-save2-614474` |
| npc-save-seed | 476 / 0 | 0 | `20261108-174215-ng-seed2-98a04f` |
| npc-save-restart | 202 / 0 | 0 | `20261108-174305-ng-restart2-9cfdb8` |
| npc-conversation | 445 / 0 | 0 | `20261108-174607-ng-conv2-c6d42f` |
| minimum-loop | 112 / 0 | 0 | `20261108-171940-ng-min-3-4620cd` |
| npc-performance | 61 / 0 | 0 | `20261108-172016-ng-perf-a4ef77` |
| npc-clock | 303 / 0 | 0 | `20261108-172019-ng-clock-8d1ccf` |

12 个入口合计 **3867 / 0**，全部 `exit0`、`completion_marker=true`、`unexpected_errors=[]`。报告父目录 `D:/projects/sea-work/verification/`。

`garden-npc` 在真实主场景（含用户手摆变换）里验：菜园桥可走面已从模型派生（42 矩形、surface_y 12.53 世界）、豆豆的世界位置在桥面上、5 个锚点可解析、靠近后气泡显示台词、同一天不换句、换一天换另一句。

`visual-garden-bubble` 真实渲染两张（单句 / 长句换行），逐图打开核对：奶白圆角纸面、底部小三角、文字完整、气泡完整在视口内、尾巴指向角色头顶。

## 5. 必须说明的取舍与代价

1. **玩家走不到豆豆身边。** 用户明确说「只让豆豆在楼上」且不额外做上楼路径，所以菜园桥（约 28 米高）与街面 0.30 之间没有连接。玩家在楼下船上能看到她、收到头顶招呼，但走不到判定区、无法走近交谈。`npc-conversation` 里她的「走近交谈」已改为断言「楼顶可见」，她的站立与招呼由 `garden-npc` 验。**如果以后想让玩家上去聊，需要单独一轮做楼梯，并把该断言改回来。**
2. **菜园桥是压平的。** 双坡土面高差 0.3 米以内，派生面按格压平取中位高度（27.40），角色会有几厘米浮空。做成精确斜面（`flatten_slopes=false`）时，2.5 米宽的带子被 `agent_radius` 腐蚀成孤岛、求路返回空——实测过，更糟。楼顶是平的，不受影响。
3. **三个楼顶还没上楼路径**，所以只有「可站、可放 NPC」的意义，玩家暂时上不去。这一点和用户「只让豆豆在楼上」的选择一致。
4. **豆豆的天台站台没删。** `rooftop_npc_stations.tscn` 里她的 5 个 Marker 仍在场景里（用户没要求删），只是日程不再指向。`npc-integration` 的断言已从「场景里没有她的 Marker」改成「日程不在天台」。

## 6. 连带更新的测试断言（不是掩盖）

| 文件 | 原断言 | 现在 |
|---|---|---|
| `test_npc_integration.gd` | 35 锚点（天台 30 + 浮店 5） | 40（另加花园 5） |
| 同上 | 七人 `home_labels` 7 | 8（天台 6 + 浮店 1 + 花园 1） |
| 同上 | `owners` 断言六人在天台 | 豆豆改判「日程不在天台」 |
| 同上 | `homes == 7`、`interactions == 7` | 6（豆豆在外） |
| 同上 | `npc_site_position` / `npc_supported` 只分天台/浮店 | 加花园分支 |
| `test_npc_save.gd` | 新进程断言 `zone_id` 二选一 | 三选一（加 `neon_garden_quarter`） |
| `test_npc_conversation.gd` | 七人都走「走近交谈」 | 豆豆改判「楼顶可见」 |
| `test_npc_world.gd` | 七人日程不得回退 | 豆豆在仅含旧住所港的夹具里允许回退（夹具边界，已写明） |

## 7. 门禁

- `check_architecture.py` → PASS，25 独立服务 0 issues。
- `check_placed_positions.py` → PASS，3 结构 0 警告。`main.tscn` 本次无 diff，用户手摆 transform 未动；新增的 `NpcStations` 是霓虹花园的子节点，不改变该 root 的台账数值。
- `check_feature_contracts.py` → **109 issues**（上一轮 53）。增加部分是本次真实改动的 runtime hash 漂移：`neon_garden_quarter.tscn`、`main.gd`、`npc_world_presenter.gd`、`npc_world_ports.gd`、`npcs.json`、`resident_harbor` 相关等，以及新增文件尚未登记。按既有口径不批量重签、不冒签；`--sync` 在有 issues 时不写派生索引。
- `git diff --check`：本次新增/修改文件无问题（输出里那条 `2026-11-08_home_seabed_and_dive_reopen.md` 是并行会话的文件）。

## 8. 未执行

低端设备、发行包、手柄/触屏、长期 FPS、完整菜园游玩体验（玩家上楼种菜）均未执行。豆豆在楼上的动作是日程锚点落位，不是新的种植 AI 状态机——她到点站在菜园桥、按既有 `set_action` 播动画，没有新增「播种/浇水/收获」的行为树。这一点与本轮「NPC 的 AI 行为」的字面要求有差距，记录在此。

## 12. 当晚修订：气泡放大、触发半径放宽（用户反馈）

用户看完首版渲染图的原话是「对话框要大一点，[不然]得这么近才能看到」。首版字号 21、文本宽上限 292、触发半径 16 米——在 1280×800 的窗口里，那相当于右上角一行小字，玩家必须把船贴到楼底下才会触发，而就算触发了也未必看得清。两处一起改：

| 项 | 首版 | 现在 | 理由 |
|---|---:|---:|---|
| 字号 | 21 | **30** | 1280 宽下相当于 22 号，船在主航道也读得清 |
| 内边距 | 18×12 | **28×20** | 字大了留白也要跟上，否则拥挤 |
| 圆角 | 22 | **30** | 与放大的纸面比例一致 |
| 文本宽上限 | 292 | **468**，且不超过视口宽 **42%** | 固定 468 在 1280 窗口占四成，再宽顶到屏幕两边 |
| 尾巴 | 24×13 | **34×20** | 跟着纸面比例 |
| 阴影 | size 10 / offset 3 | **14 / 4** | 纸面抬高后原来的影子太薄，浮不起来 |
| 触发半径（水平 XZ） | 16 m | **32 m** | 主航道正常经过就触发，不用特意靠近 |
| 停留 | 4.5 s | **7.5 s** | 从远处看到再读完一句，4.5 秒会被淡出打断 |

顺带修了一个只有放大后才暴露的问题：**触发半径放到 32 米后，豆豆经常在镜头外**。原来的实现会把气泡夹到屏幕边缘硬画出来——那就是一张指向画外的纸条，看起来像 UI 出错。现在 `_track()` 判断角色屏幕坐标是否越界（含相机背后，留 48 像素余量），越界只把 `_on_screen` 置 false 并隐藏，**不结束这次招呼、计时继续走**，镜头转回来气泡立刻恢复。

这也让 `is_speaking()` 的语义从「可见」改成「还在这次招呼里」（`_target` 有效且 `_alpha > 0`）——否则角色一出画就会被上层逻辑当成「已经说完」，镜头回来也不会再有。

### 连带修改的测试

`test_garden_npc.gd` 的「靠近后气泡显示台词」原来不摆相机，靠「反正一直可见」通过。放大后这条变成了假绿/假红的分水岭：

- 改成按玩家真实视角抬头——把相机 `target` 指向豆豆、`distance` 24 米，再触发，断言「抬头看向楼顶时气泡显示台词」。这是玩家真实的操作路径。
- 新增「气泡按远读尺寸排版」`524×122`（旧尺寸约 300×60，直接量出来的差别）。
- 新增「角色出画时气泡收起，不在屏边挂纸条」与「再回到画面里气泡恢复」。第一条第一版写错了：我只把相机 `dir` 转 180°，但相机是绕 `target` 转的、`target` 就是她本人，转完还在画面正中、断言必红。改成把 `target` 平移到 46 米外才真正出画。这个坑记在此处，后续别再犯。

`capture_garden_bubble.gd` 加了两个镜头：`far`（相机距离 30 米，验「远处能不能读」）与 `small`（1280×800 窗口 + 长句，验不越界、宽度不超过屏宽六成）。21/0。

### 验收

| 入口 | 结果 | 报告 |
|---|---|---|
| `garden-npc` | 17 / 0 | `20261108-180314-ng-garden-big3-c50e2` |
| `visual-garden-bubble` | 21 / 0（4 张 PNG） | `20261108-180526-ng-bubble-big4-6204c2` |
| `minimum-loop` | 112 / 0 | `20261108-180600-ng-min-big-a92dc7` |

`far` 那张逐图看过：30 米外 30 号字清楚可读，三角尾巴仍指着头顶，气泡没有压住角色。`small` 那张：1280×800 长句换三行，宽度约屏宽四成五，不越界。

只改了 `speech_bubble.gd`、`main.gd` 的两个常量、测试与截图工具；`main.tscn` 仍无 diff，用户手摆 transform 未动。
