# 2026-10-23 · 交接泡沫：移植生产版卡通水面的 ContactFoam

[主文档](../../GDD_V1.0.md#feature-control) · [水面账本](../features/ocean/ledger.md) · [水面功能文档](../features/ocean/spec.md) · [水面渲染说明](../../godot/OCEAN_RENDERING.md)

## 来源与目标

用户提供 `stylized_water_prod_2026-10-23.zip`（`demos/stylized_water_prod/`），要求「分析这套水材质的使用方法，将和物体交接的部分用这个来表现」。

该包是一整套水面材质：深度透射、天空 Cubemap 反射、太阳高光、涟漪网络、以及**交接泡沫（ContactFoam）**。本项目的 `water.gdshader` 早前已完全对标网页版 `water.js`（体色写 `EMISSION`、不吃光照），整包替换会退回「写实、生硬光影」的老问题，因此只取交接泡沫这一层。

包的完整用法、参数表和偏离理由已写入 [godot/OCEAN_RENDERING.md](../../godot/OCEAN_RENDERING.md) 的「交接泡沫：移植生产版卡通水面的 ContactFoam」一节，此处只记录决策与证据。

## 决策

1. **不引入包的离线烘焙流程。** 包用编辑器工具把选定障碍网格与固定水位平面的交线烘成 R16F 符号距离场（默认 0.08 m/格）。本项目 `src/rendering/shore_distance.gd` 每次启动已经把可见几何与 1.12 m 水位平面的交线烘成 1536² 距离图（R 米制距离、G 实体尺寸系数，约 0.133 m/格），同类数据、已有重建入口 `Water.rebuild_shoreline()`。因此只移植着色器层，不加工具、不加纹理、不改资产路径。
2. **只替换交接带。** `ocean_foam.gdshaderinc` 删除 `shore_rim`（圆环描边 + 两道同心弧线）与 `shore_foam`（三层外扩涟漪），交接带统一由新的 `shaders/contact_foam.gdshaderinc` 负责；`shore_height`（岸浪几何位移）、`crest_foam`（浪尖白斑）、船尾迹与 `contact_edge` 保留。
3. **水线改米制现算。** 包把约 0.05 m 宽的实白水线画在条带自身前 5% 的 V 里，而我们的距离图是 0.133 m/格——实测整条带落进第一个 texel 被插值抹平，画面里交接带直接消失（见「过程证据」）。因此水线用 `contact_rim` 按真实米数现算（`contact_foam_rim_width`，默认 0.24 m），条带只供中间与外侧的侵蚀泡沫。
4. **给 V 加世界噪声。** 距离图的等距台阶会把条带读成一条条偏置弧线（`v_paint`），加 ±0.10 的世界噪声扰动后读作手绘。

## 实施

- 新增 `godot/shaders/contact_foam.gdshaderinc`：`contact_rim`（米制水线 + 两档噪声手绘起伏）、`contact_ring`（外推开口环，程序模式）、`erode_contact_pattern`（5 次 `textureGrad` 的 `min` 侵蚀）、`contact_foam_texture`（三段生命周期 `birth/hold/retreat` + `interval` 空档 + `expansion` 向外生长）、`sample_contact_foam` 入口。附带自成套的 `contact_hash/contact_noise`，不依赖宿主着色器已声明 `noise`。
- `godot/shaders/ocean_foam.gdshaderinc` 精简为：轮廓距离读取、`shore_height`、`foam_grain`、`torn_shape`、`cartoon_ribbon`、`contact_edge`（兜底，强度 0.28）、`crest_foam`。
- `godot/shaders/water.gdshader` 引入新 include，交接带单独用 `contact_foam_color` 上色后再叠其余白沫，便于把交接带调得比船尾迹更冷一档。
- `godot/assets/materials/water.tres`：新增 `contact_foam_color / rim_width / width / strength / animation_speed / interval_seconds / pattern / repeat_metres`，`edge_strength 0.86 → 0.28`，移除 `shore_foam_strength / edge_thickness / edge_noise_scale`。
- 新增资产 `godot/assets/textures/water/foam_line.png`（2172×724 灰度条带，来自该包），导入参数 `mipmaps/generate=true`、`size_limit=0`、`detect_3d/compress_to=0`，与本项目其他贴图一致。
- 运行资源清单 `/assets/registry/runtime_resource_inventory.json`：刷新 `water.tres` 哈希，新增 `foam_line.png` 条目，状态标为 `third_party_package_source_license_and_registration_pending`（压缩包未附授权声明，未取生产 AssetID）。

## 过程证据（为什么改米制水线）

第一版按包原样接入（条带负责全部，`contact_foam_width = 0.85`）：画面里**完全没有交接带**。原因是最亮的接触带位于条带 V≈0.02–0.09，按 0.85 m 宽度换算即 0.017–0.077 m，而距离图一格是 0.133 m——落在第一个 texel 内被双线性插值抹平。第二版把宽度提到 1.9 m 后条带出现，但表现为「雾状白糊」；再补上米制 `contact_rim` 与 V 噪声后才有清晰的米制水线 + 断裂侵蚀泡沫。最终 `contact_foam_width` 定在 1.15 m、外圈衰减 0.10→0.74（归一化距离）：2.4 m 在整机位下会把条带笔画拉成一圈散乱白线，收到 1.15 m 后泡沫只贴着实体。

## 验证

统一入口：`python3 scripts/run_verification.py visual-sea-style ocean selftest --label contact-foam-final`，全部在工程外副本和独立用户目录运行。

- 证据目录：`../sea-work/verification/20261023-224951-contact-foam-shipped-320d74/`。`visual-sea-style`、`ocean`、`selftest` 均退出 0、通过；真实退出码与日志哈希见 [验证摘要](2026-10-23_water_contact_foam_verification.json)。
- 后端覆盖：Forward+（Metal）与 `--rendering-driver opengl3`（gl_compatibility，即 Web 导出后端）均无 SHADER ERROR，两个后端都能看到交接带。`textureGrad` / `textureSize` 在两个后端可用。
- 目视覆盖：默认机位 `godot/outputs/godot-preview.png`（1440×900）、近景 `--zoom=16 --look=1,1.12,3`，以及 `visual-sea-style` 的 harbor / channel / aqua / fish / fish-later 五帧。近景确认水线贴合实体、粗细起伏自然、外圈有断裂的侵蚀泡沫，开阔水面不出现乱白点。
- 只签署本机 Metal Forward+ 与 gl_compatibility；移动端后端未签。

## 遗留

- `foam_line.png` 的授权未核验，正式发行前需补齐或换成自制条带。
- 条带沿水线用固定世界斜投影（`0.73x + 0.68z`）取 U，长直墙段会出现方向相关拉伸——这是包本身已知的限制，未在我的移植中修复；若要消除需要引入沿轮廓弧长坐标（当前距离图不含该信息）。
- `foam_line.png` 是 2172×724 无损且带 mip，运行时约 6 MB 载荷 + mip；若后续要压体积，可降采样到一半并用 `contact_foam_repeat_metres` 补偿。
