# SEA-RESIDENT · NPC 居民、对话与关系网 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-resident) · [功能文档](spec.md) · [商店功能](../shop/spec.md) · [施工文档](../../development/2026-11-07_npc_module_framework.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

### 2026-11-07 19:40 覆盖口径（七人全天台历史；本轮以文末22:39覆盖）

七人改在 `rooftop_ranch` 天台草地暂驻，用户手摆root与其下NpcStations的35个局部Marker为站位真值，随scene变换，不锁绝对世界坐标。NPC不再以前置依赖消费SEA-RESIDENCE；公开世界站位端口当前接草地，后续可插住所，R09所有者不变。七人无物理房屋，UI仅写“暂驻天台”；七人/配件/剧情/两商店/五职业和NPC、Shop独立性保留。旧七屋条款保历史，住所partial且deferred用户暂停，不新增开发、不作为当前门禁、不签退通过。截至本轮收尾，Main的resident_harbor实例及zones/scope绑定已移除，源资源保留；用户手摆root及其他旧transform未动。最新已验/未验范围见文末，文档分支不改生产代码。下方旧住所路线与待办均按此覆盖，不再要求本轮完成住房。

```json
{
  "feature_id": "SEA-RESIDENT",
  "status": "implemented",
  "owner": "NpcService / NpcWorldPresenter / AvatarVisual",
  "code_paths": [
    "godot/src/npc",
    "godot/assets/data/npc/npcs.json",
    "godot/assets/data/npc/residences.json",
    "godot/assets/data/npc/dialogues.json",
    "godot/assets/data/npc/events.json",
    "godot/assets/data/npc/requests.json"
  ],
  "verification": ["npc-shop", "npc-rules", "npc-world", "npc-appearance", "npc-careers", "npc-performance", "npc-clock", "npc-integration", "npc-save", "npc-save-restart", "visual-npc-release", "npc-people", "npc-profile-ui", "npc-shop-site", "npc-relocation", "visual-npc-people", "npc-conversation", "visual-npc-conversation"]
}
```

## 设计承接与实施条目

下表保留早期接线前实施状态；R01–R14旧七人全天台运行签署为implemented的历史，证据保留。本轮人物/迁址由文末22:39覆盖与R15–R18承接，登记partial、新实测pending，不沿用旧PASS。

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-RESIDENT-R01 | 部分实现；七人 NPC 目录、独立运行服务、住所声明和角色组装入口已建立 | `npc_catalog.gd`、`npc_service.gd`、`npc_world_presenter.gd`；真实场景位置/完整表现仍待验收 |
| SEA-RESIDENT-R02 | 部分实现；对白运行器、个人/关系事件与Panel/Session选择回看入口已见 | `npc_dialogue_runner.gd`、`events.json`、`npc_panel.gd`；真实输入、取消/重放/幂等及内容游玩仍待专项 |
| SEA-RESIDENT-R03 | 部分实现；数据日程、时间段和 home residence fallback 已建立 | `npc_schedule_resolver.gd`、`npc_world_presenter.gd`；真实 WalkArea 移动仍待专项 |
| SEA-RESIDENT-R04 | 部分实现；七人好感/9边、交谈/礼物限制和图查询已有规则 | `npc_relationship_graph.gd`、`npc_service.gd`、`npc_save_codec.gd`；礼物额度和剧情边可追溯结果仍待实测 |
| SEA-RESIDENT-R05 | 部分实现；NPC 与 Shop 通过 vendor_requested 公开事件连接，不读商店内部字段 | `main.gd` 装配、`shop_service.gd`；Farm/Building/Quest 全链路仍待集成验收 |
| SEA-RESIDENT-R06 | 部分实现；严格 codec 与 Registry/旧档默认入口已见源码，不能视为存档闭环 | `npc_save_codec.gd`、`save_schema.gd`、`save_game.gd`；schema对齐、明确migration、坏档不改现场及跨进程待主线程实测 |
| SEA-RESIDENT-R07 | 部分实现；静态数量核对为7人/7住所引用/9边/84日常对白/21个人+4关系事件 | `npcs.json`、`dialogues.json`、`events.json`；不是内容游玩通过，剧情/回看/fallback仍待验 |
| SEA-RESIDENT-R08 | 部分实现；NpcActor 程序化复用 Avatar/Character，七件独特配件已有源码 | `npc_actor.gd`、`npc_accessories.gd`；外观参数完整性、玩家profile隔离、骨骼动作及真实渲染待验 |
| SEA-RESIDENT-R09 | 部分实现；通过公开世界站位端口，当前草地，后续可插住所；NpcWorldPresenter / NpcWorldPorts所有者不变，CharacterMotor+GroundSpace驱动路线 | `npc_world_presenter.gd`、`npc_world_ports.gd`；旧消费独立住所锚点为19:40前历史，不再作为前置；天台失路/失支撑/暂停/恢复pending主验，不生成房屋 |
| SEA-RESIDENT-R10 | 部分实现；五职业action与两商店vendor意图已有Session入口 | `npc_session.gd`；ship/cultivation/salvage/building/archive接收方与实际结果由主线程接通并回填 |
| SEA-RESIDENT-R11 | 部分实现；独立Panel/Session/world源码已见，生产装配尚需收口 | `npc_panel.gd`、`npc_session.gd`；Main旧HUD桥接、命名端口/模态/恢复需实测，不以测试文件存在算通过 |
| SEA-RESIDENT-R12 | 部分实现；规则已明确112日生日、7日周、生日额度优先和严格npc.version=1 | `npc_service.gd`、`npc_save_codec.gd`；坏数据、时钟倒退、剧情追溯及旧档migration由主线程实测 |
| SEA-RESIDENT-R13 | pending主验；七人暂驻rooftop_ranch草地，用户手摆root+NpcStations35局部Marker随scene变换，无物理房屋、UI仅写“暂驻天台”；住房deferred | 主线程回填Main的resident_harbor实例/zone binding移除且源资源保留、R09公开站位端口、七人/职业/两店、路线与save/integration/真实渲染最新证据；住所版历史PASS不计当前天台通过 |

