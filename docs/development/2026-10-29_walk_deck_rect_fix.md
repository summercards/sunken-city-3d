# 码头栈桥两处可走进水里：行走矩形 + 身影半径

日期：2026-10-29 · 功能：SEA-MOVE（R01）· 关联：SEA-WORLD

## 现象

主人截图圈出木屋码头栈桥的左右两条边：站在那儿能继续往海里走，人物浮在水面上。
画面上看不出任何"能走"的提示 —— 没有栏杆、没有高亮，只是点过去就去了。

第一轮按实测甲板收窄了矩形之后，主人复查仍然能"穿进去"：人物中心已经踩在甲板内，
但**帽檐和肩膀压在水面上**，看上去还是人站在水里。

## 根因（三层）

### 第一层：行走矩形从来没按甲板实测过

本工程的走路**不走物理碰撞**：场景里没有 `StaticBody3D` / `CollisionShape3D`，
角色站得住是因为 `WalkArea.surface_y` 把脚直接贴到那个高度（`walk_area.gd`）。
"哪里能走"完全由 `Walk_zone1_home_dock.rects` 这一份矩形决定。

第三块矩形是 `Rect2(0, 11.5, 6.5, 6.5)`，即 x `0.0…6.5`、z `11.5…18.0`。
用球检测实测栈桥甲板只有 x `0.60…5.80`、z `12.90…17.90`：

| 边 | 原矩形 | 实测甲板 | 越界 |
|---|---|---|---|
| 左缘 | x = 0.00 | x = 0.60 | 0.60 m |
| 右缘 | x = 6.50 | x = 5.80 | 0.70 m |
| 末端 | z = 18.00 | z = 17.90 | 0.10 m |

左右各多出约 0.6 m 的行走带，正好盖在栈桥两侧的缆桩与海面上。

矩形是 2026-10-26 整理阻挡时按"大概范围"写的，当时只量了主甲板。

### 第二层：把圆心夹到甲板边，人还伸出去半米

矩形改准之后仍然"穿"，因为判据本身是错的：

`clamp_point()` 只保证**角色中心点**在甲板内。可角色不是一根杆子 ——
斜俯视看到的是整只人，站直时最宽处是渔夫帽檐（`CylinderMesh` radius **0.34**）
和手臂外缘。中心点贴着甲板边，帽檐就必然悬在水面上。

这就是"修了矩形却还是进水"的原因：改的是**点**，漏的是**身影**。

### 第三层：主人跑的是旧导出包（这才是"并没有改变"的原因）

前两层修完，主人复查仍然"穿进去"。查下来不是代码没生效，而是**包没重导**：

| 产物 | 修复前时间戳 | 内容 |
|---|---|---|
| `godot/build/windows/sea.exe` + `sea.pck` | 10:32 | 旧矩形 `[0, 6.5, 11.5, 18]` |
| `godot/build/web/index.*` | 10:32 | 同上 |

修复发生在 16:00 之后，两个包都是当天上午导的。`.gitignore` 里
`/godot/build/` 被忽略，所以这份"发行产物"从来不进版本库、也没人因为改数据而重导 ——
它静静躺在那里，谁双击 `sea.exe` 谁就回到七小时前的行为。

已重新导出（windows 17:44 / web 17:46），并从 PCK 二进制里直接取出 walk 数据确认：

```
zone1_home_dock ... "rects": [
  [-1, 4.5, 5, 11.5],
  [4.5, 9.5, 7.5, 11.5],
  [0.35, 5.55, 11.5, 12.9],
  [0.6, 5.8, 12.9, 17.9]
]
```

**教训**：改数据不等于改行为。这个工程有"源码 + 导出包"两份状态，
导出包不跟源码同源校验，就会出现"改完还是老样子"。

后续要防的话，可以在 `run_verification.py` 里加一条「导出包 mtime 必须晚于
`godot/scenes/zones/*.tscn` 与 `godot/assets/data/*.json`」的检查 —— 目前只记录，
未接入（导出一次 1 分 16 秒，不适合每次都跑）。

### 顺带修掉：导出包里 interactable.gd 根本编译不了

重导后先跑了一遍新包，报：

```
SCRIPT ERROR: Parse Error: Identifier "EditorInterface" not declared in the current scope.
   at: GDScript::reload (res://src/interaction/interactable.gd:185)
SCRIPT ERROR: Parse Error: Could not resolve class "Interactable".
   at: gather_spot.gd:2  →  gather_field.gd 一并失败
```

`EditorInterface` 只存在于编辑器构建，导出模板里没有这个符号。静态写
`EditorInterface.get_selection()` 会让整个脚本在导出包解析阶段就失败，
连带把采集链（`gather_spot.gd` → `gather_field.gd`）拖垮。

