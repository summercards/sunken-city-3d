# 2026-10-29 拾取进度条与浮层进度条变细

关联功能：SEA-PICKUP（R09）、SEA-BUILDING（R09）、SEA-UI（R42）。

## 现象

1. 海上点漂浮木或鱼群，之后是一段没有任何反馈的航行 —— 玩家不知道船还要多久到、也不知道点了到底有没有生效。
2. 首版拾取条做完之后，主人第二次反馈：**"这个进度条我还没开始拾取就出现了。逻辑不对"**（附截图：船在画面下方老远，浮木上方已经挂着一条暗色空条）。
3. 建造施工的进度条一直偏粗，压着水面和木板。
4. 修完时机之后，主人第三次反馈：**"没看到进度条，是被挡住了吗？帮我放在角色上方好了"**（附夜景截图：船在画面中央，浮木完全不在取景框内）。
5. 挂到角色头顶之后，主人第四次反馈，并且**指出了根因在玩法逻辑、不在表现**：**"角色还没停船就开始走进度条了。很不合理。需要先停下来，然后进度才出现。这个应该是获取东西的逻辑要调整，而不是进度条的表现。应该是角色走近后，停下，触发开始打捞或者捕鱼，然后触发开始后，进度条出现。"**

## 根因

### 一、"拾取时间"到底是什么

代码里**没有**独立的拾取 hold 计时器。真实链路是：

`点击浮木/鱼群` → `main._handle_prop_click()` → `boat.sail_to()` 规划航线 → `_pending_pick = {...}` → 船航行 → 靠停后 `main._process()` 里 `props.collect_crate()` / `props.collect_fish()` 结算。

所以"拾取时间"其实就是**船划过去的那段航程**，期间零反馈。

### 二、首版为什么"还没开始就出现"

首版把进度定义成 `1 - 剩余航程 / 总航程`，从点击那一帧开始显示。要划 31 米的时候，条在 0% 已经挂在目标头上 —— 那不是拾取，是赶路。**"有进度"和"这次拾取用了多久"被我混成了一件事。**

真正的拾取是贴近目标开始打捞的那一下，所以判定门槛改成时间而不是全程：

```
接近段长度 = cruise_speed() × PICK_REVEAL_SECONDS      # 2.6 m/s × 2.0 s = 5.2 m
剩余 > 接近段  → 不显示（只是航行）
剩余 ≤ 接近段  → 比例 = 1 - 剩余 / 接近段
```

条在船停稳那一刻刚好走满，不新增任何等待 —— 结算时机没动。

### 三、第四次反馈（最关键）：根因是"用航程伪造了拾取时间"

前三次改的都还是**表现**：什么时候显示、显示在哪。但主人指出的是规则本身错了 —— **船不停下来，就不该有进度**。

我那套 `PICK_REVEAL_SECONDS`（剩余航程折算成"还剩几秒到"）本质上是在**用航行进度冒充打捞进度**。它能让条看起来一直在动，但语义是假的：船还在划、人还没碰到东西，条已经在走了。玩家读到的是"我明明还没开始捞"。

正确的顺序是规则层面的：

```
点击目标 → 船划过去（这段没有任何进度）
        → 船停稳 + 目标在范围内（这一刻才叫"开始打捞"）
        → 打捞计时 1.2 / 1.6 秒（进度条只反映这一段）
        → 计时走满 → 真正结算
```

这不是把条挪个位置能解决的，是**玩法状态机缺了两段**。所以这次改的是获取逻辑。

### 四、第三次反馈：不是被挡住，是条跟着目标出画了

主人猜"被挡住了"，实际是**挂点选错了对象**。

镜头是跟着角色（`cam.follow_subject = player`）走的，而条当时挂在**目标**（浮木/鱼群）上。拾取时船朝着目标划过去，目标很容易偏出取景框 —— 一旦出画，条就跟着消失。偏偏那几秒正是玩家最想看到进度的时候。

这不是"被 UI 挡住"，是"条根本不在画面里"。改成挂在**角色头顶**：角色永远在镜头中心，条就永远看得见。

定位方式：世界点取 `player.global_position + UP × ANCHOR_LIFT(1.35)`，再按 `SCREEN_GAP = 16 px` 上移。角色 `head_pivot` 在本地 (0, 0.98)，头部半径约 0.21、发顶更高，1.35 米正好落在帽子上方留一点空隙。

### 五、"太粗"不是 size 写错了

`building_controller.gd` 原本已经写了 `bar.size = Vector2(92, 12)`，但实际渲染约 **92×20**。原因是 `ProgressBar` 的最小高度由样式盒 **content margin** 决定，而 `cozy_ui.surface()` 固定写 `content_margin_left/right = 16, top/bottom = 10`，再叠上 `apply()` 的 `custom_minimum_size.y = max(16, ...)` 与 `style_tree()` 的 18 —— **改 size 完全无效**。

所以不是调参问题，是控件选错了。必须自绘。

## 修法

