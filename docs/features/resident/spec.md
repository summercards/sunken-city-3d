# SEA-RESIDENT · NPC 居民、对话与关系网

[主文档中控](../../../GDD_V1.0.md#sea-resident) · [本功能账本](ledger.md) · [商店功能](../shop/spec.md) · [住所功能](../residence/spec.md) · [施工文档](../../development/2026-11-07_npc_module_framework.md)

设计修订：r5（2026-11-07 22:39，生活化称呼、人物内容与六天台/一海店）。所属系统：生活。本轮状态 **implemented（2026-11-08当前运行签署，非verified）**；当前规则以文末“22:39 当前覆盖”及 R15–R18 为准，最新实测见末尾11-08签署，旧七人全天台签署仅对原快照有效。人物内容见[七名居民人物设定](characters.md)，交接见[本轮开发记录](../../development/2026-11-07_npc_names_and_shop.md)。

### 2026-11-07 19:40 覆盖声明（历史：七人全天台）

用户最新要求：“先不用做他们的住所，先全部放到那个天台草地上去”。七人当前正式现场改为 `rooftop_ranch`，沿用户手摆 root 下的 `NpcStations` 提供35个局部 Marker，随 scene/root 变换求实际站位，不写绝对世界坐标。七人当前无物理房屋，UI显示“暂驻天台”，不写“已经住屋”；保留七人稳定ID、七件配件、21+4剧情/84对白/9边、两商店和五职业端口，NPC与Shop继续独立。

移除NPC对SEA-RESIDENCE的功能前置依赖；生活站位改走公开世界站位端口，当前接草地，未来可插住所但不是本轮门禁。下文七屋/50m²/家具/住所消费及 `(38,0,-32)` 仅保留为19:40之前的历史方案；住所资源留存，状态partial、制作/接入deferred（用户暂停），不新增住房开发，不删除或签退历史条款。截至本轮收尾，Main已移除resident_harbor实例及zones/scope绑定，源资源保留；用户手摆root及其他旧transform未动。执行事实与待主验范围见文末最新记录。

`D:/projects/sea-work/verification/20261107-192319-seven-npc-release-a6fb1b` 的release integration/save已PASS仅属住所版历史，不是天台版通过。当前天台运行验收已由214439五项2277/0、exit0/PASS独立确认，14PNG已出、三图已由主线程目检，其余11图待审；最终范围见文末签署。
功能登记名仍为 `SEA-RESIDENT`；运行模块名为 **NPC**，职责目录为 `godot/src/npc/`。商店另以 `SEA-SHOP` 登记，NPC 只发出 vendor 端口事件，不拥有商品、价格或购买结算。

## 1. 功能目的与边界

NPC 模块负责七名固定居民的身份、日程、对话剧情、玩家关系、居民之间的关系网、住所归属和可选请求。它可以在没有 Farm、Building、Order 或 Shop 内部字段的情况下独立运行；跨功能只通过注入端口、公开查询、命令和事件交接。

本模块拥有：

- 七名 NPC 的稳定身份与内容目录；
- NPC 的日程解析、位置意图和生活状态；
- 与玩家的好感、见面、送礼限制、剧情解锁；
- NPC-NPC 关系图、关系变化和关系相关剧情条件；
- 对话队列、分支选择、事件幂等和请求状态；
- 七名 NPC 的稳定归属引用；当前生活锚点由既有天台的公开世界站位provider提供，SEA-RESIDENCE仅为暂停的历史方案，NPC不拥有空间布局；
- `npc` 存档快照及版本迁移。

本模块不拥有：

- 玩家背包、瓶盖、作物、建筑、船只、世界时间或移动物理；
- NPC 的真实导航求解和碰撞体；它只发出移动意图，由 SEA-MOVE / SEA-WORLD 执行；
- 任务总账或订单总账；NPC 请求可以被 SEA-QUEST / SEA-ORDER 消费，但不复制它们的状态；
- 战斗、血条、死亡、失败状态、婚姻或强制恋爱线。关系变化只影响可选对白和剧情，不会让核心种植/建造循环失败。

## 2. 牧场类 NPC 参考与本项目取舍

参考牧场类游戏常见的四个有效结构：

1. **日程驱动生活感**：NPC 按时间、星期、天气和关系条件切换地点/动作/对白。
2. **关系分段**：玩家每天交谈、完成请求、送礼后，关系进入可读的阶段，解锁人物故事。
3. **关系事件**：事件不是单纯弹文字，而是展示人物选择、共同生活和世界变化。
4. **关系网**：NPC 之间本来就有亲属、师徒、同伴和矛盾，玩家接触一个人会逐步理解其他人。

本项目不照搬某一款游戏的角色、台词或数值。关系值、周限制和事件条件采用本项目自己的契约，先保证“温和、可回看、无失败压力”。参考入口：[Stardew Valley Friendship](https://www.stardewvalleywiki.com/Friendship)、[Stardew Valley Schedule data](https://stardewvalleywiki.com/Modding:Schedule_data)、[Story of Seasons 关系与事件概述](https://harvestmoon.fandom.com/wiki/Story_of_Seasons)。

## 3. 七名 NPC 首批 roster

以下 `npc_id` 是稳定 ID。22:39当前显示名采用日常称呼，不限两字，不附会民族、地域或假名含义；旧名仅用于辨认历史记录，不作存档迁移键。

| npc_id | 当前显示名（旧名） | 职能 | 当前常在场地（非住房承诺） | 眼下主线 | residence_id（保留稳定引用） | 关联模块 |
|---|---|---|---|---|---|---|
| `npc_luo_yan` | 船老大（牵线） | 船匠、领航员 | 天台草地·船务站点 | 修备用船、重测水深，与阿海对清返航信号 | `residence_dock_workshop` | SEA-SHIP / SEA-NAV / SEA-BUILD |
| `npc_mu_he` | 豆豆（叶脉） | 种植者、种子保管人 | 天台草地·种植站点 | 重写标签、轮种青菜，试种失去名字的种子 | `residence_sunroom_greenhouse` | SEA-FARM / SEA-CROP / SEA-INVENTORY |
| `npc_ji_chen` | 阿海（回声） | 打捞者、旧城记录员 | 天台草地·打捞整理站点 | 修日志匣、补记漏看的返航信号 | `residence_salvage_cabin` | SEA-SALVAGE / SEA-DIVE / SEA-WORLD |
| `npc_nan_zhi` | 木头叔（榫口） | 木工、屋顶修缮师 | 天台草地·木作站点 | 修稳长凳，为小车留道、做不挡路的工具架 | `residence_builder_loft` | SEA-BUILD / SEA-BUILDING / SEA-WORLD |
| `npc_bai_shi` | 灯伯（灯芯） | 灯火守望者、档案管理员 | 天台草地·档案站点 | 换灯罩、分清借物本与名册，补写旧尺寸的缘由 | `residence_lantern_archive` | SEA-QUEST / SEA-TIME / SEA-WORLD |
| `npc_hua_yi` | 小花（花序） | 花店经营者、花材培育师 | 天台草地·小花花店站点 | 修排水、摆明价签，托船给阿店送瓶装花 | `residence_flower_shop` | SEA-SHOP / SEA-FARM / SEA-CROP |
| `npc_bao_he` | 阿店（货架） | 综合商店经营者、补给整理员 | 东南海上商店·`sea_supply` | 理补货单、修借物篮，在店边收花和核单 | `residence_general_store` | SEA-SHOP / SEA-INVENTORY / SEA-ORDER |

### 首批内容预算（旧七人全天台阶段历史，22:39扩写见文末）

- 7 个个人剧情线，每人 3 个剧情事件：初识、转折、收束，共 **21 个个人事件**。
- 4 个跨人物关系事件：牵线/回声的旧航线、榫口/灯芯的师徒约定、叶脉/花序的种植记忆、花序/货架的商店补给，共 **4 个关系事件**。
- 7 个 NPC × 3 个日程段 × 4 种对白情境（普通日、雨天、夜间、关系阈值）作为首批数据预算，共 **84 个对白槽位**；槽位没有内容时必须走模块 fallback，不显示空框。
- 首轮不做婚姻、配偶、儿童和永久错过剧情；所有剧情可回看，错过当天只改变出现时机，不删除内容。
- 七人保留独立 `residence_id` 作为稳定语义引用，当前由天台草地NpcStations35局部Marker承接，不代表已住屋。21+4事件、84日常对白和9关系边已实现且有规则/集成专项，完整剧情人工体验另待产品验收。旧独立50m²房屋/床桌灯/住商空间方案保留在下文“住房历史方案”专节，不作为当前前置。

## 4. 关系网

关系网分为“静态内容关系”和“剧情运行变化”两层。静态关系在 `NpcCatalog` 中，运行变化只写 `edge_deltas`，不改内容表。下表保留旧称及早期叙事摘要作历史，当前九边ID/base不变，实际背景以文末22:39覆盖及[人物专文](characters.md#9-九条持久关系边与和解可见性)为准。

| 关系边 | 类型 | 基础强度 | 初始冲突/纽带 | 可触发的公共剧情 |
|---|---|---:|---|---|
| 牵线 ↔ 叶脉 | 旧日同伴 | +65 | 航线优先还是种子优先 | 共同修复第一条生活航线 |
| 牵线 ↔ 回声 | 前搭档 | -35 | 一次打捞事故后的信任裂痕 | 找回旧航行记录 |
| 牵线 ↔ 榫口 | 工作伙伴 | +20 | 实用结构与居住舒适的取舍 | 码头与屋顶之间的连接 |
| 叶脉 ↔ 榫口 | 共事伙伴 | +55 | 种植空间与建筑空间互相让位 | 把废平台改成可持续种植区 |
| 叶脉 ↔ 灯芯 | 记忆传承 | +35 | 种子来源的真相是否公开 | 旧种子名册 |
| 回声 ↔ 灯芯 | 隐瞒与追问 | -20 | 档案中有一段被刻意删去的记录 | 灯火档案公开日 |
| 榫口 ↔ 灯芯 | 师徒 | +75 | 是否把旧规矩交给新居民 | 聚落公共灯火约定 |
| 叶脉 ↔ 花序 | 种植伙伴 | +60 | 花材是否应优先留给居民 | 花色温室 |
| 花序 ↔ 货架 | 店铺伙伴 | +45 | 鲜花与日用品的货架空间 | 开店第一天 |

关系边不是失败条件。关系事件满足条件后，选择可以改变 `edge_delta`，但统一限制为：

```text
edge_effective = clamp(edge_base + edge_delta, -100, 100)
```

关系图查询必须返回副本。UI 只能展示节点、边、类型、已知程度和剧情提示，不得直接改边值。

## 5. 关系、对白与剧情规则

### 5.1 玩家与 NPC 的关系值

每名 NPC 有独立 `affinity`，范围 `0..1000`，显示心级由下式得到：

```text
hearts = floor(clamp(affinity, 0, 1000) / 100)
```

首轮基准：

| 行为 | 关系变化 | 限制 |
|---|---:|---|
| 当天首次正常交谈 | +16 | 每名 NPC 每个游戏日一次 |
| 完成 NPC 请求 | +40 | 由请求结果事件结算，NPC 不写任务/背包 |
| 喜爱礼物 | +40 | 每周最多 2 次，生日额外允许 1 次 |
| 喜欢礼物 | +24 | 同上 |
| 普通礼物 | +8 | 同上 |
| 不喜欢礼物 | -12 | 不低于 0，不阻断核心玩法 |
| 厌恶礼物 | -24 | 不低于 0，不阻断核心玩法 |
| 生日倍率 | ×3 | 只作用于礼物基础变化 |

礼物变化公式：

```text
gift_delta = clamp(base_taste_delta × occasion_multiplier × quality_multiplier, -80, 120)
```

实际 `NpcService.give_gift` 先 `roundi(base × occasion × quality)` 再 clamp 至 `[-80,120]`，最后 affinity clamp 至 `0..1000`；返回的实际 delta 可以因好感边界小于计算值。`occasion_multiplier` 普通日 `1`、生日 `3`，品质 `normal/silver/gold=1.00/1.10/1.20`。关系不自然衰减，负向选择只影响可选内容。

日历以 `npcs.json.calendar` 与 `NpcService._gift_allowance` 为准：游戏日从1开始，`week=str(int((day-1)/7))`，星期为 `(day-1)%7+1`，生日年内日为 `(day-1)%112+1`。每周2次普通额度；生日优先使用当日独立1次额度，不占普通次数，之后仍可用当周剩余普通额度，生日当天成功礼物均乘3。`last_gift_day` 拒绝倒退日期；`birthday_gift_day` 防止重复生日专用额度。112日 NPC 周年规则不是 HUD 365日显示日历，不借改 NPC 改玩家时间/存档。

### 5.2 剧情节点

- 个人事件默认在 `affinity >= 200 / 500 / 800` 分别解锁初识、转折、收束。
- 关系事件需要两名相关 NPC 均已相识，并满足对应边强度或前置选择；不能只靠某一个 NPC 的高好感强行跳过另一人的故事。
- 对话分支必须在事件提交后才写入选择结果。重复打开已完成事件只进入回看，不重复发放奖励、不重复改关系。
- 选择结果只能改变对白、关系边或请求内容；不得删除农田、扣除未确认物品、阻止睡觉、建造或存档。

### 5.3 对话会话状态机

```text
CLOSED
  -> OPENING
  -> TYPING
  -> WAIT_INPUT / WAIT_CHOICE
  -> COMMIT_CHOICE
  -> NEXT_PAGE 或 CLOSING
  -> CLOSED
```

实际 `npc_dialogue_runner.gd` 是模块内部状态机；`npc_panel.gd` 展示，`npc_session.gd` 只持有页签/确认/反馈意图，不复用开场 `CharacterDialogue` 或旧 HUD 对话。打字中再次确认只补全当前行，再确认才推进；用 `session_id` 和 NPC 戳拒绝过期按钮。当前独立面板打开即为模态（包括日常对白），世界停止 NPC 移动，暂停只允许取消；旧“单句日常不锁世界”为历史目标，不作为当前事实。关闭、读档、场景销毁、交互失效须清会话；距离失效及睡眠/室内/标题输入盾按当前天台集成实测证据签署，不能因源码存在即认定通过。

## 6. 日程与世界表现

日程是数据，不写在场景脚本分支里。`ScheduleResolver` 读取 `WorldClock` 的只读快照、天气快照、关系阈值、剧情标记和世界区块可用性，按优先级选择当天路线：

```text
特殊剧情 > 节日/天气 > 关系阈值 > 星期/季节 > 默认日程
```

每名 NPC 首轮至少有 3 个日程段：

- 06:00–10:00：起床/准备；
- 10:00–17:00：职业活动点；
- 17:00–21:30：公共生活点或回家；
- 21:30 后：回家并进入休息表现（可选扩展段）。

规则层只产生目标锚点/动作意图；`NpcWorldPresenter` 经 `npc_world_ports.gd` 消费公开世界站位 `anchor_snapshot()`，当前由 `npc_rooftop_anchors.gd` 读取既有rooftop_ranch的NpcStations35局部Marker，从GroundSpace/WalkArea的 `surface_point/path_between` 获取路线，由Character/CharacterMotor执行 `move_ground`，不按插值穿墙、不自己造屋。Marker随用户手摆root实际变换，读档重求路，不恢复临时坐标；旧resident_harbor参考方案仅历史，当前未挂载。

目标缺失/无路时尝试 home anchor 并发可观察 fallback；home 也无路则原地停止，出生/支撑失效则停止并隐藏，不能以瞬移或生成替代地面掩盖失败。world 的暂停/睡眠/室内/对白屏蔽与到达表现必须通过实际 `npc-world` 和真实渲染验证。

## 7. 独立模块契约

### 7.1 内部职责

| 子职责 | 唯一职责 | 不得做的事 |
|---|---|---|
| `NpcCatalog` | 读取稳定身份、对白、事件、日程、关系边内容 | 不保存运行关系，不访问场景节点 |
| `NpcService` | 拥有七名 NPC 的运行状态、关系、住所归属和事件标记 | 不拥有背包、作物、建筑、商店或时间 |
| `ScheduleResolver` | 按只读世界快照解析日程 | 不直接移动 CharacterBody3D |
| `DialogueRunner` | 推进一段对话和选择提交 | 不在展示层结算物品 |
| `NpcRelationshipGraph` | 查询/修改玩家关系与 NPC-NPC 边变化 | 不让 UI 直接写字典 |
| `NpcSaveCodec` | 校验、编码、迁移 `npc` 快照 | 不创建默认空档覆盖原存档 |
| `NpcActor` / `NpcAccessories` | 程序化复用 Avatar/Character/骨骼动作，装配七件职业配件 | 不读取或提交玩家 AvatarProfile，不改玩家实例 |
| `NpcPanel` / `NpcSession` | 独立展示与瞬态输入会话，调用服务命令 | 不拥有 durable 关系/物品/业务状态 |
| `NpcWorldPresenter` / `NpcWorldPorts` | 消费公开世界站位锚点（当前天台草地）、查询时间与屏蔽状态，驱动物理移动 | 不创建房屋/地面，不复制导航或库存规则 |

### 7.2 对外命令、查询、事件

| 类别 | 端口 | 说明 |
|---|---|---|
| 命令 | `meet(npc_id)` | 登记已相识；幂等 |
| 命令 | `start_dialogue(npc_id, context)` | 请求一段可用日常/剧情对白 |
| 命令 | `choose_dialogue(dialogue_id, choice_id)` | 只在当前会话有效，提交幂等 |
| 命令 | `give_gift(npc_id, item_id, quality)` | 只校验 NPC 喜好与次数，消费由 Inventory 端口执行 |
| 命令 | `acknowledge_request(request_id, result)` | 接收 SEA-QUEST/其他模块的结果，不拥有奖励写入 |
| 查询 | `npc_snapshot(npc_id)` | 返回身份、当前表现标签、相识状态和关系心级副本 |
| 查询 | `dialogue_state()` | 返回当前页面、选项、是否锁输入 |
| 查询 | `relationship_graph(viewer)` | 返回可见节点、边和提示，不泄露未解锁秘密 |
| 查询 | `schedule_at(npc_id, world_snapshot)` | 返回目标锚点与动作意图 |
| 事件 | `npc_met` / `dialogue_completed` | 供 UI、目标和剧情记录消费 |
| 事件 | `affinity_changed` / `relation_edge_changed` | 只携带 delta 与原因，不携带可写状态引用 |
| 事件 | `npc_request_opened` | 交给 SEA-QUEST/SEA-ORDER 生成可执行请求 |
| 事件 | `npc_schedule_fallback` | 目标点不可达时的可观察降级 |

### 7.3 交接原则

- SEA-TIME 只提供时间查询；NPC 不推进时间。
- SEA-MOVE / SEA-WORLD 只接收 NPC 的移动意图；NPC 不写导航、WalkArea 或场景变换。
- SEA-FARM、SEA-BUILD、SEA-SALVAGE 等通过公开结果事件接入；NPC 不读取对方私有字段。
- Inventory 是物品数量的唯一写入者。送礼先预检、后由 Inventory 执行扣除，成功事件回到 NPC 结算关系。
- SEA-UI 只负责展示和输入转发；不保存关系值、事件标记或日程副本。
- SEA-SHOP 只接收 `vendor_requested(npc_id, shop_id)`；NPC 不读取商品目录、价格、库存或购买结果的内部字段。
- 其余五人由 Session 发 `action_requested(npc_id, action_id)`：牵线=`ship`，叶脉=`cultivation`，回声=`salvage`，榫口=`building`，灯芯=`archive`。Main 只路由到外部公开功能口，职业按钮不是业务已经实现的证明；缺接收方须明确提示/禁用，不伪造结算。
- 主线程注入对象命名方法：`configure(clock_query, exchange, remove, count, result_port)`；规则当前拒绝捕获闭包，端口以弱引用管理。礼物/请求成功扣除才结算，`acknowledge_request` 校验 `result_tag` 后仍交付库存，不能接受伪造成功结果。Main 接线及 Inventory 原子 exchange 由主线程负责，本分支不改代码。
- 前置依赖遵循 GDD：19:40移除SEA-RESIDENCE，保留AVATAR及既有其他依赖；世界站位端口当前接rooftop_ranch草地，后续可插住所，不强制加载住所资源。UI/SAVE为装配协议，不再加前置边。旧RESIDENCE/AVATAR输入要求保留为历史，住所和商店都不得反向硬依赖NPC。

## 8. 存档契约

运行存档顶层键固定为 `npc`，`npc.version=1`。静态 roster、对白、日程和关系基础边来自内容表，不写入每份存档。动态快照至少包含：

```text
npc {
  version: 1,
  graph: {
    met: {npc_id: bool}, affinity: {npc_id: int},
    last_talk_day: {npc_id: int},
    gift_week: {npc_id: string}, gift_count: {npc_id: int},
    birthday_gift_day: {npc_id: int}, last_gift_day: {npc_id: int},
    edge_deltas: {edge_id: int}
  },
  seen_events: {event_id: {day: int, choices: {page_id: choice_id}}},
  choice_flags: {"event_id:page_id": choice_id},
  request_states: {request_id: {status, source_event, opened_day, completed_day?, result_tag?}}
}
```

以上为实际 `NpcSaveCodec.empty_snapshot/validate` 结构，不使用旧版扁平 graph 或 `seen_events` 数组草案。日期为 `-1` 哨兵或正整数（不接受0），周计数0..2；根字段、graph字段及七人/九边 ID 集合必须精确，未知/缺字段拒绝，数值只接受有限整数值。选择必须构成已到达剧情路径，前置事件/请求与日期一致，choice_flags/edge_deltas 须能由事件重建，请求来源与完成标签须匹配内容表；不能只验数值范围。

当前对话页面、打字进度、待提交分支、移动路径和临时目标不存档；`to_dict()` 取消未提交会话，`from_dict()` 先严格校验再替换，失败不改现场。缺失 `npc` 只允许在明确旧档 migration 中调用默认快照（codec 的 `migrate(null)` 仅供迁移），已有但损坏/未来版本不得当新档补空。主线程须对齐 SaveSchema/SaveGame/Registry 的实际版本与严格 codec，并在全部恢复完成后刷新世界表现；这些接线现已由当前天台save/integration/restart实际通过，证据见最终签署；不再只按源码存在推定。玩家 `profile` 不被读取、提交、重置或复制到 NPC durable 存档；商店静态目录和住所静态 TSCN 不进入 `npc`。

## 9. 设计条款与验收标准

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-RESIDENT-R01 | NPC 是独立模块，拥有七名固定 NPC 的身份、日程、对话、剧情、玩家关系、住所归属与 NPC-NPC 关系图；不把规则散落到 Main/HUD/Farm/Building/Shop。 |
| SEA-RESIDENT-R02 | 对话会话支持多页、选择、剧情节点、回看和幂等提交；剧情选择不引入失败状态，不直接写入其他模块。 |
| SEA-RESIDENT-R03 | 日程由时间/天气/关系/剧情条件数据驱动，目标不可达时可观察降级到 home anchor，不阻断游戏。 |
| SEA-RESIDENT-R04 | 玩家关系按公式结算，交谈/请求/礼物限制可验证；NPC-NPC 关系边的变化可追溯且不能被 UI 直接篡改。 |
| SEA-RESIDENT-R05 | Farm、Building、Ship、Quest、Shop 等关联通过端口和事件完成，NPC 不复制或夺取它们的状态所有权；商店功能仍由 SEA-SHOP 独立维护。 |
| SEA-RESIDENT-R06 | `npc` 存档快照版本化，正常、重复、取消、坏数据、旧档迁移和跨进程恢复均有独立验证入口。 |
| SEA-RESIDENT-R07 | 七名 NPC 的首批内容预算可落地：21 个个人剧情事件、4 个关系事件、84 个对白槽位、7 个住所 ID，并保留内容缺失 fallback。 |
| SEA-RESIDENT-R08 | 七角色程序化复用 Avatar/Character/骨骼及原动作系统，各有独特配件和可区分外观；不触碰玩家 profile，真实渲染与动作另验。 |
| SEA-RESIDENT-R09 | world 通过公开世界站位端口消费稳定锚点和 GroundSpace，当前草地，后续可插住所；NpcWorldPresenter / NpcWorldPorts与CharacterMotor执行路线的owner不变，不生成房屋或硬编码世界坐标，失效可观察停止/降级。旧“仅消费SEA-RESIDENCE”属19:40前历史。 |
| SEA-RESIDENT-R10 | 五人职业 action_requested 与两人 vendor_requested 分离挂载外部功能；NPC 不拥有外部业务和奖励，不将按钮存在视为全链路完成。 |
| SEA-RESIDENT-R11 | 独立 Panel/Session 和主线程装配完成模态、取消、暂停、恢复及真实交互链路；结构/运行/视觉/设备/未验分开留证，不虚报通过数。 |
| SEA-RESIDENT-R12 | 生日112日/周7日/额度优先级及严格 durable npc.version=1 与实际 rules 一致；旧无 npc 仅明确 migration，坏档和过期会话不改现场。 |
| SEA-RESIDENT-R13 | 七人正式现场为rooftop_ranch天台草地，尊重用户手摆root，NpcStations含7×5=35局部Marker并随scene/root变换；公开世界站位端口无住所前置，七人无物理房屋且UI仅写“暂驻天台”。保留七人身份/配件/剧情/职业与独立Shop；主线程移除Main的resident_harbor实例及zone binding但保留源资源，天台世界路线、交互、两店、save/integration及真实渲染须独立验收，历史住所版PASS不得替代。 |

## 10. 实现与待完成边界（22:39前七人全天台阶段历史）

当前规则、Panel/Session、world端口、七角色/配件与Main装配均已实现并实际运行验证。最终shop259/0与天台五项2277/0均exit0/PASS；七人实际草地站位、真实航行/步行/职业交互、严格存档/重启和profile隔离已验。状态implemented（已实现待完整产品验收），不是仅源码存在，也不是verified；住房仍partial/deferred，不纳入本轮完成。

### 主线程回填占位

规则/world/appearance/五职业及真实天台integration/save/restart/visual证据已收齐，完整命令/工作树快照/退出码见[最终签署](../../development/2026-11-07_npc_performance_fix.md#8-最终天台运行签署与14图清单)。剩余仅完整产品验收：R02/R07全剧情人工体验，R08/R11/R13其余11图目检，R11/R14设备/发行包/持续性能，以及主线程另签全局门禁；不再写当前链路待接线。

现有规则继续运行。NPC 文档和目录归位不代表行为已经接入、资产已经生产或存档已经迁移；阶段事实以本功能账本为准。

## 来源与交付记录

- [NPC 模块施工文档](../../development/2026-11-07_npc_module_framework.md)
- [商店功能设计](../shop/spec.md)
- [商店功能账本](../shop/ledger.md)
- [模块与数据接口约定](../../architecture/module_contracts.md)
- [拆分前完整主文档](../../archive/pre_split_20261023/GDD_V1.0.md)
- [本次工程拆分记录](../../development/2026-10-23_feature_split.md)

## 2026-11-07 性能优先收尾（历史：七人全天台，覆盖当时待接线表述）

7人/七配件、21个人+4关系事件、84日常对白、9关系边、五职业端口、独立NPC与Shop及两店11商品、三花各四stage均已实现并有专项，不再仅描述为静态数量。正式现场为既有rooftop_ranch的NpcStations35局部Marker，无物理住房、UI“暂驻天台”；Main已撤resident_harbor实例和zones/scope绑定但保留source，用户手摆root及其他旧transform未动。住房历史source继续partial/deferred，本轮不恢复住房开发。

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-RESIDENT-R14 | clock.changed仅经Main._on_npc_clock_changed→notify_world更新小字典；Presenter按0.5s检测日/分钟、任意日程from/to、conditions.hour_from/hour_to及21:30边界、天气、关系/剧情、手摆Marker/root和support变化，变化才全量解析；每batch仅1次anchor_snapshot，support cache按active/surface/revision及变换失效，idle不逐physics投影。保留force读档/恢复刷新、失支撑停止/隐藏及fallback语义，不以关泛光、降画质或删NPC换性能。 |

性能与世界等专项已PASS，R14实施细节及主时钟R12证据见[性能修复记录](../../development/2026-11-07_npc_performance_fix.md)。重复npc_sync median 0.008ms是五次含首轮2.458ms的统计，不是每次全量sync成本。211435 shop-rules218/7是已保留的失败历史，213213最终259/0已解决；214439当前天台五项2277/0、exit0/PASS，14PNG已产出，主线程已目检三图、其余11图待审。当前R01–R14运行实现签署通过，状态implemented，不标完整产品verified。最终证据见[施工记录第14节](../../development/2026-11-07_npc_module_framework.md#14-最终天台交付范围签署)。

## 住房历史方案（19:40前，暂停保留）

旧初始活动点依次为水上码头、种植平台/太阳房、绞盘打捞站、建造区/自建平台、太阳房/旧铁道观景点、花店温室、综合商店；旧设计要求七个residence_id映射独立50m²住所、床/桌/灯、住商空间和住所35Marker。现仅保留为历史source/设计，不是七人当前地点或已住屋事实；当前地点全部为第3节天台草地对应职业站点，住房partial/deferred，不恢复开发。

## 最终签署与产品未验（历史：22:39前七人全天台快照）

当前R01–R14实际运行实现已通过既有专项及214439天台交付；shop259/0，天台integration668/0、save618/0、seed408/0、restart202/0、visual381/0合计2277/0，均exit0且unexpected_errors空。14图仅主线程实际目检seven-residents/flower-purchase/story-choice三图：7人原草地、无住房、配件区别、花店5商品/价格/购买、可读剧情2choices和天台暂驻UI已确认。其余11图待审，未设备发行/持续性能/全剧情人工体验；这属于已实现待产品验收，不是当前功能未接入。

## 2026-11-07 22:39 当前覆盖：生活化称呼、人物内容与六天台/一海店

本节覆盖旧修订及上方所有“当前七人全天台/35天台Marker/两经营者同场”的地点结论，原章节与PASS全部保留为历史快照，不重新签署。既有R01–R14保留稳定用途；R09的公开站位、R14的0.5秒增量与单batch查询继续生效，R13旧七人天台实例分配改由R18覆盖。当前为 **partial，本轮运行/视觉/存档均pending**，源码已落不等于新实测通过。

### 人物资料、可见性与话题

`npcs.json`每行新增`profile`九字段：`age_group`（当前七人均为成人）、`age_range`、`personality`、`past`、`arrival_reason`、`short_term_wish`、`secret_or_regret`、`habit`、`catchphrase`。年龄从二十多岁至六十来岁，不把豆豆等昵称当儿童设定；不新增强制gender迁移，不改玩家可自定义Avatar风格、外观ID或`profile`快照。每人六条`social_notes[{npc_id,text}]`，共42条定向相处看法；它们是内容，不是42条持久关系边。

认识页展示称呼、年纪、性格、过去、来由、愿望、习惯和常说的话，不直接展示`secret_or_regret`。未认识对象的相处看法同时隐藏对象名字及全文，显示“还没认识的人 · 等见过面再聊。”，不能只遮名字却留下可反推的正文。九条原关系边只补`summary/history/tension/reconcile`，不增加边、不改base；只有相关双方的`kind=relationship`剧情完成后，才在关系页显示该边`reconcile`。当前四个双人事件对应`edge_route_echo/edge_joint_lamp/edge_seed_flower/edge_flower_shelf`；其余五边即使有编辑用和解文本也不因高好感或无关剧情自动公开，不另造解锁事件。

每人四个主动话题`past/daily/friends/plans`，共28话题，每题两页，共56页；`conversation_topics`只列ID/标题，`start_topic`用`kind=display`推进。开始、读完、取消、重复阅读均不调用`talk/meet`，不加好感，不写`seen_events/choice_flags/request_states`，不发完成业务事件；会话UI刷新不算业务结算。认识页与话题可读不代表秘密字段应公开，也不承诺所有叙事暗示都要等完整剧情才出现。人物实际内容与示例见[人物专文](characters.md)。

### 对白数量与稳定旧档

保留84个daily ID，仍为7人×3时段×4情境；每槽`text`加两条`variants`共3句、合计252句。intro每人3页合计21页，另算，不混入252或56。当前轮换由`day-1 + weather_offset + seen_events.size() + posmod(slot_id.hash(),3)`再模3选择，天气顺序`clear/cloudy/rain/storm`；相同日/天气/剧情状态/槽位重复打开或读档选择一致，不引入随机种子或轮换计数存档。天气或剧情进度变更可使同日换句，不能误签成同日无条件固定。

25旧事件（21个人+4关系）与7请求只改标题、对白、描述为具体日常用语，保留NPC/event/page/choice/edge/request ID、前置条件、effects及数值、costs/result_tag/followup和`npc.version=1`。以稳定ID恢复已相识、好感、礼物次数、已完成剧情与请求；禁止按新显示名重建空档。话题与扩写静态内容不进入durable快照，不改原正常交谈/intro的每日好感规则。

### 场地聚合、动态支撑与性能

六人仍在`World/SeaStructures/rooftop_ranch/NpcStations`，共30个Home/Work/Social/Rest/Door Marker；阿店五Marker在`World/SeaStructures/floating_shop/Objects/NpcStations`、zone=`sea_supply`。浮店是用户已摆好的东南场地，root/transform以用户Main实例为准，本轮不移动建筑、不钉绝对坐标、不新建住所。Home/Rest只是语义站位；UI写“常在”，六人标天台暂驻、阿店标东南海上商店，不把场地写成已建住房。SEA-RESIDENCE继续partial/deferred。

`NpcAnchorHub`聚合`npc_rooftop_anchors`与`npc_site_anchors`的只读`anchor_snapshot/home_labels`，用`canonical_anchor_for_npc(anchor_id,npc)`按归属解释旧共享锚名。Main只向Presenter注入Hub，不写别名/日程规则；NPC不引入Shop价格或交易规则。阿店常规home/work/social及雨天、好友、周末、关系剧情和夜间Rest全在sea_supply：home=`residence_general_store`、work=`anchor_general_store`、social=`residence_general_store_social`。小花备花托船送、阿店本地收货，六人所有日程/剧情条件仍落天台，不跨海造路或瞬移。

浮店站位快照带`position_local/support_frame/support_origin/site_pose/support_revision`及只读ground/ground_space引用。原浮店owner唯一负责heave；Presenter每physics随刚性支撑位移携带阿店、当前目标和在途路径，动态矩形做廉价支撑检查，不给天台六人新增逐physics三角投影。layout比较用局部位置和场地静态姿态，剔除瞬时世界position/support_origin及heave高度；海浪不能触发七人全量sync、寻路或导航rebake。真实root/Marker变动、active/surface/revision失效仍须在0.5秒批次识别，每batch一次Hub快照，保留force读档恢复和失支撑停止/隐藏/fallback；不以删NPC或降画质换性能。

### 新增稳定条款（本轮均partial / pending）

追加前已核实本功能最大编号为R14，无R15–R18占用。

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-RESIDENT-R15 | 七人显示名按当前roster映射，允许三字等生活化称呼；所有稳定ID及npc.version=1不变。旧档关系/礼物/剧情/请求按ID恢复，不重置玩家Avatar或强迁gender。 |
| SEA-RESIDENT-R16 | 七份九字段成人profile、42条social_notes、九旧边四类背景、21页intro和28话题56页完整；认识页不展示secret，未相识看法隐藏name/text，reconcile仅相关双人剧情完成后可见。话题仅display，不加好感/事件或durable字段。 |
| SEA-RESIDENT-R17 | 84个daily ID不变，每槽text+2variants=252句按日/天气/剧情/槽位确定性轮换，无随机持久字段；25事件/7请求仅文案朴素化，稳定ID、条件、effects/costs等数值不变，取消/回看/旧档不重复结算。 |
| SEA-RESIDENT-R18 | 当前6roof/1sea，天台30+浮店5 Marker由Hub聚合；阿店home/work/social及所有条件日程留sea_supply，其他六人不跨海。每physics support_frame携带、heave不进layout签名、不rebake或触发七人全量sync；手摆/失效/force仍正确，保持R14增量与单快照。 |

### 本轮待主线程回填

`npc-people`、`npc-profile-ui`、`npc-shop-site`、`npc-relocation`、`visual-npc-people`与rules/performance/save回归全部pending；实际注册名称、命令、工作树快照、退出码、计数、日志/截图和未验项由主线程写[开发记录第6节](../../development/2026-11-07_npc_names_and_shop.md#6-主线程实测回填)及[账本末节](ledger.md#2026-11-07-2239-当前覆盖与新增条款承接)。本分支只读核对与文档定点编辑，不执行global sync、hash、Godot或runner，旧5324/0、241PNG和59.943FPS不能作为本轮迁址/人物通过证据。

## 2026-11-08 继续执行后本轮运行签署

本轮两功能均为 **implemented（已实现）**，不是 **verified**。R15–R18继续保持原稳定用途；本轮实际已注册并运行的新入口为`npc-people`、`npc-profile-ui`、`npc-shop-site`、`npc-relocation`、`visual-npc-people`。正式`shops.json`经营者显示标签为“小花花店/阿店海上商店”，`residences`标签同步，仅改display label；11个商品及`flower_ribbon`/“花序缎带”未改。六人仍在天台30个Marker，阿店仍在东南`sea_supply`浮店5个Marker；建筑手摆root未动，住所继续partial/deferred。

最终13专项报告为：`npc-shop`18/0、`npc-people`3054/0、`npc-profile-ui`1393/0、`npc-shop-site`335/0、`npc-rules`655/0、`shop-rules`259/0、`npc-world`126/0、`npc-performance`61/0、`npc-clock`303/0、`npc-appearance`2469/0、`flower-crops`1233/0、`npc-careers`71/0、`sleep-cycle`42/0，报告目录为`D:/projects/sea-work/verification/20261108-041703-npc-final-regression-799f0f/report.json`。`npc-people`更严字段/数值最终复跑为`D:/projects/sea-work/verification/20261108-042106-npc-people-strict-final-0d9095/report.json`的3054/0，该结果覆盖前一项，不重复累加。正式交付报告`D:/projects/sea-work/verification/20261108-035812-npc-people-delivery-599f67/report.json`另含`npc-relocation`898/0、`npc-integration`695/0、`npc-save`615/0、`npc-save-seed`405/0、`npc-save-restart`197/0、`visual-npc-people`348/0及28张PNG。按19个独立入口合计13177/0，均exit0且`unexpected_errors=[]`。

设备为Godot 4.6.3、VulkanForward+、RTX4060Ti；截图记录为1920窗口，实际PNG像素以文件为准，不从窗口尺寸推断。21张人物front/identity/background由独立代理逐图查看，7张场景业务图由主线程逐图打开；长文底部属于可滚动视口的正常剪裁，未推断隐藏行。28张图均已审阅不等于所有剧情、动作及滚动以下内容均完成人工验收。低端设备、发行包、完整剧情体验、资产权属及用户美术验收仍pending；本轮未测长期FPS，不继承59.943。

旧FAIL历史保留：JSON数值float与literal int dict严格比较误报（改为逐字段数值相等并保留精确字段数）、旧名字断言、Panel常量遮蔽native、话题局部ID误判全局唯一、UI键盘同帧/未释放；仅修测试与runner，未改变事件数值。runner补齐五个入口，独立套件移除autoload，集成使用`--nosave`，并修复terrain重复copy/mount缺陷。全局门禁当前sync32/check35问题可能随并行变化，不锁定最终数字；hash/source drift未批量重签。architecture25服务0、placed3结构0警告、gitdiffcheck通过，但不宣称全工程门禁通过。

本轮验收页为`D:/projects/sea-work/outputs/npc_names_shop_acceptance.html`及同名JSON；开发记录`../development/2026-11-07_npc_names_and_shop.md`由主线程追加第8节。`npc.version=1`未变，固定旧v1数据、严格坏档及跨进程验证；历史工程assets为symlink（同文件），不能作为冻结内容快照比对证据。
