# 两套水面的发光增益分开拟合（2026-10-25）

## 起因

`1be5063` 起新增了吸收式水面（`water_absorption.gdshader` + `water_absorption.tres`），
P 面板可以「原版 / 吸收式」切换。两套材质共用 `main.gd` 的 `_runtime_water_params()`，
于是也共用了同一个 `RenderFlagsLib.water_emission_gain()`。

昨天刚按原版着色器把系数重拟合成 `(1.26, 1.26, 1.26)`。吸收式那套的发光量级比原版
亮一档多，同一个系数必然顾此失彼：真渲染实测，吸收式在 `gl_compatibility` 下只有
`11 / 75 / 123`，Forward+ 是 `24 / 185 / 196`，误差 65.4，切过去明显发暗发灰。

## 量法

沿用 `tools/capture_water_gain_probe.gd`（这一轮加了 `SEA_SCHEME` 选方案、`r/g/b`
逐通道写法），两后端各扫一遍，`scripts/measure_water_backend_parity.py` 比色。

先扫标量：2.2 / 2.5 / 2.8 / 3.1 / 3.4，最优在 2.5，但误差仍有 17——

| gl gain | 实测水色 | 误差 |
|---|---|---|
| 2.2 | `13 / 148 / 207` | 19.77 |
| **2.5** | `17 / 167 / 222` | **16.95** |
| 2.8 | `57 / 183 / 232` | 23.41 |

绿偏低、蓝偏高，方向相反 ⇒ 标量救不了，需要逐通道。再扫三组：

| gl gain (r/g/b) | 实测水色 | 误差 |
|---|---|---|
| **2.5 / 2.8 / 2.0** | `21 / 184 / 194` | **2.39** |
| 2.55 / 2.85 / 1.95 | `24 / 187 / 191` | 2.47 |
| 2.6 / 2.9 / 1.9 | `31 / 189 / 188` | 6.57 |

取 `(2.5, 2.8, 2.0)`。

## 改动

- `godot/src/rendering/render_flags.gd`：`water_emission_gain(scheme := "original")`
  按方案返回；吸收式 `(2.5, 2.8, 2.0)`，原版仍是 `(1.26, 1.26, 1.26)`，Forward+ 一律 `Vector3.ONE`。
- `godot/src/bootstrap/main.gd`：注册方案的循环把方案 id 传进 `_runtime_water_params()`。
- `godot/tools/capture_water_gain_probe.gd`：支持 `SEA_SCHEME` 与 `r/g/b` 逐通道档位。
- `scripts/measure_water_backend_parity.py`：档位标签不再假定是单个浮点。

## 验证

端到端用 `capture_water_schemes.gd`（不覆盖增益，走面板切方案的真实链路）在两后端
各跑一遍，同机位比开阔水面像素：

| 方案 | Forward+ | gl_compatibility | 误差 |
|---|---|---|---|
| 原版 | `1 / 105 / 147` | `10 / 102 / 146` | 4.21 |
| 吸收式 | `24 / 185 / 196` | `20 / 184 / 194` | 2.75 |

其余：`[schemes] 复原后方案=original 控件数=60`，两后端均退出 0、无 SHADER ERROR；
`--selftest` 537 passed；`run_verification.py ocean` PASS；`check_feature_contracts.py`
PASS 31 features / 236 source assets / 220 runtime hashes / 0 issues。

## 未做

- 仍只在本机（Apple M1，Metal 3.2）实测，Web 实机与移动端 GPU 未覆盖。
- `web/water.js` 依旧没同步这两套方案。
- 三张水面贴图授权仍是 pending。
