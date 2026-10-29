# 种植区自由摆位修正（SEA-BUILDING-R04）

日期：2026-10-29
关联：SEA-BUILDING-R04 / SEA-BUILDING-R05 / SEA-BUILDING-R07

## 现象

玩家在新拼接的木板上进入建造 → 选择"培养土种植区"，光标压在木板上时虚影常红，提示"种植区需要完整放在木板内"，几乎无法完成施工。截图里红框只是压在板的边缘与凹口上，板面本身是够的。

## 根因

旧判定把**单块木板**当作边界，并要求种植区完整落进该板内缩 0.12 米的矩形：

```gdscript
Catalog.tile_rect(support.x,support.z).grow(-0.12).encloses(Catalog.plot_rect(request))
```

代入尺寸（板 2.15×2.575，种植区 1.794×1.575）：

- x 方向容差 = (2.15 − 0.24 − 1.794) / 2 = **±0.058 米**
- z 方向容差 = (2.575 − 0.24 − 1.575) / 2 = ±0.38 米

而摆位吸附是 `snappedf(local, 0.1)`，步长 0.1 米**大于** x 容差的整个有效宽度 0.116 米。也就是说光标在 x 上只有落到板中心附近唯一一个 0.1 格点才合法，视觉上约两三个像素。这不是"不容易"，而是事实上建不出来。

同时还有两条叠加限制：

1. `for item in _rows: if item.kind=="planter" and item.support==support.id` —— 一块板只允许一格，跨接缝摆放根本不可能。
2. `walk_rects` 只从 planter 的 `support` 板挖洞；一旦允许跨板，另一块板不会让出 footprint，玩家会站在种植格中间。

测试长期为绿，是因为 `test_building.gd` 与 `test_building_visual.gd` 都把点击目标放在板的**几何中心** `(4.3, -1.2875)`，恰好落在唯一合法的 0.1 格点上。测试验证了"中心能放"，没有验证"自由能放"。

## 改法

边界从"单块板"改成"整片已完工木面"：

- `Catalog.deck_tiles(rows)`：汇总所有已完工 deck 的 footprint。
- `Catalog.covered(rect, tiles)`：按所有木板 x 边界切竖条，逐条合并 y 覆盖区间后判断是否完全覆盖。接缝被两块板共同覆盖，缺口不会被误判。
- `Catalog.PLANTER_MARGIN = 0.04`：仍要求离开木面外缘，但不要求塞进单块板。
- `service.geometry_reason`：`covered(plot_rect.grow(0.04), deck_tiles)` + 「与其他种植区 footprint 不重叠（留 2 厘米）」；删除"这块木板已经有种植区"。
- `support` 保留为**主支撑板**，仍要求存在、是已完工 deck、且与本格相交；存档结构与旧档兼容，判定放宽不会让旧档失效。
- `world.walk_rects`：每块 deck 减去**每一个**种植区 footprint（通用矩形差集 `_subtract`），不再只认 `support`。
- `world.approach_points`：四个接近点若被挤出木面，拉回最近的可行走条带，避免贴边建造后点不到。
- `service.snap_planter`：光标压在板边导致越界不足 0.4 米时，按 0.1 米网格在 ±0.4 米内搜最近的合法格点并吸过去。重叠、压到角色不吸，照常报错，所以不会把问题藏起来。

新容差（单块板）：

- x = (2.15 − 0.08 − 1.794) / 2 = **±0.138 米**
- z = (2.575 − 0.08 − 1.575) / 2 = ±0.46 米

x 容差已大于吸附步长，板中心附近至少两个格点可用；跨板摆放时容差随并集扩大。一块板仍放不下两格（1.575×2 > 2.575），所以视觉结果没有变成"板上一排格子"，只是不再卡在板中心。

## 验证

全部走 `scripts/run_verification.py`，隔离用户数据：

| 套件 | 结果 |
|---|---|
| building | 29 checks, 0 failures（新增 9 项：接缝覆盖、半边越界、缺口越界、第三块板、偏离中心可建、重叠仍拒、贴边越界、贴边吸回、远处仍拒） |
| building-integration | 38 checks, 0 failures |
| building-restart / building-seed | 8 / 5 checks, 0 failures |
| visual-building | 21 checks, 0 failures（新增"偏离中心预览合法"与"压边自动吸回"，真实渲染＋鼠标点击） |

证据目录：`D:/projects/sea-work/verification/20261029-114803-verification-e7ded5` 等。

首轮 `visual-building` 出现 `rotate key`／`mouse places planter` 失败，日志无脚本错误与资源错误；紧接着连跑两轮（含加诊断打印的一轮）均 PASS，诊断打印显示 `active=true / recipe=planter / turn` 递进正常。判为冷启动时序抖动，仍保留该失败记录，不作为回归结论。

`surface` 当前为红（28 项航路失败，zone5↔zone3/zone4 等）。已用 `git checkout` 还原本次四个建造源文件后重跑，失败依旧且失败集合不同，确认是既有红项、与本次改动无关，未在本轮处理。

## 没有改的部分

- 木板拼接仍限原六格周围两圈网格，不支持角点连接与海上独立基地（R02 不变）。
- 种植区尺寸、成本、工期不变；Farm 的播种/浇水/生长/收获链路未触碰。
- `web/` 原型里的"建造"是旧版设施升级，不是浮板拼接，无需同步。
