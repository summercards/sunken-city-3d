# 太阳房（zone1）撤掉花瓣飘落粒子

- 日期：2026-10-28
- 功能：SEA-AMBIENT（环境植物与生活表现）
- 依据：按图反馈 ——"阳光房的中间有一些飘起的粒子，帮我去掉"

## 那批粒子是什么

不是模型、不是烘焙网格，是**区块级环境粒子**。

调用链：

1. `godot/tools/naming.py` 的 `ZONE_PLANT_EFFECTS["zone1"] = {"effect": "petals", ...}`
2. `godot/tools/build_plants.py:210` 把它写进本区块每一株**专用植物**场景（`scenes/plants/zones/zone1_home_harbor/*.tscn` 的 `effect = "petals"`）
3. `godot/src/ambient/plant_field.gd:76-79` 收集到该字段后，调 `_spawn_effect()` 在**区块中心**建**一个**发射器
4. `godot/src/ambient/plant_effect.gd:27-28` 按 `petals` 分支发出「向下飘、5.5 s 生命、重力 0.35、粉白 0.09–0.16 m 方片」

关键点：**一个区块只有一个发射器，位置取 `WalkAreas` 首个子区域的 `center_world()`，不是跟着植物走。** 所以它固定飘在 zone1 正中——也就是太阳能木屋上层平台与木栈道交界那片空地。`emission_box_extents = (7, 0.6, 7)` 再给它罩住 14×14 m 的范围。

这正对上截图里那些白/淡粉小点：既不在花盆上方（花瓣不会从花里冒出来），也跟着镜头上方的空域一起铺开。

**顺带发现一处悬空设计**：每个植物场景里都有一个 `EffectPoint` Marker3D（`build_plants.py` 写在 `bounds[1] * 0.6` 高度），原意显然是「从植株冠部发出粒子」，但 `plant_effect.gd` 从没读过它——`_spawn_effect()` 只用 `_zone_center()`。这是本次粒子位置看起来"跟植物无关"的根因。本次未改动该设计（改它等于重做发射器定位，超出"去掉粒子"的范围），仅记录在案。

## 改了什么

撤的是**数据**，不是代码路径。

| 文件 | 改动 |
|---|---|
| `godot/tools/naming.py` | `zone1` 的 `effect` 由 `"petals"` 改为 `None`，保留 `sway 0.028` / `wind 0.9` |
| `godot/tools/build_plants.py` | `write_plant_scene()` 在 `effect` 为空时**不写** `effect` 行，但仍写 `sway_amplitude` / `wind_strength` |
| `godot/scenes/plants/zones/zone1_home_harbor/*.tscn`（16 个） | 逐文件删掉 `effect = "petals"` 一行，摆动参数保留 |
| `godot/src/ambient/plant_effect.gd` | 仅注释：`petals` 分支标注 zone1 已停用，说明「停用只改数据」 |

设计取舍：

- **不改 `plant.gd` / `plant_field.gd` 的收集逻辑**。`effect == ""` 时 `spawn_from_placements()` 的 `not effects.has(node.effect) and node.effect != ""` 本来就会跳过，`_spawn_effect()` 根本不会被调用。零代码分支、零运行时开销，也不留「为了去掉一个效果而改架构」的债。
- **不删 `petals` 实现**。以后想恢复，把 `naming.py` 里 `"effect": None` 写回 `"petals"`，重跑 `build_plants.py` 即可；也能给别的区块用。
- **保住叶片摆动**。`petals` 是「飘落的花瓣」，`sway`/`wind` 是「植株在风里摇」，两件事。删粒子时如果把整行 effect 配置一起删，`wind_strength` 会退回默认 1.0、`sway_amplitude` 退回 0.025，叶子会突然摇得更凶——这是 concurrent 修改里最容易漏的连带损伤，所以 `build_plants.py` 里做了显式分支并留了注释。

## 影响面

zone1 的 16 株专用植物（`plant_04_8l` … `plant_41_5l`）原先全部登记 `petals`。改后：

- 发射器数量：1 → 0（zone1）
- 摆动：完全不变（每株仍是 0.028 / 0.9）
- 生长、摆放、`describe()`、实例 ID：全部不变，不触发存档键变动

