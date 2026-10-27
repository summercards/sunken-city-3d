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
    "visual-sea-style",
    "lighting-params",
    "lighting-panel"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-OCEAN-R01 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-OCEAN-R02 | 本机双后端实测通过，两套水各自拟合，目标设备未覆盖 | 后端差异集中在 `src/rendering/render_flags.gd`；2026-10-24 按重做后的着色器重测 `water_emission_gain()`，原版开阔水面 Forward+ `1/105/147` 对 gl_compatibility `10/102/146`（误差 4.21，旧系数下为 140.7）。2026-10-25 吸收式水面加入后系数按方案分开，吸收式 `24/185/196` 对 `20/184/194`（误差 2.75，共用 1.26 时为 65.4）。均为真实渲染图像比对，非无头逻辑测试。 [测量记录](../../development/2026-10-24_water_backend_parity.md) / [方案分开](../../development/2026-10-25_water_scheme_gain.md) |
| SEA-OCEAN-R03 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-OCEAN-R04 | 本轮表现与专项通过 | 岸线双环开放波纹弧线与3层动态外扩涟漪、柔和半兰伯特光影与清晰投射阴影标定完成；Metal Forward+ 实机目视验证与 ocean 回归通过。 [交付记录](../../development/2026-10-23_sea_visual_style.md) |
| SEA-OCEAN-R05 | 本轮表现与专项通过 | 交接带改由 `shaders/contact_foam.gdshaderinc` 承担（移植 stylized_water_prod 的 ContactFoam），旧的 `shore_rim`/`shore_foam` 已移除；Forward+ 与 gl_compatibility 双后端实机目视通过，条纹纹理授权待补。 [交付记录](../../development/2026-10-23_water_contact_foam_port.md) |
| SEA-OCEAN-R06 | 本轮实现，Forward+ 真实渲染实测通过 | 新增 `relief` 段（5 项）：`relief_light` 亮部提亮、`relief_shade` 暗部压暗、`relief_gain` 对比、`relief_color` 迎光色、`relief_enabled` 开关。驱动量是**各向异性噪声**（`add_relief`），不是解析波场 —— 用 `wave.x` 或用单条正弦的相位都会在海面产生平行斜纹（两版实测均被肉眼识别）。只改颜色，`ocean_sample` / `bow_height` / 船吃水 / `shore_distance` 全未变；双后端无 SHADER ERROR，`ocean` 专项退出 0。 [交付记录](../../development/2026-10-26_water_look_and_panel_dim.md) |
| SEA-OCEAN-R07 | 定版：绿通道 107.3（参考 109.8）、标准差 5.08（参考 5.06） | `body_deep` → `(0.031, 0.588, 0.788)`、`exposure_comp` → `0.230`；等距俯视 46 m 开阔水面实测 `0/106/151`，参考帧 `0/108/153`；起伏 p5 103 / p95 115 与参考完全一致。**统计口径**：只算 32×32 格内 100% 是水的区域（整幅画均值会被建筑与白沫污染，把 std 抬高约一倍，本轮据此误调过一次）。探针 `tools/probe_water_stats.gd` / `tools/probe_water_look.gd`。 [交付记录](../../development/2026-10-26_water_look_and_panel_dim.md) |
| SEA-OCEAN-R08 | 本轮实现并实测 | P 面板打开时 HUD 遮罩 `visible=false`、`strength=0`，开阔水面像素与关闭态一致（`0/105/152`）；背包作为对照仍为 `13/90/124`。见 SEA-UI-R17。 [交付记录](../../development/2026-10-26_water_look_and_panel_dim.md) |
| SEA-OCEAN-R09 | 本轮实现并实测 | 新增 `src/rendering/light_params.gd`（30 项：环境 19 + 太阳 11）作为清单唯一源，`color_grade_panel.gd` 增加「光照」页；`tools/check_light_params.gd` 172 项对账（属性存在、出厂值落在范围内、控件覆盖）通过，`tools/probe_light_panel.gd` 22 项端到端通过（写入落到 `Environment` / `Sun`、朝向两轴互不覆盖、关面板后重开恢复、滤镜页不再冲掉光照存档、复位回到场景值）。`visual-paper-fit` 与 `verify_island_ui`（126 项 / 0 失败）回归通过。 [交付记录](../../development/2026-10-26_light_param_panel.md) |
| SEA-OCEAN-R10 | 本轮实现，两套方案实测通过 | 焦散画在水面材质里、采样水下几何体的世界坐标（`bed_world`），不另开 pass 也不动 300+ 个 toon 实例。踩掉两个坑：采样坐标用 `bed_world.xz` 会在竖墙上退化成竖向拉丝（改为三轴互质混合）；`on_geometry` 的 Reverse-Z 判据写反会把该亮的墙全挡掉。图案用双层值噪声（不用正弦，避免规则条纹）。近景 16 m 水下墙面绿通道增量：原版 mean 9.23 / p95 34.0 / 覆盖 34.4%，吸收式 mean 8.10 / p95 34.0 / 覆盖 32.9%，两套观感一致。`check_water_params` 原版 73 项 / 吸收式 40 项通过，`ocean` 与 `visual-sea-style` 退出 0，双后端无 SHADER ERROR。 [OCEAN_RENDERING](../../../godot/OCEAN_RENDERING.md) |

