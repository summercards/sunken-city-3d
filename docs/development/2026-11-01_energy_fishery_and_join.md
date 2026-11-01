# 2026-11-01 · 过场文字停留、体力与疲劳、扩建阻挡修复、渔场改造

本轮四条用户需求，分别归 SEA-SLEEP、SEA-ENERGY（新登记）、SEA-BUILDING、SEA-AQUA。主文档摘要已同步，`docs/generated/feature_index.json` 由 `check_feature_contracts.py --sync` 重新生成。

## 1. 睡觉/起床黑幕文字停留太久不够（SEA-SLEEP-R06）

`godot/src/ui/sleep_curtain.gd` 里两段文字的时长原来是睡眠文字淡入 0.18 秒、停 0.3 秒、淡出 0.18 秒，起床文字停 0.65 秒，用户反馈「一闪就没了」。

改为常量 `COVER_FADE = 0.45`、`COVER_HOLD = 2.4`（入睡）、`MORNING_FADE = 0.45`、`MORNING_HOLD = 2.6`（起床）。圆幕合拢 0.85 秒、打开 1.05 秒、全黑后切时间与位置、文字消失后才开幕这些时序语义都没动，只把文字在屏幕上待的时间拉长。

验证不只看常量：`test_sleep_cycle.gd` 新增 5 项，其中两项在真实过场里实测「全黑后 1.6 秒两段文字仍完整可见」。`sleep-cycle` 与 `visual-sleep-cycle` 均通过。

## 2. 体力与疲劳（SEA-ENERGY，新 FeatureID）

新功能，独立 spec/ledger，参考《星露谷物语》。规则层 `godot/src/energy/energy_service.gd`，表现层 `godot/src/ui/stamina_bar.gd`，装配在 `Economy.energy`（挂在 Economy 下，与 farm/orders 同级）。

- 上限 100，新局满值，每日醒来回满。
- 开销：播种 2、浇水 1、收获 1、建造 4、拆回 3、搬移 3、岸边采集 3、海上打捞 3。行走、购买、存取、睡觉不扣。
- 扣费一律放在**结算成功之后**：种植类在 `farm.gd` 的 plant/water/harvest 末尾；建造类在 `building_service.begin/move/remove` 扣款成功后；采集在 `_on_gathered` 收到产出后（`GatherSpot.blocked_reason()` 会在按住 E 之前就用只读端口拦下体力为零的情况）；打捞在 `_finish_pick` 真的收到东西之后。
- 低于 25% 提一次「有点累了 · 回家睡一觉会好起来」，同日不重复，次日重置。
- 归零：`Main._on_energy_exhausted()` 先播角色台词「啊，太累了，今天需要休息了。」（`character_dialogue` 新增 `close_line()`，到点自动收起），再走 `sleep_cycle.request_forced()`，即同一套黑幕过场，`forced` 标记这次是被体力逼的。期间 `input_blocked()` 返回真，重复触发只执行一次。
- 醒来：`_wake_at_home()` 在全黑段调 `energy.after_sleep(sleep_cycle.forced)`。被逼着睡的那一次上限变 50 并补满；下次正常入睡恢复 100。惩罚标记 `pending_half` 单独存档，读两次不会变成 25。
- 右下角体力条：压在「锁定视角」圆按钮上方 12px、右对齐同一边距、跟随同一缩放系数。奶油底槽 + 青绿填充，低于 25% 转琥珀、归零转珊瑚，文案「体力 当前 / 上限」右对齐。自绘而非 ProgressBar，理由与 `thin_progress_bar.gd` 相同（`cozy_ui.surface()` 的内容边距会把 ProgressBar 撑到 20px 以上，细条画不出来）。
- 存档：`economy.energy = {version, current, maximum, pending_half}`，**不进 required**，写入之前的老档读成满体力，不读成 0。
- 端口：`farming_ports.spend_energy / energy_reason`、`building` 的 ports 同名两项、`GatherSpot.energy_reason` 都是**可选**端口，未接时三个模块照常运行 —— `farm.gd` / `building_service.gd` 仍然不访问 `Economy`/`GameState`。

## 3. 浅水养殖台「无法拼接」（SEA-BUILDING-R25）

用户截图标了五处绿框，都在浅水养殖台周边。逐格跑 `building.can_place()` 拿到原因：

