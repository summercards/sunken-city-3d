# SEA-FARM · 种植与日常照料

2026-10-29空间口径：固定种植格、DIY标准/小型培养土及蔬菜均可踩踏，由SEA-BUILDING/SEA-WORLD投影拥有；经过不浇水、不收获、不损坏作物。点击/气泡/E及种植时序保留。[通行交付](../../development/2026-10-29_walk_on_planters.md)。

[主文档中控](../../../GDD_V1.0.md#sea-farm) · [本功能账本](ledger.md)

设计修订：r1（2026-10-23 工程拆分，未更改玩法数值）。所属系统：经营。
范围来源：主文档保留的全局设计、拆分前文档与当前代码核对；下面明确区分目标与实现边界。

## 功能目的与边界

正式或规划入口：岸上种植菜单及地格交互。

本功能以这一玩家行为或工程交付闭环为管理粒度，内部操作作为设计条款逐项承接；不按脚本数量拆功能。跨功能前置和关系由主文档本行统一维护。

## 设计条款与验收标准

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-FARM-R01 | 默认最小循环固定开放太阳房1格与浅水平台6格，并允许SEA-BUILDING注册新增地格；旧ID迁移保留，圆弧农场6格冻结并隐藏。播种、浇水、次晨生长、收获和再种闭环。 |
| SEA-FARM-R02 | 每个游戏早晨07:00只推进一次已浇水作物；自然时间和休息走同一入口，缺水只停长。水壶12份，岸上免费补满。 |
| SEA-FARM-R03 | 买种先检查容量与余额，收获满包保留作物，番茄三茬后清空。 |
| SEA-FARM-R04 | 地格/作物 ID 稳定；保留 farm v2 快照与旧秒制存档迁移，旧已种作物可继续照料。 |
| SEA-FARM-R05 | 规则通过注入端口查询库存、设施和解锁资格，可在无 Main、无 Economy Autoload 的测试中执行。 |
| SEA-FARM-R06 | FarmField 注册地格；DailyShipping通过注入命令推进可访问地格并同步日历，主场景休息不得再额外调用 advance_day。 |
| SEA-FARM-R07 | 查询返回独立副本且无副作用；修改须走模块命令，调试生长调整也使用明确命令入口。 |

| SEA-FARM-R08 | 地格点击先显示播种/浇水/收获图标气泡，当前不可用动作灰显且点击给轻提示。播种只提供背包数量大于0的种子，多种时二级气泡选择；选定后才接近、扣1包播种。已浇水不可重复；成熟格必须明确选择收获后入包。 |
| SEA-FARM-R09 | 浅水平台六格改为独立木框培养土，稳定ID不变。新播生菜、番茄、南瓜首熟均为3个浇水日；播种土丘、第一日幼芽、第二日长叶、第三日成熟分别可见。旧已种计时保存原值，番茄续茬规则保留。 |
| SEA-FARM-R11 | 标准与小型动态培养土按稳定dynamic/实例ID增量登记，播种/浇水/生长/收获仍归Farm。摆件搬移只更新表现与操作点，不注销地格、不改作物/水/生长；有作物不得由建造拆回，空格拆回才注销。保存恢复先注册布局地格再恢复Farm |

## 所有者、接口与数据

状态/交付所有者：**Farm / FarmField 场景适配**。正式代码和资源入口：

- [godot/src/farming](../../../godot/src/farming)
- [godot/assets/data/crops.json](../../../godot/assets/data/crops.json)
- [godot/scenes/props/farm_plot.tscn](../../../godot/scenes/props/farm_plot.tscn)
- [godot/scenes/props/farm_cell.tscn](../../../godot/scenes/props/farm_cell.tscn)

读取上述所有者的公开查询，修改通过其命令或交互入口；事件由拥有该状态的对象发出。具体公开方法、信号和持久化字段见本账本的接口清单。原有稳定 ContentID、场景 ID 和存档键保持不变，重命名须另做迁移。

共享资源的所有权以被依赖功能为准。本功能引用它们，不复制背包数值、资产记录或其他功能规则。规划中的接口尚无实现时必须先补契约再编码。

## 当前实现与待完成边界

Farm 的规则端口保留；FarmField/FarmPlot 显式注入 Farm，不再访问全局 Economy。开垦、工具升级、品质和季节仍为规划。

2026-10-27 接口：configure；plant / water / harvest / advance_day / access_reason；register_plot / clear_plot_specs；plots_changed；farm v2 to_dict/from_dict。

详细所有权、状态转换与扩展方法见 [模块接口约定](../../architecture/module_contracts.md)；实测范围见 [框架交付记录](../../development/2026-10-27_modular_framework.md)。原目标中尚未实现的内容保持登记，不因架构拆分自动升级完成度。

## 2026-10-28 种植一律走种子二级

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-FARM-R09 | 空地点击「种植」**总是**打开第二级种子气泡，不因「背包里只有一种种子」跳过；二级只列出持有数量 > 0 的种子，每颗气泡下方标注「作物名 ×持有数」，顶部标「选择种子」。选中后才让角色走过去并播种。 |
| SEA-FARM-R10 | 二级菜单的气泡簇按自身包围盒夹进视口（含胶囊文字与标题），锚点靠屏幕边缘时最外侧气泡不得被切掉。 |

改法：`main._open_spot_bubbles` 的 `plant` 命令去掉 `owned.size()==1` 直种分支，统一 `_open_seed_bubbles`；`action_bubble.gd` 新增 `caption` 自绘胶囊；`world_action_bubbles.gd` 的 `open` 接受标题、`_place` 改为按包围盒夹取。

[本轮交付](../../development/2026-10-28_dock_seed_weather_asset_fix.md)。

## 验收入口

通过主文档定位本功能后执行账本列出的检查。正常、拒绝、取消/重复、存档恢复均按适用范围记录；真实渲染、听验和设备项单列。本次使用统一 runner 的隔离存档项目，不能直接拿玩家存档做测试。

## 来源与交付记录

- [拆分前完整主文档](../../archive/pre_split_20261023/GDD_V1.0.md)
- [拆分前功能计划](../../archive/pre_split_20261023/功能重做计划.md)
- [本次工程拆分记录](../../development/2026-10-23_feature_split.md)
- [godot/FARMING_DESIGN.md](../../../godot/FARMING_DESIGN.md)
- [godot/MANAGEMENT_LOOP.md](../../../godot/MANAGEMENT_LOOP.md)

## 2026-10-27 查询与恢复边界补强

state/spec/crop_def/plot_specs/crop_definitions 深副本；debug_set_growth 仅截图调试使用；modules31项覆盖。

[本轮实测记录](../../development/2026-10-27_framework_boundary_hardening.md)。

## 2026-10-27 当前最小循环与开始画面

本节及本轮修改条款优先于下方保留的历史范围。默认发布配置只开放家园生活循环；旧全功能验证须显式 `--full-world`，不能代替最小版本验收。接口、迁移及实测见[交付记录](../../development/2026-10-27_minimum_loop_and_title.md)。

## 2026-10-27 场景点击经营循环

最新规则见本轮新增条款；07:00结算和瓶盖命名优先于历史引用。[交付与实测](../../development/2026-10-27_plot_shipping_loop.md)。

2026-10-28：R08改用世界动画气泡；规则和注入端口不变。实测见[本轮记录](../../development/2026-10-28_pocket_action_bubbles.md)。


## 2026-10-28 HUD与笔记表现接线

种植入口归入海岛笔记的种植分类。UI读取crop_definitions、grow_days、yield_of、plot_specs、state、status_text与access_reason展示真实资料和地格状态；前往地格仍经plot_focus_requested，播种/浇水/收获继续在世界气泡中明确选择。规则和状态所有权保持Farm。

对应SEA-UI-R35–R38；[本轮交付](../../development/2026-10-28_corner_hud_notebook.md)。本功能整体状态与玩法边界保留。

## 2026-10-29 家园建造接入

| 条款 ID | 规则 |
|---|---|
| SEA-FARM-R11 | 建成种植区每次注册一格，外观与浅水六格相同，plot_id为dynamic/建造实例ID。FarmField通过增量register_node/unregister_node对接，操作气泡、选种、浇水、07:00生长、收获与笔记查询沿用Farm。存档先重建登记再恢复作物，旧固定地格ID保留。 |
| SEA-FARM-R12 | 原浅水平台六格为新局已拥有的种植区，无需再建造或付费；初次登记即生成独立空状态，首次存档包含`platform_plot`及`:1..5`。固定格与DIY格共用格内/侧边操作站位、选种、接近、浇水、生长与显式收获链路，船上点击也应正常上岸到位。重复登记只补缺失状态，不覆盖作物；缺少空格记录的旧档补空，已有作物品种、水分、生长、续茬和稳定ID保持。位置、外观、可踩踏规则及新局3包种子不变。 |

[交付与实测](../../development/2026-10-28_building_delivery.md)。

初始六格的登记与交互修订见[本轮交付](../../development/2026-10-29_initial_six_planters.md)。

## 2026-10-30 收获获得表现

| 条款 ID | 规则 |
|---|---|
| SEA-FARM-R13 | 气泡选择收获、E交互和正式FarmPlot.perform均在Farm成功结算后，经FarmPlot→FarmField的acted事件，把原返回的crop/reward交给SEA-MOVE播放举高收包动作；一次成功只播放一次。接近和长按准备阶段不得提前展示成功实物，满包/未成熟/取消不产生成功表现。奖励仍由Farm调用库存注入端口在原业务时点结算，动画完成/取消不得再次发奖或撤回，番茄续茬、成长、水分、收获数量和存档结构不变。 |

动作细节归SEA-MOVE-R14，实物副本归SEA-CROP-R14。种植与浇水也统一从成功acted事件触发表现，移除气泡命令与长按开始的重复播放路径。直接调用无场景Farm规则仍可独立使用，不依赖角色或动画。详见[本轮交付](../../development/2026-10-30_harvest_receive_animation.md)。

## 2026-11-01 作物按「天」结算：睡一觉就是一天

现场反馈：中午 12:00 浇水，第二天早上 06:00 醒来，看到的还是「今日已浇 · 还需 3 天」，非要等到 07:00（用户的原话是「到 12 点才更新」）才翻页 —— 和牧场物语、《星露谷物语》那种「睡一觉就换天」的手感不一致。

实测定位到两处：①睡觉流程里的生长调用被 `if not Scope.minimal()` 挡掉了，而默认就是 minimal 范围，**相当于默认配置下睡觉根本不推进作物**；②唯一还在生长的路径是 07:00 的出货结算（`DailyShipping.observe`），于是「换天」被绑在了「收货」这个和种植无关的钟点上。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-FARM-R14 | 生长以**日历日**为单位，睡觉醒来那一刻就换天 —— 玩家在 06:00 睁开眼睛时，作物的剩余天数、湿度与外观阶段必须已经是新一天的状态，不得等到 07:00 或任何其它钟点。实现口径：`FarmModel.advance_to_day(calendar_day)` 是唯一换天入口，自带水位线 `grow_day`（同一天只长一次，重复调用是空操作）；`Main._wake_at_home` 在全黑段用世界时钟的日调用它；07:00 的 `DailyShipping.observe` 也调同一个入口，因此「自然时间跨过 07:00」这条旧路径仍然长一天，且两条路径叠加不会长出两天。缺水仍停长（醒来只清湿度、不扣天数）。水位线进存档（`farm.grow_day`，v3），旧档缺它时按存档日起步，读档重进同一天不得再长。R02/R11 中的「07:00 生长」表述由本条取代为「醒来即生长」，07:00 只保留出货结算。 |

### 为什么水位线和 `day` 分开存

`FarmModel.day` 只是日历显示，会随读档/世界时钟被 `sync_calendar_day` 覆盖。如果拿它当水位线，「07:00 结算先跑、随后 sync 覆盖 day」会把当天的生长静默跳过。所以 `grow_day` 只由生长写入，`day` 只由日历写入。

### 验收

统一 runner 的 `farm-day-change`（23 项）：醒来那一帧 `remaining` 已减、湿度已清、状态文案已换、可见阶段已进；07:00 结算不重复；醒来立刻浇水不会被多长一天；不睡觉让时间跨过 07:00 仍长一天；缺水日不长；读档与旧档都不得重长。回归 `farming`、`minimum-loop`、`visual-plot-shipping`、`initial-planters`、`walk-on-planters`、`building-integration` 通过。见[本轮交付](../../development/2026-11-01_farm_day_change.md)。

## 2026-11-06 默认种植区全键盘闭环（专项与契约回归通过）

本节是当前输入口径，不重写历史结果。目标为默认可玩种植区不留鼠标专属入口；不据此开放开垦、工具升级、品质、季节等规划。整体仍为 `partial`。维护键位表与验收矩阵见[本轮记录](../../development/2026-11-06_keyboard_complete.md)，不作为游戏内教程。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-FARM-R15 | 固定六格与已登记的 DIY 地格沿原 Farm 命令链操作：靠近后 Q / Shift+Q 循环同源近距候选，锁定目标按住 E 打开该格菜单；`use_action_menu=true` 时空地、生长与 ready 成熟态都先打开选择，不直接收获。一级包含当前状态，种植始终进入仅列持有种子的二级，确认后才接近、计时并调用 `FarmPlot.perform`。二级 Esc 返回同格一级，一级 Esc 关闭，不扣资源、不偷做邻格业务。 |
| SEA-FARM-R16 | 键盘完成播种→浇水→房门/床睡眠换天→继续照料→成熟显式收获→再播种；缺种、已浇、满包等拒绝必须保留原状态并显示原因，水壶为空可走既有补水并浇水命令。成功仍由 Farm→FarmPlot/FarmField acted 链触发一次表现与结算，不因 E 持续按住、菜单确认、动画或返回重复扣种/扣水/发奖。生长沿 R14，出货沿 DailyShipping，不能另建键盘专用业务状态。 |

源码核实：`godot/src/farming/farm_plot.gd:86` 的 `interact()` 在 action-menu 模式下对 ready 同样发出 `interaction_requested`；`godot/src/bootstrap/main.gd:3623`、`:3651`、`:3770`、`:3785`、`:3795` 装配一级/二级/原命令。`keyboard-farm-loop` 脚本覆盖真实按键、六格切换、三次床铺睡眠及拒绝/取消，但使用位置、库存、水壶和初始日历夹具，不等于已验收整段旅行或所有品种/所有 DIY 布局。

最终专项：`20261106-200446-keyboard-release-regression-eae88a/report.json` 已记录 `keyboard-farm-loop` **606/0**、`keyboard-travel` **374/0**、`keyboard-panels` **80/0**，均 exit0、passed=true。`20261106-194828-keyboard-visual-travel-final-09cca9/report.json` 的真实渲染 `visual-keyboard-farm-loop` **617/0**、exit0，输出9张唯一截图；本轮画面目视审阅已检查 watered/full-bag/harvest-overhead/already-watered，确认无底部条和键位教程。完整绝对路径见[本轮总交付](../../development/2026-11-06_keyboard_complete.md)。同批 initial-planters247/0、walk-on-planters53/0、farm-day-change23/0通过；minimum-loop141/10、harvest-receive80/1及交互角标/标题旧断言失败保留为本轮过程解释。`20261106-201957-keyboard-contract-regression-888baa/report.json` 已接受适配后的minimum-loop147/0、harvest-receive92/0、interaction-reach35/0、dock-seed22/0，均exit0、passed=true，四项不再pending；主线程keyboard-final-contracts批次待附，不预记结果。整体仍partial，保留规划/设备等边界。