这不是本次改动引入的（`2c50f51` 引入，`995db38` 与 10:32 的旧包里都有），
但既然"包必须能跑"是这次修复成立的前提，就一起修了：
改成 `Engine.has_singleton("EditorInterface")` + `Engine.get_singleton()` 运行时取，
取不到就当"没选中"。

修完 `sea.exe --headless` 不再有 Parse Error。

### 第四层（真正的病根）：可行走矩形画在栏杆绳外面

主人明确"穿进去"指的是**穿过栈桥两侧的栏杆绳**之后，量一下绳子在哪就清楚了。

`bridge_rope` 是带名字的组件实例，实测世界包围盒：

| 绳 | x 范围 | 高出甲板 |
|---|---|---|
| 西侧长绳 | 0.833 … 0.936 | 0.48 ~ 1.06 m |
| 东侧长绳 | 5.197 … 5.300 | 0.48 ~ 1.06 m |
| 根部端头（两段） | 0.517 … 5.617 | 同上 |
| 末端端头（两段） | 0.517 … 5.617 | 同上 |

绳围出来的内部空间是 x `0.936…5.197` × z `11.853…17.172`。

而我前两轮按"甲板边"写的矩形是 x **0.6…5.8**：

- 左沿 0.60 < 西绳内沿 0.936 → 人站在**绳外** 0.336 m
- 右沿 5.80 > 东绳内沿 5.197 → 人站在**绳外** 0.603 m

所以人不是"穿过"绳子，而是**一开始就站在绳子外面走** —— 绳子在甲板内侧，
人走在甲板外沿，视觉上就是绳子从身体里穿过去。

这也解释了为什么我前两轮的修复"看起来都对但没用"：
我把判据从「甲板边」改成了「甲板边 + 身影半径」，
可边界本身选错了 —— 该用绳内沿，我用了甲板外沿。

### 修复：矩形以绳内沿为界

```
- Rect2(0.35, 11.5, 5.2, 1.4)   # 按甲板边
- Rect2(0.6, 12.9, 5.2, 5.0)
+ Rect2(1.28, 11.5, 3.6, 0.42)  # 根部：端头两段短绳之间
+ Rect2(0.936, 11.92, 4.261, 5.23)  # 长绳区内空
```

根部 z 11.5…11.92 只有中间能走（端头短绳落在 x 0.517…1.253 与 4.881…5.617），
所以那块单独收窄成 x 1.28…4.88，而不是整段都收窄。

### 会失败的断言：`rope-bounds`

`godot/tests/test_rope_bounds.gd` —— 关键是**从模型几何现场量绳位**，不写死坐标：

1. 找出所有 `bridge_rope` 实例的世界 AABB（headless 下必须读
   `instance_transforms` meta，`MultiMesh.get_instance_transform()` 一律返回单位矩阵）；
2. 取两道长绳的内沿作为左右边界，取绳的 z 跨度作为前后边界；
3. 断言「栈桥段每块矩形的四条边都不越出绳内沿」；
4. 行为断言：点绳外 0.6 m，站位必须被夹回绳内。

把矩形回滚成旧值，这条断言报 5 项失败，其中一条正是主人的现象：

```
FAIL 点东绳外 (5.80,14.51) → 站位 x=5.400 仍在东绳内沿 5.197 以内
```

站位 5.400 意味着人整个在东绳（5.197）外面 —— 精确复现"人穿过栏杆"。

## 「能不能走」到底靠什么判断（回答主人的架构疑问）

实测结论：**整个运行时一个碰撞体都没有**。

探针 `godot/tools/probe_world_colliders.gd`：

```
[colliders] PhysicsBody3D 总数: 0
[colliders] player 是 PhysicsBody3D: false  子节点类型: Node3D,Node3D
[colliders] 竖直射线 x=1.00 z=14.20 → 无任何碰撞体
[colliders] 竖直射线 x=3.00 z=14.20 → 无任何碰撞体
[colliders] 竖直射线 x=6.60 z=14.20 → 无任何碰撞体
```

也就是说：栈桥上从上往下打射线，既没有地板也没有墙。人站在那儿，
不是因为脚下有碰撞面，而是 `WalkArea.surface_y = 1.38` 把他的 y 直接写死。

工程里确实有"阻挡"系统，但它**只服务船**：

| 对象 | 判定依据 | 数据从哪来 |
|---|---|---|
| **船** | `water_block_rects` / `BlockerSet` | 运行时从组件可见几何派生（0.4 m 栅格） |
| **人** | `WalkArea.rects` | 场景 TSCN 里手写的矩形 |

