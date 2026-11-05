# 相机缩放上限收到 38 米（SEA-CAMERA-R11）

2026-11-05

## 诉求

主人在实机局面截图里指出：**摄像机最远就到「38」这一档，不用再拉远。**

## 改了什么

| 文件 | 变更 |
|---|---|
| `godot/src/camera/orbit_camera.gd` | `zoom_max` 190 → **38**；`distance` 54.25 → **38**（开局即最远）；`min_distance/max_distance` 这两个旧相容字段同步到 38 与 38，`_cur_distance` 初值 60 → 38 |
| `godot/src/camera/camera_panel.gd` | `_default_distance` 106 → 38、读数占位 38 m、滑杆 `max_value` 占位 190 → 38（`_sync()` 仍每次按 `cam.zoom_min/zoom_max` 覆盖，所以真正的上下限只有一个源） |
| `godot/tests/test_camera_follow.gd` | 原「默认25%」断言改为上限/开局/比例三项；新增「连续往外滚 12 档后仍 = 38」；8 项 → 11 项 |
| `scripts/run_verification.py` | 注册 `visual-camera-zoom`（真实渲染）与 `visual-zoom-framing`（取景对照探针） |
| `godot/tools/capture_camera_zoom.gd` | 新增：真实渲染下限位证据，连续外滚/内滚各 20 档，存 38 / clamped / 9 三张图 |
| `godot/src/bootstrap/main.gd` | `--zoom=` 调试参数在请求超过 `zoom_max` 时先抬高上限再定位（仅调试入口） |
| 19 个证据脚本 | 各自抬高自己的 `zoom_max`，见下表（含 8 个抓图工具、5 个探针/性能档、7 个测试） |

只有一条玩家可见的变化：**能拉到的最远处从 190 m 收到 38 m，且开局就停在 38 m**，之后只能往近处看。
FOV 31°、俯角 22–78°、阻尼、跟随/手动接管、UI 阻断、`pose_lock`、存档字段一律未动。

## 取景工具与证据脚本的处理

上限收紧后，凡是自己摆 40 m 以外机位的脚本都会被 `refresh()/set_distance()` 静默夹回 38 m ——
截图变糊、断言仍绿，是最坏的那种假绿。这些脚本各自在自己文件里加了一行抬高 `zoom_max`
的调用，**玩家上限不受影响**，也只影响证据取景：

| 类别 | 文件 | 需要的机位 |
|---|---|---|
| 抓图工具 | `capture_ocean_pickups` | 100 m |
| | `capture_water_showcase` | 50–68 m |
| | `capture_sea_barrier` | 42–58 m |
| | `capture_sea_style` | 43–45 m |
| | `capture_vegetation` | 95 m |
| | `capture_rooftop_ranch` / `capture_rooftop_ranch_v005` | 46–52 / 95 m |
| | `capture_sunken_city` | 72–190 m |
| 宣传片 | `record_promo` | 72 m |
| 探针 | `probe_water_look` | 46–78 m |
| | `probe_visibility` | 120 m |
| | `probe_panel_dim` | 46 m |
| | `probe_water_layers` | 44 m |
| 性能档 | `profile_vegetation` | 42 / 95 m |
| 测试 | `test_submerged_street` | 88–118 m |
| | `test_submerged_neighborhood` | 54–70 m |
| | `test_submerged_water_light` | 47–73 m |
| | `test_fishery_environment` / `test_fishery_production` | 43 / 45 m |
| | `test_atmosphere` | 42 m |
| | `test_corner_notebook` | 62 m |
| | `test_home_lighting` | 54 m |

`capture_route_ripple` 不使用超限机位，只把注释里的「默认视距 54.25」改成 38。

`godot/src/bootstrap/main.gd` 的 `--zoom=` 调试参数同步补了上限联动：显式要求更远时先抬高
`zoom_max` 再 `set_distance`，避免「参数写了 78、实际被夹到 38、看起来却正常」。

## 验证

| 检查 | 结果 | 证据 |
|---|---|---|
| `camera` | PASS，exit 0，`[camera-follow] 11 checks, failures=0` | `sea-work/verification/20261105-183037-zoom38-final-dca469/camera.log` |
| `visual-camera-zoom` | PASS，exit 0，`[camera-zoom] 14 checks, 0 failures`（真实渲染 1280×800） | 同上 |
| `visual-sunken-city` | PASS，exit 0，`[sunken-city-render] 124 checks, 0 failures` | `sea-work/verification/20261105-185239-sunken2-b518fd/` |
| `visual-sea-barrier` / `visual-vegetation` / `visual-rooftop-ranch` / `visual-ocean-pickups` | 全 PASS，exit 0 | `sea-work/verification/20261105-185329-clamp3-b93c72/` |
| `visual-submerged-street` / `visual-submerged-neighborhood` | 全 PASS，exit 0 | `sea-work/verification/20261105-185000-clamp2-4bf3c4/` |
| `click` / `visual-title-screen` | 全 PASS，exit 0 | `sea-work/verification/20261105-185637-camfinal-073073/` |

