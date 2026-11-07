# 模块与数据接口约定

## 2026-10-29 角色碰撞与三维空间

SEA-MOVE拥有CharacterMotor的物理执行和Character表现生命周期；ActorController仍唯一写角色状态。Main物理帧是生产唯一tick驱动，原_update_walk仅作兼容转发，渲染帧不重复推进。CharacterBody3D胶囊(0.22m/1.30m)只碰人物地面层256，人物层512；船与潜水仍经原系统，状态切换管理启停。

SEA-WORLD装配GroundSpace，读取WalkArea表面声明；它只持有派生物理体/NavigationServer3D私有map，释放时清RID，不写源布局。SEA-BUILDING通过既有geometry_changed回调请求刷新，不修改BuildingService/Farm规则。动态中心域body_radius=0不重复内收。area_at、surface_point和三维route供移动、交互与世界存档适配使用；旧XZ接口留给旧工具。

表现端口register_action/play_action/cancel_action及started/finished/cancelled只描述动作，不能结算奖励。2026-10-30：FarmPlot成功acted事件统一触发play_farm_action(event,payload)，harvesting消费crop上下文播放2.4秒举高收包；play_receive_item(crop_id)可复用表现，播种/浇水仍1.1秒。取消/上船/潜水/睡眠/恢复/替换清动作、临时实物、包盖与袖长。架构边界见[框架交付](../development/2026-10-29_character_physics_framework.md)与[收获交付](../development/2026-10-30_harvest_receive_animation.md)。

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
| 作物品种 | CropCatalog（无状态，只读表） | reload（仅供工具/测试） | ids / has / get_crop / definitions / stage_labels / model_scene / stage_for_progress / validate | 无（品种是内容，不是状态；地格状态仍归 Farm） |
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

当前 wire version 为 4，顶层包含 building、economy、game、gather、pickups、dive、salvage、time、weather。v0/v1 只给历史缺失/新增模块补默认值；未知内容 ID 在所属模块按当前内容表过滤，类型错误、负容量/数量、非有限数值和未来版本拒绝。

注册表先验证全部模块及世界位置，再调用恢复接口。恢复不购买、不结算奖励、不读写文件；完成后统一刷新镜头、区域表现和 HUD。读档回到稳定待机状态；离线时间冻结，施工/冷却存剩余秒，默认作物由07:00晨次推进，06:00醒来不结算。

存盘先写 tmp、读回验证，保存上一份有效备份，再替换主档。主档损坏时尝试 bak；未来版本主档不降级读取备份。启动默认读档，失败保护原槽位并关闭自动写入；可用显式新路径另存。不得以 `{}` 代替新游戏或恢复默认值。新游戏应由单独的明确命令创建新槽位。

这不等于验证过所有存储设备的断电行为；真实断电与发行平台文件系统仍需设备验收。

## 开发与验收

1. 从主文档定位 FeatureID，修改该功能 spec 和 ledger；新增功能先登记主文档。
2. 在自己的职责目录增加服务/状态/动作及配置，声明输入端口、查询、事件、存档字段和迁移默认值；依赖由装配层注入。
3. 先跑不带 Autoload 的模块测试，再跑相关场景集成；运行统一使用 `scripts/run_verification.py`。新增存档模块必须覆盖坏数据不改变现场、重复/取消与跨进程恢复。
4. `python scripts/check_architecture.py` 阻止业务重新访问全局和正式代码依赖测试目录。`python scripts/check_feature_contracts.py --sync` 后再跑无参数检查。
5. 资产通过 `assets/registry/ledger_index.json` 路由到类型分账本；功能账本与资产账本分开。源授权、导出与正式接入未验证保持 pending。

历史规划列表中的居民现已进入七人NPC部分实现阶段，当前所有权见下方2026-11-07契约及其下午补充；其余功能以各自账本为准。已有独立文档和账本不等于验收完成，禁止空模块或结构通过伪装玩法完成。

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

## 2026-10-29 独立家园拼接建造

SEA-BUILDING的BuildingService唯一写入动态布局与施工时间；Main只组合服务、Inventory支付端口、BuildingBoundary资格/空间查询和BuildingWorld投影。独立文档及账本在docs/features/building。固定ConstructionService仍归SEA-BUILD，Farm仍唯一写作物。

SnapshotRegistry新增整份snapshot_validator；在任何apply前校验快照布局中的角色/船位置，避免查询旧世界误拒绝新平台上的角色。building第一个恢复，BuildingWorld显式重建投影和地格登记（恢复期间信号被屏蔽），随后恢复Economy内Farm，最后恢复game姿态；不以中间changed事件串接恢复。v0-v3由decode显式补空building。

UI的owned_modal_query/close/input为独立手册和预览提供注入的模态生命周期，旧系统菜单每帧刷新不能取消此状态；Esc关闭建造，F9仍进入原确认流程。

## 2026-10-29 作物品种独立域（SEA-CROP）