所以「模型长什么样」跟「人能不能走」**毫无关系**。栈桥换成更窄的板、
加一圈栏杆、把甲板削掉一块 —— 只要 `rects` 不改，人照样按旧矩形走。
反过来也一样：这次矩形改准了，模型一个像素都没动。

这也是为什么这类 bug 反复出现：三份数据（模型、矩形、水面阻挡）互不约束，
改一份不会提醒另外两份。

## 修复

### 1. 行走矩形按实测甲板拆成两块（`zone1_home_harbor.tscn`）

```
- Rect2(0, 11.5, 6.5, 6.5)
+ Rect2(0.35, 11.5, 5.2, 1.4)   # 主甲板南沿到栈桥根部，按实测 x 0.20…5.75 内缩
+ Rect2(0.6, 12.9, 5.2, 5)      # 栈桥本体，按实测 x 0.60…5.80 / z 12.90…17.90
```

一块矩形做不到"先宽后窄"（主甲板那段本来就该全宽），硬收会把主甲板边缘切掉。

`godot/assets/data/zones.json` 同步。注意两份坐标写法不同：TSCN 是
`Rect2(x, z, w, h)`，JSON 是 `[x0, x1, z0, z1]`（`zones.gd: bind_scene()`）。
运行时用场景覆盖 JSON，JSON 只是无场景测试的基线 —— 但两份分叉会让测试与实机不一致。

### 2. 站位点按身影半径内收（`walk_area.gd`）

新增 `body_radius = 0.38`、`clearance(x, z)`、`walkable_local(p)`：

- `clearance()` 量「该点到行走区并集边界的最短距离」= 能塞进多大的圆；
  用并集而不是单块矩形，接缝处不算边界。
- `walkable_local()` 判据改成「以该点为圆心、`body_radius` 为半径的圆整个落在并集内」。
  不满足就从近到远一圈圈找最近的可行点（圈在外层，保证拿到最近的那个）。
- 整片区域都容不下人影（走廊比人窄）时返回原位 —— 那是数据侧要改的事。

`clamp_point()` 改成两步：先夹进矩形并集，再按身影内收。

**`path_between()` 不做内收**：交互目标（土箱、菜箱中心）的落点语义是"走到那个点"，
终点内收会挪动落点、破坏可达性判断（实测会把 zone5 六个菜箱全判成不可达）。
内收只在「点地面走路」这条路上做。

### 3. 内收进 `zone_scene.pick_walk()`

落点内收放在 `pick_walk()` 的返回值里，而不是 `main.gd` 的 `_try_walk()`：
这样所有"点地面走路"的入口都拿到已内收的落点，不必各自实现一遍。

## 关于半径取值（踩过的坑）

先用 AABB 角点量角色轮廓，得到 **0.54 m** —— 那是斜立方体包围盒的对角线，虚高一大截：
0.54 会把栈桥两侧各收掉 0.54，5.2 m 宽的栈桥只剩 4.1 m 可用，可走区域被无故吃掉。

按实际几何取：渔夫帽檐 `radius = 0.34`（`character.gd` 第 99 行），手臂外缘略小，
取 **0.38** 留 4 cm 余量。

## 量化

探针 `godot/tools/probe_deck_cover.gd` 用半径 0.10 m 的球做覆盖检测
（单条射线会掉进木板缝，把整排判成"没有甲板"，量出来的边界会抖）。

`zone1_home_dock` 甲板覆盖率（`visual-walk-deck`，0.25 m 栅格 + 3×3 抖动）：

| 指标 | 改矩形前 | 改矩形后 |
|---|---|---|
| 甲板覆盖率 | 0.903 | 0.943 |
| 无甲板格子 | 152 / 1568 | 83 / 1468 |

站位身影净空（`walk-deck-fit`，目标值 `body_radius = 0.38`）：

| 点击位置 | 内收前站位 | 内收后站位 | 净空 |
|---|---|---|---|
| 栈桥东缘 (6.60, 14.20) | (5.80, 14.20) 净空 0.00 | (5.40, 14.20) | 0.40 |
| 栈桥西缘 (0.00, 14.20) | (0.60, 14.20) 净空 0.00 | (1.00, 14.20) | 0.40 |
| 栈桥末端 (3.00, 18.20) | (3.00, 17.90) 净空 0.00 | (3.00, 17.50) | 0.40 |

实测脚本：`godot/tools/probe_jetty_walk.gd`（`--headless` 之外需真实渲染仅用于截图，
数值部分 headless 亦可得）。


## 开销

`clamp_point()` 只在「点地面」时跑一次，不在逐帧循环里。实测（200 次平均）：

| 情形 | 耗时 |
|---|---|
| 区域内点击（无需内收） | 0.04 ms |
| 贴边点击（一轮 16 方向推到位） | 0.40 ms |
| 角落点击（直角凹口，需要兜底外扩） | 1.3 ms |

