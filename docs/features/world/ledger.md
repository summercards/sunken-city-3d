# SEA-WORLD · 区块与世界装配 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-world) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-WORLD",
  "status": "partial",
  "owner": "Zones / ZoneScene",
  "code_paths": [
    "godot/src/world",
    "godot/scenes/zones",
    "godot/scenes/world",
    "godot/assets/data/zones.json"
  ],
  "verification": [
    "selftest",
    "surface",
    "visual-sea-style"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-WORLD-R01 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-WORLD-R02 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-WORLD-R03 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-WORLD-R04 | 本轮表现与专项通过 | 环境静态鱼、尾鳍、圆环和点击圆盘退役；漂流物旧透明环退役，桶身金属环保留；源烘焙文件未修改，9 个区块 GLB 仅退役匹配的旧装饰三角索引。 [交付记录](../../development/2026-10-23_sea_visual_style.md) |

## 资源与调用入口

- [godot/src/world](../../../godot/src/world)
- [godot/scenes/zones](../../../godot/scenes/zones)
- [godot/scenes/world](../../../godot/scenes/world)
- [godot/assets/data/zones.json](../../../godot/assets/data/zones.json)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

- `godot/src/world/zones.gd`：命令/查询 `get_zone(id: String), label(id: String), landing(zone_id: String, landing_id: String = "main"), landings_of(zone_id: String), is_unlocked(zone_id: String), footprint(zone_id: String), zone_at(point: Vector3, radius: float = 12.0), bind_scene(zone: Node3D)`；事件 `无`。
- `godot/src/world/bake_store.gd`：命令/查询 `ensure_loaded(), geom(index: int), material(tex: int, tint: bool, unlit: bool, alpha: bool, double_side: bool), line_material(), timed_materials()`；事件 `无`。
- `godot/src/world/zone_scene.gd`：命令/查询 `set_geometry_source(src: String), pick_walk(origin: Vector3, dir: Vector3), area_containing(x: float, z: float), floor_height_at(x: float, z: float), set_zone_level(level: int, instant := false), update_time(t: float), landing_points(), landing_point(id: String)`；事件 `无`。
- `godot/src/world/zone_batch.gd`：命令/查询 `build(), update_time(t: float)`；事件 `无`。

- `ZoneBatch.retired_geometries / retired_alpha_geometries`：场景声明的历史批次退役清单；Environment 及五个区块均设置，以覆盖批次回退路径；默认空。烘焙版本升级时必须重新核验几何 ID。每个批次记录 `source_geometry` 便于检查。

## 验证记录

入口：`python3 scripts/run_verification.py selftest surface`。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 selftest、surface 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

新区域仍需完整的内容配置、边界和到达验证。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

- 2026-10-23 画面优化：环境静态鱼、尾鳍、圆环和点击圆盘退役；漂流物旧透明环退役，桶身金属环保留；源烘焙文件未修改，9 个区块 GLB 仅退役匹配的旧装饰三角索引。 [独立验证与截图记录](../../development/2026-10-23_sea_visual_style.md)。
