# 2026-10-28 · 时间光照与睡觉

[主文档总目录](../../GDD_V1.0.md#feature-control) · [海洋/光照](../features/ocean/spec.md) · [海洋账本](../features/ocean/ledger.md) · [天气](../features/weather/spec.md) · [睡觉](../features/sleep/spec.md)

## 用户要求

> 先去掉这个蒙版，使用真实光照去制作时差效果，要关系很多的色彩光影。原来的数值先保持，不着急做。

两件事：**删掉那张全屏暗色纸**，以及**用真光照做昼夜**；而且**原有美术数值不能变**。

## 一、那张蒙版是什么

不是后处理，也不是 P 面板调色，而是 `godot/src/weather/weather_presenter.gd` 里一张全屏 `draw_rect`，挂在 `WorldWeather`（`layer = 0`）上 —— 盖 3D、在 UI 之下，所以只压暗世界、不压暗界面。

原式：

```gdscript
Color(0.08, 0.15, 0.30, (1.0 - daylight) * 0.32 + clouds * 0.06)
```

三处都错：

1. **蓝叠加不是压暗。** CanvasItem 混合是 `c' = c·(1-a) + tint·a`。tint 是深蓝，等于给每个像素抬一层蓝色底噪，纯黑被抬到 `0.15a`，暗部不再是暗部 —— 这就是「蒙了一层脏玻璃」的成因。
2. **线性曲线在白天就有值。** 开局 08:00 的 `daylight` 恰好 0.5，一进游戏就有 0.16 压暗。
3. **时间和光照无关。** 整幅画面只是盖了张纸，影子方向、水面高光、天空颜色在「夜里」全是正午。

已彻底删除。屏幕层现在只画雨线，并且有源码级断言盯着 `draw_rect` 不许回来。

## 二、真实光照怎么做

新增 `godot/src/rendering/daylight_rig.gd`（`DaylightRig`）作为这批属性的**唯一写入者**，时段表在 `daylight_presets.gd`。

### 「原来的数值先保持」怎么落实

资源文件里的值（`world_env.tres`、`main.tscn` 的 Sun 节点、`water.tres`、`ocean_sky.tres`）**全部原样不动**，它们是 09:00 基准。装置启动时抄成快照，之后每帧输出 `基准 × 系数`，而 09:00 的系数严格为 1.0。

实际校验：`daylight` 专项把 `sun/env/water/sky` 四个目标下每一个被接管的属性逐个比对，09:00 全部回到捕获值（太阳变换用 `global_basis` 整体还原，避免三角往返误差累积）。

### 谁被接了进来

昼夜不是只改一个亮度。这批属性一起动，画面才成立：

| 目标 | 属性 | 作用 |
|---|---|---|
| Sun | `light_energy`、`light_color`、高度角、方位角、`light_angular_distance`、`shadow_opacity` | 影子方向与长度真的会转；黄昏光变软、影子变淡 |
| Environment | `ambient_light_energy`、`ambient_light_color`、`background_energy_multiplier`、`fog_light_color`、`fog_light_energy`、`fog_sky_affect` | 环境光随日出日落明暗与冷暖；雾跟着天色走 |
| 天空盒 | `sky_top_color`、`sky_horizon_color`、`ground_bottom_color`、`ground_horizon_color`、`sun_curve`、`sun_angle_max` | 抬头那片天真会变色；低角度时太阳晕更大更软 |
| 水面 · 反射 | `sky_top/horizon/ground`、`sky_sun_glow`、`sun_color`、`sun_direction`、`sun_highlight_strength` | 水面反射的天空与太阳同步；太阳落了水上不该还有亮斑 |
| 水面 · 水色 | `body_shallow`、`body_deep` | **关键**：水面是 `ALBEDO = 0` + 纯 `EMISSION`，一个像素都不收灯光，不压这几项就会「建筑全暗、海面还亮着」 |

### 面板不再是直接写入者

调色面板（P 键）写的是同一批属性。两边都写就互相覆盖 —— 面板拖完，下一帧被时变乘掉。所以：

- 面板读 `base_of`、写 `adopt`，改的永远是**基准**；深夜把太阳调到 2.0，第二天中午看到的也是 2.0。
- 写回资源文件前先 `suspend()`（把基准铺回场景）再存，`resume()` 收尾。所有失败分支也会走到 `resume`，不会把装置永久停在暂停态。不做这一步，夜里点一次「写入文件」就把夜间的暗值烧进 `.tres`。

## 三、踩过的四个坑（都留了注释）

这几条是这轮真正的成本，记下来免得下次重犯：

1. **太阳朝向读写的约定相反。** 读用 `basis.z`、写按 `-basis.z` 解释（`look_at` 让 -Z 指向目标），差 180°，正午会把太阳甩到场景背后。已统一到面板的约定。
2. **暖色插值把水面弄亮。** 第一版直接 `lerp(暖色, warm)`，而暖色比体色亮 —— 傍晚水面比正午还亮。改成「亮度由环境光+太阳的合成曲线决定，色相单独偏」。
3. **往绿底掺橙 = 灰橄榄。** 浅水体色绿分量到 0.95，直接 lerp 暖色仍是绿主导。改成摘出亮度、用暖色按同亮度重建色相再混回去 —— 亮度守恒，色相由暖色决定。
4. **黄昏的「暖」和「暗」同时发生 = 浑浊。** 落日贴着海平线，光几乎全打在浪面上，那是一天里海最亮的时候之一。加了 `DUSK_WATER_LEVEL` 下限，并把深夜色偏乘以 `(1-warm)`，避免蓝调抵消刚染上的金。

## 四、实测

全部经 `scripts/run_verification.py`，独立用户目录，未触碰真实存档。

**必须逐项跑，不能堆在一次调用里。** `framework-integration`、`minimum-loop`、`save-seed` 三项都要 runner 准备各自配对的存档种子；一次传多个会在同一份隔离目录里互相覆盖种子，表现是一整片 `reject without mutation` 与 `07:00 pickup` 失败 —— 看上去像回归，实际是测试装置串味。逐项跑全部通过。

| 专项 | 结果 |
|---|---|
| `daylight` | PASS，123 项断言 0 失败 |
| `visual-weather` | PASS，七帧真实渲染 |
| `framework-integration`（`--full-world`） | PASS |
| `framework-modules` / `title-screen` / `minimum-loop` / `save-seed` | PASS |
| `sleep-cycle` / `visual-sleep-cycle` | PASS（22 项） |
| `check_feature_contracts.py` | PASS：33 功能 / 429 源资产 / 317 运行哈希 / 0 issues |

证据目录：

```
D:\projects\sea-work\verification\20261028-041648-verification-ec6906
```

水面像素采样（右侧开阔水面，避开 UI 与建筑）：

| 时段 | 水面 RGB | 亮度 | 暖度 R−B | 相对 09:00 |
|---|---|---|---|---|
| 06:00 | 37.7 / 91.2 / 109.3 | 81.2 | −71.6 | 75.9% |
| **09:00** | 24.3 / 126.3 / 158.1 | **107.0** | −133.8 | **100.0%** |
| 12:00 | 19.2 / 134.1 / 167.8 | 112.1 | −148.7 | 104.8% |
| 15:00 | 18.3 / 117.6 / 146.1 | 98.6 | −127.8 | 92.2% |
| 18:00 | 59.8 / 106.6 / 123.0 | 97.8 | **−63.1** | 91.5% |
| 21:00 | 34.5 / 60.0 / 77.7 | 55.8 | −43.3 | 52.2% |
| 00:00 | 34.6 / 59.9 / 77.9 | 55.8 | −43.3 | 52.2% |

这张表读法：

- **亮度拱形正确**：06:00 低 → 12:00 峰 → 21:00 半。
- **18:00 的暖度从 −134 拉到 −63**，是黄昏真的变暖，不是变暗。
- **00:00 与 21:00 的水面亮度接近**；跨午夜连续性另由预设边界测试验证。

## 五、边界与未做

- **开始画面固定 09:00 基准**：标题不推进日历，也不应随时间变色。
- **睡觉（`SEA-SLEEP`）是同一轮引入的独立模块**，串接时钟、角色与 UI，不新增第二份存档时间；详情见 [sleep 契约](../features/sleep/spec.md)。分界是：`WorldClock.wake_to_morning` 是时间唯一写入口，`DaylightRig` 只读时钟输出画面。
- **云量还没接进光照。** 天气已提供 `cloud` 查询，但阴天压暗需要把它作为参数传进 `DaylightRig`；本轮没做。
- **体积云、风暴光照、季节**未制作。
- **网页原型 `web/`** 无对应昼夜层，未涉及。

睡觉的完整需求、输入边界与逐轮日志另见[睡觉交付记录](2026-10-28_sleep_cycle_delivery.md)。
