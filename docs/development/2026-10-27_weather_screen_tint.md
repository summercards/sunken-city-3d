# 2026-10-27 画面那层发暗的蒙版

[主文档总目录](../../GDD_V1.0.md#feature-control) · [天气功能](../features/weather/spec.md) · [天气账本](../features/weather/ledger.md)

## 用户反馈

画面有一层很暗的蒙版。

## 定位

不是后处理滤镜，也不是 P 面板的调色，而是 `godot/src/weather/weather_presenter.gd` 里一张全屏 `draw_rect`。它挂在 `main.gd::_setup_calendar` 建的 `WorldWeather`（`layer = 0`）上，盖在 3D 之上、所有 UI 之下，所以只压暗世界，不压暗界面。

原式：

```gdscript
draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.15, 0.30, (1.0-daylight)*0.32 + clouds*0.06))
```

两处都给画面加了灰：

1. **蓝色叠加而不是压暗。** CanvasItem 混合是 `c' = c·(1-a) + tint·a`。tint 是深蓝，等于给每个像素抬一个蓝色底噪，纯黑被抬到 `0.15a`，暗部不再是暗部 —— 观感就是「蒙了一层脏玻璃」。
2. **线性曲线在白天就有值。** `daylight = sin((hour-6)/12·π)`，开局 08:00 恰好是 0.5，于是开局就有 `0.16` 压暗；`day_length_seconds = 1200`，8 分 20 秒后进 18:00，之后连续 10 分钟都是 0.38（雨天再加 0.06）。玩家实际看到的大部分时间都落在最暗那一档。

## 实施

只改屏幕氛围层本身，不碰灯光、水材质和环境资源 —— `SEA-WEATHER-R03` 明确禁止表现层覆盖灯光调参，P 面板写进 `world_env.tres` / `main.tscn` 的值必须是画面最终值。

| 项 | 旧 | 新 |
|---|---|---|
| 夜色曲线 | `(1-daylight)×0.32` 线性 | `(1-daylight)³×0.24` 三次方 |
| 夜色色偏 | `Color(0.08,0.15,0.30)` 深蓝 | `Color(0.06,0.09,0.16)` 近黑 |
| 夜色上限 | 0.32（雨天 0.38） | 0.24 |
| 阴云项 | `clouds×0.06`，白天无条件 | `0.05×clouds×daylight`，夜里不叠 |

几个时刻的新旧对照：

| 时刻 | daylight | 旧 alpha | 新 alpha |
|---|---|---|---|
| 08:00 开局 | 0.50 | 0.16 | 0.03 |
| 12:00 | 1.00 | 0 | 0 |
| 16:00 | 0.87 | 0.04 | 0.002 |
| 20:00 | 0 | 0.32 | 0.24 |
| 22:00 雨 | 0 | 0.38 | 0.24 |

三次方是关键：`daylight > 0.6` 的时段（约 09:50–16:10）新值为 0 附近，白天彻底干净，只在真正接近天黑时才起来。

新增三个纯查询供验证直接断言，不必从截图反推像素：`night_amount()`、`screen_tint()`、`cloud_amount()`。

## 验证

全部经 `scripts/run_verification.py`，独立用户目录，未触碰真实存档。

| 专项 | 结果 | 证据 |
|---|---|---|
| `weather-tint` | PASS，10 项断言 0 失败 | `sea-work/verification/20261027-232319-verification-fb2163/weather-tint.log` |
| `visual-weather` | PASS，三帧渲染 | 同目录 `project/outputs/weather_clear{,_dawn}.png`、`weather_rain.png` |

`weather-tint` 断言的内容：正午底色为零、开局 ≤0.04、深夜等于上限且 ≤0.26、夜色各通道 <0.2、入夜过程单调不减、阴云正午 ≤0.05、雨夜不被二次压暗、水下抑制。

像素复核（水面区域采样，避开 UI）：

| 帧 | 水面均 RGB | 相对晴天 |
|---|---|---|
| `weather_clear`（12:00 晴） | 138.4 / 168.1 / 143.3 | — |
| `weather_clear_dawn`（08:00 晴） | 135.1 / 164.0 / 140.5 | −2.2% |
| `weather_rain`（20:00 雨） | 112.3 / 136.6 / 121.6 | −19% |

−19% 与 `alpha 0.24` 的混合预期 `c·0.76 + tint·0.24` 吻合（绿通道 168→133 预期，实测 137）。

## 未改动与未解决

- **夜色仍只是屏幕层，不是真夜晚。** 日照查询目前只驱动这张叠加色和左上角日历文字；`Sun`、`OceanSky`、`WorldEnvironment` 都不随时钟变化，所以 20:00 是「正午光照 + 24% 压暗」，读得出变暗，读不出时间。真昼夜要求装配层按日照驱动太阳朝向与能量、天空亮度，那会与 P 面板写进资源的调参值互相覆盖，属独立设计条目，已写入 spec「当前实现与待完成边界」。
- **HUD 的模态遮罩没动。** 开面板时另有一层 `hud.gd:87` 的去色 18% + 压暗 12%，是刻意的模态反馈，`NO_DIM_PANELS` 已把调色面板排除在外。
- **`framework-integration` 有一处既有失败，不是本轮引入。** `godot/tests/test_framework_integration.gd:45` 取 `record.pickups.crates[0]`，隔离存档里该数组为空，报 `Invalid access of index '0'`。`git show HEAD` 同位置即为该行，未包含本轮任何改动。因此本轮的断言放在独立专项 `weather-tint` 里，不依赖它。
- 网页原型 `web/` 没有对应的屏幕夜色层，不涉及。