第一版从 0.05 m 起步逐圈外扩，贴边要量 7～10 圈、约 4.4 ms —— 偏重，
所以改成「按缺口 deficit 一次推到位，试不出来再逐圈兜底」。

## 会失败的断言

这类错误不报错、不崩、不进日志 —— 人物只是站在水上。没有断言盯着，重做甲板必然重犯。

1. `godot/tests/test_walk_deck_fit.gd`（`walk-deck-fit`，headless 可跑）
   - 主人圈的两处越界点必须**不可走**；
   - 栈桥自身、接缝、泊位站立点、出货箱位置必须**仍可走**（防"堵缺口把整条栈桥切掉"）；
   - 四条边缘点击的**站位身影净空 ≥ body_radius**（防"点收窄了但人影仍探出去"）。
2. `godot/tools/verify_walk_deck.gd`（`visual-walk-deck`，必须真实渲染）
   五个区块全部 WalkArea 的甲板覆盖率不得低于实测基线。上升放行，下降失败。

两条都接进 `scripts/run_verification.py`。

## 验证

```
python scripts/run_verification.py walk-deck-fit visual-walk-deck walk-facing board-click dock-seed --label final-gate
```

```
walk-deck-fit PASS exit=0
visual-walk-deck PASS exit=0
walk-facing PASS exit=0
board-click PASS exit=0
dock-seed PASS exit=0
```

`visual-walk-deck` 明细：

```
OK   zone1/zone1_home_dock cover=0.943 base=0.940 cells=1468 wet=83
OK   zone1/zone1_salvage   cover=0.895 base=0.890 cells=390  wet=41
OK   zone2/zone2_station   cover=0.697 base=0.690 cells=920  wet=279
OK   zone3/zone3_ground    cover=0.391 base=0.390 cells=1992 wet=1213
OK   zone4/zone4_shore     cover=0.685 base=0.680 cells=273  wet=86
OK   zone5/zone5_aqua      cover=0.909 base=0.900 cells=572  wet=52
```

回归对照：把场景矩形回滚到旧值，`walk-deck-fit` 报 3 failures；
把 `body_radius` 调回 0，四条身影净空断言全报失败。确认断言真的会响。

真实渲染取证（复刻主人报问题时的机位与朝向，点栈桥东缘）：
`evidence/2026-10-29_walk_deck/jetty_edge_after.png`。人物整个落在岸绳以内，
帽檐、肩膀、脚都不再压到水面。

## 已知残留

- `zone1_home_dock` 仍有 83 格无甲板，集中在 rect1 北侧 `z 5.0…6.0 / x 0.4…1.4`
  一块结构缝。那儿踩下去是踩在结构缝里而不是水里，观感上不明显，但严格说也越界。
  要收得把 rect1 北沿按实测再切一刀，属于甲板重做的活。
- `zone2`（0.697）、`zone3`（0.391）、`zone4`（0.685）覆盖率偏低，是
  `2026-10-26_sea_scene_blockers.md` §4 已记录的既有残留。本次只登记基线，不放宽也不掩盖。
- 岸绳（栈桥两侧的围栏绳）没有碰撞，人站在甲板内缘时绳子会穿过身体。
  绳子是 `solar_cabin_bridge` 组件里的装饰几何，要不要挡人属于表现与玩法口径问题，未纳入本次。

## 与既有失败的关系

`surface`（`不可达目标不退回穿岸直线` 等 8 项）、`selftest`（25 项）、`click`（3 项）
在本次改动前的工作区基线上就是同样数量 —— 用 `git stash` 回滚本次四个文件后复跑对照确认。
它们来自同一工作区里另一批未提交的航行边界 / 建造改造（`main.gd` 把
`navigation.allowed_area` 从 `Scope.SAIL_BOUNDS` 改成了 `Rect2()`），与本次栈桥修复无关。

## 相关文件

- 修改：`godot/scenes/zones/zone1_home_harbor.tscn`、`godot/assets/data/zones.json`、
  `godot/src/navigation/walk_area.gd`、`godot/src/world/zone_scene.gd`、
  `scripts/run_verification.py`
- 新增：`godot/tests/test_walk_deck_fit.gd`、`godot/tools/verify_walk_deck.gd`、
  `godot/tools/probe_deck_cover.gd`、`godot/tools/probe_deck_measure.gd`、
  `godot/tools/probe_deck_edges.gd`、`godot/tools/probe_jetty_walk.gd`、
  `godot/tools/probe_player_radius.gd`、`godot/tools/capture_walk_edge.gd`、
  `godot/tools/capture_jetty_edge.gd`
