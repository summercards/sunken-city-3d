# 2026-10-30 海上地图：你在哪、太阳房在哪

承接 SEA-UI-R46。用户指出航海图上「圆环是你的位置」但读不出**我在哪、太阳房在哪**。

## 问题

`island_atlas.gd` 原来只做两件事：画区块奶油地块，给 `game_state.current_zone` 画一圈橙环。

- 橙环套的是**区块中心**，不是角色位置。船停在家园与浅水台之间的海面时，环仍贴在家园中心——那是虚假的「你现在在这里」。
- 太阳房与别处的画法完全一样（一块奶油、一颗青绿点、一行小字），没有「这是家」的视觉重量。
- 底部说明写「圆环是你的位置」，玩家却在图上找不到第二个可对照的锚点。

## 改法

**数据来源改成真实世界坐标。** `Main._setup_hud` 注入 `hud.player_query`：

```gdscript
hud.player_query = func() -> Dictionary:
    if player == null: return {}
    return {"zone":GameState.current_zone,"position":player.global_position}
```

`island_atlas._you_spot()` 取 `position.x / position.z`，走同一个 `project()`。UI 层不沿父节点找 Main、不读角色脚本内部字段，和 R18 一致。查询为空（无角色、未进世界）时才退回当前区块中心——**必须仍画出标记**，不能因为没取到就留白。

**太阳房变成认得出来的徽标。** `HOME_ZONE = "zone1"`，画金色三角檐 + 奶油墙体 + 描边门洞，牌底给 58×44 起步（别处 38×22），金色描边，名字固定写「太阳房 · 家园」。`zone1` 永远解锁，所以这个徽标不参与「未解锁灰块」分支。

**两个标记不打架。** 停泊判定 `_berth_of()` 用 30 px 邻域：
- 在泊位上 → 橙点挂该徽标**外侧左上角**（不压房门、不压名字），该徽标边框转橙，不再写「你在这里」；
- 在海上 → 橙点画在真实投影处，上方给一枚奶油小胶囊写「你在这里」，胶囊位置夹在纸内。

**地图开着时船在动。** `_process` 每 0.25 s `queue_redraw()` 一次（仅当 `player_query` 有效且可见），不靠打开那一刻的快照。

## 踩到的两个坑

1. `_extent(rect)` 改成 `_extent(id, rect)` 后，`_draw_you()` 里仍在调旧签名，Godot 直接 `Parse Error: Identifier "id" not declared`，测试进程挂到超时（exit 124），日志里才看得到。**改签名必须同时改所有调用点**，GDScript 不会在静态检查阶段全量提示。
2. 徽标放大后，橙点一开始放在中心，正好压在房子的门和「太阳房 · 家园」上；改到右下角又撞名字。最终放**外侧左上**——牌子的边框之外，任何缩放下都不重叠。

## 证据

| 检查 | 结果 |
|---|---|
| `island-atlas`（`tests/test_island_atlas.gd`） | 10 项 0 失败，退出 0 |
| `visual-island-atlas`（`tools/capture_island_atlas.gd`） | 家园 / 浅水养殖台 / 两块之间的海面三张原生渲染，退出 0 |

改动文件：`godot/src/ui/island_atlas.gd`、`godot/src/ui/hud.gd`（`player_query` 字段与说明文案）、`godot/src/bootstrap/main.gd`（`_setup_hud` 注入）、`scripts/run_verification.py`（两项注册）、新增 `godot/tests/test_island_atlas.gd` 与 `godot/tools/capture_island_atlas.gd`。

未改：航行、泊位、存档字段、区块数据、解锁规则；地图仍是只读描绘。
