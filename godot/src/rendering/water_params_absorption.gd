extends RefCounted
class_name WaterParamsAbsorption
## 吸收式水面（`water_absorption.gdshader`）的可调参数清单。
##
## 和 `water_params.gd` 是两份独立的表，不是同一份的两个视图：两套水的身体
## 模型不一样，参数同名也不同义（旧方案的 `absorption` 是「床面每米被吸收多少」，
## 这里是「被吃掉的波长颜色」），合成一张表只会让两边的默认值互相污染。
##
## 面板按当前选中的方案取对应的表，`tools/check_water_params.gd` 两张都核对。
##
## 刻意不进面板的（共 17 项）：
##   water_level    —— `main.gd` 的 `WATER_LEVEL` 写入，牵着节点 Y 与船的吃水。
##   u_reverse_z    —— 渲染后端约定，`render_flags.gd` 按后端算。
##   emission_gain  —— gl_compatibility 的实测补偿，后端算。
##   shore_distance / shore_bounds / shore_texel / shore_enabled
##                  —— `shore_distance.gd` 每次重建岸线时写。
##   normal_map     —— 采样器，要在资源里换图。
##   ocean_waves / u_boat / u_time / u_ripples / u_ripple_count
##   wake_points / wake_strengths / wake_count
##                  —— include 带入的运行时数据，由 `water_surface.gd` 与
##                     `main.gd` 每帧写。

