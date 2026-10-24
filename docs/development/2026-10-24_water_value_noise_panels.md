# 水面体色多边形：值噪声改梯度噪声（2026-10-24 第二轮）

## 问题

上一轮已放宽三处阈值带并加 1 LSB 抖动（见 [2026-10-24_water_banding_seam](2026-10-24_water_banding_seam.md)），俯视开阔水面仍能看到大块明暗不一的板块，边界是长直边，像水面被切开拼接。用户怀疑某张贴图没有做成四方连续。

## 排查

1. **贴图不成立。** 水面这条渲染路径只绑了四个采样器：`screen_tex`、`depth_tex`（都是屏幕空间，不产生图案）、`contact_foam_pattern`（仅岸线接触带）、`shore_distance`（仅岸线距离场，材质里 `shore_enabled = false`）。水面是 `ALBEDO=0` 的纯 emission，没有平铺贴图，也没有法线贴图。
2. **对截图做低频提取。** 784×563 的截图里绿通道全域只在 106–125 之间，绝大部分是 107–117；把低频分量拉伸到全范围后，剩下的是一张典型的多边形拼图。也就是振幅只有 3–4 级，但形状是硬边的。
3. **按同样公式复现值噪声。** 用 Python 实现 `hash()` 值噪声 + `f*f*(3-2f)` 插值 + 三层倍频，生成的图案与截图里的多边形同构：格子内部是双线性插值，等值线近乎直线，格子边界梯度为 0 形成折痕。
4. **两处阈值改成软边并没有改形状。** 上一轮把 `smoothstep(0.44,0.56)` 放宽到 `(0.30,0.70)`，只是把台阶的过渡拉长，等值线依然是直边，反而把「硬切」变成「宽边的硬板块」。

## 改动

`godot/shaders/water.gdshader`：

- 新增 `hash_dir()`（两个 `hash()` 取随机方向，不归一化，省一次 sqrt）与 `gnoise()`（Perlin，quintic fade，C2 连续），`broad()` 由值噪声改为梯度噪声；
- 三层倍频各自旋转 36.87° / 73.7°，避免三套格子共轴叠加；
- 幅度系数 0.89 把新版标准差校准到与旧版一致（0.176 → 0.156），下游所有阈值保持不变；
- `web/water.js` 同步：`broad()` 换梯度噪声，并补上上一轮漏掉的宽阈值（`smoothstep(.20,.80)`、`smoothstep(-.10,.95)`、`smoothstep(.30,.70)`）与输出抖动。

## 验证

工程外副本 `sea-work/manual-water-check/`，新写 `tools/capture_water_shape.gd`：同一场景、同一相机、同一帧序列，只切换 `water.gdshader` / `water_prev.gdshader` / `water_before.gdshader`，每个版本各抓 `surface_contrast=0.26`（出厂）与 `1.0`（4 倍，用于把图案形状暴露到原生对比度可辨）两张。

| 项 | 结果 |
| --- | --- |
| Forward+ 抓图 | 退出 0，无 SHADER ERROR，`[shape] complete` |
| `gl_compatibility` 抓图 | 退出 0，无 SHADER ERROR，图案同样为软边，无多边形 |
| `surface_contrast=1.0` 目视 | 旧版成片硬边多边形板块；新版软边有机斑块，无直边 |
| 出厂 0.26，对比 ×4.2 | 旧版仍能看出板块边；新版只剩缓慢明暗起伏 |
| `node --check web/water.js` | 通过（网页版未在浏览器实拍） |
| `python scripts/check_feature_contracts.py` | 与上一轮相同，仅 `main.gd` 的 `res://outputs` 一项历史遗留 FAIL |

对照拼图：`sea-work/manual-water-check/project/outputs/water-seam-ab.png`（形状）、`water-seam-shipped.png`（出厂对比度）；原图 `sc-{normal,boost}-{old,prev,new}.png`。

## 影响面

- 只改体色图案的形态，不改颜色、亮度、阈值含义与几何；水面之外无改动。
- `noise_grad()`（涟漪坡度）仍是值噪声，但工作频率是 0.2–2 米，只进法线/菲涅尔，不产生大尺度板块。
- 网页版上一轮的宽阈值与抖动从未同步，本次一并补上，两端图案一致；浏览器实拍待补。
