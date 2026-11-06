# 2026-11-06 房间放大 1.5 倍与空间隔离

[返回主文档](../../GDD_V1.0.md#sea-room) · [功能文档](../features/room/spec.md) · [独立账本](../features/room/ledger.md)

## 需求与落点

用户报了三件事（附一张室内截图）：

1. 角色放大了，房间也要放大一些。
2. 房间原来摆在太阳房顶上方，**如果用 main 场景里的一个地方，会不会打架**。
3. 「你看外面的鸟的特效进来了」 —— 截图上房间内侧有三四片白色鸟形剪影。
   他给了三个方向：换个位置 / 用 main 里的地方 / 开个新场景。

对应条款：SEA-ROOM-R06a（缩放）、SEA-ROOM-R14（空间隔离与室内抑制）。

## 一、放大 1.5 倍

角色 `SCALE = 1.5`（`src/avatar/avatar_dimensions.gd`），身高约 1.88 米。
房间几何是 1:1 建模的（净空 5.0、门洞 2.06）。

**算一下就知道非放不可**：

| 量 | 1:1 房间 | 与 1.88 m 身高之比 | 原设计（1.25 m 角色） |
|---|---|---|---|
| 净空 | 5.00 m | 2.66 | 4.00 |
| 门洞高 | 2.06 m | **1.10** | 1.65 |
| 净空（放大 1.5 后） | 7.50 m | 3.99 | — |
| 门洞（放大 1.5 后） | 3.09 m | 1.64 | — |

门洞只有身高的 1.10 倍——人在门框下抬不起头。放大 1.5 后两个比值都回到原设计
（3.99 vs 4.00、1.64 vs 1.65），这不是「大概放大一点」，是**恢复设计意图**。

做法：几何**不重建**（Blender 资产是干净的 1:1 源，改它要重跑 13 个组件包、
重新导出、重新验收），缩放只写一处 —— `bedroom.tscn` 的根节点
`Transform3D(1.5, 0, 0, 0, 1.5, 0, 0, 0, 1.5, 0, 200, 0)`。

### 缩放会咬人的三个地方

1. **剖切判据**。`room_cutaway.gd` 原来拿世界坐标差跟一组**建模尺寸常量**
   （墙到中心 2.5、前厅正面 2.70、侧玻璃 1.72、天花高 2.75、`PORCH_FRONT_Z` 2.4）
   比。房间 scale 1.5 之后，同一个「2.5」在世界空间里是 3.75 —— 比错就是
   「转到侧面缺两面墙」。改成先 `to_local(camera.global_position)`，
   在**房间局部空间**里比，这些常量永远不用改。
2. **相机距离与缩放区间**是世界米。房间放大后仍用 14.4 米，等于镜头贴到脸上。
   改成 `CAMERA_DISTANCE × uniform_scale()`、`orbit_zoom_range()` 返回
   `8–24 × scale`。控制器在进屋时把区间写进相机，出门时还原成 `ORBIT_ZOOM_MIN/MAX` 基准。
3. **行走面与碰撞**不用改：`WalkArea` 的 `rects` 是局部坐标，`to_global` 会自动乘
   scale；家具的 `BoxShape3D` 跟着父节点缩放。`surface_y` 由
   `room_scene._ready()` 从 `global_position.y` 取，不写死在两处。

## 二、会不会打架：会不会，而且已经在打了

原来房间在 `(2.5, 12.6, 1.0)` —— 太阳房屋顶上方 0.7 米。用探针实测各层高度：

| 内容 | 高度范围（世界 y） | 与房间 12.60–15.35 |
|---|---|---|
| 海面 | 1.12 | 不碰 |
| 太阳房屋面 | 11.89 | 不碰（差 0.71） |
| **海鸥飞行层** | **14.30 – 17.70** | **重叠 1.05 米** |
| 水下街景 | < 0 | 不碰 |

**海鸥就是那几片白色剪影。** 而且不是「进屋时忘了藏」—— `_outdoor_nodes()` 明确
把 `Birds` 收起来了，探针也确认进屋后 `birds.visible == false`。

真正的路径是：**`birds.set_hour(hour)` 会自己把 `visible` 设回去**。

它内部记着 `_shown`（上一次按小时算出的可见态），并按这个状态做早退：

```gdscript
func set_hour(hour: float) -> void:
	var shown := 1 if (hour >= 6.0 and hour < 18.0) else 0
	if shown == _shown: return    # ← 早退
	_shown = shown
	visible = shown == 1          # ← 这里覆盖了登场时被外部设成的 false
```

进屋那一刻 `_shown` 仍是 1（白天），所以单次 `set_hour` 不会重新点亮。
但只要跨过一次日出日落，`_shown` 就会被写过一遍：

| 时刻 | `shown` | `_shown` 变化 | `visible` |
|---|---|---|---|
| 10:05 进屋 | 1 | 1 → 1（早退） | 外部设成 false |
| 睡到 19:00（时钟推进） | 0 | 1 → 0 | false（本来也是） |
| 跨日 06:00 | 1 | 0 → **1** | **true —— 鸟回来了** |

「在屋里睡一觉到天亮」正好走完 19:00 → 06:00 这一对时刻，于是醒来时卧室里
有海鸥。截图上的时间是 10:05，白天 —— 与这条路径完全一致。

另外 `build()` 里有一行 `visible = true`，读档/重建鸟群时同样会无视进屋时设的
`visible = false`。这条也一并封掉。

## 三、三个方案，选哪个

| 方案 | 代价 | 结论 |
|---|---|---|
| 放在 main 场景某个角落（比如远海、屋顶另一个位置） | 只要该位置的高度带里有任何内容（鸟层、未来的高楼、飞行物）就重演；而且「角落」在 150 m 可航区里没有真正的安全区 | 否 |
| **换个位置（搬到远处）+ 抑制按时段自显的环境节点** | 改一个 `transform`、加一个 `set_interior_hidden` 接口 | **采用** |
| 开新场景 | 时间、存档、区块注册、相机、UI、行走接口全部各做第二份；存档要分叉；`World/Interior` 这套已经跑通的区块抽象要推翻 | 否 |

最终摆位：**`(0, 200, 0)`**。200 米高度上没有任何室外内容（探针实测最高内容
是海鸥 17.7），离开可航区、屋面、水下都在一个数量级以上。玩家进屋后看不到外面
（世界全藏、背景纯黑），所以「在不在太阳房上」本来就没有视觉含义 —— 原先把它
摆在屋顶上方，纯粹是当时以为「应该看得见它」。

### 双保险，不是二选一

只挪远：以后任何新加的高层/高空内容都会重演同一个 bug，而且没人会记得
「房间在 200 米，别再往上放东西」。
只做抑制：房间仍贴在屋顶上，换任何机位都可能看见外面的东西。

所以两个都做，并且把抑制做成**通用接口**而不是给鸟群打特例：

```gdscript
# birds.gd
func set_interior_hidden(hidden: bool) -> void:
	if suppressed == hidden: return
	suppressed = hidden
	_apply(is_flying_hour())

func _apply(shown: bool) -> void:
	var live := shown and not suppressed   # 时段 × 室内抑制
	visible = live
	for entry in _birds:
		... set_process(live)
```

```gdscript
# room_controller.gd — 收起/恢复室外节点时一并通知
if node.has_method("set_interior_hidden"):
	node.set_interior_hidden(hidden)
```

`_show` 状态与「室内抑制」是两个独立因子，相乘才是最终可见性。这样
`set_hour` 无论怎么跳，屋里都收着；出门解除抑制后立刻按当前小时恢复。

## 三·五、放大之后才暴露的两个硬编码

房间放大 1.5 倍，把两处一直写死、但从未被触发过的数字变成了缺陷。它们都在
**交互链**上，而且都**静默失败**（不报错、不弹提示），只表现为「点了没反应」。

### 1. 接近落点写死 1.35 米 → 角色走进床垫里

`approach_action.gd`：

```gdscript
# 原来
area.clamp_point(anchor + dir * 1.35)   # 站到目标外 1.35 米
```

床放大后半长 1.52 米 —— 落点落在床垫**内部**。角色走过去，
`walk_action.step` 的碰撞检测返回 `blocked`，判定「前面被挡住了」→ `cancel()`，
状态从 `approaching` 直接掉回 `ashore_idle`，交互永远不开始。

改成按目标自己的「够得着半径」推导：

```gdscript
var stand_off := 1.35
if target.has_method("effective_focus_radius"):
    stand_off = clampf(float(target.effective_focus_radius()) + 0.35, 1.35, 2.6)
```

`effective_focus_radius()` 本来就是「这个物件要站多近才算够得着」，
且已按视觉尺寸放大（`auto_radius`）。小物件取到 1.35 下限、行为不变；
大件自动站远。

### 2. 自动长按门槛写死 2.2 米 → 站在床边也不算「到位」

`interacting.gd`：

```gdscript
# 原来
context.interactor.auto_hold = not blocked and distance <= 2.2
```

新站位是 2.25 米，2.2 的门槛**永远不成立** —— 人明明站在床边，`auto_hold`
保持 false，进度条一秒都不动。改成

```gdscript
var reach := 2.2
if target.has_method("effective_focus_radius"):
    reach = maxf(reach, float(target.effective_focus_radius()) + 0.6)
```

### 3. 顺带：走动打断在自动接近时不该算「失败」

`interactor.gd` 原来一检测到脚下挪动就发 `blocked`，而上层

```gdscript
interactor.blocked.connect(func(reason):
    _auto_target = null
    interactor.auto_hold = false)
```

于是「人还在走 → 打断 → 关掉 auto_hold」形成死锁：走近被锁，走远也被锁。
现在自动接近中（`auto_hold`）只把进度清零、重设锚点，不发 `blocked`；
手动按住 E 走开仍然提示（那才是玩家真的想取消）。

## 四、顺带修掉的锤子

截图右上角那颗锤子（拆除工具）在屋里也在。房间里既不能建造也没有可拆的东西，
点它只会进入一个空模式。`launcher_visibility_query` 加一条 `not room_service.inside`。

## 五、实测

| 用例 | 结果 |
|---|---|
| `room` | **112 项 0 失败**（新增：放大 1.5、远离室外内容、鸟群抑制、时段跳变仍不可见、出门解除抑制） |
| `sleep-cycle` | **42 项 0 失败**（修复前 1 项失败：`world click approaches and begins sleep`） |
| `visual-room` | 6 机位 0 失败 |
| `visual-room-orbit` | 8 机位 0 失败 |
| `sleep-cycle` / `water-layer` / `camera` / `modules` / `save-protection` | 见下方汇总 |

实拍：`room-inside.png` 中白色剪影与锤子都已消失，角色在 7.5 m 净空里比例正常。

## 六、遗留

- 房间仍然挂在 `main.tscn` 的 `World/Interior` 下。如果将来要做「多个室内场景」
  或「从别人的屋顶走进去」，需要把房间提到独立 `PackedScene` 资源再按需实例化 ——
  那是内容量的需求，不是隔离的需求，现在不做。
- 床、地毯、家具的**建模尺寸**没变（跟着房间乘 1.5）。若以后要「床比房间更精细」，
  得单独给家具 scale，那会破坏 `place_bed` 的局部坐标语义。
