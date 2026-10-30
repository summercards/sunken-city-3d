# sea 游戏设计文档

**版本：** V1.0  
**文档状态：** 项目主文档 / 功能管理中控
**记录日期：** 2026-10-17；管理结构修订：2026-10-23
**项目类型：** 治愈系水上家园建造 × 轻度资源经营 × 航海探索

---

## 0. 主文档中控规则

本文是 sea 的唯一项目管理中枢。先在本页确定目标、全局规则和功能关系，再进入每个功能的独立文档与独立账本。Godot 为当前正式运行工程（`godot/`）；`web/` 目录保留 Three.js 原型，作为烘焙来源和视觉对照，不作为第二份当前玩法主设计。两套实现互不引用。

- 每个功能一个稳定 FeatureID、一份独立功能文档、一份独立功能账本；规划中的功能同样登记。
- 本文拥有全局目标、功能范围、依赖和阶段安排；功能文档拥有该功能细则；功能账本拥有实施状态与证据。
- 功能之间通过公开命令/查询/事件和稳定 ID 交接，资源与状态只有一个最终写入者。
- 新增功能先登记本页再建独立文件；修改功能先读其文档和账本，验证后回填账本并同步本页摘要。
- 本页状态摘要由 `python3 scripts/check_feature_contracts.py --sync` 从功能账本更新；禁止在两处手工维护不同进度。
- 第一版按完整行为闭环划分功能。例如种植含播种、浇水、生长、收获，各步骤有独立设计条款；后续若升级为独立功能，先在本页拆 FeatureID，再拆文件。
- 目标设计与当前实现分别保留；已有代码不能自动取代用户目标，旧完成度百分比不代表当前状态。

