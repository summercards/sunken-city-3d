# 2026-11-09 水下表面复用水上波场

[主文档中控](../../GDD_V1.0.md#sea-ocean) · [OCEAN 设计](../features/ocean/spec.md) · [OCEAN 账本](../features/ocean/ledger.md) · [模块契约](../architecture/module_contracts.md)

## 1. 目标与范围

用户反馈 55m 抬头画面太脏，希望参考明亮蓝海面动态波光和太阳高光。本轮先查工具与复用路径，不硬做第二套水面。范围只覆盖 SEA-OCEAN 水下表面表现和 A/B 验证，不改海面两套材质、CPU 浮力、Main、shore、布局、Air、Dive FSM、鱼群或120m/水下1m入水口径。

官方资产库已查阅：[BoujieMIT Asset Library #2070](https://godotengine.org/asset-library/asset/2070)。页面标注支持 Godot 4.1+并含 Snell/tools；本地已有相同基础，因此不下载、不安装。商业 4.7 方案不引入，项目不升级 Godot 4.6.3。

## 2. 复用审计结论

### 2.1 水上波场接口

`godot/shaders/ocean_waves.gdshaderinc` 现在提供显式时钟入口 `ocean_sample_at(p, clock)`，原 `ocean_sample(p)` 仍以 `u_time` wrapper 调用。该入口返回高度及 `dh/dx`、`dh/dz`，从而让水下表面与水上几何使用同一波场导数。波公式、`wave_scale` 语义、CPU 浮力和水上材质未改变。

### 2.2 水下共享 include

`godot/shaders/uw_surface_shared.gdshaderinc` 只作为水下适配层：

- 复用 `ocean_waves`、`wave_scale` 和既有 `large_wave_normals`；
- 法线纹理使用约28m尺度，实际居中坡度在 G/B 通道，R 均值约0.995，不把 R 当作 RG 法线；
- 两组 UV 双滚动采样，用于打散重复感，但不把纹理等值线直接切成纸片岛；
- 波脊来自 `ocean_sample_at(world.xz * vec2(.42,.82), clock*.55)` 的导数与正向阈值；
- 颜色是干净蓝底，浅白亮纹只加亮，不乘黑污纹；
- 太阳高光沿水上同导数过滤 exponential lobe，避免未过滤白噪声；不使用硬 Snell 圆窗；
- `underside_wave_light` 与 `underside_sun_light` 独立，供关闭动态波/太阳高光的基准与开启动态 A/B。

水下不直接套用水上原材质的岸线、SSR或深度吸收；`uw_surface_optics` 不再作为“新 surface 仍在调用”的技术口径。旧函数名的兼容历史不能替代新的共享 surface 复用契约。

### 2.3 Surface profile 与模块边界

Session 脱树前只读注入 `ocean_waves`、`wave_scale`、`large_wave_normals` 所需 profile。该 profile 不共享 liveMat，不修改 Main、shore、布局、Air 或 FSM；晚创建材质只消费显式输入，不回写水上状态。既有单 fogpass、140–190m 远景收口、泡/鱼、家园120m水深与水下1m入水保持不变。

## 3. A/B 与验证口径

先以 wave/sun 关闭态验证基础衰减和深度读法，再独立开启波光与太阳高光。这样避免把同 ROI 深度亮纹误算成动态波包，也不把波包失败误判为基础水下可见性失败。验证只签本专项包内的 headless 与 visual 结果，不外推到低端、长时、用户终审、完整物理折射或全局资源门禁。

最新专项包：

`D:/projects/sea-work/verification/20261109-183519-underwater-surface-packets-verified-0cd7f3`

- headless：179/0；
- visual：473/0；
- 结论：专项包验证通过，最终整合与录制尚未完成。

## 4. 失败历史与修正边界

以下历史保留，不改写为最终通过：

1. 初始夹具类型 Parse 失败；
2. shader helper 使用 `CAMERA_POSITION_WORLD`，发现其不是可用的全局变量，改为显式参数传入；
3. 法线切岛密集初版 visual 473/0，计数通过但目检不合格，保留该视觉否决；
4. 波包版 visual 473/2，原因是 shader 字符串过窄，并把同 ROI 的深度亮纹污染到波包判断；
5. 后续测试改为关闭 wave/sun 验证基准衰减，同时保留动态波与太阳的独立 A/B，不以基准通过掩盖动态表现待审。

## 5. 既有失败和未签范围

- 不借用旧 4834 签署作为本轮水下波面结论；
- 不把 headless 179/0 或 visual 473/0 外推为最终整合、录制或整工程通过；
- 不签低端设备、长时/连续性能、用户终审、完整物理折射或全局资源门禁；
- 不修改海面原波公式、CPU浮力、水上材质、Main、shore、布局、Air、FSM、泡/鱼和120m/水下1m边界。

## 6. 最终验收与动态预览

主批：`D:/sea-visual-check/verification/20261109-185449-underwater-surface-reuse-signed-6d7336/report.json`。原水上海面伴随回归：`D:/projects/sea-work/verification/20261109-185519-surface-wave-compatibility-683760/report.json`。

| 入口 | checks | failures | 环境 |
|---|---:|---:|---|
| visual-underwater-experience | 475 | 0 | Vulkan Forward+，92张专项PNG与72帧预览 |
| underwater-experience | 179 | 0 | headless |
| sunroom-underwater | 85 | 0 | headless |
| dive-control | 396 | 0 | headless |
| dive-maps | 338 | 0 | headless |
| dive-transition | 226 | 0 | headless |
| visual-dive-maps | 350 | 0 | 十图真实渲染 |
| ocean（--visual） | 148 | 0 | 原海面浮力/波场/尾迹/岸线实机回归 |
| 合计 | **2197** | **0** | 8入口均exit0/PASS、unexpected_errors=[] |

11份本轮运行与测试文件同签署副本逐字节一致。Godot4.6.3/Vulkan1.4/Forward+/RTX4060Ti，1280×800。未修改水上原波公式，`ocean_sample`仍以相同u_time运行原式，CPU浮力/船只导航及主场景未改。

### 6.1 55米仰视数据与目检

- 生产式机位XZ(0,-35)周围95个建筑记录，深度55m、72°FOV，另有XZ(-260,-260)开阔对照机位；不是把机位移到水面上冒充水下。
- 55m海面ROI mean luminance=0.433972，浅蓝亮纹占14.23%，其中71.46%位于太阳中心排除区之外，分布覆盖9个分区；近全白比例0。旧墨青脏斑改为干净蓝面和断续浅白波脊。
- 55m clock0→4实际变化385573像素（53.37%），mean_abs_rgb=0.09394；波光开关变化210469像素/peak0.49804，太阳高光开关231473像素/peak0.58431，均以相同日照强度独立测试，不用昼夜替代高光。
- FlatNormal非null中性纹理与真实GB纹理差分、恢复原纹理复拍、原水面开关、5/30/70/115m及灰实体深度衰减全部通过。衰减基准关闭移动亮纹与太阳，动态两项另行独立验；保留既有灰实体单调递减阈值。
- 逐图审阅20m clock2、55m clock0/2/4、70m仰视、wave-off、sun-off和第三人称预览首尾帧。初版纹理等值线产生纸片岛的做法被否决，最终波脊按既有海面波包坡度生成，没有恢复硬Snell圆盖。现有10条深度遮挡光柱继续使用，本次未新增光柱或宣称重现参考图全部体积光。

### 6.2 动态预览

`D:/projects/sea-work/outputs/underwater-surface-reuse-20261109/surface-motion.mp4`：1280×800、18fps、72帧、4秒，H264/yuv420p，约1.02MiB。来源为同一实机渲染器按固定表现时钟输出的55m第三人称帧序列，角色/楼体/鱼/气泡保留。不是AI视频，也不是玩家连续操控录像；只用于复核波光和高光实际运动。

### 6.3 全局门禁与未签范围

已运行`check_feature_contracts.py --sync`：exit1、69issues，43features/1037source assets/1422runtime hashes，主要资源hash漂移；有问题时派生索引不写，未批量重签未知资产。只读复查亦exit1、69issues；全局登记未通过，不称派生索引已成功同步。GDD与Ocean规格账本、模块契约、新记录均CRLF且无CRCRLF；限定diff --check通过。

本轮水面专项通过，不升级为全工程发布通过。低端GPU、长时性能、完整昼夜天气、用户美术终审、完整物理折射与全局资源门禁未签。参考图的光束数量/美术密度不作为已达到承诺；本轮交付重点是复用现有海面后的蓝色波光与太阳高光，最终由用户审阅。

交付目录：`D:/projects/sea-work/outputs/underwater-surface-reuse-20261109/`，含运动预览、20/55m实拍、波光/太阳独立关闭对照、原始报告与像素数据。上方FINAL PENDING为过程状态，当前以本节结果为准。
