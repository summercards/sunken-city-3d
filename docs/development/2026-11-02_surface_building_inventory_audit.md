# 海上建筑清点与设计／账本对照（2026-11-02）

> 本文记录整理前快照；其五值water_layer计数与S03–S05结论由随后[建筑两类职责整理](2026-11-02_building_two_class_contract.md)更新。当前入口见[建筑两类账本](../../assets/registry/BUILDING_CLASSES.md)。浮店故障及运行检查覆盖缺口继续pending。

[主文档](../../GDD_V1.0.md#feature-control) · [SEA-ASSET](../features/asset/ledger.md) · [SEA-WORLD](../features/world/ledger.md) · [场景资产账本](../../assets/registry/ledgers/scenes.json)

本轮为清点与审计。依据当前工作区及本轮隔离验证，未修改建筑源、正式TSCN、分类规则、玩法或资产哈希。工作区原有大量未提交修改，本轮只新增本记录并在两个功能账本追加审计事实。

## 1. 结论与计数口径

海上用途必须同时纳入 `surface` 与 `amphibious`。阳光房虽有海下基座，整栋仍是海上可用设施；不能因为带海下部分而排除。纯水下景观 `submerged`、远景 `backdrop`、船和装饰不计入海上建筑数量。

- **正式场景有8条建筑／设施总成记录，对应7个独立地点。** 绞盘打捞台与野外渔场为同一地点升级前后两种装配，不是新增一座独立岛台。
- **另外4套独立建筑仅完成制作源，未接入Godot。** 其中太阳能花屋被登记为 `part`，仅筛 `entity` 会漏掉。
- **另有13种拼接结构构件**（通用木板＋12件结构），不能当成13栋楼；10件生活摆件、种植平台和培养土另计。
- 当前最小范围纳入4个设施地点：阳光房、打捞台／升级渔场、浅水养殖台、海上悬浮商铺。浮店当前有实测故障，所以“场景存在”不能解释为“四处均可正常玩”。横滨铁道、圆弧农场、远海街町属于保留的完整世界内容，默认范围隐藏。

### 原始账本行数（不是建筑栋数）

| water_layer | entity | part | none | 合计 |
|---|---:|---:|---:|---:|
| surface | 15 | 205 | 0 | 220 |
| amphibious | 9 | 110 | 0 | 119 |
| submerged | 8 | 23 | 0 | 31 |
| backdrop | 82 | 43 | 0 | 125 |
| none | 0 | 0 | 72 | 72 |
| 合计 | 114 | 381 | 72 | 567 |

海上相关共339行＝24条 `entity`＋315条 `part`，内含源级候选、历史件、植物和家具，不能写成339栋建筑。24条实体中，11条是设施／建筑总成、13条是可建结构；再补回误标 `part` 的太阳能花屋，得到12条完整建筑／设施登记（8条运行总成＋4套源级候选）。阳光房海上分区是整栋的子总成，不另增地点。

## 2. 正式场景中的海上建筑／设施

下表8项均为 `amphibious/entity`，所有登记的 source / manifest / runtime_path / prefab 路径当前存在。`runtime_reference_verified` 表示历史参照核验，不代替本轮玩法或美术验收。

| 建筑／设施 | AssetID | 所在场景／职责 | 当前范围与对照结论 |
|---|---|---|---|
| 太阳能木屋／阳光房 | SEA-REF-FACILITY-SOLAR-CABIN | zone1；solar_cabin.tscn；海上区域＋海下基座 | 默认场景，A区住宅；当前源v008。完整三级成长、居民等按原功能账本仍有待完成内容 |
| 绞盘打捞台 | SEA-REF-FACILITY-SALVAGE-STATION | zone1；salvage_station.tscn | 默认场景，同址渔场升级前状态；C区历史设施。打捞指令在最小范围停用，不能以模型存在宣称打捞玩法完成 |
| 野外渔场升级装配 | SEA-FISHERY-ASSEMBLY | zone1；wild_fishery.tscn | 上一项同址升级后状态，条件显隐；本轮fishery-environment 42项通过。原电线杆、海下基础和泊位保留，不是zone5的特殊养殖 |
| 浅水养殖台 | SEA-REF-FACILITY-AQUACULTURE-PLATFORM | zone5；zone5_aqua_platform.tscn | 默认场景；当前提供木板／种植用途，E区特殊养殖、投苗／投喂等仍规划 |
| 海上悬浮商铺／海上补给站 | SEA-SCENE-FSH-ASSEMBLY | SeaStructures/floating_shop；zone_id=sea_supply | 默认纳入，**位置／水线／靠泊／行走故障已复现**；与原家园补给站／渔场不是同一地点 |
| 横滨沉没铁道 | SEA-REF-FACILITY-YOKOHAMA-STATION | zone2；zone2_yokohama_station.tscn | 正式场景资源保留，默认隐藏；“沉没”是名称，屋顶可玩部分仍归海上设施 |
| 圆弧屋顶农场 | SEA-REF-FACILITY-ARC-ROOFTOP-FARM | zone3；zone3_arc_farm.tscn | B区原规划，正式场景保留但默认隐藏；当前生活循环的种植已落在家园／浅水台，不能将旧B区模型标为当前开放 |
| 远海街町 | SEA-REF-FACILITY-FAR-SHORE-SETTLEMENT | zone4；zone4_far_shore.tscn | 正式场景资源保留，默认隐藏；完整世界还有远海资格要求 |

默认范围依据 `godot/src/core/play_scope.gd:13`（zone1、zone5、sea_supply）；场景装配依据 `main.tscn`、zone1及五区TSCN。区域数、设施数与总成数分别计数，不相互替代。

### 与主设计A–E的映射

| 主设计功能区 | 承接位置 | 审计裁定 |
|---|---|---|
| A 太阳能木屋 | 阳光房 | 有资产承接；原完整成长目标仍按SEA-BUILD等账本推进 |
| B 圆弧屋顶农场 | zone3圆弧农场；当前种植循环在家园／zone5 | 有模型，默认范围与初版首局规划不同；这是已登记的范围调整，不是漏资产 |
| C 绞盘打捞站 | zone1独立打捞台；现可升级野外渔场 | 资产存在；原打捞成长和当前渔场用途需要分别读账本 |
| D 水上码头 | 家园栈桥、泊位及交易／船只相关入口 | 功能区不必独占一栋楼；不能因无同名设施总成就判缺一栋。浮店承接补给交易，不等于船只三级升级已完成 |
| E 浅水养殖台 | zone5；特殊养殖仍规划 | 不可把zone1野外渔场的产鱼算作zone5特殊养殖完成；SEA-AQUA账本已区分 |

## 3. 仅有制作源的4套建筑

| 建筑 | AssetID | 当前登记 | 当前源 |
|---|---|---|---|
| 太阳能花屋参考装配 | SEA-SCENE-SOLAR-FLOWER-HOUSE | surface/part，source_verified_runtime_pending；**整套误落零件角色** | solar_flower_house/v004 |
| 清新错层花屋码头 | SEA-SCENE-PFH-ASSEMBLY | surface/entity，source_verified_runtime_pending | pastel_flower_harbor/v001 |
| 饱满卡通热带花屋 | SEA-SCENE-TFH-ASSEMBLY | surface/entity，source_verified_runtime_pending | tropical_flower_house/v001 |
| 巨手托举纪念品灯塔 | SEA-SCENE-LHL-ASSEMBLY | amphibious/entity，source_verified_runtime_pending | liberty_lighthouse/v001 |

4套的runtime_path/prefab均为空，参考图权属均pending。它们是独立保留的制作成果，不表示当前游戏已使用，也不是当前阳光房的额外实例。历史v001/v002/v003等版本不再按建筑种类逐版加数。

## 4. 逐项问题与证据

### S01 · 高：浮店实际装配违反设计，当前无法按海上商铺正常兑现空间关系（已登记旧问题，本轮复现）

设计SEA-ASSET-R35/R36、SEA-WORLD-R13/R14要求：阳光房主体中心正南50米、甲板顶世界Y=1.38（水面1.12＋0.26），可行走环廊、合法泊位。

当前 `godot/scenes/main.tscn:150` 的浮店原点为 **(69.91094, -18.097904, 46.376625)**，带旋转与非均匀缩放；设计冻结原点约(6.158222, -1.134, 51.813078)。X偏差63.75米，南向距离44.56米。该transform与HEAD一致，不是本轮审计产生。

- `floating-shop`：41检查，5失败，退出1。
- `sea-supply`：37检查，8失败，退出1；前／右／后环廊、边缘安全落点、船位水线与码头关系均有失败。
- 正式靠泊查询输出船位 **(52.6004, -12.4096, 44.3212)**，明显低于水面1.12；行走投影仍在1.38米，模型和玩法空间分离。
- 旧专项以“原点Y＋未变换局部板顶”报板顶-15.584；在已有旋转／缩放下这不是精确的真实甲板标高。按完整transform，甲板局部中心(0,2.514,0)世界Y约 **-12.05米**；环廊各点还受倾斜影响。不得沿用旧记录“整栋沉水16.7米”的不准确说法：全栋包围盒顶部仍约5.50米。
- 本轮真实渲染已查看rect-overview与on-deck：主体沉水，“上岸”位置在露出水面的屋顶／栏边，未站在设计甲板上。

此问题已见同日[水层拆分记录](2026-11-02_water_layer_split.md)，本轮不重复计为新缺陷。需要明确浮店的目标职责后再修正式实例变换与空间投影；本轮保留手改TSCN。

### S02 · 高：通用水层门禁存在漏检，截图通过也不代表空间正确（本轮新增审计发现）

`water-layer` 本轮104项全绿，与S01同时成立，因此它只能证明当前执行的声明义务，不能证明建筑水线／玩法完整。

代码审查进一步确认：

1. `test_water_layer.gd:86` 的collect只收集水层非空的节点；未登记节点被直接跳过，`evidence.unregistered` 从未写入。因此文档声称“新增建筑不写水层即报错”尚未兑现。
2. `layer_of` / `role_of` 优先读取存在的属性，即使值为空也不回退metadata。打捞台根脚本继承scene_component.gd，属性默认空串，但TSCN只写metadata；当前证据entities中**没有独立绞盘打捞台**。子树虽可能被宿主区块间接覆盖，它作为entity自身的检查已被跳过。
3. 基座在运行场景标为part，通用专项直接跳过其独立实体义务；账本却写entity（见S04）。
4. 水上检查只看阻挡配置或water_shapes方法存在、有无活动区，没有验证几何与行走面／泊位吻合，也没有验证声明资产与账本角色一致。
5. `capture_floating_shop.gd` 的16项主要检查截图生成／执行到取景分支；“view on-deck”等为check(true)。本轮真实渲染脚本16项通过，截图却呈现S01异常。

以上漏检机制为本轮代码审查证据；本轮未额外注入“缺字段”的故障测试。建议按稳定AssetID／场景职责收集应检对象，再核声明，并以设施专项验证水线和几何关系；截图须人工查看或增加行为断言。

### S03 · 中：完整太阳能花屋误标part，按整栋筛选漏计（本轮新增）

`SEA-SCENE-SOLAR-FLOWER-HOUSE` 的category=scene_assembly，源是v004完整场景，但water_layer_role=part。该家族在工具中统一写死part，没有为这个非“-ASSEMBLY”后缀的独立总成设置例外；它也没有运行宿主来解释为其子件。结果：同为独立源级建筑，PFH/TFH/LHL能筛出来，该套被漏掉。应校准该总成角色及对应家族规则，不改稳定AssetID。

### S04 · 中：账本与正式基座的角色不一致（本轮新增）

`SEA-SCENE-BLB-ASSEMBLY` 账本为submerged/entity；`solar_cabin_submerged_base.tscn:17`及场景声明工具为submerged/part。当前静态校验不对读这两处，所以全绿不表示一致。需统一“独立水下总成”还是“整栋设施内子件”的角色，并写清基座职责。当前规范还要求part水层必须与宿主相同，但阳光房是amphibious，海上／海下子件分别为surface/submerged；这种合法分段与文字规则冲突。

### S05 · 中：水层规范的家族表已落后于实际规则（本轮新增）

`docs/standards/水层分类与空间职责.md:67–68` 与工具／账本不同：

| 家族或资产 | 规范表文字 | 工具／当前账本 |
|---|---|---|
| SEA-SCENE-LHL-*灯塔 | surface | amphibious |
| 种植平台／培养土 | surface/entity | surface/part |
| SEA-KIT-*的10件家具例外 | 泛化写surface/entity | none/none（由KIT_FURNITURE显式处理） |

灯塔有漂浮驳船跨水线，按amphibious有合理依据；土格由宿主提供行走及航线职责，按part也有功能依据。这里应先同步规则文字和例外，不能为了对齐陈旧表格把资产全改成surface/entity。

## 5. 明确不算新增缺陷

- 水上339行包含构件、植物、家具与历史源；数目大不等于重复登记339栋。当前全域静态检查未发现AssetID重复、路径缺失或哈希漂移。
- 海下基座虽然生产分类写building，空间职责仍是水下部分，不计海上独立建筑；六种水下景观在main摆了8个实例，也不计海上数量。
- 打捞台与渔场同址两种状态、阳光房海上分区与整栋、商铺与sea_supply区块均不重复计地点。
- 默认隐藏zone2/3/4有PlayScope及SEA-WORLD-R08承接；不能据此判资源丢失。
- 4套候选未接入、参考授权pending、旧设施来源沿用未重新核验、三级建筑成长／船型成长／居民／第五区特殊养殖待完成，均是原账本已登记边界，本轮不伪报为已完成或新增遗漏。
- A–E是功能分区，不是必须各有一个同名完整楼体；交易码头可以由家园栈桥及泊位承接。

## 6. 本轮验证与证据

命令行工具最初未在PATH，按windows-cli-tool-provisioning的运行进程定位法找到现有Godot 4.6.3，之后仅为验证命令设置GODOT环境变量，未修改机器PATH或项目调用方。

| 检查 | 当前结果 | 退出码 | 证据边界 |
|---|---|---:|---|
| check_feature_contracts.py（初次） | 37功能、578源资产、514运行哈希，0问题 | 0 | 全域结构／路径／已登记哈希；不等于567场景资产之外又新增578个场景 |
| apply_water_layer.py --dry-run | 567行，0差量 | 0 | 账本与工具自身的家族表一致 |
| water-layer | 104检查，0失败 | 0 | 含漏检边界S02 |
| floating-shop | 41检查，5失败 | 1 | S01位置和水线 |
| sea-supply | 37检查，8失败 | 1 | S01行走／靠泊 |
| fishery-environment | 42检查，0失败 | 0 | 原占地、胶囊、围网及候选存读的现有专项 |
| visual-floating-shop | 16检查，0失败；8张真实渲染PNG | 0 | 已亲眼看2张，S01异常；不可据此签美术／可用验收 |

运行验证全部通过scripts/run_verification.py，在Autoload前隔离用户数据。无预期故障注入；本轮未见非预期SCRIPT ERROR／引擎ERROR，13项失败均为浮店断言。未执行：完整世界全部设施的逐处靠泊／移动重验、所有源Blend逐包重开、美术授权审查、设备性能和完整建造／生活回归。不用历史通过替代这些未执行项。

- [本轮headless验证报告](D:/projects/sea-work/verification/20261102-173529-surface-building-inventory-7f8397/report.json)
- [本轮真实渲染报告](D:/projects/sea-work/verification/20261102-173802-surface-building-inventory-render-570ec1/report.json)
- [机器清单：12条总成与339条海上相关记录](D:/projects/sea-work/audits/2026-11-02_surface_building_inventory/inventory.json)
- [浮店水下实景](D:/projects/sea-work/verification/20261102-173802-surface-building-inventory-render-570ec1/project/outputs/floating-shop-rect-overview.png)
- [当前角色上岸实景](D:/projects/sea-work/verification/20261102-173802-surface-building-inventory-render-570ec1/project/outputs/floating-shop-on-deck.png)

后续优先级：先处理浮店的目标摆放和空间一致性，再补水层漏检；随后校准总成／构件角色与规范家族表。维持稳定AssetID和正式场景路径，不重生成覆盖手改场景，不批量刷新哈希。

账本回填后已依工程约定运行 `python scripts/check_feature_contracts.py --sync` 及不带参数复核，均退出0：37功能、578源资产、514运行哈希，0问题。该结果不消除上述浮店运行失败与检查覆盖缺口。