| 格 | 原因（修复前） | 根因 |
|---|---|---|
| (0,-1)(1,-1)(2,-1)(0,2)(1,2)(2,2) | 这里有既有建筑 | 平台自己的水下底座在水面线生成的阻挡矩形与平台轮廓等大，木板网格与平台轮廓不同步，贴边接必然重叠 |
| (-1,0)(-1,1) | 请让船离开施工范围 | 船正停在泊位，泊位旁那格与船重叠（正常拦截，把船开走即可） |
| (3,0)(3,1) | 这里已有浮台 | 玩家已建的 4×4 浮台（正常拦截） |

修复只改 `Main._construction_obstacles()`：水面阻挡里，凡与固定平台轮廓相交的项一律不计入「既有建筑」。远处区块地面、海上浮店、其他结构照旧拦截；平台本体仍报「这里是原有平台」；泊位那侧仍然拒绝，但原因现在是泊位与上下船通道，不再是「既有建筑」。新增 `building-base-neighbors` 28 项守着这四件事，并真的建出北、南两块板再存读一遍。

## 4. 家园补给站升级为渔场（SEA-AQUA-R04/R05）

用户指定升级对象是第二张截图里的平台（家园补给站，即家园打捞浮台上的补给入口）。规则层 `godot/src/aqua/fishery_service.gd`，界面 `godot/src/ui/fishery_panel.gd`。

- 入口：木牌气泡新增「升级为渔场」，与商店/仓库/出货箱同一条动线（先走过去、站定才开面板）。材料不足时该气泡按现有规则变灰并写明缺什么。
- 成本：木板 100 + 鱼 50，**背包与保管仓库合并计数、合并扣费**（100 块木板塞不进 24 格背包）。
- 界面：`hud.open_aqua_upgrade()` → `fishery_options` 页，复用 `home_loop_panel.row()` 的行列表（左侧说明、右侧动作胶囊、禁用态写原因），与种植页一致。
- 升级后：木牌文案改「渔场 · 商店 / 仓库 / 出货箱」，平台上插一面旗（复用建造组件 `flag.tscn`，明确是临时标记，不冒充正式渔场美术）；`economy.fishery = {version, unlocked}` 进存档，旧档读成未升级，读档后文案与旗子一并恢复。
- 养殖生态（投苗/生长/收成，R01–R03）**仍未实现**，状态保持登记，不因这次改造升级完成度。

## 5. 漂浮结构没有吃水线白沫（SEA-OCEAN-R24）

反馈：新加进去的海上悬浮商铺在水面上没有白色波纹，同屏的家园平台与自建木板都有。

排查过程（三层，逐层排除）：

1. **不是泡沫参数**：两处用的是同一套 `water.gdshader` 与同一份距线图，家园那块有白沫就证明参数没被改坏。
2. **不是根节点漏扫**（第一版判断）：`_set_shore_uniforms()` 确实只扫了 zone 根节点，`World/SeaStructures` 没进去。把它并进取样根后**反而更糟** —— 切面从 9950 降到 2978。原因是 `shore_distance` 只在「三角形跨过水面高度平面」的地方切截面，而浮店整块浮在水面上方（甲板底面离水面 +0.04 米），竖直方向没有任何面跨过水面，所以它贡献 0 条、还把取样框抢走了一半。**根因是取样口径，不是漏扫**。
3. **为什么船有它、水没有**：船的水面阻挡走 `BlockerSet`（从几何派生矩形，与水面高度无关），早就在 `_water_shapes()` 里单独收集过浮店。于是「船知道这块东西存在，水不知道」—— 正是这次反馈的观感。

修复：`ShoreDistance.rebuild()` 增加可选的 `outline_rects` —— 把这些结构的占地轮廓**直接当作距离场种子线段**。距线图本来就是无符号距离场，四条边播种之后，内部点离最近边线远、外圈贴一圈，与几何截面出来的效果一致。

两个坑：

- **只在并集外沿播种**。第一版逐块播了每块自己的四条边，结果并集内部每条接缝外一圈都成了「贴边」，泡沫像棋盘一样铺满整块甲板（实景图确认）。现在每条边先看它的内侧中点有没有被别的矩形覆盖，被覆盖就不播。
- **不能先合成一个大外包框**。浮店甲板绕 Y 转了约 -98°，轴对齐包络比甲板本身宽 3~5 米，泡沫会离船体一大截 —— 看起来像地上画了个圈，而不是水贴着船。所以逐条轮廓播种（浮店 27 条），轮廓由 `BlockerSet` 的 0.4 m 栅格派生，模型换形状、换旋转都自动跟随。

