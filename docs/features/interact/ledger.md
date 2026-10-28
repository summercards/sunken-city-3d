# SEA-INTERACT · 点击与长按交互 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-interact) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-INTERACT",
  "status": "partial",
  "owner": "Interactor / Interactable / ActorController",
  "code_paths": [
    "godot/src/interaction"
  ],
  "verification": [
    "visual-corner-notebook",
    "click",
    "surface",
    "framework-integration",
    "visual-pocket-bubbles",
    "visual-plot-shipping"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-INTERACT-R01 | 现有交互查询与拒绝反馈；click/selftest通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-INTERACT-R02 | cancel清除进度、锁定和自动输入；取消回调集成通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-INTERACT-R03 | 模态阻断auto_hold，精确目标接近；click与集成通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-INTERACT-R04 | 已实现并专项核验 | [框架交付记录](../../development/2026-10-27_modular_framework.md)；[模块接口约定](../../architecture/module_contracts.md) |

## 资源与调用入口

- [godot/src/interaction](../../../godot/src/interaction)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

Interactor.cancel / update；completed、blocked；ActorController.approach / complete_interaction / cancel。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；兼容字段仅供已有调试工具，不作为新增业务写入口。

## 验证记录

当前入口：`python3 scripts/run_verification.py click surface framework-integration`。

2026-10-23 历史实测结果见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 click、surface 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

- 2026-10-23 真实事件补充：visual-click 退出 1，第二地格点击目标断言失败；拆分前基线同样失败，完整根因待定位。不得以核心 click 通过覆盖此失败。详见[交付记录](../../development/2026-10-23_feature_split.md)。

## 遗留与下一步

Main 保留输入路由；接近、自动按住及完成释放由 ActorController 状态管理，交互类型不拥有种植或订单规则。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 2026-10-26 功能与健康审计

SEA-INTERACT-R01/R02/R03：click 30项通过；真实visual-click有5项失败（种植入口、视角面板、保存按钮、第二地格命中、退出打捞），需区分旧UI测试假设与实际输入问题，保持partial。

[本轮审计与证据](../../development/2026-10-26_feature_architecture_save_3c_audit.md)。本轮只审计和登记，未修改玩法实现。

## 2026-10-27 模块框架落地

Main 保留输入路由；接近、自动按住及完成释放由 ActorController 状态管理，交互类型不拥有种植或订单规则。

新增条款 SEA-INTERACT-R04 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。

## 2026-10-28 场景气泡与口袋界面

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-INTERACT-R05 | 已实现；实际渲染与输入专项通过；设备/授权边界单列 | [交付记录](../../development/2026-10-28_pocket_action_bubbles.md) |

本轮运行结果、过程失败、退出码与未执行项集中记在交付记录。旧记录保留为历史，整体状态仍partial。


## 2026-10-28 HUD与笔记表现接线

展开的图标菜单也属于模态阻断，外点收起先消费点击。泊位自身船锚已承担悬停反馈，HoverCard对landing保留target与指针但不显示第二颗手形图标；其它交互物的小操作图标和气泡不变。

对应SEA-UI-R35–R38；[本轮交付](../../development/2026-10-28_corner_hud_notebook.md)。本功能整体状态与玩法边界保留。
