# SEA-RESIDENT · NPC 居民、对话与关系网 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-resident) · [功能文档](spec.md) · [施工文档](../../development/2026-11-07_npc_module_framework.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-RESIDENT",
  "status": "planned",
  "owner": "规划：NpcService",
  "code_paths": [],
  "verification": []
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-RESIDENT-R01 | 规划待实现；本轮已冻结 NPC 独立职责、五人 roster 与目标目录 | 独立 `godot/src/npc/` 计划路径；正式代码接入前不得以空脚本宣称完成 |
| SEA-RESIDENT-R02 | 规划待实现；已冻结多页对白、选择、剧情节点、回看与幂等提交契约 | `DialogueRunner` 独立专项；覆盖正常、选择、重复打开、取消、读档取消 |
| SEA-RESIDENT-R03 | 规划待实现；已冻结时间/天气/关系/剧情优先级与 home anchor 降级 | `ScheduleResolver` 独立专项；覆盖可达与不可达目标，不依赖真实 NPC 节点 |
| SEA-RESIDENT-R04 | 规划待实现；已冻结玩家关系公式、送礼周限制与 NPC-NPC 关系边模型 | `NpcRelationshipGraph` 独立专项；覆盖幂等、边 delta、边界 clamp 和 UI 只读 |
| SEA-RESIDENT-R05 | 规划待实现；已冻结 SEA-TIME、SEA-MOVE、SEA-WORLD、SEA-FARM、SEA-BUILD、SEA-QUEST 的端口交接 | 架构静态门禁；禁止访问 Main/HUD/Economy 或其他模块私有字段 |
| SEA-RESIDENT-R06 | 规划待实现；已冻结 `npc.version=1` 动态快照、取消瞬态与迁移要求 | 与 SEA-SAVE 联合专项；覆盖坏数据不改现场、旧档迁移、跨进程恢复 |
| SEA-RESIDENT-R07 | 规划待实现；已冻结 5 人、15 个个人事件、2 个关系事件、60 个对白槽位预算 | 内容表完整性专项；缺内容必须 fallback，不得渲染空对话框 |

## 资源与调用入口

- 尚无正式实现；不创建空实现冒充完成。

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是本轮冻结的目标契约，不代表已经有正式实现；实现时必须以此为边界并回填真实代码路径。

- 计划服务：`NpcService`；计划子职责：`NpcCatalog`、`ScheduleResolver`、`DialogueRunner`、`NpcRelationshipGraph`、`NpcSaveCodec`。
- 命令：`meet`、`start_dialogue`、`choose_dialogue`、`give_gift`、`acknowledge_request`。
- 查询：`npc_snapshot`、`dialogue_state`、`relationship_graph`、`schedule_at`。
- 事件：`npc_met`、`dialogue_completed`、`affinity_changed`、`relation_edge_changed`、`npc_request_opened`、`npc_schedule_fallback`。
- 计划存档字段：顶层 `npc`，内部 `version=1`；动态字段见 [功能文档第 8 节](spec.md#8-存档契约)。当前 `code_paths` 仍为空，不对生产工程写入字段。

## 验证记录

入口：尚无专项实现；本轮只完成设计/施工/账本闭环，后续按 [NPC 模块施工文档](../../development/2026-11-07_npc_module_framework.md) 先做无场景纯规则专项，再做正式接入。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 尚无本功能独立运行验收，不将结构通过视为玩法完成。

## 遗留与下一步

当前有环境生活表现和历史角色开场对白，未发现完整 NPC 身份、日程、对话、剧情和关系图运行实现。下一步不是把逻辑塞进 Main 或 HUD，而是建立 `godot/src/npc/` 的纯规则模块与内容表，再经装配层接入。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。
- 2026-11-07：将本功能明确收敛为独立 NPC 模块框架；冻结五名 NPC、关系网、对话剧情、日程端口、存档契约与施工阶段。仍为 `planned`，未创建空实现或修改正式运行代码。