## kind 取值同 `water_params.gd`：float / bool / color / color4 / vec3 / vec2 / node。
const GROUPS := [
	{
		"name": "absorb",
		"label": "吸收",
		"note": "这一套的水色不是画出来的，是从屏幕里已有的颜色中吃掉一部分。",
		"rows": [
			{"key": "absorption_color", "label": "吸收色", "kind": "color",
				"hint": "被水吃掉的波长。深处显示的是它的互补色——想让它读起来是青绿，这里就要偏暖。"},
			{"key": "depth_distance", "label": "深度参考", "kind": "float",
				"min": 0.1, "max": 50.0, "step": 0.1, "unit": "m",
				"hint": "多深的水算「满吸收」。调小＝水更快变不透。出厂 14 m 是按沉没城市"
					+ "调的：低于 5 m 时水下的废墟会被整片涂掉。"},
			{"key": "beers_law", "label": "比尔斜率", "kind": "float",
				"min": 0.0, "max": 20.0, "step": 0.1,
				"hint": "比尔-朗伯定律的指数斜率。越大越早饱和，浅水就开始变色；"
					+ "参考实现用 3 以上，那会让两米深的浅台直接变成一块死色。"},
			{"key": "screen_gain", "label": "屏幕增益", "kind": "float",
				"min": 0.0, "max": 1.5, "step": 0.01,
				"hint": "吸收之前先把屏幕色乘一下。参考实现用 0.9，用来压一点通透感。"},
			{"key": "deep_darkness", "label": "深水压暗", "kind": "float",
				"min": 0.1, "max": 1.0, "step": 0.01,
				"hint": "深水亮度压到几成。参考实现的深水是亮的互补色（它的池底本来亮），"
					+ "这片海域要压暗才有纵深；1.0 等于关掉。"},
			{"key": "refraction_strength", "label": "折射强度", "kind": "float",
				"min": 0.0, "max": 80.0, "step": 0.5,
				"hint": "水下物体随波扭动的像素量。边缘撕裂时调小。"},
		],
	},
	{
		"name": "fresnel",
		"label": "菲涅尔",
		"note": "越接近平视，水面越像镜子。",
		"rows": [
			{"key": "fresnel_radius", "label": "菲涅尔指数", "kind": "float",
				"min": 0.0, "max": 6.0, "step": 0.01,
				"hint": "大＝只有很掠的角度才反白，水面更像一潭深色；小＝整片发亮。"},
			{"key": "fresnel_color", "label": "反射色", "kind": "color",
				"hint": "掠射角处混进去的颜色，应该是天空在水平方向的颜色。"},
			{"key": "fresnel_strength", "label": "反射强度", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.01},
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
			{"key": "normal_map_strength", "label": "法线贴图", "kind": "float",
				"min": 0.0, "max": 2.0, "step": 0.01,
				"hint": "高频细节的强度。太阳高光碎不碎主要看这一项。"},
			{"key": "normal_repeat_metres", "label": "贴图尺度", "kind": "float",
				"min": 0.5, "max": 20.0, "step": 0.1, "unit": "m",
				"hint": "法线条带在世界里重复一次多少米。调大＝细节变大块。"},
			{"key": "scroll_speed", "label": "滚动速度", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.01},
			{"key": "scroll_offset", "label": "滚动偏移", "kind": "vec2",
				"min": -3.0, "max": 3.0, "step": 0.01, "sub": ["X", "Y"],
				"hint": "第二层贴图相对第一层的错位。两层反向漂移才不会被看成传送带。"},
			{"key": "scroll_scale_offset", "label": "层间尺度", "kind": "float",
				"min": 0.1, "max": 3.0, "step": 0.01,
				"hint": "第二层的世界尺度倍率。整数倍会和第一层锁成同一张平铺。"},
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
				"hint": "越大光斑越紧。俯视海面时 900 会糊成一坨。"},
			{"key": "sun_lobe_gain", "label": "高光增益", "kind": "float",
				"min": 5.0, "max": 400.0, "step": 1.0, "fmt": "%.0f",
				"hint": "光斑峰值。参考包用 250 配 0.2 m 波幅的池塘。"},
		],
	},
	{
		"name": "edge",
		"label": "边缘泡沫",
		"note": "水面贴着固体的那一圈白，靠水深差判断，不依赖岸线图。",
		"rows": [
			{"key": "edge_thickness", "label": "边缘厚度", "kind": "float",
				"min": 0.0, "max": 2.0, "step": 0.001, "unit": "m",
				"hint": "多浅的水算「贴着东西」。调大＝泡沫从物体往外铺得更开。"},
			{"key": "edge_speed", "label": "飘动速度", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.001},
			{"key": "edge_noise_scale", "label": "噪声尺度", "kind": "float",
				"min": 0.05, "max": 4.0, "step": 0.01,
				"hint": "泡沫花纹的密度。太大变成细砂，太小变成大块斑。"},
			{"key": "edge_color", "label": "泡沫颜色", "kind": "color"},
			{"key": "edge_strength", "label": "泡沫强度", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.01},
		],
	},
	{
		"name": "shore",
		"label": "岸线泡沫",
		"note": "用与旧方案同一张岸线距离图，所以两套水的岸边泡沫落在同一位置。",
		"rows": [
			{"key": "shore_foam_width", "label": "带宽", "kind": "float",
				"min": 0.0, "max": 3.0, "step": 0.01, "unit": "m"},
			{"key": "shore_foam_strength", "label": "强度", "kind": "float",
				"min": 0.0, "max": 1.5, "step": 0.01},
			{"key": "shore_foam_color", "label": "颜色", "kind": "color"},
		],
	},
	{
		"name": "ripples",
		"label": "桨环",
		"note": "船桨划出的环。这一套是提亮，不画墨线。",
		"rows": [
			{"key": "ripple_ring_strength", "label": "提亮强度", "kind": "float",
				"min": 0.0, "max": 1.5, "step": 0.01},
			{"key": "ripple_ring_radius", "label": "环半径倍率", "kind": "float",
				"min": 0.2, "max": 3.0, "step": 0.01,
				"hint": "环向外扩的速度倍率。大＝划一次推开更远。"},
		],
	},
	{
		"name": "caustics",
		"label": "焦散",
		"note": "浅水底部的光网。默认关：只在能看清水底时才值得开。",
		"rows": [
			{"key": "caustics_enabled", "label": "启用焦散", "kind": "bool"},
			{"key": "caustic_size", "label": "网格尺度", "kind": "float",
				"min": 0.0, "max": 8.0, "step": 0.01},
			{"key": "caustic_range", "label": "可见深度", "kind": "float",
				"min": 1.0, "max": 256.0, "step": 0.1, "unit": "m",
				"hint": "深过这个值就看不到光网了。"},
			{"key": "caustic_strength", "label": "强度", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.01},
		],
	},
	{
		"name": "waves",
		"label": "波浪几何",
		"note": "四条波写在 water_surface.gd，两套水共用，这里只控制总波幅。",
		"rows": [
			{"key": "wave_scale", "label": "总波幅", "kind": "node",
				"min": 0.0, "max": 2.0, "step": 0.05, "default": 1.0,
				"hint": "顶点位移的倍率，船吃水也跟着变。两套水共用同一个节点属性。"},
		],
	},
	{
		"name": "output",
		"label": "输出",
		"note": "水面纯自发光，最后一步的整体缩放。",
		"rows": [
			{"key": "exposure_comp", "label": "曝光补偿", "kind": "float",
				"min": 0.2, "max": 2.5, "step": 0.01,
				"hint": "整片水的亮度。和 WorldEnvironment 的曝光是两个东西。"},
			{"key": "dither_strength", "label": "抖动", "kind": "float",
				"min": 0.0, "max": 4.0, "step": 0.05,
				"hint": "屏幕空间静态抖动，用来打散 8 位色带。"},
		],
	},
]


## 这一套暂时没有内置预设：它的出厂值就是 `water_absorption.tres`，
## 面板的「出厂」项直接读资源，够用。留着同名接口是为了面板代码两套共用。
static var BUILTIN_PRESETS := []


static func builtin(name: String) -> Dictionary:
	for p in BUILTIN_PRESETS:
		if String(p.name) == name:
			return p
	return {}


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
