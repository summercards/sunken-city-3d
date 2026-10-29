# 走不到不给入口、建造要先到工地（2026-10-29 二次修订）

对应条款：[SEA-INTERACT-R09](../features/interact/spec.md)、[SEA-BUILDING-R10](../features/building/spec.md)。
证据：`unreachable-menu`（23 项）、`building-approach`（18 项）、`visual-building`（24 项）。

## 一、我上一轮理解错了

上一轮我把「点不出子菜单」读成「需要给反馈」，于是做成：菜单照弹，
每一项涂灰并写明「那边在别的区域，需要先坐船靠岸」。

用户的回复带了图：「我人在这个位置，走路是过不去的对吧。点击另一个平台的操作，
应该是点不出这个菜单的。」

他是对的。菜单出现在一个点不动的东西上，**它本身就在说「这个能操作」**。
把原因写在标题上不解决问题 —— 那只是给一句谎话配了个解释。

## 二、改成「不给入口」

| 层 | 旧 | 新 |
|---|---|---|
| 悬浮图标 | 走不到也画，还会被夹到屏幕边缘 | **不画**。`_pick()` 默认跳过走不到的目标 |
| 指针 | 变成手形 | **保持箭头** |
| 点击 | 弹菜单 + 灰色选项 + 标题写原因 | **不弹菜单**，只 toast 一句原因 |
| 原因措辞 | 「那里没有能走过去的地面」 | 「那边在别的区域，需要先坐船靠岸」/「那里走不过去，中间没有连通的路」/「那里是水面，走不过去」 |

实现落点：

- `HoverCard.reach_gate`：注入式可达性查询（`main._land_reach_reason`）。
  `_pick(screen, include_barred=false)` 默认过滤；点击分派时用 `include_barred=true`
  再查一次，**只为了取出原因说一句话**，不弹菜单。
- 350 ms 缓存：悬停每帧都要问，路径规划不便宜。过期即重算
  —— 走两步之后结论就该变了。
- 可达性按 `approach_points` 判，不按物体中心判。原因：培养土会把格心从可行走面里
  挖掉，按中心判会把自己刚建好的菜箱说成「走不过去」。这是上一版引入的回归，
  `visual-building` 里「built plot opens regular bubbles」失败暴露了它。

保留上一轮的两条有效修复（它们与本轮方向不冲突）：

1. **命中范围是物体屏幕包围盒（外扩 10 px）**，不是那颗 38 px 的圆。
   图标是命中之后才画的，「先点中它才看得见它」是不可能满足的条件。
   包围盒面积 > 视口 12% 的物件退回图标口径 —— 否则菜箱把整张甲板包进去，
   点甲板全被判成点箱子，玩家再也走不了路。
2. **锚点出屏时退回点击点**，菜单不再开一帧就关；并让开右上/右下两颗常驻圆按钮。

## 三、建造要先走到工地

旧 `BuildingController.handle_input`：

```gdscript
if not preview.is_empty():
    var result: Dictionary = service.begin(preview)   # 当场扣料、当场开工
```

五米外点一下，木板上就自己长出进度条。建造读起来像在 map 上点按钮。

新流程：

```
点击虚影
  → can_place 检查（不通过直接 toast，不排队）
  → 已在格子旁（≤0.8 米）？ → 当场开工
  → 否则：记下意图 + 找落脚点 + 让角色走过去
  → 站定（距离 ≤0.8 米 **且** 已停下） → 扣材料、开始计时
```

关键判断：

| 决定 | 原因 |
|---|---|
| 到位要求「距离 + 已停下」两个条件 | 只看距离会在滑进去的最后半米就开工，进度条追着人跑；只看停下可能被截停 |
| 等待上限 8 秒 | 卡住时不至于让玩家一直等 |
| 中途停下但没到位 → 取消 | 否则会永远挂着 |
| 等待期间虚影锁在目标格 | 鼠标一动就换位置，玩家会以为刚才点的那格没记住 |
| 退出建造模式清排队 | 不留「走着走着突然开工」 |
| 已在旁边就当场开工 | 站在工地边点一下还要看他走两步，是纯粹的摩擦 |

落脚点 `_construction_stand_point`：沿「角色这一侧」由近到远探
1.15 / 1.5 / 1.9 / 2.4 米，取第一个落在可走矩形且**有通路**的位置。
不能直接拿格心 —— 新木板格还没进可行走面。都探不到就把格心夹到最近的可行走条带。

控制器新增三个注入端口（`stand_point` / `approach` / `actor_state`），
不读 `Economy` / `Main` / 场景树，符合 SEA-BUILDING-R07。

## 四、验证

```
building-approach        PASS exit=0   18 checks, 0 failures
unreachable-menu         PASS exit=0   23 checks, 0 failures
visual-building          PASS exit=0   24 checks, 0 failures
building                 PASS exit=0
building-integration     PASS exit=0
interact-focus           PASS exit=0
board-click              PASS exit=0
farming / modules / pocket-bubbles  PASS exit=0
```

`building-approach` 覆盖：远处只排队不扣料 / 等待期虚影不跟鼠标 / 走到位自动开工且只扣一次 /
开工后人站在工地边 / 退出模式清排队且不再自己开工 / 站在旁边点一下当场开工。

`unreachable-menu` 覆盖：走不到的目标悬停判空、点击不弹菜单、只给一句原因 /
可达目标点本体就弹菜单 / 菜箱 → 种植 → 选种子 / 巨型包围盒不吞甲板 /
接近失败必有提示。

## 五、实景

| 文件 | 内容 |
|---|---|
| [approach-1-ghosts.png](evidence/2026-10-29_build_approach/approach-1-ghosts.png) | 选中配方，平台东侧出现拼接虚影，人站在平台中央 |
| [approach-2-queued.png](evidence/2026-10-29_build_approach/approach-2-queued.png) | 点了虚影：虚影锁在目标格，左下提示「走到木板边再开工」，材料未扣、未开工 |
| [approach-3-walking.png](evidence/2026-10-29_build_approach/approach-3-walking.png) | 走过去途中 |
| [approach-4-started.png](evidence/2026-10-29_build_approach/approach-4-started.png) | 站到格子边，开工；虚影消失 |
| [approach-5-done.png](evidence/2026-10-29_build_approach/approach-5-done.png) | 板子成型，人还站在旁边，提示「拼接木板建造完成」 |
| [no-menu-when-unreachable.png](evidence/2026-10-29_build_approach/no-menu-when-unreachable.png) | 站在木屋码头点水上平台：没有图标、没有菜单，只有一句「那边在别的区域，需要先坐船靠岸」 |

## 六、仍存在的边界

- 在水上（mode != 0）不做可达性预检：船会先靠岸，提前判死会把
  「在船上点岸上的箱子」变成点不动的东西。这条沿用旧行为。
- 等待施工期间若角色被其它输入打断（开面板、睡觉），`context_reason` 变化会关闭建造模式，
  排队随之清掉，不会静默开工。
- 未运行 `click`（其 3 项失败为既有航行与区块复原问题，HEAD 版本对照结果一致）。
