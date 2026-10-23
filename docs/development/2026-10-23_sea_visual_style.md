# 2026-10-23 · 柔和光影投影、卡通动态水波纹与彩色小鱼群表现

[主文档](../../GDD_V1.0.md#feature-control) · [海面拾取账本](../features/pickup/ledger.md) · [水面账本](../features/ocean/ledger.md) · [世界账本](../features/world/ledger.md)

## 来源与原因

1. 对照参考画面与网页版：需要消除 Godot 默认 `diffuse_toon` 阶梯断层造成的生硬明暗与脏黑背光面，同时保留清晰柔和的屋顶/植物投射阴影（阴影/受光亮度比约 `0.75`），避免画面过曝泛白。
2. 建筑、浮台与立柱的吃水线需要呈现参考图中的多圈卡通动态水波纹（圆润主水线 + 两道带自然缺口与粗细渐变的同心弧线 + 3 层向外扩散渐隐的动态涟漪圈），而非生硬噪点切边或模糊雾团。
3. 鱼群需要缩小比例、采用鲜明可爱的彩色配色（珊瑚鲜橙、明亮金黄、樱桃粉红、荧光薄荷青、晴空亮蓝、鲜嫩青柠绿），并具备生动的 S 型摆尾、周期冲刺、侧倾与贴水跃动效果。

## 实施

- **柔和卡通光影与投射阴影恢复（`toon.gdshader` / `toon_alpha.gdshader` / `toon_common.gdshaderinc` / `world_env.tres` / `main.tscn`）**：
  - 将 `half_lambert * ATTENUATION` 统一送入平滑过渡 `mix(0.26, 0.96, smoothstep(0.14, 0.78, lit_factor))`，并为暗部注入晴空青蓝柔光 `vec3(0.68, 0.86, 0.94)`。
  - 环境标定：`tonemap_exposure = 1.10`、`ambient_light_energy = 0.36`、`adjustment_brightness = 1.00`、`adjustment_contrast = 0.88`、`adjustment_saturation = 1.08`，同步更新 `user://filter.cfg`。
  - 主太阳光 `light_energy = 0.54`、`shadow_opacity = 0.86`、`shadow_blur = 1.4`；实测天台投影区亮度 `150.8`、受光区亮度 `200.7`（比值 `0.752`，与参考图 `0.750` 对齐），高光 P95 为 `215.9`（参考图 `216.7`），彻底消除过曝并恢复清晰柔和的建筑与绿植投影。
- **水面与物体边缘的卡通动态白波纹（`ocean_foam.gdshaderinc` / `surface_ripple.gdshader` / `water.tres`）**：
  - `shore_rim` 由主吃水线 `cartoon_ribbon` + 两道 `shore_arc_band`（两端渐细、带自然留白缺口的同心卡通弧线）组成。
  - `shore_foam` 升级为 3 层向外扩散、粗细渐变的开放式波纹弧线，随时间柔和呼吸与消散。
  - `surface_ripple.gdshader` 增加双圈交错开环弧线与向外扩散的脉冲波纹圈（`pulse`），与水面波浪同步起伏。
- **缩小彩色鱼群与生动动态效果（`fish_school_visual.gd`）**：
  - 鱼身缩小至原尺寸约 60%（`Vector3(0.098, 0.068, 0.185)`），带 `0.88x–1.06x` 个体差异，背部加亮色条纹与轻度自发光，配套涟漪半径缩至 `1.68m`。
  - 6 色鲜明配色轮换，加入周期性加速冲刺（darting）、8 字形呼吸轨迹、头部+身体+尾鳍相位差 S 型摆动、转弯侧倾与水面微跃。
- **旧烘焙静态鱼/圆环退役保留**：环境及各区块 `StaticBatch` 与 9 个区块 GLB 的旧静态鱼/圆环/点击盘退役保持不变，[逐文件前后哈希与面数报告](2026-10-23_retired_surface_geometry.json)。

## 保留的网页锚点（世界 X / Z，米）

| X | Z |
|---:|---:|
| 18.50664 | -23.00175 |
| -13.04740 | -9.35030 |
| 44.09835 | 17.45034 |
| 43.61626 | -31.29347 |
| -45.09357 | -47.52166 |
| -20.83852 | 9.64335 |
| 29.22829 | 15.19535 |

## 验证

统一入口：`python3 scripts/run_verification.py visual-sea-style ocean selftest --label soft-shadow-final`，全部在工程外副本和独立用户目录运行。

- 最终规则与渲染验证目录：`../sea-work/verification/20261023-222032-soft-shadow-final-50af79/`。
- `visual-sea-style`、`ocean`、`selftest` 均退出 0、全部通过（`selftest` 537 passed, 0 failed；`ocean` 43 checks, 0 failures；`visual-sea-style` 35 条彩色小鱼全部参与动态游动，0 failures）。
- 截图包含 `harbor`、`channel`、`aqua`、`fish`、`fish-later` 五帧及默认机位完整画面 `godot/outputs/godot-preview.png`，均已目视与像素分位数核验。

[随工程保存的逐项验证摘要](2026-10-23_sea_visual_verification.json)。
