# 2026-11-07 NPC 独立模块框架施工文档

[主文档功能入口](../../GDD_V1.0.md#sea-resident) · [NPC 设计文档](../features/resident/spec.md) · [NPC 账本](../features/resident/ledger.md) · [模块接口约定](../architecture/module_contracts.md)

## 1. 本轮施工目标

本轮只确立 NPC 模块的产品边界、数据边界、施工顺序和验收门禁，不把 NPC 规则塞进 `Main`、`HUD`、`Farm`、`Building`、`Economy` 或现有开场对白脚本。

目标是建立一个可以独立运行、独立测试、独立维护的 NPC 规则域：

- 首批固定 5 名 NPC；
- 有日常对话、剧情对话和分支选择；
- 有 15 个个人剧情事件和 2 个跨 NPC 关系事件的内容预算；
- 有玩家-NPC 好感与 NPC-NPC 关系网；
- 有时间、天气、关系、剧情条件驱动的日程；
- 有版本化 `npc` 存档快照；
- 所有关联通过端口、查询、事件和稳定 ID 完成。

**本轮不创建空运行脚本。** 设计文档和账本建立完成不等于 NPC 已经在游戏中出现。

## 2. 参考结论与本项目取舍

本轮参考了牧场类 NPC 的常见结构：

- Stardew Valley 的好感/心级、每日交谈、每周送礼次数、生日倍率、关系事件和日程条件；
- Stardew Valley 的按季节/星期/好感阈值选择日程；
- Story of Seasons / Harvest Moon 系列的花朵等级、事件解锁、请求与村民群体关系。

参考只用于抽象模块能力，不复制角色、台词、地图、数值或美术。链接已记录在 [NPC 设计文档](../features/resident/spec.md#2-牧场类-npc-参考与本项目取舍)。

本项目采用的取舍：

| 参考能力 | sea 的落地方式 | 不采用的部分 |
|---|---|---|
| 好感心级 | `affinity 0..1000`，每100点显示1心 | 不做每日衰减，不做强制打卡 |
| 送礼 | 每周2次，生日额外1次，按喜好和品质结算 | 不让送错礼物阻断种植/建造 |
| 日程 | 06:00/10:00/17:00/21:30 时间段 + 条件优先级 | 不把真实导航写进 NPC 规则 |
| 心级事件 | 200/500/800 阈值的个人事件 | 首轮不做永久错过 |
| 村民关系 | 7条静态关系边 + 可追溯 delta | 不做强制恋爱、婚姻和儿童 |
| 请求/任务 | NPC 只提出请求、接收结果 | 不复制 SEA-QUEST 或 SEA-INVENTORY 状态 |

## 3. 目标目录与职责冻结

正式代码接入时，目录只允许放在 `godot/src/npc/`；内容表只放在 NPC 自己的内容目录；测试夹具放在统一测试入口允许的测试目录，不让正式代码反向依赖测试目录。

目标结构：

```text
godot/src/npc/
├─ npc_service.gd              # 五名 NPC 的运行状态唯一所有者
├─ npc_catalog.gd              # 静态身份、关系基础、对白、事件、日程内容表
├─ npc_relationship_graph.gd   # 玩家关系与 NPC-NPC 边的命令/查询
├─ schedule_resolver.gd        # 只读世界快照 -> MoveIntent
├─ dialogue_runner.gd          # 多页对白、选择、提交、回看状态机
├─ npc_save_codec.gd           # npc.version=1 的校验、编码、迁移
├─ ports/
│  ├─ npc_world_port.gd        # 世界锚点/天气/时间只读适配
│  ├─ npc_move_port.gd         # 移动意图输出端口
│  ├─ npc_gift_port.gd         # 背包预检/扣除结果端口
│  └─ npc_dialogue_port.gd     # UI 展示与输入意图端口
└─ data/
   ├─ npcs.json                # 五名 NPC 的稳定身份与表现标签
   ├─ npc_relationships.json   # 静态关系边
   ├─ npc_schedules.json       # 日程规则
   ├─ npc_dialogues.json       # 普通对白与情境槽位
   ├─ npc_events.json          # 15+2 个剧情事件
   └─ npc_requests.json        # 可选请求内容
```

本目录冻结为“纯规则 + 数据 + 端口”。NPC 场景表现、肖像、动画和锚点实例后续由装配层接入，不能把场景节点路径硬编码进 `NpcService`。

## 4. 五人首批内容施工表

| NPC | 稳定 ID | 主要内容 | 关联结果事件 |
|---|---|---|---|
| 洛言 | `npc_luo_yan` | 船匠/领航员；旧航线故事；3个个人事件 | SEA-SHIP、SEA-NAV、SEA-BUILD |
| 沐禾 | `npc_mu_he` | 种植者/种子保管人；种子记忆故事；3个个人事件 | SEA-FARM、SEA-CROP、SEA-INVENTORY |
| 纪沉 | `npc_ji_chen` | 打捞者/旧城记录员；旧城航行记录；3个个人事件 | SEA-SALVAGE、SEA-DIVE、SEA-WORLD |
| 南栀 | `npc_nan_zhi` | 木工/屋顶修缮师；家园归属故事；3个个人事件 | SEA-BUILD、SEA-BUILDING、SEA-WORLD |
| 白拾 | `npc_bai_shi` | 灯火守望者/档案管理员；公共记忆故事；3个个人事件 | SEA-QUEST、SEA-TIME、SEA-WORLD |

关系边首批 7 条，内容在设计文档冻结。实现时每条边必须有稳定 `edge_id`，不得用排序下标作为存档 ID。

## 5. 数据契约草案

### 5.1 NPC 身份内容

```json
{
  "id": "npc_luo_yan",
  "display_name": "洛言",
  "role": "boatwright_navigator",
  "home_anchor": "anchor_dock_luo_yan",
  "portrait_id": "portrait_npc_luo_yan",
  "dialogue_tags": ["boat", "route", "repair"],
  "event_ids": ["npc_luo_yan_intro", "npc_luo_yan_turn", "npc_luo_yan_close"]
}
```

### 5.2 日程内容

```json
{
  "npc_id": "npc_luo_yan",
  "rules": [
    {
      "when": {"hour_from": 6, "hour_to": 10},
      "anchor_id": "anchor_home_luo_yan",
      "action": "prepare"
    },
    {
      "when": {"hour_from": 10, "hour_to": 17},
      "anchor_id": "anchor_dock",
      "action": "repair_boat"
    }
  ],
  "fallback_anchor_id": "anchor_home_luo_yan"
}
```

条件优先级固定为：

```text
特殊剧情 > 节日/天气 > 关系阈值 > 星期/季节 > 默认日程
```

解析结果必须是 `MoveIntent`，包含 `npc_id`、`anchor_id`、朝向和动作，不包含路径点、碰撞体或 SceneTree 引用。

### 5.3 对话内容

对白必须有稳定 `dialogue_id`，每页有 `page_id`，选项有 `choice_id`。缺失条件时选择 fallback；不可因为内容表缺一条就生成空对话框。

```json
{
  "dialogue_id": "npc_luo_yan_daily_dock",
  "npc_id": "npc_luo_yan",
  "kind": "daily",
  "conditions": {"met": true, "affinity_min": 0},
  "pages": [
    {
      "page_id": "p1",
      "speaker": "npc_luo_yan",
      "text_key": "npc.luo_yan.daily.dock.001",
      "choices": []
    }
  ],
  "fallback_dialogue_id": "npc_luo_yan_fallback"
}
```

## 6. 施工阶段

### S0：文档与目录契约（本轮）

- [x] 主文档保留 `SEA-RESIDENT` 唯一 FeatureID，并改名为 NPC 居民、对话与关系网。
- [x] 功能设计文档冻结五人 roster、关系网、对话状态机、日程和存档边界。
- [x] 功能账本逐条承接 R01–R07，状态仍为 `planned`。
- [x] 模块接口约定补充 NPC 的所有者、端口和恢复规则。
- [x] 施工文档建立，明确不创建空运行模块。

### S1：纯规则骨架

目标：不加载 `main.tscn`、不依赖 Autoload、不创建 NPC 场景节点。

- 建立 `NpcCatalog` 的内容表解析和稳定 ID 校验；
- 建立 `NpcRelationshipGraph`，实现 affinity/edge delta、clamp、只读副本和幂等命令；
- 建立 `DialogueRunner`，实现多页、打字完成、选择、重复提交、取消和回看；
- 建立 `ScheduleResolver`，实现条件优先级和 home anchor 降级；
- 建立 `NpcSaveCodec`，实现 `npc.version=1` 校验、编码和旧档明确迁移；
- 先以纯规则专项通过，再进入场景接入。

### S2：内容接入

- 填充五名 NPC 的稳定内容表；
- 填充 15 个个人事件、2 个关系事件；
- 填充至少 60 个对白槽位和 fallback；
- 对内容 ID、条件引用、事件前置、关系边引用做完整性检查；
- 不接真实 NPC 模型前，不把 `implemented` 写入账本。

### S3：装配层接入

- 由 Main/Bootstrap 只负责注入服务和连接端口；
- SEA-INTERACT 把交互目标转给 NPC；
- SEA-TIME/SEA-WEATHER 只提供快照；
- SEA-MOVE/SEA-WORLD 消费 `MoveIntent` 并回传到达/不可达结果；
- SEA-UI 展示对话和关系，只发送输入意图；
- Inventory 预检/扣除成功后，NPC 才结算礼物关系；
- SnapshotRegistry 注册 `npc`，恢复完成后才刷新表现。

### S4：正式表现与验收

- NPC 角色模型、肖像、动画和锚点资产另走 SEA-ASSET 登记；
- 验证日程切换、真实行走、不可达 fallback、对话 UI、关系网展示；
- 验证读档、坏档保护、跨进程恢复和重复交互；
- 设备、性能、内容审阅和美术授权分别记录，不用纯规则通过替代真实表现验收。

## 7. 必须写成会失败的断言

以下契约不能只靠注释：

1. **五人固定性**：`npcs.json` 必须恰好包含 5 个唯一 `npc_id`，关系边两端必须存在。
2. **关系边有界**：`edge_effective = clamp(edge_base + edge_delta, -100, 100)`；异常值拒绝，不静默截断存档数据。
3. **好感有界**：`affinity` 必须是整数 `0..1000`；心级必须等于 `floor(affinity / 100)`。
4. **对白完整**：每个事件页至少一个可显示文本键；缺条件走 fallback，不得返回空页。
5. **对话幂等**：同一 `choice_id` 重复提交不得重复改变关系或事件奖励。
6. **日程可降级**：目标锚点不可达时必须发出 `npc_schedule_fallback` 并返回 home anchor。
7. **存档边界**：`npc` 快照不得包含路径、SceneTree 对象、临时打字进度或其他模块私有库存。
8. **查询隔离**：关系图、NPC 快照和对话状态返回深副本，修改副本不能改变服务内部状态。
9. **跨模块写入**：NPC 不得直接调用 `Economy`、`Main`、`HUD`，不得写 Farm/Building/Inventory 的内部字段。

## 8. 预期验证入口

正式实现后新增并登记以下专项名称；在代码落地前不把它们写入账本 `verification`，避免把未存在的 runner 入口当作已通过：

| 专项 | 验证范围 |
|---|---|
| `npc-modules` | 五人目录、关系图、好感公式、幂等和纯规则状态机 |
| `npc-dialogue` | 日常/剧情对白、多页、选择、取消、回看、fallback |
| `npc-schedule` | 时间/天气/关系/剧情优先级、目标切换、不可达降级 |
| `npc-content` | 5人、15+2事件、60槽位、稳定引用和缺内容保护 |
| `npc-save` | v1快照、坏数据不改现场、旧档迁移、跨进程恢复 |
| `npc-integration` | 交互、UI、移动意图、送礼端口、公开结果事件 |
| `visual-npc` | 五人真实表现、对话面板、日程移动和关系网可读性 |

## 9. 当前状态与下一步

当前状态：**规划完成，施工未开始，正式代码 0 条路径。**

下一步应从 S1 开始，先建立纯规则服务与最小内容表，再申请正式场景接入。不要先做五个 NPC 场景节点；没有服务、快照和失败断言，先做模型只会把规则重新散落回场景脚本。

本轮没有修改 `godot/` 正式运行代码、玩家存档、场景摆位、资产登记或 `web/` 原型。