依赖方向单向：`SEA-FARM → SEA-CROP → SEA-ASSET`。CropCatalog / CropView **不得**反向引用 Farm、地格状态或场景节点。

| 边界 | 规则 |
|---|---|
| 品种数据 | `godot/assets/data/crops.json` 唯一源，由 CropCatalog 解析；Farm 只查询，不缓存第二份可写副本 |
| 阶段判定 | `CropStage.stage_for_progress(progress, ready)` 是唯一映射；FarmPlot 只转交，不自己写阈值 |
| 表现 | `CropView` 按 `model` 加载 `scenes/crops/<id>.tscn`，切换阶段只改 `visible`，不建网格、不改状态 |
| 缺失降级 | 模型或阶段节点缺失时保留上一阶段并只警告一次，不崩溃、不留空箱 |
| 资产 | 主记录在 `ledgers/crops.json`（domain=crops），不写入 `scenes.json` |

跨进程契约的断言入口：`crops`（隔离测试，不加载 main）、`visual-crops`（12 阶段真实渲染）、`structure`（契约与哈希）。

2026-10-29：`BuildingWorld.contact_rects()`只读派生完工木板占地，经Main组合到`WaterSurface.set_runtime_contact_rects()`；水面只维护表现用24项上限的矩形通道，不写建造布局。两方案通过`runtime_water_contacts.gdshaderinc`合并静态岸线与动态接触距离，保留各自泡沫风格；布局同步/恢复更新派生数据，未完工虚影不接水线。[验证](../development/2026-10-29_deck_draft_pole_placement.md)。

2026-10-29种植区可踩踏：`BuildingCatalog.blocks_actor()`声明摆件的人物阻挡资格，`BuildingSpace`与`BuildingWorld`按同一声明派生通行和恢复资格。固定六格及DIY两种培养土默认不挡人，木板外缘保护继续生效；建设占位不等于人物阻挡。Farm/Crop仍唯一负责作物状态，人物穿过不发种植或收获命令。[当前契约与实测](../development/2026-10-29_walk_on_planters.md)。

2026-10-29初始六格：Farm.register_plot幂等补缺失空状态，首次存档即拥有六格，不覆盖旧作物。BuildingWorld按原固定格实际矩形派生操作点，固定与DIY共用BuildingSpace.operation_points_for；ActorController的操作点预筛从所属泊位开始处理船上接近，最终走原靠泊校验。未建立第二份初始布局或改存档ID。[本轮契约与实测](../development/2026-10-29_initial_six_planters.md)。

2026-10-30开放海域资源：SeaProps.sync_population(clock_query, boat_position)消费唯一日历和船位，内部OceanPopulation拥有64m网格槽位/缺失截止时间，远格卸载不重置采集。WaterNavigation.is_open_water为合法水域查询。07:00统一日更鱼/木，浮木独立6–10游戏小时补回；pickups.ocean可选存档扩展由SaveSchema恢复前校验。成功collected/fish_collected事件只驱动PickupProgress.receive的原背包图标上飘，表现不结算奖励。[当前证据](../development/2026-10-30_ocean_pickups.md)。

## 2026-10-30 模块化建造内容与楼层

| 所有者/接口 | 契约 |
|---|---|
| `BuildingCatalog` / `building_kit.json` | 目录拥有稳定配方ID、Prefab、尺寸、profile和启用标记；active=false仅退出新建，不删除旧定义。旧三配方兼容。 |
| `BuildingService` / `AssemblyRules` | 唯一布局写入者；规则以副本校验承载、挂点、同高度重叠及依附拆除，保存稳定support和py高度。未知/缺失支撑拒绝，不把其当种植区。 |
| `BuildingWorld` / `AssemblySurfaces` | 从完工布局派生模型、墙/门阻挡、楼梯坡面与二层表面；输入WalkArea/GroundSpace，不保存第二份楼层布局。 |
| `BuildingController` / `BuildingBook` | 目录分类分页、R旋转/U楼层/Shift精细与预览；实际支付仍经Service，输入不直接写布局。 |
| `KitVisual.action_requested` | 资产只发`storage`/`water`语义信号；Main组合到共享仓库与Farm.refill。灯/风车等表现只在组件内维护临时渲染状态。 |
| `WalkArea.open_surface_junctions` / `WalkAction` | 显式坡面接缝避免生成封口边界；三维路线沿实际胶囊执行，路径中间引导容差不改变终点契约。 |

首批限制：基础层/二层，不开放第三层、竖梯、风力发电或风铃音效。业务与技术验证分别记录在[本轮交付](../development/2026-10-30_modular_building_kit.md)。

## 2026-11-02 新旅程与角色定制

