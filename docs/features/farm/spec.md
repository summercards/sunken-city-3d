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
