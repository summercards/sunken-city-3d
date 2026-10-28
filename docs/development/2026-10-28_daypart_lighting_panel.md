# 2026-10-28 P 面板分时段光照调参

[主文档](../../GDD_V1.0.md#sea-ui) · [机器证据](2026-10-28_daypart_lighting_panel.json)

## 请求与续接范围

续接 Codex 会话「Retry disconnected request」（thread `01a18089`）里被额度中断的那一轮。原请求：

> 游戏内的调试工具P键，需要把每个时段的效果的参数页分开。在边上，后期还要增加不同天气的效果调试，不同季节的。应该按照季节-天气-时间段 这样的进去。保存后会直接覆盖当前时间段的效果数值。不影响其它的效果和天气变化动态逻辑。

中断时只完成四次只读探查，方案已定但未落一行代码。本轮从零实现，并补齐探针、回归与账本。

## 设计要点（为什么是差值）

最关键的一条：**偏移存的是差值，不是绝对值。**

`daylight_presets.gd` 里每个时段是一组关键帧，`sample()` 在关键帧之间做 `smoothstep` 插值，这就是「傍晚一路渐暗」这类动态的来源。如果把某一段直接拍成绝对值，段内的插值就被抹平了 —— 17:00 到 18:30 会变成一条水平线，正是主人说的「影响天气变化动态逻辑」的反面。

差值叠加在**本帧已经算好的值**上：

```
最终值 = 曲线值(时刻) + Σ(该时段偏移 × 平滑权重)
```

- 段内偏移恒定，曲线的形状原样保留；
- 段间用 `Slots.slot_weights()` 做 `smoothstep` 混合，**和明暗曲线共用同一条曲线**，所以偏移不会在段边界突然出现或消失；
- 不碰 `daylight_rig._base`（09:00 基准），所以不出现「调了夜里白天也变」；
- 不碰 `weather_service`，天气推进与 `changed` 事件不受影响。

## 新增与修改

| 文件 | 变更 |
|---|---|
| `godot/src/rendering/daylight_slots.gd` | 新增。18 个组合（4 季 × 3 天气 × 8 段）的槽位表、`slot_at`、`slot_weights`、section 编解码、`verify()` 自检 |
| `godot/src/rendering/daylight_rig.gd` | 新增分时段偏移层：`set_offset` / `offset_count` / `erase_slot` / `natural_of`、`_apply_offsets`、预览锁、`light_slots.cfg` 读写；`_scene_read`/`_scene_write` 扩到 sky 与 water 四类目标 |
| `godot/src/rendering/light_params.gd` | 新增 `TARGET_SKY` 与「天空盒」分组 7 项，清单由 30 项增至 37 项 |
| `godot/src/rendering/color_grade_panel.gd` | 三页都显示侧栏；光照页天空盒可调；水面 9 项改走偏移；滤镜页对比度改走偏移；`_sync_light`/`_sync_water`/`_capture_values` 改读「这一段实际值」 |
| `godot/src/bootstrap/main.gd` | `_setup_daylight` 订阅 `weather_service.changed`，天气一变就换一套偏移 |
| `godot/tools/probe_light_panel.gd` | 22 → 44 项。补天空盒写入、水面按段隔离、对比度不被覆盖 |
| `godot/tools/check_light_params.gd` | 172 → 217 项。补时段表对账、sky 分组属性与出厂值核对 |
| `godot/tests/test_home_lighting.gd` | 旧断言「P 改基准、夜里读基准」改为「P 改选中时段、夜段不受影响」 |


## 时段怎么分

直接由 `daylight_presets.gd` 的 `PRESETS` 关键帧 label 推导，不手抄第二份真相：

| 时段 | 代表时刻 | 覆盖区间 |
|---|---|---|
| 深夜 | 00:00 | 00:00–05:30 |
| 黎明前 | 05:30 | 05:30–06:00 |
| 清晨 | 06:00 | 06:00–07:00 |
| 上午 | 07:00 | 07:00–11:00（平顶段，整段同一偏移） |
| 正午 | 12:00 | 12:00–14:12 |
| 下午 | 14:12 | 14:12–17:00 |
| 夕阳 | 17:00 | 17:00–19:00 |
| 黑夜 | 19:00 | 19:00–24:00 |

`check_light_params.gd` 的 `Slots.verify()` 会盯着这张表和预设表的 label：改了预设忘了改这里，当场报红。这条是防「几个月后没人记得」的那根断言。

## 覆盖范围：28 项随时段走的参数

第一版只覆盖了光照页那 12 项，主人追问「影响整个时间画面的是不是水面参数也会变化」后补齐。**答案是会变，而且必须变**：

`water.gdshader` 是 `ALBEDO = 0` + 纯 `EMISSION` 输出，一个像素都不接收灯光。海水色、天空反射、太阳高光这 9 项就是海面**唯一**的亮度来源。不让它们跟时段曲线走，夜里建筑全黑了、海还是一片亮青色 —— 那是整幅画面里最假的一块。

| 层 | 项数 | 具体项 | 分时段可调 |
|---|---|---|---|
| 太阳 | 6 | 强度、颜色、角径、阴影浓度、高度角、方位角 | ✅ |
| 环境 | 7 | 环境光、环境光色、天空亮度、雾色、雾受光、雾及天空、对比度 | ✅（对比度在滤镜页） |
| 天空盒 | 7 | 天顶色、地平线色、地面底色、地面地平线、天空曲率、日晕锐度、日晕角径 | ✅ |
| 水面 | 9 | 天顶色、地平线色、地面色、日晕强度、太阳色、太阳方向、高光强度、浅水色、深水色 | ✅（太阳方向除外） |

水面页里**不**随时段走的（波形、泡沫、吸收、涟漪、网格细分等材质参数）保持全局。原因很简单：它们不参与昼夜曲线，`DaylightRig` 从不写它们。

## 顺带修掉的两个同源问题

### 水面页其实一直在改基准

`_water_write` 原本对归昼夜装置管的 9 项调 `rig.adopt("water", key, ...)` —— 改的是 09:00 基准。所以在「水面」页把夕阳的海调成金色，白天正午深夜会一起变。这跟光照页那个毛病同源，只是藏得更深（水面页的滑杆看起来确实动了，因为基准一变整天的海都变了）。

现在这 9 项走 `set_offset`，与光照页同一套。

`sun_direction` 例外：它是向量，且每帧由 `water_sun_direction()` 按太阳弧算出来。给它记偏移等于跟弧线打架，`set_offset` 直接拒收。

### 滤镜页的对比度其实一帧就失效

```gdscript
"contrast":
    _env.adjustment_contrast = v      # 旧实现，直接写
```

但 `DaylightRig._apply_env` 每帧都做：

```gdscript
_env.adjustment_contrast = lerpf(float(base["adjustment_contrast"]), 1.0, night)
```

拖到 1.42，画面只闪一帧就回到曲线值。现在改走偏移，探针里有一条专门的回归断言：「对比度改完跑过一帧仍在 1.42」。

曝光 / 亮度 / 饱和度不归昼夜装置管，仍是全局 —— 它们改的是整幅画面的最终调色，本来就不该分段。


## 面板行为

- 侧栏挂在主面板**左缘之外**，独立挂在 root 上，由 `_process` 每帧跟随主面板 `position`。不并进主面板做横排：`island_presenters` 用 `Cozy.place(..., right=true)` 直接把主面板定位到右侧，容器里的横排会被这次定位撕开（实测侧栏留在屏幕最左、主面板跑到最右，中间隔半屏）。只连 `resized` 信号也不够，实测侧栏会停在旧位置压住主面板左缘。
- 侧栏与主面板间距 34 px = 视觉缝隙 10 + 主面板纸张外扩 `Cozy.PAPER_OUTSET` 24。少了那 24，侧栏右缘会被纸压住。
- 侧栏打 `island_label` 标记让 `Cozy.style_tree` 跳过整棵子树：它会染色但不会把每个按钮顶到 44 px（十五个按钮就是 660 px，800 高窗口装不下）。皮肤自己按奶油+墨字画，和主面板一致。
- 按钮宽度必须显式给：`SIZE_EXPAND_FILL` 只影响分配，不参与最小尺寸计算。只写 `custom_minimum_size = (0, h)` 会让 GridContainer 算出 0 列宽，按钮被压成窄条（第一版就是这样，季节按钮竖成一条）。
- 打开面板时先站到当前游戏时刻对应的时段，再把画面锁到该段代表时刻 —— 拖滑杆看到的是「这一段长什么样」，不是 09:00 的基准。
- 关闭面板立即放掉预览锁，游戏时间照常走。
- 已调过的时段按钮前显示 `·`，翻回去对比时找得到。
- 复位只清空当前组合，其它时段不连坐。

## 收藏与复位的语义

- 收藏（`water_presets.cfg`）存的是**当前选中那一段实际显示的一套**（`_water_scene_read`）。用基准值存会在别的时段套用时凭空多出一截偏移。
- 套用收藏时，归昼夜装置管的项写成偏移，所以「套到别的时段」等于「让这一段看起来像收藏的那一段」；材质参数照原样直接写。
- 水面页的「出厂（材质文件）」对归昼夜装置管的项 = **清掉这一段自己加的偏移**，回到曲线本身。写成「把曲线值当目标值」会存出一个非零差值，看着像被动过。

## 存档

`user://light_slots.cfg`，section 为 `季节|天气|时段`，键为 `target__prop`（`/` 换成 `__`，避免 ConfigFile 把键名当路径解析）。

旧的 `user://filter.cfg` 里 `[environment]` / `[sun]` 两段不再读写。**文件保留不删** —— 那是用户自己调出来的数，不该被我这边清掉；只是分时段之后「全局基准」这个概念已经由偏移取代。

## 当前实测

全部由 `scripts/run_verification.py` 在 Autoload 前隔离用户数据，真实渲染与 headless 分开记录。

| 检查 | 渲染 | 结果 | 退出码 |
|---|---|---|---|
| lighting-params | headless | `[lighting-params] 217 checks, 0 failures`（37 参数：环境 19 + 太阳 11 + 天空 7） | 0 |
| lighting-panel | headless | `[light-probe] 44 checks, 0 failures` | 0 |
| daylight | headless | `[daylight] 194 checks, 0 failures` | 0 |
| visual-home-lighting | real | `[home-lighting] 114 checks, 0 failures` | 0 |
| visual-weather | real | `[visual-weather] complete` | 0 |
| modules | headless | 通过 | 0 |
| framework-modules | headless | 通过 | 0 |
| minimum-loop | headless | 通过 | 0 |
| ocean | headless | `checks=141 failures=0` | 0 |
| decorations | headless | `1589 checks, failures=0` | 0 |

证据目录：

```text
D:\projects\sea-work\verification\20261028-135829-daypart_final-0abf35
```

关键几条断言（探针原样输出）：

```
PASS 打开面板站在当前时段「上午」（实际 morning）
PASS 夕阳段没有被上午的改动染上（实际 0.30）
PASS 夕阳太阳本来就比上午弱（0.30 < 0.54）
PASS 切回上午还是 1.23（实际 1.23）
PASS 上午存的是差值 0.690（实际 0.690）
PASS 清空偏移后回到基准（0.54）
PASS 复位回到场景出厂太阳强度（0.54）
PASS 上午的偏移被清空
PASS 夕阳的偏移没被连坐
PASS 天空盒地平线色真写进材质（ff4d19）
PASS 正午的天空没被夕阳的改动染上（9cc9d6）
PASS 浅水色真写进着色器（ff380f）
PASS 正午的海水没被夕阳的改动染上（26bab0）
PASS 对比度改完跑过一帧仍在 1.42（实际 1.42）
```

「ff4d19 写进去 / 9cc9d6 留在正午」和「ff380f 写进去 / 26bab0 留在正午」这两组是最好的证据：同一个参数在两个时段各是各的，没有串味。

## 过程失败

1. **`loading` 阶段 `Variant` 推断编译失败**：`var coerced := _coerce_light(...)` 与 `var touched := ... and int(...)` 触发「从 Variant 推断类型」警告当错误，`lighting-params` 与 `lighting-panel` 双双 exit=124。改为显式 `: Variant` / `: bool`。
2. **侧栏被甩到屏幕最左**：第一版把侧栏和主面板套进一个 `HBoxContainer`，但 `Cozy.place` 直接改主面板的 `position`，容器被这次定位撕开。改为独立挂载。
3. **侧栏不跟随**：只连 `resized` / `item_rect_changed` 时侧栏停在旧位置，压在主面板左缘上。改为 `_process` 每帧跟随。
4. **侧栏深色底压深墨字**：沿用调试面板的深色皮肤时，`Cozy.style_tree` 把字染成 `#625744`，深墨压深底等于看不见。改为奶油皮肤并让 `style_tree` 跳过整棵子树。
5. **侧栏按钮被压成窄条**：`custom_minimum_size = (0, h)` 让 GridContainer 算出 0 列宽，季节按钮竖着排成一条。改为按 `SIDE_W` 显式算列宽。
6. **天空盒核对脚本 exit=124**：`ProceduralSkyMaterial` 是 RefCounted，`free()` 会报 `Can't free a RefCounted object`。去掉那两处调用。
7. **探针在 headless 下 exit=124**：设了 `SEA_SHOT_DIR` 时无条件 `await RenderingServer.frame_post_draw`，而 headless 永远不发这个信号。日志里全是 PASS，退出码却是超时 —— 最容易误判成通过的一种。加 `DisplayServer.get_name() != "headless"` 判断。
8. **`visual-home-lighting` 旧断言失败**：原测「P 改的是 09:00 基准、夜里读到的还是基准」。分时段之后面板不再动基准，这条断言随实现一起改 —— 保留原意（「改一段不影响另一段」），换成三条更精确的断言。

前七项都是本轮新代码自己的错，不是历史遗留。第 8 项是语义变更，已在账本条款里写明。

第 7 项值得单独记一笔：**exit=124 但日志全绿**是这个 runner 最容易骗人的失败形态。判通过的依据必须是「退出码 0 且有完成标记」，不能只看日志里有没有 FAIL。


## 未做

- 季节只有配置分类，没有推进规则（项目本来就没有季节系统）。四季的偏移都能存，等季节系统上线直接接上。
- 天气对光照的**实际数值影响**（阴天压暗多少、雨天降多少饱和）没有新增 —— 主人的原意是「后期还要增加不同天气的效果调试」，本轮只把调试入口和存档按天气分好组，不发明天气的视觉规则。
- `sun_direction` 不可按时段调：它是向量，且每帧由太阳弧算出来，记偏移等于跟弧线打架。
- 触控与手柄未验。

## 遗留的接口不一致（未在本次修）

`daylight_rig` 有三处读「基准」的旧口子：`base_of()`、`adopt()`、`_write_base()`（写回资源时用）。分时段之后，`adopt()` 已经没有调用方了 —— 面板两处（光照页、水面页）都改走 `set_offset`。留着不删是因为 `_write_base()` 还依赖同一套 `_base` 结构，删 `adopt()` 不会简化什么，反而让「写回资源」那条路径看起来和面板断了联系。

如果后续要收口，方向是让「写回资源」也走偏移：资源文件存曲线基准，偏移存 cfg，两者不互相污染。