### 共享控件 `godot/src/ui/thin_progress_bar.gd`（新增）

自绘 `Control`，`_draw()` 里画两个圆角 StyleBox，完全绕开 `ProgressBar` 的主题最小尺寸：

| | 宽 | 高 | 轨道 | 填充 |
|---|---|---|---|---|
| 建造 | 92 | **8** px | 暖棕 `#584c38`（原样保留） | 暖金 `#e9c16b`（原样保留） |
| 拾取 | 76 | **6** px | 奶油白 `#fff9e8` @ 0.62 | 青绿 `#5baa96` |

圆角取半高（4 / 3 px），无描边无阴影 —— 细条上描一圈只会显更粗。

`cozy_skip` 标记打在 **`_init()`** 而不是 `_ready()`：`_cozy_node_added` → `CozyUI.apply_instance` 是 `call_deferred`，只要有一帧抢在前面，`style_tree` 就会把尺寸刷回去。

拾取条原来沿用的是 `interact_prompt` 那条按住条的深青轨道。但那条贴在船舷/建筑前，而拾取条浮在**亮蓝水面**上：半透明深青叠上去变成一条脏暗线，远看像水波纹。改成奶油底 + 青绿填充，与 HUD 的奶油圆边同源，明度差 0.98 vs 0.60 足够读出走了多少。

### 拾取表现模块 `godot/src/pickups/pickup_progress.gd`（新增）

`CanvasLayer` layer=30（与建造条同族，低于 HUD 60 / 订单 62 / 菜单 90）。API：`begin()` / `set_ratio()` / `refresh()` / `hide_bar()` / `complete()` / `clear()` / `tick(delta)`。

`begin()` 不再接收目标节点 —— 挂点由 `subject`（角色）决定，与目标无关。`refresh()` 只用 `subject.global_position`，角色失效或落到相机背后才收条。

- 结算成功 → 走满后停留 0.5 s 再收，否则最后一格一闪而过看不见。
- **结算失败（船半路被岸线挡住）→ 直接收条，不闪满格**。原来无脑 `complete()` 等于骗玩家"捞到了"。

### 拾取状态机 `godot/src/bootstrap/main.gd`（本轮核心改动）

`main` 里新增三阶段常量与状态：

```gdscript
const PICK_PHASE_IDLE := 0        # 没有拾取
const PICK_PHASE_SAILING := 1     # 已点目标，船正划过去 —— 零进度
const PICK_PHASE_GATHERING := 2   # 已停稳且够得着 —— 正在捞，走进度
const PICK_GATHER_CRATE := 1.2    # 捞浮木时长（秒）
const PICK_GATHER_FISH := 1.6     # 捕鱼时长（秒）
```

四个方法各自只负责一件事：

| 方法 | 时机 | 作用 |
|---|---|---|
| `_begin_pick_sail(pick)` | 点击浮木/鱼群 | 进 SAILING，`begin()` + `hide_bar()`（清掉上一轮残留） |
| `_begin_pick_gather()` | 停稳且 `_pick_in_reach()` | 进 GATHERING，按类型给时长，条从 0 出现 |
| `_update_pickup_progress(delta)` | 每帧 | SAILING 只判断"到没到"；GATHERING 才减计时、推比例 |
| `_finish_pick()` | 计时归零 | 真正调 `collect_crate` / `collect_fish`，成功才停满格 |

几个必须写对的细节：

- **够不着要作废**。船被岸线挡住也会 `starts_sailing() == false`，那时离目标还有几十米。不校验就会在原地对空气捞 1.2 秒然后什么都没收到。`_pick_in_reach()` 用浮木 2.2 米 / 鱼群 `FISH_PICKUP_RADIUS`（3.2 米）。
- **打捞中不重复触发**。`_update_pickup_progress` 在 GATHERING 段不再看 `starts_sailing()`，否则船身随浪微动被判定为"又开始航行"会把进度打回 0。
- **潜水时冻结**。人不该一边下潜一边捞木头，GATHERING 段遇 `dive.active` 直接 return，计时与条都停住。
- **自己划到浮木旁也要捞 1.2 秒**。原来这条走 `try_pickup` 一停就瞬收，与"点过去要打捞"自相矛盾。`_start_idle_pick()` 让它走同一套：停稳 → `nearest_crate(boat.position, PICKUP_RADIUS)` → 开捞。`try_pickup` 因此删除（全仓已无引用）。
- 原先 8 处 `_pending_pick.clear()` 统一换成 `_cancel_pending_pick()`（同时清阶段、收条）。留下一条"永远不走"的条比不画更误导。

### 接线 `godot/src/bootstrap/main.gd`

- `_setup_pickup_progress()` 装配模块，注入 `cam` **与 `player`**。`_setup_player()` 在它之前执行（`_ready` 里第 200 行 vs 第 205 行），所以 `player` 已经就绪。
- `begin()` 不再接收目标节点 —— 挂点由 `subject`（角色）决定，与目标无关。
- `_process()` 里只有两行：`_update_pickup_progress(delta)` 推进当前这一轮，`_start_idle_pick()` 兜住"自己划过去"的情况。旧的那一大段"停稳就结算"分支已删除。

