# SEA-RESIDENCE · 七人住所社区与生活锚点

[主文档中控](../../../GDD_V1.0.md#sea-residence) · [本功能账本](ledger.md) · [NPC功能](../resident/spec.md) · [商店功能](../shop/spec.md) · [施工记录](../../development/2026-11-07_npc_module_framework.md)

设计修订：r1（2026-11-07 下午）。所属系统：世界/生活。状态保持 `partial`，资源存在不代表运行、视觉或设备验收完成。

### 2026-11-07 19:40 覆盖声明：用户暂停住所

用户要求“先不用做他们的住所，先全部放到那个天台草地上去”。SEA-RESIDENCE保留登记与既有源码/场景，状态仍为 `partial`（已有历史制作资源留存），本轮制作、接入与验收安排为 **deferred / 用户暂停**，历史制作不作为当前接入；不新增住房开发，不删除下文R01–R07，不以暂停签退为通过或已完成住房。

下文七屋/50m²/床桌灯/两住商空间/住所35Marker/Main增量装配及参考 `(38,0,-32)` 均为19:40之前的历史方案，不是当前NPC或Shop硬前置。截至本轮收尾，Main现有 `resident_harbor` 实例及zones/scope绑定已移除，源资源保留；用户手摆root与其他旧transform未动。此为当前接入清理事实，不是住房验收通过。

当前七人无物理房屋，正式现场为 `rooftop_ranch` 用户手摆root下 `NpcStations` 的35个局部Marker，随scene/root变换，不按历史住所参考位或绝对世界坐标摆放；UI仅写“暂驻天台”。该公开世界站位端口由世界场景提供，非住所开发；后续可插住所provider，但当前NPC已移除SEA-RESIDENCE功能依赖。NPC规则、配件/剧情/职业与独立Shop保留，商店交易不等待住商房屋。

历史证据 `D:/projects/sea-work/verification/20261107-192319-seven-npc-release-a6fb1b` 中release integration/save已PASS仅对应住所版，不证明当前天台版或住房全项完成。当前天台运行主验已由214439五项2277/0独立通过，14PNG已产出、三图由主线程目检而11图待审，见[最终签署](../../development/2026-11-07_npc_module_framework.md#14-最终天台交付范围签署)；住房恢复开发须等用户后续明确要求。

## 1. 目的、依赖与所有权

为七名NPC提供可进入、可站立、可维护的独立住所、生活锚点和连续社区空间。前置仅 `SEA-WORLD / SEA-ASSET / SEA-INTERACT`，**不反向依赖 SEA-RESIDENT**。稳定 npc_id 只是归属映射元数据；即使没有NPC服务，住所场景也应能独立加载和提供锚点。

本域拥有正式静态TSCN布局、房屋实例、家具与商店空间、生活Marker及世界空间声明；不拥有NPC好感/剧情/日程、玩家profile、商店商品价格、Inventory、玩家建造布局或第二套移动物理。GroundSpace由既有世界框架派生，CharacterMotor执行移动；不能靠新造碰撞/导航系统掩盖路线失败。

## 2. 七座正式房屋与两商店

每座正式房屋目标面积50m²（10m×5m），各有床、桌、灯和独立主题陈设；尺寸/家具源码需由主线程在住所专项与真实渲染签署，不能把目录数量当尺寸/可进入性通过。花店和综合商店是七座房屋中的两座住商空间，不另增加两套住所状态。

| residence_id | 归属npc_id / 当前名 | 正式场景 | 空间用途 |
|---|---|---|---|
| residence_dock_workshop | npc_luo_yan / 牵线 | residence_dock_workshop.tscn | 修船间 |
| residence_sunroom_greenhouse | npc_mu_he / 叶脉 | residence_sunroom_greenhouse.tscn | 晒种房 |
| residence_salvage_cabin | npc_ji_chen / 回声 | residence_salvage_cabin.tscn | 打捞舱 |
| residence_builder_loft | npc_nan_zhi / 榫口 | residence_builder_loft.tscn | 木作阁 |
| residence_lantern_archive | npc_bai_shi / 灯芯 | residence_lantern_archive.tscn | 灯火档案屋 |
| residence_flower_shop | npc_hua_yi / 花序 | residence_flower_shop.tscn | 花序花店；shop_flower |
| residence_general_store | npc_bao_he / 货架 | residence_general_store.tscn | 货架综合商店；shop_general |

上述路径均相对 `godot/scenes/residence/`，共用 `residence_shell.tscn` 但保留7个独立正式场景，不能改为NpcWorldPresenter运行时拼屋。

## 3. 场景真值与主场景增量装配

- 正式社区为 `res://scenes/residence/resident_harbor.tscn`，区块ID=`resident_harbor`；Main的 `World/SeaStructures/resident_harbor` 是新增独立实例。当前参考变换 `(38,0,-32)` 只用于定位，不冻结坐标，不改用户其他场景摆位。
- **静态TSCN是唯一布局真值**。`godot/assets/data/npc/residences.json` 当前 `version=2` 只声明场景、节点路径、归属和稳定锚点ID，不保存第二份坐标，不属于NPC durable版本。作者工具存在不意味着本轮可以重跑覆盖手工布局。
- 社区统一 `WalkAreas/Community`，通过既有ZoneScene/GroundSpace从地面声明和家具障碍派生站立面、碰撞与路线。挪动社区/房屋后按公开 `refresh_space()` 刷新派生空间，不重写作者布局；任意子物体移动后的正确性仍待运行验证。
- 复用场景、家具、模型引用不等于资产登记或授权已完成；本轮不改registry，缺生产登记另记未验。

## 4. 35个生活Marker与公开端口

每座恰有 `Home / Work / Social / Rest / Door` 五个生活Marker，共35个（不把泊位等公共Marker混入此数量）。节点路径位于各房屋 `Shell/Markers/`，世界位置必须从正式Marker实时转换，不由NPC猜测旧坐标。

| 端口 | 契约 |
|---|---|
| `anchor_snapshot()` | 返回稳定anchor_id到position、zone/zone_id、ground、ground_space、residence_id、kind的查询快照；容器不可反写源布局，ground是只读空间服务引用，不可序列化 |
| `refresh_space()` | 刷新从作者场景派生的可走面/GroundSpace，不产生NPC业务状态 |
| 旧锚点适配 | 若提供`resolve_anchor`，只负责稳定ID兼容；当前需主线程核实，不推测其已经实现。NPC找不到锚点走可观察home降级/停止，不生成替代房屋 |

花店work anchor为 `anchor_flower_shop`，综合商店为 `anchor_general_store`；其余五座为 `<residence_id>_work`。home anchor保持residence_id，social/rest/door用独立稳定ID。夜间NPC消费自家Rest站位，不站床心。物理路线由消费者调用 `surface_point/path_between` 并由CharacterMotor执行，住所不直接搬动角色。

## 5. 存档与交互

本轮住所无动态持久快照，不新增 `residence` 存档键。静态房屋/家具/锚点恢复从正式TSCN重建；NPC归属引用与动态关系仍归 `npc.version=1`，玩家profile保持不动。玩家稳定区块/位置由现有game存档契约承担；主线程需验证新resident_harbor合法位置与读档恢复，不把新增区块当已兼容。

房屋只提供空间与交互挂点；NPC对话/职业命令由NPC公开端口，商品及购买由ShopService。两商店场景存在不能算商店购买和NPC日程已接通。

## 6. 设计条款与验收

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-RESIDENCE-R01 | 独立住所域，依赖WORLD/ASSET/INTERACT而不反向依赖NPC；无NPC服务仍能加载和查询空间。 |
| SEA-RESIDENCE-R02 | 7座独立正式50m²房屋，每座床/桌/灯及主题陈设；两商店为其中两座住商空间，尺寸/入口/家具真实可见可维护。 |
| SEA-RESIDENCE-R03 | resident_harbor静态TSCN为布局真值，main仅增量实例；参考坐标不钉死，不覆盖用户其他摆位，不保存第二份坐标。 |
| SEA-RESIDENCE-R04 | 7×5=35生活Marker和稳定ID/节点映射完整，anchor_snapshot返回随变换的真实空间信息；旧锚点缺失可观察降级。 |
| SEA-RESIDENCE-R05 | 社区统一GroundSpace，家具/墙体阻挡与可走面由世界框架派生；CharacterMotor执行路线，禁止另一套碰撞/导航或穿墙传送。 |
| SEA-RESIDENCE-R06 | 静态住所无副本存档，不触碰玩家profile或NPC durable所有权；新世界区块稳定位置与save/integration恢复必须验证。 |
| SEA-RESIDENCE-R07 | 结构、运行、真实渲染、设备/性能与未验分别记录；主线程完成residence及NPC/商店/存档集成前保持partial，不以资源数量宣称完成。 |

## 7. 当前边界与主线程回填占位

只读已见正式场景、resident_harbor.gd、residences.json和test_residence.gd；本分支未运行sync、Godot、作者脚本或专项。主线程回填 `residence` 的实际runner/适配入口、命令、工作树版本、退出码、断言/失败数与日志；真实渲染的7屋/家具/商店/35Marker对应截图；Main区块接线、统一路线、手摆变换及save/integration结果；设备后端、性能、未验项。不能把隔离夹具或历史记录直接升级为当前整局通过。

## 2026-11-07 收尾：历史source封存与接入清理

当前Main已撤resident_harbor实例、zones/scope绑定，正式住所source资源继续留存，R01–R07与章节顺序不删、不签退通过。用户暂停住房不影响七人NPC、独立Shop或天台公开世界站位；NpcStations35局部Marker位于既有rooftop_ranch，七人无物理房屋，UI“暂驻天台”，不是新建住所。用户手摆root与其他旧transform未动，仅本轮天台泊位局部Marker/boat避让旧shore_environment阻挡。

天台通行专项已通过，不属于住房验收；性能修复保留泛光、七人和画质，详见[本轮记录](../../development/2026-11-07_npc_performance_fix.md)。天台integration/save/seed/restart/visual已由214439五项2277/0、exit0/PASS独立通过，14PNG已产出、主线程三图目检、其余11图待审，不能从住所版历史PASS推断；该天台完成不转为住房完成。状态仍partial，本轮住房开发/接入/验收deferred，恢复须用户后续明确要求；上节住房回填清单仅作历史待恢复清单。
