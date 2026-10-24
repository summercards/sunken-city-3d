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

- 2026-10-24 体色硬边修复：`swell` / `wave_light` / `facet` 三处阈值带放宽，输出前加 1 LSB 静态抖动（新 uniform `dither_strength`）；解决俯视水面的硬直角色块与 8 bit 色带。同机位 A/B 真实渲染截图对照通过。 [交付记录](../../development/2026-10-24_water_banding_seam.md)。

- 2026-10-24 体色图案根源修复：`broad()` 由值噪声改为梯度噪声（Perlin，quintic fade，逐倍频旋转 36.87° / 73.7°，幅度校准 0.89），消除值噪声等值线的长直边与共轴格边；`web/water.js` 同步梯度噪声、宽阈值与抖动。双后端真实渲染验证通过。 [交付记录](../../development/2026-10-24_water_value_noise_panels.md)。

- 2026-10-24 水面按生产包重做：`water.gdshader` 整体重写为「法线贴图 + 解析天空反射 + 太阳滤波高光 + 深度透射 + 波纹等高线网络」，保留工程自有的波场顶点位移、尾迹、船桨涟漪、岸线与交界泡沫；体色改用垂直水柱以保住掠射角下的沉没城市可读性。新增 `large_waves.png` / `ripple_pattern.png`（均登记为第三方授权待补）。 [交付记录](../../development/2026-10-24_water_rebuild_prod_package.md)。

- 2026-10-24 水面参数进 P 面板：新增 `src/rendering/water_params.gd` 作为可调参数的唯一清单（按着色器 group 分组，范围照抄 `hint_range`），`color_grade_panel.gd` 扩成「滤镜 / 水面」两页，支持即时生效、复位、复制、逐行写回 `water.tres`，值记在 `user://water.cfg`。`foam_color` 原本声明但未接线，本次一并接上；`source_color` 的 vec3 颜色在资源里统一改为 `Color` 存储。CozyUI 新增 `cozy_skip` 豁免。新增 `tools/check_water_params.gd` 静态核对与 `tools/capture_water_panel.gd` 截图工具。 [交付记录](../../development/2026-10-24_water_param_panel.md)。

- 2026-10-24 出厂参数定版 + 收藏预设：手工调好的 25 项参数与节点波幅（`wave_scale` 1.2）成为新出厂值，方向是「浅滩近青白 + 深色混入更慢 + 中频关掉 + 高光收成小亮点 + 整体压暗」；三个压住滑杆端点的范围（`normal_repeat_metres` / `sun_glossiness` / `sun_lobe_gain`）同步放宽。P 面板水面页顶部新增「收藏」下拉：整套存 / 切 / 删，数据在 `user://water_presets.cfg`，首项「出厂」现读资源且不可删；另有内置预设「参考包初版」只记差异项、套用时其余复归出厂。`user://water.cfg` 增加 `water.tres` 的 md5 指纹，出厂值一换旧存档自动作废。`wave_scale` 的出厂值改写在 `water_surface.gd` 的导出默认值上（场景覆盖被编辑器重写丢过一次）。双后端退出 0，预设全链路探针通过。 [交付记录](../../development/2026-10-24_water_presets.md)。

- 2026-10-24 水面光点进面板：建筑附近水面漂动的小白点（`facility-vicinity water glints` 段）原本全是硬编码常量，抽成 `glints` 组 10 个参数（开关 / 颜色 / 强度 / 密度 / 大小 / 速度 / 漂移 / 明灭锐度 / 内外边界）。环带两端改成按半径比例淡入淡出，系数取 `0.95/2.2` 与 `6.2/11.8` 的精确比值，默认值下与改动前逐像素一致。参数总数 50 → 60，`check_water_params.gd` PASS。 [交付记录](../../development/2026-10-24_water_glints_params.md)。

- 2026-10-24 调参工具整体丢失后的恢复与收尾验证：工作区被还原成 HEAD 后，按内容特征从文件历史里恢复 `water.gdshader`（含 `glints` 组）、两页面板 `color_grade_panel.gd`、`water_params.gd`、`water.tres`（68 项）、`cozy_ui.gd` 的祖先链豁免与 `--water` 启动参数；补回内置预设「参考包初版」。顺手修 `scripts/run_verification.py`：Windows 上 `symlink_to` 无权限时不报错而是留空目录，导致隔离工程读不到 `res://assets` 全线假红，改用 junction 并复制兜底。判定 `ocean_sky.tres` / `world_env.tres` 的哈希漂移为 CRLF 行尾幻影，还原行尾而非重算哈希。core 9 项 PASS，双后端无 SHADER ERROR，`check_feature_contracts.py` 只剩 `main.gd:1928` 一条历史遗留。 [交付记录](../../development/2026-10-24_water_restore_verification.md)。
