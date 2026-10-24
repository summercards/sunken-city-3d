# SEA-OCEAN · 水面与光照渲染 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-ocean) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-OCEAN",
  "status": "partial",
  "owner": "WaterSurface / ShaderMaterial",
  "code_paths": [
    "godot/src/rendering",
    "godot/shaders",
    "godot/assets/materials"
  ],
  "verification": [
    "ocean",
    "visual-sea-style"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-OCEAN-R01 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-OCEAN-R02 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-OCEAN-R03 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-OCEAN-R04 | 本轮表现与专项通过 | 岸线双环开放波纹弧线与3层动态外扩涟漪、柔和半兰伯特光影与清晰投射阴影标定完成；Metal Forward+ 实机目视验证与 ocean 回归通过。 [交付记录](../../development/2026-10-23_sea_visual_style.md) |
| SEA-OCEAN-R05 | 本轮表现与专项通过 | 交接带改由 `shaders/contact_foam.gdshaderinc` 承担（移植 stylized_water_prod 的 ContactFoam），旧的 `shore_rim`/`shore_foam` 已移除；Forward+ 与 gl_compatibility 双后端实机目视通过，条纹纹理授权待补。 [交付记录](../../development/2026-10-23_water_contact_foam_port.md) |

## 资源与调用入口

- [godot/src/rendering](../../../godot/src/rendering)
- [godot/shaders](../../../godot/shaders)
- [godot/assets/materials](../../../godot/assets/materials)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

- `godot/src/rendering/boat_wake.gd`：命令/查询 `update_wake(t: float, boat: Node3D, surface: MeshInstance3D)`；事件 `无`。
- `godot/src/rendering/color_grade_panel.gd`：命令/查询 `set_open(open: bool), set_values(exposure: float, brightness: float, contrast: float, saturation: float)`；事件 `无`。
- `godot/src/rendering/render_flags.gd`：命令/查询 `reverse_z(), water_emission_gain()`；事件 `无`。
- `godot/src/rendering/shore_distance.gd`：命令/查询 `rebuild(roots: Array, level: float, resolution := RESOLUTION, region := Rect2(), bind(mat: ShaderMaterial), distance_at(p: Vector2)`；事件 `无`。
- `godot/src/rendering/water_surface.gd`：命令/查询 `sample_surface(p: Vector2, at_time: float = -1.0), update_surface(t: float, boat: Node3D, focus: Vector3), emit_ripple(p: Vector2, strength := 1.0), rebuild_shoreline(roots: Array, region := Rect2()`；事件 `无`。

- `godot/shaders/contact_foam.gdshaderinc`：`sample_contact_foam(p: Vector2, d: float, width: float, t: float) -> float`；输入为 `shore_distance` 距离图的米制距离与该实体的尺寸系数，返回 0..1 的交接泡沫覆盖。`contact_foam_pattern` 为空（1×1）时自动退回 `contact_foam_procedural`。艺术参数见 `assets/materials/water.tres` 的 `contact_foam_*`。

## 验证记录

入口：`python3 scripts/run_verification.py ocean`。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 ocean 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

保留拆分前水面修改；跨后端与目标设备仍需专项验证。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

- 2026-10-23 画面优化：替换细碎噪声切边，限制深度边界抗锯齿宽度；Metal Forward+ 实机目视验证与 ocean 回归通过。 [独立验证与截图记录](../../development/2026-10-23_sea_visual_style.md)。

- 2026-10-23 交接泡沫移植：`shore_rim` / `shore_foam` 移除，改由 `shaders/contact_foam.gdshaderinc`（移植 stylized_water_prod 的 ContactFoam）驱动，新增 `foam_line.png` 条带与 `contact_foam_*` 参数；双后端无 SHADER ERROR，visual-sea-style / ocean / selftest 全部退出 0。 [交付记录](../../development/2026-10-23_water_contact_foam_port.md)。
