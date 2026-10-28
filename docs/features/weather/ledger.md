# SEA-WEATHER · 天气 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-weather) · [功能文档](spec.md)

## 登记头

```json
{
  "feature_id": "SEA-WEATHER",
  "status": "implemented",
  "owner": "WeatherService / WeatherPresenter",
  "code_paths": [
    "godot/src/weather",
    "godot/assets/data/weather.json"
  ],
  "verification": [
    "framework-modules",
    "framework-integration",
    "daylight",
    "visual-weather"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-WEATHER-R01 | 已实现 | [本轮专项记录](../../development/2026-10-27_modular_framework.md) |
| SEA-WEATHER-R02 | 模块确定性与跨进程恢复通过 | [本轮专项记录](../../development/2026-10-27_modular_framework.md) |
| SEA-WEATHER-R03 | 真实渲染晴天/雨夜及接口检查通过 | [本轮专项记录](../../development/2026-10-27_modular_framework.md) |
| SEA-WEATHER-R04 | 本阶段只提供查询，不施加生产效果 | [本轮专项记录](../../development/2026-10-27_modular_framework.md) |
| SEA-WEATHER-R05 | 屏幕夜色退役，真实光照接管 | [本轮实测](../../development/2026-10-28_daylight_sleep.md) |

## 当前接口清单

`configure(config)` 设置 duration_seconds（默认240秒）与 seed（默认3701）；`tick(delta)` 推进；`set_weather(kind)->bool` 拒绝未知类型；`query()` 返回 kind/label/rain/cloud/remaining；`changed(snapshot)` 通知；`paused` 由会话暂停管理。WeatherPresenter.present 消费数值并绘制。

快照 `weather` 包含 kind、remaining、seed、duration。使用确定性随机序列，剩余时间不会读取系统墙钟。WeatherPresenter 仅绘制屏幕氛围；天气规则不访问 Farm、Inventory、Main、HUD 或海水材质。

## 资源归属

本次使用程序绘制氛围，未新增或虚构美术 AssetID。后续天气贴图、声音从[资产总入口](../../../assets/registry/README.md)登记相应分账本。

## 遗留与下一步

已提供基础天气系统和晴/云/雨氛围；体积云、粒子风雨、季节、风浪和生产效果属于后续内容。本阶段 implemented 不表示跨平台视觉已完整验收。

## 变更记录

- 2026-10-27：从时间/天气规划拆分独立所有者、配置、快照和验证入口；原时间 R01–R03 保持条款承接；新增天气 FeatureID。
- 2026-10-27：模块测试、跨进程存档和真实渲染证据见[交付记录](../../development/2026-10-27_modular_framework.md)。
- 2026-10-27：屏幕氛围层重做（R05）。旧实现 `(1-daylight)×0.32` 线性曲线配 `Color(0.08,0.15,0.30)` 蓝色叠加，开局 08:00 即有 0.16 压暗、18:00 后一路 0.32、雨天再叠 0.06，整幅画面永久带一层发蓝的灰。改为三次方曲线 + 近黑色偏 + 上限 0.24，白天严格归零；阴云项改为只乘 daylight。新增 `weather-tint` 专项把数值契约变成会失败的断言。详见[本轮记录](../../development/2026-10-27_weather_screen_tint.md)。
- 2026-10-28：天气成为光照调参的配置分类（R06）。`daylight_rig.set_scene_context(season, weather)` 由 `weather_service.changed` 驱动，三种天气各存一套分时段偏移。天气规则、种子、剩余时间与生产效果均未改。详见[本轮记录](../../development/2026-10-28_daypart_lighting_panel.md)。
- 2026-10-28：面板可在游戏天气为晴时预览多云/雨那一套偏移（R07）。修的是「点多云画面不变、滑杆像死的」——`_apply_offsets` 原来只读游戏实际天气，而 `weather.json` 是 `mode=fixed`，`cloudy|rain` 的 offsets 在游戏里永远读不到。现在面板经 `DaylightRig.set_preview(hour, season, weather)` 接管渲染上下文，`WeatherService` 一个字不改，关面板一次放掉三项。详见[本轮记录](../../development/2026-10-28_weather_preview_context.md)。

## 2026-10-28 天气作为光照调参分类

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-WEATHER-R06 | 已实现；`changed` 订阅在 `main._setup_daylight`，天气切换只换偏移不换规则 | `daylight` 194项 + `visual-weather` 真实渲染 |
| SEA-WEATHER-R07 | 已实现；面板点选即切渲染上下文，游戏天气状态不被改写，关面板恢复 | `lighting-panel` 61项（44→61）+ `lighting-params` 221项（天气 id 表三处对账） |


## 2026-10-28 天气固定为晴

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-WEATHER-R07 | 已实现；`mode=fixed`，`fixed_kind=clear`，`tick` 不轮换 | `dock-seed` 1 项断言（固定不变、无雨线） |
| SEA-WEATHER-R08 | 已实现；旧档雨不沿用，v2 存档可恢复显式天气 | `dock-seed` 2 项断言 |

接口变化：`configure` 新增 `mode` / `fixed_kind`；`to_dict` 增加 `version`。其余查询与信号未改，`framework-modules` 的 tick 分段/恢复断言仍通过。

[本轮记录](../../development/2026-10-28_dock_seed_weather_asset_fix.md)。