- `AvatarProfile`唯一拥有已提交`profile`快照；`query()`深拷贝，`commit(draft)`验证并发`changed`。UI只编辑独立草稿，`AvatarSession`协调提交/整局写盘；写失败回滚档案并保留预览和可重试草稿。
- `AvatarCatalog`读取稳定槽位/选项ID，`AvatarVisual`只接收appearance，不访问Main/Economy；保留角色功能根、碰撞、肩肘髋膝及原动作采样。未知ID保留于档案、表现采用槽位默认值。
- `AvatarEditor`只发preview/save/cancel/rotate意图。`AvatarSession`注入profile/player/camera/save Callable，`ArrivalFlow`注入放到真实泊位和交还标题相机的Callable。独立目录不反向引用bootstrap或经营服务。
- 根存档保持v4，新增`profile.version=1`，缺失profile仅在decode及直接restore入口明确迁移为已完成旅人；已有但损坏profile必须拒绝。SnapshotRegistry注册profile并屏蔽恢复中间信号，最终由_after_restore统一投影外观。
- `design_refs`只预留稳定设计ID，`extensions`保留扩展元数据，完整profile限制16KiB；当前没有图案创作/外部文件加载/分享实现。扩展设计仓库独立拥有纹理，档案只引用。

独立设计与台账：[角色档案](../features/avatar/spec.md)、[码头开场](../features/onboarding/spec.md)；[本轮证据](../development/2026-11-02_avatar_and_arrival.md)。

用户指定比例修订：AvatarDimensions唯一拥有新基体的肩/肘/髋/膝静止尺寸，Character建节点与ItemReceive腕部求解共用；层级和生命周期保持，获物2.4秒/1.60米顶点与奖励边界保留。AvatarVisual只改网格；比例不写碰撞和玩法根。指定参考由SEA-AVATAR-R13管理。

## 2026-11-02 四肢连续网格与骨骼

AvatarLimbSkinning（Skeleton3D）拥有4张连续封闭索引网格、Skin绑定和21骨姿势；AvatarVisual只传入稳定外观选项，shader负责袖口/裤脚/鞋底分色。原动作采样器不改网格或奖励，继续输出肩肘/髋膝不可见控制，Character在采样完成后一次sync_visual_pose，LimbSkeleton同步控制骨和独立伸长辅助骨，GPU完成变形。辅助骨不向下一旋转控制骨传递非均匀缩放，避免长臂获物姿势剪切。

四肢网格只在构造时生成，换装不重建骨骼/顶点权重，运行期不以CPU逐顶点改网格。deformed_points为只读验收/量测端口，不在生产_process中调用。保存仍只有profile稳定ID，恢复重置控制姿势并投影骨骼，不持久化临时蒙皮姿态；碰撞和根位移所有者不变。[独立契约](../features/avatar/spec.md)与[本轮证据](../development/2026-11-02_avatar_limb_skinning.md)。

## 2026-11-07 独立 NPC 与商店模块契约（SEA-RESIDENT / SEA-SHOP）

`NpcService` 是七名固定 NPC 的唯一运行状态所有者，正式目录为 `godot/src/npc/`。它独立维护身份、日程意图、对白会话、个人剧情、玩家好感、NPC-NPC 关系边、住所归属、请求状态和 `npc` 存档快照；不访问 Main/HUD/Economy/Shop 私有字段，不持有背包、作物、建筑、船、时间或导航状态。`ShopService` 是花店与综合商店的独立规则所有者，目录为 `godot/src/shop/`；它只通过 Inventory 端口买卖，不读取 NpcService 好感/剧情。

| 端口 | 提供方/消费方 | 契约 |
|---|---|---|
| `WorldClock.query()` | SEA-TIME → NPC | NPC 只读世界日、小时、星期，不推进时间 |
| `WeatherService.query()` | SEA-WEATHER → 装配层 → NPC | NPC 只读天气标签，不修改天气 |
| 目标锚点/动作意图 | NPC rules → NpcWorldPresenter → SEA-MOVE / SEA-WORLD | R09通过公开世界站位端口消费anchor_snapshot，当前rooftop_ranch草地、后续可插住所但无SEA-RESIDENCE前置；GroundSpace/WalkArea提供surface_point/path_between，CharacterMotor执行；无路尝试home，仍失败则停止/隐藏并报fallback，不造房/传送 |
| `interact(npc_id)` | SEA-INTERACT → NPC | 交互层转发目标，不把 NPC 内部状态写到热点节点 |
| `InventoryGiftPort` | 装配层 → Inventory / NPC | 先预检物品并由 Inventory 唯一扣除，成功事件才结算好感 |
| `vendor_requested(npc_id, shop_id)` | NPC → SEA-SHOP | NPC 只声明经营者与商店 ID，不读取商品/价格/库存 |
| `buy(shop_id,product_id,amount,request_token="")` | 独立ShopPanel → SEA-SHOP → Inventory | ShopService校验报价，仅调用注入exchange(costs,gains)；主线程补齐真实原子Inventory，不用分步pay/add/remove或退款模拟 |
| `purchase_completed` | SEA-SHOP → 装配层/NPC 可选消费 | 只携带公开稳定 ID 和结果，不复制购买状态 |
| 业务结果事件 | Farm/Build/Ship/Salvage/Quest → NPC | NPC 只消费公开稳定 ID 和结果，不复制业务状态、不发放其他模块奖励 |
| `SnapshotRegistry` | SEA-SAVE → NPC | 注册/验证/apply `npc.version=1`；恢复期间屏蔽中间事件，瞬态对话和移动路径不存档 |

