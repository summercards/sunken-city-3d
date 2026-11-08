# 家园海底·回字型深沟 高楼参考位清单

[主文档](../../../GDD_V1.0.md) · [世界功能](../world/spec.md) · [摆位台账](placed_positions.md) · [交付记录](../../development/2026-11-08_sealed_buildings_and_canyon_ring.md)

**沿矩形四边直线摆放，不是环形。** 两层方框：外框半宽 112 m（每边 7 个，间距 37.33 m，共 24 个），
内框半宽 72 m（每边 5 个，间距 36.0 m，共 16 个），沟宽 40 m，合计 40 栋。
每条边上的楼 X 或 Z **严格共线**，朝向只取 0°/90°/180°/270° 四向、一律朝框内，不加抖动。
尺度 2.0×（v003 原生几何），内框整体退一档，从沟底看是内低外高两层楼墙。

这些是**参考位**，不是验收标准。你在编辑器里摆完以实际 transform 为准（AGENTS 第 12 条），
摆完后我按实测值更新台账，不会改回参考值。

## 外框（24 个）

| 节点名 | 边 | 参考 X | 参考 Y | 参考 Z | 朝向 | 组件 | 楼高(×2) | 楼顶 Y | 露出水面 |
|---|---|---|---|---|---|---|---|---|---|
| `tall_outer_00_slender_tower` | Z 边 | -112.00 | -61.90 | 112.00 | 180° | slender_tower | 119.3 m | 57.4 | +49.8 m |
| `tall_outer_01_terrace_residence` | Z 边 | -74.67 | -61.90 | 112.00 | 180° | terrace_residence | 68.3 m | 6.4 | -1.2 m |
| `tall_outer_02_tram_tenement` | Z 边 | -37.33 | -66.70 | 112.00 | 180° | tram_tenement | 88.7 m | 22.0 | +14.4 m |
| `tall_outer_03_rounded_corner` | Z 边 | 0.00 | -66.70 | 112.00 | 180° | rounded_corner | 68.3 m | 1.6 | -6.0 m |
| `tall_outer_04_terraced_tower` | Z 边 | 37.33 | -66.70 | 112.00 | 180° | terraced_tower | 109.1 m | 42.4 | +34.8 m |
| `tall_outer_05_cutaway_tenement` | Z 边 | 74.67 | -61.90 | 112.00 | 180° | cutaway_tenement | 67.7 m | 5.8 | -1.9 m |
| `tall_outer_06_balcony_tenement` | Z 边 | 112.00 | -61.90 | 112.00 | 180° | balcony_tenement | 78.5 m | 16.6 | +9.0 m |
| `tall_outer_07_terrace_residence` | Z 边 | -112.00 | -61.90 | -112.00 | 0° | terrace_residence | 68.3 m | 6.4 | -1.2 m |
| `tall_outer_08_tram_tenement` | Z 边 | -74.67 | -61.90 | -112.00 | 0° | tram_tenement | 88.7 m | 26.8 | +19.2 m |
| `tall_outer_09_rounded_corner` | Z 边 | -37.33 | -66.70 | -112.00 | 0° | rounded_corner | 68.3 m | 1.6 | -6.0 m |
| `tall_outer_10_terraced_tower` | Z 边 | 0.00 | -66.70 | -112.00 | 0° | terraced_tower | 109.1 m | 42.4 | +34.8 m |
| `tall_outer_11_cutaway_tenement` | Z 边 | 37.33 | -66.70 | -112.00 | 0° | cutaway_tenement | 67.7 m | 1.0 | -6.7 m |
| `tall_outer_12_balcony_tenement` | Z 边 | 74.67 | -61.90 | -112.00 | 0° | balcony_tenement | 78.5 m | 16.6 | +9.0 m |
| `tall_outer_13_slender_tower` | Z 边 | 112.00 | -61.90 | -112.00 | 0° | slender_tower | 119.3 m | 57.4 | +49.8 m |
| `tall_outer_14_rounded_corner` | X 边 | 112.00 | -61.90 | -74.67 | -90° | rounded_corner | 68.3 m | 6.4 | -1.2 m |
| `tall_outer_15_terraced_tower` | X 边 | 112.00 | -61.90 | -37.33 | -90° | terraced_tower | 109.1 m | 47.2 | +39.6 m |
| `tall_outer_16_cutaway_tenement` | X 边 | 112.00 | -61.90 | 0.00 | -90° | cutaway_tenement | 67.7 m | 5.8 | -1.9 m |
| `tall_outer_17_balcony_tenement` | X 边 | 112.00 | -61.90 | 37.33 | -90° | balcony_tenement | 78.5 m | 16.6 | +9.0 m |
| `tall_outer_18_slender_tower` | X 边 | 112.00 | -61.90 | 74.67 | -90° | slender_tower | 119.3 m | 57.4 | +49.8 m |
| `tall_outer_19_terraced_tower` | X 边 | -112.00 | -61.90 | -74.67 | 90° | terraced_tower | 109.1 m | 47.2 | +39.6 m |
| `tall_outer_20_cutaway_tenement` | X 边 | -112.00 | -61.90 | -37.33 | 90° | cutaway_tenement | 67.7 m | 5.8 | -1.9 m |
| `tall_outer_21_balcony_tenement` | X 边 | -112.00 | -61.90 | 0.00 | 90° | balcony_tenement | 78.5 m | 16.6 | +9.0 m |
| `tall_outer_22_slender_tower` | X 边 | -112.00 | -61.90 | 37.33 | 90° | slender_tower | 119.3 m | 57.4 | +49.8 m |
| `tall_outer_23_terrace_residence` | X 边 | -112.00 | -61.90 | 74.67 | 90° | terrace_residence | 68.3 m | 6.4 | -1.2 m |

