# 2026-11-09 靠泊热点与缩放区间

两条用户反馈一并处理：

1. **键盘靠岸误报「无法到达该泊位」**（原话：「我明明停在这里，标记都出来了，显示无法到达」，随后更正「不是鼠标操作，是键盘操作」）。
2. **镜头缩放区间**：最远收到「视野 38%」，最近收到「视野 7%」（两张同版本截图）。

## 一、靠泊热点

### 现场

主人把船划到家园泊位旁边，屏幕上两个锚图标都在，按 E 弹「无法到达该泊位」。船离 park 不到 3 米。

### 根因（两条，都实测过）

| # | 根因 | 证据 |
|---|---|---|
| ① | `zone1` 绞盘泊位的 `BoatPark` 落在岸线 0.9 m 缓冲里：实测 `(-9.946291, 1.12, 18.20936)`，`is_open_water()` 判 false。`plan_route_to()` 对落点越界直接返回空 → 这个泊位**每一次**靠岸都必然报「无法到达」 | 探针 `[probe] zone1/salvage park_open=false path=0` |
| ② | 「已经靠妥」的判据要求 `landing_id` 与当前身份一致。键盘划回来的船身份还是上一个泊位，于是掉进规划分支；而「热区」旁路（距离 ≤ 1.0 m 无条件放行）又不查可航，于是**提示出现了、动作必然失败** | 还原旧代码跑新用例：11 项失败，`toast` 正是「无法到达该泊位」 |

附带发现：`is_open_water` 的 0.9 m 外扩是**规划缓冲**，不是物理边界。键盘划船受 `_clear()` 约束进不了缓冲，但 `place_at`（存档恢复、传送、工具）可以把船放进去；一旦进去，任何目标都变成不可达。

### 改法

| 文件 | 改动 |
|---|---|
| `godot/src/navigation/water_navigation.gd` | 新增 `nearest_open_water(x, z, max_radius)`；`plan_route_to()` 起点越界最多抬 `START_ESCAPE = 2.6 m`、落点越界最多抬 `GOAL_ESCAPE = 1.8 m`，抬不出去才返回空 |
| `godot/src/bootstrap/main.gd` | `_landing_data()` 归一化 `boatPark` 到开阔水面（`PARK_ESCAPE = 3.5 m`，缓存按原始值失效）；`_select_landing()` 新增「已在旁边」一档（≤ `DOCK_ADOPT_TOLERANCE = 3.0 m` 且 `_park_glide_clear`）→ 认领身份 + 直滑入位，**不寻路**；`_near_landing_key()` 与它同源；`_sail_to_landing()` 以路径终点为航行目标 |
| `godot/src/building/building_access.gd` | 自建平台 `landing_data()` 用同一条 park 合法化规则，避免标记被 `is_open_water` 过滤掉而按键还能用 |

数字都在代码里标了理由：2.6 m ≈ 一个船宽（船贴岸时不会更远）；1.8 m 是落点允许的最后一小步；3.5 m 是「这个泊位数据确实坏了」的判定线；3.0 m 是「就在旁边」的判定线（旧 1.0 m 太紧，1.6 m 只够判「已靠妥」）。

### 验证

- 新增 `godot/tests/test_dock_hotspot.gd`（31 项），注册为 runner 检查项 `dock-hotspot`：
  全部静态泊位 park 合法（含绞盘泊位）、缓冲内起点仍可规划、泊位旁 2 m 按靠岸不报「无法到达」并最终上岸、已靠妥时直接上下船。
- 改动后：`dock-hotspot` 31/0 PASS，exit0 — `D:/projects/sea-work/verification/20261109-171130-dock-hotspot-r6-f1015c/report.json`
- 改动前（暂存还原 + 关掉 goal 容差）：11 项失败、报「无法到达该泊位」 — `D:/projects/sea-work/verification/20261109-171040-dock-hotspot-baseline3-836e50/report.json`
- 同批回归：`dock-seed`、`board-click`、`interaction-reach`、`interact-focus`、`sea-supply`、`ocean` 全 PASS（`.../20261109-171206-dock-regress-b45638/report.json`）。

### 已知非本轮问题

- `building-ocean` 的 `recipe available aboard` 失败：把本轮四个源文件 `git stash` 后复跑同样失败（`.../20261109-171534-build-ocean-baseline-5dd880/report.json`），与靠泊无关。
- `click` 的 runner FAIL：水下 shader 报 `Unknown identifier: CAMERA_POSITION_WORLD`，测试本身 39 checks / 0 failures；来自工作区里在飞的水下改动。

## 二、缩放区间（SEA-CAMERA-R16）

主人给的两张图读数是 **视野 38%** 与 **视野 7%**，按现行刻度 `d = 9 + pct × (77.8 − 9)` 反解：

