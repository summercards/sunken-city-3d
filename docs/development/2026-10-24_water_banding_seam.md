# 水面“割裂感”修复（2026-10-24）

功能：SEA-OCEAN（水面与光照渲染）· 条款 SEA-OCEAN-R01
涉及文件：`godot/shaders/water.gdshader`、`godot/assets/materials/water.tres`、`assets/registry/runtime_resource_inventory.json`、`godot/OCEAN_RENDERING.md`

## 问题

俯视水面出现大块不同明度的平行四边形色块，边缘硬直，读起来像水面被切开拼接。

## 排除项

- **不是几何接缝**：主场景只有一块水面（`scenes/main.tscn` 的 `PlaneMesh`，`_ready()` 换成 `water_surface.gd:_make_grid()` 的 257² 自适应网格），无重叠面、无 z-fighting，网格只有位移。
- **不是矩形色阶偏移**：对截图做 32×32 分块中值，蓝通道全图 151–157，绿通道 103–112 以 3–5 级台阶跳变、台阶边界为直线——是色块不是接缝。
- 网页版 `web/water.js:55/73/74/97/102` 是同一套算法同一组常数，故为原设计固有，不是 Godot 移植走样。

## 根因

`water.gdshader` 的体色叠加了三层低频场，每层都是对**直线等值线**做平滑阈值：

| 层 | 来源 | 原阈值带 |
| --- | --- | --- |
| `swell` | `broad(p*0.12)`，`hash()` 值噪声，格边梯度为 0（8.3 米直角菱形格） | `smoothstep(0.30,0.70)` |
| `wave_light` | `sin(dot(p,d))` 三条平面波，等值线是直线 | `smoothstep(0.10,0.85)` |
| `facet` | `broad(wave_domain)`，格边 3.7 米 | `smoothstep(0.44,0.56)`（几乎二值） |

水面是纯 emission（`ALBEDO=0`，`EMISSION` 承载全部颜色），没有法线光照、高光、环境反射或贴图来打散这些 2–4% 的低频平色块；8 bit 输出再把缓变振幅切成同心台阶，台阶边缘的马赫带效应让“色块”看起来像“切口”。

## 改动

1. 放宽三处阈值带（同光量摊在梯度上，而不是台阶上）：
   - `swell` 0.30–0.70 → 0.20–0.80；
   - `wave_light` 0.10–0.85 → −0.10–0.95，系数 `vec3(0.002,0.018,0.020)` → `vec3(0.002,0.014,0.016)`；
   - `facet` 0.44–0.56 → 0.30–0.70。
2. 输出前加 1 LSB 抖动：新 uniform `dither_strength`（默认 1.0），interleaved gradient noise，屏幕空间静态。写在 `EMISSION` 处，泡沫与反光平面一并受益。
3. `water.tres` 显式登记 `dither_strength = 1.0`；运行资源清单只刷新 `water.tres` 一条哈希（1749 B → 1788 B），不做批量接受漂移。

## 验证

工程外副本 `sea-work/manual-water-check/`（真实复制 `assets` 与 `.godot`，因为 `run_verification.py` 的隔离副本在本机沙箱里符号链接会失效），Godot 4.7.2-stable / Forward+ / RTX 3060：

| 项 | 结果 |
| --- | --- |
| `tools/capture_sea_style.gd`（真实渲染，Forward+） | 退出 0，无 SHADER ERROR，`[sea-style] complete` |
| `tools/capture_water_ab.gd`（新写的同机位 A/B，Forward+） | 退出 0，`[ab] complete`，四组视图各出旧/新两张 |
| 同一 A/B 在 `--rendering-method gl_compatibility` | 退出 0，无 SHADER ERROR（`FRAGCOORD` 抖动在两后端均可编译） |
| 视觉 A/B（对比增强 3.6×） | 改动前开阔水面有明确对角直边与菱形色块；改动后连续渐变、无直边 |
| 原生对比度 | 两版都读作平滑水面，抖动未引入可见颗粒 |
| `python3 scripts/check_feature_contracts.py` | 1 项遗留：`main.gd:1928` 的 `res://outputs` 目录在仓库里不存在（HEAD 已存在，与本次无关）；本功能哈希漂移已消除 |

A/B 抓图：`sea-work/manual-water-check/project/outputs/ab-{old,new}-{far,mid,near,top}.png`（Forward+）、`gl-{old,new}-*.png`（gl_compatibility）、拼图 `water-ab.png` / `water-ab-final.png`。

## 遗留

- `main.gd:1928` 的 `res://outputs` 让契约检查永远有 1 项 FAIL，需要决定是补占位目录还是改路径。
- 本机沙箱下 `run_verification.py` 的隔离副本（资产为符号链接）不可用，`ocean` 逻辑回归需在用户终端执行；本次改用真实副本渲染验证。
- 阈值带放宽等于压低 `surface_contrast` 的有效对比，近距离画意光斑略平；要回层次调 `surface_contrast`，不要收窄阈值带。
- 形状级修复（perlin 梯度噪声 + 逐 octave 旋转）留作选项，会同时改掉网页对照图案。
