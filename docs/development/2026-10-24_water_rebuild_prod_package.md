# 水面按生产包模型重做（2026-10-24，第三轮）

## 起因

前两轮都在改「同一套画法」的参数：先放宽阈值带、加抖动，再把值噪声换成梯度噪声。用户仍能看到割裂，因为这版水面的问题不在边缘软硬，而在**整张水面没有任何高频细节**——纯 emission、无贴图、无光照，颜色是低频场的函数。任何低频场的等值线在平坦大面上都会被读成边界。

本轮按用户提供的 `stylized_water_prod` 参考包（`F:\Downloads\stylized_water_prod_2026-10-23.zip`）的着色模型重做水面，把细节放回纹理空间。

## 参考包的模型

`demos/stylized_water_prod/stylized_water_prod.gdshader` 的五层结构：

| 层 | 作用 | 本工程处理 |
| --- | --- | --- |
| 深度透射 | 屏幕色 + 屏幕深度还原水柱，指数混合浅水染色与深水色 | 采用，但改用垂直水柱（见「一处刻意分叉」） |
| 法线贴图 | 大尺度法线条带双向滚动 | 采用，`large_waves.png` |
| 天空反射 | Cubemap + 掠射菲涅尔 | 改为解析渐变，不引入 Cubemap 资源 |
| 太阳高光 | 扁平化法线 + 屏幕导数滤波的单个高光瓣 | 采用，收紧到本工程机位 |
| 波纹网络 | 有符号距离等高线贴图驱动的墨线网络 | 采用，`ripple_pattern.png`，按本工程尺度缩 |
| 交界泡沫 | 离线烘焙的接触场 | **不采用**：本工程已有启动期光栅化的岸线图集与移植版 ContactFoam |

## 保留的工程自有层

参考包是 34×30 m 的池塘 demo，没有这些东西，但本工程依赖：

- `ocean_waves.gdshaderinc` 的顶点位移——`water_surface.gd` 的 `sample_surface()` 用同一组波参数给船算吃水，换波场会让船浮在错误的面上；
- `ocean_wake.gdshaderinc` 的船尾迹、船桨涟漪环（`u_ripples`）；
- `ocean_foam.gdshaderinc` 的岸线高、细物体接触边缘、浪顶白沫；
- `contact_foam.gdshaderinc` 的交界泡沫带（上一轮移植）；
- 设施周边水面微光（`glint_zone`）。

## 改动

### `godot/shaders/water.gdshader`（整体重写）

- 顶点位移沿用 `ocean_sample()`；新增 `v_normal_uv` / `v_ripple_uv` / `v_ripple_phase` 三个仿射载体，时钟全部留在片元。
- 法线 = 几何坡度（`normal_lighting`）叠加法线条带两次反向滚动的倾斜（`surface_normal_strength`）。
- 体色按参考包的链路：`depth_blend` / `body_opacity` → `shallow_visibility` / `bottom_visibility` → `bed * (bottom_visibility + shallow_tint * transmission * shallow_visibility) + body_deep * (transmission * (1 - shallow_visibility))`。
- 天空反射改为 `sky_at()`：用 `ocean_sky.tres` 的三个颜色做解析渐变，再叠一个朝太阳方向的暖晕。省掉 416 KB 的 Cubemap，也不会和场景天空漂移。
- 太阳高光用参考包的滤波模型（法线 Y 压扁 ×3、反射方向用 `dFdx/dFdy` 估像素足迹），峰值增益改成 uniform `sun_lobe_gain`：参考包的 250 是配它自己的波场和低机位，本工程机位高得多，250 会糊成一片白云，实际取 60。
- 波纹网络保留参考包的相位结构与生命周期脉冲，但**世界尺寸单独参数化**（`ripple_tile_metres`，6×4.5 m），并把淡出范围做成参数（`ripple_fade_near/far`，6/28 m）。参考包按 24×18 m 一格，在俯视开阔海面上是米级宽的白色带子。
- 输出仍是 `ALBEDO=0` + `EMISSION`，保留 `exposure_comp` / `emission_gain` / `dither_strength`。

