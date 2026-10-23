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

`shaders/ocean_foam.gdshaderinc` 根据距离产生细接触白边和错相的外推波包。轮廓有小幅扇贝状弯曲，浪线在传播时拉薄、断裂并消散，复位前强度归零。岸浪同时贡献最多约 2.4 厘米的位移和相应法线，不只改变颜色。

## 海面白浪与材质

- 开阔海面的白浪与主波相位共用方向、色散速度、横向弯曲和时钟。低频空间/时间包络控制出现与消退，不铺满海面，也不是独立漂移的白色斑块。
- 浪头是**有宽度的破碎白斑**（宽带 + 亮核 + 后侧渐薄的水膜），不是一像素描线；40 米外整体淡出，避免远看塌成扁平白斑。
- 白沫使用受场景光照影响的浅色材质、较高粗糙度和较低透射，保留明暗与厚薄层次；不使用白色自发光。
- `water.gdshader` 保留深度吸收、屏幕折射、GGX 高光与天空环境反射。水粗糙度默认 0.13，水/空气 F0 约 0.02037。透射颜色不再被水材质重复照亮。
- 可调参数：`shore_foam_strength`、`crest_foam_strength`、`foam_color`、`water_roughness`。

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
