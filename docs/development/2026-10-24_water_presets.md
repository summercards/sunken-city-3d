# 水面出厂参数定版与收藏预设

日期：2026-10-24
范围：`godot/assets/materials/water.tres`、`godot/assets/materials/water.tres` 出厂值、`godot/src/rendering/color_grade_panel.gd`、`godot/src/rendering/water_params.gd`、`godot/shaders/water.gdshader`、`godot/scenes/main.tscn`

## 做了什么

1. 把手工调好的 25 项参数 + 节点波幅写进 `water.tres` / `main.tscn`，成为新的出厂值。
2. P 面板「水面」页顶部加「收藏」：下拉整套切换、存、删。
3. `user://water.cfg` 加出厂指纹，`water.tres` 一换，旧存档自动作废。

## 参数表

| 参数 | 旧 | 新 |
|---|---|---|
| `body_shallow` | (0.128, 0.618, 0.584) | (0.51750183, 0.99609375, 0.99609375) |
| `body_deep` | (0.070, 0.399, 0.549) | (0.02822876, 0.60872674, 0.72265625) |
| `depth_half_distance` | 7.0 | 12.25 |
| `shallow_tint_strength` | 1.3 | 2.7 |
| `view_occlusion_strength` | 0.10 | 0.19 |
| `absorption` | (0.088, 0.036, 0.028) | (0.236, 0.091, 0.025) |
| `refraction_strength` | 22.0 | 26.0 |
| `normal_lighting` | 0.45 | 1.0 |
| `surface_normal_strength` | 0.45 | 0.35 |
| `normal_repeat_metres` | 2.5 | 1.0 |
| `detail_broad` | 0.36 | 0.97 |
| `detail_mid` | 0.44 | 0.03 |
| `detail_fine` | 0.16 | 0.49 |
| `sky_top_color` | (0.30775, 0.94922, 0.78384) | (0.318985, 0.72265625, 0.49559116) |
| `sky_horizon_color` | (0.610, 0.790, 0.840) | (0.23641968, 0.42378378, 0.4765625) |
| `sky_ground_color` | (0.10, 0.26, 0.32) | 不变 |
| `sky_curve` | 0.35 | 0.57 |
| `sky_sun_glow` | 0.35 | 0.02 |
| `reflection_strength` | 0.35 | 不变 |
| `fresnel_power` | 6.0 | 5.8 |
| `sun_direction` | (0.5191, 0.7787, -0.3523) | (0.49, 0.92, -0.1) |
| `sun_color` | (1.0, 0.955, 0.8) | (0.3040924, 0.85546875, 0.76500857) |
| `sun_highlight_strength` | 0.30 | 0.06 |
| `sun_glossiness` | 7000 | 8000 |
| `sun_lobe_gain` | 60 | 10 |
| `exposure_comp` | 0.66 | 0.45 |
| `dither_strength` | 1.0 | 1.35 |
| `wave_scale`（节点） | 1.0 | 1.2 |

波纹、泡沫、吃水线泡沫各项保持原值。

## 顺手放宽的三个范围

这套值有三项正好压在滑杆端点上，不放开就只能单方向调：

| 参数 | 旧 `hint_range` | 新 |
|---|---|---|
| `normal_repeat_metres` | (1.0, 20.0, 0.1) | (0.5, 20.0, 0.1) |
| `sun_glossiness` | (100.0, 8000.0, 50.0) | (100.0, 12000.0, 50.0) |
| `sun_lobe_gain` | (10.0, 400.0, 1.0) | (5.0, 400.0, 1.0) |

着色器与 `water_params.gd` 同步改，`check_water_params.gd` 的范围核对才仍 PASS。

## 收藏的实现选择

- **不塞进 `water.cfg`**。`water.cfg` 是「上次调到哪」，收藏是「我特意存下来的几套」，清存档时不该一起没。
- **顺序记在 `[meta] names`**。ConfigFile 的 section 顺序不保证，不能靠 `get_sections()` 返回的顺序做下拉顺序。
- **存面板值而不是着色器值**。颜色 `Color`、向量 `Vector3`/`Vector2`、节点属性 `float`，与 `_water_read()` 同型，套用时原样喂回 `_water_write()`。存着色器值（`source_color` 的 vec3 要转 `Color`）就得再维护一套转换，容易和写回路径分叉。
- **第一项固定是「出厂」**，现读 `water.tres`，不可删，等价于底部「复位」按钮，但不用先滚到底。
- **同名即覆盖**，不弹二次确认，flash 里写明「已覆盖」。删有确认框。
- 名字里的 `[` `]` 会被剔掉：ConfigFile 的 section 名用方括号收尾，带进去会把文件写坏。

## 出厂指纹

`water.cfg` 加一行 `__mat_sig = <water.tres md5>`，`_apply_water_cfg()` 加载时比对，不匹配整份丢弃。

必要性来自实测：本机 `user://water.cfg` 里存着上一版（7.0 / 1.3 那一套），不加指纹的话，新出厂值启动即被盖住，看起来像「改了没生效」。加上之后，以后任何一次改 `water.tres` 都会自动让旧存档失效。

`wave_scale` 的出厂值在 `main.tscn` 的节点导出属性上，不在资源里。面板第一次解析到节点时抓一份 `_factory_wave_scale`，「复位」和「出厂」项都按它还原。

## 验证

| 项 | 结果 |
|---|---|
| `tools/check_water_params.gd` | `PASS 50 个参数与着色器一致（另有 20 个豁免）` |
| 预设全链路探针（临时脚本，已删） | 22 项全过：存 / 切换 / 覆盖 / 删 / 出厂项 / 指纹 |
| Forward+ 真实渲染 | 退出 0，无 SHADER ERROR |
| `gl_compatibility` | 退出 0，无 SHADER ERROR |
| `check_feature_contracts.py` | 仅剩 `main.gd:1928` 引用 `res://outputs` 一项历史遗留 FAIL |
| `main.tscn` 体积 | 6178 → 6178 字节，未被 `@tool` 烘焙 |

探针覆盖的具体断言：出厂四项（`body_shallow` / `depth_half_distance` / `dither_strength` / 节点 `wave_scale`）与实际值一致；存两套后改三个值能整组复原；覆盖同名不增条目；选「出厂」回到 12.25 / 1.2；删除后下拉只剩出厂项、文件里不留测试条目；`water.cfg` 的指纹与 `water.tres` 当前 md5 相等。

## 未做

- `web/water.js` 仍未同步这套参数，网页原型与 Godot 端的观感早已分叉（上一轮遗留）。
- 两张贴图（`large_waves.png` / `ripple_pattern.png`）的授权登记仍是 `pending`（上一轮遗留）。
- 收藏不能导出成文件分享给别人，只能本机 `user://`。需要的话可以加「复制为预设文本」。
