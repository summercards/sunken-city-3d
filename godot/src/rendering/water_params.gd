extends RefCounted
class_name WaterParams
## 水面可调参数的唯一清单 —— P 面板「水面」页照这张表生成控件。
##
## 为什么单列一份而不是让面板自己扫着色器：扫出来的只有 `depth_half_distance`
## 这种英文标识符，没人愿意猜。这里补的是「中文名 / 分组 / 顺序 / 小数位」，
## 数值范围照抄着色器的 `hint_range`，不另立一套。
##
## 漏一个参数就等于玩家永远看不见它，所以 `tools/check_water_params.gd`
## 会把 `water.gdshader`（含 4 个 include）里的每个 uniform 和这张表对一遍，
## 表里多写、着色器里漏写都会报出来。
##
## 刻意不进面板的 4 个：
##   water_level   —— 由 `main.gd` 的 `WATER_LEVEL` 每帧写入，还牵着场景里
##                    Water 节点的 Y 和船的吃水；单独改一处只会让三者对不上。
##   u_reverse_z   —— 渲染后端约定，`render_flags.gd` 按后端算。
##   emission_gain —— gl_compatibility 的实测补偿系数，也是后端算的。
##   shore_enabled / shore_bounds / shore_texel
##                 —— `shore_distance.gd` 每次重建岸线时写。
## 采样器（贴图）和数组（4 条波、8 圈涟漪、32 个尾迹点）同样不进：
## 前者要在资源里换图，后者的每个分量在着色器里是整体参与运算的。

