# SEA-MOVE · 角色移动与上下船 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-move) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-MOVE",
  "status": "partial",
  "owner": "角色 / 行走协调器（当前 Main）",
  "code_paths": [
    "godot/src/player",
    "godot/src/navigation/walk_area.gd",
    "godot/src/navigation/ground_path.gd",
    "godot/src/navigation/landing_point.gd"
  ],
  "verification": [
    "surface",
    "click"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-MOVE-R01 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-MOVE-R02 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-MOVE-R03 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |

## 资源与调用入口

- [godot/src/player](../../../godot/src/player)
- [godot/src/navigation/walk_area.gd](../../../godot/src/navigation/walk_area.gd)
- [godot/src/navigation/ground_path.gd](../../../godot/src/navigation/ground_path.gd)
- [godot/src/navigation/landing_point.gd](../../../godot/src/navigation/landing_point.gd)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

- `godot/src/player/character.gd`：命令/查询 `play_farm_action(_event: String), build(), set_walking(on: bool), set_rowing(on: bool), set_diving(on: bool)`；事件 `无`。
- `godot/src/navigation/walk_area.gd`：命令/查询 `outlines(), path_between(start: Vector3, goal: Vector3), contains_local(x: float, z: float), contains_world(x: float, z: float), pick(origin: Vector3, dir: Vector3), center_world(), clamp_point(x: float, z: float), area_span()`；事件 `无`。
- `godot/src/navigation/ground_path.gd`：命令/查询 `contains(polygons: Array, p: Vector2), clear_segment(polygons: Array, a: Vector2, b: Vector2), route(polygons: Array, start: Vector2, goal: Vector2)`；事件 `无`。
- `godot/src/navigation/landing_point.gd`：命令/查询 `ground(), stand_position(), data()`；事件 `无`。

## 验证记录

入口：`python3 scripts/run_verification.py surface click`。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 surface、click 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

行走状态仍在 Main，后续可单独抽取控制器；本轮保持运行行为。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。
