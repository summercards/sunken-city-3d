# 水下基座不再派生水面阻挡

日期：2026-10-29 · 功能：SEA-WORLD（R05）· 关联：SEA-NAV（R10）

## 现象

从 zone5「浅水养殖台」泊位往西/北走不过去。看着是一片开阔水面，点上去船不动或绕远路。

## 根因

`太阳能木屋-海下基座`（`bloom_lower_building`，缩放 1.45 × 1.43）里有一块顶板
`roof_slab_11`，尺寸 16.24 × 17.77 m，**顶面 y = 1.16**，水面 **y = 1.12** —— 只高出 4 cm。

`blocker_set.gd` 的 `_crosses_band()` 对水平薄面的判据是 `y_min >= water_y - 0.05`，
也就是只要不低于水面 5 cm 就算阻挡。于是这块贴水顶板派生出一块
**16.4 × 17.6 m** 的水面阻挡（世界 x −2.0…14.4，z −4.8…12.8），
把 zone1 与 zone5 之间唯一的 **2.6 m** 水道整条封死。

木屋实体只占 x 0…8.6 / z −3.4…2.6，这块阻挡约 90% 是空的。玩家在画面上看不到任何东西。

## 量化

船在 zone5 泊位 (16.77, 15.92)，目标正北 10 m：

| 指标 | 修复前 | 修复后 |
|---|---|---|
| 航路点数 | 8 | 3 |
| 航路长度 | 42.7 m | 11.2 m |
| 绕行比 | 4.00 | 1.12 |
| z=13.0 走廊宽度 | 0 个通行格（封死） | 0.75 m（网格格心） |
| z=14.0 走廊宽度 | 0 个通行格 | 5.25 m |
| 实跑结果 | — | 4.4 s 到达，误差 0.01 m，0 次 blocked 事件 |

## 修复

改数据声明，不改派生算法。`blocker_set.gd` 已经提供 `mode = "none"`（组件自己声明
「不参与水面阻挡」），这正是该机制的用途。

1. `godot/scenes/facilities/solar_cabin_submerged_base.tscn`
   新增 `Blockers` 节点，`mode = "none"`、`blocks_water = false`。
   沉在水下的基座整体不参派水面阻挡。

2. `godot/scenes/facilities/solar_cabin.tscn`
   在木屋根节点新增 `Blockers`，`mode = "auto"`、
   `target_path = NodePath("../太阳能木屋-海上区域")`。
   水面阻挡只从露在水面以上的「海上区域」派生 —— 支撑柱、平台照常挡住船，
   水下基座不再混进来。

`target_path` 是相对 BlockerSet 自身的路径，必须写 `../`。

## 为什么不是改判据门槛（已试过并回滚）

最初的方案是把水平薄面门槛提到 `water_y + 0.10`。实测会反向误删 zone5 自己的
浮台底板（`Models/unit_01`，顶面只比水面高约 4 cm，但它就是船该被挡住的甲板基座），
`visual-blockers` 立刻报 zone5 漏阻挡 35%。

根因不是门槛数值，而是**「顶面略高于水」这一几何特征本身无法区分「沉没建筑」和
「浮台底板」**。这个判断只有组件自己知道，所以必须由组件声明，不能由通用阈值猜。

同时记录一个夹缝陷阱：判据门槛若与 `tools/verify_blockers.gd` 的 `WATER + 0.15`
不一致（当时用了 0.10），会在中间夹出一条谁都不认的带，表现为验收工具报漏阻挡、
而游戏里又确实走得过去。

## 验证

`python3 scripts/run_verification.py visual-blockers boat-water-contact ocean --label cabin-base-none`

```
OK   zone1 rects=30 空=0 漏=2.4%
OK   zone2 rects=58 空=0 漏=3.9%
OK   zone3 rects=40 空=0 漏=1.2%
OK   zone4 rects=16 空=0 漏=12.9%
OK   zone5 rects=3  空=0 漏=0.0%
[blockers-check] OK failures=0 rects=147
boat-water-contact PASS
ocean PASS
```

zone1 漏阻挡由 5.0% 降到 2.4%（删掉的是那块无支撑的巨型阻挡，剩下的 2.4% 是轮廓锯齿）。
zone5 由 39.2% 降到 0.0%。

真实渲染取证：把每条水面阻挡画成半透明红板抬到水面上 0.22 m 截图，
修复后船周围 26 × 26 m 范围内 16 块红板全部落回实体建筑上，水道内无红板；
船从泊位往北实跑 4.4 s 到位，`navigation_blocked` 触发 0 次。

## 已知但未处理的既有问题

`solar-components`（703 checks，4 failures）与 `click`（32 checks，3 failures）在
**修复前基线**上就有同样数量的失败（已用 `git checkout` 回滚对照确认），与本改动无关：

- `solar-components`：four independent semantic modules / 49 active source components /
  right lounge retained: cooler / expanded runtime triangles match optimized export
- `click`：新航线取消旧拾取 / 航行途中改道 / 建造菜单前往并自动交付

## 附带发现

zone5 的 `Models/detail`（水下基座，顶面 1.36 m）原本派生 **0 条**阻挡。
这是同一套规则在另一个方向的表现，未被 `verify_blockers` 抓到（它按跨水实体算支撑率）。
本次未改动，留待区块重做时一并处理。
