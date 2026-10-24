# 第二套水面：吸收式（Absorption Based Stylized Water）

日期：2026-10-24
范围：`godot/shaders/water_absorption.gdshader`、`godot/assets/materials/water_absorption.tres`、`godot/src/rendering/water_params_absorption.gd`、`godot/src/rendering/water_surface.gd`、`godot/src/rendering/color_grade_panel.gd`、`godot/src/bootstrap/main.gd`、`godot/tools/`、`assets/registry/`

## 需求与口径

原话：「在现有的基础上增加一个水对象，可以进行切换对比。现在的这个要保留。然后按照
https://godotshaders.com/shader/absorption-based-stylized-water/ 这个方法再制作一个。同样要把
所有参数做到 P 按键的测试工具里去。两个水对象要在游戏中可以进行切换，调整参数。注意不要改掉原来的。」

四条硬要求：新增第二套（照参考文章的方法）、原版不许动坏、新那套的参数全进 P 面板、两套能在游戏里切且各自可调。

## 为什么是两份材质，不是一个着色器里加 if

参考实现的水面**没有自己的体色**：它把屏幕里已有的颜色当体色，按比尔-朗伯定律吃掉一部分波长，
深了再把互补色补回去。原方案是「手绘浅/深水色对 + 深度混入」。两者同名参数不同义——
旧方案的 `absorption` 是「床面每米被吸收多少」（vec3），这里是「被吃掉的波长颜色」（vec3），
数值区间与调参直觉完全不同。

合成一张表会带来两个具体坏处：「复位到出厂」没有唯一答案（`if` 分支下有两套出厂值）；
面板只能列一套滑杆，另一套的参数永远调不到。所以：**两份着色器 + 两份材质 + 两份清单**，
切换只换 `material_override`。

## 与参考实现的关系

照抄的部分（`depth_blend` 合成链）：

```glsl
depth_blend = 1 - exp(-clamp(depth / depth_distance) * beers_law);
color       = screen - absorption_color * depth_blend;
color       = mix(color, 1 - absorption_color, depth_blend * depth_blend);
```

有意的偏离，理由都写在着色器头注释里：

| 偏离 | 理由 |
|---|---|
| 用**垂直**水深，不用轴向路径长度 | 掠射角下轴向路径长数倍，参考模型会在玩家平视海面时把整片水变成一块不透明的吸收色，正好挡住沉没城市——那是这个游戏的主体。轴向长度只驱动折射与接触带 |
| 去掉 global shader uniform（风、玩家位置） | 工程已在玩法代码里持有这些量 |
| 去掉屏幕空间反射的 raymarch | 工程已有反射探针覆盖可见波段 |
| 去掉 displacement / edge / ramp 贴图 | 波场是解析的、边缘泡沫是程序化的；本方案除共用一条法线带外不引入新贴图槽 |
| 焦散用三倍频噪声扭曲成亮脉络（`caustic_net`） | 参考用的 BCC 格点噪声带解析导数，约 40 行且每像素多次取样；这里只需要膝深范围内的脉络会动 |
| 新增 `deep_darkness`（`color *= mix(1, k, depth_blend)`） | 参考的互补色是为亮的池底调的。直接照搬，整片海俯视时是均匀浅青，深海与浅滩一样亮，没有纵深。默认 0.65＝深水压到六成半 |

刻意与原方案共用的：波场 `ocean_sample()` / `bow_height()`（`boat.gd` 用同一对函数算吃水，换波场会让船穿水）；
船尾浪与桨环法线；岸线距离图；`EMISSION` 输出 + `ALBEDO = 0`（`gl_compatibility` 下 `ALBEDO + unshaded`
被合成为纯黑，见 `render_flags.gd`）。

## 文件清单

| 文件 | 作用 |
|---|---|
| `shaders/water_absorption.gdshader` | 吸收式水面，10 组 37 个可调参数 |
| `assets/materials/water_absorption.tres` | 配套材质（44 项 `shader_parameter`），已登记进 `assets/registry/runtime_resource_inventory.json` |
| `src/rendering/water_params_absorption.gd` | 参数清单（面板唯一来源），与 `water_params.gd` 同结构 |
| `src/rendering/water_surface.gd` | 新增 `schemes` 注册表 + `use_scheme()` / `register_scheme()` / `current_material()` |
| `src/rendering/color_grade_panel.gd` | 水面页顶部的方案开关；两套清单按当前方案分发 |
| `src/bootstrap/main.gd` | 启动时注册两套、逐套写运行时参数；`--water-abs` 直接以吸收式启动 |
| `tools/check_water_params.gd` | 改为双方案核对（两套各查「着色器→清单 / 清单→着色器 / 资源」） |
| `tools/capture_water_schemes.gd` | 同机位截两套 + 面板放大图 |
| `tools/probe_absorption_tuning.gd` | 出厂值扫描（两轮，各 4 档） |
| `tools/diff_images.gd` | 两张 PNG 的差异统计（平均绝对差 / 超阈值占比 / 最大差），回答「这两张看着一样，到底差多少」 |