NPC 的关系图查询、对白查询和日程查询都返回副本。Shop 的目录和购买快照同样返回副本。UI 只能发送 `meet`、`start_dialogue`、`choose_dialogue`、`request_vendor`、`buy` 等意图；不能直接改 `affinity`、`edge_deltas`、`seen_events`、`schedule`、商品价格或库存。关系与对白规则见 [SEA-RESIDENT 设计](../features/resident/spec.md)，商店规则见 [SEA-SHOP 设计](../features/shop/spec.md)，施工顺序和门禁见 [NPC 模块施工文档](../development/2026-11-07_npc_module_framework.md)。

### 下午补充（历史）：七人角色、独立住所与装配验收边界

- **依赖分支**：GDD已先登记SEA-RESIDENCE→WORLD/ASSET/INTERACT，无反向NPC依赖；SEA-SHOP→INVENTORY/CROP/INTERACT，无RESIDENT硬依赖；NPC增加RESIDENCE/AVATAR输入，UI/SAVE保持装配协议而非新增前置边。候选图只读静态检查无环，不是正式结构/运行专项，不改其他功能前置。
- **代码与角色所有权**：实际 `src/npc` 包含 `npc_service/catalog/relationship_graph/schedule_resolver/dialogue_runner/save_codec` 规则，以及 `npc_panel/session/world_presenter/world_ports/interactable/actor/accessories`。NpcActor程序化复用AvatarCatalog/AvatarVisual/Character及骨骼动作，7独特配件分别为signal_spool、seed_pouch、diving_goggle、joint_pencil、lantern_badge、petal_visor、stock_clip。独立NPC外观快照只供表现，不读写玩家AvatarProfile或保存玩家profile副本；外观参数完整性与真实效果需npc-appearance和真实渲染。
- **住所唯一真值**：新增独立[SEA-RESIDENCE](../features/residence/spec.md)拥有resident_harbor及7座50m²正式TSCN、各自床/桌/灯、两商店空间、统一GroundSpace和35生活Marker。main新增实例参考(38,0,-32)，坐标可调整，不覆盖其他用户摆位。residences.json版本2是稳定ID/Marker节点映射，不是坐标副本或npc存档版本。anchor_snapshot返回position/zone/ground/ground_space/residence_id/kind的容器快照，空间对象仅作只读服务引用，不可存档；NPC world不得自己生成房屋/地面。
- **会话与职业**：NpcPanel→NpcSession→NpcService，Session仅持瞬态页签/确认/反馈，不结算业务；session_id/NPC戳拒绝旧按钮，取消/读档/场景销毁清理。当前NPC独立面板打开即模态，包括日常对白；Main统一屏蔽世界输入与睡眠/室内/标题流程。花序/货架发vendor_requested后进入独立ShopPanel；其余五人发action_requested(npc_id,action_id)，依次为ship/cultivation/salvage/building/archive，接收方属于外部功能，不以按钮存在宣称功能已接通。
- **端口生命周期**：NpcService.configure接受clock_query/exchange/remove/count/result_port对象命名方法，规则拒绝捕获闭包并持弱引用；world端口同样需有效命名查询。Main只装配，不加入NPC/商店业务判断。请求acknowledge_request验证result_tag后仍交付库存，不能用外部success字段伪造完成；result回调仅通知。主线程须补齐真实Inventory.exchange并接通这些端口，本分支不改代码。
- **商店所有权**：独立ShopService/Catalog/Panel；shops.json两目录11商品，其中三作物种子仅引用CropCatalog的seed/seed_price，名称描述取ItemDB。quote纯查询、返回副本；目录坏数据全表拒绝。exchange失败数量/排列/信号全不变，成功全量提交后发信号。token去重仅实例内120秒/最多256条，含拒绝、不续期，同token异参拒绝，空token独立请求；重配/重建/过期/淘汰不保证去重，不持久化或承诺跨进程exactly-once。
- **严格durable**：npc.version=1只存graph（met/affinity/last_talk_day/gift_week/gift_count/birthday_gift_day/last_gift_day/edge_deltas）、seen_events事件记录字典、choice_flags、request_states。精确字段/ID、有限整数、剧情路径/前置日期/请求来源、choice_flags及边变化可追溯重建，全部以NpcSaveCodec.validate为准；from_dict先验后替换，坏档不改现场。旧无npc只在明确migration补默认，不将已有坏npc当旧空档；主线程对齐SaveSchema/SaveGame/Registry并在全量恢复后刷新world。保存取消未提交会话，不存路径/临时目标/profile/静态商店目录/住所布局。
- **生日与周**：day从1开始，week=str(int((day-1)/7))，生日年内日=(day-1)%112+1；先生日专用1次再当周普通2次，生日当天礼物均乘3，roundi后clamp[-80,120]再限制affinity。NPC周年与HUD365日显示不是一份日历副本。
- **验收职责**：静态数量核对7人/21个人+4关系事件/84日常对白/9边不等于运行。主线程真实接线并跑npc-rules/shop-rules/npc-world/npc-appearance/residence及真实渲染、save/integration；核实名称是否注册再记录实际入口。本分支未运行sync/Godot/测试，不新增runner/registry，不编造通过数，三域保持partial。结构、运行、视觉、设备和未验分别回填[施工记录第11节](../development/2026-11-07_npc_module_framework.md#11-主线程实测回填占位)，不以隔离测试替代整局证据。

## 2026-11-07 潜水独立地图与稳定会话契约

本节覆盖上方潜水所有权表的历史口径，对应SEA-DIVE-R06–R11、SEA-BOOT-R07、SEA-WORLD-R26、SEA-SAVE-R19；四功能状态仍 `partial`，不改变其它模块所有权。

| 所有者 / 端口 | 现行契约 |
|---|---|
| Main → DiveSession | Main只装配轻节点及 `configure(host)`、`source_query(position)`、`give_rewards(reward)->bool`（Inventory.add_all原子端口），give_resource仅旧工具兼容，无常驻地图几何。生产来源由岸上current_zone或船上实际TSCN泊位XZ最近的已安装/Scope启用区块解析；覆盖全海平面，不是有限半径或JSON参考位。 |
| DiveMapCatalog | `source_ids / get_map / validate`提供静态来源→唯一map_id/scene_path/label/chest_id_base，查询返回副本；9来源含zone3/4规划，不持实例/进度，不自动恢复未安装海面区块。 |
| DiveSession | 唯一全局潜水进度与共享DiveAir所有者；`dive / enter_map / surface / abort_to_surface`编排切图，`swim_to / cancel_navigation / toggle_lamp`转发到当前runtime。`depth_changed / zone_changed / air_changed / message / exited`向外发布；active/switching/source_id/map_id/runtime供诊断，不作为外部私有写入口。 |
| UnderwaterWorld / maps/*.tscn | 只拥有当前地图阶段/动作、内容/碰撞、潜水角色、相机/本地WorldEnvironment/HUD；复用旧region的不同组合/出生点/宝箱/鱼群子集，非9套新美术。`setup([], local_environment) -> bool`在ready后执行，检查结构/几何归属/出生点完整入水段及宝箱站位，失败不能继续运行半初始化图。 |
| Main生命周期 → SceneTree | preflight通过才把同一Main移出树缓存，不free/重建/读档；稳定会话临时移到root，current_scene切唯一runtime。海面时钟/天气/经营/自动存档暂停，外部信号与可见性暂存；挂起退出保留save_registry/端口。上浮或setup失败回滚同一Main，卸载海底，恢复原船人姿态/模式/相机/环境及必要GroundSpace/表现端口，不重跑Main._ready；正式结束才清理。 |
| SnapshotRegistry / SaveGame | 原 `dive` 项注册DiveSession；active或switching均纳入busy_query，直接SaveGame.write也须拒绝，不只UI门禁。上浮返回不调用SaveGame.read/restore；正常稳定海面才允许写盘。 |

根v4仍为 `dive:{found:int[],opened:int[]}`，不换key、不增map_id必填字段；zone1的0..4不变，其余固定基数100..800加局部子集，全局唯一、不重新编号。DiveSession返回合并当前图，`from_dict`清空全局旧进度后全量覆盖，未加载地图与未知ID必须保留，不能套用上方通用未知内容过滤概述。runtime仅投影本图已知ID，重复开启不得重发奖励。DiveAir恢复冷却由稳定会话跨图持有，卸载或换图不重置，氧气/冷却/中途动作不新增持久字段。

> 2026-11-08 起「默认潜水仍屏蔽」已被下方同名章节取代，其余挂起/恢复/存档规则继续有效。

默认潜水仍屏蔽（历史）；旧underwater_world.tscn保留但不常驻运行，旧build_underwater.py只用于工程外候选，不覆盖正式maps/Main。SunkenCity及其海床不参与此次潜水改造。统一runner已登记 `dive-maps / visual-dive-maps`，本分支未执行任何验证或sync/check；运行/视觉结果 **pending，待父线程补充**。[完整机制、九图配置与回填表](../development/2026-11-07_dive_map_switch.md)。

## 2026-11-08 潜水重新开放与世界对齐“家园海底”契约

本节覆盖 2026-11-07 节的“默认屏蔽潜水”与“仅 9 条来源”两条口径，其余挂起/恢复/存档规则不变。对应 SEA-DIVE-R15–R19。

| 所有者 / 端口 | 现行契约 |
|---|---|
| PlayScope → 潜水入口 | 默认范围内 `dive / lamp / rise / descend` 可用；`build / hook / camera / orders / salvage` 仍锁。HUD 潜水按钮与角落菜单在最小循环保留潜水入口，`--full-world` 不再是开启潜水的前提。 |
| DiveMapCatalog | `source_ids()` 仍 9 条海区来源；追加 `home_map()` 与 `is_home_water(point, anchor)` 提供**世界对齐**目标 `dive_home_seabed`（`scenes/underwater/sunroom_region.tscn`）。家园不占来源 ID，`validate()` 一并校验其唯一 map_id/scene_path。锚点由调用方给实际位置，catalog 不写死坐标。 |
| Main → source 解析 | `_dive_source_at(point)` 先判家园水域（水平 60 米内，锚点 = `zone1 → 太阳能木屋` 的 `global_position`），命中返回 `home_seabed`；否则维持岸上 current_zone / 船上最近已安装泊位。`_on_dive` 用**角色真实落水点**（岸上取人、船上取船）而不是固定船位。 |
| DiveSession → 世界对齐地图 | 目录 `world_aligned=true` 时必需节点为 `Camera / WorldEnvironment / Water`（非 `Regions/Deco/Chests/DiveCamera`），跳过旧 `setup()` 与 swim 数据预检，改为 `begin_dive(surface_point) -> bool`；`dive(point, source)` 把落水点交给该图。其余编排、进度合并、`_commit_return` 恢复路径完全共用，不新增第二种返回逻辑。 |
| SunroomRegion（家园海底） | `begin_dive` 先进入 `enter` 占位，等物理提交（垂直射线打到海床）后选点转 `swim`；`surface` 走 0.55 秒可见上浮后发 `exited`。对外暴露 `swim_to / cancel_navigation / toggle_lamp / surface / abort_to_surface`、`depth_changed / zone_changed / air_changed / message / exited`、`to_dict / from_dict`（无宝箱时为 v4 空表）、`chest_count / discovered_count`。氧气复用 `DiveAir`，不新增持久字段。 |

信号恢复规则：从潜水返回时只重连**仍存活且尚未连接**的脚本信号；Terrain3D 的原生 `region_map_changed / height_maps_changed` 随重新进树自动恢复，手工再连会报 already connected，故整类跳过。

最终证据：`D:/projects/sea-work/verification/20261108-055128-dive-home-seabed-signed2-00d74f/report.json`，九入口 exit0/PASS、合计 1270 项 0 失败。[机制与踩坑](../development/2026-11-08_home_seabed_and_dive_reopen.md)。

## 2026-11-07 19:40 NPC世界站位覆盖（历史）：天台暂驻，住所deferred

本节覆盖前文下午“NPC增加RESIDENCE输入”“住所唯一真值”对本轮的强制接入要求，保留历史，不改所有者。用户要求“先不用做他们的住所，先全部放到那个天台草地上去”。

- **依赖**：移除SEA-RESIDENT→SEA-RESIDENCE，其他NPC依赖保留；Shop仍仅依赖INVENTORY/CROP/INTERACT，不以NPC或住房为硬前置。NPC/Shop规则、会话、库存与durable所有权不变。
- **R09公开端口**：NpcWorldPresenter / NpcWorldPorts通过公开世界站位端口消费anchor_snapshot，当前rooftop_ranch草地，未来可插住所provider但不强制加载住所。GroundSpace/WalkArea只读空间查询、CharacterMotor执行及fallback/停止规则不变；不造屋、不插值穿墙、不存另一份世界坐标。
- **R13天台站位**：正式NPC现场为rooftop_ranch，用户手摆root下NpcStations提供35个局部Marker（7人×Home/Work/Social/Rest/Door）；随scene/root实际变换取得站位，不冻结绝对世界坐标、不重跑作者工具覆盖手摆。Home/Rest等稳定语义仅为当前草地站位，不代表物理住房。七人当前无物理房屋，UI仅显示“暂驻天台”，七人身份/配件/剧情/五职业及两商店保留，NPC独立、Shop独立。
- **住房生命周期**：SEA-RESIDENCE登记partial（历史制作资源留存），本轮deferred用户暂停，不新增开发、不删除R01–R07、不将通过签退。截至本轮收尾，Main中resident_harbor实例及zones/scope绑定已移除，源资源保留；参考(38,0,-32)只历史、不作本轮前置。用户手摆root与其他旧transform未动；本分支仅记执行结果，不改代码。
- **证据与回填**：`D:/projects/sea-work/verification/20261107-192319-seven-npc-release-a6fb1b` 的release integration/save已PASS只属住所版历史，不证明当前天台版通过。19:40时R13/路线/交互/商店/save/integration/真实渲染pending主验；随后已验、失败和仍待主验统一以文末性能收尾及[施工记录第13节](../development/2026-11-07_npc_module_framework.md#13-性能优先收尾与当前证据)为准，不将历史住所版PASS转成天台结论。

## 2026-11-07 时钟单推进与 NPC 增量同步（七人全天台阶段历史；性能原则延续）

- **SEA-TIME-R12**：WorldClock仍唯一拥有时间；Main删除第二次clock.tick，只调sleep_cycle.advance，由其内部至多tick一次并cap23:00睡点，暂停/睡眠不推进；06:00醒与07:00晨次不变。clock.changed→Main._on_npc_clock_changed→Presenter.notify_world仅传小型世界字典，信号栈不解析日程、不采锚点、不寻路。
- **SEA-RESIDENT-R14**：Presenter0.5s检测日/分钟、任意日程from/to和conditions.hour_from/hour_to及21:30边界、天气、关系/剧情、手摆Marker/root/support变化；变化才全量同步，每batch仅1次anchor_snapshot。support cache随active/surface/revision和变换失效，idle不逐physics投影；force读档/恢复刷新及失支撑停止/隐藏、fallback保持，不以缓存牺牲正确性。
- **当前装配**：七人都在既有rooftop_ranch的NpcStations35局部Marker，无物理住房、UI“暂驻天台”；Main已撤resident_harbor实例及zones/scope绑定但source保留，用户root与其他旧transform未动。七人/七配件、21+4/84/9、五职业、两商店11商品、三花四stage已实现并有专项；NPC与Shop的独立所有权不变。
- **证据分层**：主时钟301/0+sleep42/0，性能fixture61/0，当前合批NPC性能/rules/world/appearance/careers/flowers/sleep PASS；211435 shop-rules218/7、exit1为失败历史，已由213213最终259/0解决，不反改旧批为全绿。真实Forward+/4060Ti/1600×1000泛光开59.943FPS、Main._process median0.752ms；重复sync median0.008ms不是全量sync每次成本，旧住所撤除与draw变化不能算作纯算法收益。泛光、画质和七人保留。
- **最终范围签署**：当前天台五项integration668/0、save618/0、seed408/0、restart202/0、visual381/0，总2277/0，214439报告五项exit0/PASS、unexpected_errors空；shop最终259/0。NPC R01–R14当前运行实现通过，NPC/Shop登记implemented（已实现待完整产品验收），不是verified；住房source仍partial/deferred。14真实PNG已出，主线程仅目检seven-residents/flower-purchase/story-choice三图，确认七人原草地/无新住房、形象配件、花店5商品价格与购买、剧情2choices及天台暂驻UI；其余11图待审。报告/命令/版本与全部截图链接见[性能修复记录第8节](../development/2026-11-07_npc_performance_fix.md#8-最终天台运行签署与14图清单)。

## 最终签署边界（七人全天台历史）：运行通过不等于完整产品验收

真实HUD航行、上下船、消防梯、七点走路、鼠标/E、职业、七请求礼物、坏档原子与重启profile隔离已在当前天台实际通过；无需再等执行或借旧住所版结果。天台provider为 `godot/src/npc/npc_rooftop_anchors.gd`，不是设施zone脚本；当前七个初始地点均天台草地对应职业站点，不代表房屋/温室已接入。R02/R07全剧情人工体验、R08/R11/R13剩余11图人工审阅及R11/R14设备/发行包/持续性能仍待完整产品验收。主线程另跑全局门禁；本轮不修改代码/registry/runner，不重复global check。

## 2026-11-07 22:39 NPC人物与双场地契约（当前覆盖，partial / pending）

上文七人全天台/35天台Marker及运行PASS保留为历史；当前6roof/1sea覆盖其场地分配，不改状态所有者。SEA-RESIDENT追加R15–R18（原最大R14），SEA-SHOP追加R10（原最大R09），两账本本轮partial、新实测pending；SEA-RESIDENCE仍partial/deferred，不作为前置，不恢复住房、不修改用户Main roots。

### 静态内容、展示与durable边界

- `NpcCatalog`唯一读取七人显示称呼映射：npc_luo_yan=船老大、npc_mu_he=豆豆、npc_ji_chen=阿海、npc_nan_zhi=木头叔、npc_bai_shi=灯伯、npc_hua_yi=小花、npc_bao_he=阿店。不限两字，不做地域/民族/假名释义；只换显示内容，稳定ID与npc.version=1不变，不强迁gender、不改玩家可自定义Avatar或其profile。
- `row.profile`恰为`age_group/age_range/personality/past/arrival_reason/short_term_wish/secret_or_regret/habit/catchphrase`九字段，当前七人均成人；`social_notes`每人指向其余六人的具体相处看法，共42条，不新增持久关系边。九旧边仅加summary/history/tension/reconcile，不改base或edge ID。
- `NpcService.character_profile(npc_id)`返回独立人物内容副本，`conversation_topics`返回话题ID/标题，`start_topic`启动display会话；Panel/Session只展示/转发，不拥有新好感或剧情状态。认识页隐藏secret_or_regret；未认识对象的social_notes隐藏名字和全文；reconcile仅在包含该边双方的已完成relationship事件后公开，不能用好感或无关事件放行。四有专属双人事件边外的五边不另造事件，和解内容默认仍隐藏。
- 28个past/daily/friends/plans话题各两页共56页，读完/取消/重开不调用talk/meet、不增加好感、不发剧情/业务完成事件、不写seen_events/choice_flags/request_states。84daily槽ID不变，各text+2variants共252句，另有21intro页。正常daily/intro仍沿原交谈规则，不因话题零结算被一起改掉。
- 日常轮换仅由现有日/天气/剧情完成数和稳定槽位hash求模，等价输入重复/读档一致；天气或剧情变更可换句，不新增随机流/计数持久字段。25旧events/7requests只文案朴素化，page/choice/event/request ID、条件、effects/costs/result_tag/followup和数值不变。静态人设/话题/目录/世界锚点不写npc存档，旧档按ID恢复，严格坏档原子性保持。

### 世界端口与支撑所有权

| 所有者 / 公开端口 | 当前契约 |
|---|---|
| Main → `NpcAnchorHub.configure(providers)` → Presenter | Main只装配天台NpcStations与浮店Objects/NpcStations，并向Presenter注入Hub；不在Main硬编码别名/日程/交易规则。 |
| `NpcAnchorHub.anchor_snapshot/home_labels` | 聚合provider只读快照；天台30 Marker与浮店5 Marker合计35，但不再是35个全天台。`canonical_anchor_for_npc(anchor_id,npc)`按NPC归属解释共享旧名，不能借别人的同名锚点掩盖缺失。 |
| `npc_rooftop_anchors.gd` | 六人Home/Work/Social/Rest/Door由用户rooftop_ranch局部Marker提供，所有普通/天气/好友/周末/剧情/夜间日程留在天台，不跨海寻路。 |
| `npc_site_anchors.gd` | 只适配既有floating_shop/sea_supply的地面/局部Marker，不造地、不拥有Shop规则。阿店home=residence_general_store、work=anchor_general_store、social=residence_general_store_social，含Rest及全部条件日程都在浮店本地。 |
| `anchor_snapshot`动态支撑扩展 | 提供position_local、support_frame、support_origin、site_pose、support_revision及只读ground/ground_space；frame是浮店Objects刚性支撑引用，不可持久化。 |
| 浮店原owner → Presenter `_carry_supports` | heave仍由浮店世界owner推进，Presenter每physics仅携带阿店、目标与在途路径并做动态矩形廉价支撑检查；不把六个静态天台NPC送入逐physics三角投影。 |
| `NpcWorldPorts.layout_snapshot/anchor_layout` | 动态站位比较局部position与静态site_pose，排除瞬时position/support_origin及heave高度；海浪本身不触发七人全量sync、重寻路或导航rebake。root/Marker变动、active/surface/revision仍使缓存失效，保留失支撑停止/隐藏与force恢复。 |

沿用R14：clock.changed只notify小字典，0.5秒批次检测时间/天气/关系剧情/真实布局变化，每batch一次Hub快照；WorldClock仍唯一推进。UI标“常在”，不标“住处”；六人天台暂驻、阿店东南海上商店，Home/Rest不是已建住房证明。位置以用户TSCN实际root为准，不锁绝对坐标，不通过改Main旧transform或临时地面修验收。

### 商店边界与新实测

ShopCatalog显示标题目标“小花花店/阿店海上商店”，由主线程改shops.json；文档分支读到的仍为旧标题，不把计划写成已落。ShopService/Catalog/Panel继续独立、可无NPC购买，vendor_npc_id只作可选展示元数据；NPC只发vendor_requested，世界provider不引入价格/商品规则。两目录11商品ID、price/max_amount及CropCatalog来源不变，不顺带改flower_ribbon商品标签。跨海送花是叙事，不自动改Inventory/订单或强迫NPC跨海。

主线程计划跑npc-people、npc-profile-ui、npc-shop-site、npc-relocation、visual-npc-people及rules/performance/save，实际入口是否注册须核实；命令、head+working_tree、退出码/计数、日志、真实截图与逐图审阅见[本轮开发记录第6节](../development/2026-11-07_npc_names_and_shop.md#6-主线程实测回填)，同时回填[Resident账本](../features/resident/ledger.md#2026-11-07-2239-当前覆盖与新增条款承接)和[Shop账本](../features/shop/ledger.md#2026-11-07-2239-当前覆盖与-r10-承接)。本分支不执行global sync/hash/运行，不复用历史全天台PASS证明6roof/1sea；未验项保持pending。
