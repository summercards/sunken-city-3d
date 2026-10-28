# 2026-10-28 航线虚线移除与点击水纹

对应 SEA-NAV-R09。用户指出航行时铺在海面上的虚线太难看，要求整条去掉；点击位置的反馈改成「小波纹散开」。

## 去掉的是什么

`route_ribbon.gd` 原实现用 ImmediateMesh 沿航路每 1.1m 铺一段 0.5m×0.34m 的横带（DASH/GAP = 0.55/0.55），底色 `(0.66,0.99,0.90)`、alpha 0.85，外加终点一个呼吸圆环。代码里当时也写了理由：「加了岸线寻路之后航路会拐弯，需要提前看见」。实测结论相反：等距俯视下它横穿海面，一眼就读成 UI 画上去的虚线，而且绕行时那根线自己也在拐，反而把注意力从船上拽走。

本轮把整条虚线、终点呼吸环、ImmediateMesh 全部删除；`show_route(points, water_y)` 签名保留，调用方（`_try_sail_to` / `_sail_to_landing` / `_handle_prop_click` / `_update_camera_feedback`）一行未改，仍交整条航路，函数只取末点。路径计算、绕障、30 条航线回归不受影响。

`debug_band_count()` 保留并恒返回 0，供验收断言盯着「谁把航段加回来」。

## 换成什么

终点放一组贴浪面的细白弧，从中心往外推，循环播放（`PERIOD=2.4s`，`RADIUS=0.72m`，`OPACITY=0.45`）。方向感和绕行由船本身表达，不再画出来。

同时把两处「重复反馈」删掉：`_try_sail_to` 与 `_select_landing` 原本在铺完航线后再叠一个 `reticle.show_at(..., true)` 准星，位置和水纹重合，只是多出一圈相位不同的干扰。

`click_reticle.gd` 整体还原到改动前：岸上点地格走位仍是原来的落点环 + 圆点。那里没有水面，套水纹不合理。

## 着色器

新增 `godot/shaders/water_ripple.gdshader`，被 `route_ribbon.gd` 独用。`#include ocean_waves.gdshaderinc`，顶点按 `ocean_sample()` 贴浪面起伏（+0.055m 抬离水面），并每帧从 `WaterSurface` 同步 `u_time / ocean_waves / wave_scale`，所以波纹跟真实浪线走，不是一张浮在水上的贴纸。

造型是显式 3 圈：`radius = front - i * wavelength`，`front = mix(0.07, 0.86, pow(u_progress, 0.58))`。

| 参数 | 值 | 作用 |
|---|---|---|
| `wavelength` | 0.30 | 相邻两圈径向间距（p 空间） |
| `crest_width` | 0.014 | 亮脊半宽，本视距约 2px |
| `crest_decay` | 0.45 | 每往内一圈保留的亮度 |
| `u_opacity` | 0.45 | 整体透明度 |
| `u_progress` | 0→1 循环 | 波前位置 |

### 走过的四条弯路（记下来，下次别再走）

1. **`floor()` 数圈**：圈边界上 `fwidth()` 跳变，边缘裂成一圈锯齿状断点。
2. **`fract()` 三角波 + 角度调制**：各圈相位沿半径错开，整片连成螺旋，画出来是蚊香。
3. **亮脊 + 双侧暗肩**（ALBEDO 转深色压暗）：暗肩太宽就成了「白圈套黑盘」的霓虹灯，比原虚线更难看。
4. **只降 alpha 想「淡一点就行」**：水面本身满是白色泡沫碎线，浅色细环混在泡沫里根本读不出。

最终靠三件事让圈读得出来：比水面亮（`ring_tint = (0.86,0.99,0.97)`）、线足够细（1–2px）、沿圆周粗细与亮度都在变（`sin(angle*… )` 调制，且只挂角度不挂半径）。

## 验收

新增 `visual-route-ripple` 专项（`godot/tools/capture_route_ripple.gd`），真实渲染、隔离存档，断言三条：点水面确实出航、`debug_band_count() == 0`、终点水纹 `visible`。截图抓 4 个相位（起手 / 中段 / 散开 / 只剩目标）。

取景上踩过一个坑：按世界坐标反算屏幕位置来裁切，算出来偏 200 多像素，裁到的全是空水，一度误判「水纹没渲染」。现在直接拿视口中心 `(640,400)` 当点击坐标，再在铺完后把相机对准 `ribbon.global_position`（航路末点会被导航网格吸附，和点击点差几十厘米）。

| 专项 | 退出码 | 完成标记 |
|---|---|---|
| visual-route-ripple | 0 | `[route-ripple] checks done, failures=0` |
| click | 0 | `[click-controls] 32 checks, 0 failures` |

`click` 需带 `--full-world`：默认最小范围下 `_on_destination("zone3")` 等三条跨区用例本就不成立，是既有前提差异，非本轮引入。

证据：`D:\projects\sea-work\verification\20261028-221414-ripple-final-9a4366`。

## 保护范围

未改航速、转向、吃水、碰撞、泊位、寻路算法与 30 条航线数据；未改存档结构、水面着色器、昼夜光照与水域判定。`_try_sail_to` / `_sail_to_landing` 只删了准星那两行，其余逻辑与提示语不变。
