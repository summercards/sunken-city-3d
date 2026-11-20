# SEA-DIVE · 潜水探索与宝箱

[主文档中控](../../../GDD_V1.0.md#sea-dive) · [本功能账本](ledger.md)

设计修订：r1（2026-10-23 工程拆分，未更改玩法数值）。所属系统：探索。
范围来源：主文档保留的全局设计、拆分前文档与当前代码核对；下面明确区分目标与实现边界。

## 功能目的与边界

正式或规划入口：潜水入口按来源海域切换独立海底地图，探索发现宝箱。2026-11-08 起潜水在默认 PlayScope 重新开放，阳光房附近下水进入「家园海底」。旧四个 region 作为复用内容组件，不再表示所有海域共用一张常驻地图。

本功能以这一玩家行为或工程交付闭环为管理粒度，内部操作作为设计条款逐项承接；不按脚本数量拆功能。跨功能前置和关系由主文档本行统一维护。

## 设计条款与验收标准

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-DIVE-R01 | 氧气随深度、运动与头灯消耗，归零强制上浮并恢复冷却，不扣已有资源。 |
| SEA-DIVE-R02 | 宝箱先发现再交互，未发现不显示可点击目标；搜索完成才给奖励。 |
| SEA-DIVE-R03 | 存档记录宝箱发现/开启状态，恢复采用全量复位；读档回到海面而非恢复中途潜水。 |
| SEA-DIVE-R04 | 潜入、游泳、上浮使用公共状态机生命周期；搜索、移动、镜头、姿态各自独立动作，不直接访问经济全局。 |
| SEA-DIVE-R05 | 海底鱼群复用场景装饰/动物组件，由潜水表现层注入时间与深度材质；不接管鱼类资源、宝箱或存档。 |

## 所有者、接口与数据

状态/交付所有者：**UnderwaterWorld / DiveAir / 阶段状态机**。正式代码和资源入口：

- [godot/src/diving](../../../godot/src/diving)
- [godot/scenes/underwater](../../../godot/scenes/underwater)

读取上述所有者的公开查询，修改通过其命令或交互入口；事件由拥有该状态的对象发出。具体公开方法、信号和持久化字段见本账本的接口清单。原有稳定 ContentID、场景 ID 和存档键保持不变，重命名须另做迁移。

共享资源的所有权以被依赖功能为准。本功能引用它们，不复制背包数值、资产记录或其他功能规则。规划中的接口尚无实现时必须先补契约再编码。

## 当前实现与待完成边界

潜水已拆为 surface/enter/swim/exit 状态及7个独立动作；UnderwaterWorld 保留几何与内容装配，奖励回调注入。真实深度、透明渲染和设备性能仍需专项 GPU 验收。

2026-10-27 接口：dive / surface / swim_to / cancel_navigation / to_dict / from_dict；phase_machine；exited、air_changed；give_resource 注入。

详细所有权、状态转换与扩展方法见 [模块接口约定](../../architecture/module_contracts.md)；实测范围见 [框架交付记录](../../development/2026-10-27_modular_framework.md)。原目标中尚未实现的内容保持登记，不因架构拆分自动升级完成度。

## 验收入口

通过主文档定位本功能后执行账本列出的检查。正常、拒绝、取消/重复、存档恢复均按适用范围记录；真实渲染、听验和设备项单列。本次使用统一 runner 的隔离存档项目，不能直接拿玩家存档做测试。

## 来源与交付记录

- [拆分前完整主文档](../../archive/pre_split_20261023/GDD_V1.0.md)
- [拆分前功能计划](../../archive/pre_split_20261023/功能重做计划.md)
- [本次工程拆分记录](../../development/2026-10-23_feature_split.md)
- [godot/UNDERWATER_RENDERING.md](../../../godot/UNDERWATER_RENDERING.md)

2026-10-27 接口收口：公开头灯与诊断入口：toggle_lamp / uses_underwater_environment。

## 2026-11-07 按来源海域切换独立地图

本节是现行规则，覆盖前文统一海底几何/所有者的历史描述，不改R01–R05的稳定ID与原玩法数值。状态仍为 `partial`；Main装配稳定 `DiveSession`，它唯一持有全局进度与共享 `DiveAir`；`UnderwaterWorld`只拥有当前地图的阶段/动作、内容与表现。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-DIVE-R06 | 生产入口经注入source_query解析稳定来源ID：岸上使用GameState.current_zone；船上在实际已安装、Scope启用且catalog有映射的区块中，按各自TSCN实际泊位global_position的XZ距离取最近者，近似等距按来源ID稳定仲裁。划分覆盖整个海平面，无有限半径限制，不取zones.json参考origin、不取显示名称作为map key；没有有效来源则拒绝，不回退家园。 |
| SEA-DIVE-R07 | 每来源海域唯一map_id与独立TSCN，目录9来源含规划zone3/4，目录存在不自动把海面区块装回Main。各图复用旧basin/neighborhood/reef/trench资产，以不同组合、出生点、宝箱及鱼群子集区分，不宣称9套新美术。配置及几何/碰撞归属一致：街区solids 0..32、海沟33..42，移除region同时撤对应碰撞；无海沟图封闭原北口；setup返回bool，失败不得继续运行半初始化地图。 |
| SEA-DIVE-R08 | 先校验目录、场景必需节点、map_id/基数与数据可用性，再把同一Main移出树缓存；不free、不重建、不读档。稳定DiveSession临时留在树根，SceneTree.current_scene切为唯一海底runtime；地图拥有本地WorldEnvironment、DiveCamera、潜水角色及HUD，海面时钟/天气/经营/自动存档暂停。runtime.setup使用本地环境并继续验证出生点完整入水段、宝箱站位及内容结构，失败回滚同Main，重复/重入拒绝。 |
| SEA-DIVE-R09 | 正常或缺氧上浮返回同一Main实例及原船/角色姿态、角色模式、相机、环境，卸载海底runtime，恢复原外部信号/可见性、GroundSpace及必要表现端口；不能用重读存档或重跑Main._ready恢复。DiveAir在稳定会话跨图共享，卸载/改选地图不能清空恢复冷却，海面继续推进换气/冷却；氧气归零仍不扣已有资源。 |
| SEA-DIVE-R10 | 进度保持根v4原 `dive:{found:int[],opened:int[]}`；zone1原0..4保留，其它固定百位基数100..800加各图局部子集，全局ID唯一且不重编号。稳定会话保留未知ID与未加载图进度，返回合并当前图结果；from_dict是全量覆盖，必须清除现场旧进度再应用，不叠加读档。无需map_id必填扩展，不换key、不重复发已开启奖励。active/switching经SnapshotRegistry.busy_query拒绝直接SaveGame.write及中间快照，不只屏蔽UI。 |
| SEA-DIVE-R12 | 宝箱通过注入give_rewards整份原子入包，背包不足不发部分奖励、不记已开启，地图本地消息说明原因；已开箱重复请求不再奖励。独立HUD消费当前图氧气/水深，30%橙/15%红告警，Esc暂停期间不耗氧，菜单能上浮。正常返回和异常地图销毁均释放runtime/挂起会话资源；正常返回保存原手摆Terrain3D实例、变换与top_level，不能让地形缓存退出中的潜水相机。 |
| SEA-DIVE-R11 | 默认PlayScope仍屏蔽潜水/灯入口，内部enter_map与显式开发回归不代表默认开放。旧underwater_world.tscn保留为旧资源，不在Main运行常驻；旧build_underwater.py只允许工程外候选生成，不覆盖正式maps或Main。海面World/SunkenCity及其海床继续纯观赏，本次不移动、不改造为潜水地图。 |

### 公开端口与内容维护

- `DiveSession.configure(host)`；装配注入 `source_query(position)` 与原子 `give_rewards(reward)->bool`（生产接Inventory.add_all；give_resource仅旧工具兼容）。命令 `dive / enter_map / surface / abort_to_surface / swim_to / cancel_navigation / toggle_lamp`；事件 `depth_changed / zone_changed / air_changed / message / exited`；快照 `to_dict / from_dict`。`runtime / active / switching / source_id / map_id`供只读诊断，兼容转发不作为新增私有写入口。
- `DiveMapCatalog.source_ids / get_map / validate`只管静态目录与副本查询，不持实例、会话或进度。2026-11-08 追加 `home_map()` 与 `is_home_water(point, anchor)`：家园海底是世界对齐目标，不进 `source_ids()`，`validate()` 一并校验其唯一 map_id 与场景路径。`UnderwaterWorld.setup(surface_nodes, world_env) -> bool`在地图ready后接收本地环境；生产传空海面节点表，不从已出树Main借环境。
- [九图目录与配置表](../../development/2026-11-07_dive_map_switch.md#3-九图目录与配置快照)逐项摘录catalog和正式TSCN；修改内容时保持稳定全局宝箱ID，不按当前排列重新编号。

### 本轮验收状态

最终统一runner实测：`dive-maps`312/0、`visual-dive-maps`322/0，九图真实渲染；`modules`31/0、`framework-integration`52/0、`click`39/0、`minimum-loop`147/0以及存档种子/保护均exit0、无非预期错误。九张近景已目检，属于机制验收与旧内容组合，不是九套新美术或全空间/性能签署。旧综合selftest511/24与全局资产/内容/哈希漂移单列未通过；低端GPU、全部人工探索、手柄触屏未执行。[完整结果与边界](../../development/2026-11-07_dive_map_switch.md#10-最终实测与签署)。

## 2026-11-07 阳光房下独立水下区域（独立预览）

| 条款 ID | 规则与验收 |
|---|---|
| SEA-DIVE-R13 | 独立 `sunroom_region.tscn`复用当前SunkenCity、SunkenSeabed与SolarCabinBase，本轮不写Main、原9图或catalog。city逻辑域240×240、terrain1024×1024、water1280×1280（与原Main同尺寸），各域长宽一致；海面Y=1.12、旧城根Y=43.487442和基座原矩阵保持。海床实测-62..-18.562597、最大深63.12米；城市实测包络P(-120,-38.65286,-120)、S(240,37.00966,240)，最高-1.64320、海面余量2.7632米，不混用逻辑域和几何包络。追加鱼/珊瑚/设施灯仅观赏，不新增玩法、碰撞、宝箱奖励或存档。最终205426-signed专项67/0、真实渲染89/0均exit0/PASS；只签独立场景，F6及右键＋WASD/QE/Shift为预览控制，不代表玩家潜水接入。production_route_integrated=false，原9来源及默认屏蔽保持，不称第10可潜水图或默认已开放；集成minimum-loop147/1仍FAIL，全局静态与来源/性能/用户美术等未验项另列。 |

[最终交付、过程与未验边界](../../development/2026-11-07_sunroom_underwater_region.md)。

## 2026-11-07 阳光房水下美术 r2 与独立区域阻挡（已独立验收，产品未接入）

本轮追加覆盖 R13 中“不新增碰撞”的阶段限制，仅对独立 `sunroom_region.tscn` 生效；R13 原记录及旧结果保留，不外推到海面主场景或原9图。初填时三个专项均pending，当前已有下述独立场景实测，不再以初填状态代表当前结果。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-DIVE-R14 | 新区域按实际 Mesh/MultiMesh 实例建立 exact `ConcavePolygonShape3D`、backface_collision 代理，非均匀缩放/剪切烘入形状，以mesh＋deformation缓存并immutable复用；保持真实洞口/桥下/凹形空间，不用整包AABB替代。最终实测758 proxy、85 uniqueMeshes、3115351 instanceTriangles；physicsrun缓存99、visual缓存158，同一精确Basis key受启动浮点拆分影响，缓存数不强求相同，各角色数量/assemblies/triangles一致，50源GLB不动；原9图手工solid不改。Terrain3D仅本实例collision_mode=3，不改高度源/data/material/assets。Viewer胶囊半径0.35米/高1.6米，move_and_collide每段≤0.75米、每段最多8slide，总预算2048steps/4096tests，余量0.001米，Shift 8→18米/秒；水面下中心上限=1.12−0.8−0.02=0.30米。raw set仅测试fixture；try_set拒绝重叠/越界，F6出生延迟至物理提交后校验。当前sunroom-collision264/0覆盖100米请求thinwall两轴接触误差<3厘米、全部8roles至少1抽样、海床/桥下路口/斜滑/安全定位，不冒称每个三角面均测。setup1834.253ms/load256.285ms为单次建树记录，非FPS通过；低端/连续运行与性能签署仍pending。scope只限本独立scene，可供未来角色复用，未接production player、路由或存档；toplevel、位置、范围、深度不变，不新增宝箱/奖励，仍F6、production_route_integrated=false。本任务不改Main；Main 可能被并行修改，不要求 Main 字节不变。 |

美术归SEA-AMBIENT-R24，资产归SEA-ASSET-R60。[最终证据与静态门禁回填位](../../development/2026-11-07_sunroom_underwater_art_r2.md)。最终报告：`D:/projects/sea-work/verification/20261107-232826-sunroom-art-r2-signed-5f3e30/report.json`：sunroom-underwater78/0、sunroom-collision264/0、visual118/0，新区域460/0；dive-maps302/0、modules31/0，回归333/0；五入口总793/0，全部PASS/exit0无unexpected。225915为中间历史，运行final已签署。旧100米cast保守停靠约0.09米导致接触精度断言未达标，不是穿透或阻挡失败；≤0.75米substep修正精度，最终误差<0.03米。local env/sky/material均resource_local_to_scene保护多实例。登记工具执行中，实际成功及sync/check真实输出由父线程补；低端/连续performance/rights/user acceptance/02b/production仍pending。

## 2026-11-08 潜水重新开放与“家园海底”（现行）

本节覆盖 R11 中“默认屏蔽潜水入口”的阶段限制，R11 原记录保留为历史。**潜水在默认范围重新开放**：`dive / lamp / rise / descend` 随家园海域可用；`build / hook / camera / orders / salvage` 仍不在最小循环范围。功能状态仍 `partial`（设备、低端性能、美术深化未签）。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-DIVE-R15 | 第 10 个潜水目标“家园海底”按**世界坐标**归属而非海区 ID：`DiveMapCatalog.home_map()/is_home_water(point,anchor)` 提供唯一 `dive_home_seabed` 映射，锚点取 `zone1 → 太阳能木屋` 的实际 `global_position`，不写死坐标；水平半径 `entry_radius=60` 米，`domain=Rect2(-120,-120,240,240)`。`source_ids()` 仍为 9 条，原 9 图 map_id/场景/宝箱基数不变，家园不占来源 ID，也不作为第 10 条海区。 |
| SEA-DIVE-R16 | 入水点 = 海面点的同 XZ 正下方，仅在结构占位时就近避让：候选环 16..30 米（`entry_search_radius=30`）内、12 角度、路面 +6/8/10/12 米四层，须满足 ① 半径 12 米球形净空（排除贴墙）、② 头顶 16 米内无楼板（排除基座内腔）、③ 某方向存在 18~38 米楼体（排除空广场），取目标 26 米最接近者作初始朝向。**碰撞延迟提交**是硬前置：先 `enter` 阶段占点，等垂直向下确实打到海床（<119/120 米）才算物理就绪，再选点；否则射线全为“无遮挡”，会选中基座内部。找不到满足条件的点逐级放宽，最终保底“有净空即可下水”，不把玩家卡在海面。 |
| SEA-DIVE-R17 | 家园海底复用 `sunroom_region.tscn` 全部内容（旧城 50 组件 388 实例、4 区海床、原基座、8 群 138 鱼、32 珊瑚、24 设施灯、192 气泡、200 悬尘、10 条软射光），水位 Y=1.12、旧城根 43.487442、240×240 城域、1024×1024 海床、最深 63.12 米均不变。在 F6 预览之外追加潜水契约：`begin_dive(surface_point)->bool`、`enter/swim/exit` 三阶段（exit 0.55 秒可见上浮）、`swim_to/cancel_navigation/toggle_lamp/surface/abort_to_surface`、`depth_changed/zone_changed/air_changed/message/exited`；阻挡沿用 R14 的 758 精确代理与 ≤0.75 米分段扫掠；氧气共享 `DiveAir`，入水固定水面下 6 米以越过 5 米换气带；本地 HUD 显示「家园海底 · 氧气 · 水深」，无宝箱时不显示发现计数。 |
| SEA-DIVE-R18 | 家园海底无宝箱，`to_dict()` 仍返回 v4 的 `{found:[],opened:[]}`，不新增存档键、不扩字段、不改根版本；返回海面走同一 `DiveSession._commit_return`，恢复原 Main 实例、船人姿态、相机与环境。长潜水后返回时只重连仍存活且尚未连接的脚本信号，Terrain3D 原生信号随重新进树自动恢复不重复连接。 |
| SEA-DIVE-R19 | 默认范围断言随开放更新：`PlayScope.command_enabled` 允许 `dive/lamp/rise/descend`，HUD 潜水按钮不再置灰，角落菜单在最小循环也保留潜水入口；`minimum-loop` 只断言入口可用与其余入口仍锁定，实际下潜/返回由 `dive-maps` 覆盖。`minimum-loop` 不再断言“潜水命令锁死”。 |

最终实测（`D:/projects/sea-work/verification/20261108-055128-dive-home-seabed-signed2-00d74f/report.json`，九入口全部 exit0/PASS、无 unexpected，合计 1270 项 0 失败）：dive-maps 323/0、visual-dive-maps 335/0、framework-integration 52/0、minimum-loop 148/0、modules 31/0、click 39/0、sunroom-underwater 78/0、sunroom-collision 264/0、save-seed PASS。真实渲染的入水画面已目检：旧城楼房、街道、翻倒车辆与远处街区可见，镜头不贴墙、不落在空广场、不陷入基座内腔。[完整机制与踩坑记录](../../development/2026-11-08_home_seabed_and_dive_reopen.md)。低端设备、连续性能、全路线人工探索、用户美术终审仍未签；家园海底无宝箱/无独立奖励，不宣称新增收集内容。

## 2026-11-08 家园海底第三人称、独立布局与 35 米深度

| 条款 ID | 规则与验收 |
|---|---|
| SEA-DIVE-R20 | 进入家园海底不再是第一人称：独立 `DiverVisual` 复用 `res://src/player/character.gd` 的程序化角色、`build()`、`set_diving(true)` 与 `res://src/player/animation/swimming_action.gd`；角色只负责表现，`ViewerBody` 仍是唯一移动/碰撞权威。角色跟随真实 ViewerBody 速度和朝向，潜水装备/潜水镜可见；第三人称相机距角色 5.5m、高度 1.0m、射线避障，F6 非潜水预览不接管相机。 |
| SEA-DIVE-R21 | 家园海底作为独立可编辑布局：`sunken_city_layout.tscn`、`sunken_seabed_layout.tscn`、`solar_cabin_submerged_base_layout.tscn` 均由 shared 包装复制为本地 TSCN；`sunroom_region.tscn` 只引用这三份本地布局，Main 仍引用 shared 场景，用户可在本地布局里移动/增删旧城实例和基座而不改海面 Main。旧城 GLB 组件引用保持 shared，Terrain3D 数据暂仍为 `res://terrain/sunken_seabed`，metadata 明确 `shared_terrain_data_pending=true`，没有伪造新高度图。 |
| SEA-DIVE-R22 | 家园海底的可游深度契约目标为 35m：水面 Y=1.12，Viewer 最低中心 `viewer_min_y=-33.88`，胶囊离海床 0.8m，局部参考 `lowest_seabed_y=-34.68`，运行时移动夹限以本地契约为准；低于边界的旧城几何保留为视觉，直到独立海床高度图正式制作。`sunken_seabed_layout.tscn` 的共享 Terrain3D 数据边界仍是 pending，不把 export 改值冒充真实新海床。 |
| SEA-DIVE-R23 | 家园海底局部表现优化：深度/角色深度驱动水色与吸收；单一 `Camera/WaterFogPass` 做连续分层雾，避免 Environment fog 与屏幕雾双重抹黑；本地 palette 加深度吸收与轻焦散；beam 采用 16 步深度挡墙积分、上下软边、远景 fade；原确定性 192 气泡/200 悬尘/10 射光保留，未修改共享水材质、WorldEnvironment、原9图。网络技术参考 Godot 官方 Volumetric Fog/FogVolume、GPUParticles3D、Sky shader 与水体深度/Fresnel/caustics 资料；本轮选择低风险本地通道，未无条件开启高成本体积雾。 |

最终专项回归：`D:/projects/sea-work/verification/20261108-123311-home-seabed-thirdperson-final-d703fe/report.json` 九入口全 PASS/exit0、无 unexpected，合计 1241 项 0 失败：dive-maps 326/0、visual-dive-maps 338/0、framework-integration 52/0、minimum-loop 112/0、modules 31/0、click 39/0、sunroom-underwater 79/0、sunroom-collision 264/0、save-seed PASS。第三人称实拍已目检：角色、潜水装备、楼房、翻倒巴士、街道与射光均可见；真实布局姿态检查通过，35m 深度契约与本地 TSCN 布局检查通过。注意：`sunken_seabed_layout.tscn` 仍共享高度数据，35m 是当前可游边界契约，不是全新 Terrain3D 高度图验收。
## 2026-11-08 水面抬高 50 米与雾/环境对齐旧九图（现行）

| 条款 ID | 规则与验收 |
|---|---|
| SEA-DIVE-R24 | 家园海底按用户要求再下探 50 米，实现方式为**抬高水面、不动几何**：`water_level` 1.12→51.12，`Water` Mesh Y 同步 51.12，旧城根 43.487442、388 实例、4 区海床、基座原矩阵、138 鱼、32 珊瑚、24 灯全部保持原值，Main／原 9 图／catalog 未改。旧城街面 Y≈-18 由约 19 米水深变为 69 米，头顶到水面为连续水柱。深度契约：`target_depth_m` 35→85，`viewer_min_y` 仍 −33.88（既等于 51.12−85，也等于 `lowest_seabed_y` −34.68+0.8，双重校验成立），运行时中心最高点 51.12−0.82=50.30；海床实测最低 −62、最大深 113.12 米，低于 −33.88 的旧城几何仍只作视觉。metadata 记 `depth_basis=sea_surface_raised_50m_geometry_unchanged`、`city_deepened_by_m=50`、`water_level=51.12`，asset_version v002→v003。 |
| SEA-DIVE-R25 | 入水占位改按旧城街面而非水面：新增 `entry_street_y=-18`、`entry_rise=10`，`begin_dive` 占位取 (x, −8, z)，`_entry_spot` 的路面搜索同引用该常量。水面抬高后若仍用「水面下 6 米」（=45.12）占位，碰撞提交前的若干帧镜头会停在 51 米空白水柱里、再瞬移 50 米落到街上，观感等于切错场景。选区判据（16~30 米环、12 角度、路面 +6/8/10/12、半径 12 米球形净空、头顶 16 米无楼板、某方向 18~38 米楼体、取 26 米最接近者）全部保留，不因变深放宽。 |
| SEA-DIVE-R26 | 家园海底雾与环境改为与 zone1 逐行同源，替换此前自算模型（公式、参数与取舍见 SEA-AMBIENT-R26）。`region_fog_amount` 由 `pow(smoothstep(6,110,d),1.3)` 改为 `1−exp(−(d×density)^1.8)`，30 米处浓度 0.08→0.48；背景／水面／终端雾统一 `uw_gradient_display(SCREEN_UV, 深度)`，删除方向渐变、水平分层、XZ 448..500 米边缘吸收三处叠加；环境光改回 SKY 半球双色并按 `1.9/π×(1−deep×0.6)` 衰减；glow／SSAO 关闭、两条方向光归零、FOV 68→55。不改共享水材质、`world_env.tres`、原 9 图。 |
| SEA-DIVE-R27 | 家园海底布局用同一批旧城组件搭「回字型深沟」：**沿矩形四边直线摆放**，外框半宽 112 m（每边 7 个／间距 37.33 m，共 24 个）、内框半宽 72 m（每边 5 个／间距 36.00 m，共 16 个），合计 40 栋，沟宽 40 m；引用 `sunken_city_tall` 的 v008 封闭组件，尺度 2.0 倍。每条边上的楼 X 或 Z 必须完全相同，朝向只允许 0/90/180/270 且朝框内，不加随机抖动。楼基取最近地面组件顶面，行内相邻楼体平面重叠不得超过 1 m。**新增实例不得删除或改动任何已有实例**——位置归用户，重叠处由用户手工取舍。 |
| SEA-DIVE-R28 | 沟壁节点（`tall_*`）不参与生态接地：`_build_surface_index` 必须跳过它们，珊瑚与设施灯只能贴在旧城街面与坡地上，不得被抬到塔身或塔顶。 |
| SEA-DIVE-R29 | 家园海底水面 = 上街面 + **120.0 m**，当前 `water_level = 101.587442`（上街面 −18.412558）。**「底部」一律指上街面**，不取最低海床台面。`target_depth_m` = 120.0，`viewer_min_y = water_level − 120.0 = lowest_seabed_y + 0.8`，两项必须同时成立。改水面时 Water 节点、atmosphere 的 `WATER_LEVEL` 与深度契约必须同步。 |
| SEA-DIVE-R30 | 入水点停在**水面下 1.0 m**（`entry_depth_below_surface`），不再落在街面层。因为 `DiveAir` 的换气带是 5 m、会让入水点永远满氧，家园海底必须把可覆盖的 `surface_depth` 设成 0.5 m；其它地图保持默认 5.0。浅水层被占满时才允许回退到原街面搜索。 |
| SEA-DIVE-R31 | 雾密度曲线只按前 85 m 水深取密度（`min(region_view_depth, 85.0)`），深水不得比浅水更稀，否则远景海床会从雾里浮出。 |

本地专项 `tests/test_sunroom_underwater_region.gd` 已按新契约改写（水面 51.12、最深 113.12 米、target 85 米、viewer_min −33.88），结果为 80 项 0 失败；真实渲染器加载本场景无着色器编译错误。**九入口批量回归未在本轮重跑**，低端设备、持续性能、全路线人工探索与用户美术终审仍未签署，本轮不据此宣称全工程绿。深度仍以 `lowest_seabed_y=-34.68` 这一共享海床引用为参照，独立 Terrain3D 高度图继续 pending。

## 2026-11-08 统一潜水 3C（最终口径覆盖，验收 PENDING）

本节覆盖前文“家园与旧九图分别拥有阶段/输入/氧气/相机”及旧 5.5m/FOV55 等 3C 口径；历史条款和结果保留，不重新签署。R27/R28 已用于高楼布局/生态排除，本次从 R29 连续新增，不借用或重编号旧 ID。功能仍为 `partial`。开发与验收回填见 [统一潜水 3C 记录](../../development/2026-11-08_unified_dive_3c.md)。

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-DIVE-R29 | 海面/陆地共用一套独立 `ActorController`；潜水共用另一套独立 **Shared DiveRuntimeController**，实际脚本 `godot/src/diving/dive_runtime_controller.gd`。家园 + 旧九图均使用同一 `surface → enter → swim → exit → surface` 生命周期，不是海面/家园/旧图三套状态机，也不是每图复制一份潜水逻辑。两域只经 DiveSession 挂起/恢复交接，不同时推进。 |
| SEA-DIVE-R30 | Map 适配只提供内容、入口、位置、碰撞执行、route、camera_clip、env、explore：`dive_begin/entry_tick/exit_begin/exit_tick/end`、`dive_position/set_position/move/water_level`、`dive_route/cancel_content/content_tick/camera_clip/zone_label`。控制器唯一解释潜水输入、推进阶段/运动意图、潜水耗氧、相机姿态和角色表现；Map 不再独立 tick 潜水输入/氧气/相机。`phase/phase_machine` 仅兼容旧测试并转发当前控制器；无控制器夹具的兼容对象不得变成生产第二状态机。旧 enter/surface/finish_exit/swim/camera/diver_pose actions 及旧阶段驱动不得继续运行；`search_action` 仅可作为 explore 内容搜索执行，不得接管 3C。 |
| SEA-DIVE-R31 | `DiveSession` 保持事务切图：preflight/setup 失败回滚；挂起并恢复**同一 Main 身份**及原船人姿态/模式/相机/环境，不 free/rebuild/read-save 代替恢复。active/switching 的直接写盘门禁继续有效。根 v4 `dive:{found:int[],opened:int[]}` 不变，固定宝箱 ID、未知 ID 与未加载图进度保留，from_dict 全量替换；奖励通过 give_rewards 原子提交，满包不部分发奖/不标开启。共享 DiveAir 由稳定 Session 持有；潜水控制器推进潜水耗氧，Session 仅在海面推进换气/cooldown，切图或卸载不得重置冷却、不建立第二份 air。 |
| SEA-DIVE-R32 | InputMap 使用 `dive_left/right/forward/back/up/down/sprint`：A/D/W/S + 对应方向键；Q 或 Ctrl 下潜，E 或 Space 上升，Shift 加速。巡航 4.2m/s、加速 7m/s；ACCEL_TAU=0.22s、BRAKE_TAU=0.16s、反向 tau=0.13s，为指数平滑时间常数而非精确到速/停止时长。WASD 无需右键；右键只环视，不是游动使能键。手动输入取消自动路线。 |
| SEA-DIVE-R33 | 自动游动仅在左键 release 时判定：按下至释放位移 ≤8px 且期间未超过 8px 才作短点击；拖拽不误触。目标经 Map.dive_route 拒绝不可达路径，不退化为穿墙直线；受阻停止并反馈。滚轮调整第三人称距离 4..13m，默认 7.5m。 |
| SEA-DIVE-R34 | 潜水广角 FOV72°、加速渐变至78°；pitch 限 [-1.1,1.15] 弧度，yaw 平滑 tau=0.07s。镜头直接继承主体位移，速度前视 0.10s，避免阻尼追赶角色；无镜头滚转。防墙调用半径 0.32m 的 camera_clip：收回立即、离墙缓出，插值后再做最终 clip，不能用平滑跨越阻挡。Map 提供空间裁剪，不拥有第二套镜头状态。 |
| SEA-DIVE-R35 | 复用 Character 模型/骨骼，但潜水创建**独立实例**，不挪用或改写海面角色实例。动画消费碰撞后的实际速度，不以按键/期望速度假游；float / cruise / sprint 连续混合，垂直速度驱动上升/下降 pitch，转向驱动 turnbank。hat/mask 由潜水装备生命周期切换：入水保存帽子可见性、隐藏 hat/显示 mask，退出还原；海面 idle/walk/rowing 等动画不改，模型表现不写位移/奖励。 |
| SEA-DIVE-R36 | 家园与旧九图统一 `godot/src/diving/dive_map_hud.gd`：海底墨绿半透明板 + 奶油按钮；氧气 bar/百分比、深度、地图/游动状态、键位 hint、头灯及消息统一展示，30%/15% 告警不回退；无宝箱不展示虚假发现总数。Esc 打开暂停菜单，暂停不耗氧，可继续或上浮；UI 只读状态并经 Session 发命令，不直接改 air/phase/位置。 |
| SEA-DIVE-R37 | 本批只改 3C 文档，不改家园水面 51.12m、可游深度 85m、viewer_min_y=-33.88，也不动用户手摆 layout、Base2（SolarCabinBase2）与现有 40 栋高楼。位置/数量以当前 TSCN 为准，历史“388 实例”仅为当时快照，不作当前固定断言；不得为通过测试回退手摆布局。真正独立的 Terrain3D 海床高度数据仍 pending，不把包装或移动边界当独立海床验收。 |
| SEA-DIVE-R38 | 当前统一 3C 验收独立登记，不能借旧 PASS：behaviour 暂报 [403 或 396]/0，准确入口名/批次/计数由主线程最终回填；初批 dive-maps326/0、click39/0、framework-integration52/0 虽断言零失败，但 resource leak 导致批次 FAIL、修复中，不宣称通过。curved collision 3448/42 为必须保留的 FAIL 历史，未获本轮精确复测不得签通过。最终报告、exit/unexpected/leak、截图审阅和全局检查分别 PENDING。 |

主线程唯一最终运行签署位置：[开发记录第 5 节](../../development/2026-11-08_unified_dive_3c.md#unified-dive-3c-acceptance)。本分支只作源码核对和文档追加，不执行 Godot，不升级历史结果；真实 3C 手感、全十图、设备/连续性能及用户终审仍须按实测签署。

## 2026-11-08 统一潜水 3C 最终验收结果

本批已按 SEA-DIVE-R29–R38 完成隔离回归与真实渲染验收。最终报告：`D:/projects/sea-work/verification/20261108-202515-dive-unified-final-edbd96/report.json`。

| 入口 | 结果 |
|---|---:|
| dive-control | 396/0 |
| dive-maps | 326/0 |
| visual-dive-maps | 338/0，真实渲染 |
| sunroom-underwater | 83/0 |
| sunroom-collision | 3313/0 |
| click | 39/0 |
| framework-integration | 52/0 |
| minimum-loop | 112/0 |
| modules | 31/0 |
| keyboard-control | 30/0 |
| control-feel | 31/0 |
| character-motor | 42/0 |

上述入口均 exit0、无 unexpected。操控专项实际验证了十张海底地图共用同一控制器、WASD 无需右键、点击游/拖拽区分、4.2/7m/s、加速/刹停/反向、FOV72/78、4..13m镜头距离、相机防墙、实际氧气一次消耗、float/cruise/sprint 动画、角色正Z朝运动方向、hat/mask 生命周期和 HUD。真实输出位于该 run_dir 的 `project/outputs`，包含 home/zone1 等运行画面与 `dive-control-report.json`。

边界仍保持：低端 GPU、连续运行性能、全路线人工探索、用户美术终审和独立 Terrain3D 海床高度图未签；旧 `curved collision 3448/42` 失败报告保留为历史证据，不被本批 3313/0 覆盖或抹除。

## 2026-11-08 统一潜水3C最后修正与签署

以`D:/projects/sea-work/verification/20261108-205037-dive-unified-signed-2f2292/report.json`为当前有效证据，覆盖前述中间批次和PENDING状态但不删除历史。13个计数入口合计5196/0，另save-seed前置PASS；报告14项全部exit0/PASS、无unexpected。dive-control为396/0，visual-dive-control为403/0（真实渲染增加7项），dive-maps326/0、visual-dive-maps338/0、sunroom-underwater83/0、sunroom-collision3313/0及海面/基础回归均通过。

家园入水保底点不再放进基座内腔或仅以“净空”跳到空水柱；按真实街面与净空在落水XZ附近搜索，允许水平避让，不承诺XZ零偏移。实际生产入水图显示旧城街区而非封闭窗墙内腔。水面51.12、可游85m、viewer_min-33.88与用户手摆布局保持，操控统一不改城市或Main的布局。

实测巡航约4.20m/s、冲刺约6.99m/s，当前固定步工况冲刺松键刹停约1.06m；广角72°至78°、镜头4..13m、动画按碰撞后实际速度、HUD/暂停/返回行为已验。海面ActorController独立，家园与旧九图只使用同一潜水控制器。低端设备、持续性能、全路线人工体验、用户美术终审与独立海床仍未签，功能总体仍partial。完整逐项签署见[开发记录第8节](../../development/2026-11-08_unified_dive_3c.md#8-最后修正后签署当前有效结果覆盖第5节待填和第7节中间批次)。

## 2026-11-08 水下光学与双向无文字圆幕（本轮规则，验收 PENDING）

先只读核对功能归属复用，再实施仰视海面、深度暗光/阳光、双向黑圈遮加载及呼气/环境泡增鱼。历史已有 R29–R31 的重复语义，本轮保留、不重编号，核对最大 R38 后从 R39 续写。家园采用最新 120m 口径，旧 51.12/85m/街景入水与旧 5196/0 仅为历史，不证明本轮通过；功能保持 `partial`。

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-DIVE-R39 | 稳定 DiveSession 拥有双向切图装配事务；Main 注入既有 SleepCurtain，复用 SEA-SLEEP-R05 / SEA-UI-R24 的像素圆幕和 cover_blank/uncover_blank，不造第二套幕或睡眠流程。关 0.85s、开 1.05s，全程无文字、不跳日。生产 request_dive(point,source)->bool 仅表示请求接受，结果经 transition_started/transition_phase/transition_completed/transition_failed 反馈；重入拒绝，低级同步 dive/enter_map 保留给原测试/工具，不冒充生产过场。 |
| SEA-DIVE-R40 | 合拢后等待真实 RenderingServer.frame_post_draw 已绘制全黑，才允许 load_threaded_request/get、instantiate、建树与碰撞装配；入口 verified（地图提供时）及共享控制器 swim 就绪，再提交角色/环境/相机准备帧才展开。上浮/缺氧返回亦先全黑再卸载 runtime、恢复 Main。headless process_frame 只算逻辑屏障，不签真实全黑；加载/校验/准备失败须在遮黑事务内回滚，不露半初始化场景。 |
| SEA-DIVE-R41 | switching 从接受至完全展开全程有效：锁玩法输入、点击游/镜头操作、耗氧与海面换气/cooldown推进、保存及日期/经营；黑幕内只放行必要 entry 物理准备。直接 SaveGame.write 与 SnapshotRegistry.capture 同受 busy 门禁。返回/失败恢复同一 Main 及原 curtain 的身份、parent/index、focus_query、处理模式、船人姿态/模式、相机/环境和 Economy ticking；不 free/rebuild/read-save、不重跑 Main._ready，不残留 runtime/借幕。 |
| SEA-DIVE-R42 | 家园保持 water_level=101.587442、target_depth_m=120.0、viewer_min_y=-18.412558、lowest_seabed_y=-19.212558、clearance=0.8，满足 water−120=viewer_min=lowest+0.8。入水优先水面下 1.0m、surface_depth=0.5m；仅浅层无净空才沿原安全搜索兜底，不回退常规街景入水。Water/氛围/材质消费同一水位；九图保留各自水位/换气带。用户 Main/ExistingModels/Base2 及原手摆布局不动，不用旧参考位/历史实例数修测试。 |
| SEA-DIVE-R43 | 本轮只记源码已接入与验收 PENDING；已存在入口 dive-transition、visual-dive-transition、underwater-experience、visual-underwater-experience 分列实测。transition 初始 Parse black、Main 子类引用 Autoload Zones 编译阻断、visual timeout，以及水下体验真实视觉 195/8、195/4 均保留 FAIL 历史；后续修复正在跑，不预签 PASS。最终报告/计数/exit/unexpected/leak、全黑与展开截图及人工审阅由主线程回填开发记录第 5 节，不借旧签署。 |

共享光学归 SEA-OCEAN-R26–R29；环境泡、呼气和鱼归 SEA-AMBIENT-R28–R31，不新增 Air 或玩法所有者。[本轮开发记录与最终待填](../../development/2026-11-08_underwater_optics_and_transition.md#underwater-optics-transition-acceptance)。

主线程最终结果已另追加至记录第7节：双向圆幕真实149/0、行为226/0，光学生态真实195/0/行为65/0；地图329/0、3C396/0、家园85/0、碰撞2824/0、切日42/0、房间112/0等通过。本轮请求功能专项完成，但框架第二代写盘52/1独立复跑仍失败，全局sync69/只读70资源门禁未过，不能宣称全批全绿。历史PENDING为委派阶段，不覆盖当前签署；低端/持续性能/历史远雾边界/独立海床等未签范围仍见记录。

## 2026-11-10 圆幕展开后可见入水（现行设计，运行验收 PENDING）

用户明确要求更新设计。本节核对既有最大 R43 后从 **R44** 连续追加，历史重复编号、原文及 PASS/FAIL 均保留；本节覆盖旧 R30/R42 的「水面下 1.0m」与 R40 等「必须 swim 才开幕」要求，不把旧批次通过视为本轮通过。功能仍为 `partial`，证据与主线程运行回填位置为 [入水表现开发记录](../../development/2026-11-10_dive_entry_splash.md)（主线程创建）。

| 条款 ID | 现行规则 / 应验证的行为 |
|---|---|
| SEA-DIVE-R44 | 复用同一无文字圆幕，cover **0.85s**；合拢并经真实 `RenderingServer.frame_post_draw` 确认全黑已绘制后，才加载、实例化、建树及准备碰撞/选点。控制器处于 **prepared enter**，且地图提供 `entry_verified` 时该值必须为真，即可准备初始角色、环境和镜头，再以 **1.05s** uncover；不再等待 swim 或完成下沉。整个 opening 角色位置与 Air 仍冻结，不能边开幕边下沉。圆幕必须彻底 `idle` 且不可见，随后 Session `transition_phase` 进入 `entering`，调用 `controller.release_entry` 才启动可见入水；不是新增控制器状态。headless 帧屏障不算真实 post-draw 证据。 |
| SEA-DIVE-R45 | 家园正常浅层入水：中心从水面下 **1.6m → 4.8m**，时长 **1.65s**。`u=clamp(t/1.65,0,1)`，统一 ease-out：`f=1-(1-u)^3`；向下位移 `s=3.2*f` 米，向下速率 `v=3*3.2/1.65*(1-u)^2` 米/秒，末速为 0。实际移动必须经 `move_viewer` 与胶囊完整段扫掠安全检查，不用视觉插值或位置直写穿墙；曲线是安全路径上的目标，受阻不能强制到点。横向避让/候选切换只在黑幕准备时发生，可见段不得横跳重选。浅层完整下沉段不通时保留原街面安全搜索兜底，不强迫浅层穿透或取消兜底。 |
| SEA-DIVE-R46 | 旧九图保留 **2.2s** 入水时长、终点世界 **Y=-10** 及完整入水段预检，仅统一为 `f=1-(1-u)^3` 的 ease-out（`u=clamp(t/2.2,0,1)`），末速为 0；实际移动仍走原地图碰撞执行端口。不能套用家园 1.6→4.8m 改掉旧图终点、水位或默认 5m 换气带。 |
| SEA-DIVE-R47 | Shared DiveRuntimeController 仍唯一拥有 `surface/enter/swim/exit` 四态，不增加 Splash FSM。Map 提供 `dive_entry_ready` 准备查询与 `dive_entry_progress` 进度查询；`dive_entry_tick` 执行已释放的入水段并反馈完成。控制器提供 `entry_is_prepared`、`release_entry`、`set_entry_view`：Session 只查询准备、设置初始视图并在原幕彻底退场后释放；prepared 是 enter 内握手，不是第五态。Map 不拥有第二份相机/输入/耗氧状态，Session 的 `entering` 仅为事务阶段。 |
| SEA-DIVE-R48 | 入水动画由碰撞后**实际位置差/dt** 驱动 velocity 与角色运动表现，不能直接消费期望曲线速率假游。进入 swim 的边界清零入水残速/运动历史，不把下沉末端惯性带入普通游泳；相机保持当前连续姿态，不能在 swim 切换时 snap 重置。opening 时实际位移为 0，角色不得提前播放由假速度产生的游动。 |
| SEA-DIVE-R49 | 入水镜头仍由同一 Shared DiveRuntimeController 拥有，消费同一 entry 进度：距离 **6.3→7.5m**、FOV **76→72°**、初始略仰逐步回基础 pitch；单次 heave 最大 **0.08m**，无 roll。初始视图在黑幕内准备、opening 保持，release 后才推进。沿用 **0.32m** camera_clip 的候选裁剪与插值后最终裁剪，立即收回/离墙缓出；不能为入水取消双 clip。普通游泳 FOV72°、冲刺78°、滚轮距离4..13m不动。跨链见 [SEA-CAMERA-R17](../camera/spec.md#2026-11-10-潜水入水镜头跨链现行设计运行验收-pending)：登记表现关系，不改 OrbitCam owner 或海面参数。 |
| SEA-DIVE-R50 | 一次性入水气泡为纯表现，池预算 **40**、本次发射 **16 颗**，复用既有气泡 shader；世界空间尾迹不粘在角色上，不重复触发成持续喷泡。入水结束/切到 swim 后已有尾迹继续更新至自然回收，不在状态边界截断。它不写氧气、不参与物理、不发奖励、不写存档，不替代既有环境泡或常规呼气；卸载仍按地图表现生命周期清理。 |
| SEA-DIVE-R51 | `switching` 与 `transition_frozen` 从接受请求持续到控制器到达 **swim** 才解除，不能在 uncover 结束即解除。整个 entry 的玩法输入（含导航/镜头操作）、save/capture、日期/经营、潜水耗氧及海面 Air 换气/cooldown 均冻结；释放后只放行入水运动/镜头/一次性表现，不放行普通游泳或耗氧。返回、缺氧、取消/失败仍走同 Main/原 curtain 恢复事务，不重建、不读档、不改身份及原处理模式。根 v4 与 `dive:{found:int[],opened:int[]}` 不改，用户 TSCN/手摆布局不动，家园120m与水位101.587442保持。 |

### 本轮预计验证入口与未签范围

- 已存在的 `dive-transition`：预计验证 prepared enter/verified 握手、opening 零位移与 Air 冻结、幕 idle 且不可见后才进入 entering/release、到 swim 才解锁；家园与旧九图的时长/ease-out/终点、完整胶囊扫掠与浅层失败兜底、实际速度动画、重复/失败/返回、直接 save/capture 门禁及同 Main/原 curtain 身份恢复。
- 已存在的 `visual-dive-transition`：预计验证真实全黑 post-draw 先于加载、1.05s opening 全程不下沉、彻底退幕后可见入水、镜头6.3→7.5m/76→72°/pitch/heave/无roll、双 clip 与 swim 无 snap、16颗世界尾迹到自然回收。静帧不替代连续时序/动画验收。
- 按影响范围预计复跑既有 `dive-control`、`visual-dive-control`、`dive-maps`、`visual-dive-maps`、`sunroom-underwater`、`sunroom-collision`、`framework-integration`；具体命令、批次、计数、退出码、unexpected/leak、截图与逐项审阅由主线程按真实结果回填。
- **当前运行测试 PENDING，不预签 PASS**。本次仅更新上述设计及承接文档，未运行 Godot、runner、sync；未创建开发记录、不改 GDD、代码、场景或其他文档。低端设备、持续性能、全路线人工体验、用户终审及独立海床的历史未签边界继续保留。

### 2026-11-10 主线程最终验收（覆盖上方委派阶段 PENDING）

R44–R51已实现并完成当前专项：`20261110-233501-dive-entry-polish-core-cc526e`中transition500/0、maps857/0、control396/0、collision2824/0；`20261110-233501-dive-entry-polish-visual-6a99e7`真实transition404/0、control403/0。`20261110-233926-dive-entry-final-integration-222f98`中水下体验179/0、家园85/0、海面camera14/0、modules31/0、minimum112/0、framework52/0及3个存档入口通过。12个计数入口5857/0，15项均exit0/PASS、unexpected=[]；报告均在工程外verification目录，完整命令/报告/失败历史见[开发记录第5节](../../development/2026-11-10_dive_entry_splash.md#5-最终运行验收)。

最终家园基础俯角0.16rad，起始偏移−0.22rad；21张真实帧覆盖1.6667s，实际终点水深4.799905m。opening相机固定、可见入水/实际速度/完整胶囊段、swim首帧连续与尾迹归零、readiness及释放后失败遮黑回滚均验；未改TSCN或v4存档。全局sync79/只读81问题未过，含本轮改动脚本的待定向哈希签署与其它登记漂移，不批量重签；功能整体partial，设备/长时/独立海床/用户终审未签。

## 2026-11-14 3–5分钟水下体验、打捞拍照捕鱼与3A向3C规划（planned）

本节承接既有最大条款 R51，落实用户提出的潜水体验深化，但**只做设计登记，不代表代码、资源或运行效果已经完成**。详细路线、现状内容基线、氧气预算候选、舒适性和实施验收要求见 [3–5分钟水下体验主方案](underwater_experience_plan.md)；本轮记录见 [开发记录](../../development/2026-11-14_underwater_experience_plan.md)。新增 R52–R75 与 SEA-CAMERA-R18/R19、SEA-MOVE-R32、SEA-SAVE-R20/R21 跨功能承接；功能状态继续为 `partial`，新增条款运行状态为 `pending`。

| 条款 ID | 规划规则 / 应验证的行为 |
|---|---|
| SEA-DIVE-R52 | 单次有效水下窗口目标为 **180–300秒**，从 `swim` 解锁到请求结束潜水计算；三条首发路线定为 **210/225/240秒**。主动沿地图安全路径游回浅层仍属于 `swim`，计入窗口并耗氧；正式 `exit` 表演、入水/加载/圆幕不计时，照片异步不阻塞或另加窗口时间。打捞、拍照、捕鱼是可选活动，可提前结束，不设强制倒计时、体力条或氧气存档字段。 |
| SEA-DIVE-R53 | 入口继续使用现有来源海域与家园海底映射，经 `DiveSession` 事务接受/拒绝；重复请求、无来源或地图前置不满足时拒绝，不回退第二地图。 |
| SEA-DIVE-R54 | 电影化入水复用无文字圆幕、真实全黑 `frame_post_draw`、prepared enter、uncover 和 `release_entry`；opening 零位移、Air冻结，圆幕完全 idle 且不可见后才开始可见下沉，仍由 Shared DiveRuntimeController 驱动。 |
| SEA-DIVE-R55 | 水下移动、自动路线取消、碰撞挡停和安全路径沿现有 Controller/Map 端口；踢蹼滑行、悬停、倒游、侧移、刹停、转身和返程姿态均消费碰撞后的实际速度，不按期望速度假动作。 |
| SEA-DIVE-R56 | 潜水镜头承接 SEA-CAMERA-R18：候选默认距离9.5m、距离5..16m、vFOV74°/冲刺80°、显式 `KEEP_HEIGHT`、0.32m双clip、无roll；镜头只归 Shared DiveRuntimeController，海面 OrbitCam/R16 不变，目标交互不抢手动镜头。 |
| SEA-DIVE-R57 | 轻潜水镜承接 SEA-CAMERA-R19：中心55%不扭，边缘默认位移不超过短边1.5%、可调上限3%并可归零；在世界雾和透明合成后、HUD/圆幕前呈现；标签正向投影与点击逆映射共享，零强度等价。 |
| SEA-DIVE-R58 | 打捞、拍照和鱼群目标使用稳定内容 ID；发现、观察、可交互、已耗尽是内容状态，不把玩家位置、相机、Air或中途动作写入 durable save。 |
| SEA-DIVE-R59 | 打捞使用短时、可取消、一次性 token；完成前不消耗目标，完成时整份奖励原子提交；满包、重复、过期、非法目标或切换态不得发部分奖励或改变耗尽状态。 |
| SEA-DIVE-R60 | 捕鱼使用抄网表现和内容端口，成功必须由实际接触/命中确认；不因持续按键、镜头锁定或假命中发奖，不改海面捕鱼规则，不让装饰鱼节点成为物品写者。 |
| SEA-DIVE-R61 | 拍照记录稳定 `photo_id`、最佳构图摘要、首次日期和可选本地图片相对引用；图片异步失败不删除观察记录，也不回滚已完成的奖励。 |
| SEA-DIVE-R62 | 照片图片保留水下雾、光线与可选镜片效果，不含 HUD/圆幕；构图摘要只保存目标几何和可见性指标，雾影响可见度，但雾颜色、材质等渲染资源不入存档。取景不强制转向、不抢手动镜头；HUD字形不扭，标签锚点经轻潜水镜正向映射对齐世界，点击使用对应逆映射，零强度等价。 |
| SEA-DIVE-R63 | 潜水 HUD 只读 Controller/Session，显示深度、Air、活动提示、打捞/拍照/捕鱼反馈和剩余日配额；不直接写位置、Air、Inventory或存档，暂停继续沿既有规则冻结。 |
| SEA-DIVE-R64 | 电影化出水复用同一 `DiveSession`、Controller和圆幕；请求时取消活动 token，`switching/transition_frozen` 锁玩家输入、奖励、Air、保存、日期与经营，但对白名单内、受 Session 返回令牌授权的同一 Controller `exit` 表现 tick 放行。仅实碰撞安全末段 **4–6m、1.2–1.8秒**可见上浮，随后 cover→真实全黑 `frame_post_draw`→卸 runtime→恢复同 Main/uncover；深处请求、无安全短路径或缺氧救援禁止线性穿楼到水面，改为原位抬头气泡 **0.3–0.6秒**后遮黑，叙事压缩返程。随时可跳镜头，不跳遮黑与恢复事务；主动完整上浮可在 `swim` 沿地图路径返回并获返程气量提示，不强制深处锁输入游40秒。 |
| SEA-DIVE-R65 | 出水完成后恢复同一 Main 身份、原船/角色姿态与模式、海面 OrbitCam、WorldEnvironment、GroundSpace、UI信号和处理模式；不 free/rebuild/read-save，不残留潜水 Character、Map tick、镜头或 HUD。 |
| SEA-DIVE-R66 | Air详设候选为 `A=100`、`rate=(1/3)*(1+0.15*clamp(depth/120,0,1))*M+tool`，`M=1/1.08/1.35` 分别对应悬停/巡航/冲刺，灯耗气0；`tool=0.02/s` 仅实际打捞/收网时叠加，其余为0。首版无水下换气，稳定 `swim` 推进耗氧，返回同 Main 后再补气，保留 **6秒**救援 cooldown；潜水时海面 WorldClock 与换气/cooldown 暂停，切换/正式exit的Air冻结。**35%/15%**提醒叠加按安全路径余量提前返程提示；这是游戏化预算，不作为现实潜水指导。`dive.expedition` 不保存氧气、位置、当前动作或中途相机，数值效果待实现实测。 |
| SEA-DIVE-R67 | `active/switching/transition_frozen` 的 save busy 禁止 `SnapshotRegistry.capture`、`SaveGame.write` 与 restore，不禁止稳定 `swim` 的内存观察/奖励。活动准入必须 `active && swim && !switching && !transition_frozen`，另设独立 `content_busy` 与单次 token 锁，提交无 `await`，不以UI禁用替代。切换/取消/过期照片异步回调不得回写已卸载会话；已提交内存观察保留，文件成功且 Session 归属仍有效才挂相对引用。 |
| SEA-DIVE-R68 | 打捞/捕鱼奖励、耗尽、日配额与观察状态在无 `await` 的内容事务内提交，Inventory 是唯一物品写者。先预检整份 capacity、稳定ID、token、epoch与配额，再同线程提交库存和 Session 耗尽/配额，全部成功后最终广播，失败回滚。现有 `Inventory.add_all` 内部先广播会让外部观察到不一致，未来必须扩展现事务的抑制/延后广播及回滚入口；不能宣称已具备跨 owner 原子提交，承接 SEA-SAVE-R21。 |
| SEA-DIVE-R69 | 首版家园 **5个新资源稳定目标**产出合计 `wood2/rope1/parts1/glass1/pearl1`；所有地图新增资源合计共享同一每日配额 `wood2/rope1/parts1/glass1/pearl1`，捕鱼 `fish2`。按注入 WorldClock 的 **07:00 epoch** 刷新，同 session、切图、返回重入和重复请求不刷新；目标耗尽和当日产量不能靠重进恢复。与旧九图23个宝箱的 `opened` 奖励分账，不设置单次宝箱/摄影/抄网硬上限，由内容和全局日配额约束经济。 |
| SEA-DIVE-R70 | 持久化承接 SEA-SAVE-R20：root v4 与 `dive:{found:int[],opened:int[]}` 保持，原未知整数宝箱ID继续保留；新增可选 `dive.expedition` 由 DiveSession 唯一输出。仅缺整个 expedition 时明确迁移为空；存在 `version:1` 必须包含合法的 version、resource_epoch、consumed、daily_yield、photos 全部必填字段，照片记录必填字段也须完整。 |
| SEA-DIVE-R71 | 读取 expedition 严格校验全部必填字段、类型、未来版本/晨次、重复稳定ID、非法计数和照片相对路径遍历；未知稳定ID保留。已有 version1 缺字段或 `consumed` 损坏必须拒绝，不能补空使资源刷新；失败不改现场、不覆盖有效备份，不与缺整个模块的迁移混淆。 |
| SEA-DIVE-R72 | 照片 JSON 不写二进制、绝对路径、雾颜色或渲染资源；图片异步成功且校验 Session 归属有效后，才向已提交观察挂受控相对引用，切换/取消/过期回调不回写已卸载会话。图片缺失/删除/生成失败不删除已提交的 `photo_id`、构图摘要与首次日期观察；迟到的有效引用仅入内存，等下次普通save，不逐图强写。 |
| SEA-DIVE-R73 | 每次返回同一 Main 且所有 busy 解锁后，仅向现有 `SaveGame.write` 发起一次返回保存请求，仍受禁存、`nosave`、坏档保护与当前保存意愿约束；写盘失败不重发奖励、不撤销已得内存资源，只提示重试。图片迟到仅挂经归属校验的内存引用，等待下次普通save，不增加本次返回请求或为每图强写。 |
| SEA-DIVE-R74 | 验收覆盖3–5分钟连续体验、提前出水、重复/取消/满包/过期 token、跨07:00日配额、坏档/未来版本、照片成功/失败/缺图、捕鱼/打捞奖励、进出水录像、5体型与30/60/120FPS、16:9/16:10/21:9/Compatibility；headless不替代真实渲染、输入和图片链路。 |
| SEA-DIVE-R75 | 本轮仅规划和账本登记；实现前联动 SEA-CAMERA-R18/R19、SEA-MOVE-R32、SEA-SAVE-R20/R21，并扩展既有潜水、过场、水下体验和存档入口；不得新增假测试入口、借历史 PASS 或提前升级运行状态。 |

### 本轮设计基线与未签边界

当前家园海底仍是观赏内容，没有宝箱、可打捞奖励或可捕捉鱼；旧九图的23个宝箱继续使用既有 `opened` 进度和奖励链路；现有水下鱼群全部为视觉组件，不能直接视为捕鱼产量；正式工程也尚无玩家摄影收集系统。首版路线、返程方式、无水下换气、资源/捕鱼配额与摄影奖励取舍等产品选择已由主方案锁定。P0已将候选耗氧、镜头候选值、显式KEEP_HEIGHT、浅层安全出水末段/深处压缩返回接入代码并完成专项验证；内容ID落地、打捞/捕鱼/摄影系统、跨owner事务、舒适性镜片和3–5分钟真实完整路线仍待实现与验收。

本轮预计扩展既有 `dive-control`、`visual-dive-control`、`dive-transition`、`visual-dive-transition`、`underwater-experience`、`visual-underwater-experience` 及存档/事务入口；不新增 verification 名称。低端 GPU、持续运行、全路线人工体验、独立海床高度图、用户美术终审及全局契约门禁继续保持未签。

### 2026-11-14 本轮口径收口与委派边界

以上R52–R75仍全部 `planned/pending`，只修订本轮新增规划，不改历史规则、历史签署或登记头；主方案详设由主线程补齐。稳定swim内容提交与save busy分离，正式exit仅以Session授权白名单推进表现，不开放玩家操作或耗氧。委派写作阶段未运行全局checker/sync或Godot，仅做四文件diff-check与条款对应静态核对；主线程最终checker/sync静态结果见[开发记录](../../development/2026-11-14_underwater_experience_plan.md)，不据此预签运行通过。

<a id="dive-swim-feel-design"></a>
## 2026-11-19 潜水游感与障碍缓冲（现行）

本节细化 R35/R48/R54/R55 的游动与表现，不替换已有出入水生命周期或前轮玩法规划。与 [SEA-MOVE-R33–R36 角色表现](../move/spec.md#move-dive-swim-feel-design) 配套，逐条承接见[本功能账本](ledger.md#dive-swim-feel-ledger)，参考转化、复查步骤及待签项见[本轮开发记录](../../development/2026-11-19_dive_swim_feel.md)。

| 条款 ID | 设计规则 / 应验证的行为 |
|---|---|
| SEA-DIVE-R76 | 正式十图（家园海底＋旧九图）共享 `DiveRuntimeController`，复用各图独立的潜水 `Character` 实例与现有 21 骨蒙皮。Controller 决定运动意图、姿态上下文和混合；Map 提供净空并执行原碰撞/滑移，实际位移是驱动游动幅度和踢蹼节拍的依据。Character 只消费上下文，不写玩法根位移；无逐图 3C 分叉或第二套潜水状态机。 |
| SEA-DIVE-R77 | 正式入水的 prepared enter 与整个 opening 保持零位移、静态预备姿势和 Air 冻结；同一圆幕完全退场、既有 `release_entry` 后才播放可见的头先下潜：上身快速转向下方 → 腿跟随抬起 → 流线／小幅踢蹼 → 回到水平。稳定 `swim` 中 Q 下潜依据实际下行速度连续混合到头先流线姿态，不重播专用于入水的折身段；松开、受阻或切回水平移动时连续收势。动作不改变既有安全下沉路径、时序或门禁；实际未前进时不继续假踢。 |
| SEA-DIVE-R78 | 开阔水域前游有推进与滑行；依旧按原输入映射请求移动，不重绑键位。按 S、且角色水平正面与当前操控参考前向对齐时，保持朝向并向后移动，表现为倒蹼。侧向或其他反向意图仍可自由转身，不将所有反向运动固定为倒游，也不因倒游突然翻转朝向。保留原点击路线与手动接管。 |
| SEA-DIVE-R79 | 按拟移动方向作只读净空查询，并以向下净空区分海床接近；用当前实际碰撞体/阻挡规则，而非中心射线、视觉网格距离或动画脚尖猜测。家园使用玩家实际胶囊对现有代理与地形扫掠；旧九图沿用现有实体/地形判阻与路径子步近似净空，不换碰撞体，不提供或伪造精确表面法线。探测不移动角色、不改变地图数据；最终仍由原 Map 执行碰撞。 |
| SEA-DIVE-R80 | 朝墙逼近时，按净空渐进收掉撞墙方向的推进并收手臂；斜擦墙保留可走的切向运动，是否及如何滑移由原地图碰撞决定。近海床以收腿、抬脚、收蹼和保持躯干水平为主，不用上推角色或强制回弹替代净空判定。完全挡停时禁止持续假踢；掉头或撤离后缓慢淡出防护姿态并连续恢复常态，不因仅处在墙边而惩罚远离方向。 |
| SEA-DIVE-R81 | 无强制弹开、震屏、伤害或新增碰撞惩罚；不改存档结构/门禁、正式场景/用户手摆、Session 事务、切图、Air 或过场生命周期。验收按可复现路线和实际参与阻挡的胶囊/代理或旧判阻范围分别记录；角色或脚蹼的网格观感抽样不等于全地图、全网格零穿透保证。阈值、幅度、混合时长等待后续调校和实测，本轮不定未确认常量。 |