## kind 取值：
##   float / bool     单值
##   color            vec3 + source_color（面板显示取色器）
##   color4           vec4 + source_color（带透明度）
##   vec3             三个浮点分量的向量，不是颜色（吸收系数、太阳方向）
##   vec2             两个浮点分量
##   node             写在 Water 节点上、每帧由 water_surface.gd 同步进材质
const GROUPS := [
 preload("res://src/rendering/night_water_params.gd").GROUP,
	{
		"name": "body",
		"label": "水体",
		"note": "床面透过水看到的颜色。越深越靠近深水色。",
		"rows": [
			{"key": "body_shallow", "label": "浅水色", "kind": "color",
				"hint": "床面附近的体色。和 bed 相乘后决定浅滩看起来多亮。"},
			{"key": "body_deep", "label": "深水色", "kind": "color",
				"hint": "看不到床面时（开阔深海）的最终颜色。"},
			{"key": "depth_half_distance", "label": "深色半程", "kind": "float",
				"min": 0.1, "max": 14.0, "step": 0.05, "unit": "m",
				"hint": "垂直水深到多少米时，深水色的混入量过半。调小＝水更快变不透。"},
			{"key": "shallow_tint_strength", "label": "浅水染色", "kind": "float",
				"min": 0.0, "max": 4.0, "step": 0.05,
				"hint": "浅水色对被看到的水下物体染色的强度。3.0 以上会像掺了奶。"},
			{"key": "view_occlusion_strength", "label": "掠射遮挡", "kind": "float",
				"min": 0.0, "max": 0.5, "step": 0.01,
				"hint": "视线贴着水面时压暗床面的量。0 完全关掉。"},
			{"key": "absorption", "label": "吸收系数", "kind": "vec3",
				"min": 0.0, "max": 0.4, "step": 0.001, "fmt": "%.3f",
				"sub": ["R", "G", "B"],
				"hint": "bed 颜色每米被吸收多少。红最大、蓝最小，沉没城市会先变青再消失。"},
			{"key": "refraction_strength", "label": "折射强度", "kind": "float",
				"min": 0.0, "max": 80.0, "step": 0.5,
				"hint": "水下物体随波扭动的像素量。水下物体边缘出现撕裂时调小。"},
		],
	},
	{
		"name": "surface",
		"label": "表面细节",
		"note": "法线 = 几何坡度 + 法线贴图，两者都要。",
		"rows": [
			{"key": "normal_lighting", "label": "几何坡度", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.01,
				"hint": "大浪的坡度有多少进入法线。0 只留贴图细节，水面会变平。"},
			{"key": "surface_normal_strength", "label": "法线贴图", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.01,
				"hint": "高频细节的强度。太阳高光碎不碎主要看这一项。"},
			{"key": "normal_repeat_metres", "label": "贴图尺度", "kind": "float",
				"min": 0.5, "max": 20.0, "step": 0.1, "unit": "m",
				"hint": "法线条带在世界里重复一次多少米。调大＝细节变大块。"},
			{"key": "detail_broad", "label": "低频纹理", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.01},
			{"key": "detail_mid", "label": "中频纹理", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.01},
			{"key": "detail_fine", "label": "高频纹理", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.01,
				"hint": "高频在 46 m 外就淡出，调太大只会闪成噪点。"},
		],
	},
	{
		"name": "caustics",
		"label": "水下光斑",
		"note": "透过水面照到床面和沉没建筑上的阳光波纹。焊在水下物体上，不跟着水面漂。",
		"rows": [
			{"key": "caustics_enabled", "label": "启用", "kind": "bool",
				"hint": "关掉即可完全移除这一层，其余参数保留。"},
			{"key": "caustics_color", "label": "光斑颜色", "kind": "color",
				"hint": "叠到水下物体上的颜色。偏青白最像穿透水面的日光；偏黄会变成沙底。"},
			{"key": "caustics_strength", "label": "强度", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.005,
				"hint": "叠加上去的量。0.2 以上开始抢建筑本身的颜色。"},
			{"key": "caustics_scale", "label": "十字密度", "kind": "float",
				"min": 0.2, "max": 4.0, "step": 0.01,
				"hint": "调大＝格子更小更密。2.0 时格子数变四倍。太密会在远处闪。"},
			{"key": "caustics_speed", "label": "流动速度", "kind": "float",
				"min": 0.0, "max": 3.0, "step": 0.01,
				"hint": "光斑爬动的快慢。0＝定住，方便调形状和密度。"},
			{"key": "caustics_detail", "label": "边缘柔和度", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.01,
				"hint": "第二层更细的光网。0 只剩规则格子，看着像印刷网点。"},
			{"key": "caustics_depth_near", "label": "浅端起始", "kind": "float",
				"min": 0.05, "max": 4.0, "step": 0.01, "unit": "m",
				"hint": "水深到这个距离时达到全强度，再浅则渐隐。水面正下方本来就还没聚焦。"},
			{"key": "caustics_depth_far", "label": "深端淡出", "kind": "float",
				"min": 2.0, "max": 40.0, "step": 0.1, "unit": "m",
				"hint": "深到这个距离后光斑消失。太深的光早就散掉了，画出来只会是一层噪点。"},
		],
	},
	{
		"name": "relief",
		"label": "立体明暗",
		"note": "水面不吃光照，俯视时靠这一层给出浪的明暗。只改颜色，不动几何与波场。",
		"rows": [
			{"key": "relief_enabled", "label": "启用明暗", "kind": "bool"},
			{"key": "relief_gain", "label": "浪脊对比", "kind": "float",
				"min": 0.2, "max": 3.0, "step": 0.01,
				"hint": "调大＝亮脊带宽、浪更密；调小＝只留最高的那几道脊。1.0 是出厂。"},
			{"key": "relief_light", "label": "浪脊提亮", "kind": "float",
				"min": 0.0, "max": 3.0, "step": 0.01,
				"hint": "浪顶加亮多少。加性叠加，红通道也会抬起来，像透光的薄水。0 关掉亮部。"},
			{"key": "relief_shade", "label": "波谷压暗", "kind": "float",
				"min": 0.0, "max": 3.0, "step": 0.01,
				"hint": "浪背往深水色拉多少。混色不是相乘，调大也不会发黑。"},
			{"key": "relief_color", "label": "迎光色", "kind": "color",
				"hint": "浪峰提亮时掺进去的颜色。偏青白最像薄水，偏暖会变成沙丘。"},
		],
	},
	{
		"name": "sky",
		"label": "天空反射",
		"note": "解析渐变，取的是 ocean_sky.tres 的三色。",
		"rows": [
			{"key": "sky_top_color", "label": "天顶色", "kind": "color"},
			{"key": "sky_horizon_color", "label": "地平线色", "kind": "color"},
			{"key": "sky_ground_color", "label": "地面色", "kind": "color",
				"hint": "反射朝下时的颜色，给浪背面一点暗底，别照得和天空一样亮。"},
			{"key": "sky_curve", "label": "渐变曲线", "kind": "float",
				"min": 0.05, "max": 1.0, "step": 0.01,
				"hint": "小＝地平线附近蓝得快，大＝整片天更接近天顶色。"},
			{"key": "sky_sun_glow", "label": "日晕", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.01},
			{"key": "reflection_strength", "label": "反射强度", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.01},
			{"key": "fresnel_power", "label": "菲涅尔指数", "kind": "float",
				"min": 1.0, "max": 12.0, "step": 0.1,
				"hint": "大＝只有很掠的角度才反光，水面更像一潭深色；小＝整片发白。"},
		],
	},
	{
		"name": "sun",
		"label": "太阳高光",
		"note": "方向不会跟着场景 Sun 走，改灯时要同步。",
		"rows": [
			{"key": "sun_direction", "label": "太阳方向", "kind": "vec3",
				"min": -1.0, "max": 1.0, "step": 0.01, "sub": ["X", "Y", "Z"],
				"hint": "水面指向太阳的世界方向，着色器内部会归一化。改了要跟场景 Sun 对齐。"},
			{"key": "sun_color", "label": "高光颜色", "kind": "color"},
			{"key": "sun_highlight_strength", "label": "高光强度", "kind": "float",
				"min": 0.0, "max": 3.0, "step": 0.01},
			{"key": "sun_glossiness", "label": "高光锐度", "kind": "float",
				"min": 100.0, "max": 12000.0, "step": 50.0, "fmt": "%.0f",
				"hint": "越大光斑越紧。俯视海面时 900 会糊成一坨，出厂 8000。"},
			{"key": "sun_lobe_gain", "label": "高光增益", "kind": "float",
				"min": 5.0, "max": 400.0, "step": 1.0, "fmt": "%.0f",
				"hint": "光斑峰值。参考包用 250 配 0.2 m 波幅的池塘，出厂 10。"},
		],
	},
	{
		"name": "ripples",
		"label": "波纹",
		"note": "贴图描出的墨线网络，有生灭周期。",
		"rows": [
			{"key": "ripples_enabled", "label": "启用波纹", "kind": "bool"},
			{"key": "ripple_color", "label": "波纹颜色", "kind": "color4",
				"hint": "RGB 是墨色，A 是图层不透明度（不是水的透明度）。"},
			{"key": "ripple_coverage", "label": "覆盖率", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.01,
				"hint": "同时有多少网络活着。0.7 是中性值，越大线越持久。"},
			{"key": "ripple_width_multiplier", "label": "线宽", "kind": "float",
				"min": 0.0, "max": 1.5, "step": 0.01},
			{"key": "ripple_dissipation_speed", "label": "消散速度", "kind": "float",
				"min": 0.25, "max": 4.0, "step": 0.01},
			{"key": "ripple_scale", "label": "波纹缩放", "kind": "float",
				"min": 0.3, "max": 3.0, "step": 0.01},
			{"key": "ripple_tile_metres", "label": "单块尺寸", "kind": "vec2",
				"min": 0.5, "max": 30.0, "step": 0.1, "unit": "m", "sub": ["X", "Y"],
				"hint": "一块贴图铺多少米。参考包按 34 m 池塘调，海面上要用小得多的值。"},
			{"key": "ripple_fade_near", "label": "淡出起点", "kind": "float",
				"min": 0.0, "max": 60.0, "step": 0.5, "unit": "m"},
			{"key": "ripple_fade_far", "label": "淡出终点", "kind": "float",
				"min": 1.0, "max": 120.0, "step": 0.5, "unit": "m",
				"hint": "更远处只会摩尔纹，必须淡干净。"},
			{"key": "flow_speed", "label": "流速", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.01,
				"hint": "同时影响波纹生灭节拍和法线条的漂移速度。"},
			{"key": "flow_direction_degrees", "label": "流向", "kind": "float",
				"min": 0.0, "max": 360.0, "step": 0.1, "unit": "°"},
		],
	},
	{
		"name": "glints",
		"label": "水面光点",
		"note": "建筑附近漂动的小亮点。只长在离岸 2~12 m 的环带里，开阔海面没有。",
		"rows": [
			{"key": "glints_enabled", "label": "启用光点", "kind": "bool"},
			{"key": "glint_color", "label": "光点颜色", "kind": "color",
				"hint": "亮点本身的颜色。偏白青时最像反光，偏暖会变成萤火。"},
			{"key": "glint_strength", "label": "强度", "kind": "float",
				"min": 0.0, "max": 2.0, "step": 0.01,
				"hint": "亮度倍率。1.0 是原样，2.0 会亮到几乎变成纯色块。"},
			{"key": "glint_density", "label": "密度", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.01,
				"hint": "有多少格子长光点。出厂 0.24；调到 0 就一个都不剩。"},
			{"key": "glint_size", "label": "点大小", "kind": "float",
				"min": 0.2, "max": 3.0, "step": 0.01,
				"hint": "点的半径倍率。调太大会连成一片，不像水光。"},
			{"key": "glint_speed", "label": "闪烁速度", "kind": "float",
				"min": 0.0, "max": 3.0, "step": 0.01,
				"hint": "明灭节拍和漂移快慢。0 会定住不动。"},
			{"key": "glint_drift", "label": "漂移幅度", "kind": "float",
				"min": 0.0, "max": 3.0, "step": 0.01,
				"hint": "点离开格子中心多远。调大像在水里飘，0 就钉死在原地。"},
			{"key": "glint_twinkle", "label": "明灭锐度", "kind": "float",
				"min": 0.5, "max": 8.0, "step": 0.01,
				"hint": "小＝一直亮着，大＝一闪就灭。出厂 2.4。"},
			{"key": "glint_zone_inner", "label": "内边界", "kind": "float",
				"min": 0.5, "max": 20.0, "step": 0.1, "unit": "m",
				"hint": "离岸多远开始出现。贴着建筑的那一圈留空，光点才不会压到码头上。"},
			{"key": "glint_zone_outer", "label": "外边界", "kind": "float",
				"min": 2.0, "max": 40.0, "step": 0.1, "unit": "m",
				"hint": "离岸多远之后不再出现。调大＝光点铺得更开。"},
		],
	},
	{
		"name": "foam",
		"label": "泡沫",
		"note": "浪尖、船尾、物体吃水线三层，彼此独立。",
		"rows": [
			{"key": "crest_foam_strength", "label": "浪尖泡沫", "kind": "float",
				"min": 0.0, "max": 1.5, "step": 0.001,
				"hint": "浪顶的白。这个尺度下白帽是两米宽的白漆，所以出厂很淡。"},
			{"key": "foam_color", "label": "泡沫颜色", "kind": "color",
				"hint": "浪尖泡沫和船尾泡沫共用的颜色。"},
			{"key": "contact_depth", "label": "深度边缘", "kind": "float",
				"min": 0.0, "max": 4.0, "step": 0.01,
				"hint": "细杆件（栏杆、缆绳）够不上岸线图时，靠这个深度差补一圈淡淡的印子。"},
			{"key": "edge_strength", "label": "边缘强度", "kind": "float",
				"min": 0.0, "max": 1.5, "step": 0.01},
			{"key": "contact_foam_color", "label": "吃水线色", "kind": "color4"},
			{"key": "contact_foam_rim_width", "label": "贴边线宽", "kind": "float",
				"min": 0.0, "max": 0.6, "step": 0.005, "unit": "m",
				"hint": "紧贴物体的实线宽。必须大于岸线图的 0.133 m 一个纹素，否则插值会抹掉。"},
			{"key": "contact_foam_width", "label": "泡沫外扩", "kind": "float",
				"min": 0.0, "max": 3.0, "step": 0.01, "unit": "m"},
			{"key": "contact_foam_strength", "label": "泡沫强度", "kind": "float",
				"min": 0.0, "max": 1.5, "step": 0.01},
			{"key": "contact_foam_animation_speed", "label": "生灭速度", "kind": "float",
				"min": 0.0, "max": 4.0, "step": 0.01},
			{"key": "contact_foam_interval_seconds", "label": "间隔", "kind": "float",
				"min": 0.0, "max": 4.0, "step": 0.1, "unit": "s"},
			{"key": "contact_foam_repeat_metres", "label": "贴图重复", "kind": "float",
				"min": 1.0, "max": 15.0, "step": 0.1, "unit": "m"},
		],
	},
	{
		"name": "waves",
		"label": "波浪几何",
		"note": "四条波写在 water_surface.gd，这里只控制总波幅。",
		"rows": [
			{"key": "wave_scale", "label": "总波幅", "kind": "node",
				"min": 0.0, "max": 2.0, "step": 0.05, "default": 1.0,
				"hint": "顶点位移的倍率，船吃水也跟着变。改这里就是改 Water 节点的 wave_scale。"},
		],
	},
	{
		"name": "output",
		"label": "输出",
		"note": "水面纯自发光，最后一步的整体缩放。",
		"rows": [
			{"key": "exposure_comp", "label": "曝光补偿", "kind": "float",
				"min": 0.2, "max": 2.5, "step": 0.01,
				"hint": "整片水的亮度。和 WorldEnvironment 的曝光是两个东西，别互相顶。"},
			{"key": "dither_strength", "label": "抖动", "kind": "float",
				"min": 0.0, "max": 4.0, "step": 0.05,
				"hint": "屏幕空间静态抖动，用来打散 8 位色带。0 关掉会看到分层。"},
		],
	},
]


