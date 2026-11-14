# SEA-FACILITY · 设施解锁与生产 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-facility) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-FACILITY",
  "status": "partial",
  "owner": "FacilityService",
  "code_paths": [
    "godot/src/facilities/facility_service.gd"
  ],
  "verification": [
    "management",
    "selftest",
    "framework-modules"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-FACILITY-R01 | 独立服务成本/前置校验，management 与模块测试 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-FACILITY-R02 | 温室等已有规则由原经营/种植专项覆盖；完整设施内容仍按原计划 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-FACILITY-R03 | facility_unlocked 查询注入消费者；仓库解锁恢复专项通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-FACILITY-R04 | 已实现并专项核验 | [框架交付记录](../../development/2026-10-27_modular_framework.md)；[模块接口约定](../../architecture/module_contracts.md) |

## 资源与调用入口

- [godot/src/facilities/facility_service.gd](../../../godot/src/facilities/facility_service.gd)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

configure / build_facility / facility_unlocked / to_dict / from_dict；sites_changed；facilities 字段。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；兼容字段仅供已有调试工具，不作为新增业务写入口。

## 验证记录

当前入口：`python3 scripts/run_verification.py management selftest framework-modules`。

2026-10-23 历史实测结果见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 management、selftest 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

设施由独立 FacilityService 拥有，温室/仓库等消费者通过 facility_unlocked 查询。后续设施内容依原设计单独补齐。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 2026-10-27 模块框架落地

设施由独立 FacilityService 拥有，温室/仓库等消费者通过 facility_unlocked 查询。后续设施内容依原设计单独补齐。

新增条款 SEA-FACILITY-R04 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。

## 2026-11-14 B2 设施支付窗口承接

承接SEA-FACILITY-R01/R03/R04（S15/S16）：build_facility在owner busy中调用原construction_pay，再提交facilities并发布sites_changed；重复/不足仍不重复扣料。WarehouseService负责合并库存原子支付，Economy.is_busy聚合设施busy进入Registry门禁，不新增设施价格/前置或第二份状态。

相关modules101/0、framework-modules52/0及统一事务专项103/0 PASS/exit0仅签实际覆盖链路，不冒称所有设施内容/全owner极值均已验收。登记头partial保持，legacy management36/1旧完整范围夹具及视觉/最终门禁分列于[B2主记录](../../development/2026-11-13_engine_deep_audit.md#b2-业务事务与空间修复最终回填2026-11-14)。

### B2 最终状态（2026-11-14）· [主记录](../../development/2026-11-13_engine_deep_audit.md#b2-最后复测与签署范围2026-11-14)
- 005436 transactions103/0、005741 framework52/0均PASS/exit0；012647 management按当前安装内容明确zone3退役后37/0、exit0，不恢复生产内容，旧36/1保留。
- 仅签已覆盖设施支付/状态提交链路，不签所有设施内容或全owner极值；全库契约仍失败，登记头partial保持，视觉边界及冻结证据见主记录。

## 2026-11-14 B3 Goal/设施查询边界承接

设施展示目标通过`GoalService.goal_info`返回成本递归副本，查询结果修改不会污染Facility/Ship/Construction权威支付；`b3-goal-query-copy`、`management`、`framework-integration`均exit0。该项只修展示查询边界，不改变设施规则、成本数值或完整设施内容验收，登记头partial保持。
