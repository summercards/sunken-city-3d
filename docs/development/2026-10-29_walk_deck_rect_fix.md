# 码头栈桥两处可走进水里：行走矩形越过甲板

日期：2026-10-29 · 功能：SEA-MOVE（R01）· 关联：SEA-WORLD

## 现象

主人截图圈出木屋码头栈桥的左右两条边：站在那儿能继续往海里走，人物浮在水面上。
画面上看不出任何"能走"的提示 —— 没有栏杆、没有高亮，只是点过去就去了。

## 根因

本工程的走路**不走物理碰撞**：场景里没有 `StaticBody3D` / `CollisionShape3D`，
角色站得住是因为 `WalkArea.surface_y` 把脚直接贴到那个高度（`walk_area.gd`）。
"哪里能走"完全由 `Walk_zone1_home_dock.rects` 这一份矩形决定。

第三块矩形是 `Rect2(0, 11.5, 6.5, 6.5)`，即 x `0.0…6.5`、z `11.5…18.0`。
实测栈桥甲板只有 x `0.60…5.85`、z `12.90…17.90`：

| 边 | 矩形 | 实测甲板 | 越界 |
|---|---|---|---|
| 左缘 | x = 0.00 | x = 0.60 | 0.60 m |
| 右缘 | x = 6.50 | x = 5.85 | 0.65 m |
| 末端 | z = 18.00 | z = 17.90 | 0.10 m |

左右各多出约 0.6 m 的行走带，正好盖在栈桥两侧的缆桩与海面上 —— 就是主人圈的两处。

这不是"碰撞漏了"，而是**可行走矩形从来没按甲板实测过**。矩形是 2026-10-26
整理阻挡时按"大概范围"写的，当时只量了主甲板，栈桥末端沿用了旧值。

## 量化

探针 `godot/tools/probe_deck_edges.gd` 给区块可见网格临时建三角碰撞（只在本进程内存里），
在每块矩形内按 0.25 m 栅格、每格抖 3×3 点取多数（抗木板缝造成的假空洞），
统计"脚下确有 surface_y 附近朝上实心面"的比例：

| 指标 | 修复前 | 修复后 |
|---|---|---|
| `zone1_home_dock` 甲板覆盖率 | 0.903 | 0.943 |
| 无甲板格子数 | 152 / 1568 | 83 / 1468 |
| 栈桥段（原第三块矩形）无甲板格子 | 约 60 | 0（该段并入新矩形后仅剩 2 格木板缝） |
| 越界行走带面积 | 约 8.3 m²（左右各 0.6 m × 6.5 m） | 0 |

## 修复

改数据，不改算法 —— `walk_area.gd` 的矩形语义本来就是"可行走区域就是场景数据"。

`godot/scenes/zones/zone1_home_harbor.tscn` 的 `Walk_zone1_home_dock.rects`：

```
- Rect2(0, 11.5, 6.5, 6.5)
+ Rect2(0, 11.5, 6.5, 1.4)      # 主甲板南沿到栈桥根部，保留全宽
+ Rect2(0.6, 12.9, 5.25, 5.0)   # 栈桥本体，按实测甲板 x 0.60…5.85 / z 12.90…17.90
```

拆成两块而不是直接收窄：主甲板在 z `11.5…12.9` 这段本来就是全宽（`#` 覆盖满），
栈桥才收窄。一块矩形做不到"先宽后窄"，硬收会把主甲板边缘也切掉。

`godot/assets/data/zones.json` 的 `zone1.walk[zone1_home_dock].rects` 同步更新。
注意两份的坐标写法不同：TSCN 是 `Rect2(x, z, w, h)`，JSON 是 `[x0, x1, z0, z1]`
（`zones.gd: bind_scene()` 的写法）。运行时会用场景覆盖 JSON，JSON 只是无场景测试的基线，
但两份不一致会让测试与实机分叉，所以必须一起改。

## 会失败的断言

这类错误不报错、不崩、不进日志 —— 人物只是站在水面上。没有断言盯着，几个月后重做甲板
必然重犯。所以加了两条：

