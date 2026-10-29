# WorkBuddy 行走诊断与游戏构成复核

日期：2026-10-29。审计归属 SEA-QUALITY-R01/R03/R04，关联 SEA-MOVE-R01/R08、SEA-NAV-R04、SEA-WORLD-R05/R11、SEA-BUILDING。此次交付为诊断、结构观测和文档登记，未修改玩法、场景、移动代码或资产，也未提交或推送 Git。

## 依据与结论边界

- 阅读 [WorkBuddy 分享会话](https://workbuddy.link/p/eGgCilxomjxS00vdamw7RF?ext2=copy_link) 全部 8 条消息，包含其最终栏杆绳诊断及方案 A/B 建议。分享中的执行记录为历史证据，不作为此次测试结果。
- 按主文档导航读取 MOVE、NAV、WORLD、BUILDING、QUALITY 功能文档/账本及模块接口约定，并核对当前实现。正式实现位于 godot/；web/ 是独立 Three.js 原型及历史视觉/烘焙来源。
- 通过统一 runner 的隔离工程观察当前默认主场景。HEAD 为 cbffe47c64254818c192bd92f90f7d16e2ce5508，工作区同时存在自由建造等未提交修改；结论针对复制时的快照，不代表 HEAD 单独内容或用户编辑器内未保存状态。
- headless 仅用于结构、数值与专项断言；本轮没有真实输入、真实渲染或现场复现用户的穿绳操作，不能签署“所有穿透已修复”。

## 当前游戏由哪些部分构成

| 部分 | 当前实际构成 | 意义 |
|---|---|---|
| 表现 | Godot 3D 场景、独立 PackedScene、Mesh/MultiMesh、部分程序化角色/装饰、水面与昼夜着色 | 画出来的模型不自动成为物理实体 |
| 人物移动 | Character 继承 Node3D；ActorController 状态/动作驱动；WalkArea 的 XZ 矩形/多边形求路，路径高度取 surface_y | 是在 3D 画面中使用平面规则的移动；模型不直接拦人 |
| 航行 | Boat + WaterNavigation；组件 BlockerSet 的 auto/manual/none 声明和动态建造占地提供水面形状；求路与实际航行逐段复核 | 存在自定义逻辑阻挡，未接物理引擎碰撞；自动派生不代表必然准确 |
| 自由建造 | BuildingService 持有布局，BuildingWorld 投影表现/行走面/水面阻挡，BuildingSpace 从承载并集扣除培养土与角色空间 | 已有从布局派生规则的机制，不是全世界只有六行静态手写数据 |
| 经营/持久化 | Inventory、Farm、CropCatalog、DailyShipping、Warehouse 等功能所有者，经命令/查询/事件接入；SnapshotRegistry 收集和恢复快照 | 移动空间问题不要求重写经营系统 |

产品范围按 GDD 当前最小生活循环及自由建造修订理解：捕鱼/种植、库存、出货、购买、睡觉/昼夜、航行及建造已有实现；居民、养殖、任务成就、音乐和音效仍登记为规划中。该判断来自范围和账本，本轮没有重新验收全部玩法，不给全项目完成度百分比。

## 代码事实

- `godot/src/player/character.gd:1`：extends Node3D。
- `godot/src/player/actions/walk_action.gd:25`：按 SPEED × delta 沿路径推进；第34行只检查候选中心点 contains_world，第37行直接写 global_position，没有 move_and_slide 或形状扫掠。
- `godot/src/navigation/walk_area.gd:105`：path_between 不按 body_radius 内收；第154行 clamp_point 对目标落点做净空修正。GroundPath 验证线段是否留在多边形并集，但没有独立的全程角色体积碰撞判据。因此落点安全不等于沿途肩膀/帽檐都安全；这是静态风险分析，未作为本轮已复现故障。
- `godot/src/building/building_space.gd:5/55`：动态平台按0.22米半宽派生可站中心区域，并扣除摆件扩张占地；`building_world.gd:23` 将该区域 body_radius 设0以避免二次内收。旧 WalkArea 默认0.38米是帽檐/身影留边，二者语义不同，后续应明确身体碰撞半径与视觉余量，不机械替换成同一个值。
- `godot/src/world/blocker_set.gd:19/44`：水面阻挡有 auto/manual/none 三种来源，自动分支按水线到船体高度带扫描几何并栅格化；有意排除纯景观和不阻挡组件。

## 对 WorkBuddy 建议的判断

1. 当前人不靠物理碰撞移动、模型与手写行走面可能漂移，这两点成立；栏杆内沿不同于甲板外沿，也解释了为什么仅改善甲板覆盖率不能证明栏杆挡人。
2. 将“没变化”归因于旧发行包，不能用于解释用户明确指出的编辑器测试。必须区分磁盘源码快照、编辑器已保存场景和实际运行实例。
3. “CharacterBody3D 会天然带来惯性、与点击移动冲突”不成立。它是脚本控制的运动角色体；点击决定目标、导航决定路线、运动体处理碰撞可以共存。调参或更新时序可能造成抖动，但不是该节点类型必然的手感。
4. “扫描朝上甲板三角形即可根治栏杆穿透”不成立。甲板的朝上面仍延伸到绳外，竖向栏杆/墙和家具占地需要单独的阻挡语义；桌面/箱盖也不能仅因朝上就变成可站地面。填一格缝隙还可能错误连接真实断口。BlockerSet 的栅格工具可复用，水面占用与陆地可行走面并非简单取反关系。
5. 加碰撞体或换 NavMesh 也不会自动保持永远一致：导航仍需按角色尺寸烘焙并在几何变化后更新，现有直接写 position 的移动必须改为消费碰撞结果，不能只往模型下加 CollisionShape3D。

官方依据：[CharacterBody3D](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html) 定义其为脚本控制的角色物理体；[导航网格](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationmeshes.html) 明确导航与表现/物理独立，路径只处理中心，需烘焙尺寸余量；[NavigationAgent](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html) 不负责移动父节点；[碰撞形状](https://docs.godotengine.org/en/stable/tutorials/physics/collision_shapes_3d.html) 支持为物体组合简单代理。

## 建议方向（尚未实施）

保留经营服务、ActorController 状态机、点击交互和存档接口。让稳定组件声明可站表面、人物障碍和船只障碍：地板提供承载面，栏杆/墙/培养土提供适度简化的障碍，花叶和纯景观按明确规则排除。由同一组件声明派生导航与碰撞代理，并对齐模型/布局变更生命周期。

先在太阳房码头验证“地面 + 两侧栏杆 + 角色运动执行层”的小范围闭环。后续逐步接入人物运动体或等价形状扫掠，在保留路径规划的同时增加实际位移的碰撞兜底；是否迁移为 Godot NavMesh 应由自由建造的动态更新、通路、上下船与复杂度实测决定，无需把全 NavMesh 当作前置条件。已有动态平台的布局派生路线继续保留，接入同一空间语义接口。

验证必须分别覆盖：脚下有支撑、身体不穿栏杆/墙/培养土、整条路径有足够宽度、交互可达、上下船、平台完工/搬移/拆除后的路径刷新及存读档。现有甲板/栏杆专项是局部回归证据，不能替代这些目标。

## 本轮执行与证据

使用 godot-runtime-probe 技能的方法，通过 `scripts/run_verification.py` 的 isolated_project 在 Autoload 前设置独立用户目录。临时探针和包装脚本仅在工程外；未改正式 runner。Godot 4.7.2，Python 3.14.2。

- 结构观测：`D:/projects/sea-work/verification/20261029-182844-workbuddy-composition-5521ec/report.json`；对应 composition-probe.log 与 composition_source_hashes.json。
- 当前默认主场景：PhysicsBody3D=0、CollisionShape3D=0、NavigationRegion3D=0、NavigationAgent3D=0、WalkArea=6。角色类型为 Node3D。观察到777个MeshInstance3D节点和407个MultiMeshInstance3D节点，此数是节点数而非组件资产数或逻辑实体数，不作性能结论。
- 三条栈桥竖直物理射线均未命中物理体；六个行走区有独立surface_y。zone5运行时body_radius=0，符合其事先派生中心区域的实现。
- composition-probe退出0，无非预期引擎错误；只证明完成结构观测。
- 初次探针误读不存在的main.char，脚本错误后超时退出124。已修临时探针为main.player，失败日志保留在 `D:/projects/sea-work/verification/20261029-182811-workbuddy-composition-a4eb7b/`，不计为产品回归或通过。
- `python3 scripts/check_architecture.py` 退出0：15个独立规则/存储服务，0问题；该数字是门禁报告的服务数，不是全项目功能数量。
- 同一首轮隔离快照继续执行的 `rope-bounds` 14项、`walk-deck-fit` 16项均0失败、退出0，均无非预期引擎错误。首轮整体退出1源于临时探针超时，不能把整轮记为通过；两个专项的逐项结果见其report.json。
- 初次 `check_feature_contracts.py --sync` 退出0：35功能、459源资产、392运行资源哈希、0问题。最终文档登记后再次按顺序执行sync和无参数检查，输出与真实退出码保存至 `D:/projects/sea-work/audits/2026-10-29-workbuddy-composition/contract_checks.json`。未更新资产哈希来接受未知漂移。

未执行：真实渲染/鼠标复现、完整游戏回归、设备/发行包、长时间性能、碰撞改造方案原型。没有声称这些项目已通过。

## 后续两层房间、楼梯与碰撞迁移范围评估

用户补充的未来方向为进入二楼、连续上下楼梯。本节是方案与范围评估，尚未批准为已实施功能，也未变更现有MOVE规格中的平面行走规则。

在这个方向下，推荐人物采用CharacterBody3D与胶囊碰撞体，环境由稳定组件提供地板、墙和栏杆等简化碰撞；陆地寻路升级为保留高度的3D导航。点击交互、角色状态机、模型和表现动作可以继续复用，由运动执行层在物理步执行移动。引入角色碰撞不要求船也改成刚体模拟。

### 新核对的高度限制

- `godot/src/world/zone_scene.gd` 的 `area_containing(x,z)` 只按XZ返回首个包含点的区域；`floor_height_at`也只有XZ参数。上下重叠的两层需要按三维位置/表面或区域身份区分。
- `WalkArea.path_between`把整条路径的Y设为同一个surface_y，无法直接表示连续上升的楼梯路径。
- `landing_point.gd` 的stand_position把Y设为父地面的surface_y；上下船还会重设角色父节点和姿态，需管理碰撞/运动启停及落地验证。
- `main.gd` 的restore_world_state以保存的XZ查首个地面，并把已存的Y替换成该surface_y；validate_world_state同样依赖此查询。存档已有XYZ，不意味着已支持多层恢复，必须连同地面验证/解析一起升级；是否增加稳定表面ID由具体场景设计决定。
- 当前有10个测试文件直接调用actor_controller.tick；迁移后应保留无物理依赖的状态测试，并让实际碰撞与上下楼测试等待引擎物理帧。不能沿用分享诊断中的“25处”作为本轮文件数。

### 工作量边界（初步估算）

| 部分 | 预计改动 |
|---|---|
| 人物执行 | 增加运动体/胶囊、重力、贴地与斜坡设置；把直接写position的行走改为碰撞移动；表现可作为运动体的子节点保留 |
| 地面导航/点击 | 三维路径、重叠楼层命中、不可达拒绝、角色尺寸和净空；静态室内可使用NavigationRegion3D/NavMesh |
| 交互/上下船 | 接近点按完整路径判断可达，避免隔层触发；上船停用陆地运动，下船恢复并验证安全落脚点 |
| 动态建造 | 完工/搬移/拆除更新碰撞与导航；分块更新或布局生成导航面，避免每次全世界重烘焙 |
| 存档/镜头 | 三维地面校验与恢复、旧档兼容；验证镜头高度及室内遮挡。室内隐藏屋顶等为独立可选表现需求 |
| 内容与验收 | 组件碰撞代理、楼梯/二层样板及导航资源；补当前主场景、上下船、建造、楼层选择和跨进程恢复专项 |

这是中等偏大的移动与空间基础改造。初步预计涉及约15–25个正式脚本的新增/适配，另计组件场景、导航资源及测试；此范围不是已冻结文件清单，也不是工期承诺。实际场景工作量取决于开放哪些区块、哪些组件需要挡人，以及是否包含可建楼梯、多层建造、梯子或移动平台。

建议分三步实施：一楼/楼梯/二楼的独立样板先闭环；再迁移现有主场景及动态建造；最后按需要扩展室内遮挡、梯子等特殊动作。这样可以先验证现有速度、转向、上下船和存档契约能否保留，再扩大场景覆盖。

### 楼梯与梯子要区分

普通楼梯可保留可见台阶，使用平滑斜坡碰撞代理让胶囊连续上行，并按坡度配置贴地。若必须逐级踩真实台阶，通常还需台阶抬升检测；NavMesh的agent_max_climb是寻路烘焙规则，不会为CharacterBody3D自动增加抬脚能力。竖直梯子则需要攀爬状态、进出点和动画；NavigationLink只提供路径连接，不执行攀爬动作。

依据：[CharacterBody3D的斜坡/贴地参数](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html)、[NavigationMesh烘焙参数](https://docs.godotengine.org/en/stable/classes/class_navigationmesh.html)、[NavigationLink的执行边界](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationlinks.html)。本次为源码影响评估，未新增运行测试、楼梯原型或修改移动实现。
