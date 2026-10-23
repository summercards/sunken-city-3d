# SEA-DIVE · 潜水探索与宝箱 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-dive) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-DIVE",
  "status": "partial",
  "owner": "UnderwaterWorld / DiveAir",
  "code_paths": [
    "godot/src/diving",
    "godot/scenes/underwater"
  ],
  "verification": [
    "selftest",
    "modules"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-DIVE-R01 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-DIVE-R02 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-DIVE-R03 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |

## 资源与调用入口

- [godot/src/diving](../../../godot/src/diving)
- [godot/scenes/underwater](../../../godot/scenes/underwater)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

- `godot/src/diving/underwater_region.gd`：命令/查询 `build(), world_bounds()`；事件 `无`。
- `godot/src/diving/uw_materials.gd`：命令/查询 `get_material(slot: Dictionary), set_lamp(on: bool, pos: Vector3, dir: Vector3), set_depth(depth: float), freeze_time(t: float), set_facing_debug(root: Node, on: bool), clear_cache(), from_color(color: Color, options: Dictionary = {}), apply_to_standard_meshes(root: Node)`；事件 `无`。
- `godot/src/diving/underwater_world.gd`：命令/查询 `setup(surface_nodes: Array, world_env: WorldEnvironment), dive(_boat_pos: Vector3, zone_label := ""), surface(), trench_floor_at(x: float, z: float), blocked(p: Vector3, margin := 0.35), cancel_navigation(), swim_to(destination: Vector3), swim_to_screen(screen: Vector2), debug_teleport(p: Vector3), freeze_time(t: float), set_facing_debug(on: bool), region_node(id: String), discovered_count(), to_dict(), from_dict(data: Dictionary), chest_count(), opened_chests(), debug_discover(index: int), region_nodes(), search_state()`；事件 `depth_changed(depth: float), zone_changed(name: String), exited, message(text: String), air_changed(ratio: float, lamp_on: bool, found: int, total: int)`。
- `godot/src/diving/uw_deco.gd`：命令/查询 `setup(fish_specs: Array), hide_kind(kind: String), update(dt: float, t: float, diver: Vector3, cam: Camera3D)`；事件 `无`。
- `godot/src/diving/dive_air.gd`：命令/查询 `reset(), ratio(), drain_rate(depth: float, moving: bool, sprint: bool), seconds_left(depth: float, moving: bool, sprint: bool), update(delta: float, depth: float, moving: bool, sprint: bool), refill(), can_dive(), summary()`；事件 `无`。

## 验证记录

入口：`python3 scripts/run_verification.py selftest modules`。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 selftest、modules 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

海底根仍合并移动、相机和宝箱协调；真实深度与透明渲染需独立 GPU 验收。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。
