# SEA-WEATHER · 天气

[主文档中控](../../../GDD_V1.0.md#sea-weather) · [独立账本](ledger.md)

设计修订：r2（2026-10-27）。所属系统：生活。世界时间与天气分别拥有独立状态，通过装配层组合显示。

## 设计条款与验收标准

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-WEATHER-R01 | 晴、多云、雨由独立服务拥有；支持明确天气命令、周期轮换和只读查询，不修改其他玩法状态。 |
| SEA-WEATHER-R02 | 天气随机流、当前类型和剩余周期存档；不同 tick 分段与读档后演化一致，离线冻结。 |
| SEA-WEATHER-R03 | 显示层消费天气和日照查询；海面显示阴云/雨线/夜色，水下抑制屏幕天气，不覆盖海水材质或灯光调参。 |
| SEA-WEATHER-R04 | 天气与生产系统仅经接口协作，未设计的产量、浇水与危险天气效果不得暗中生效。 |

## 所有者、接口与数据

唯一所有者：**WeatherService / WeatherPresenter**。

- [godot/src/weather](../../../godot/src/weather)
- [godot/assets/data/weather.json](../../../godot/assets/data/weather.json)

`configure(config)` 设置 duration_seconds（默认240秒）与 seed（默认3701）；`tick(delta)` 推进；`set_weather(kind)->bool` 拒绝未知类型；`query()` 返回 kind/label/rain/cloud/remaining；`changed(snapshot)` 通知；`paused` 由会话暂停管理。WeatherPresenter.present 消费数值并绘制。

快照 `weather` 包含 kind、remaining、seed、duration。使用确定性随机序列，剩余时间不会读取系统墙钟。WeatherPresenter 仅绘制屏幕氛围；天气规则不访问 Farm、Inventory、Main、HUD 或海水材质。

## 当前实现与待完成边界

已提供基础天气系统和晴/云/雨氛围；体积云、粒子风雨、季节、风浪和生产效果属于后续内容。本阶段 implemented 不表示跨平台视觉已完整验收。

## 验收入口

通过统一 runner 执行 `framework-modules framework-integration visual-weather`，自动隔离玩家存档。测试种子准备由 runner 自动配对。真实渲染与逻辑测试分别登记。详见[模块接口约定](../../architecture/module_contracts.md)和[框架交付记录](../../development/2026-10-27_modular_framework.md)。