## 内置预设：写死「曾经当过出厂值」的整套参数，用来和当前版本对比。
##
## 只列与当前 `water.tres` 不同的项 —— 套用时会先把其余参数复位到出厂值，
## 所以这里不用抄全 60 条，以后改出厂值也不会留下半新半旧的状态。
## 数字取自 2026-10-24 那版参数存档，是当时实际生效的值（含节点波幅）。
static var BUILTIN_PRESETS := [
	{
		"name": "参考包初版",
		"note": "按 stylized_water_prod 重做后那一版：浅滩青绿、水更不透（深色半程 7 m）、"
			+ "天空偏薄荷绿、太阳暖白大光斑、细节落在中频。",
		"values": {
			"body_shallow": Color(0.128, 0.618, 0.584, 1),
			"body_deep": Color(0.07, 0.399, 0.549, 1),
			"depth_half_distance": 7.0,
			"shallow_tint_strength": 1.3,
			"view_occlusion_strength": 0.1,
			"absorption": Vector3(0.088, 0.036, 0.028),
			"refraction_strength": 22.0,
			"normal_lighting": 0.45,
			"surface_normal_strength": 0.45,
			"normal_repeat_metres": 2.5,
			"detail_broad": 0.36,
			"detail_mid": 0.44,
			"detail_fine": 0.16,
			"sky_top_color": Color(0.30775452, 0.94921875, 0.78384125, 1),
			"sky_horizon_color": Color(0.61, 0.79, 0.84, 1),
			"sky_curve": 0.35,
			"sky_sun_glow": 0.35,
			"fresnel_power": 6.0,
			"sun_direction": Vector3(0.5191, 0.7787, -0.3523),
			"sun_color": Color(1, 0.955, 0.8, 1),
			"sun_highlight_strength": 0.3,
			"sun_glossiness": 7000.0,
			"sun_lobe_gain": 60.0,
			"wave_scale": 1.0,
			"exposure_comp": 0.66,
			"dither_strength": 1.0,
		},
	},
]


## 按名字找内置预设，找不到返回空字典。
static func builtin(name: String) -> Dictionary:
	for p in BUILTIN_PRESETS:
		if String(p.name) == name:
			return p
	return {}


## 内置预设名，用来挡住「收藏不许和内置重名」。
static func builtin_names() -> Array[String]:
	var out: Array[String] = []
	for p in BUILTIN_PRESETS:
		out.append(String(p.name))
	return out


## 摊平成 key -> row，面板和检查脚本都用它。
static func flat() -> Dictionary:
	var out := {}
	for g in GROUPS:
		for row in g.rows:
			var r: Dictionary = row.duplicate()
			r["group"] = g.name
			out[r.key] = r
	return out