`visual-camera-zoom` 断言：上限=38、下限=9、开局即最远、比例 100%；外滚 20 档后 `distance` 与平滑后的
`_cur_distance` 都仍为 38，相机位置到目标点 < 38.5 m；内滚 20 档仍能到 9 m（证明收紧上限没有把缩放整体压死）。
产物：`camera-zoom-38.png`（开局/最远）、`camera-zoom-clamped.png`（外滚到底）、`camera-zoom-9.png`（最近）。

`visual-sunken-city` 那轮先失败过一次：我把 `main.get("cam")` 写成 `:=` 推断，Variant 推断被工程当作错误
（`Parse Error`），修正为显式 `Node` 类型后 124 项全过。失败轮保留，不用通过轮掩盖。

## 范围外既有失败（本轮未修，不是相机引起）

工作区里有他人未提交的改动（`godot/src/ui/hud.gd` 15:39、`launcher_icon.gd` 15:39、
`play_scope.gd` 15:42、`ocean_sky.tres` 18:00、`sunny_palette_gloss.gdshader`），本次会话 18:11 才开始。
下列失败在这些改动之后就已存在，本轮只记录、未修复：

| 检查 | 失败项 | 判定依据 |
|---|---|---|
| `visual-corner-notebook` | 11 项（菜单展开、笔记翻页、Esc、定位图标、launcher 四入口） | 全为 HUD/launcher 行为；断言与缩放无关 |
| `framework-modules` | `solid and world boundary rejected` | 世界边界由 `play_scope.gd`（15:42）决定，非相机 |
| `visual-atmosphere` / `visual-home-lighting` | 灯光与船体锚点若干项 | 断言是灯光/几何；所用机位 14–54 m 均在上限内被完整尊重 |
| `visual-submerged-water-light` | `World/UnderwaterScenery` 节点不存在 | 场景树缺节点，与相机无关 |
| `visual-fishery` | 渔场建造气泡文案 | UI 气泡，与相机无关 |

判定方法：这些脚本使用的机位（14–54 m）在抬高 `zoom_max` 后都被完整尊重，取景与改动前逐像素同源；
因此新出现的失败不可能来自缩放上限。

## 登记

- 功能文档新增 `SEA-CAMERA-R11`，账本新增对应实施条目，主文档追加同日章节。
- `assets/registry/runtime_resource_inventory.json` 只更新本轮确实改动的三条
  （`orbit_camera.gd`、`capture_sea_barrier.gd`、`capture_sunken_city.gd`）的 bytes/sha256；
  其余既有漂移（`ocean_sky.tres`、`poster_atlas.png.import`、`SEA-SCENE-ORF-ASSEMBLY` 源哈希）
  保持原状未掩盖 —— 那些不是本轮改动，按工程约定不批量更新哈希隐藏未知变更。
- `python3 scripts/check_feature_contracts.py --sync` 后剩余 3 项问题全部属于上述既有漂移。

## 未做

- 未跑跨分辨率手感验收；窗口尺寸变化对 38 m 取景的影响未单独量。
- 未改网页原型 `web/gameplay.js` 的 `maxDistance = baseCameraDistance * 2.25`（约 243 m）。
  两套实现各自独立，网页侧若也要收紧，属另一次改动。
- 抽屉式「远景/最远」预设的按钮文案未改（仍是「远景」，只是现在最远就是 38 m）。

## 仍需主人确认的一处口径

主人截图那一帧（1280×800，浮屋约占画面宽度三成、左上角露出另一栋楼）与 `visual-zoom-framing` 的
**78 m / 90 m** 两档吻合，而与 38 m 明显不符（38 m 下浮屋占画面六成以上）。

旧区间是 9–190 m，面板与 HUD 显示的是**百分比**：「38」在旧区间里对应 `9 + 0.38×181 ≈ 77.8 m`。
也就是说，主人看到的「38」很可能是**缩放百分比 38%**，而不是 38 米。

按主人明确选择，本轮先按 **38 米**落地（`zoom_max = 38.0`）。若本意是 78 m，只需把
`orbit_camera.gd` 的 `zoom_max` 与 `distance` 两处 38.0 改成 78.0，并同步 `camera_panel.gd`
的两处占位值与测试里的三项常量。对照图在
`sea-work/verification/20261105-182711-framing-b4ce04/project/outputs/framing-5425.png / framing-6800.png / framing-7800.png / framing-9000.png`。

## 登记

- 功能文档新增 `SEA-CAMERA-R11`，账本新增对应实施条目。
- `assets/registry/runtime_resource_inventory.json` 只更新本次确实改动的两条（`orbit_camera.gd`、`capture_sea_barrier.gd`）的 bytes/sha256，其余既有漂移（`ocean_sky.tres`、`poster_atlas.png.import`、`SEA-SCENE-ORF-ASSEMBLY` 源哈希）保持原状未掩盖 —— 那些不是本轮改动。

## 未做

- 未跑跨分辨率手感验收；窗口尺寸变化对 38 m 取景的影响未单独量。
- 未改网页原型 `web/gameplay.js` 的 `maxDistance = baseCameraDistance * 2.25`（约 243 m）。两套实现各自独立，网页侧若也要收紧，属另一次改动。