## 切换链路

顺序是固定的，换一步就出问题（注释里也写了）：

```
set_water_scheme(id)
  → water_node.use_scheme(id)        # 换 material_override，重新 _sync，重新 bind 岸线图
  → _rebuild_spec()                  # 清单换成另一套
  → _water_mat = null                # 逼 _ensure_water() 重取，否则继续往旧材质写
  → _rebuild_water_rows()            # 按新清单重建控件（37 ⬌ 60）
  → _sync_water()                    # 控件回读材质
  → _apply_water_cfg()               # 套该方案自己的存档段
```

踩到的五个坑：

1. **岸线图按材质绑定**。`shore_distance.gd` 把距线图写进材质的 `shore_distance` uniform，只绑当前那套的话，切过去是没有泡沫的干净水面。`rebuild_shoreline()` 改成给每套已登记材质都 bind。
2. **`_ensure_water()` 有缓存**。切完方案它还拿着旧材质，滑块就继续往旧材质写，画面没反应。加了「节点当前材质是否已经不是手里那份」的判断。
3. **`_file_defaults` 会跨方案污染**。「复位」用的是材质文件里读出来的出厂值，切换后必须重读。
4. **收藏写盘会抹掉另一套**。`_preset_order()` 按当前方案过滤是对的（下拉里不该出现另一套的名字），但写盘必须用不过滤的 `_preset_order_all()`，否则存一次就把另一套的收藏名清空。收藏里额外记一列 `__scheme`。
5. **存档要分两段**。`water.cfg` 的 `[water]` 还是旧方案那批键（老存档照旧生效），吸收式另起 `[water_absorption]`，各自一行 `__mat_sig`。`[meta] scheme` 记住上次用的方案，重启回到同一套。

## 参数清单

10 组 37 项：吸收（6）/ 菲涅尔（3）/ 表面细节（6）/ 太阳高光（5）/ 边缘泡沫（5）/ 岸线（3）/ 涟漪（2）/ 焦散（4）/ 波浪几何（2）/ 输出（2），其中波浪几何里的 `wave_scale` 是节点导出属性。

17 项刻意不进面板，理由与 `water_params.gd` 同源：`water_level`（`main.gd` 的 `WATER_LEVEL` 决定节点 Y 与吃水）、`u_reverse_z` 与 `emission_gain`（后端补偿）、岸线四项（`shore_distance.gd` 每次重建时写）、`normal_map`（要换图）、`ocean_waves` / `u_boat` / `u_time` / `u_ripples` / `u_ripple_count` / 三个尾迹数组（每帧写）。

`check_water_params.gd` 的两个 PASS：

```
[water-params] PASS 原版 · 60 个参数与着色器一致（另有 21 个豁免）
[water-params] PASS 吸收式 · 37 个参数与着色器一致（另有 21 个豁免）
```

## 出厂值怎么定的

第一版直接照参考实现的比例（`depth_distance` 3.5 m、`beers_law` 5.5）拍了一张——整片海是均匀的青，
**水下的沉没城市完全看不见**。原因不在深度缓冲：把 `EMISSION` 临时换成 `depth_blend` 截图，
深度罩几乎全白（说明 `depth_blend` 确实接近 1），问题是这个模型在 3.5 m 就把屏幕色替换成互补色，
而这座城市刚好泡在 3~12 m。

于是写了 `tools/probe_absorption_tuning.gd` 做同机位扫描：

| 档 | `depth_distance` | `beers_law` | `deep_darkness` | 结果 |
|---|---|---|---|---|
| a | 3.5 | 5.5 | 0.60 | 废墟全被涂掉，只剩一片青 |
| b | 8.0 | 3.0 | 0.75 | 废墟隐约可辨，仍偏糊 |
| c | 14.0 | 2.2 | 0.80 | 废墟清楚，深浅有层次 |
| d | 22.0 | 1.5 | 0.85 | 已经很接近原版的通透度，吸收特征变弱 |

第二轮回 `c` 附近调远景亮度与菲涅尔（`deep_darkness` 0.65~0.7、`fresnel_radius` 5→6、`fresnel_strength` 0.35→0.25），
最终出厂：

