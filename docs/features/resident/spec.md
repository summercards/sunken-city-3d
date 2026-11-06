# SEA-RESIDENT · NPC 居民、对话与关系网

[主文档中控](../../../GDD_V1.0.md#sea-resident) · [本功能账本](ledger.md) · [施工文档](../../development/2026-11-07_npc_module_framework.md)

设计修订：r2（2026-11-07，确立独立 NPC 模块框架；未新增运行代码）。所属系统：生活。
功能登记名仍为 `SEA-RESIDENT`；运行模块名为 **NPC**，目标职责目录为 `godot/src/npc/`。这是同一个 FeatureID，不另拆重复的居民/NPC 功能。

## 1. 功能目的与边界

NPC 模块负责五名固定居民的身份、日程、对话剧情、玩家关系、居民之间的关系网和可选请求。它可以在没有 Farm、Building、Order 等业务内部字段的情况下独立运行；跨功能只通过注入端口、公开查询、命令和事件交接。

本模块拥有：

- 五名 NPC 的稳定身份与内容目录；
- NPC 的日程解析、位置意图和生活状态；
- 与玩家的好感、见面、送礼限制、剧情解锁；
- NPC-NPC 关系图、关系变化和关系相关剧情条件；
- 对话队列、分支选择、事件幂等和请求状态；
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

## 3. 五名 NPC 首批 roster

以下 `npc_id` 是稳定 ID；中文名是首批内容名，后续允许改显示名，但不能复用或重命名 ID。

| npc_id | 显示名 | 职能 | 初始活动点 | 角色主线 | 关联模块 |
|---|---|---|---|---|---|
| `npc_luo_yan` | 洛言 | 船匠、领航员 | 水上码头 | 想把断掉的旧航线重新接回聚落 | SEA-SHIP / SEA-NAV / SEA-BUILD |
| `npc_mu_he` | 沐禾 | 种植者、种子保管人 | 种植平台、太阳房 | 让沉没前的种子记忆继续生长 | SEA-FARM / SEA-CROP / SEA-INVENTORY |
| `npc_ji_chen` | 纪沉 | 打捞者、旧城记录员 | 绞盘打捞站 | 找回一段不愿面对的旧城航行记录 | SEA-SALVAGE / SEA-DIVE / SEA-WORLD |
| `npc_nan_zhi` | 南栀 | 木工、屋顶修缮师 | 建造区、自建平台 | 把“临时活下去”变成可以长期生活的家 | SEA-BUILD / SEA-BUILDING / SEA-WORLD |
| `npc_bai_shi` | 白拾 | 灯火守望者、档案管理员 | 太阳房、旧铁道观景点 | 整理居民之间的旧约定，重新点亮公共灯火 | SEA-QUEST / SEA-TIME / SEA-WORLD |

### 首批内容预算

- 5 个个人剧情线，每人 3 个剧情事件：初识、转折、收束，共 **15 个个人事件**。
- 2 个跨人物关系事件：洛言/纪沉的旧航线、南栀/白拾的师徒约定，共 **2 个关系事件**。
- 5 个 NPC × 3 个日程段 × 4 种对白情境（普通日、雨天、夜间、关系阈值）作为首批数据预算，共 **60 个对白槽位**；槽位没有内容时必须走模块 fallback，不显示空框。
- 首轮不做婚姻、配偶、儿童和永久错过剧情；所有剧情可回看，错过当天只改变出现时机，不删除内容。

## 4. 关系网

关系网分为“静态内容关系”和“剧情运行变化”两层。静态关系在 `NpcCatalog` 中，运行变化只写 `edge_deltas`，不改内容表。

| 关系边 | 类型 | 基础强度 | 初始冲突/纽带 | 可触发的公共剧情 |
|---|---|---:|---|---|
| 洛言 ↔ 沐禾 | 旧日同伴 | +65 | 航线优先还是种子优先 | 共同修复第一条生活航线 |
| 洛言 ↔ 纪沉 | 前搭档 | -35 | 一次打捞事故后的信任裂痕 | 找回旧航行记录 |
| 洛言 ↔ 南栀 | 工作伙伴 | +20 | 实用结构与居住舒适的取舍 | 码头与屋顶之间的连接 |
| 沐禾 ↔ 南栀 | 共事伙伴 | +55 | 种植空间与建筑空间互相让位 | 把废平台改成可持续种植区 |
| 沐禾 ↔ 白拾 | 记忆传承 | +35 | 种子来源的真相是否公开 | 旧种子名册 |
| 纪沉 ↔ 白拾 | 隐瞒与追问 | -20 | 档案中有一段被刻意删去的记录 | 灯火档案公开日 |
| 南栀 ↔ 白拾 | 师徒 | +75 | 是否把旧规矩交给新居民 | 聚落公共灯火约定 |

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

其中 `occasion_multiplier` 为普通日 `1`、生日 `3`；品质乘数为普通 `1.00`、银星 `1.10`、金星 `1.20`。关系自然不随时间衰减，避免把五名 NPC 变成每日打卡惩罚；负向选择只影响可选关系内容。

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

`DialogueRunner` 是模块内部状态机。它不复用或改写现有开场/角色对白脚本 `CharacterDialogue`；UI 通过 `DialoguePresenterPort` 注入展示。打字中再次点击只补全当前行，确认后才推进；多页剧情打开输入盾，单句日常对白不锁世界。关闭、读档、离开有效交互距离时都必须清理临时会话。

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

NPC 模块只产生 `MoveIntent(npc_id, anchor_id, facing, action)`；真实路线、WalkArea、碰撞和到达状态由 SEA-MOVE / SEA-WORLD 接管。目标点不可达时使用该 NPC 的 home anchor，并发出 `npc_schedule_fallback`，不能卡死全局流程。

## 7. 独立模块契约

### 7.1 内部职责

| 子职责 | 唯一职责 | 不得做的事 |
|---|---|---|
| `NpcCatalog` | 读取稳定身份、对白、事件、日程、关系边内容 | 不保存运行关系，不访问场景节点 |
| `NpcService` | 拥有五名 NPC 的运行状态、关系和事件标记 | 不拥有背包、作物、建筑或时间 |
| `ScheduleResolver` | 按只读世界快照解析日程 | 不直接移动 CharacterBody3D |
| `DialogueRunner` | 推进一段对话和选择提交 | 不在展示层结算物品 |
| `NpcRelationshipGraph` | 查询/修改玩家关系与 NPC-NPC 边变化 | 不让 UI 直接写字典 |
| `NpcSaveCodec` | 校验、编码、迁移 `npc` 快照 | 不创建默认空档覆盖原存档 |

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

## 8. 存档契约

运行存档顶层键固定为 `npc`，`npc.version=1`。静态 roster、对白、日程和关系基础边来自内容表，不写入每份存档。动态快照至少包含：

```text
npc {
  version,
  met: {npc_id: bool},
  affinity: {npc_id: int},
  last_talk_day: {npc_id: int},
  gift_week: {npc_id: string},
  gift_count: {npc_id: int},
  seen_events: [event_id],
  choice_flags: {choice_id: value},
  edge_deltas: {edge_id: int},
  request_states: {request_id: state}
}
```

当前对话页面、打字进度、移动路径和临时目标不存档；保存/读档发生时会取消会话并回到稳定状态。缺失 `npc` 只允许在明确的旧档迁移中补默认空状态，损坏字段必须拒绝且不覆盖原档。未来版本禁止降级读取。

## 9. 设计条款与验收标准

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-RESIDENT-R01 | NPC 是独立模块，拥有五名固定 NPC 的身份、日程、对话、剧情、玩家关系与 NPC-NPC 关系图；不把规则散落到 Main/HUD/Farm/Building。 |
| SEA-RESIDENT-R02 | 对话会话支持多页、选择、剧情节点、回看和幂等提交；剧情选择不引入失败状态，不直接写入其他模块。 |
| SEA-RESIDENT-R03 | 日程由时间/天气/关系/剧情条件数据驱动，目标不可达时可观察降级到 home anchor，不阻断游戏。 |
| SEA-RESIDENT-R04 | 玩家关系按公式结算，交谈/请求/礼物限制可验证；NPC-NPC 关系边的变化可追溯且不能被 UI 直接篡改。 |
| SEA-RESIDENT-R05 | Farm、Building、Ship、Quest 等关联通过端口和事件完成，NPC 不复制或夺取它们的状态所有权。 |
| SEA-RESIDENT-R06 | `npc` 存档快照版本化，正常、重复、取消、坏数据、旧档迁移和跨进程恢复均有独立验证入口。 |
| SEA-RESIDENT-R07 | 五名 NPC 的首批内容预算可落地：15 个个人剧情事件、2 个关系事件、60 个对白槽位，并保留内容缺失 fallback。 |

## 10. 当前实现与待完成边界

当前只有环境生活表现和历史上的角色开场对白；没有完整 NPC 身份、日程、关系网或五人剧情运行实现。本次只冻结设计、接口、施工顺序和账本承接，不创建空运行模块冒充完成。

现有规则继续运行。NPC 文档和目录归位不代表行为已经接入、资产已经生产或存档已经迁移；阶段事实以本功能账本为准。

## 来源与交付记录

- [NPC 模块施工文档](../../development/2026-11-07_npc_module_framework.md)
- [模块与数据接口约定](../../architecture/module_contracts.md)
- [拆分前完整主文档](../../archive/pre_split_20261023/GDD_V1.0.md)
- [本次工程拆分记录](../../development/2026-10-23_feature_split.md)
