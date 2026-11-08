# 家园海底：水面抬高 50 米 + 雾/环境对齐旧九图

日期：2026-11-08
范围：`godot/scenes/underwater/sunroom_region.tscn` 及其本地着色器、氛围节点、专项测试
对应条款：SEA-DIVE-R24–R26、SEA-AMBIENT-R26–R27

## 1. 两个请求

1. 「看一下雾气和视效的参数，是不是和这个场景一致的」——对照 zone1 截图。
2. 「直接对齐，不用截图对比」——按 zone1 的公式改。
3. 期间追加：「还有这个海底地图，让城市更加往下 50 米，相当于海平面拉高 50 米。」

## 2. 核对结论：原来不一致

| 项目 | zone1 | 原家园海底 |
|---|---|---|
| 雾公式 | `1 − exp(−(d × density)^1.8)` | `pow(smoothstep(6, 110, d), 1.3)` |
| 30 米处浓度 | 0.48 | 0.08 |
| 环境光 | SKY 半球双色，`1.9/π` | 平色 0.48 |
| 背景 | 屏幕垂直渐变 | 方向渐变 + 水平分层 + 边缘吸收 |
| glow / SSAO | 无 | 开 / 开 |
| FOV | 55 | 68 |

中近景几乎无雾是画面「扁平」的主因；glow + 平色环境光把浅色海床又糊了一层。

## 3. 深度：为什么用「抬水面」而不是「搬几何」

两种做法在画面上等价（相对水面都是深 50 米），差别只在绝对坐标：

- 搬几何（城市/海床/基座/鱼/珊瑚/灯/气泡柱/光柱各减 50）要动 388 个实例、56 个生态接地、8 群鱼、10 条光柱，且 `_entry_spot` 里硬编码的路面 −18 会失效。
- 抬水面只改 `water_level` 与 `Water` Mesh 两处，几何零位移，海面 XZ 对齐契约、Main、原九图、catalog 全不受影响；`_entry_spot` 的路面高度依然有效。

因此选抬水面：`water_level 1.12 → 51.12`。旧城街面 Y≈−18，水深由约 19 米变为 **69 米**。

深度契约同步扩到 85 米，`viewer_min_y` 不变：

```
51.12 − 85.0  = −33.88
−34.68 + 0.80 = −33.88   # lowest_seabed_y + viewer_floor_clearance
```

两项同时成立，`_verify_depth_contract` 无需改逻辑。运行时夹限上限变为 `51.12 − 0.82 = 50.30`。

### 入水占位

`begin_dive` 原来把占位放在「水面下 6 米」= 45.12，物理提交后才由 `_entry_spot` 落到街面。水面抬高后这中间是 51 米空白水柱：会先在 45 米处渲染若干帧空场景，再瞬移 50 米。

改为街面占位：`entry_street_y = -18`、`entry_rise = 10`，占位 `(x, −8, z)`；`_entry_spot` 的路面搜索改用同一常量。选区判据（16~30 米环、12 角度、路面 +6/8/10/12、12 米球形净空、头顶 16 米无楼板、某方向 18~38 米楼体）全部保留。

## 4. 雾与环境：改成与 zone1 同源

`shaders/sunroom_underwater_color.gdshaderinc`（重写）

```glsl
vec3 region_water_display(vec2 screen_uv) {
    return uw_gradient_display(screen_uv, region_view_depth);
}
float region_fog_amount(float distance_m) {
    float density = mix(0.026, 0.012, smoothstep(65.0, 210.0, region_view_depth));
    return clamp(1.0 - exp(-pow(max(distance_m, 0.0) * density, 1.8)), 0.0, 1.0);
}
```

删掉原方向渐变、`smoothstep(14, 92)` 水平分层、`smoothstep(448, 500)` XZ 边缘吸收三处叠加——它们都是「第二层雾」。边缘吸收原本用来遮 1024 米高度图的字面边界，改由指数雾在 110 米处饱和接管。

`sunroom_underwater_fog.gdshader`：逐行对齐 `uw_fog.gdshader`（近/远平面推导、`INV_PROJECTION_MATRIX` 反投影、`RENDERER_COMPATIBILITY` 的 ndc.z 换算）。

