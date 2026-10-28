# SEA-WEATHER · 天气

[主文档中控](../../../GDD_V1.0.md#sea-weather) · [独立账本](ledger.md)

设计修订：r2（2026-10-27）。所属系统：生活。世界时间与天气分别拥有独立状态，通过装配层组合显示。

## 设计条款与验收标准

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-WEATHER-R01 | 晴、多云、雨由独立服务拥有；支持明确天气命令、周期轮换和只读查询，不修改其他玩法状态。 |
| SEA-WEATHER-R02 | 天气随机流、当前类型和剩余周期存档；不同 tick 分段与读档后演化一致，离线冻结。 |
| SEA-WEATHER-R03 | 显示层消费天气和日照查询；海面显示雨线；昼夜交给独立光照驱动，水下抑制屏幕天气，不覆盖海水材质或灯光调参。 |
| SEA-WEATHER-R04 | 天气与生产系统仅经接口协作，未设计的产量、浇水与危险天气效果不得暗中生效。 |
| SEA-WEATHER-R05 | 天气屏幕层仅绘制雨线，不画全屏色块、不写灯光或海水参数；真实昼夜由SEA-OCEAN的DaylightRig消费同一世界时间驱动。 |

## 所有者、接口与数据

唯一所有者：**WeatherService / WeatherPresenter**。

- [godot/src/weather](../../../godot/src/weather)
- [godot/assets/data/weather.json](../../../godot/assets/data/weather.json)

`configure(config)` 设置 duration_seconds（默认240秒）与 seed（默认3701）；`tick(delta)` 推进；`set_weather(kind)->bool` 拒绝未知类型；`query()` 返回 kind/label/rain/cloud/remaining；`changed(snapshot)` 通知；`paused` 由会话暂停管理。WeatherPresenter.present 消费数值并绘制。

表现层只消费天气查询；夜色由DaylightRig输出，原screen_tint/night_amount接口退役。

快照 `weather` 包含 kind、remaining、seed、duration。使用确定性随机序列，剩余时间不会读取系统墙钟。WeatherPresenter 仅绘制屏幕氛围；天气规则不访问 Farm、Inventory、Main、HUD 或海水材质。

## 当前实现与待完成边界

已提供基础天气系统和晴/云/雨氛围；体积云、粒子风雨、季节、风浪和生产效果属于后续内容。本阶段 implemented 不表示跨平台视觉已完整验收。

昼夜表现已接到独立光照驱动；天气仍不施加生产效果。云量目前是规则查询，体积云与风暴光照未制作。

## 2026-10-28 天气作为光照调参分类

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-WEATHER-R06 | 晴/多云/雨作为 P 面板光照页的配置分类，每种天气各存一套分时段偏移；`daylight_rig` 订阅 `weather_service.changed`，天气切换立即换用对应偏移，不新增天气视觉规则。 |

本轮只做**调试入口与存档分组**，不发明「阴天该暗多少」这类数值。天气对画面的实际影响仍是原有 `weather_presenter` 的屏幕层，生产加成仍未启用。

[本轮交付](../../development/2026-10-28_daypart_lighting_panel.md)。

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-WEATHER-R07 | 面板打开期间，天气既是偏移写入分组也是渲染上下文：点「多云 / 雨」画面立刻按该天气的偏移重新渲染，`WeatherService` 的 kind、剩余时间、随机流与存档快照一律不被面板改写；关面板恢复游戏实际天气。当前构建 `weather.json` 为 `mode=fixed`，`cloudy` / `rain` 两套偏移在游戏内不可达，面板预览是它们的唯一入口。 |

[本轮交付](../../development/2026-10-28_weather_preview_context.md)。


## 2026-10-28 天气固定为晴

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-WEATHER-R07 | 当前版本天气为**固定晴**，不随游戏时间自行轮换；`weather.json` 的 `mode` 为 `fixed` 时 `fixed_kind` 决定唯一天气，`tick` 不消耗周期、不产生随机切换。轮换路径保留在同一服务内，仅由配置切换，不另立第二套天气规则。 |
| SEA-WEATHER-R08 | 存档 `version=2`：旧档（无版本或 `version<2`）里的 `kind` 来自已退役的随机轮换，固定模式下读档必须落到 `fixed_kind`，不得把旧档里的「雨」带回来；`version=2` 存档显式设定的天气正常恢复。 |

改法：`weather_service.gd` 增加 `fixed` / `fixed_kind`，`configure` 读 `mode`，`tick` 在固定模式下直接返回；`to_dict` 写 `version`，`from_dict` 按版本决定是否沿用旧 `kind`。屏幕层（`weather_presenter.gd`）与光照分类（R06）未改：晴天下 `rain=0`，雨线自然不画。

[本轮交付](../../development/2026-10-28_dock_seed_weather_asset_fix.md)。

## 验收入口

通过统一 runner 执行 `framework-modules framework-integration daylight visual-weather`，自动隔离玩家存档。`daylight` 断言光照与屏幕层的数值契约（R05），`visual-weather` 沿预设表七个关键帧（06:00/09:00/12:00/15:00/18:00/21:00/00:00）各留一帧真实渲染证据。测试种子准备由 runner 自动配对。真实渲染与逻辑测试分别登记。详见[模块接口约定](../../architecture/module_contracts.md)和[本轮记录](../../development/2026-10-28_daylight_sleep.md)。