## 资源与调用入口

- 已有规则、Panel/Session、world源码及运行装配入口；NPC角色程序化复用 `AvatarVisual`/`Character` 和原骨骼动作，七件配件由 `NpcAccessories` 管理，不触碰玩家 `profile`。住所不再由 `NpcWorldPresenter` 生成，正式TSCN/35 Marker/统一GroundSpace归 [SEA-RESIDENCE账本](../residence/ledger.md)。购买规则/独立面板归 [SEA-SHOP账本](../shop/ledger.md)。

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是当前实现的公开契约；生产代码仍必须只通过这些边界交接，不得访问其他模块私有字段。

- 服务：`NpcService`；子职责：`NpcCatalog`、`NpcScheduleResolver`、`NpcDialogueRunner`、`NpcRelationshipGraph`、`NpcSaveCodec`。
- 命令：`meet`、`talk`、`start_npc_dialogue`、`start_event`、`advance_dialogue`、`choose_dialogue`、`close_dialogue`、`give_gift`、`fulfill_request`、`acknowledge_request`、`request_vendor`。
- 查询：`roster`、`npc_snapshot`、`dialogue_state`、`relationship_graph`、`schedule_at`、`list_events`、`gift_options`、`list_requests`；副本不可反写。
- 事件：`npc_met`、`dialogue_completed`、`affinity_changed`、`vendor_requested`、`npc_schedule_fallback`。
- 存档字段：顶层 `npc`，内部 `version=1`；动态字段由 `NpcService.to_dict/from_dict` 管理，瞬态对白不存档。商店购买结果属于 SEA-SHOP。

## 验证记录

本节与下方原“遗留与下一步/主线程回填占位”保留当时阶段记录，所有“当前/pending/待主验”均指当时；最终运行已收齐并通过，以末尾implemented签署为准。

- 2026-11-07 19:40证据隔离：`D:/projects/sea-work/verification/20261107-192319-seven-npc-release-a6fb1b` 为**住所版历史**，其release integration/save已PASS；不是本轮天台版通过。当前R13及天台世界/两店/存档/视觉均pending主线程回填实际入口、命令、版本、退出码、断言/失败数、日志与截图，不沿用旧PASS签署。

历史已登记入口：`python scripts/run_verification.py npc-shop --label npc-shop`，登记头保留其历史值，不等于本轮通过。主线程计划专项为 `npc-rules` / `npc-world` / `npc-appearance`，测试文件已见 `test_npc_rules.gd` / `test_npc_world.gd` / `test_npc_appearance.gd`；本分支不登记或修改runner，不假定这些名称已注册。真实渲染及save/integration按施工文档独立回填。本轮未执行sync、Godot或专项，无通过数。

