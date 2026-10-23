# SEA-NAV · 航行与靠泊 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-nav) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-NAV",
  "status": "partial",
  "owner": "Boat / 航行协调器",
  "code_paths": [
    "godot/src/navigation/boat.gd",
    "godot/src/navigation/route_ribbon.gd"
  ],
  "verification": [
    "surface",
    "selftest"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-NAV-R01 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-NAV-R02 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-NAV-R03 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |

## 资源与调用入口

- [godot/src/navigation/boat.gd](../../../godot/src/navigation/boat.gd)
- [godot/src/navigation/route_ribbon.gd](../../../godot/src/navigation/route_ribbon.gd)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

- `godot/src/navigation/boat.gd`：命令/查询 `build(), place_at(pos: Vector3, yaw: float), sail_to(pos: Vector3, yaw: float, zone_id: String, landing_id: String, path: Array = []), remaining_distance(), sail_to_point(pos: Vector3, path: Array = []), starts_sailing(), remaining_route(), wake_uniform(), rowing_state(), cruise_speed()`；事件 `arrived(zone_id: String, landing_id: String), navigation_blocked`。
- `godot/src/navigation/route_ribbon.gd`：命令/查询 `show_route(points: Array, water_y := WATER_Y), clear()`；事件 `无`。

## 验证记录

入口：`python3 scripts/run_verification.py surface selftest`。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 surface、selftest 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

航路求解和调用仍部分在 Main；旧 parity 算法不是正式运行唯一来源。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。
