# 海上补给站 · 浮店从景观变成可停靠的最小区块

承接 SEA-ASSET-R36 / SEA-WORLD-R14 / SEA-NAV-R12 / SEA-INTERACT-R12 / SEA-ORDER-R12。v003 矩形改造只换了造型，浮店仍是「看得见、上不去」：船被挡住、甲板没有行走面、没有泊位、没有入口。本轮把它接成真正能去的地方。

## 做了什么

**它现在是一个最小区块，但仍然住在 `World/SeaStructures` 里。** 新脚本 `godot/src/world/sea_supply_zone.gd` 继承 `zone_scene.gd`，只补两处差异：建筑几何挂在 `Visual` 而不是 `Models`；阻挡声明在根节点下而不是建筑子树里。`main._setup_scene()` 在扫完 `World/Zones` 之后，再把 `World/SeaStructures` 下带 `zone_id` 的节点并进同一张 `_zone_nodes`，重复 id 直接报错。

不另造一条靠岸通道：泊位、上岸、存读都复用现有那条链路。

- **甲板**：`Walk_sea_supply_deck`（`area_id=sea_supply_deck`，`surface_y=1.38`）由 v003 的 20×15 米名义甲板派生成前/后/左/右四条环廊矩形，环廊宽 3.0 米。**封闭主体内部不设行走矩形**——「没有店门」在玩法上就是「进不去」，不是「能穿墙」。
- **泊位**：`Landing_main`，站立点在甲板面（`z` 局部 5.2），船位在甲板外 2.35 米开阔水面（局部 9.85），靠岸边在两者之间（局部 1.9）。从家园起航可规划出 6 点折线。
- **入口**：`Objects/SupplyCounter` 锚在正面招牌下的甲板上（`focus_anchor=node`，锚点 `y=2.514`），`interact()` 只发 `opened`，由 `main._open_supply` 打开既有商店页。补给站不持有商品表、不复制价格：种子仍走 `Farm.buy_seed`，土壤仍走 `MaterialShop`，浮店不做仓库和出货箱。

## 顺带修掉的两个连带问题

- `sea_props._school_bounds()` 用 `zone.landings[0]` 取区块基准点。结构物区块一旦没绑定泊位就会越界；改成跳过空 landings 的区块。鱼群/漂流物区域因此不会被一个没有生活区的地标无声撑大。
- `landing-markers` 夹具在 2026-10-31 的 R22 规则（岸上不能隔空起板，只有乘船可在该处起独立起点）之后一直是红的：它直接调 `building.begin()` 而不带 `origin`，默认成 `shore` 被规则挡住。这轮按真实链路补 `origin:"boat"`，不放宽产品规则。修完 25 项 0 失败。

## 实测

全部经 `scripts/run_verification.py`，Autoload 前隔离用户数据。

| 检查 | 结果 |
|---|---|
| `sea-supply` | 37 项 0 失败 |
| `sea-supply-probe` | 通过；`outputs/sea-supply-probe.json` 记录登记、甲板、泊位实测值 |
| `floating-shop` | 32 项 0 失败（几何、材质序列化、水面阻挡未被改坏） |
| `visual-floating-shop` | 16 项 0 失败，新增 `on-deck`（角色站在环廊上看招牌）与 `berthed`（船停在开口外）两张实拍 |
| `island-atlas` / `landing-markers` / `character-space-save` / `ground-space` / `character-motor` / `ocean-pickups` / `wood-density` | 全部 exit 0 |

`sea-supply` 断言的完整链路是：靠妥 → 自动上岸（落在泊位站立点 0.6 米内）→ 走到招牌下（`_start_walk` 到柜台，距离 ≤2 米）→ 按 E 使 `hud._tab == "shop"` 且面板打开。另加反例：把玩家存到海面上必须被 `validate_world_state` 拒绝。

## 没做的（明确 pending）

- 浮店不做店内空间（封闭立面不承诺可进入），本轮不新增室内。
- 不做出货箱、保管仓库、交易订单面板——仍在码头。
- 补给站没有 NPC 值守，是无人自助入口。
- 参考图商业授权与用户最终美术验收仍 pending。

## 顺带暴露的三处既有问题

**自检的区块计数。** `selftest` 原来硬断言 `Zones.list.size() == 5`、「每个注册区块都在 `World/Zones` 下有实例」。结构物区块不在这棵树里，两处都会误报。改成按 `scene_binding` 分流：生活区仍是 5，结构物按自己的挂载点单独核对（存在、`zone_id` 一致、有行走面、有泊位）。

**自检的穿岛判定口径。** `_route_crosses_land` 只查 `shore.json` 的烘焙粗矩形，而家园港那块矩形（`x=2.6, z=-5.1, hx=6.35, hz=2.65`）比实际甲板外扩约 0.7 米。新增的 zone3 → sea_supply 长航段擦过这个角的 3 个采样点，被判穿岛，但用真正挡船的口径（`main._is_open_water`，与碰撞同源）逐点复查，这三点都是开阔水面。改成「烘焙矩形命中 **且** 实时几何也说不是水面」才算穿陆，并保留 `route-supply-probe` 记录 `baked_hits=3 / real_crossings=0`。真正的穿陆仍会让断言变红。

> 未做：`shore.json` 这批矩形本身偏粗（比几何外扩 0.7 米），会让岸线泡沫和寻路栅格的边界都偏保守。重新烘焙不在本轮范围内。

**自检的存量红项。** 本次 `selftest` 511 通过 / 26 失败。在 HEAD（`c692f28`）的干净副本上跑同一检查是 507 通过 / 26 失败，失败项集合逐条相同——这 26 项是历史存量（2026-10-30 起就在），不是本轮引入，也没有被本轮掩盖。逐条清单见两份日志的差异比对。