## 验证

新增两个闸门，都已注册进 `scripts/run_verification.py`：

| 闸门 | 内容 | 结果 |
|---|---|---|
| `progress-bars` | **45 项**。控件层：两条共用同一控件、渲染高 8/6 px、拾取更细、过一遍 cozy 主题仍是 6 px、轨道浅底 + 填充明度差足够、建造配色未被改动。挂点层：**目标在相机背后时条仍可见**、条心对准角色（误差 < 2 px）、条与目标投影点分开 1517 px、角色移动条跟随 242.8 px。**阶段层**：点了立刻不显示、一路推到只剩 3 米仍航行时条不出现、停稳才进 GATHERING 且条从 0 起步、0.6 秒到 0.50、走满才结算并进账、停稳但离 20 米直接作废、取消立即收条 | **PASS，0 失败** |
| `visual-pickup-progress` | **12 项** + 四张真实渲染图（航行段 / 白天打捞 / 夜里打捞 / 夜里航行段）。"真的看得见"不靠肉眼：同一机位拍两次（条显示 / 条隐藏），只比对条所在矩形，必须真有像素变化 | **PASS，白天 241 px / 夜里 243 px 随显隐变化；航行段与打捞途中不进账均 PASS** |

夜景专拍的理由：主人那张截图就是夜里，深色水面上一条低对比细线，肉眼看图很容易自我说服"应该有吧"。白天与夜里各验一次才算数。

> 该渲染闸门第一版是假通过风险源：截图是窗口像素（1280×800），而 `Control.position` 在画布坐标（1600×1000），直接比对会去量一块完全错位的水面，得出"什么都没画"的假结论。已改用 `get_screen_transform()` 换算。

回归：`building-integration` 38 项 PASS（`progress.size()==1` 语义未变）。

契约与架构：`check_feature_contracts.py --sync` 与无参检查 PASS（35 功能 / 459 源资产 / 392 运行期哈希 / 0 问题）；`check_architecture.py` 15 服务 0 问题。

证据目录（工程外 `sea-work/`）：

- `20261029-145249-pick-gather-visual-f87e81`：改状态机后的第一轮渲染证据
- `20261029-145356-pick-gather-visual2-806b7c`：航行段构图修正后重拍（固定往 -x 让 16 米会落进岸上的房子，改成挑开阔水面）
- `20261029-143036-pickup-anchor-visual-65f818`：挂角色后的白天与夜景证据（上一轮）
- `20261029-143315-pickup-anchor-accept-b8738a`：上一轮验收三连（`progress-bars` 37 项 / `visual-pickup-progress` 8 项 / `building-integration` 38 项，全 PASS）

### 同轮两个红项的归属（已隔离确认，非本轮引入）

- `minimum-loop` 的 `world sailing boundary`（`_is_open_water(60,30)` 期望 false）。
- `selftest` 的 `区块复原 zone1` / `船位复原`。
- `click` 的 `新航线取消旧拾取` / `航行途中改道` / `建造菜单前往并自动交付`。三条都依赖 `_on_destination("zone3"/"zone2")` 真的开船，而 minimal 范围里这两个区是锁的（`Zones.is_unlocked` 直接 return）。**把 `main.gd` 与 `sea_props.gd` 整体 stash 掉（等于纯 HEAD）复跑 `click`，三条一模一样失败**，确认与本次拾取改动无关。

隔离方法：`git stash` 分别撤掉（a）本轮改动、（b）本轮 + 航行范围改动、（c）只把 `main.gd:186` 的 `allowed_area` 单行还原成 `HOME_WATER`（**保留本轮全部接线**）。结论：

- 只还原那一行，`minimum-loop` 立即 PASS → 该红项来自并行任务把 `allowed_area` 与旧档回位判定从 `HOME_WATER` 换成 `SAIL_BOUNDS`（150×150），使 `(60,30)` 落入合法可航区，与 `test_minimum_loop.gd:32` 的旧断言冲突。断言或可航区需由该任务收口。
- `selftest` 两条在**纯 HEAD 航行语义**下同样失败 → 长期既有问题，与本轮及该航行改动均无关。

本轮不代改他人断言。

## 未改变的行为

- **唯一改动的玩法数值**：新增打捞时长（浮木 1.2 秒 / 鱼群 1.6 秒，原先到站瞬收）。只影响"停下之后捞多久"。
- 航速、奖励数量、掉率、补货计时、存档结构：全未改动。
- `try_pickup` 删除：它是"一停就瞬收"的旧语义，与新规则冲突；调用方已全部改走阶段机。
- 建造施工计时、费用、`progress` 字典条目语义、世界锚点：全未改动。
- `cozy_ui.gd` 本体未改：改造绕开 `ProgressBar` 即可，不去动全局主题的下限值。
- 建造条配色保持原暖棕 + 暖金，本轮只改粗细。
