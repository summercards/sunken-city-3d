# 模块与数据接口约定

[主文档总目录](../../GDD_V1.0.md#feature-control)

## 所有权

`bootstrap/main.gd` 是场景装配与跨功能流程编排入口。Autoload `Economy` 是经营服务装配及旧接口适配层；规则分别由功能服务拥有。新增规则写到所属功能，不向 Main、HUD 或 Economy 的转发方法加入业务判断。`GameState.mode` 是角色状态机的兼容投影；正式行为调用 `ActorController.request_mode`，调试恢复才使用 `reconcile_mode`。

| 功能 | 唯一状态所有者 | 输入接口 | 查询 / 输出 | 持久化 |
|---|---|---|---|---|
| 资源背包 | Inventory | add / pay / remove | count / to_dict / changed | capacity、counts |
| 建造 | ConstructionService | begin_site_upgrade / tick_sites | site_level / sites_changed / site_work_finished | site_levels、site_work |
| 设施 | FacilityService | build_facility | facility_unlocked / sites_changed | facilities |
| 仓库 | WarehouseService 内部 Inventory | deposit_materials / withdraw_material / construction_pay | construction_count / resources_changed | warehouse |
| 船级 | ShipService | upgrade_ship | ship_level / upgraded | ship_level |
| 目标 | GoalService | track_goal | goal_info / resources_changed | tracked_goal |
| 种植 | Farm | plant / water / advance_day / register_plot | state / plot_specs / crop_definitions / phase / crop_of / plots_changed | farm |
| 订单 | Orders | fulfill / reroll / tick | offers / offer_at / changed / fulfilled | orders |
| 打捞奖励 | SalvageRewards | commit_salvage | can_salvage / salvage_ready | salvage.left |
| 采集 | GatherField / GatherSpot | interact / from_dict | seconds_left / collected | gather，稳定采集点 ID |
| 漂流物与鱼群 | SeaProps | collect_crate / collect_fish | collected / fish_collected | pickups，目标 ID、位置、补货计时、随机流 |
| 角色 | ActorController | start_walk / approach / depart / cancel / request_mode | state_id / snapshot / state_changed | game，稳定姿态；不续接旧行动 |
| 航行 | Boat / WaterNavigation | sail_to / plan_route_to / invalidate | is_open_water / valid_route / segment_clear / remaining_route / arrived / navigation_blocked | game.boat |
| 镜头 | OrbitCam | resume_follow / suspend_follow / restore_follow | follow_enabled | 不恢复瞬态拖拽，读档重新跟随 |
| 潜水 | UnderwaterWorld / DiveAir | dive / surface / swim_to | phase / discovered_count / exited | dive.found、opened；氧气与中途动作不存 |
| 世界时间 | WorldClock | tick / rest_to_morning / wake_to_morning | query / changed / day_changed | time |
| 睡觉 | SleepCycle | advance / request；注入prepare、return_home | is_busy / woke | 不保存过渡态，使用time/game原快照 |
| 昼夜光照 | DaylightRig | capture / apply / adopt / suspend / resume | base_of / owns；读取世界小时 | 光照由time派生；09:00基准保留资源/面板配置 |
| 天气 | WeatherService | tick / set_weather | query / changed | weather |
| 存档 | SnapshotRegistry / SaveGame | register / write / read / restore | 结果字典 ok、reason、recovered | 带版本的模块快照 |

每个持久化所有者提供 `to_dict/from_dict`。经营部分为兼容旧档保留 `economy` 包装，适配层只委托各服务，不再实现施工、设施、船级或仓库规则。返回快照必须复制容器，不能将自己的状态字典作为跨模块写入口。旧兼容字段仅供存量调试工具；新增调用使用命令、查询和事件。

世界节点显式注入所需服务：建造牌与采集点读 ConstructionService；菜箱读 Farm；绞盘读 SalvageRewards；订单面板读 Inventory 与 Orders；海面与海底通过奖励回调入账。HUD 注入经营查询/命令适配器；样式适配器注入面板引用，不沿父节点寻找 Main。只读展示与业务规则分开维护。

## 状态与动作

通用状态机拥有显式转换表，先 exit 再 enter；入口内请求转换进入队列，单次最多处理 16 个转换，防止重入递归。状态以弱引用连接机器与上下文，退出场景后不遗留循环引用。

- 角色状态：ashore_idle、walking、approaching、interacting、boarding、boat_idle、sailing、diving、sleeping。
- 角色动作：walk、approach、board、disembark。表演动作：idle、walking、rowing、planting、watering、harvesting、swimming，分别独立脚本。
- 镜头状态：follow、manual。动作：pan、orbit、zoom。
- 潜水阶段：surface、enter、swim、exit。动作：enter、surface、finish_exit、swim、search、camera、diver_pose。

取消、目标失效和读档必须清除路径、完成回调、自动交互与待收取目标。完成交互释放自动按住，避免连续重复执行。模式切换由控制器驱动动画；动画不能反向结算物品或改变移动模式。

航路不是行动范围的替代。WaterNavigation 先判断起终点水域合法，再求解路径，最后逐段采样验证；Boat 的实际运动步继续用相同 segment_clear 接口。陆地行走沿 WalkArea 规划并检查步进位置。几何变动后调用 invalidate 重建导航缓存；模型阻挡的准确性仍由场景专项验证。

## 存档协议

当前 wire version 为 3，顶层包含 economy、game、gather、pickups、dive、salvage、time、weather。v0/v1 只给历史缺失/新增模块补默认值；未知内容 ID 在所属模块按当前内容表过滤，类型错误、负容量/数量、非有限数值和未来版本拒绝。

注册表先验证全部模块及世界位置，再调用恢复接口。恢复不购买、不结算奖励、不读写文件；完成后统一刷新镜头、区域表现和 HUD。读档回到稳定待机状态；离线时间冻结，施工/冷却存剩余秒，默认作物由07:00晨次推进，06:00醒来不结算。

存盘先写 tmp、读回验证，保存上一份有效备份，再替换主档。主档损坏时尝试 bak；未来版本主档不降级读取备份。启动默认读档，失败保护原槽位并关闭自动写入；可用显式新路径另存。不得以 `{}` 代替新游戏或恢复默认值。新游戏应由单独的明确命令创建新槽位。

这不等于验证过所有存储设备的断电行为；真实断电与发行平台文件系统仍需设备验收。

## 开发与验收

1. 从主文档定位 FeatureID，修改该功能 spec 和 ledger；新增功能先登记主文档。
2. 在自己的职责目录增加服务/状态/动作及配置，声明输入端口、查询、事件、存档字段和迁移默认值；依赖由装配层注入。
3. 先跑不带 Autoload 的模块测试，再跑相关场景集成；运行统一使用 `scripts/run_verification.py`。新增存档模块必须覆盖坏数据不改变现场、重复/取消与跨进程恢复。
4. `python scripts/check_architecture.py` 阻止业务重新访问全局和正式代码依赖测试目录。`python scripts/check_feature_contracts.py --sync` 后再跑无参数检查。
5. 资产通过 `assets/registry/ledger_index.json` 路由到类型分账本；功能账本与资产账本分开。源授权、导出与正式接入未验证保持 pending。

居民、养殖、任务、音乐和音效仍是主文档登记的规划功能，已有独立文档和账本；未来实现沿上述接口接入，不创建空运行模块伪装成完成的玩法。

## 查询副本与恢复事务（2026-10-27补强）

Farm 的状态、地格表和作物表查询，以及 Orders.offers/offer_at 均返回深副本；查询未知内容不得创建状态。生产调用不得直接访问种植 specs/crops/states 或订单 slots。调试夹具保留兼容字段，新增代码不沿用该入口。

注册快照时传入 event_sources，包含该模块及其内部会发事件的状态所有者。注册表保存弱引用，全部恢复期间屏蔽信号并拒绝写盘，随后恢复每个源原有的信号屏蔽状态，发出 restored；经济适配器再通知展示刷新。新模块不得依赖恢复过程中的中间事件，也不得在 apply 中执行奖励、购买、await或文件IO。

v2校验覆盖必填嵌套记录、订单状态互斥、拾取ID唯一与next_id、64位随机流、作物计时语义和直接恢复版本。旧版缺拾取状态用 `{reset:true}` 明确重建，空v2对象拒绝。仅有未来备份同样禁止创建旧版本主档。

[专项实现与证据](../development/2026-10-27_framework_boundary_hardening.md)。

## 当前最小版本适配（2026-10-27）

主文档的最小循环范围覆盖历史完整配置。新增公开边界：`PlayScope`开放规则 → Main注入Zones/WaterNavigation/SeaProps；`DailyShipping.observe(clock)`按08:00水位线调用注入的Farm命令并结算自有cargo；`InventoryTransfer.move`预检后双端发布事件；WarehouseService.deposit/withdraw仅管保管仓库。开始画面由StartScreen事件与TitleCamera.begin/blend/finish组成，Main只负责暂停及交还会话。快照v3必须含economy.daily_loop；旧版由decode迁移，当前缺字段拒绝。[实现与证据](../development/2026-10-27_minimum_loop_and_title.md)。


## 2026-10-27 场景点击经营接口

- FarmPlot.interaction_requested(plot_id) 只请求选项；HUD 的 PlotActionPanel 查询 Farm/Inventory，并经注入的 perform(action,crop) 发命令。FarmPlot.perform 复用唯一 Farm 写入者及 acted 事件，Main 校验岸上/距离并播放动作。
- ShippingBox 只发 opened；HUD 调用原 DailyShipping deposit/withdraw，箱子无第二份库存。独立保管仓库不参与晨间销售。
- DaySchedule 只声明07:00边界，不持有时间；WorldClock、DailyShipping、SaveSchema共用。保留 coins、plot_id、daily_loop 快照ID；版本3无新增必填字段。
- CultivationDeck 独立场景只管木板外观，六格 FarmPlot 管木框/土壤/生长表现，FarmModel 管作物。箱子模型仍是 SEA-SCENE-SBR-COOLER，摆位在实例清单，点击代理在区块Objects。

2026-10-28：睡觉点只发命令；23:00自动睡觉由SleepCycle调度，WorldClock唯一推进到06:00。过渡期间SnapshotRegistry.busy_query拒绝保存，醒后统一保存稳定姿态。光照、时钟、经营晨次互不复制状态。

2026-10-28 服务口袋：`PocketService` 通过注入的 `query(service)` 读取背包、服务库存、真实容量、待结算金额和种子目录，只发出 `operation_requested(id, action, amount)`；HUD适配层分派到原DailyShipping、WarehouseService和Farm命令。`DailyShipping.query()`新增`capacity`、`slots_used`只读字段，存档无新增字段。视图仅保存页码/选中态，不保存第二份物品状态。[本轮记录](../development/2026-10-28_service_pockets.md)。