[功能导航](#feature-control) · [模块接口与状态机](docs/architecture/module_contracts.md) · [场景组件分类](assets/registry/SCENE_COMPONENTS.md) · [工程约定](docs/standards/工程管理规范.md) · [本次拆分记录](docs/development/2026-10-23_feature_split.md) · [拆分前完整主文档](docs/archive/pre_split_20261023/GDD_V1.0.md)

---

## 当前可玩版本：太阳房最小生活循环（2026-10-27）

2026-10-30细节修订：海鸥只在06:00–18:00出现，过了18:00整群收起且停止动画计算，时段只读唯一WorldClock；点击浮木/鱼群后的打捞巡航到站不再把船头拧回出发朝向（`sail_to`新增`align_at_arrival`，靠泊语义不变）；面板与模态的屏幕右下角收成一枚动物森友会式圆关闭键（奶白圆片、深棕描边、手绘粗叉、逆时针歪约6°，62px贴角），原「返回Esc/选择Enter」两枚胶囊移除，键盘路径保留。归SEA-AMBIENT-R05 / SEA-PICKUP-R15 / SEA-UI-R47。[交付与实测](docs/development/2026-10-30_detail_fixes.md)。

2026-10-30模块化家园建造：新增12种独立结构组件和10种生活摆件，4×4浮台为4米见方；统一2米模数、2.8米层高，墙/柱承载挂点、楼梯与二层楼板按真实空间拼接。目录控制配方启用/停用，手册分类分页；停用不损坏已建实例和旧档。两种油灯真实照明、木箱共享仓库、水桶补水，其余摆件按明确装饰功能维护。范围归SEA-BUILDING，资产归SEA-ASSET，三维移动执行归SEA-MOVE；物品、水壶和仓库仍归原所有者。[设计、内容明细与交付](docs/development/2026-10-30_modular_building_kit.md)。

2026-10-30建造收尾：手册改为奶油纸色5列×2行卡片，仅图片、名称和消耗；固定/旧木板可承载新组件，4×4浮台按实际板边精确衔接，保留旧板尺寸；22组件统一PaletteUV为UV0并保留材质角色，修复贴图错乱。全部22件经正式游戏建成，二层行走与保存恢复、卡片鼠标、UV实际渲染验收通过。[完整结果](docs/development/2026-10-30_modular_building_kit.md)。

2026-10-30海上悬浮商铺进main：`art_source/scenes/floating_shop/v002`导出为单一运行GLB（39组件/248实例按四材质角色烘合并，669345三角面，无内嵌贴图，颜色由预制体上序列化的公共色板材质覆盖），归`building/shop`（账本等级＝商店）、放置层`above_water`。正式摆放由`main.tscn`的`World/SeaStructures/floating_shop`独有，位于阳光房主体（后部方形建筑＋前部倾斜太阳能房）占地中心正南50米海面，甲板顶面与家园甲板同高（水面+0.26米），板体与推进器沉入水下。区块外的结构没有ZoneScene扫描，`main._water_shapes()`补充收集`World/SeaStructures`，船不再穿过浮店。行走面、泊位与商店交易界面仍pending。归SEA-ASSET-R35 / SEA-WORLD-R13。[交付与实测](docs/development/2026-10-30_floating_shop_runtime.md)。

2026-10-30浮木密度最新修订：阳光房周围保留原补给区总计6束，外部海域数量降至先前30%（默认10个开放分区60束→18束），鱼群数量和位置保持。载入密集旧档即生效，并保留采集冷却；07:00日更与浮木6–10游戏小时补货规则保留。归SEA-PICKUP-R14。[交付与实测](docs/development/2026-10-30_wood_density.md)。

2026-10-30自建上岸提示：普通提示间距增至12米、屏幕间距100px、最多4个；当前返船入口优先。提示按稳定ID复用展示状态，修复0.75秒刷新时的一帧消失和悬停重置；合法边仍可直接点击板面登陆。归SEA-BUILDING-R17 / SEA-UI-R38。[修复与实景](docs/development/2026-10-30_sparse_landing_markers.md)。

2026-10-30海上资源：成功获得物品时，原背包图标与+数量在角色头顶进度条上方飘起渐隐；浮木/鱼群扩至全部可航海域，按分区随探索加载并保留采集状态。每天07:00刷新鱼群和浮木，鱼群当日不补，浮木采集后独立随机6–10游戏小时补回。归SEA-PICKUP-R11–R13 / SEA-UI-R45 / SEA-SAVE-R11。[交付与实测](docs/development/2026-10-30_ocean_pickups.md)。

2026-10-30收获表现：成功拿到生菜、番茄、南瓜后，角色俯身取物、双手举到帽子上方稍作展示，再放入右侧挎包并合盖，全程2.4秒；失败不庆祝，走开/取消/睡觉/读档清理临时实物。奖励仍在原收获业务时点只结算一次，表现不改数量和种植规则。归SEA-MOVE-R14 / SEA-FARM-R13 / SEA-CROP-R14。[设计、账本与实景](docs/development/2026-10-30_harvest_receive_animation.md)。

2026-10-29种植区通行最新修订：固定六格、DIY标准/小型培养土与蔬菜不挡人，玩家可直接踩上去；行走不改作物，平台外缘仍保护。通行投影归SEA-BUILDING-R16，承载/重叠及种植业务保留。[本轮交付](docs/development/2026-10-29_walk_on_planters.md)。

2026-10-29初始六格种植区：原平台六格是新游戏已拥有的完整种植区，首次存档即包含六格空状态，使用与DIY种植区相同的操作站位与种植流程；保留原位置、模型及`platform_plot`系列ID，旧档仅补缺格，不重置已有作物。归SEA-FARM-R12。[修复与验证](docs/development/2026-10-29_initial_six_planters.md)。

2026-10-29角色基础改造：在保留当前内容、操作与数值的范围内，正式角色接入胶囊碰撞、三维陆地导航和独立表现动作生命周期；不新增样板房/楼梯，不改经营规则。SEA-MOVE拥有执行与表现，SEA-WORLD拥有派生空间，相关交互/镜头/存档仅接口适配。[改造与验证](docs/development/2026-10-29_character_physics_framework.md)。

本阶段优先于后文长期规划：范围缩小到太阳房、旁边家园补给站、浅水种植平台及附近水域。新游戏80瓶盖、3包生菜种子。捕鱼或种植收获 → 保管仓库存取 → 显式放进出货箱 → 次日07:00自动卖出 → 商店购买种子。新播生菜、番茄、南瓜首熟均需3个浇水日，缺水停长；岸上可补水；太阳房入口点击睡觉，23:00自动回家睡觉，06:00醒来，07:00生长与收货。保管仓库不卖货；出货箱可在结算前取回。

只保留上述生活玩法及存读档、基础设置、航海图；潜水、固定建筑升级、远海、订单、打捞和取景入口锁定；本轮开放独立的家园拼接建造与海面浮木收集。P键滤镜/光照/水面调试面板按2026-10-28要求恢复开放。隐藏的进度、场景与资产不删除。代码规则入口为 `godot/src/core/play_scope.gd`，显式 `--full-world` 仅供后续功能开发回归。

**2026-10-29 最新范围修订：海上自由建造。** 按最新要求取消原平台外两圈、24新板和旧150m航区的玩法边界。可沿任意空边扩建，也可乘船在无建筑阻挡的海面开辟独立平台；建筑实体、具体泊位通道、船体、承载与通路保护仍有效。航行、相机和读档不再把合法远处位置夹回原范围，HOME_WATER界定阳光房周围六束浮木补给区，不限制航行；外部资源按可航海域分区生成；完整规则由SEA-BUILDING拥有。三种配方、精细摆位、保留作物搬移、空物件拆回退款、动态登陆及技术资源边界见[设计](docs/features/building/spec.md)与[本轮交付](docs/development/2026-10-29_open_ocean_building.md)。旧150m范围修订保留在[历史记录](docs/development/2026-10-29_sail_bounds_150m.md)。

默认先显示实景开始画面，只有倾斜的奶白SEA标题和“开始游戏”按钮，文字柔和显现。开始前日历与经营暂停，点击后镜头平滑回到角色才显示玩法UI。系统信息使用轻提示，底部对话只用于角色发言。当前功能关联：SEA-UI / SEA-WORLD / SEA-NAV / SEA-PICKUP / SEA-FARM / SEA-WAREHOUSE / SEA-ORDER / SEA-TIME / SEA-SAVE。

空地点击选择背包种子，种下后点击选择浇水，成熟后点击收获。浅水平台为六格独立木框培养土；太阳房白盖蓝箱移到码头左侧，点击后放入/取回出货物。每日07:00自动收货换瓶盖，内部货币ID及旧余额保留。

[场景种植与码头出货交付记录](docs/development/2026-10-27_plot_shipping_loop.md) · [最小循环与开始画面交付记录](docs/development/2026-10-27_minimum_loop_and_title.md)

---

## 2026-10-28 时间表现与睡觉

按最新要求，07:00–11:00保持原09:00光影基准，12:00–14:00为正午，14:00–16:00为下午，17:00–19:00为夕阳；最新夜景要求覆盖旧全暗方案：19:00起关闭太阳，保留冷色环境与天空照明、可读的深蓝海面和暖灯倒影；边界短时平滑过渡，06:00为清晨醒来。开始画面使用已恢复的存档时刻，无存档则使用新局07:00；点击进入时延续同一时刻的光照。详见[木板与分时光照](docs/development/2026-10-28_thin_cabin_and_dayparts.md)。睡觉与起床使用向角色收拢/展开的黑色圆幕，完全遮黑后切换到次日06:00；通过独立SEA-SLEEP模块串接时钟、角色与UI，不新增第二份存档时间。详情见[光照记录](docs/development/2026-10-28_daylight_sleep.md)与[睡觉交付](docs/development/2026-10-28_sleep_cycle_delivery.md)。

## 2026-10-28 家园箱子与夜灯修复

家园修复补充：码头白盖蓝箱直接挂在出货交互节点，18:00–19:00渐亮窗光、门灯与船灯，清晨渐灭；船体及细节接收真实光照，P键恢复且修改昼夜光照基准。[本轮修复与验证](docs/development/2026-10-28_home_lighting_recovery.md)。

## 2026-10-28 清晨、下午与温暖夜海

06:00以约3°的低角度橙金朝阳、冷色暗部与长阴影表达日出；下午恢复与上午同级的日照，上午/正午/夕阳的原日照关键帧保留。夜间海面改为真实受光材质，深蓝底色与反光由月光、船灯、屋灯照射形成，关闭光源后不会自行发亮，并按真实水深保留浅水透视、深水吸收与水下建筑轮廓；窗光只落在玻璃而不点亮木框；小船复用现有灯笼，暖灯随船照亮船身与海面。季节/天气/时段的既有偏移及玩家配置保留。本节覆盖早前“19点全暗”的视觉要求。[交付与实景](docs/development/2026-10-28_cozy_daypart_atmosphere.md)。

## 2026-10-28 外舷夜航照水灯

船灯改为船头左外舷的短杆挂灯，真实暖色光束向下、向外照亮附近水面，并随船转向移动；保留水深、波面反光和真实衰减。上午、中午、傍晚的光照数值继续保留。[灯具设计与开关对照](docs/development/2026-10-28_boat_navigation_lamp.md)。

## 2026-10-28 开始界面构图与存档时刻

保持原开始镜头角度、FOV与距离，仅沿视平面下移，让太阳房主体在画面中上移约10%；“开始游戏”右移到种植平台右侧的水面留白。开始界面从第一帧就按读档后的世界时刻显示光照，文字淡入和入场镜头过渡均不推进世界时间，不再先用09:00再切换存档时刻。[构图与冷启动实测](docs/development/2026-10-28_title_composition_saved_time.md)。

## 2026-10-28 场景操作气泡与口袋

交互物悬停只显示小操作图标，点击在物体上方弹出白色手绘剪影气泡，选择操作后角色才接近执行；空白处/Esc收拢。B/Tab打开平直奶油背板口袋，真实格子、空位圆点、物品名称胶囊和黄色操作气泡；生活手册独立入口。出货箱、仓库与商店的内部界面同样使用物品网格，取消旧文字详情表；见[服务口袋补齐](docs/development/2026-10-28_service_pockets.md)。关联SEA-UI / SEA-INTERACT / SEA-INVENTORY / SEA-FARM。[交付记录](docs/development/2026-10-28_pocket_action_bubbles.md)。

## 2026-10-28 登陆双向、固定天气与家园补给站贴图

登陆标记一个图标两个方向，按角色当前所在判断：岸上点 → 走回泊位上船；船上且停在此泊位 → 上岸；船不在该泊位 → 先航行、**靠妥后自动上岸**。不再要求玩家点第二次。空地「种植」一律弹二级选种子（列出持有种子与数量），只有一种也弹，不静默替你选。天气当前固定为晴，不随时间轮换；旧档里的「雨」不会被带回来，轮换逻辑保留在同一个服务内、由配置切换。家园补给站（绞盘打捞台）的顶点色在拆分导出时被写成纯白，已按世界坐标从同源 `detail.glb` 回填，几何与材质未改。关联SEA-MOVE / SEA-NAV / SEA-FARM / SEA-WEATHER / SEA-ASSET。[交付记录](docs/development/2026-10-28_dock_seed_weather_asset_fix.md)。

## 2026-10-28 主界面收纳与海岛笔记

时间/天气、瓶盖和背包容量收拢到左下，保留原白色加粗圆体，只有文字、不加背板。右上仅一个彩色图标，点击展开背包、笔记、商店、仓库、出货箱、航海图与设置的图标入口，无常驻文字；种植归入笔记。海岛笔记顶部为总目录/种植/物产/生活分类，下方六卡分页与详情，读取真实作物、地格、库存和收货资料。泊位改用同套手绘船锚，无名称，平时小、鼠标靠近放大并变暖金。关联SEA-UI / SEA-FARM / SEA-INVENTORY / SEA-TIME / SEA-NAV / SEA-INTERACT。[交付与原生截图](docs/development/2026-10-28_corner_hud_notebook.md)。

## 2026-10-28 月日显示与右下视角锁定

左下日期改为几月几日，基于存档累计天数从1月1日换算（固定365日循环），瓶盖缩小为与背包相同的28px；保留原白色加粗圆体与无背板。回到角色改为右下圆形人物定位图标，点击锁定角色视角、颜色同步跟随状态；停止行动按钮移除。关联SEA-UI / SEA-TIME / SEA-CAMERA。[交付与实景](docs/development/2026-10-28_hud_date_camera_lock.md)。

## 2026-10-29 家园拼接建造与浮木

右上菜单建造手册提供木板、标准培养土、小型培养土与搬移/拆回管理。浮木材料来源和原配方价格工期保留；新增小型培养土2木板+1土壤、3秒。取消原平台外两圈和仅限岸上施工：可持续接板，或乘船在无建筑阻挡的海面施工独立平台，完工边缘可靠泊登陆。摆件在新木板并集上按0.1米摆位、Shift精细0.01米、R旋转；搬移保留作物与生长，空物件安全拆回并整笔退材料。全部共享承载、角色宽度、连通、建筑/船/泊位和存档校验。

规则、布局与扩展目录归SEA-BUILDING，区别于SEA-BUILD固定建筑升级；Farm和Inventory仍各有唯一写入者。没有玩法圈数/固定地图/54实例上限；4MiB布局与8MiB整档仅为提交前明确告知的技术容量保护，不以不可保存的布局换取“无限”名义。前次边界审计作为[修复前证据](docs/development/2026-10-29_building_boundary_audit.md)保留，当前状态与实测见[本轮交付](docs/development/2026-10-29_open_ocean_building.md)。

## 2026-10-29 交互热区按模型本体算

点击命中从「物体屏幕包围盒外扩10px」改为相机射线打模型三角形（Möller–Trumbore），每个网格先用自身OBB粗筛，三角形按mesh实例缓存，超1500面的网格退回OBB。原因：zone5六个土箱并排，真实缝隙约0.36×0.99米，屏幕上仅十几像素宽，两侧包围盒各外扩10px把整条缝盖满，点甲板空地会被判成点土箱，既不走也不弹菜单。图标30px只留给没有几何的纯逻辑交互点，模型命中优先。同轮修掉`hud.gd`中Godot 4.6推断不出类型的条件表达式（会导致整份hud.gd解析失败）。关联SEA-INTERACT-R10。[交付与实测](docs/development/2026-10-29_pick_hotspot_follows_mesh.md)。

## 2026-10-29 走不到不给入口、建造要先到工地

陆地状态下走不到的可交互物不再给操作入口：不显示悬浮图标、指针不变手形、点击不弹菜单，只给一句原因（那边在别的区域需先坐船靠岸 / 那里走不过去 / 那里是水面）。可达性按`approach_points`判，查询带350ms缓存。点击命中范围改为物体屏幕包围盒（外扩10px），包围盒面积超过视口12%的物件退回图标热区。建造改为点虚影先让角色走到格子旁、站定后才扣材料开工；等待上限8秒，已在旁边则当场开工。关联SEA-INTERACT-R09 / SEA-BUILDING-R10。[交付与实测](docs/development/2026-10-29_build_requires_approach.md)。

## 1. 核心幻想与产品定位

2026-10-29建造外观修正：拼接木板顶面保持原高度，板底向下补足吃水厚度；完工占地增量同步到双水面吃水线。绞盘平台的电线杆与花叶按用户箭头向右侧水域独立平移，保留平台布局。关联SEA-BUILDING-R08 / SEA-OCEAN-R22 / SEA-ASSET-R31。[本轮记录](docs/development/2026-10-29_deck_draft_pole_placement.md)。

2026-10-29背包拖拽与购买数量：口袋界面（服务口袋与 B 键纯背包）的背包格支持**拖拽整理** —— 拖到另一格两者互换、拖到空槽挪到末尾，松手立即重排；商店目录/出货托盘不接受背包物品落下。整理结果随存档保留（Inventory 新增 `order`，schema 只增字段且不进 required，旧档照常可读）。商店购买改为**数量选择** `[−] N [+]` + 「购买 N」，上限取「瓶盖够买几份」与「背包还放得下几个」的较小值，到顶置灰而不让人点到瓶盖不足再被弹回；批量购买原子化，不会出现扣了钱只到一部分货。物品数量、单价、堆叠上限与存取规则均未改动。关联SEA-UI-R43/R44 / SEA-INVENTORY-R09/R10；[交付与实测](docs/development/2026-10-29_pocket_drag_buy.md)。

2026-10-29拾取流程与进度：海上拾取改为三阶段状态机 **IDLE → SAILING → GATHERING** —— 点击浮木/鱼群后船划过去，**航行段没有任何进度**（赶路不是打捞）；**船停稳且目标在范围内（浮木 2.2 米 / 鱼群 3.2 米）才开始打捞**，打捞计时（浮木 1.2 秒 / 鱼群 1.6 秒）其间**角色头顶**出现 76×6 px 细进度条、按时间从 0 走到 1，**走满那一刻才结算**（原先到站瞬收）。停稳但够不着（如半路被岸线挡住）直接作废，不对空气打捞；自己划到浮木旁同样要捞 1.2 秒，`try_pickup` 瞬收路径已删除。条**必须挂角色、不挂目标**：镜头跟着角色走，目标容易偏出取景框，挂目标的条会随之一整条消失。取消、改道、靠岸、读档、入睡立即清阶段收条；背包满等失败立即收条不闪假满格。同轮把建造施工条从 `ProgressBar`（实际渲染约 20 px，由 `cozy_ui.surface()` 的 content margin 撑高，改 `size` 无效）换成同一份自绘细条 92×8 px，拾取与建造共用 `godot/src/ui/thin_progress_bar.gd`。航速、奖励、掉率与存档结构未改动。关联SEA-PICKUP-R09/R10 / SEA-BUILDING-R09 / SEA-UI-R42；[交付与实测](docs/development/2026-10-29_pickup_progress_bar.md)。

2026-10-28水下光纹最新修订：建筑上的大块斑驳改为稀疏、淡的卡通十字波纹贴图；屋顶/立面独立投射，共用两套水面及昼夜权重。关联SEA-OCEAN-R21；[贴图与实景验证](docs/development/2026-10-28_cartoon_cross_ripple.md)。

2026-10-28：按水下参考图新增阳光房周围六栋独立纯景观建筑，每栋实际导出三角面不超过1000，归入装饰/水下建筑。布局按左侧弧楼、退后的高楼与窄楼、前方不同距离的低屋顶形成疏密和斜向水道；正式TSCN持有摆放。水下光斑改为柔和浅色聚光，双水面8时段实测，消除压黑屋顶的人工斑块。原阳光房海下基座独立维护，水下景观无互动、资源产出、碰撞或船只阻挡。关联SEA-ASSET-R29/SEA-WORLD-R10/SEA-OCEAN-R21；[制作与验证](docs/development/2026-10-28_submerged_neighborhood.md)。

2026-10-28：基础小船按用户参考替换为黄白木船，补齐圆杆宽叶双桨、三排座板、船外机、绿色行李及浮球。船体尺寸和水线保持旧船；双桨沿用划桨状态，保留现有外舷夜航灯。关联SEA-ASSET-R28 / SEA-NAV-R09；[制作与验证](docs/development/2026-10-28_reference_skiff.md)。

### 1.1 核心幻想

整个文明沉入水下，玩家却在废弃建筑的屋顶上，重新创造一个温暖、有生命力的小家园。

游戏最吸引人的并不是末日灾难本身，而是：

> 在被海水覆盖的旧世界上，逐步修复屋顶、种下植物、迎来居民，让破败的建筑重新变成有灯光、有收成、有来往船只的水上村落。

### 1.2 产品定位

- 节奏缓慢、没有强制战斗的休闲建造游戏。
- 以建造成就感、场景变化和探索发现为主要驱动力。
- 航海是解锁新景色、新材料和新建筑遗址的奖励，不应成为重复跑图负担。
- 玩家最终追求的不是单纯更高的数值，而是一个越来越繁荣、越来越有生活气息的水上世界。

### 1.3 三条长期成长线

1. **家园越来越繁荣：** 屋顶从废墟变成住宅、农场、工坊和聚落。
2. **船只越来越先进：** 从初始木船成长为可以前往远海、打捞材料和运输物资的船只。
3. **世界越来越广阔：** 从第一个屋顶群落出发，逐步发现更多沉没街区、建筑遗址和水下景观。

---

## 2. 核心玩法闭环

### 2.1 第一版核心循环

```text
发现废墟
  ↓
收集物资
  ↓
修建家园
  ↓
种植与生产
  ↓
收获资源
  ↓
扩大家园
  ↓
升级船只
  ↓
探索新的废墟
```

### 2.2 初始循环的调整原因

原始循环是：

```text
建房 → 收获 → 升级房屋 → 更多收获 → 升级船
```

这个循环能够推动数值增长，但缺少玩家主动探索、改变环境和持续建设的理由。第一版应把资源增长嵌入场景变化与区域解锁中，让每一次建造都带来“世界真的变了”的反馈。

### 2.3 三个设计原则

#### 原则一：每次建造都改变场景

建造不能只是房屋从 Lv.1 变成 Lv.2。升级后应至少发生一项可见变化：

- 屋顶出现植物、花盆或种植箱。
- 居民搬入，窗户亮起灯光。
- 邻近屋顶之间出现木桥、晾衣绳或小型码头。
- 破败建筑逐步扶正、补全或变成新的功能设施。
- 夜晚或阴影区域出现温暖灯光与生活细节。

#### 原则二：房屋、农场、船只互相依赖

- 房屋提供居民、仓储和工作能力。
- 农场生产食物、植物和交易物资。
- 船只带回木料、旧零件和特殊材料，并负责抵达新的废墟。
- 不能只依靠挂机收钱完成全部升级。

#### 原则三：航海是奖励，不是负担

- 新船只应解锁新景色、新资源、新建筑遗址。
- 常用区域之间应减少无意义的重复跑远路。
- 航海过程需要有风景、漂流物资和发现感，而不是纯粹等待进度条。
- 船只升级应自然地扩大玩家的生活范围。

---

## 3. 首个区域规划

### 3.1 区域尺度与整体构图

- 建议核心可玩区域约为 **45 × 40 米**。
- 保留现有工程中的太阳能木屋、水道、沉没铁道、远海沉没街町和周边水下建筑景观。
- 画面重点为：前景温暖家园、中景水道与航线、远景沉没建筑和水下巨鲸。
- 当前地图可继续扩展，但第一版应优先确保核心区域内的功能层次清晰。

### 3.2 五个建筑功能区

| 区域 | 功能 | 玩家获得 | 第一版状态 |
| --- | --- | --- | --- |
| A 太阳能木屋 | 住宅升级、居民、仓储 | 解锁更多种植位和工作能力 | 首局起点，优先实现 |
| B 圆弧屋顶农场 | 种植、浇水、收获蔬菜 | 持续获得农产品 | 首局核心功能 |
| C 绞盘打捞站 | 打捞漂流物和废料 | 木料、旧零件、修缮材料 | 首局核心功能 |
| D 水上码头 | 交易与改造小船 | 瓶盖、船只升级、远航许可 | 首局核心功能 |
| E 浅水养殖台 | 鱼类养殖和新材料 | 鱼类、特殊材料、后续建筑资源 | 第一版预留，后续扩展 |

### 3.3 第一版区域功能取舍

第一次游玩只需要 A、B、C、D 四个功能真正可用。E 只保留视觉预留或锁定入口，避免新玩家一开始面对过多系统。

当前工程中的横滨沉没铁道、天台种植园和太阳能木屋可继续作为第一版三个主要可玩点，但需要把它们与 A-D 的功能身份重新对齐，避免“场景名称”和“玩法功能”脱节。

---

## 4. 建筑与场景成长表现

详细设计已归入 [SEA-BUILD 功能文档](docs/features/build/spec.md)，实施状态见 [独立账本](docs/features/build/ledger.md)。原始设计全文已保留，历史网页数值不作为当前 Godot 数值。

---

## 5. 资源与数值

详细设计已归入 [SEA-INVENTORY 功能文档](docs/features/inventory/spec.md)，实施状态见 [独立账本](docs/features/inventory/ledger.md)。原始设计全文已保留，历史网页数值不作为当前 Godot 数值。

---

## 6. 前 20 分钟体验目标

这些时间是体验节奏目标，不是强制倒计时。

### 0–3 分钟：修复第一块屋顶

- 玩家乘船抵达圆弧楼或在太阳能木屋醒来。
- 使用初始木料修好两格农田。
- 看到第一批种子和建筑部件在场景中出现。
- 通过一次明确的视觉变化理解“建造会改变世界”。

### 3–7 分钟：第一次种植与收获

- 作物逐渐生长。
- 玩家去旁边绞盘站打捞旧零件。
- 第一次收获获得农产品或瓶盖。
- 玩家知道资源需要主动收取和分配，而非只等待数字自动增长。

### 7–12 分钟：升级自己的木屋

- 出售作物获取瓶盖。
- 修缮住宅，增加居民或屋顶种植位。
- 屋顶出现植物、窗灯和生活道具。
- 玩家第一次感受到“家园开始有人住”。

### 12–20 分钟：升级船只并准备远航

- 完成第二轮收获和材料收集。
- 在水上码头改造木船。
- 木船变成可驶往远海的帆船或改良船。
- 航行至远海沉没街町，看到下一座屋顶等待建设。
- 首局在“下一座屋顶可以建成什么样”的期待中结束。

---

## 7. 航海成长与探索

详细设计已归入 [SEA-SHIP 功能文档](docs/features/ship/spec.md)，实施状态见 [独立账本](docs/features/ship/ledger.md)。原始设计全文已保留，历史网页数值不作为当前 Godot 数值。

---

## 8. 交互与用户体验

### 8.1 交互原则

- 主要操作应保持简单，优先使用场景中的建筑、船只和角色作为入口。
- 建筑悬停只在鼠标指向模型时出现，避免常驻 UI 遮挡画面。
- 资源收取和升级使用统一的建筑操作点，但收取优先于升级。
- 航行入口可以来自角色行动环、船只或码头。
- 右键或手动镜头操作应明确接管自动跟随，避免镜头和玩家意图冲突。

### 8.2 反馈要求

- 资源收取：显示短暂浮动数值，并让顶部瓶盖数字产生轻微反馈。
- 升级中：显示简短进度，不打断观察场景。
- 升级完成：建筑模型、植物、灯光或居民立即发生变化。
- 不可用状态：说明缺少什么，而不是只显示无响应的按钮。
- 满级状态：给出后续解锁或“等待新区域”的方向。

---

## 9. 开发优先级

### P0：完成首个 20 分钟垂直切片

1. 统一 A-D 四个功能区的命名、入口和玩法职责。
2. 保留现有 Three.js 场景和三处可玩建筑，补齐木屋、农场、打捞站、码头之间的依赖关系。
3. 将船只升级做成可见、可操作、能解锁远海区域的系统。
4. 完成从第一次种植到驶向远海街町的首局流程。
5. 为首局流程增加明确的新手引导、目标提示或轻量任务。

### P1：补齐资源经营基础

1. 增加木料、旧零件、农产品等基础物资。
2. 增加仓储和简单交易。
3. 让打捞站成为资源来源，而不是仅有视觉装饰。
4. 让码头消耗基础材料完成船只升级。

### P2：扩展世界与生活感

1. 开放第五功能区浅水养殖台。
2. 增加居民、生活动画和聚落关系。
3. 增加更多屋顶之间的桥、船、灯和生活设施。
4. 增加存档、读档和跨刷新状态恢复。

### P3：产品化与长期内容

1. 增加任务、成就和区域复兴目标。
2. 增加更多沉没街区和深海探索内容。
3. 完善性能、兼容性和视觉回归测试。
4. 根据玩家节奏调整产出、建造成本和船只成长曲线。

---


<a id="feature-control"></a>
## 10. 功能管理与导航

下表逐行定义功能范围与前置关系；依赖是契约/数据交接，不代表允许读取对方内部字段。模块可承载多个功能，所有功能都必须独立有文档、有账本。状态摘要来源为各功能账本；`部分实现` 包括已具备行为但目标、解耦或验收尚未全部闭环。

<!-- FEATURE_CONTROL_BEGIN -->
| FeatureID | 功能 | 所属系统 | 前置功能 | 独立文档 | 独立账本 | 状态摘要 |
|---|---|---|---|---|---|---|
| <a id="sea-boot"></a>SEA-BOOT | 启动与会话装配 | 基础 | — | [文档](docs/features/boot/spec.md) | [账本](docs/features/boot/ledger.md) | 部分实现 |
| <a id="sea-world"></a>SEA-WORLD | 区块与世界装配 | 世界 | SEA-BOOT | [文档](docs/features/world/spec.md) | [账本](docs/features/world/ledger.md) | 部分实现 |
| <a id="sea-move"></a>SEA-MOVE | 角色移动与上下船 | 3C | SEA-WORLD | [文档](docs/features/move/spec.md) | [账本](docs/features/move/ledger.md) | 部分实现 |
| <a id="sea-nav"></a>SEA-NAV | 航行与靠泊 | 3C | SEA-WORLD, SEA-MOVE | [文档](docs/features/nav/spec.md) | [账本](docs/features/nav/ledger.md) | 部分实现 |
| <a id="sea-camera"></a>SEA-CAMERA | 相机跟随与手动控制 | 3C | SEA-MOVE | [文档](docs/features/camera/spec.md) | [账本](docs/features/camera/ledger.md) | 部分实现 |
| <a id="sea-interact"></a>SEA-INTERACT | 点击与长按交互 | 交互 | SEA-MOVE | [文档](docs/features/interact/spec.md) | [账本](docs/features/interact/ledger.md) | 部分实现 |
| <a id="sea-gather"></a>SEA-GATHER | 岸边采集 | 资源 | SEA-INTERACT, SEA-INVENTORY | [文档](docs/features/gather/spec.md) | [账本](docs/features/gather/ledger.md) | 部分实现 |
| <a id="sea-inventory"></a>SEA-INVENTORY | 资源与背包 | 经营 | — | [文档](docs/features/inventory/spec.md) | [账本](docs/features/inventory/ledger.md) | 部分实现 |
| <a id="sea-warehouse"></a>SEA-WAREHOUSE | 材料仓储 | 经营 | SEA-INVENTORY, SEA-FACILITY | [文档](docs/features/warehouse/spec.md) | [账本](docs/features/warehouse/ledger.md) | 部分实现 |
| <a id="sea-build"></a>SEA-BUILD | 建筑修缮与升级 | 经营 | SEA-INVENTORY, SEA-INTERACT | [文档](docs/features/build/spec.md) | [账本](docs/features/build/ledger.md) | 部分实现 |
| <a id="sea-building"></a>SEA-BUILDING | 家园拼接建造 | 经营 | SEA-INVENTORY, SEA-INTERACT, SEA-WORLD | [文档](docs/features/building/spec.md) | [账本](docs/features/building/ledger.md) | 已实现待完整验收 |
| <a id="sea-facility"></a>SEA-FACILITY | 设施解锁与生产 | 经营 | SEA-BUILD, SEA-INVENTORY | [文档](docs/features/facility/spec.md) | [账本](docs/features/facility/ledger.md) | 部分实现 |
| <a id="sea-ship"></a>SEA-SHIP | 船只升级与区域解锁 | 成长 | SEA-INVENTORY, SEA-BUILD | [文档](docs/features/ship/spec.md) | [账本](docs/features/ship/ledger.md) | 部分实现 |
| <a id="sea-crop"></a>SEA-CROP | 作物品种与四阶段形态 | 经营 | SEA-ASSET | [文档](docs/features/crop/spec.md) | [账本](docs/features/crop/ledger.md) | 已实现待完整验收 |
| <a id="sea-farm"></a>SEA-FARM | 种植与日常照料 | 经营 | SEA-INVENTORY, SEA-FACILITY, SEA-WORLD, SEA-CROP | [文档](docs/features/farm/spec.md) | [账本](docs/features/farm/ledger.md) | 部分实现 |
| <a id="sea-salvage"></a>SEA-SALVAGE | 绞盘打捞 | 探索 | SEA-INTERACT, SEA-INVENTORY | [文档](docs/features/salvage/spec.md) | [账本](docs/features/salvage/ledger.md) | 部分实现 |
| <a id="sea-dive"></a>SEA-DIVE | 潜水探索与宝箱 | 探索 | SEA-WORLD, SEA-INVENTORY | [文档](docs/features/dive/spec.md) | [账本](docs/features/dive/ledger.md) | 部分实现 |
| <a id="sea-pickup"></a>SEA-PICKUP | 海面漂流物与鱼群收取 | 探索 | SEA-NAV, SEA-INVENTORY | [文档](docs/features/pickup/spec.md) | [账本](docs/features/pickup/ledger.md) | 部分实现 |
| <a id="sea-order"></a>SEA-ORDER | 交易与订单 | 经营 | SEA-INVENTORY, SEA-BUILD, SEA-SHIP | [文档](docs/features/order/spec.md) | [账本](docs/features/order/ledger.md) | 部分实现 |
| <a id="sea-goal"></a>SEA-GOAL | 小目标追踪与引导 | 成长 | SEA-BUILD, SEA-SHIP | [文档](docs/features/goal/spec.md) | [账本](docs/features/goal/ledger.md) | 部分实现 |
| <a id="sea-resident"></a>SEA-RESIDENT | 居民与生活行为 | 生活 | SEA-WORLD, SEA-BUILD | [文档](docs/features/resident/spec.md) | [账本](docs/features/resident/ledger.md) | 规划中 |
| <a id="sea-time"></a>SEA-TIME | 世界时间 | 生活 | SEA-WORLD | [文档](docs/features/time/spec.md) | [账本](docs/features/time/ledger.md) | 已实现待完整验收 |
| <a id="sea-sleep"></a>SEA-SLEEP | 睡觉与次日醒来 | 生活 | SEA-TIME、SEA-MOVE、SEA-INTERACT | [文档](docs/features/sleep/spec.md) | [账本](docs/features/sleep/ledger.md) | 已实现待完整验收 |
| <a id="sea-weather"></a>SEA-WEATHER | 天气 | 生活 | SEA-TIME、SEA-WORLD | [文档](docs/features/weather/spec.md) | [账本](docs/features/weather/ledger.md) | 已实现待完整验收 |
| <a id="sea-aqua"></a>SEA-AQUA | 浅水养殖 | 经营 | SEA-WORLD, SEA-INVENTORY | [文档](docs/features/aqua/spec.md) | [账本](docs/features/aqua/ledger.md) | 规划中 |
| <a id="sea-quest"></a>SEA-QUEST | 任务成就与区域复兴 | 成长 | SEA-GOAL, SEA-WORLD | [文档](docs/features/quest/spec.md) | [账本](docs/features/quest/ledger.md) | 规划中 |
| <a id="sea-ui"></a>SEA-UI | HUD 与菜单反馈 | 表现 | SEA-INTERACT, SEA-INVENTORY | [文档](docs/features/ui/spec.md) | [账本](docs/features/ui/ledger.md) | 部分实现 |
| <a id="sea-ocean"></a>SEA-OCEAN | 水面与光照渲染 | 表现 | SEA-WORLD | [文档](docs/features/ocean/spec.md) | [账本](docs/features/ocean/ledger.md) | 部分实现 |
| <a id="sea-ambient"></a>SEA-AMBIENT | 环境植物与生活表现 | 表现 | SEA-WORLD | [文档](docs/features/ambient/spec.md) | [账本](docs/features/ambient/ledger.md) | 部分实现 |
| <a id="sea-save"></a>SEA-SAVE | 存档与恢复 | 基础 | SEA-BOOT, SEA-INVENTORY | [文档](docs/features/save/spec.md) | [账本](docs/features/save/ledger.md) | 部分实现 |
| <a id="sea-sfx"></a>SEA-SFX | 环境与交互音效 | 表现 | SEA-INTERACT | [文档](docs/features/sfx/spec.md) | [账本](docs/features/sfx/ledger.md) | 规划中 |
| <a id="sea-music"></a>SEA-MUSIC | 场景音乐 | 表现 | SEA-BOOT, SEA-WORLD | [文档](docs/features/music/spec.md) | [账本](docs/features/music/ledger.md) | 规划中 |
| <a id="sea-asset"></a>SEA-ASSET | 美术组件生产与登记 | 生产 | — | [文档](docs/features/asset/spec.md) | [账本](docs/features/asset/ledger.md) | 部分实现 |
| <a id="sea-quality"></a>SEA-QUALITY | 验证与性能治理 | 工程 | SEA-BOOT | [文档](docs/features/quality/spec.md) | [账本](docs/features/quality/ledger.md) | 部分实现 |
| <a id="sea-release"></a>SEA-RELEASE | 导出与发行 | 工程 | SEA-QUALITY | [文档](docs/features/release/spec.md) | [账本](docs/features/release/ledger.md) | 部分实现 |
<!-- FEATURE_CONTROL_END -->

## 11. 跨功能交接与推进顺序

经营主链：采集/打捞/种植 → 背包 → 订单或出售 → 仓储与建造 → 设施和船升级 → 更多种植空间与探索。UI 发送命令、显示结果；存档收集各所有者快照。资源写入由库存所有者执行，业务模块负责本功能状态。

工程推进顺序：文档与账本闭环 → 功能目录和接口 → 独立专项 → 正式游戏集成 → 真实表现 → 发行验证。每个阶段的事实与缺口在对应功能账本登记，不用总完成度百分比代替证据。

- [资产总索引与分账本](assets/registry/README.md)支撑各功能，不取代独立功能账本。
- [结构门禁与运行验收](docs/standards/工程管理规范.md)是持续维护入口。
- [历史开发计划](docs/archive/pre_split_20261023/开发计划_V1.0.md)和[历史功能计划](docs/archive/pre_split_20261023/功能重做计划.md)保留未完成设计与原始依据，当前调度以本页及独立功能文件为准。