### 一处刻意分叉：垂直水柱而不是轴向水柱

参考包用**轴向**视线深度差算水柱厚度。在掠射角下这条路径是垂直深度的很多倍，于是水面会恰好在玩家横向看过去时变成不透明——而本工程的核心观感是「透过水面看得见沉没的城市」。

所以 `vertical_depth = max(0, v_world.y - bed_world.y)` 用于体色与吸收，轴向 `thickness` 仍用于折射强度与「有没有水底」的判定（`thickness > 44` 视为无底，按 60 m 处理）。这一条让低机位下淹掉的货架、楼梯、塔基仍然可读。

### 资源

新增 `godot/assets/textures/water/large_waves.png`（1024²，线性 + mip，按法线图导入）与 `ripple_pattern.png`（1024² L8，线性 + mip，导入上限 512）。两者都验证过四方连续：左右/上下边界的平均差与内部相邻列差一致（法线 0.3–0.6 级，波纹 3–4 级），不存在接缝。

两条都按 `foam_line.png` 的既有约定登记为 `third_party_package_source_license_and_registration_pending`——来源与授权状态仍需补齐，和上一轮移植泡沫时一致。

### `godot/assets/materials/water.tres`

删除失效参数（`surface_contrast`、`fresnel_color/radius/gain`、`depth_near/far`、`transmission_near/far`、`ssr_*`），新增 `large_wave_normals`、`ripple_pattern`、`sun_lobe_gain`、`ripple_tile_metres`、`ripple_fade_*`、`sky_*`、`normal_repeat_metres`。太阳方向按主场景 `World/Lights/Sun` 的世界 +Z 取值 `(0.5191, 0.7787, -0.3523)`。

## 验收

工程外真实副本 `sea-work/manual-water-check/`，同机位、同帧序列，运行时只切换着色器（`tools/capture_water_ab.gd`、`capture_water_low.gd`）。

| 项 | 结果 |
| --- | --- |
| `capture_water_ab.gd`（4 机位 × 新旧） | 退出 0，无 SHADER ERROR，`[ab] complete` |
| `capture_water_low.gd`（掠射角） | 退出 0，无 SHADER ERROR |
| Forward+ | 开阔水面基色 (0,106,153)，旧版 (0,107,153)，水色未漂移 |
| `gl_compatibility` | 退出 0、无 SHADER ERROR；该后端在本机整体过曝（新旧着色器水面均值 183/246/243 对 182/245/242），属既有环境问题，与本次改动无关 |
| `python3 scripts/check_feature_contracts.py` | 仅剩 `main.gd` 引用 `res://outputs` 一条历史遗留 FAIL |

截图：`sea-work/manual-water-check/project/outputs/` 下 `w-{new,old}-{open,open2,near,harbor}.png`、`low-{new,old}.png`，对照拼图 `water-rebuild-near.png` / `water-rebuild-harbor.png` / `water-rebuild-low.png`；参数扫描 `sw-*` / `sun-*` / `rip-*` / `fres-*`。

## 取舍与后续

1. **`web/water.js` 没有同步。** 这次是换着色模型，网页版要一起换就得重写 three.js 的着色器并带两张贴图。目前网页原型仍是上一轮的梯度噪声版，两个后端的水面观感已经分叉，需要单独一轮处理。
2. **波纹网络是新增的视觉元素。** 出厂值取「细线、稀疏、45% 不透明」，接近原工程的白色笔触语言；想更接近参考包那种明确的墨线网络，把 `ripple_width_multiplier` 提到 0.8、`ripple_coverage` 提到 0.7、`ripple_color.a` 提到 0.8。
3. **法线条带按 2.5 m 重复。** 这个尺度主要是为了让太阳高光碎成闪烁而不是一片白云；如果远处出现规律性反光，把 `normal_repeat_metres` 调大。
4. 参考包的两张贴图授权状态未确认，和 `foam_line.png` 一样先记在资源清单里，上线前需要补齐。
