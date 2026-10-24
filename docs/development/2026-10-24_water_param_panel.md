# 水面参数面板（P 键）

- 日期：2026-10-24
- 功能：SEA-OCEAN（水面渲染）
- 相关：`godot/src/rendering/water_params.gd`、`godot/src/rendering/color_grade_panel.gd`、`godot/tools/check_water_params.gd`、`godot/shaders/water.gdshader`、`godot/assets/materials/water.tres`

## 目标

水面有 50 个还能改的参数，此前只能改 `water.tres` 文本再重启看效果。要求把这些参数搬进游戏里的 P 面板，边拖边看。

## 做法

### 参数清单单独一份

`src/rendering/water_params.gd` 按着色器的 `group_uniforms` 分成 8 组，逐条写中文名、控件类型、范围、步长、量纲、一句说明：

| 组 | 条目 |
| --- | --- |
| 水体 | 浅水色、深水色、深色半程、浅水染色、掠射遮挡、吸收系数（R/G/B）、折射强度 |
| 表面细节 | 几何坡度、法线贴图、贴图尺度、低频/中频/高频纹理 |
| 天空反射 | 天顶色、地平线色、地面色、渐变曲线、日晕、反射强度、菲涅尔指数 |
| 太阳高光 | 太阳方向（X/Y/Z）、高光颜色、高光强度、高光锐度、高光增益 |
| 波纹 | 启用、波纹颜色（带 A）、覆盖率、线宽、消散速度、缩放、单块尺寸（X/Y）、淡出起点/终点、流速、流向 |
| 泡沫 | 浪尖泡沫、泡沫颜色、深度边缘、边缘强度、吃水线色（带 A）、贴边线宽、泡沫外扩、泡沫强度、生灭速度、间隔、贴图重复 |
| 波浪几何 | 总波幅（写在 Water 节点上，每帧由 `water_surface.gd` 同步进材质） |
| 输出 | 曝光补偿、抖动 |

范围直接照抄着色器的 `hint_range`，不另立一套。

### 面板

`color_grade_panel.gd` 原来是单页滤镜面板，现在两页：**滤镜** / **水面**。水面页是滚动列表，每组可折叠，每行「中文名 + 滑杆 + 数值」，颜色用取色器（vec4 带透明度），向量拆成分量滑杆。底部三个键：

- **复位** —— 重新从磁盘读 `water.tres` 取出厂值（`ResourceLoader.CACHE_MODE_IGNORE`，否则拿到的是运行时改过的那份）；
- **复制参数** —— 50 行 `shader_parameter/xxx = ...`，可直接贴回资源或文档；
- **写入 water.tres** —— 见下。

拖动的值记在 `user://water.cfg`，下次启动盖回资源值。只有在真的动过滑块时才写盘，否则「打开看一眼再关掉」就会把当时的值存成一套存档，之后改 `water.tres` 的出厂值会被全部盖住。

### 写回资源：改文本行，不用 ResourceSaver

`ResourceSaver.save()` 试过，不行，三个理由：

1. 存运行时那份材质会把 `u_time` / `u_ripples` / `u_boat` / `ocean_waves` 这些每帧改的临时值一起写进文件；
2. 材质里没有的参数它会写一行 `= null`（实测 `u_time`、`wake_points` 等 8 项），等于往资源里塞垃圾；
3. 它会重排整个文件（format 4 → 3、丢 uid、改顺序），diff 看不出改了什么。

所以改成逐行替换：读出 `.tres` 文本，只重写 `shader_parameter/<key> = ...` 那几行，缺的补在末尾，CRLF/LF 按原样还回去。没动的行一个字节都不变，uid 和手写注释都留着。

### 顺手接线的一个参数

`foam_color` 在 `ocean_foam.gdshaderinc` 里声明了，但 `water.gdshader` 一直把浪尖/船尾泡沫的颜色硬编码成 `vec3(0.96, 0.985, 1.0)`，也就是这个 uniform 是死的。既然要「所有能调的参数」，就把它接上（`mix(color, foam_color, ...)`）。