`sunroom_underwater_sky.gdshader`：补 `AT_CUBEMAP_PASS` 分支返回上下双色 `(0.188,0.325,0.545) ↔ (0.733,1.0,0.937)`；可见背景仍走屏幕渐变。

`sunroom_region.tscn`：`ambient_light_source = 3`（SKY）、`ambient_light_energy = 0.6047898`（= 1.9/π）、`glow_enabled = false`、`ssao_enabled = false`、`SunRays`/`CoolFill` 能量 0（保留节点，避免改动任何节点路径）、Camera `fov = 55`。

`sunroom_region.gd`：

```gdscript
var deep := clampf((view_depth-12.0)/64.0,0.0,1.0)
environment.ambient_light_energy = (1.9/PI)*(1.0-deep*0.6)
```

`sunroom_underwater_palette.gdshader`：去掉逐材质深度吸收与饱和度增益（会在指数雾之上再压一层青），焦散项改为 `uw_emission` 同式。

## 5. 氛围节点适配 69 米水深

| 项 | 值 | 原因 |
|---|---|---|
| 光柱顶部 | Y=50.12，长度 60~70 米 | 从新水面打下来；原来 22~29 米会悬在半空 |
| 光柱 density | `× 22/长度` | 积分路径变长 3 倍会把柱子糊成实心；按长度反比归一到原来的每米光学厚度 |
| 气泡顶 | 50.47 | 必须升到新水面 |
| 悬尘带 | `MOTE_BAND = 17` 米 | 不限高会沿 67 米摊薄、速度 0.05 m/s 等于静止噪点 |
| 粒子 `custom_aabb` | 纵向 27 → 76 米 | 覆盖新的全柱范围，不靠巨大强制包围盒 |

数量、种子、16 步深度挡墙积分均未变。

## 6. 改了哪些文件

```
godot/scenes/underwater/sunroom_region.tscn           水面/环境/深度契约/相机
godot/scenes/underwater/sunroom_region/atmosphere.tscn 光柱顶部与长度、水面元数据
godot/src/diving/sunroom_region.gd                     water_level 默认、target_depth、入水占位、环境衰减
godot/src/ambient/sunroom_underwater_atmosphere.gd     水面常量、光柱密度、悬尘带、AABB
godot/shaders/sunroom_underwater_color.gdshaderinc     重写（指数雾 + 屏幕渐变 + 半球双色）
godot/shaders/sunroom_underwater_fog.gdshader          重写（对齐 uw_fog）
godot/shaders/sunroom_underwater_sky.gdshader          重写（cubemap 双色分支）
godot/shaders/sunroom_underwater_palette.gdshader      去深度染色，焦散对齐 uw_emission
godot/shaders/sunroom_underwater_particles.gdshader    fog 取屏幕渐变
godot/shaders/sunroom_underwater_beam.gdshader         fog 只按距离
godot/tests/test_sunroom_underwater_region.gd          水面 51.12 / 最深 113.12 / target 85
```

未改：`scenes/main.tscn`、原九图 `scenes/underwater/maps/*`、`src/diving/dive_map_catalog.gd`、`assets/materials/world_env.tres`、`water.tres`、共享城市/海床/基座资源、Terrain3D 高度数据。

## 7. 验证

```
godot --path godot --headless --script res://tests/test_sunroom_underwater_region.gd -- --skip-title
→ [sunroom-underwater] 80 checks, 0 failures
```

并用真实渲染器（Vulkan / RTX 4060 Ti / Forward+）单独加载本场景，确认无着色器编译错误——headless 的 dummy 渲染器不编译着色器，这一步不能省。

## 8. 未做 / 风险

- **九入口批量回归未重跑**。历史 `20261108-123311` 的 1241/0 是上一轮（35 米、旧雾）的证据，不能当作本次结果。dive-maps 里如果存在对水面高度或雾参数的断言，需要单独确认。
- 入水落点只做了逻辑层验证，没有重跑实拍目检。
- 旧城在 69 米水深，从水面往下前 50 米是连续水柱；指数雾在 60 米处已 0.89，所以下潜途中看不到城市，属预期。是否可接受要用户实机确认。
- 海床仍是共享 `res://terrain/sunken_seabed`，最低 −62，可游下限 −33.88，下方几何只作视觉。
- 低端 GPU、连续运行性能、全路线观感、用户美术终审仍未签。