取样范围取「相机可平移范围 ∪ 结构实际占地」，结构以后摆远一点也不会静默落框外。

### 验证

- `ocean` +6 项：漂浮体自己切不出截面（守根因）、显式轮廓给出 4 条外边、外沿距离 <0.35 m、远处海面 >4 m、相邻两块只留并集外沿（6 条边）、并集内部不出接触带。
- `floating-shop` +4 项：正式场景里浮店外沿吃水线 d<0.6 m、甲板内部 d>2 m、远处海面 d>4 m，另加「距线图已建」。
- `ocean` 与 `floating-shop` 实跑通过（浮店套件另有 5 项**基线就红**的失败：工作区 `main.tscn` 里有一处未提交的浮店缩放/位移，把它挪到了 x≈69.9 / y≈-18.1 / z≈46.4 并放大到 1.87/1.78/1.65，位置与甲板高度断言因此不符；暂存本轮改动后复跑同样红）。

## 验证

统一 runner，隔离用户数据，全部 `scripts/run_verification.py`：

| 套件 | 结果 |
|---|---|
| `energy` / `visual-energy` | 39 项 0 失败 / 通过（含强制休息台词与半体力实景图） |
| `fishery` / `visual-fishery` | 28 项 0 失败 / 通过（含改造页与升级后实景） |
| `building-base-neighbors` | 28 项 0 失败 |
| `sleep-cycle` / `visual-sleep-cycle` | 通过（新增停留时长实测） |
| 受影响的既有套件 | `building`、`building-join`、`building-kit`、`building-simulate`、`building-open-rules`、`building-space`、`building-approach`、`walk-on-planters`、`farming`、`modules`、`minimum-loop`、`initial-planters`、`save-seed`、`save-corrupt-seed`、`save-protection`、`framework-integration`、`dock-seed`、`harvest-receive`、`close-hint`、`progress-bars` 全部通过 |

批量建造类套件（`building-kit` 22 件、`building-simulate` 12 框架 + 10 摆件）在夹具里加了 `energy.refill()`：它们测的是承载与拼装，一天 100 点体力建不完 32 件是设计意图而非缺陷；体力本身会撞到 0 这件事由 `energy` 用正式命令验证。

### 非本轮引入的失败（改动前基线同样红）

用 `git stash` 暂存本轮全部源码改动后复跑确认：

| 套件 | 失败项 | 关联 |
|---|---|---|
| `management` | 未建仓库不可入库、第三种植床需船二级、修复后开放第二种植床、船升级开放远海和第三种植床 | 仓库门槛与种植床解锁文案 |
| `building-ocean` | independent ocean foundation is legal、boat approaches before building | 远海独立地基的 `origin` 判定 |
| `sea-supply` | 甲板高度、三面环廊可行走、边缘点击内收、泊位水线共 8 项 | `main.tscn` 里未提交的浮店缩放/位移（transform 改为 1.867/1.777/1.649 且 y≈-18.1、z≈46.4） |
| `floating-shop` | 位置「正南 50 米」、甲板顶面 0.26 米等 5 项 | 同上（浮店被挪走并放大） |
| `submerged-neighborhood` | 六栋数量、前后层次、逐栋缩放共 10 项 | `main.tscn` 里未提交的水下景色改动（多了一个 `rear_slab2`、`rear_slab` 换了 transform） |

未在本轮处理，留在各自账本与后续任务里。

## 资产登记

- `UI-HUD-CORNERS-001`（角落 HUD）升到 v003：源文件新增体力条装配，旧哈希进 `previous_sources`，`current_source_index.json` 与 manifest 同步。
- `godot/src/bootstrap/main.gd`、`godot/src/building/building_service.gd` 的运行清单哈希按实际改动更新（不是批量刷新，仅这两份）。
- `ocean_sky.tres`、`floating_shop/gloss.tres` 的哈希变化经比对是 Godot 重存格式（`uid=` 与 `0.50`→`0.5`）和行尾，数值与内容未变，按实际字节登记。

## 待办

- 渔场的养殖生态（投苗、生长、收成）与正式美术。
- 体力与食物/上限成长（本轮未登记）。
- 上面三处非本轮失败。
