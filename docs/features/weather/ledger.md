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