2026-10-23历史结构验证见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，不作为本轮实测结果。本轮结果待主线程回填本页与[下午施工记录](../../development/2026-11-07_npc_module_framework.md#11-主线程实测回填占位)；历史验证不自动升级为本次通过，未覆盖条款保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 尚无本功能独立运行验收，不将结构通过视为玩法完成。

## 遗留与下一步

当前有七人纯规则、完整预算数量的静态内容、独立Panel/Session/world、Avatar组装与配件源码；不再把“旧五人/半成品内容量/临时生成房屋”当当前方案。主线程须补齐命名时钟/库存端口、原子Inventory.exchange、独立商店桥接、五职业路由、严格存档schema及恢复刷新，再执行规则/世界/外观/住所、真实渲染与save/integration；所有验收未签署前保持 `partial`。

### 主线程回填占位

| 证据层 | 待回填内容 | 当前结论 |
|---|---|---|
| 结构 | 依赖与条款检查实际命令/版本/日志；当前只读候选依赖无环、静态内容数量核对 | 未跑正式结构专项 |
| 运行 | npc-rules/npc-world/npc-appearance实际入口、退出码、断言/失败数；五职业接收方及输入盾/取消/路线fallback | 待主线程实测 |
| 存档集成 | schema对齐、旧无npc明确migration、已有坏npc不改现场、重复/恢复/跨进程日志 | 待主线程实测 |
| 视觉 | 七人差异/七配件/骨骼动作/对白面板/真实住所路线截图及图形后端 | 待真实渲染 |
| 设备与未验 | 设备/分辨率/性能/文件系统及剩余未验条款 | 未验，不由规则替代 |

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。
- 2026-11-07 上午（历史）：建立独立 NPC 模块框架，冻结五人设计；已被下午七人设计扩展，保留记录不作为当前口径。
- 2026-11-07：扩展为七人；加入花店 NPC「花序」、综合商店 NPC「货架」、七个住所 ID、角色配件配置、NPC/商店公开端口、NPC 存档注册和 `npc-shop` 纯规则专项。状态改为 `partial`，未把真实表现验收误报为完成。
- 2026-11-07 下午：保留R01–R07原用途并追加R08–R12；按实际规则核对21+4/84/9、112日生日/7日周和严格graph存档，住所改由独立SEA-RESIDENCE供锚点，补Panel/Session/world及职业挂载/集成待验表。仅文档更新，未运行专项或sync。

## 2026-11-07 天台与性能实施结果（历史：七人全天台）

本节覆盖旧“待接线/仅静态内容”阶段描述，登记头JSON、历史章节和R01–R13承接保留。Main已移除resident_harbor实例及zones/scope绑定，source保留；7人全在既有rooftop_ranch的NpcStations35局部Marker，无物理房屋、UI“暂驻天台”，root及其他用户旧transform未动。七人/七配件、21+4事件/84对白/9边、五职业、两商店11商品、三花四stage已实现，有下列专项，不据此宣称整局全部通过。

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-RESIDENT-R14 | 已实现并通过性能专项与当前设备真实函数/帧率探针；轻量notify、0.5s变化检测、任意日程/条件/21:30边界、关系剧情天气、手摆Marker/root/support失效检测；每batch单snapshot、active/surface/revision支撑缓存、idle免逐physics投影，force恢复保留 | [性能修复记录](../../development/2026-11-07_npc_performance_fix.md)：小fixture61/0；当前合批性能61/0；真实泛光开59.943FPS、Main._process median0.752ms。重复sync median0.008ms不等于全量sync每次0.008ms；R13天台运行主验已由214439通过，产品审阅边界见最终签署 |

- 当前[合批报告](../../../../sea-work/verification/20261107-211435-npc-performance-rooftop-7e1d96/report.json)：npc-performance 61/0、npc-rules 655/0、npc-world 119/0、npc-appearance 2469/0、npc-careers 71/0、flower-crops 1233/0、sleep-cycle 42/0，均exit0/PASS。shop-rules **218 checks / 7 failures、exit1/FAIL**，是UI输入/购买反馈相关的失败历史，已由213213最终shop259/0解决；仍不能将211435旧合批改写为全绿。
- [天台通行报告](../../../../sea-work/verification/20261107-211124-rooftop-access-final-5ada04/report.json)：rooftop-npc-access 772/0、rooftop-ranch 655/0、water-layer 1613/0，三专项均exit0/PASS。只改本轮泊位局部Marker `(26.4,57.3,-2.1)` 与boat `(26.4,57.04,-5.1)`、yaw=PI/2，避开shore_environment旧圆弧楼shape；不将局部测量值钉为世界坐标规则。该报告另有landing-markers失败，不写整份报告通过。
- [真实帧率/函数报告](../../../../sea-work/verification/20261107-211435-npc-fps-after-fix-6e7a56/report.json)两项exit0；[主时钟报告](../../../../sea-work/verification/20261107-212152-npc-clock-once-cc6ca7/report.json)npc-clock301/0与sleep42/0。当前RTX4060Ti/Forward+/1600×1000保留泛光，无减质/删NPC；旧场景住所已撤，draw3186与旧3654–3955不同，不能把~5.7→~60FPS全部归于纯算法。

### 主线程最终回填（独立pending，不沿用历史PASS）

此标题保留历史锚点，原pending现已按末节签署收齐：shop259/0、当前天台五项2277/0均exit0/PASS；14PNG已出，主线程已目检三图、其余11图待审。未将旧失败或住所版PASS改写；剩余设备/发行包/持续性能/全剧情人工体验及全局门禁另签。

## 最终签署：天台R01–R14运行实现通过（22:39前历史）

登记状态由partial定点改为 **implemented（已实现待完整产品验收）**，非verified；登记头其余字段及章节顺序保留。下表覆盖上方早期“部分实现/待接线/待主验”，不删除历史。

| 条款范围 | 当前实际覆盖 | 证据与产品边界 |
|---|---|---|
| R01–R05、R07、R10、R12 | 七人独立规则/内容、21+4/84/9、对白选择/回看/幂等、好感关系/严格规则、职业/两店/七请求礼物端口均已实现并专项和集成通过 | 既有rules655/0、careers71/0、flower1233/0与最终integration668/0；R02/R07全剧情人工体验不由自动化替代 |
| R06、R11 | 严格坏档原子、迁移、取消/恢复与跨进程及玩家profile隔离通过；真实HUD航行/上下船/消防梯/七点步行/点击与E、各职业实际链路通过 | 最终save618/0、seed408/0、restart202/0；设备/发行包与全局门禁另签 |
| R08、R09、R13 | 七人全部在既有天台草地35局部Marker，实际路线/交互已验；无新住房，Main旧住所挂载及zones/scope已撤、source保留，用户root未动 | world119/0、appearance2469/0及最终visual381/0；14PNG已出，主线程三图目检，11图尚待人工审阅 |
| R14 | 单batch snapshot、0.5s边界/关系剧情天气/手摆变换/support失效、idle免逐physics投影与force恢复通过 | 性能61/0、clock301/0+sleep42/0与既有59.943FPS；持续性能/其他设备未签，重复sync0.008ms非每次全量耗时 |

[最终shop报告](../../../../sea-work/verification/20261107-213213-shop-input-final-638cdf/report.json)：259 checks / 0 failures，exit0/PASS。[当前天台最终报告](../../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/report.json)：npc-integration668/0、npc-save618/0、npc-save-seed408/0、npc-save-restart202/0、visual-npc-release381/0，合计2277/0；五项exit0/PASS、unexpected_errors=[]。head均aa12686907371f5e389e5923f259a2f886738235；实际命令、working_tree、隔离存档和工程外快照见各报告，不仅用head判内容一致。

主线程实际目检seven-residents、flower-purchase、story-choice三张：7人原天台草地，无新住房、形象/配件可辨；花店5商品/价格/购买成功，剧情可读且2choices，UI天台暂驻。14图路径与逐图状态见[性能记录第8节](../../development/2026-11-07_npc_performance_fix.md#8-最终天台运行签署与14图清单)，**不声称其余11图已目检**。

当前运行范围无已知未覆盖条款；完整产品验收未覆盖部分：R02/R07全剧情人工体验、R08/R11/R13全细节/全动作视角人工审阅、R11/R14设备/发行包/持续性能。历史landing-markers额外失败不因本次天台链通过而冒称原专项重跑。SEA-RESIDENCE仍partial/deferred，历史R01–R07未签完成。

## 主线程最终回归补签（22:39前七人全天台历史）

[221054回归](../../../../sea-work/verification/20261107-221054-npc-final-regression-bc8a22/report.json)11项 **5324/0**，全部PASS/exit0；[222551当前工作树](../../../../sea-work/verification/20261107-222551-npc-final-live-worktree-6eb68a/report.json)外观真实捕获 **241 PNG/0失败**、兼容购买44/0、正式集成668/0、存档618/0、seed408/0、restart202/0，全部PASS/exit0、无unexpected_errors。主线程已通过原图/联系图审阅14张场景图，另审七人正面组装设计；场景草高会遮住腿部/小配件，未冒签全部241图细节人工验收。此节覆盖上文三图已审/十一图待审的阶段口径，旧记录保留。

性能仍为独立实测约59.943FPS、Main0.752ms，保持泛光；完整修复与混合工作树限制、当前**sync17/check18**全局问题见[性能记录第9节](../../development/2026-11-07_npc_performance_fix.md#9-主线程最终回归视觉审阅与门禁)。架构扩展后25服务/0问题、3手摆结构/0警告、diff检查通过。功能已实现不等于全工程hash门禁通过，后续并行改动不自动继承上述快照PASS。

## 2026-11-07 22:39 当前覆盖与新增条款承接

本轮状态 **partial / pending**。登记头仅定点改status，title/link/header JSON及历次章节、旧verification值和证据保持，不把计划入口冒写成通过。上方七人全天台/35天台Marker、旧implemented与最终PASS均为22:39前原工作树历史；旧R01–R14用途保留，R13场地分配由R18覆盖，R09公开端口/R14性能原则延续。当前六人天台30 Marker、阿店东南sea_supply浮店5 Marker；住所source继续partial/deferred，不改用户Main roots，不恢复住房开发。

### 设计承接与实施条目（本轮）

追加前最大稳定编号R14，无新编号冲突。以下静态事实来自实际内容和源码只读核对，不是运行签署；完整设计见[当前spec](spec.md#2026-11-07-2239-当前覆盖生活化称呼人物内容与六天台一海店)、[人物专文](characters.md)、[开发记录](../../development/2026-11-07_npc_names_and_shop.md)。

| 对应设计条款 | 当前实施状态 | 证据 / 本轮验证要求 |
|---|---|---|
| SEA-RESIDENT-R15 | partial；七稳定ID已映射船老大/豆豆/阿海/木头叔/灯伯/小花/阿店，npc.version=1不变；本轮pending | `npcs.json`与严格codec。主线程以旧档验证相识/好感/礼物/事件/请求按ID保留，玩家Avatar与gender不强迁；不能只检查七个显示字符串。 |
| SEA-RESIDENT-R16 | partial；九字段成人profile×7、social_notes六条×7=42，九旧边新增四类背景，intro21页、28话题56页与认识/话题UI源码已见；本轮pending | `npcs/dialogues.json`、`npc_catalog/service/session/panel.gd`。`npc-people`/`npc-profile-ui`须验secret隐藏、未认识name/text双隐藏、相关双人剧情才显示reconcile及话题display无好感/事件/持久写入；其余五边无专属双人事件，不自动公开reconcile。 |
| SEA-RESIDENT-R17 | partial；84daily槽各text+2variants=252句及确定性选句源码已见，25旧事件/7请求文案朴素化；本轮pending | `dialogues/events/requests.json`、`NpcService._daily_text`。按同日/天气/剧情/槽位重复与读档复现；对比ID/条件/effects/costs等不变、取消/回看不重复结算，rules/save独立回归。 |
| SEA-RESIDENT-R18 | partial；Hub/site provider、roof30+shop5 Marker、阿店本地home/work/social与support_frame每physics携带源码已见；本轮pending | `npc_anchor_hub/site_anchors/world_ports/world_presenter.gd`与两站点TSCN。`npc-shop-site`/`npc-relocation`/performance须验所有条件日程不跨海、heave不触发七人全量sync/寻路/rebake，真实手摆/失支撑/恢复仍失效；`visual-npc-people`实拍6roof/1sea。 |

### 本轮主线程回填位置

| 层次 / 计划专项 | 应回填内容 | 当前结论 |
|---|---|---|
| 人物 / `npc-people` | 实际入口、命令、head+working_tree/工程外快照、exit、断言/失败、内容ID与数量/旧档检查日志 | pending，未运行 |
| UI / `npc-profile-ui` | 认识/话题/关系页、未知对象双隐藏、四相关双人剧情前后reconcile、话题取消/重读无业务副作用 | pending，未运行 |
| 站位 / `npc-shop-site`、`npc-relocation` | 天台6/海店1、30+5 Marker、全条件日程、用户root未动、失路/失支撑/恢复与两店独立入口 | pending，未运行 |
| 回归 / rules、performance、save | 主线程确认实际入口（预期npc-rules/shop-rules/npc-performance及npc-save/seed/restart）；海浪期sync/寻路/导航计数、旧档和玩家profile隔离 | pending，未运行；不继承旧59.943FPS或5324/0 |
| 视觉 / `visual-npc-people` | 真实后端/设备/分辨率、6roof与1sea、认识页/话题/隐藏/关系解锁/两商店截图，逐图实审与未审清单 | pending，未捕获、未目检 |
| 全局与产品 | 全局结构/hash及设备/发行包/持续性能/全剧情人工体验由主线程另签 | 本分支禁止global sync/hash/运行，不签通过 |

实际结果同时回填[开发记录第6节](../../development/2026-11-07_npc_names_and_shop.md#6-主线程实测回填)。Shop经营者场地与独立购买见[SEA-SHOP-R10](../shop/spec.md#2026-11-07-2239-当前覆盖经营者场地与独立购买)；目录目标小花花店/阿店海上商店由主线程改JSON，本分支未改商品/价格。本轮仅文档定点编辑与新建明确要求的两篇文档，无global sync、hash、Godot、runner或测试执行，无本轮通过数。

## 2026-11-08 继续执行后本轮运行签署

| 对应设计条款 | 当前实施状态 | 本轮证据 |
|---|---|---|
| SEA-RESIDENT-R15 | implemented；七新称呼、稳定ID及v1旧档保留 | people3054/0、save615/0、restart197/0 |
| SEA-RESIDENT-R16 | implemented；七背景/42看法/28话题56页与隐私、只读展示 | profile-ui1393/0、relocation898/0、28图审阅 |
| SEA-RESIDENT-R17 | implemented；252句确定性轮换、旧规则与幂等保留 | people3054/0、npc-rules655/0、save615/0 |
| SEA-RESIDENT-R18 | implemented；6roof/1sea、30+5 Marker与动态支撑/增量失效 | shop-site335/0、relocation898/0、performance61/0、integration695/0 |

登记头状态已定点更新为`implemented`，不标`verified`；标题回链、登记头JSON其他字段、历史验证数组与历史章节均保留。R15–R18保持原稳定用途。本轮实际已注册新入口：`npc-people`、`npc-profile-ui`、`npc-shop-site`、`npc-relocation`、`visual-npc-people`。正式`shops.json`为小花花店/阿店海上商店，`residences`标签同步，仅改display label；11商品和`flower_ribbon`/“花序缎带”未改。六人天台30 Marker、阿店东南`sea_supply`五Marker、建筑手摆root均保持不动，住所继续deferred。

最终13专项报告：`D:/projects/sea-work/verification/20261108-041703-npc-final-regression-799f0f/report.json`，包含`npc-shop`18/0、`npc-people`3054/0、`npc-profile-ui`1393/0、`npc-shop-site`335/0、`npc-rules`655/0、`shop-rules`259/0、`npc-world`126/0、`npc-performance`61/0、`npc-clock`303/0、`npc-appearance`2469/0、`flower-crops`1233/0、`npc-careers`71/0、`sleep-cycle`42/0。更严字段/数值复跑`D:/projects/sea-work/verification/20261108-042106-npc-people-strict-final-0d9095/report.json`为`npc-people`3054/0，作为最终覆盖，不重复累加。正式交付报告`D:/projects/sea-work/verification/20261108-035812-npc-people-delivery-599f67/report.json`包含`npc-relocation`898/0、`npc-integration`695/0、`npc-save`615/0、`npc-save-seed`405/0、`npc-save-restart`197/0、`visual-npc-people`348/0及28张PNG。按19个独立入口合计13177/0，均exit0且`unexpected_errors=[]`。

设备为Godot4.6.3/VulkanForward+/RTX4060Ti；1920为窗口记录，PNG实际像素以文件为准。21张人物front/identity/background由独立代理逐图查看，7张场景业务图由主线程逐图打开；长文底部为可滚动视口正常剪裁，未推断隐藏行。28张图都审阅不等于所有剧情、动作或滚动以下内容均人工验收。低端、发行包、完整剧情体验、资产权属、用户美术验收仍pending；未测长期FPS，不继承59.943。`npc.version=1`未变，固定旧v1数据、严格坏档、跨进程验证。

旧FAIL历史继续保留并追加说明：float与literal int dict严格比较误报改为逐字段数值相等并保留精确字段数；另修旧名字断言、Panel常量遮蔽native、话题局部ID误判全局唯一、UI键盘同帧/未释放。仅测试与runner修复，无事件数值变动；runner补五入口、独立套件移除autoload、集成使用`--nosave`、修复terrain重复copy/mount缺陷。全局门禁当前sync32/check35问题可能并行变化，不锁最终数字；hash/source drift未批量重签。architecture25服务0、placed3结构0警告、gitdiffcheck通过，但不宣称全工程门禁通过。验收页为`D:/projects/sea-work/outputs/npc_names_shop_acceptance.html`及同名JSON，开发记录由主线程追加第8节；历史assets为symlink同文件，不能作为冻结内容快照比对证据。

### 2026-11-08 最后校对覆盖

两花种说明旧人物名改“小花”，固定“花序缎带”不改。最终`20261108-043507-npc-label-polish-final-21bea3`中shop-rules260/0、people3054/0、flower1233/0；该轮视觉航行120秒超时278/1保留，不隐去。仅加强超时诊断、不改生产船/坐标/抵达阈值后，`20261108-044915-npc-visual-route-diagnosis-03bb1f`视觉348/0并重拍28PNG；最终28图逐图已审无空图/破图/重叠。最终19入口合计**13178/0**，覆盖上方13177计数；一次航程超时未稳定复现，根因仍留持续性能跟踪，不冒签彻底解决，详开发记录8.5。


## 2026-11-08 NPC先对话再进入功能

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-RESIDENT-R19 | implemented；最终验收回填见本节后续记录 | `npc-conversation`、`visual-npc-conversation`及相关规则/存档回归；实现与验收路径见[开发记录](../../development/2026-11-08_npc_conversation.md)。 |
| SEA-RESIDENT-R20 | implemented；最终验收回填见本节后续记录 | `npc-conversation`、`visual-npc-conversation`及相关规则/存档回归；实现与验收路径见[开发记录](../../development/2026-11-08_npc_conversation.md)。 |
| SEA-RESIDENT-R21 | implemented；最终验收回填见本节后续记录 | `npc-conversation`、`visual-npc-conversation`及相关规则/存档回归；实现与验收路径见[开发记录](../../development/2026-11-08_npc_conversation.md)。 |


### 本次最终验收签署

本节新增条款已实现并完成当前交互验收。13个独立入口5040/0，均exit0且unexpected_errors为空：NPC主场景473/0、真实渲染498/0（25张最终PNG全部状态已审）、规则655/0、世界136/0、资料话题1387/0、增量性能61/0、商店260/0、整局存档702/0、seed476/0、不同进程restart202/0、最小循环112/0、开场键盘39/0、点击39/0。报告选择、截图像素、逐图审阅、过程FAIL与最终覆盖均见[开发记录最终签署](../../development/2026-11-08_npc_conversation.md#最终签署本次交互专项通过2026-11-08)。资产/运行资源哈希门禁sync45、check46项仍FAIL/exit1，原基线漂移未批量重签；不以专项通过冒充全工程通过。手柄/触屏、低端/发行包、全部剧情人工游玩未执行，整体功能非完整产品verified。

## 2026-11-08 NPC 体系一套与功能出口三档

| 对应设计条款 | 当前实施状态 | 证据 / 待办 |
|---|---|---|
| SEA-RESIDENT-R22 | implemented；七人共用 `npc/` 全套实现，差异只在出口三档；共用层无按 npc_id 的业务分支 | 源码核对：`godot/src/npc/` 19 文件 3280 行，`npc_service`/`npc_session`/`npc_panel`/`npc_world_presenter`/`npc_save_codec` 内除 `FUNCTIONS` 与问候语表外无 npc_id 业务分支；`npcs.json` 七行同构。运行证据沿用 `npc-rules`、`npc-world`、`npc-careers`、`npc-integration`、`npc-save`、`npc-conversation`、`visual-npc-conversation` 既有通过结果，本轮未重跑。 |
| SEA-RESIDENT-R23 | **pending**；`function` 出口仍五处硬编码，未收口为 `npcs.json` 单一真源 | 硬编码位置：`godot/src/npc/npc_session.gd:6-12`、`:98-100`、`godot/src/bootstrap/main.gd:3819`、`:3826`、`:3875`。风险：新增职能 NPC 漏改 `main.gd:3819` 的 `expected` 会让 `_on_npc_career_requested` 静默 `return`，按钮点了没反应且不报错。收口属重构，需改 `npc_session.gd` 与 `main.gd` 接线并重跑 `npc-rules`/`npc-careers`/`npc-integration`/`npc-save`，本轮未做。 |

结构与数据事实（本轮只读核对，未改代码、未运行）：七人稳定 ID、七件配件、`npc.version=1` 与 `npcs.json` 七行字段均未变；`shop` 出口已是单点（`shop_id` 一行），`function` 出口尚未。本条不改变 R19–R21 的对话交互口径，也不改变 SEA-SHOP-R11/R12 的商店归属。

本轮的商店图标网格改动（SEA-SHOP-R12、SEA-UI-R59）不动 NPC 侧任何文件；相关运行证据见[商店账本](../shop/ledger.md#2026-11-08-商店图标网格交付)。

## 2026-11-08 豆豆迁场与头顶招呼

| 对应设计条款 | 当前实施状态 | 本轮证据 |
|---|---|---|
| SEA-RESIDENT-R24 | implemented；豆豆日程指向霓虹花园菜园桥，第三处 provider 已聚合，跨区落位走支撑点而非寻路 | `garden-npc`14/0（5 锚点可解析、work=(106.2377, 12.52529, 83.00532)、豆豆世界位置在桥面）；`npc-integration`749/0、`npc-save`702/0、`npc-save-seed`476/0、`npc-save-restart`202/0、`npc-world`135/0、`npc-rules`655/0 均通过 |
| SEA-RESIDENT-R25 | implemented；头顶气泡组件与按日轮换台词已接入，真实渲染已验 | `garden-npc`14/0（靠近显示台词、同日不换句、换日换句）；`visual-garden-bubble`13/0（两张真实 PNG：单句/长句换行，逐图审阅：纸面、三角、文字、视口内、尾巴指向头顶） |

新增文件：`godot/src/ui/speech_bubble.gd`、`godot/assets/data/npc/greetings.json`、`godot/tests/test_garden_npc.gd`、`godot/tools/capture_garden_bubble.gd`。改动：`npcs.json`（豆豆 6 处锚点）、`neon_garden_quarter.tscn`（`NpcStations` 五 Marker）、`main.gd`（第三 provider、`_tick_garden_greeting`、气泡装配）、`npc_world_presenter.gd`（跨区落位）。

明确取舍：**玩家走不到豆豆身边**（菜园桥约 28 米高、无上楼路径，用户选择只让她在楼上）。`npc-conversation` 里她的「走近交谈」已改为断言「楼顶可见」，不是放宽而是承认该链路在她身上不成立。**「今天已喊过」不持久化**：`npc_save_codec` 严格字段校验不接受新字段，加字段会让旧档加载失败；读档后当天可再喊一次。

连带更新的断言：`test_npc_integration.gd`（锚点 35→40、`home_labels` 7→8、`owners` 豆豆改判日程、`homes`/`interactions` 7→6、`npc_site_position`/`npc_supported` 加花园分支）、`test_npc_save.gd`（新进程 `zone_id` 三选一）、`test_npc_conversation.gd`（豆豆跳过走近）、`test_npc_world.gd`（豆豆在仅含旧住所港的夹具里允许回退，已注明夹具边界）。这些是布局真实变化后的必要同步，不是掩盖。

未验：豆豆在楼上的动作是日程锚点落位 + 既有 `set_action` 动画，**没有新增播种/浇水/收获的行为树**——与本轮「NPC 的 AI 行为」的字面要求有差距。

## 2026-11-08 晚 招呼气泡放大与触发半径放宽

| 对应设计条款 | 当前实施状态 | 本轮证据 |
|---|---|---|
| SEA-RESIDENT-R25 | implemented；气泡放大到字号 30 / 宽上限 468（且不超过视口宽 42%）/ 停留 7.5 秒，触发半径 16→32 米；角色出画只隐藏不结束 | `garden-npc`17/0（含「抬头看向楼顶时气泡显示台词」「气泡按远读尺寸排版 524×122」「角色出画时收起」「回到画面恢复」）、`visual-garden-bubble`21/0（4 张 PNG：近景单句、长句换行、30 米远景、1280×800 小窗）、`minimum-loop`112/0，均 exit0 |

起因：用户反馈首版「对话框太小、得靠这么近才能看到」。首版字号 21、宽上限 292、半径 16 米，实际要贴到楼底才触发且仍偏小。

补记一处必须写明的实现细节：`is_speaking()` 的语义从「可见」改为「还在这次招呼里」（`_target` 有效且 `_alpha > 0`）。放大后角色常在镜头外，若仍按「可见」判定，上层会把「她出画」当成「已经说完」，镜头转回来就再也不显示了。

只改 `speech_bubble.gd` 与 `main.gd` 两个常量。`main.tscn` 无 diff，用户手摆 transform 未动。详见[开发记录第 12 节](../../development/2026-11-08_neon_garden_garden.md#12-当晚修订气泡放大触发半径放宽用户反馈)。
