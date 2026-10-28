# 2026-10-28 调色面板的天气/季节预览

[主文档](../../GDD_V1.0.md#sea-ocean) · [机器证据](2026-10-28_weather_preview_context.json)

## 请求

> 这个调试工具，会因为天气多云、晴朗在游戏中不一样的情况下无法直接调整切换效果。

## 根因

三件事叠在一起，表现为「滑杆拖了没反应」：

1. **偏移按三键存，读取只认游戏那一组。** `_offsets` 的结构是 `季节 → 天气 → 时段`，而 `_apply_offsets()` 混合时用的是 `_season` / `_weather`，它们由 `main._setup_daylight` 从 `weather_service.kind` 灌进来。
2. **面板只锁了时刻，没锁天气。** `color_grade_panel._hold_preview()` 调的是 `rig.set_preview(hour)`，季节/天气只用来决定「写进哪个 section」。于是游戏里是晴的时候点「多云」，差值落进 `spring|cloudy|*`，画面还在读 `spring|clear|*` —— 写进去了，但没人读。
3. **当前构建的天气钉死在晴。** `assets/data/weather.json` 是 `{"mode":"fixed","fixed_kind":"clear"}`，`WeatherService.tick()` 在 fixed 下直接 return。所以 `spring|cloudy|*` / `spring|rain|*` 这些偏移在游戏里**永远读不到**，面板是唯一能看见它们的地方 —— 而面板当时也看不见。

季节同理：项目没有季节推进规则，运行时固定 `spring`，面板点「夏」存下的偏移同样是死数据。

## 改法

把「渲染用的上下文」从「游戏实际的上下文」里拆出来一层，和已有的 `_preview_hour` 并列：

| 位置 | 变更 |
|---|---|
| `daylight_rig.gd` | 新增 `_preview_season` / `_preview_weather`、`effective_season()` / `effective_weather()` / `is_previewing()`；`set_preview(hour, season_id, weather_id)` 三样一起锁；`clear_preview()` 三样一起放；`_apply_offsets` 改读 `effective_*` |
| `daylight_rig.gd` | 新增 `weather_offset_count()` / `season_offset_count()`：侧栏给天气和季节按钮打点用 |
| `color_grade_panel.gd` | `_hold_preview()` 三样一起传；`_touched()` 按三个维度分别判「调过没有」；`_refresh_status()` 加尾注 |
| `tools/probe_light_panel.gd` | 44 → 61 项，新增整段「点一下就换渲染上下文」 |
| `tools/check_light_params.gd` | 217 → 221 项，新增天气 id 表三处对账 |

关键约定：**面板绝不改游戏状态。** `_season` / `_weather` 一个字都不动，`weather_service` 也不碰 —— 关面板 `clear_preview()` 一放，画面立刻回到游戏实际的时间和天气。这样调试面板不会在存档里留下「天气被改成多云」的副作用。

```
最终值 = 曲线值(时刻) + Σ(偏移[effective_season][effective_weather][时段] × 权重)
```

## 面板行为变化

- 侧栏点「多云 / 雨 / 夏 / 秋 / 冬」：画面立刻按那一套偏移重新渲染，滑杆显示的是那一段的实际值。
- 三个维度都会打 `·`：知道哪套调过、哪套还是空的。
- 状态栏会多一句尾注，两种情况都会说清楚 —— 两种都会让人误判成「面板坏了」：
  - `预览中，游戏实际 春 / 晴`
  - `这套还没调过`（切过去画面不变是正常的，不是没写进去）

## 实测

| 检查 | 渲染 | 结果 | 退出码 |
|---|---|---|---|
| lighting-params | headless | `[lighting-params] 221 checks, 0 failures` | 0 |
| lighting-panel | headless | `[light-probe] 61 checks, 0 failures`（44 → 61） | 0 |
| daylight | headless | `[daylight] 194 checks, 0 failures` | 0 |
| visual-home-lighting | real | `[home-lighting] 114 checks, 0 failures` | 0 |
| visual-weather | real | `[visual-weather] complete` | 0 |

证据目录：

```text
D:\projects\sea-work\verification\20261028-143057-weather-preview-510bfc
D:\projects\sea-work\verification\20261028-143130-weather-preview-visual-a9c2dd
```

关键几条（探针原样输出）：

```
PASS 面板打开时预览上下文 = 游戏实际天气（clear）
PASS 点「多云」渲染上下文立刻切过去（实际 cloudy）
PASS 游戏实际天气没被面板改掉（clear）
PASS 多云段的滑杆立刻生效（实际 1.11）
PASS 差值存进 spring|cloudy|noon
PASS 晴这一套没被连带写上
PASS 切回晴立刻回到晴那一套（0.70）
PASS 点「夏」渲染上下文切到夏季（实际 summer）
PASS 关面板放掉了预览上下文
PASS 关面板后渲染回到游戏实际季节/天气（spring / clear）
PASS 多云的偏移落盘了（["spring|clear|sunset", "spring|clear|night", "spring|cloudy|noon", "summer|clear|noon"]）
```

最后一条同时证明了三件事：多云段独立成 section、晴段没被污染、季节段独立成 section。

## 过程失败

1. **`godot` 在 PATH 上是个 sh 垫片，Python 直接执行报 `WinError 193`。** `scripts/run_verification.py` 用 `shutil.which('godot')` 取到 `~/bin/godot`（`#!/bin/sh` 包装），`subprocess` 在 Windows 上不能执行它。要显式传真身：`GODOT="I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe"`。这条不影响结论，但会让人以为 runner 坏了。

## 未做

- **天气对画面的实际数值影响仍未加。** 面板现在能预览三套天气各自的偏移，但「阴天该暗多少」这类规则还是空的 —— 三套默认一致，看上去一样。这是原定的下一步，不在本次范围。
- **点「雨」不会出现雨线。** `weather_presenter` 的雨线归 `main` 每帧按 `weather_service` 推送，面板不改它。调色室只管颜色，不预览粒子。
- **游戏本身仍钉死在晴。** 要让游戏真正走到 `cloudy` / `rain` 那两套，得把 `weather.json` 的 `mode` 改成 `cycle`（轮换逻辑本来就在），或者接一个天气开关。这是玩法决定，不顺手改。
- 触控与手柄未验。

## 一句提醒

面板里调好的「多云 / 雨 / 夏」现在存得住、看得见、但**游戏里不会出现** —— 因为游戏天气和季节都还没有推进规则。这套偏移是给天气/季节系统上线时直接接的，不是给现在这一版玩的。
