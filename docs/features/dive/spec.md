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