| 参数 | 出厂 | 说明 |
|---|---|---|
| `absorption_color` | (1.0, 0.45, 0.2) | 暖橙＝吃蓝绿，深处显示青蓝互补色 |
| `depth_distance` | 14.0 m | 按沉没城市调的：低于 5 m 废墟会被整片涂掉 |
| `beers_law` | 2.2 | 参考用 3 以上，那会让两米深的浅台直接变一块死色 |
| `screen_gain` | 0.9 | 参考值 |
| `deep_darkness` | 0.65 | 深水压到六成半 |
| `fresnel_radius` / `fresnel_strength` | 6.0 / 0.25 | 地平线不再被菲涅尔冲白 |
| `exposure_comp` | 0.66 | 与原方案同一套输出习惯 |

`depth_distance` 与 `beers_law` 的取值理由同时写进了着色器注释和面板 `hint`——这两个是「一动就毁画面」的参数，
滑到 5 m 以下会直接看不到城市。

## 验证

| 检查 | 结果 |
|---|---|
| `tools/check_water_params.gd` | 两套都 PASS（60 / 37） |
| `scripts/run_verification.py core` | modules / parity / farming / surface / click / management / camera / ocean / selftest 九项全 PASS（evidence `20261025-001322-water-absorption-958f25`） |
| Forward+ 真实渲染 | 无 SHADER ERROR；吸收式为青绿系、废墟清楚；原版与改动前一致 |
| `gl_compatibility` 真实渲染 | 退出 0、0 条 SHADER ERROR、不变黑不发白；两套都能看到水下废墟。同机位平均绝对差 9.0/255（Forward+ 是 7.0/255）——按重拟合后的增益 1.26 复核，见下 |
| 切换链路 | `capture_water_schemes.gd` 打印 `当前方案=absorption 控件数=37` / `复原后方案=original 控件数=60` |
| `scripts/check_feature_contracts.py` | 220 条运行资源哈希无漂移；0 issues。那条长期的「`main.gd` 引 `res://outputs` 缺资源」其实取决于本地有没有 `godot/outputs/`（该目录被 `.gitignore`，跑一次 `--capture` 就会生成），本轮跑过抓图后它自己消失了——新克隆上还会再出现，不是本次引入的 |

截图：`sea-work/manual-water-check/schemes/`（Forward+）、`schemes-gl/`（兼容后端）、`tune/`（出厂扫描）。

### 兼容后端：与「水色增益重拟合」那一条的关系

本方案的两套材质都吃 `render_flags.gd` 的 `emission_gain`，而本条分支上另有一条
`fix(water): 重拟合兼容后端水色增益`（`a002994`）把兼容后端的增益从 `(3.8, 3.8, 2.7)`
改成 `1.26`。第一次拍兼容后端时还没这条提交，水面整体过曝（那是旧增益的问题，不是本方案的）。
变基到 `a002994` 之后重拍：退出 0、0 条 SHADER ERROR、两套都不黑不发白、水下废墟都看得见，
同机位平均绝对差 9.0/255（Forward+ 是 7.0/255，逐像素阈值 >2/255 的占 30.7% 对 25.6%，
用 `tools/diff_images.gd` 量的）。**Web 导出前要按当时的最新增益再目视一次**——吸收式的
互补色对自发光增益比原版更敏感。

## 原版没有被改动的证据

- `git diff --stat -- godot/shaders/water.gdshader godot/assets/materials/water.tres godot/scenes/main.tscn godot/shaders/ocean_waves.gdshaderinc` 为空：着色器、出厂材质、场景、共享波场文件一个字节没变。
- `water_surface.gd` 是纯增量（47 增 1 删，删的那行是 `rebuild_shoreline()` 里原来只绑当前材质的一行，改成遍历已登记方案）。
- `main.gd` 的改动只把「往水面材质写运行时参数」收口成 `_active_water_mat()`，原方案的值与写入时机不变。
- `ocean` 套件 141 项断言全通过，覆盖波高、浮力、尾浪、距离场与薄片排除——这些是原版水面的行为。
- 同机位截图 `scheme-original.png` 与改动前肉眼一致。

## 遗留

- `water_absorption.tres` 是新增的登记项，行尾必须是 LF（登记哈希按 LF 算）。本机 `core.autocrlf=true` 且仓库无 `.gitattributes`，**未来一次 checkout 会把它写成 CRLF 并报哈希漂移**——判定法见 [water_restore_verification.md](2026-10-24_water_restore_verification.md)：转 LF 后与 `git show HEAD:<path>` 逐字节比，相同就是幻影，还原行尾而不是重算哈希。
- 吸收式在 `gl_compatibility` 下同样依赖 `emission_gain` 补偿，且比原版更吃这个系数（互补色整体乘在自发光上）。本分支已按 `1.26` 复核过，但**增益以后再改，这里要跟着重拍**。
- 焦散默认关闭。它在深水几乎不可见、浅滩才有脉络，等有具体浅滩场景再定出厂。
