# SEA-DIVE · 潜水探索与宝箱 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-dive) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-DIVE",
  "status": "partial",
  "owner": "UnderwaterWorld / DiveAir / 阶段状态机",
  "code_paths": [
    "godot/src/diving",
    "godot/scenes/underwater"
  ],
  "verification": [
    "selftest",
    "modules",
    "framework-integration",
    "decorations",
    "visual-decorations"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-DIVE-R01 | DiveAir纯模块与自检通过；真实深度画面另计 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-DIVE-R02 | 搜索独立动作，奖励通过give_resource；selftest通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-DIVE-R03 | 快照由模块全量恢复，读档稳定海面；存档与自检通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-DIVE-R04 | 已实现并专项核验 | [框架交付记录](../../development/2026-10-27_modular_framework.md)；[模块接口约定](../../architecture/module_contracts.md) |
| SEA-DIVE-R05 | 已接入；逻辑与组件检查通过 | 7群各18条鱼独立组件；自主更新关闭，潜水时钟sample驱动；见本轮记录 |

## 资源与调用入口

- [godot/src/diving](../../../godot/src/diving)
- [godot/scenes/underwater](../../../godot/scenes/underwater)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

dive / surface / swim_to / cancel_navigation / to_dict / from_dict；phase_machine；exited、air_changed；give_resource 注入。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；兼容字段仅供已有调试工具，不作为新增业务写入口。

## 验证记录

当前入口：`python3 scripts/run_verification.py selftest modules framework-integration`。

2026-10-23 历史实测结果见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 selftest、modules 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

潜水已拆为 surface/enter/swim/exit 状态及7个独立动作；UnderwaterWorld 保留几何与内容装配，奖励回调注入。真实深度、透明渲染和设备性能仍需专项 GPU 验收。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 2026-10-27 模块框架落地

潜水已拆为 surface/enter/swim/exit 状态及7个独立动作；UnderwaterWorld 保留几何与内容装配，奖励回调注入。真实深度、透明渲染和设备性能仍需专项 GPU 验收。

新增条款 SEA-DIVE-R04 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。

2026-10-27 接口收口：公开头灯与诊断入口：toggle_lamp / uses_underwater_environment。

## 2026-10-27 场景组件细分与动物恢复

见[本轮交付与验证记录](../../development/2026-10-27_scene_component_split.md)及[组件分类目录](../../../assets/registry/SCENE_COMPONENTS.md)。运行验证与素材授权分别登记；交互请求端口不代表玩家摆放编辑器已实现。

最终补验：decorations 1589项通过；visual-decorations 1592项通过（包含独立实例、真实鱼群近景和正常上浮环境恢复）。surface 503项/30航线、自检537项通过；静态契约32功能/426源资产/317运行哈希0问题。旧水下网页同机位测试缺基准未执行，单列在本轮记录。