## 资源与调用入口

- [godot/src/rendering](../../../godot/src/rendering)
- [godot/shaders](../../../godot/shaders)
- [godot/assets/materials](../../../godot/assets/materials)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

- `godot/src/rendering/boat_wake.gd`：命令/查询 `update_wake(t: float, boat: Node3D, surface: MeshInstance3D)`；事件 `无`。
- `godot/src/rendering/color_grade_panel.gd`：命令/查询 `set_open(open: bool), set_tab(id: String), set_values(exposure: float, brightness: float, contrast: float, saturation: float), set_water_scheme(id: String)`；事件 `无`。`set_tab` 接受 `filter` / `light` / `water`。
- `godot/src/rendering/light_params.gd`：命令/查询 `flat() -> Dictionary, keys() -> Array[String], section_of(target: String) -> String`；事件 `无`。这是 P 面板「光照」页的唯一参数清单，`target` 取 `env` / `sun`。
- `godot/src/rendering/render_flags.gd`：命令/查询 `reverse_z(), water_emission_gain()`；事件 `无`。
- `godot/src/rendering/shore_distance.gd`：命令/查询 `rebuild(roots: Array, level: float, resolution := RESOLUTION, region := Rect2(), bind(mat: ShaderMaterial), distance_at(p: Vector2)`；事件 `无`。
- `godot/src/rendering/water_surface.gd`：命令/查询 `sample_surface(p: Vector2, at_time: float = -1.0), update_surface(t: float, boat: Node3D, focus: Vector3), emit_ripple(p: Vector2, strength := 1.0), rebuild_shoreline(roots: Array, region := Rect2()`；事件 `无`。

- `godot/shaders/contact_foam.gdshaderinc`：`sample_contact_foam(p: Vector2, d: float, width: float, t: float) -> float`；输入为 `shore_distance` 距离图的米制距离与该实体的尺寸系数，返回 0..1 的交接泡沫覆盖。`contact_foam_pattern` 为空（1×1）时自动退回 `contact_foam_procedural`。艺术参数见 `assets/materials/water.tres` 的 `contact_foam_*`。

## 验证记录

入口：`python3 scripts/run_verification.py ocean`。光照页另有两项：`python3 scripts/run_verification.py lighting-params lighting-panel`。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 ocean 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。
- 2026-10-26 光照页验证：`lighting-params` 退出 0（172 checks / 0 failures），`lighting-panel` 退出 0（22 checks / 0 failures），`ocean` / `visual-paper-fit` 退出 0，`verify_island_ui` 126 项 / 0 失败。未执行：`visual-sea-style` 本轮未重跑（本轮不涉及画面定版参数）；gl_compatibility 后端未单独复验（光照页只改引擎属性，不新增着色器）。

## 遗留与下一步

保留拆分前水面修改。本机 Forward+ 与 gl_compatibility 的双后端水色已按像素实测对齐（见 R02）；目标设备（Web 实机、移动端）仍需专项验证。网页原型 `web/water.js` 未同步本轮参数与着色模型。`foam_line.png` / `large_waves.png` / `ripple_pattern.png` 的第三方授权登记仍为 pending。

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