```
最近 = 9 + 0.07 × 68.8 = 13.82 m
最远 = 9 + 0.38 × 68.8 = 35.14 m
```

| 项 | 旧 | 新 |
|---|---|---|
| `zoom_min` / `zoom_max` | 9 / 77.8 m | **13.82 / 35.14 m** |
| 显示刻度分母 | `zoom_min`–`zoom_max` | **`zoom_ref_min` 9 – `zoom_ref_max` 77.8**（固定，不随区间走） |
| 两端读数 | 0% / 100% | **7% / 38%**（与主人截图同一套语言） |
| 开局 `distance` | 54.25 m | **27.9 m**（新区间 66%，显示读 27.5%；旧值 54.25 在 9–77.8 里是 65.8%，同一位置） |

刻度不复用区间是有意的：主人用百分比指认机位（11-06 那次是「38 = 77.8 米」），刻度一动，同一句话就换个画面。开局不钉在最远也是 11-05 踩过的坑（一进游戏就是最远、只能往近处看，已推翻过一版）。

验证：

- `camera` 14/0 PASS — `D:/projects/sea-work/verification/20261109-172516-final-dock-cam-9ef8a4/report.json`
- `visual-camera-zoom` 18/0 PASS，真实渲染 1280×800，产物 `camera-zoom-far.png`（35.14 m / 38%）、`camera-zoom-clamped.png`（滚满 20 档仍钉在上限）、`camera-zoom-near.png`（13.82 m / 7%，船在画面内） — `D:/projects/sea-work/verification/20261109-174222-camzoom-fix-5cae98/report.json`
- 取景对照（同一机位、家园主泊位水面，17:52 光照，1600×1000）：`D:/projects/sea-work/evidence/2026-11-09_zoom/boat-open-d14.png`（13.82）、`boat-open-d28.png`（27.9）、`boat-open-d35.png`（35.14）

### 抓图工具自己的两个坑（本轮目检时才发现）

改动本身没动抓图工具，但核对「最近 7%」那张图时发现它拍出来是一整屏空水面，查下去是两个工具侧问题，都已修：

| 现象 | 原因 | 改法 |
|---|---|---|
| 13.82 m 那张几乎全空 | 机位锚在甲板上的一个点 `(0.45, 1.75, -0.65)`，最近档镜头离目标只剩十几米，视线被屋体/檐口吃掉 | 机位改锚**船**（+1.2 m），并按 8 个方位做射线选向，取「相机在水面之上且到船无遮挡」的第一个方位 |
| 更隐蔽：滚完 20 档后 target 被搬走 21 m | 滚轮是「朝光标缩放」，`zoom_action` 会给 `target` 加位移；工具固定传屏幕点 `(540, 337)`，20 档累计把视点拖到 `(-12.98, 6.24)` | 每档锚点改传**目标自己的屏幕位置** `unproject_position(_cur_target)`，缩放只改远近、不搬视点 |

顺带加了两条断言把这两件事锁住：最远/最近档 `船在取景内`（`is_position_in_frustum`）、最近档 `镜头仍在水面之上`。检查数 15 → 18。

## 三、契约与登记

- `assets/registry/runtime_resource_inventory.json` 只刷新本轮真正改过的三行（`bootstrap/main.gd`、`building/building_access.gd`、`camera/orbit_camera.gd`），按各行原有结构写 `sha256`/`bytes`/`previous_sha256`/`hash_history`/`verification`，不改字段集合。其余并行改动的 drift **保留可见**，不做批量刷哈希 —— 与清单 note 里「其它并行改动的 drift 保留不掩盖」一致。
- `docs/generated/feature_index.json` 已重建：旧文件停在更早的主文档状态，缺 `SEA-SUNROOM`/`SEA-SHOP`/`SEA-RESIDENCE` 三个功能，与主文档对不上；重建后 `stale` 告警消失。重建只读主文档与各账本，不写 `GDD_V1.0.md`（主文档哈希前后一致：`5aeaa83cad34`）。
- `python3 scripts/check_feature_contracts.py` 当前 **69 issues，全部是并行改动带来的哈希漂移**（水下 shader 套件、阳光房区域、HUD 角标、若干资产源），与本轮四个文件无关；本轮三行已不再出现在列表里。

## 四、未执行 / 边界

- 没有在真机上手玩键盘靠岸全流程（本轮靠 `dock-hotspot` 用例 + 逐帧驱动验证）；手感（滑入 1–3 m 的观感）仍需主人实机确认。
- `--full-world`、建造组合、潜水与 NPC 全链路未随本轮复验。
- 69 条既有哈希漂移未处理：那是其它在飞改动，不该由本轮代为认证。
- 整体仍 `partial`。
