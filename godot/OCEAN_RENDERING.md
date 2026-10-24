> 技术参考与历史记录。项目管理入口为 [主文档](../GDD_V1.0.md#feature-control)，本主题从 [独立功能文档](../docs/features/ocean/spec.md) 和 [账本](../docs/features/ocean/ledger.md) 进入。下文历史验收只对原记录时点成立。

# 水面、白浪与边缘波纹（2026-10-22）

视觉参考：TechFusion《花了一周在Unity中写的风格化海洋环境渲染》
https://www.bilibili.com/video/BV1TqM76nEWf/

保留并重做白边、海面白浪和船行浪。参考视频中的岸线细白边、向外扩散的弯曲浪线，以及间歇出现、推进后消散的白浪分别由同一水面 Shader 表现。没有在海面摆放白色条带、泡沫贴片或固定描边网格。

## 自动岸线

`src/rendering/shore_distance.gd` 遍历实际可见场景几何（MeshInstance3D / MultiMesh），求三角形与海拔 1.12 米平面的交线，再生成欧氏距离纹理。材质不再使用旧 `shore.json` 中的矩形；旧 JSON 仍供原有导航逻辑使用。

- 合并 GLB 按焊接顶点连通性拆分，避免薄片装饰、旧水花管线等被当成实体岸线。排除高度小于 0.5 米的连通分量、隐藏对象和完全没入水中的对象。
- 1536×1536 RG 浮点纹理：R 为到轮廓的米制距离，G 为附近实体的尺寸系数。小箱子、细柱产生更小的波纹，避免大圆圈包围小物体。
- 覆盖相机平移范围加 24 米边界；当前为 204×204 米，每像素约 0.133 米。每次启动从当前场景重新生成，移动/旋转/更换场景模型后无需手画岸线。
- 运行中主动改动静态场景或水位时，调用 `Water.rebuild_shoreline(roots, region)` 重建。并非每帧重切静态模型；移动船体使用当帧深度交界和实际航迹。

`shaders/contact_foam.gdshaderinc` 负责「水与物体交接」的那一条带：贴合实体的米制白水线 + 由 `foam_line.png` 条带侵蚀出来的中间/外圈泡沫，带「出生 → 保持 → 退去」生命周期（2026-10-23 从生产版卡通水面包移植，见文末）。`shaders/ocean_foam.gdshaderinc` 只剩岸浪几何位移、开阔海面浪尖白斑、船尾迹，以及给细栏杆/缆绳用的极淡深度描边。岸浪同时贡献最多约 2.4 厘米的位移和相应法线，不只改变颜色。

## 海面白浪与材质

- 开阔海面的白浪与主波相位共用方向、色散速度、横向弯曲和时钟。低频空间/时间包络控制出现与消退，不铺满海面，也不是独立漂移的白色斑块。
- 浪头是**有宽度的破碎白斑**（宽带 + 亮核 + 后侧渐薄的水膜），不是一像素描线；40 米外整体淡出，避免远看塌成扁平白斑。
- 白沫使用受场景光照影响的浅色材质、较高粗糙度和较低透射，保留明暗与厚薄层次；不使用白色自发光。
- `water.gdshader` 保留深度吸收、屏幕折射、GGX 高光与天空环境反射。水粗糙度默认 0.13，水/空气 F0 约 0.02037。透射颜色不再被水材质重复照亮。
- 可调参数：`crest_foam_strength`、`foam_color`、`water_roughness`，交接带另见 `contact_foam_*`。

## 对标网页版（2026-10-23，以 `water.js` 为准）

网页版的 `water.js` 是唯一真源：**它的水面完全不参与光照**，是一张
「折射场景 × 透射 + 平涂体色」的合成图。Godot 版早期把体色写进 `ALBEDO`，
于是太阳、环境光、镜面项各自往水面上加东西（竖向渐变、边缘高光、模糊反光块），
再叠加 SSR，整体就比网页版暗一档、也更「写实」。现在改成同样的做法：

```glsl
vec3 color = submerged * transmission + body * (1.0 - transmission);
ALBEDO   = vec3(0.0);
EMISSION = color * exposure_comp * emission_gain;
```

`ALBEDO` 归零 + `SPECULAR` 归零，灯光再怎么变都进不来；`render_mode` **不要加
`unshaded`**——那样 `EMISSION` 会被忽略，gl_compatibility 下更是直接输出黑色。

### 体色照抄网页版（线性值，不是 sRGB）

| | 网页版 / 现在 | 改造前 |
|---|---|---|
| 浅水 | `(0.008, 0.300, 0.250)` | `(0.10, 0.62, 0.58)` |
| 深水 | `(0.008, 0.125, 0.240)` | `(0.015, 0.285, 0.445)` |
| 吸收 /米 | `(0.125, 0.064, 0.046)` | `(0.34, 0.15, 0.075)` |
| 深度过渡 | `smoothstep(2, 13)` 米 | 归一化比尔-朗伯，26 米才饱和 |
| 掠射色 | `(0.16, 0.39, 0.51)` × 0.65 | `(0.44, 0.74, 0.86)` × 0.30 |

`body_shallow` / `body_deep` / `absorption` / `fresnel_color` 都**不能带
`source_color`**：那个 hint 会把数值当 sRGB 再转一次线性，颜色整体再压暗一档
（这是第一次改完水面变墨绿的原因）。对应的 `.tres` 里要写 `Vector3(...)`，
写 `Color(...)` 不生效。

### 校验用的实测色

在 `--zoom=70`（等距视角）下取开阔水面：

| | 目标（网页版） | 现在 |
|---|---|---|
| 开阔水面 | `(0, 112, 156)` | `(0, 112, 160)` |

改完必须这样逐像素核一次，别只看缩略图——`exposure_comp`（0.55）就是按这个值反解出来的。

### 两个后端的色调映射不一样

同一个 `EMISSION` 输入，Forward+ 与 gl_compatibility 出来的像素差得很远
（实测 0.25 线性值 → 212 对 89），而且**蓝通道压缩得更狠**，单标量补偿对不上：
增益 3.0 时绿差 40，增益 4.0 时蓝差 60。所以 `emission_gain` 是 `vec3`，
由 `src/rendering/render_flags.gd` 的 `water_emission_gain()` 按后端给出
（兼容后端 `Vector3(3.8, 3.8, 2.7)`，Forward+ `Vector3.ONE`）。
Web 导出走兼容后端，**改完必须单独用 `--rendering-driver opengl3` 截一张**核对，
否则会出现「桌面正常、网页一片黑」。

### 其余跟着网页版改的地方

- 开阔水面**没有白浪**：`crest_foam_strength = 0`。网页版的白只出现在岸线、
  船首、尾流和点击涟漪上，海面本身是平的。
- 白沫颜色改成网页版的 `(0.96, 0.985, 1.0)`。
- `normal_lighting = 0.40`：网页版的光学法线只由三条低频正弦构成，表面是一张
  带缓慢切面的纸，不是逐道浪脊都有高光。
- SSR 默认关掉（`ssr_mix = 0`），网页版根本没有屏空间反射。
- `shore_distance.gd` 的厚度门限 `0.5 → 0.22` 米：网页版的岸线轮廓来自地块脚印，
  浮台（约 0.3 米厚）也算岸线；不放进来，平台边就只有一侧有白线。
- `shore_rim` 去掉水深门控、改成按实体尺寸（`shore.y`）过滤：站在 10 米深水上的
  平台边没有任何「浅水柱」，用水深判断会把这一侧整条白线抹掉；细栏杆靠尺寸挡掉。

## 吸收模型（2026-10-23 第一版，保留作历史）

> 深水过渡现在由上面的 `depth_near` / `depth_far` 取代，
> `depth_distance` / `beers_law` 已不参与计算，下面这段只解释来路。

参考 <https://godotshaders.com/shader/absorption-based-stylized-water/>，把「按世界深度硬切」换成归一化的比尔-朗伯曲线：

- `depth_distance`（默认 26 米）是「算作开阔海」的水柱深度，`beers_law`（4.2）控制饱和快慢：
  `depth_blend = 1 - exp(-clamp(depth/depth_distance, 0, 1) * beers_law)`。
  旧实现是 `smoothstep(0.6, 12.0, depth)` 选体色、`1 - smoothstep(5.0, 20.0, depth)` 掐掉透射，
  两条近似线性的过渡到 20 米就彻底停了，远水是一片平色。
- 水体基色仍是 `shallow_color → deep_color` 混合后乘 `body_gain`；透射按真实视线路径
  `exp(-thickness * absorption)`，海底随同一条归一化曲线淡出，深水自然溶进体色。
- 掠射角另加一层 `fresnel_color`（`fresnel_radius` 决定这层贴不贴地平线，`fresnel_gain` 是强度），
  水色随视角变浅不再只靠 Schlick 镜面项。
- 波纹从「各向同性噪声团」改成**沿风向拉长**的三层涟漪（横向频率高于纵向），
  浪脊垂直于风向排布；细层按视距淡出以避免闪烁。
- 新增屏幕空间反射：沿反射视图射线步进查深度缓冲，命中不透明表面后取其颜色，权重为
  `(0.30 + 0.70 * 掠射)`：天空环境贴图看不到港区墙体，这一层补的是楼体倒影。
  `ssr_mix = 0` 可直接关掉（运行期跳过整段循环）。

调参优先级：`depth_distance` / `beers_law`（水多快变深）→ `absorption`（哪种颜色先被吃掉）→
`fresnel_gain`（远景水面亮度）；`body_gain` 只整体加减水体权重。
所有可调项都已写进 `assets/materials/water.tres`，可直接在编辑器检查器里改。

## 水线描边与细节层（2026-10-23 收尾）

水面上的白有两套，别混在一起改：

- **岸线白边** `shore_rim(p, thickness)`：按到轮廓的**米制距离**画一条硬切白带
  （`rim` 再过 `smoothstep(0.26, 0.58)`，边缘是画出来的，不是渐变）。宽度随实体尺寸
  （轮廓图 G 通道 `shore.y`）缩放：固定 0.34 米会把细系船柱整根吞掉，看起来像插在水里的白棍。
  新增 `thickness` 门控——轮廓图里混着细栏杆、缆绳这类**游离线段**，没有水柱的像素不画白线，
  否则水面上会浮着一条白条。
- **白沫 / 浪尖** 仍走柔和的 `shore_foam` / `crest_foam`，不做成一像素硬边。

当前数值：`edge_thickness 0.5`、`contact_depth 0.9`、`edge_strength 0.94`、
`edge_noise_scale 5.5`、`crest_foam_strength 0.34`、`shore_foam_strength 1.0`。

### 硬边画法（2026-10-23 二改，按参考案例还原）

参考 shader 的白边不是渐变，而是一条**极陡的 1D ramp**（0→白、0.08→黑）被噪声采样：

```glsl
edge_mask = normalize(texture(edge_ramp, vec2(noise * (1 - edge_blend))).r)
```

- `edge_blend → 1`（贴着物体）时采样点落在 0，整条带是实白；
- 往外 `edge_blend` 变小，噪声把采样点推过阈值，白带被切成手绘一样的碎块。

本项目落在 `ocean_foam.gdshaderinc` 的 `torn_edge(grain, edge_t)`，两个细节必须注意：

1. **阈值不能照抄 0.08。** 参考案例用的是 cellular 噪声（值集中在小值），
   value noise 的均值在 0.5，用 0.08 只能画出一条断断续续的虚线。这里取 **0.19**。
2. **`edge_t` 要用平方曲线**（`1 - t*t`）。线性映射下带宽走三分之一就开始掉白点，
   边缘变成虚线；平方曲线让内半幅保持实白、只把撕裂留给外缘。

另外 `contact_edge` / `shore_rim` 都必须再乘一个 `smoothstep` 收尾，
否则陡峭 ramp 会在**开阔水面**留下约 8% 的白色散点（`edge_t = 0` 时噪声自己就越过了阈值），
看起来像水面上撒了雪。参考案例乘的是 `edge_blend`，作用相同。

### 白带宽度受轮廓图分辨率约束

轮廓图 1536² 覆盖约 204 米，**每 texel 0.133 米**。原先 `width` 用
`clamp(shore.y, 0.30, 1.35)` 缩放，小物件被压到 0.1 米——不到一个 texel，
双线性插值直接把白带抹掉。现在下限提到 0.55，`edge_thickness` 按**米**给（0.5），
白带稳定在 0.28~0.65 米。

`shore_rim` 的 `near_object` 门控原来是 `0.06~0.55` 米，它只放过「像素正下方就是物体」。
浮台外侧那条水面的视线会穿过两三米水才打到沉没的街区，于是整圈白边被误杀——
这是「边缘一直不清晰」的真正原因，不是 ramp 写错了。现在放宽到 `0.10~3.0` 米。

## 波纹去写实化（2026-10-23）

三层各向异性噪声梯度会持续产生光照明暗，这是「像照片」的来源，与白沫、反射无关
（同帧数逐项置零验证过：`crest / shore_foam / ssr / fresnel / refraction` 都不是元凶）。

- 新增 `normal_lighting`（默认 0.55）：只压缩**进入光照的法线**，折射与反射仍用完整 `slope`。
  1.0 时每一道浪脊都有真实的漫反射高光；0.55 时水面接近平涂，只留下折射里的细节。
  这是本项目的「风格化旋钮」——想更写实就往上调。
- 浪尖白沫改成 `torn_shape(patch, 0.74 - 0.06 * on_top)`：
  硬切的实白块，阈值高到只有少数浪尖带白。放在 0.64 时整片开阔水面都是白板。
  `on_top` 的门限也从 `0.150~0.275` 收到 `0.22~0.34`，白沫只出现在真正的峰顶。

### 波纹密度（2026-10-23 三改）

「密度太高」指的是空间频率，不是振幅——调 `detail_*` 只会改强弱，不会减少条数。
两处共同决定海面上有多少条波纹：

1. **涟漪层的频率**（`water.gdshader` 里的 `add_ripple` 第 3/4 个参数，单位是 1/米）：
   `1.55/0.95` → **`1.05/0.62`**，`6.40/4.60` → **`3.60/2.40`**，波长相应从
   4.0/6.6 米拉到 6.0/10 米、0.98/1.37 米拉到 1.7/2.6 米。振幅同步下调（0.052→0.050，0.018→0.015），
   否则波长拉长后单条波纹显得又粗又重。
2. **基础波的短波长两条**（`water_surface.gd` 的 `ocean_waves`，第 4 个分量是波长）：
   `3.8 / 1.9` → **`6.0 / 3.2`**，振幅 `0.035/0.012` → `0.030/0.009`。
   这一条是关键：把这两条振幅置 0 试过，细密横纹立刻消失，说明之前满屏的密纹主要来自 1.9 米那条。

长波长那条（12 米）不动——它提供大起伏和船的升沉，去掉海面就没有体积感了。

细节层重排：`detail_broad 0.40 / detail_mid 0.58 / detail_fine 0.24`。中层涟漪的振幅系数
（0.100 → 0.062）和横向波长（3.20 → 4.60）都下调、拉长，海面从「满屏密纹」变成
「大起伏 + 细纹」，近处不再像磨砂玻璃。

屏幕空间反射加掠射门控 `smoothstep(0.06, 0.42, fres_wide)`：俯视相机下反射射线扎到浮台底下，
采回来的是一整片模糊白色，像水面糊了一块雾。近景权重归零，只有接近地平线的远景才叠楼体倒影。
`ssr_mix = 0` 依旧整段跳过。


## 基础波浪与船行浪

- `World/Water`：连续 257×257 网格，观察目标附近 0.5 米间距，外围逐渐稀疏。四组带横向弯曲和振幅包络的解析波，避免无限长的平行条纹。
- `ocean_waves` 每项为 `(方向 X, 方向 Z, 振幅米, 波长米)`。基础波的 CPU 浮力与 GPU 位移共用参数和时钟。船体采用四点采样计算升沉、俯仰和横摇；自身尾流和微小岸浪未反馈到浮力。
- `World/BoatWake` 只保存最多 64 个世界空间历史点，压缩为最多 32 个 Shader 采样点；尾浪随真实转向弯曲，停止后继续扩散并在 9 秒内消退，传送时清空。
- 尾浪的位移、法线及细白沫都在水面材质中计算，不另画白色尾带。船首有局部肩浪；划桨和停船保留法线涟漪。
- `boat.json` 的七条旧白色装饰管仍不参与显示。鱼群静态双圆环不恢复，玩法交互保留。

## 验证与预览

```sh
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path godot --script res://tests/test_ocean.gd
~/Applications/Godot.app/Contents/MacOS/Godot --path godot --script res://tests/test_ocean.gd
bash godot/verify_surface.sh
~/Applications/Godot.app/Contents/MacOS/Godot --path godot --write-movie outputs/water-upgrade/wave-detail.avi --fixed-fps 30 --script res://tools/capture_wave_detail.gd
~/Applications/Godot.app/Contents/MacOS/Godot --path godot --write-movie outputs/water-upgrade/shore-waves.avi --fixed-fps 30 --script res://tools/capture_ocean.gd
```

### 20 秒水面成片（2026-10-23）

```sh
# 1) 必须先把输出目录建好：--write-movie 不会自己创建，路径写错时它只在末尾报
#    ERR_UNCONFIGURED 就当作写完了（621 帧"成功"但文件不存在）。
mkdir -p godot/outputs/ocean-absorption/movie/seq
# 2) 用 PNG 序列而不是 .avi。AVI(MJPEG) 在这里会写到几个 GB 还停不下来。
~/Applications/Godot.app/Contents/MacOS/Godot --path godot --resolution 1280x800 \
  --write-movie outputs/ocean-absorption/movie/seq/shot.png --fixed-fps 30 \
  --script res://tools/capture_water_showcase.gd
# 3) 前 20 帧是场景预热的静止画面，从第 20 帧起算。
/Users/summercards/.local/bin/ffmpeg -y -framerate 30 -start_number 20 \
  -i godot/outputs/ocean-absorption/movie/seq/shot%08d.png -frames:v 600 \
  -c:v libx264 -preset slow -crf 19 -pix_fmt yuv420p -movflags +faststart \
  outputs/ocean-absorption/water-showcase.mp4
```

`capture_water_showcase.gd` 的机位：`target (4, 1.12, -6)`、`--orbit 0.9,-0.25` 的等效增量、
距离 50→68→52 的缓慢起伏，沿右向缓慢环绕（`_orbit` 每帧给 0.0013 rad 并带 sin 缓动）。
`main.hud.visible = false` + `ribbon.hide()`，画面里只有水面和港区。

专项覆盖：波高/梯度、浮力与导航解耦、尾浪转向/停船/传送、实际网格交线与欧氏距离、模型移动/旋转、隐藏/全浸没对象、MultiMesh 实例变换，以及合并模型内薄片的排除。Headless 的 Dummy RenderingServer 不保留 MultiMesh 实例变换，因此这一项额外用 Metal 实际渲染后端验证。

最新录像为 `outputs/water-upgrade/wave-detail.mp4`（固定镜头观察白浪和岸线）与 `shore-waves.mp4`（航行）。历史 `clean-ocean.mp4` 是误删白沫的迭代，已不代表当前实现。录像固定 30 Hz 离线录制，不能据此推断实时 FPS。

这是风格化解析水面和程序泡沫，不是完整流体求解器；反射来自场景灯光和天空，尚未实现建筑平面镜像反射。P 面板的个人滤镜仍优先，录像使用曝光 1.05、亮度/对比度/饱和度 1.0。独立海底地图不受影响。

## 交接泡沫：移植生产版卡通水面（2026-10-23）

来源：用户提供的 `stylized_water_prod_2026-10-23.zip`（`demos/stylized_water_prod/`）。该包是一整套水面材质（深度透射 + 天空 Cubemap 反射 + 太阳高光 + 涟漪网络 + 交接泡沫），**这里只取「和物体交接」的那一层**：`ContactFoam`。其余部分不接入——本项目的水面已经是自己的平涂合成（体色走 `EMISSION`、不吃光照），换掉会退回网页版之前的状态。

### 包里的用法（要点）

1. 材质赋给一块水平矩形水面网格的 `Material Override`；水面 `Cast Shadow = Off`、`Extra Cull Margin ≥ 0.9 m`，网格要有足够细分支撑顶点位移。
2. 交接泡沫不是靠屏幕深度现算的，而是**离线烘焙一张固定水位二维距离场**：编辑器里选中水面网格 → 菜单执行 `tools/generate_contact_field.gd` → 再选障碍网格/父节点 → 设 texel 尺寸（默认 0.08 m）→ 生成。输出 `水面名_稳定标识_contact_field.res`（R16F 单通道、无 mip、截断 2.0 m，符号距离：实体内部为负）。
3. 工具只往材质写四个技术参数：`contact_field_texture`、`contact_field_mapping`（全局整数格原点 + texel 间距）、`contact_field_valid`，以及一段元数据；艺术参数（颜色/宽度/速度/图案）一律不动。
4. 着色器把世界 XZ 换算成格子 UV：
   ```glsl
   vec2 grid = world_position.xz / contact_field_mapping.zw - contact_field_mapping.xy;
   contact_field_uv = (grid + 0.5) / vec2(textureSize(contact_field_texture, 0));
   ```
5. `ContactFoam` 有两种美术模式，由 `contact_foam_pattern` 是否为空决定：
   - **程序模式**：`边缘线`（贴边、宽度缓慢呼吸）与 `外推环`（从贴边向外推进、用三角波撕成开口弧线）取 `max`。
   - **条形纹理模式**：`foam_line.png` 是一张灰度条带，U 沿水线重复、V 从贴边指向外侧；随生命周期推进把采样半径当作「侵蚀半径」做 5 次 `min` 取样，于是同一张图会**真的被吃掉**而不是整体淡出。
6. 生命周期是显式三段：`birth → hold → retreat`，可选 `interval` 空档；`source_v = v / expansion` 让图案从贴边向外生长。

### 本项目的接入方式

不新开烘焙流程：`src/rendering/shore_distance.gd` 每次启动已经把可见几何与 1.12 米水位平面的交线烘成 1536² 的距离图（R = 米制距离，G = 实体尺寸系数），与包里的固定水位距离场是同一类数据。`shaders/contact_foam.gdshaderinc` 直接读它，因此：

- 不需要编辑器工具、不需要额外纹理、不改变现有资产与场景路径；
- 几何/水位变化后仍旧走 `Water.rebuild_shoreline(roots, region)` 重建，与原来一致；
- 包里的 `contact_field_*` 三个技术参数不引入。

### 一处有意的偏离（重要）

包里那条约 0.05 米宽的实白水线**画在条带自身的前 5% V 里**，而它的距离场是 0.08 米/格。本项目的距离图是 **0.133 米/格**，那条线会落进第一个 texel 里被双线性插值抹平——实测整条交接带直接消失。因此：

- **水线改成米制现算**（`contact_rim`，宽度 `contact_foam_rim_width`，默认 0.24 m，两档世界噪声做手绘粗细起伏），不再依赖条带的前几行；
- 条带只负责中间与外侧的侵蚀泡沫（`contact_foam_width` 默认 1.15 m），它的前几行恰好落在同一位置，两者叠起来仍读作一条带；
- 另外给 V 加了世界噪声扰动（`v_paint`），否则距离图的等距台阶会显成一条条偏置弧线。

`ocean_foam.gdshaderinc` 里原来的 `shore_rim`（圆环描边 + 两道同心弧线）与 `shore_foam`（三层外扩涟漪）**已删除**，交接带统一由 `contact_foam` 负责。保留 `contact_edge` 作为细栏杆/缆绳的兜底（距离图会排除竖向厚度 < 0.22 m 的实体），强度降到 0.28，只留一层极淡内晕。

### 参数

| 参数 | 默认 | 作用 |
| --- | --- | --- |
| `contact_foam_color` | `(0.93,0.99,0.97,1)` | 交接泡沫颜色与整体不透明度；A=0 关闭该层 |
| `contact_foam_rim_width` | `0.24` | 米制水线宽度，必须大于距离图 texel（0.133 m） |
| `contact_foam_width` | `1.15` | 侵蚀泡沫的外扩范围（米），0 只留水线 |
| `contact_foam_strength` | `1.0` | 整体强度 |
| `contact_foam_animation_speed` | `1.0` | 泡沫自身生命周期速度（不影响波浪） |
| `contact_foam_interval_seconds` | `0.5` | 一轮结束后的额外空档 |
| `contact_foam_pattern` | `foam_line.png` | 留空/1×1 则退回程序模式 |
| `contact_foam_repeat_metres` | `5.0` | 条带沿水线的世界重复尺度 |

条带沿水线用固定的世界斜投影（`0.73x + 0.68z`）取 U，这是包里已知的方向相关拉伸限制，未改动。

### 资产与授权

`godot/assets/textures/water/foam_line.png`（2172×724 灰度，无损、生成 mip）来自该包，导入参数与本项目其他贴图一致（`mipmaps/generate=true`、`size_limit=0`、`detect_3d/compress_to=0`）。**该压缩包未附授权声明**，因此运行资源清单里登记为 `third_party_package_source_license_and_registration_pending`，未取生产 AssetID；正式发行前需要补齐授权或替换为自制条带。

### 验收

- Forward+ 与 gl_compatibility（Web 导出后端）均无 SHADER ERROR，两个后端都能看到交接带。
- `python3 scripts/run_verification.py visual-sea-style ocean selftest`：全部退出 0。`ocean` 仍覆盖波高、浮力、尾浪、距离场与薄片排除；`selftest` 537 项通过。
- 近距离（`--zoom=16 --look=1,1.12,3`）确认水线贴合实体、粗细起伏自然、外圈有断裂的侵蚀泡沫，开阔水面不出现乱白点。

## 调参面板（P 键「水面」页）

按 P 打开调试面板，两个页签：滤镜 / 水面。水面页顶部先选方案（原版 / 吸收式），原版列 60 个参数，按着色器的 `group_uniforms` 分 9 组（水体 / 表面细节 / 天空反射 / 太阳高光 / 波纹 / 水面光点 / 泡沫 / 波浪几何 / 输出），每组可折叠；吸收式方案是另一份 37 项的清单，见文末「第二套水面」。拖动即时生效；颜色用取色器，向量拆成分量滑杆；每行悬停有中文说明。

### 清单是唯一来源

参数写在 `src/rendering/water_params.gd`，面板照着它生成控件。新增 uniform 必须同时加清单，否则永远调不到 —— `tools/check_water_params.gd` 会从着色器反读类型与 `hint_range` 对一遍：

```bash
Godot --headless --path godot --script res://tools/check_water_params.gd
# [water-params] PASS 原版 · 60 个参数与着色器一致（另有 21 个豁免）
# [water-params] PASS 吸收式 · 37 个参数与着色器一致（另有 21 个豁免）
```

它还会查资源：每个参数在 `.tres` 里有没有值、`source_color` 的 vec3 是不是存成 `Color`、有没有混进 `u_time` / `u_ripples` 这类每帧改的运行时参数。

### 不进面板的 21 项

`water_level`、`u_reverse_z`、`emission_gain`、`shore_distance/bounds/texel/enabled`、5 个采样器（含 `normal_map`）、4 条波 / 8 圈涟漪 / 32 个尾迹点的数组。前三个与岸线四项都是别的系统每帧或每次启动写的，做了滑杆也会被覆盖；采样器要换只能换图，不是滑杆能表达的量。

### 写回资源改文本行

`ResourceSaver` 会把每帧改的临时值写进文件、给材质里没有的参数写 `= null`、并重排整个文件（format 4 → 3、丢 uid）。所以「写入 water.tres」只逐行替换 `shader_parameter/<key> = ...`，没动的行一个字节不变。

### 两个类型陷阱

- `source_color` 的 vec3 如果存成 `Vector3`，读出来数值一样，但 `ResourceSaver` 按类型不符处理，保存时写成 `= null`，参数就没了。资源里所有 vec3 颜色一律存 `Color`。
- CozyUI 会给整棵树套奶油底 + 珊瑚色按钮。调试面板在 `_ready` 里打 `set_meta("cozy_skip", true)`，`cozy_ui.gd` 的 `apply()` 要**往上找祖先**才挡得住 —— 面板子控件是运行时逐个 `add_child` 的，只看自己有没有标记不够。

### 截图验收

两个抓图脚本，都靠 `SEA_SHOT_DIR` 指定落盘目录：

- `tools/capture_water_panel.gd` —— 整屏图：水面页顶 / 中段（按组名滚到「水面光点」）/ 底 + 滤镜页。顺带会把水面渲出来，能看参数有没有把水弄坏。
- `tools/capture_water_compare.gd` —— 面板按 `_panel` 的全局矩形裁下来放大 2 倍（1280 宽下面板里是 8 px 的字，不放大根本认不出滑杆标签），再截同一机位下「出厂 / 内置参考包初版」两张海面对比。

对比图**不经过面板套预设**：面板套用会写 `user://water.cfg`，跑一次就把玩家存档改了。脚本直接照 `WaterParams.builtin()` 的差异项往材质上设，开机时先存一份全量快照，跑完按快照复原，并打印复原差异（应为空）。

## 出厂参数定版

`water.tres` 现在是一轮手工调参后的成品，不再是参考包的移植初始值。方向：

| 项 | 之前 | 现在 | 意图 |
|---|---|---|---|
| `body_shallow` | (0.128, 0.618, 0.584) | (0.518, 0.996, 0.996) | 浅滩推到近青白 |
| `body_deep` | (0.070, 0.399, 0.549) | (0.028, 0.609, 0.723) | 深水更青 |
| `depth_half_distance` | 7.0 m | 12.25 m | 深色混入更慢，水更通透 |
| `shallow_tint_strength` | 1.3 | 2.7 | 浅水色染色更重 |
| `absorption` | (0.088, 0.036, 0.028) | (0.236, 0.091, 0.025) | 红光吸收加大 |
| `normal_lighting` | 0.45 | 1.0 | 几何坡度全量进法线 |
| `normal_repeat_metres` | 2.5 m | 1.0 m | 法线细节更密 |
| `detail_broad/mid/fine` | 0.36/0.44/0.16 | 0.97/0.03/0.49 | 细节堆在低频与高频 |
| `sky_top_color` | (0.308, 0.949, 0.784) | (0.319, 0.723, 0.496) | 天顶收敛到青绿 |
| `sky_horizon_color` | (0.610, 0.790, 0.840) | (0.236, 0.424, 0.477) | 地平线压暗 |
| `sky_curve` / `sky_sun_glow` | 0.35 / 0.35 | 0.57 / 0.02 | 过渡更缓、日晕关掉 |
| `sun_color` | (1.0, 0.955, 0.8) | (0.304, 0.855, 0.765) | 暖白改冷青 |
| `sun_highlight_strength` | 0.30 | 0.06 | 高光收小 |
| `sun_lobe_gain` / `sun_glossiness` | 60 / 7000 | 10 / 8000 | 光斑更小更紧 |
| `exposure_comp` | 0.66 | 0.45 | 整体压暗 |
| `dither_strength` | 1.0 | 1.35 | 压暗后色带更明显，抖动加一点 |
| `wave_scale`（节点） | 1.0 | 1.2 | 浪更高 |

三个滑杆范围同时放宽（着色器 `hint_range` 与清单同步改）：`normal_repeat_metres` 下限 1.0→0.5、`sun_glossiness` 上限 8000→12000、`sun_lobe_gain` 下限 10→5。这套值原本正好压在三根滑杆端点上。

**`wave_scale` 的出厂值写在 `water_surface.gd` 的导出默认值上，不是 `main.tscn` 的节点属性。** 场景覆盖被编辑器重写丢掉过一次（实测），默认值不会。

## 收藏：整套参数切换

面板顶部一行：`收藏 [下拉] [存] [删]`。下拉结构是 `出厂（water.tres）` / `── 内置 ──` / 用户收藏。

- **出厂**：现读 `water.tres`，不可删。
- **内置**：写在 `water_params.gd` 的 `BUILTIN_PRESETS`，目前只有「参考包初版」（重做后、手工调参前那一版）。只记与当前出厂不同的项，套用时先把其余参数复位到出厂值 —— 不抄全 60 条，以后改出厂值也不会留下半新半旧。
- **用户收藏**：存 `user://water_presets.cfg`，section 名 `preset:<名字>`，顺序单独记在 `[meta] names`（ConfigFile 的 section 顺序不保证）。值是「面板值」形态（`Color` / `Vector3` / `float`），与 `_water_read()` 同型，套用时原样喂回 `_water_write()`。

名字里的 `[` `]` 会破坏 ConfigFile 的 section 语法，存之前剔掉；不能和出厂/内置重名。分隔项要 `set_item_disabled`，否则会被选中、按钮文字变成「内置」。

## 存档带出厂指纹

`user://water.cfg` 里有一行 `__mat_sig = <water.tres 的 md5>`。启动时指纹对不上就整份作废 —— 否则改完出厂值重启，旧存档会把它整个盖住，看起来像「改了没生效」。改出厂值这件事本身就会让旧存档失效，不需要手动清。

## 水面光点（建筑附近的亮点）

水面上的小白点不是粒子，是片元里按格子哈希撒出来的点，只长在靠岸线距离图划出的环带内（离岸约 0.95~11.8 m），所以只在建筑附近出现。共 10 个参数：

| 参数 | 默认 | 范围 | 原来写死的值 |
|---|---|---|---|
| `glints_enabled` | true | — | （无开关） |
| `glint_color` | (0.88, 0.99, 0.96) | 取色 | `vec3(0.88, 0.99, 0.96)` |
| `glint_strength` | 1.0 | 0~2 | 末级乘 0.86 |
| `glint_density` | 0.24 | 0~1 | `h1 > 0.76` |
| `glint_size` | 1.0 | 0.2~3 | 半径 `0.042 + 0.022*h3` |
| `glint_speed` | 1.0 | 0~3 | `u_time * (0.85 + h2*0.75)` |
| `glint_drift` | 1.0 | 0~3 | 漂移半径 0.16 |
| `glint_twinkle` | 2.4 | 0.5~8 | `pow(sin(ph), 2.4)` 的指数 |
| `glint_zone_inner` | 2.2 | 0.5~20 m | `smoothstep(0.95, 2.2, d)` |
| `glint_zone_outer` | 11.8 | 2~40 m | `1 - smoothstep(6.2, 11.8, d)` |

环带边界改成半径后，淡入淡出按固定比例 `inner * 0.4318`、`outer * 0.5254` 算 —— 这两个比例就是 `0.95/2.2` 与 `6.2/11.8`，所以默认值与参数化之前逐像素一致。

`glint_density = 0` 等于关掉（`h1 > 1.0` 恒假）；`glint_speed = 0` 把相位钉住，点变成常亮的静止光斑。`shore` / `shore_d` 必须留在开关外面，下面的吃水线泡沫要用。

## 第二套水面：吸收式方案（2026-10-24）

同一篇文章的方法做了另一套水面：`shaders/water_absorption.gdshader` + `assets/materials/water_absorption.tres`。
它不画体色，取屏幕里已有的颜色按比尔-朗伯定律吃掉一部分波长，深了再补互补色。两套**并存**，
P 面板水面页顶部一行「方案：原版 / 吸收式」切换，`material_override` 换掉即可，网格、波场、
尾迹、桨环、岸线图全是同一份——对比的是着色模型，不是两个世界。

```
depth_blend = 1 - exp(-clamp(depth / depth_distance) * beers_law);
color       = screen - absorption_color * depth_blend;
color       = mix(color, 1 - absorption_color, depth_blend ^ 2);
color      *= mix(1.0, deep_darkness, depth_blend);   // 本工程新增：只靠色相没有纵深
```

### 三条必须守住的边界

- **垂直水深，不是轴向路径**。参考实现用轴向长度，掠射角下会把整片海变成一块不透明的吸收色，
  正好挡住沉没城市。轴向长度只留给折射与接触带。
- **`depth_distance` 按城市调，不按参考的池子调**。出厂 14 m；低于 5 m 时水下的废墟会被整片涂掉
  （实测第一版 3.5 m 就是这么糊掉的）。`beers_law` 同理，参考的 3 以上会让两米深的浅台变成死色。
- **波场必须与原方案共享**（`ocean_sample()` / `bow_height()`）。`boat.gd` 用同一对函数算吃水，
  换波场会让船穿水。

两套都不走 `ALBEDO + unshaded`，理由与前面「两个后端的色调映射不一样」一节一致：兼容后端会合成为纯黑。

### 面板与存档

- 参数清单是 `src/rendering/water_params_absorption.gd`（10 组 37 项），与原版的 `water_params.gd`
  是两份独立的表。同名不同义的参数（`absorption` 是「每米吸收多少」还是「被吃掉的波长颜色」）
  决定了它们不能合并，否则「复位到出厂」没有唯一答案。
- 存档分两段：`[water]` 仍是原版那批键（老存档照旧生效），`[water_absorption]` 是吸收式，各自一行
  `__mat_sig`；`[meta] scheme` 记住上次用的方案。收藏里多记一列 `__scheme`，下拉按当前方案过滤，
  写盘用不过滤的完整顺序，否则存一次会抹掉另一套的收藏名。
- `tools/check_water_params.gd` 两套都核对：
  `PASS 原版 · 60 个参数` / `PASS 吸收式 · 37 个参数`。
- `tools/capture_water_schemes.gd` 同机位截两套（走面板的 `set_water_scheme()`，顺带验证切换链路），
  `tools/probe_absorption_tuning.gd` 是出厂值扫描。

细节、扫描数据与验证记录见 [water_absorption_scheme.md](../docs/development/2026-10-24_water_absorption_scheme.md)。