- 2026-10-24 双后端水色重新对齐：水面重做后 `gl_compatibility` 的水被旧增益 (3.8, 3.8, 2.7) 推到接近削顶（开阔水面 170/241/236，Forward+ 是 1/103/147），本机 GL 端整片水面发白、海底连带被冲淡。按 gain 0.3~3.8 逐档真实渲染 + 开阔水面像素均值拟合，`water_emission_gain()` 改为 1.26，误差 140.7 → 4.0；红通道有约 +9 的色调映射地板，任何增益都压不到 0。新增可复跑工具 `tools/capture_water_gain_probe.gd` 与 `scripts/measure_water_backend_parity.py`。 [测量记录](../../development/2026-10-24_water_backend_parity.md)。

- 2026-10-24 第二套水面（吸收式）：照 Absorption Based Stylized Water 新增 `shaders/water_absorption.gdshader` 与 `assets/materials/water_absorption.tres`，与原方案并存；P 面板水面页顶部加「原版 / 吸收式」方案开关，切换只换 `material_override`（网格、波场、尾迹、桨环、岸线图共用），两套各有独立参数清单（37 / 60）与独立存档段（`[water]` / `[water_absorption]`）。坚持用垂直水深、`depth_distance` 出厂 14 m，是为了保住掠射角下沉没城市的可读性——参考实现的池子尺度会把水下的废墟整片涂掉。原版着色器、材质与场景零改动，core 九项与双后端验证通过。 [交付记录](../../development/2026-10-24_water_absorption_scheme.md)。

- 2026-10-25 两套水面的发光增益分开：吸收式的发光量级比原版亮一档多（Forward+ 水色 `24/185/196` 对 `1/105/147`），共用 `water_emission_gain()` 的 1.26 会让它在 `gl_compatibility` 下掉到 `11/75/123`（误差 65.4）。改为按方案返回：吸收式 `(2.5, 2.8, 2.0)` 逐通道，原版维持 1.26；`main.gd` 注册方案时把 id 传进 `_runtime_water_params()`。端到端误差 原版 4.21 / 吸收式 2.75。 [交付记录](../../development/2026-10-25_water_scheme_gain.md)。

- 2026-10-26 水色按参考帧定版 + 俯视立体明暗 + P 面板去遮罩：新增 `relief` 段（`relief_light` / `relief_shade` / `relief_gain` / `relief_color` / `relief_enabled`），只改颜色，不动顶点位移、共享波场、船吃水与岸线距离图。驱动量用各向异性噪声：先用 `wave.x`、再用单条 4.9 m 波相位，两版都在海面留下平行斜纹，已改掉。`body_deep` → `(0.031, 0.588, 0.788)`、`exposure_comp` → `0.230`；纯水格实测绿通道 107.3 / 标准差 5.08，参考帧 109.8 / 5.06。P 面板不再铺 HUD 的压暗遮罩（见 SEA-UI-R17）。`ocean` / `visual-sea-style` 退出 0；`selftest` 仍 535 通过 2 失败，两项在未改动代码上同样存在（背包格子容器、zone1 共享材质），非本轮引入。 [交付记录](../../development/2026-10-26_water_look_and_panel_dim.md)。

- 2026-10-26 光照参数进 P 面板：新增 `src/rendering/light_params.gd` 作为「光照」页的唯一清单（环境 19 项 + 太阳 11 项），`color_grade_panel.gd` 由两页扩成「滤镜 / 光照 / 水面」三页。太阳朝向以相对海平面的高度角/方位角表达（`look_at` 反算基），不让玩家在欧拉角上换算。写入分两条路：环境走 `ResourceSaver`（并还原被它改成 LF 的 CRLF 行尾，避免整文件 diff 幻影），太阳按行改 `main.tscn` 的 Sun 节点块（实测只动 2 行，节点数与 unique_id 原样保留）。同时修掉一个会丢存档的坑：`_save_cfg()` 原来新建 ConfigFile 直接 save，会把同文件的 `[environment]` / `[sun]` 段抹掉，现改为先 load。新增 `tools/check_light_params.gd`（172 项）、`tools/probe_light_panel.gd`（22 项），并登记进 `scripts/run_verification.py` 的 `lighting-params` / `lighting-panel`。[交付记录](../../development/2026-10-26_light_param_panel.md)。