1. `godot/tests/test_walk_deck_fit.gd`（`walk-deck-fit`，不需要真实渲染）
   把主人圈的两处越界点钉死为"不可走"，同时断言栈桥自身、接缝、泊位站立点、
   出货箱位置仍然可走 —— 防止"为了堵缺口把整条栈桥切掉"这种反向错误。
2. `godot/tools/verify_walk_deck.gd`（`visual-walk-deck`，必须真实渲染）
   五个区块全部 WalkArea 的甲板覆盖率不得低于实测基线。覆盖率上升放行，下降失败。

两条都接进 `scripts/run_verification.py`。

## 验证

```
python scripts/run_verification.py walk-deck-fit visual-walk-deck --label walk-deck-final
```

```
walk-deck-fit PASS exit=0
visual-walk-deck PASS exit=0
```

`visual-walk-deck` 明细（真实渲染，0.25 m 栅格 + 3×3 抖动）：

```
OK   zone1/zone1_home_dock cover=0.943 base=0.940 cells=1468 wet=83
OK   zone1/zone1_salvage   cover=0.895 base=0.890 cells=390  wet=41
OK   zone2/zone2_station   cover=0.697 base=0.690 cells=920  wet=279
OK   zone3/zone3_ground    cover=0.391 base=0.390 cells=1992 wet=1213
OK   zone4/zone4_shore     cover=0.685 base=0.680 cells=273  wet=86
OK   zone5/zone5_aqua      cover=0.909 base=0.900 cells=572  wet=52
[walk-deck] 6 checks, 0 failures
```

回归验证：把 `zone1_home_harbor.tscn` 回滚到旧矩形后，
`walk-deck-fit` 报 3 failures、`visual-walk-deck` 报 1 failure，确认断言真的会失败。

真实渲染取证（把 WalkArea 矩形画成甲板上 6 cm 的红框，俯视 + 侧视）：
`docs/development/evidence/2026-10-29_walk_deck/jetty_walkrect_top.png`、
`jetty_walkrect_side.png`。红框左右两侧已贴回甲板边缘，不再落到水上。

实跑取证（`godot/tools/probe_jetty_walk.gd`）：从栈桥中点分别点向左右两侧边缘外侧 0.5 m，
角色被 `clamp_point()` 夹回甲板内并停在木板上，而不是走出水面：

```
[probe] left  want=(0.10, 1.38, 14.5) clamped=(0.60, 14.5) inside=false → final=(0.60, 14.5) on_deck=true
[probe] right want=(6.40, 1.38, 14.5) clamped=(5.85, 14.5) inside=false → final=(5.85, 14.5) on_deck=true
```

截图：`evidence/2026-10-29_walk_deck/jetty_walk_stops_on_deck.png`。

其它专项：`walk-facing` / `board-click` / `dock-seed` 通过；`click` 3 项、
`surface` 1 项（`种植物件是独立场景 home_plot`）为改动前既有失败 —— 用 `git stash`
回滚两份数据文件后复跑，同样数量失败，与本改动无关。

## 已知残留（未纳入本次范围）

- `zone1_home_dock` 剩余 83 格无甲板，集中在 rect1 北侧 `z 5.0…6.0 / x 0.4…1.4`
  一块结构缝。那儿踩下去是踩在结构缝里而不是水里，观感上不明显，但严格说也越界了。
  要收就得把 rect1 北沿按实测再切一刀，属于甲板重做时的活。
- `zone2`（0.697）、`zone3`（0.391）、`zone4`（0.685）覆盖率仍然偏低，是
  `2026-10-26_sea_scene_blockers.md` §4 已记录的既有残留：旧手工矩形与废墟拼接接缝。
  本次只登记基线，不放宽、不掩盖。
- `zone5` 的 52 格集中在 `x -3.2…0 / z -2.8…-2.5` 一带，同一性质。

## 相关文件

- 修改：`godot/scenes/zones/zone1_home_harbor.tscn`、`godot/assets/data/zones.json`、
  `scripts/run_verification.py`
- 新增：`godot/tests/test_walk_deck_fit.gd`、`godot/tools/verify_walk_deck.gd`、
  `godot/tools/probe_deck_edges.gd`、`godot/tools/capture_walk_edge.gd`、
  `godot/tools/probe_jetty_walk.gd`
