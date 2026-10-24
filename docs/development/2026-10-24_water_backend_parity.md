# 水面双后端水色对齐（2026-10-24）

## 起因

`96ba2d2` 那批提交把 `water.gdshader` 按生产参考包整体重写，新增 `exposure_comp`
与解析天空反射，发光量级整体上移，但 `RenderFlagsLib.water_emission_gain()` 里的
兼容后端补偿系数还是重做前实测的 `(3.8, 3.8, 2.7)`。

本机把两份提交拉下来、跑真实渲染做验收时暴露出来：`gl_compatibility` 下整片水面
发白，连同沉没建筑一起被冲淡；Forward+ 则是正常的深青。

| 区域（同机位同帧） | Forward+ | gl_compatibility（旧系数） |
|---|---|---|
| 开阔水面 | `1 / 103 / 147` | `170 / 241 / 236` |
| 深水 | `84 / 146 / 142` | `198 / 221 / 186` |

GL 端蓝绿已到 236/241，接近削顶，不是「暗一档」而是过冲。旧注释里「兼容后端比
Forward+ 暗得多」的前提在新着色器上已经不成立。

## 量法

不复用任何历史数值，重新扫一遍：

1. `tools/capture_water_gain_probe.gd` 在同一机位、固定 90 帧预热后，把
   `emission_gain` 逐档设成扫描值再截图，一轮 9 张。
2. 同一脚本跑两遍，一次默认后端、一次 `--rendering-driver opengl3`。
3. `scripts/measure_water_backend_parity.py` 取 Forward+ 的 `gain-1.0.png` 作参考，
   按「蓝通道明显高于红、红 < 40」圈出水面像素并排掉 UI 条带，同一个掩码套到
   每张 GL 图上，算平均色与平均绝对误差。

掩码只取自参考图，所以 GL 偏色再大也是量同一块屏幕区域。

## 结果

参考（Forward+）：`0.9 / 105.0 / 147.4`，水面像素 596879（46.1%）。

| gl gain | 实测水色 | 平均绝对误差 |
|---|---|---|
| 0.6 | `13 / 38 / 57` | 56.45 |
| 0.9 | `12 / 65 / 98` | 33.16 |
| 1.0 | `12 / 76 / 112` | 25.10 |
| 1.2 | `10 / 96 / 139` | 8.80 |
| **1.26** | **`10 / 103 / 147`** | **4.27** |
| 1.32 | `11 / 109 / 154` | 6.90 |
| 1.6 | `10 / 137 / 184` | 25.65 |
| 2.2 | `51 / 185 / 223` | 68.49 |
| 3.8（旧值） | `183 / 240 / 253` | 140.69 |

取 `1.26`。蓝绿两端都落在 3 个色阶内；红通道实测有约 `+9` 的地板（0.3 档时反而
更高，是色调映射曲线的抬升，不是增益能压的），所以三个分量用同一个值，不再像
旧实现那样拆成三档。

## 改动

- `godot/src/rendering/render_flags.gd`：`water_emission_gain()` 的兼容后端返回值
  `(3.8, 3.8, 2.7)` → `(1.26, 1.26, 1.26)`，注释换成新的实测依据。
- `godot/tools/capture_water_gain_probe.gd`（新）：增益扫描探针，`SEA_GAINS` 可覆盖档位。
- `scripts/measure_water_backend_parity.py`（新）：两目录比色，直接打印建议系数。

## 验证

| 项 | 结果 |
|---|---|
| 探针双后端各 9 档真实渲染 | 均退出 0，无 SHADER ERROR |
| 修复后同机位水色 | Forward+ `1/105/148` 对 GL `10/103/147`，误差 **4.0**（修复前 140.8） |
| 双后端面板截图 `capture_water_panel.gd` | 均退出 0，两页面板正常 |
| `capture_water_compare.gd` 出厂/预设复原 | `复原后与出厂一致=true` |
| `tools/check_water_params.gd` | PASS 60 个参数与着色器一致（20 个豁免） |
| `tests` 自检 `-- --selftest` | 537 passed, 0 failed |
| `check_feature_contracts.py` | PASS 31 features / 147 source assets / 219 runtime hashes / 0 issues |

## 未做与须知

- 只在本机（Apple M1，Metal 3.2）双后端实测。Web 实机、移动端 GPU 的色调映射曲线
  未覆盖，同一系数在那边仍可能偏；跨设备验证仍是账本遗留。
- `large_waves.png` 按 VRAM 压缩（`compress/mode=2`）导入，`gl_compatibility` 会报
  `BPTC_RGBA not supported by hardware, converting to RGBA8`。这是运行时一次性转码，
  不影响观感；Web 端本来也要转，内存结果一样，所以没改导入设置。
- `web/water.js` 仍未同步这套参数与着色模型，网页原型与 Godot 端观感继续分叉。
