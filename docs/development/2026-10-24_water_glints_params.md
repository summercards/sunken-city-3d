# 水面光点参数化

日期：2026-10-24
范围：`godot/shaders/water.gdshader`、`godot/assets/materials/water.tres`、`godot/src/rendering/water_params.gd`、`godot/tools/capture_water_panel.gd`

## 起因

截图里建筑附近水面上散布的小白点，玩家想调。查下来是 `water.gdshader` 的 `facility-vicinity water glints` 段——不是粒子系统，是片元里按格子哈希出来的点，只长在离岸 0.95~11.8 m 的环带内。整段原来全是硬编码常量，所以只能改代码。

## 做法

抽成 `glints` 组，插在「波纹」之后、「泡沫」之前，10 个参数：

| 参数 | 中文 | 默认 | 范围 |
|---|---|---|---|
| `glints_enabled` | 启用光点 | true | bool |
| `glint_color` | 光点颜色 | (0.88, 0.99, 0.96) | 取色 |
| `glint_strength` | 强度 | 1.0 | 0~2 |
| `glint_density` | 密度 | 0.24 | 0~1 |
| `glint_size` | 点大小 | 1.0 | 0.2~3 |
| `glint_speed` | 闪烁速度 | 1.0 | 0~3 |
| `glint_drift` | 漂移幅度 | 1.0 | 0~3 |
| `glint_twinkle` | 明灭锐度 | 2.4 | 0.5~8 |
| `glint_zone_inner` | 内边界 | 2.2 | 0.5~20 m |
| `glint_zone_outer` | 外边界 | 11.8 | 2~40 m |

## 默认值必须等于改动前

这是本次唯一的硬要求：参数化不能顺手把画面改了。

- `glint_color` / `glint_size` / `glint_speed` / `glint_drift` / `glint_twinkle`：默认值直接写成原来的字面量，乘 1.0、指数 2.4，恒等。
- `glint_density = 0.24` → 判定式 `h1 > 1.0 - 0.24 = 0.76`，与原 `h1 > 0.76` 一致。
- 环带：原式是 `smoothstep(0.95, 2.2, d) * (1 - smoothstep(6.2, 11.8, d))`。参数化成 `smoothstep(inner*0.4318, inner, d)` 与 `1 - smoothstep(outer*0.5254, outer, d)`，两个系数就是精确比值 `0.95/2.2 = 0.431818…`、`6.2/11.8 = 0.525424…`。默认 `inner = 2.2`、`outer = 11.8` 时起点是 0.94996 与 6.19972，与 0.95 / 6.2 差 4e-5 / 3e-4 米，8 bit 输出不可见。
- 末级 `clamp(..., 0.0, 0.88)` → `clamp(..., 0.0, 1.0)`。原上限从未触顶（`glint_sum ≤ 1` × `glint_zone ≤ 1` × 0.86 = 0.86），所以默认输出不变，但 `glint_strength = 2` 才有空间。

## 结构上的两个注意点

- `shore` / `shore_d` 必须留在 `if` 之外。下面的吃水线泡沫用同一份岸线数据，塞进光点块里会编译不过。
- `if (glint_zone > 0.001)` 早退保留了，只是挪进开关内层。开阔海面占大多数像素，两层格子循环是这段最贵的部分。

## 验证

| 项 | 结果 |
|---|---|
| `tools/check_water_params.gd` | `PASS 60 个参数与着色器一致（另有 20 个豁免）` |
| Forward+ 渲染 | 退出 0，无 SHADER ERROR；默认值下光点分布与截图一致 |
| `gl_compatibility` | 退出 0，无 SHADER ERROR |
| 参数有效性 | 同机位 `density` 0.24 → 1.0、`strength` 1.0 → 2.0、`size` 1.0 → 2.2，光点数量与尺寸肉眼可见地变多变大 |
| 面板 | 滚到「水面光点」组，10 个控件全在，出厂值 1.00 / 0.24 / 1.00 / 1.00 / 1.00 / 2.40 / 2.20m / 11.80m |
| `check_feature_contracts.py` | 仅剩 `main.gd:1928` 引用 `res://outputs` 一项历史遗留 FAIL |
| `main.tscn` | 6178 字节未变，没被 `@tool` 烘焙 |

顺带给 `tools/capture_water_panel.gd` 加了一张中段图 `water-panel-mid.png`，按分组标题文字滚过去（不写死像素位置），以后加新组也能拍到。

## 未做

`web/water.js` 里搜不到 glint / mote 相关实现（水面着色器注释提到的 "web build's luminous motes" 在当前网页代码里已无对应），所以网页原型这一段不需要同步。网页版与 Godot 端在其它参数上仍然分叉，那是更早的遗留项。