它是 `source_color`，着色器里拿到的是线性值，所以资源里存的是硬编码值的 sRGB 形式 `Color(0.9822, 0.9934, 1)`，视觉逐像素不变。面板上「泡沫颜色」因此是真能改的。

## 两个坑

### 1. CozyUI 会把调试面板改花

`main.gd` 给整棵树套 `src/ui/cozy_ui.gd`（奶油底 + 圆角 + 珊瑚色按钮）。它把分组标题染成珊瑚色、按钮一律顶到 38 px 高，水面页的密度直接散掉；`ColorPickerButton` 也是 Button，被顶到 38 px。

给 `cozy_ui.gd` 加了 `cozy_skip` 元数据：带这个标记的节点子树整个不碰，面板在 `_ready` 里给自己打上。这样滤镜页和水面页都用自己的深色皮肤（滤镜页原先被 cozy 的奶油色影响，一并修正）。

### 2. `source_color` 的 vec3 存 `Vector3` 会在保存时丢值

面板一开始把 vec3 颜色写成 `Vector3`（沿用资源文件里原来的写法）。读出来数值一模一样，但只要用 `ResourceSaver` 存一次，游戏里就会出现：

```
shader_parameter/body_shallow = null
shader_parameter/sky_top_color = null
```

原因是属性声明类型是 COLOR，值为 VECTOR3，文本序列化时按类型不符处理成 null。`sun_color` 用的是 `Color(...)` 就没这个问题。

所以：**`source_color` 的 vec3 一律存 `Color`**，`water.tres` 里 6 处 `Vector3` 颜色已改成 `Color`；`check_water_params.gd` 增加了一条检查，存成 `Vector3` 会直接报 FAIL。

## 验证

- `godot/tools/check_water_params.gd`：**PASS 50 个参数与着色器一致（另有 20 个豁免）**。它从着色器反读每个 uniform 的类型与 `hint_range`，对清单查「漏项 / 名字对不上 / 类型不符 / 范围或步长不符」，再查资源里每个参数有没有值、`source_color` 是不是存成 `Color`、有没有混进运行时参数。清单少一项就等于玩家调不到，这条检查是防止以后加 uniform 忘了加面板。
- `godot/tools/capture_water_panel.gd`：真实渲染抓三张（水面页顶 / 底、滤镜页），Forward+ 退出 0、无 SHADER ERROR。截图确认 8 个分组、50 个控件全部在位，长列表可滚，数值列与色值不溢出。
- 功能探针（临时脚本，已删）：写值 → 读回 `(1,0,0.5,1)`；节点参数 `wave_scale` 1.75 落到 Water 节点；存盘 → 改值 → 回放正确；复位回到 `(0.128,0.618,0.584,1)` / `wave_scale` 1.0 / `crest_foam_strength` 0.12；写回资源 49 项、文件里无 `= null`、`body_shallow` 仍是 `Color`。
- 水色未漂移：写回/还原前后，同机位开阔水面中位色 `(0,108,150)` 一致。
- `gl_compatibility` 后端跑 150 帧退出 0、无 SHADER ERROR（`foam_color` 接线没有破坏兼容后端）。
- `scripts/check_feature_contracts.py` 仍只剩 `main.gd:1928` `res://outputs` 一项历史遗留 FAIL。

## 遗留

- `water_params.gd` 里 20 项豁免（`water_level`、`u_reverse_z`、`emission_gain`、`shore_*`、贴图采样器、4 条波 / 8 圈涟漪 / 32 个尾迹点的数组）都在脚本头部写了理由。其中 `water_level` 还牵着场景 Water 节点的 Y 与船的吃水，单独调一处会让三者对不上，故不做成滑杆。
- 四条波的方向/振幅/波长仍在 `water_surface.gd` 的 `ocean_waves` 里；面板只给总波幅。需要逐条调波时再考虑加 UI。
- `web/water.js` 原型没有对应面板（网页版没有调试 UI 体系）。