## 内框（16 个）

| 节点名 | 边 | 参考 X | 参考 Y | 参考 Z | 朝向 | 组件 | 楼高(×2) | 楼顶 Y | 露出水面 |
|---|---|---|---|---|---|---|---|---|---|
| `tall_inner_24_half_tower` | Z 边 | -72.00 | -61.90 | 72.00 | 180° | half_tower | 88.7 m | 26.8 | +19.2 m |
| `tall_inner_25_frame_construction` | Z 边 | -36.00 | -66.70 | 72.00 | 180° | frame_construction | 63.7 m | -3.0 | -10.6 m |
| `tall_inner_26_roof_garden_shell` | Z 边 | 0.00 | -66.70 | 72.00 | 180° | roof_garden_shell | 52.0 m | -14.7 | -22.3 m |
| `tall_inner_27_canal_shell` | Z 边 | 36.00 | -66.70 | 72.00 | 180° | canal_shell | 58.1 m | -8.6 | -16.2 m |
| `tall_inner_28_canal_housing` | Z 边 | 72.00 | -61.90 | 72.00 | 180° | canal_housing | 78.5 m | 16.6 | +9.0 m |
| `tall_inner_29_frame_construction` | Z 边 | -72.00 | -61.90 | -72.00 | 0° | frame_construction | 63.7 m | 1.8 | -5.8 m |
| `tall_inner_30_roof_garden_shell` | Z 边 | -36.00 | -66.70 | -72.00 | 0° | roof_garden_shell | 52.0 m | -14.7 | -22.3 m |
| `tall_inner_31_canal_shell` | Z 边 | 0.00 | -66.70 | -72.00 | 0° | canal_shell | 58.1 m | -8.6 | -16.2 m |
| `tall_inner_32_canal_housing` | Z 边 | 36.00 | -66.70 | -72.00 | 0° | canal_housing | 78.5 m | 11.8 | +4.2 m |
| `tall_inner_33_half_tower` | Z 边 | 72.00 | -61.90 | -72.00 | 0° | half_tower | 88.7 m | 26.8 | +19.2 m |
| `tall_inner_34_canal_shell` | X 边 | 72.00 | -61.90 | -36.00 | -90° | canal_shell | 58.1 m | -3.8 | -11.4 m |
| `tall_inner_35_canal_housing` | X 边 | 72.00 | -61.90 | 0.00 | -90° | canal_housing | 78.5 m | 16.6 | +9.0 m |
| `tall_inner_36_half_tower` | X 边 | 72.00 | -61.90 | 36.00 | -90° | half_tower | 88.7 m | 26.8 | +19.2 m |
| `tall_inner_37_canal_housing` | X 边 | -72.00 | -61.90 | -36.00 | 90° | canal_housing | 78.5 m | 16.6 | +9.0 m |
| `tall_inner_38_half_tower` | X 边 | -72.00 | -61.90 | 0.00 | 90° | half_tower | 88.7 m | 26.8 | +19.2 m |
| `tall_inner_39_frame_construction` | X 边 | -72.00 | -61.90 | 36.00 | 90° | frame_construction | 63.7 m | 1.8 | -5.8 m |