其它区块不受影响：

| 区块 | effect | 现状 |
|---|---|---|
| zone1 sea | ~~petals~~ | **本次停用** |
| zone2 横滨铁道 | pollen | 专用植物场景目录尚不存在，未生效 |
| zone3 圆弧农场 | wind | 只加强摆动，本就不发粒子 |
| zone4 远海街町 | sea_breeze | 专用植物场景目录尚不存在，未生效 |
| zone5 浅水养殖台 | ripple | 专用植物场景目录尚不存在，未生效 |

（`scenes/plants/zones/` 下目前只有 `zone1_home_harbor` 与 `zone3_arc_farm` 两个目录，zone3 那 20 株都是 `wind`。）

## 验证

入口：`python scripts/run_verification.py visual-decorations --timeout 300`

| 项 | 结果 |
|---|---|
| 退出码 | 1（**既有**失败，见下） |
| checks | 1599 checks, failures=1 |
| 本次新增断言 | 3 条全通过 |

`godot/tests/test_scene_decorations.gd` 新增三条，盯住「粒子不会再回来」和「摆动没被误删」：

```gdscript
check(emitters==0,"zone1 builds no ambient particle emitter")
check(zone1_plants.effect_node==null,"zone1 plant field holds no effect node")
check(sway_kept>=10,"zone1 plants keep sway after petals removed")
```

为什么是「断言 zone1 一个发射器都没有」而不是「断言 effect 字段为空」：字段为空只是数据现状，真正要保证的是运行时**没有粒子被建出来**。哪天有人把 `ZONE_PLANT_EFFECTS` 改回去，这条会立刻红。

### 既存失败（与本次无关）

```
FAIL decorations follow dive lifecycle
```

该失败在 `2026-10-27-185641-fish-deco-vis`、`2026-10-27-185918-after-restore` 两次历史运行里已经存在（均为 `1592 checks, failures=1`），守的是「潜水时海面世界整体隐藏」这条约束，属 SEA-AMBIENT 未完成项。本次未触碰潜水链路，按原样保留待办。

### 实拍

同机位（`decorations-home`，`target=(4,6,5)`、`distance=45`、`orbit=(-0.6,0.7,0.8)`）。改前依据为主人提供的截图：上层平台与栈道上方散布白/淡粉小点；改后同机位实拍空域干净，屋顶、遮阳篷与阳台轮廓完整。

证据：`docs/development/assets/2026-10-28_zone1_no_petals.png`

### 运行时干扰（记录一次踩坑）

同一份工作区连续三次运行，只有第一次与第三次得到 `1599 checks, failures=1`，中间两次出现：

```
FAIL independent movable furniture
FAIL independent upgrade plants
SCRIPT ERROR: Nonexistent function 'sample' in base 'Node3D'
[shoreline] geometry segments=8256   # 正常是 706
```

`solar_bounds` 也跟着变（`S=(18.17,30.03,22.59)` vs 正常 `(20.19,29.16,23.29)`，`roof_y` 11.84 → 12.61）——即太阳能木屋本体都没装配完整。

排查结果：**任务管理器里有多个早先运行遗留的 `Godot_v4.6.3` 进程没退出**（其一 1.0 GB 常驻），它们仍持有隔离工程与 `.godot/imported` 的 junction，后一次运行读到的是被争用的资产与缓存。

`taskkill` 掉全部 4.6.3 残留后立刻复现正常结果。**结论：本仓库跑 `run_verification.py` 前应先确认没有残留的验证用 Godot 进程**，否则会把"环境争用"误读成"场景少装配了一半"。这不是本次改动引起的回归。

工作区完整性同时用 `git diff <被 pop 的 stash commit> -- godot/src godot/scenes godot/tests godot/tools` 核对为空，确认中途那次 `git stash push/pop` 未损坏任何文件。

## 遗留

- `FAIL decorations follow dive lifecycle`：既有失败，属潜水生命周期断言，需在 SEA-DIVE 侧单独处理。
- `check_feature_contracts.py` 的 runtime hash drift（`world_env.tres`、`salvage_station.glb`）在本轮开始前就存在，本次未触碰。
