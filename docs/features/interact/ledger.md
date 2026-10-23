# SEA-INTERACT · 点击与长按交互 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-interact) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-INTERACT",
  "status": "partial",
  "owner": "Interactor / Interactable",
  "code_paths": [
    "godot/src/interaction"
  ],
  "verification": [
    "click",
    "surface"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-INTERACT-R01 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-INTERACT-R02 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-INTERACT-R03 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |

## 资源与调用入口

- [godot/src/interaction](../../../godot/src/interaction)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

- `godot/src/interaction/interact_prompt.gd`：命令/查询 `celebrate(), update_from(actor: Node), flash_blocked(reason: String)`；事件 `action_requested`。
- `godot/src/interaction/interactor.gd`：命令/查询 `ensure_input_map(), update(delta: float, holding: bool), progress(), debug_focus(spot: Node3D)`；事件 `action_started(spot: Node3D), target_changed(spot: Node3D), progress_changed(ratio: float), completed(spot: Node3D, reward: Dictionary), blocked(reason: String)`。
- `godot/src/interaction/hover_card.gd`：命令/查询 `update_hover(screen: Vector2), clear()`；事件 `无`。
- `godot/src/interaction/click_reticle.gd`：命令/查询 `show_at(point: Vector3, sailing := false)`；事件 `无`。
- `godot/src/interaction/interactable.gd`：命令/查询 `focus_text(), can_interact(), interact(_actor: Node3D), focus_enter(), focus_exit()`；事件 `focus_changed(focused: bool)`。

## 验证记录

入口：`python3 scripts/run_verification.py click surface`。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 click、surface 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

- 2026-10-23 真实事件补充：visual-click 退出 1，第二地格点击目标断言失败；拆分前基线同样失败，完整根因待定位。不得以核心 click 通过覆盖此失败。详见[交付记录](../../development/2026-10-23_feature_split.md)。

## 遗留与下一步

Main 仍负责部分输入路由；公共交互类型不能直接拥有种植或订单规则。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。
