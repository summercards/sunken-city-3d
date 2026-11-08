# 2026-11-08 NPC 体系核对：一套实现与三类功能出口

[主文档](../../GDD_V1.0.md#sea-resident) · [居民设计](../features/resident/spec.md) · [居民账本](../features/resident/ledger.md)

本轮是**只读核对 + 文档承接**，没有改任何代码、没有运行验证。目的是把「七个 NPC 是不是一套体系、差异在哪里」这个此前只存在对话里的结论写进正式文档，并把它变成可校验的条款。

## 1. 结论

七个居民共用同一套实现，差异只落在**功能出口**上，分三档。

| 层 | 文件 | 行数 | 是否按 npc_id 分支 |
|---|---|---:|---|
| 数据 | `npcs.json` + `npc_catalog.gd` | 360 | 否，七行同构 |
| 状态 | `npc_service.gd` | 486 | 否 |
| 流程 | `npc_session.gd` + `npc_dialogue_runner.gd` | 293 | **是**（FUNCTIONS 表与五人问候语） |
| 呈现 | `npc_panel.gd`、`npc_actor.gd`、`npc_accessories.gd` | 795 | 否 |
| 世界 | `npc_world_presenter.gd`、`anchor_hub`、`site_anchors`、`schedule_resolver` | 671 | 否 |
| 存档 | `npc_save_codec.gd` | 148 | 否 |

`godot/src/npc/` 合计 19 个文件 3280 行，七人全部走同一条链。

## 2. 出口三档

| 档 | 判定 | 出口 | 成员 |
|---|---|---|---|
| 经营型 | `npcs.json` 有 `shop_id` | `vendor` → 独立 `ShopPanel` | 小花 `shop_flower`、阿店 `shop_general` |
| 职能型 | 无 `shop_id`，命中职能映射 | `function` → `NpcCareerPanel` | 船老大 `ship`、豆豆 `cultivation`、阿海 `salvage`、木头叔 `building`、灯伯 `archive` |
| 无功能 | 两者皆无 | 只剩聊聊 / 退出 | 当前无 |

职能型不复制外部业务规则：船升级归 SEA-SHIP、种植归 SEA-FARM/CROP、打捞归 SEA-SALVAGE、建造归 SEA-BUILDING，档案只读 SEA-RESIDENT 自己的事件。

## 3. 发现的不一致（已登记为 pending）

同样叫「功能出口」，两档的实现方式差一个量级。

- **商店型是单点**：`npcs.json` 加一行 `shop_id` 即可，代码里没有第二处 npc→shop 映射。
- **职能型是五处硬编码**：

| 位置 | 内容 |
|---|---|
| `godot/src/npc/npc_session.gd:6-12` | `FUNCTIONS` 表：npc_id → [action, 中文标签] |
| `godot/src/npc/npc_session.gd:98-100` | 五人各自的问候语 |
| `godot/src/bootstrap/main.gd:3819` | `expected`：反向校验 npc→action |
| `godot/src/bootstrap/main.gd:3826` | `ids`：action→npc 查表 |
| `godot/src/bootstrap/main.gd:3875` | 硬编码 `"npc_bai_shi"` 打开档案 |

后果是具体的：**加第 8 个职能 NPC 要同步改 5 处；漏改 `main.gd:3819` 的 `expected`，`_on_npc_career_requested` 会静默 `return`，按钮点了没反应、不报错、不留日志。** 而加第 8 个商店 NPC 只改 1 行数据。

`npcs.json` 已经是七人的唯一真源，但 `function` 这条还留着第二份真源，违反 AGENTS.md 第 6 条「状态只有一个写入者」。

## 4. 条款

| 条款 | 状态 | 说明 |
|---|---|---|
| SEA-RESIDENT-R22 | implemented | 七人共用一套会话/呈现/世界/存档；共用层不得按 npc_id 分支业务，差异只能落在出口三档 |
| SEA-RESIDENT-R23 | **pending** | 出口必须来自 `npcs.json` 单一真源；`function` 五处硬编码尚未收口 |

R22 的 implemented 依据是源码只读核对（共用层除 FUNCTIONS 与问候语表外无 npc_id 业务分支），**不是本轮运行证据**；运行证据沿用既有 `npc-rules`、`npc-world`、`npc-careers`、`npc-integration`、`npc-save`、`npc-conversation`、`visual-npc-conversation` 的通过结果，本轮未重跑，不据此签发新的绿项。

R23 故意标 pending 而不是顺手改成 implemented：收口属重构，要动 `npc_session.gd` 与 `main.gd` 接线，并重跑 `npc-rules`/`npc-careers`/`npc-integration`/`npc-save` 四个入口。本轮没做，就不签。

## 5. 未执行

- 未改代码、未加断言、未运行 Godot。
- 未跑 `check_feature_contracts.py`（本轮只动文档，且该检查的失败面是既有哈希漂移，与本节无关）。
- R23 收口后的验证入口与预计改动量见账本对应行，留待实际动手那一轮填。

## 6. 账本归属

NPC 的独立账本已经是 `docs/features/resident/ledger.md`，登记名 `SEA-RESIDENT`，运行模块名 `NPC`，职责目录 `godot/src/npc/`。三者是同一件事的三种称呼，不是三份东西——`spec.md` 开头那句「功能登记名仍为 SEA-RESIDENT；运行模块名为 NPC，职责目录为 godot/src/npc/」就是这个意思。本节内容按 AGENTS.md 第 2 条只追加在该账本尾部，标题、主文档回链与 `## 登记头` JSON 均在原位未动（已核验：文件仍以 `# SEA-RESIDENT` 开头，登记头可解析，`feature_id=SEA-RESIDENT`、`status=implemented`）。
