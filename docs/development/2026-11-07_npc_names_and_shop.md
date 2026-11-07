# 2026-11-07 · 居民生活化称呼、人物内容与阿店迁址

[主文档中控](../../GDD_V1.0.md#sea-resident) · [NPC设计](../features/resident/spec.md) · [NPC账本](../features/resident/ledger.md) · [人物设定](../features/resident/characters.md) · [Shop设计](../features/shop/spec.md) · [Shop账本](../features/shop/ledger.md) · [模块契约](../architecture/module_contracts.md)

## 1. 本轮范围与签署状态

用户22:39要求名字接地气、不限两字，阿店搬到东南海上商店，每人补对白、关系和背景。本轮设计已由主线程追加到GDD；本分支**不修改GDD**，只维护下列七文档：

1. `docs/features/resident/spec.md`
2. `docs/features/resident/ledger.md`
3. `docs/features/shop/spec.md`
4. `docs/features/shop/ledger.md`
5. `docs/architecture/module_contracts.md`
6. 本开发记录（用户明确新增）
7. `docs/features/resident/characters.md`（用户明确允许人物专文）

先读`AGENTS.md`及GDD功能导航、两功能spec/ledger，再只读实际JSON与世界/面板源码。原文档均采用定点Edit/尾部追加，不整文件重写；账本title/link/header JSON、已有verification数组、历史章节和旧PASS保持原顺序，登记头仅将status改为`partial`。已有结构中的历史说明不搬移，也不插新章节到登记头之前。新文档不替代功能账本。

**当前状态：SEA-RESIDENT、SEA-SHOP均partial；本轮运行/视觉/存档/性能签署pending。** 追加前核实Resident最大R14、Shop最大R09，新稳定编号为Resident R15–R18及Shop R10，无编号冲突。旧R01–R14/R01–R09保留用途；R13旧七人全天台分配由R18覆盖，R09公开站位与R14增量性能原则继续有效，不删历史、不把旧PASS签退或冒转成本轮通过。

本分支未改代码、JSON、场景、测试、runner、registry或用户Main roots；未执行global sync、hash、Godot、统一runner或测试。只读源码可以说明实现已经落下，不能说明新运行通过。22:39前的5324/0、241PNG、旧全天台集成/存档计数及约59.943FPS均只保历史范围，不当作迁址与人物扩写验收。

## 2. 实际内容与旧档兼容

### 2.1 显示名与人物字段

实际`godot/assets/data/npc/npcs.json`映射如下，稳定ID不变，不以显示名作为存档键：

| 稳定NPC ID | 新称呼 | 旧显示称呼 | 成人年龄段 | 当前场地 |
|---|---|---|---|---|
| `npc_luo_yan` | 船老大 | 牵线 | 四十来岁 | 天台草地 |
| `npc_mu_he` | 豆豆 | 叶脉 | 二十多岁 | 天台草地 |
| `npc_ji_chen` | 阿海 | 回声 | 三十来岁 | 天台草地 |
| `npc_nan_zhi` | 木头叔 | 榫口 | 五十来岁 | 天台草地 |
| `npc_bai_shi` | 灯伯 | 灯芯 | 六十来岁 | 天台草地 |
| `npc_hua_yi` | 小花 | 花序 | 二十多岁 | 天台草地花摊 |
| `npc_bao_he` | 阿店 | 货架 | 三十多岁 | 东南浮店sea_supply |

昵称不限制二字，不附会民族、地域或假名含义。`profile`九字段为`age_group`、`age_range`、`personality`、`past`、`arrival_reason`、`short_term_wish`、`secret_or_regret`、`habit`、`catchphrase`；成人值在`age_group`，不是新增名为“成人”的字段。七人全部成人，豆豆的称呼不是儿童证据；不硬迁gender，不改玩家可自定义Avatar风格或玩家profile。

每人六条`social_notes[{npc_id,text}]`共42条，写具体相处：船老大给豆豆的种子盖雨衣、阿海给苗留旧盆、木头叔降花架、灯伯抄大字表、小花与阿店隔水托盘和托船送花。它们是定向叙事看法，不新增42条存档关系。九条旧持久边只加`summary/history/tension/reconcile`，edge ID、双方、type/base仍保持。具体七人生平、习惯、愿望、隐情与六人看法/原对白示例已写入[人物专文](../features/resident/characters.md)，不是只有名单。

### 2.2 内容数量与确定性轮换

| 内容 | 实际静态规模 | 不变的边界 |
|---|---|---|
| 人物 | 7份×9字段profile、7份×6看法=42条 | 七稳定NPC ID、角色外观/配件引用、玩家profile隔离 |
| intro | 每人3页，共21页 | 初识会话不混入daily数量 |
| daily | 84旧槽ID，每槽text+2variants=3句，共252句 | morning/work/evening与normal/rain/night/friend维度、旧槽ID |
| 主动话题 | 每人past/daily/friends/plans各1题，共28题，每题2页共56页 | 仅display，不变成新增剧情事件 |
| 剧情 | 21个人+4关系，共25个旧event | event/page/choice ID、条件、前置、effects及数值 |
| 请求 | 7旧request，标题/描述朴素化 | request ID、source_event、costs、result_tag、followup |
| 关系图 | 9旧edge，各补4类背景 | 不新增边、base与原数值效果不变 |

`NpcService._daily_text`现用公式：

```text
count = variants.size() + 1 = 3
weather_offset = [clear, cloudy, rain, storm].find(weather)
index = (day - 1 + weather_offset + seen_events.size()
         + posmod(slot_id.hash(), count)) % count
index == 0 取 text；其余取 variants[index - 1]
```

同日/天气/剧情完成数/槽位输入等价时，重复打开和读档选句一致；跨日可轮换，天气或剧情进度改变也可同日换句，不把“确定性”误写成“一天只能一句”。不新增随机种子、话题阅读数或选句计数存档。

七请求成本便于旧档/回归对照：`request_route_rope` rope×2；`request_seed_trial` seed×3；`request_echo_box` parts×2；`request_joint_bench` wood×3；`request_lamp_glass` glass×2；`request_flower_pot` shell×3；`request_shelf_basket` rope×2。25事件和7请求只改显示文案的要求须由主线程对旧快照验证，本分支不把内容数量核对冒签成条件/effects逐项回归通过。

`npc.version=1`不变，graph/seen_events/choice_flags/request_states结构不增字段；相识、好感、礼物周次数/生日额度、已完成事件、关系delta及请求都按原ID恢复。静态人设/话题/目录不写存档；坏档先验后换、读档清瞬态会话与路径、玩家profile隔离继续验证。禁止因新显示称呼重建默认空npc，也不把已有坏npc当旧档缺字段补空。

## 3. UI与内容可见性契约

实际入口为`NpcPanel → NpcSession → NpcService`，面板首页已有“认识一下”“聊点别的”，页头当前文本为“常在”，不再把生活锚点称作物理“住处”。

| 页面/查询 | 允许展示/执行 | 不允许的泄露或副作用 |
|---|---|---|
| `character_profile(npc_id)` → 认识一下 | 称呼、年纪、性格、过去、来由、愿望、习惯、口头禅及可知看法，查询副本 | 认识页不直接渲染secret_or_regret；不能把编辑用整份人物专文当玩家图鉴。 |
| social_notes → 认识/关系页 | 已认识对象的名字和看法全文 | 对方未相识时，名字和text同时不渲染，仅提示“还没认识的人 · 等见过面再聊。”；不只遮标题。 |
| 关系网 | 双方已知时展示summary/history/tension | reconcile仅相关双方已完成的relationship事件放行，不靠好感、单人剧情或无关事件。 |
| `conversation_topics` → 聊点别的 | 返回四个话题ID与标题；选择后`start_topic`展示两页 | 话题打开、读完、取消、重开不调用talk/meet、不加好感，不写事件/请求，不发剧情或业务完成事件。 |
| 普通daily/intro | 沿原会话与每天首次正常交谈规则 | 不能为了话题零结算而把原daily/intro每日交谈结算一并改掉。 |

四个双人事件与可公开和解边：`relation_old_route → edge_route_echo`，`relation_lamp_promise → edge_joint_lamp`，`relation_seed_color → edge_seed_flower`，`relation_shop_supply → edge_flower_shelf`。其余五边有编辑用reconcile但没有该双方专属双人事件，仍隐藏，不凑新边或新事件。人物自述话题可能谈到旧事，不等于secret字段无条件公开或剧情完成；验收区分“明确隐藏字段”和“叙事提到线索”。

话题使用`_pending.kind=display`，完成时`committed=false`直接返回；UI会话刷新不是业务事件。话题页码、打字进度、按钮戳均瞬态，取消/读档/销毁清理，不持久化。UI、世界输入盾、模态/关闭与鼠标键盘重复输入须本轮实测，不因界面源码存在自动通过。

## 4. 双场地、支撑与经营独立性

### 4.1 当前布局与公开端口

- 六人：`World/SeaStructures/rooftop_ranch/NpcStations`，`rooftop_npc_stations.tscn`六组Home/Work/Social/Rest/Door，共30 Marker。
- 阿店：`World/SeaStructures/floating_shop/Objects/NpcStations`，`floating_shop_npc_stations.tscn`一组五Marker，zone=`sea_supply`，不再在天台留下生效的第七组。
- 两场地合计35 Marker，但不是旧35个全天台Marker。位置随用户实际TSCN root/局部Marker变换，本文不记录硬性绝对世界坐标。源住所保留partial/deferred，不新增住房、不动用户Main roots。
- `NpcAnchorHub.configure([roof_provider, shop_provider])`聚合`anchor_snapshot/home_labels`。Main只注入Hub给Presenter，不新增Main别名表、日程判断或Shop结算规则。
- `canonical_anchor_for_npc(anchor_id,npc)`按NPC稳定归属解释共享旧名。浮店只读适配由`npc_site_anchors.gd`读取地面与Objects刚性frame，天台仍由`npc_rooftop_anchors.gd`提供。

阿店常规06:00–10:00本地理货home=`residence_general_store`、10:00–17:00本地柜台work=`anchor_general_store`、17:00–21:30店边核单social=`residence_general_store_social`；雨天、好友、周末、`relation_shop_supply`和夜间Rest也全留在浮店本地。其他六人的普通与条件日程仍在天台；小花花在天台装盘、托船送，阿店在店边收单收花。不能为了双人剧情强行跨海走路、造一条空中路径或瞬移到对方身边。

### 4.2 动态支撑与性能不退化

浮店原owner继续唯一控制heave。site快照带`position_local/support_frame/support_origin/site_pose/support_revision`及只读ground/ground_space；这些引用和临时坐标不写npc存档。Presenter每physics把刚性frame位移携带到阿店、当前目标和在途路径，廉价检查动态矩形支撑；六个静态天台NPC不新增逐physics三角投影。

layout签名以局部position与静态site_pose/地面revision为准，剔除瞬时世界position/support_origin及海浪高度。海浪升沉不应触发七人全量sync、路径重算或导航rebake；实际root/Marker变动、地面active、surface/revision失效仍使缓存失效。保持R14的clock.changed只notify小字典、0.5秒变化检测、每batch一次Hub快照、force读档恢复与失支撑停止/隐藏/fallback；不以删人、关泛光或降画质换性能。

本轮performance应观察`sync_requests/sync_executed`、anchor_snapshots、pathfinding、support_carries/dynamic_support_checks与导航revision，区分0.5秒检测、真实布局重算和每physics携带，不能拿“没有任何轮询”代替增量正确性。旧59.943FPS/0.008ms重复sync统计不当作本轮持续性能，也不把新海浪引起的全量重算藏进旧计数。

### 4.3 商店标题与独立购买

目标目录标题“小花花店”=`shop_flower`/`npc_hua_yi`、“阿店海上商店”=`shop_general`/`npc_bao_he`。本分支读取`shops.json`时仍是“花序花店/货架综合商店”；**主线程待改标题**，本分支只写契约，不改JSON也不声称标题已落。

两目录11商品ID及价格/上限完全不变：花店3种花种+flower_bundle+flower_ribbon，综合店3作物种子+general_soil/general_rope/general_glass。品种种价仍取CropCatalog，其他价格沿原目录；`flower_ribbon`现标签“花序缎带”不因经营者改名被顺带替换。商店不硬依赖NPC、Farm或住所，只依赖INVENTORY/CROP/INTERACT。

NPC仅发vendor_requested，装配层关闭NPC模态后打开独立ShopPanel；ShopService能在无NPC实例下报价、开店、购买，唯一写口仍为同一Inventory.exchange，失败不变/成功单次、token实例内120秒/256条边界不改。经营场地与vendor是展示/入口，不让好感、秘密、话题或送花叙事暗改价格、库存、订单或存档所有权。

## 5. 稳定条款与实施定位

| 条款 | 文档/源码定位 | 本轮状态与必要新证据 |
|---|---|---|
| SEA-RESIDENT-R15 | resident spec/ledger；npcs.json、npc_save_codec及save接线 | partial/pending：显示名映射、ID与npc.version=1、真实旧档关系礼物剧情请求保留、玩家Avatar隔离。 |
| SEA-RESIDENT-R16 | npcs/dialogues.json；npc_catalog/service/session/panel | partial/pending：7profiles/42notes、21intro、28话题56页、四类边背景、secret/未知对象/和解门禁与话题零副作用。 |
| SEA-RESIDENT-R17 | dialogues/events/requests.json；NpcService._daily_text | partial/pending：84旧daily ID/252句、等价输入读档确定性、25event/7request条件数值不变、取消/回看幂等。 |
| SEA-RESIDENT-R18 | npc_anchor_hub/site_anchors/world_ports/world_presenter，两站点TSCN | partial/pending：6roof/1sea、30+5 Marker、全条件日程不跨海、每physics支撑、heave排除签名且不rebake、R14性能与失效恢复。 |
| SEA-SHOP-R10 | shop spec/ledger；shops.json、ShopService/Catalog/Panel及vendor装配 | partial/pending：两个新目录标题主线程待改；11商品ID/价格不变，无NPC独立购买与迁址后真实两入口/购买/save/视觉。 |

## 6. 主线程实测回填

下表是**新证据占位**，不是已执行结果。主线程计划使用`scripts/run_verification.py`并先核实实际注册入口；本分支不启动任何运行、不进行global sync/hash。结果须带实际命令、时间、head+working_tree或工程外内容快照、隔离存档路径、exit、checks/failures、unexpected_errors、日志/报告与未验说明，不能只写“PASS”。

| 计划入口/层次 | 必须覆盖 | 本轮报告/命令/版本 | exit / checks / failures | 本轮结论 |
|---|---|---|---|---|
| `npc-people` | 名字映射、7份9字段成人profile、42notes、9旧边、21intro、84槽252句、28topic56页、旧25event/7request标识与规则不变 | 待主线程回填 | — / — / — | pending |
| `npc-profile-ui` | 认识/话题可达、secret不渲染、未知对象name/text双隐藏、相关双人剧情前后reconcile、取消/重复阅读无好感或事件写入、常在文案 | 待主线程回填 | — / — / — | pending |
| `npc-shop-site` | Hub/site provider、30+5 Marker、阿店全条件留sea_supply、其他六人留天台、手摆/失支撑/force恢复、支撑携带与独立Shop边界 | 待主线程回填 | — / — / — | pending |
| `npc-relocation` | 真实Main六天台/一海店、鼠标/E与模态关闭、两店真实交易、scene/root与用户摆位未改、迁址后恢复 | 待主线程回填 | — / — / — | pending |
| `visual-npc-people` | 真实渲染的人物、两场地、认识/话题/关系门禁/两新目录标题/购买反馈；逐图人工审阅 | 待主线程回填 | — / — / — | pending |
| rules回归（预期`npc-rules`、`shop-rules`，以实际注册为准） | 原关系/好感/生日/礼物/事件/请求数值、严格目录、无NPC购买、exchange原子/token、旧world选句断言适配后回归 | 待主线程回填 | — / — / — | pending |
| performance回归（预期`npc-performance`，其他时钟/世界专项由主线程选） | 单时钟、0.5秒与每batch快照、heave不令七人全量sync/寻路/rebake，手摆失效仍刷新、不降质 | 待主线程回填 | — / — / — | pending |
| save回归（预期`npc-save`、seed/restart，实际名核实） | 旧档改显示不改ID、不重置关系/礼物/剧情请求、坏档原子、跨进程恢复、路径会话瞬态与玩家profile隔离 | 待主线程回填 | — / — / — | pending |

### 视觉逐图与人工边界

| 应留证画面 | 截图/后端/设备/分辨率 | 人工审阅结果 |
|---|---|---|
| 六人原天台草地同框，新称呼/配件可辨，无阿店旧站位生效 | 待主线程回填 | pending，未捕获/未审 |
| 东南浮店阿店、柜台/晚间本地站位与随heave支撑 | 待主线程回填 | pending，未捕获/未审 |
| 认识页公开资料、secret未直出、未认识对象双隐藏 | 待主线程回填 | pending，未捕获/未审 |
| 主动话题两页与返回/取消、常在文案 | 待主线程回填 | pending，未捕获/未审 |
| 关系页对应双人事件前后和解可见性 | 待主线程回填 | pending，未捕获/未审 |
| 小花花店/阿店海上商店目录标题、商品价格与购买反馈 | 待主线程回填 | pending，未捕获/未审 |

真实图像需实际打开目检，生成PNG或联系图不等于全细节人工验收。设备/发行包/长期性能/全剧情人工体验另签；没有覆盖的项明确保留未验，不用自动化或旧图数量补签。

### 回填同步位置与未验交接

1. 本节写完整本轮命令/工作树/隔离产物、退出码、计数、日志/截图及未验。
2. `docs/features/resident/ledger.md`末节“2026-11-07 22:39 当前覆盖与新增条款承接”：逐R15–R18签真实覆盖，不批量把历史改为新PASS。
3. `docs/features/shop/ledger.md`末节“2026-11-07 22:39 当前覆盖与 R10 承接”：目录标题更新事实、独立购买、两世界入口和save/视觉证据。
4. 两spec文末待回填项据新实测更新状态；未完成仍partial/pending，禁止只因源码或文档写完改为implemented/verified。
5. GDD、runner注册、shops.json两标题以及全局结构/sync/hash由主线程处理；本分支不触碰。住所继续deferred、用户Main roots保留。

## 7. 本文档分支交付说明

已有五文档只定点修改/追加，新建本记录与人物专文；旧七人全天台章节明确为历史，新当前覆盖6roof/1sea。静态内容核对来自实际JSON和源码阅读，不运行任何验收，也不生成或更新hash/派生索引。当前人物内容、世界适配源码已见，商店目录标题仍待主线程改；全部本轮专项/视觉/旧档回归结果待第6节回填，不冒签旧PASS。

## 8. 2026-11-08 磁盘恢复后主线程最终签署

本节覆盖前面分支的pending与待改标题说明，保留它们作为历史。主人确认继续时C盘可用11.58GB，当前本轮代码、内容与文档均已保存；SEA-RESIDENT / SEA-SHOP登记为implemented（非verified）。六人仍在用户原天台，阿店在用户既有东南浮店，建筑手摆root未改，住所继续partial/deferred。

### 8.1 实际改动与失败修复

- `shops.json`两个display_name统一为“小花花店 / 阿店海上商店”，`residences.json`两个展示标签同步；11商品、价格、上限、`flower_ribbon`及其“花序缎带”商品标签未改。
- `test_shop_rules.gd`、`test_npc_integration.gd`与`capture_npc_people.gd`统一断言完整店名，清掉第三种“阿店海店”漂移。
- runner登记`npc-people / npc-profile-ui / npc-shop-site / npc-relocation / visual-npc-people`；独立套件移除Autoload，迁址与画面入口使用`--nosave`。修复隔离工程`terrain`同时copy与mount导致WinError183的旧缺陷；失败目录保留，不碰源terrain。
- 首轮真实失败保留在`20261108-034118-npc-shop-resident-rules-867e17`：people3054/21、rules655/7、profile-ui解析失败、world66/1并脚本错误。people的JSON数值float与literal int字典严格相等误报，改为逐字段精确数值相等和字段集合/数量保护；生产200/500阈值、请求成本未变。rules仍断言旧显示名，更新七个新称呼。
- profile-ui的`Panel`常量遮蔽原生类，改为`NpcPanelScript`；随后1393/24失败来自把每NPC局部话题ID误当全局唯一，改为逐NPC检测。world旧测试未跨面板打开帧、只按下不释放键，改真实按下/释放与跨帧等待、run等待UI协程；保留Enter/E/Esc真实输入断言，不改生产防抖状态机。最终world126/0（新增释放键断言）。
- 二轮失败保留`20261108-034945-npc-resident-fixes-8be300`；最终输入专项`20261108-035802-npc-input-final-305ced`两项全绿。不把失败历史删掉，不改其report。

### 8.2 本轮统一入口与最终结果

实际Godot为4.6.3 console executable；入口均经`scripts/run_verification.py`在Autoload前隔离用户数据。报告包含实际引擎命令、head=`aa12686907371f5e389e5923f259a2f886738235`、working_tree、隔离project和每项user_data_name，不能仅凭同head判断内容相同。`SEA_KEEP_USER_DATA=1`显式保留本轮隔离存档及诊断，避免清理失败掩盖专项结果；未修改真实玩家存档。

```text
python -X utf8 scripts/run_verification.py npc-shop npc-people npc-profile-ui npc-shop-site npc-rules shop-rules npc-world npc-performance npc-clock npc-appearance flower-crops npc-careers sleep-cycle --label npc-final-regression
python -X utf8 scripts/run_verification.py npc-relocation npc-integration npc-save npc-save-restart visual-npc-people --timeout 420 --label npc-people-delivery
python -X utf8 scripts/run_verification.py npc-people --label npc-people-strict-final
```

| 最终报告（均位于工程外sea-work/verification） | 专项与结果 | 结论 |
|---|---|---|
| `20261108-041703-npc-final-regression-799f0f/report.json` | npc-shop18/0、people3054/0、profile-ui1393/0、shop-site335/0、npc-rules655/0、shop-rules259/0、world126/0、performance61/0、clock303/0、appearance2469/0、flower1233/0、careers71/0、sleep42/0 | 13入口全部PASS/exit0 |
| `20261108-035812-npc-people-delivery-599f67/report.json` | relocation898/0、integration695/0、save615/0、seed405/0、restart197/0、visual348/0 | 6入口全部PASS/exit0 |
| `20261108-042106-npc-people-strict-final-0d9095/report.json` | 更严people3054/0 | 覆盖同项最终结果，不重复累加 |

按19个独立入口合计**13177 checks / 0 failures**，所有最终`unexpected_errors=[]`。规则、真实交互、两店交易、六天台一海店、升沉携带及不全量重算、旧v1固定夹具、坏档原子、玩家profile隔离与跨进程重启通过。当前性能专项是机制/计数门禁，不冒签长期FPS。

注意：历史`20261107-222551.../project/assets`与当前assets为同文件目录联接。拿它比对当前events/requests会天然相等，**不是冻结历史数据证据**。本轮旧档兼容依据固定旧v1夹具、成本/条件/ID断言、完整rules/save和真实跨进程恢复；不把链接比较写成“全部旧文案前后已独立冻结比对”。

### 8.3 28张当前真实画面与审阅

图像目录为`../sea-work/verification/20261108-035812-npc-people-delivery-599f67/project/outputs/`。7人各`front/identity/background`合计21张由独立审阅者实际逐图查看；其余7张由主线程逐图打开：`roof-six-group`、`sea-shop-overview`、`sea-topic-selection`、`sea-topic-dialogue`、`sea-relationships`、`sea-purchase`、`flower-title`，全部以`npc-people-`为文件前缀。

- 六人草地同框，阿店浮店实景，七个新称呼与“常在”地点正确；角色与面板可读，无明显文字重叠。
- 两店完整新标题正确，花店5商品/综合店6商品原价，海店真实购买成功反馈可见。
- 主动话题选择/多页对白可读，认识页不直出秘密、未相识看法遮蔽；关系页相关人物认识后可见背景，未解锁和解不直出（门禁由自动专项补验）。
- 长文页底部有滚动视口裁切，滚动条可见，属于正常可滚动布局，不判为丢字；没有凭截图推断视口以下全部内容。审过28图不等于全剧情、全动作、全滚动组合或最终用户美术验收。
- 真实后端Godot4.6.3 / Vulkan Forward+ / RTX4060Ti；不降画质、不以关泛光或删人换性能。本轮未重测长期FPS，不继承历史59.943。

### 8.4 契约与全工程边界

`check_architecture.py`为25服务/0问题，`check_placed_positions.py`为3结构/0警告，`git diff --check`通过。已按约运行`check_feature_contracts.py --sync`及不带参数检查：全工程仍有source/runtime hash漂移与派生索引问题，混合工作树持续并行变动；不批量重签未知文件，也不声称整个工程门禁通过。`--sync`在存在其他issue时按原脚本不写摘要，故全局derived stale单独保留待修，不修改门禁逻辑造绿。

低端设备、发行包、长期运行帧率、全部剧情人工体验、资产权属与用户最终美术确认仍pending，功能implemented不是verified。当前结果与全部命令/错误/图像哈希汇总在工程外`sea-work/outputs/npc_names_shop_acceptance.json`，可视验收页为`sea-work/outputs/npc_names_shop_acceptance.html`。

### 8.5 花种说明最后校对与真实画面复拍

画面目检发现蓝星花/珊瑚花物品desc仍指旧人名“花序”，已仅把这两条说明改“小花”；固定商品“花序缎带”保持。shop-rules新增一条两说明断言；`20261108-043507-npc-label-polish-final-21bea3/report.json`中shop-rules260/0、npc-people3054/0、flower-crops1233/0通过，覆盖前同项最终结果。故19独立入口最终合计**13178/0**（不是13177/0）。

该轮visual在120秒航程到浮店附近未发arrived，278/1失败，原报告保留。成功/失败的boat、actor controller和发航行链源码一致，不能归因于两desc改名；也不能直接断定是性能/靠泊bug。只增强`test_npc_integration.gd`超时日志，追加真实boat position/remaining/route/wp/velocity/process/FPS，不改变生产船或阈值、不放宽抵达断言。

随后统一runner `visual-npc-people --timeout 420 --label npc-visual-route-diagnosis`在`20261108-044915-npc-visual-route-diagnosis-03bb1f/report.json`实际**348/0、exit0、unexpected_errors=[]**，完整28PNG重新生成；最新图目录以此替换8.3旧目录。最终28图全部由独立审阅者实际逐图打开，0空图/破图/文字重叠，两新店标题、六天台一海店、说明“小花培育”与固定商品名正确；原图分辨率1728×1080。一次航程偶发超时未稳定复现，留任务149跟踪，**不宣称根因已经消除**。之前13专项及正式存档/集成结果仍保对应快照证据，不把后续并行改动自动继承成通过。

最终验收页生成时结构检查：全局`--sync` **33 issues**、无参检查 **34 issues**（额外derived feature index stale），均exit1；架构25服务/0、手摆3结构/0警告、全工程diff空白检查exit0。主文档两功能摘要已与implemented登记一致，未批量重签33条未知/混合hash。交付文件为自包含缩略图HTML与完整JSON，原图可单独点击，真实用户数据未删除。
