extends RefCounted
## P 面板「光照」页的参数清单：WorldEnvironment 的光照/大气/后处理 + 太阳光。
##
## 为什么单独一份清单：`water_params.gd` 管的是着色器 uniform，这份管的是
## **引擎对象属性**（`Environment` 与 `DirectionalLight3D` 的 `set_indexed`）。
## 两者的写入路径、复位来源、写回目标都不同，硬塞进一张表只会到处 if。
##
## 每行字段：
##   key    —— 面板内部键，也是 `user://filter.cfg` 的键名，改名等于丢存档
##   label  —— 中文名
##   target —— `env`（WorldEnvironment 的 Environment）或 `sun`（World/Lights/Sun）
##   prop   —— Godot 属性名，允许 `a:b` 的子属性写法；`dir:elevation` / `dir:azimuth`
##             是太阳朝向的两个虚拟轴，没有同名属性，由面板换算成朝向
##   kind   —— `float` / `bool` / `color`
##   min/max/step/fmt —— 浮点行用；范围必须包住 `world_env.tres` 与
##             `scenes/main.tscn` 里的出厂值，否则一开面板就把场景改坏
##
## 这一份清单被 `tools/check_light_params.gd` 静态核对：属性名写错、范围包不住
## 出厂值都会当场报红，不用等到打开面板才看见滑块停在端点。
##
## 不进清单的属性都写清理由：
##   ambient_light_source / reflected_light_source：枚举，改了等于换一套光照模型
##   tonemap_mode：枚举，改了整幅画面的映射曲线，不是调参
##   fog_mode：本项目固定用 depth 模式，切到指数模式雾浓度才生效
##   fog_density / fog_height / fog_height_density：depth 模式下不参与计算
##   volumetric_fog_*：项目没开体积雾，列表再长也是空转
##   sdfgi_* / ssil_* / ssr_*：项目未启用，开了是另一套性能账
##   glow_levels/1..7：斜坡权重，属于「换泛光型号」而不是日常调参

const TARGET_ENV := "env"
const TARGET_SUN := "sun"

const GROUPS := [
	{
		"id": "environment",
		"label": "环境",
		"note": "天空亮度、环境光、泛光、环境遮蔽与雾。环境光是阴影里的全部亮度来源，压到 0 会整片发黑。",
		"rows": [
			# ---- 环境光 --------------------------------------------------
			{"key": "ambient_energy", "label": "环境光", "target": TARGET_ENV,
				"prop": "ambient_light_energy", "kind": "float",
				"min": 0.0, "max": 2.0, "step": 0.01, "fmt": "%.2f",
				"hint": "阴影里的填充亮度。0.36 是出厂值，低于 0.2 背光面会糊成一块。"},
			{"key": "ambient_color", "label": "环境光色", "target": TARGET_ENV,
				"prop": "ambient_light_color", "kind": "color",
				"hint": "环境光的颜色，同时决定阴影偏冷还是偏暖。"},
			{"key": "ambient_sky", "label": "天空占比", "target": TARGET_ENV,
				"prop": "ambient_light_sky_contribution", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.01, "fmt": "%.2f",
				"hint": "环境光里有多少来自天空贴图。1 = 全用天空，0 = 全用上面的环境光色。"},
			{"key": "sky_energy", "label": "天空亮度", "target": TARGET_ENV,
				"prop": "background_energy_multiplier", "kind": "float",
				"min": 0.0, "max": 2.0, "step": 0.01, "fmt": "%.2f",
				"hint": "天空盒本身的亮度倍率。只改天空和它给的环境光，不改太阳。"},

			# ---- 泛光 ----------------------------------------------------
			{"key": "glow_enabled", "label": "泛光", "target": TARGET_ENV,
				"prop": "glow_enabled", "kind": "bool",
				"hint": "开启后亮部会往外渗光。水面高光和水线发亮主要靠它。"},
			{"key": "glow_intensity", "label": "泛光强度", "target": TARGET_ENV,
				"prop": "glow_intensity", "kind": "float",
				"min": 0.0, "max": 2.0, "step": 0.01, "fmt": "%.2f",
				"hint": "渗出光的强弱。0.38 是出厂值。"},
			{"key": "glow_bloom", "label": "泛光光晕", "target": TARGET_ENV,
				"prop": "glow_bloom", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.005, "fmt": "%.3f",
				"hint": "整幅画面加的一层柔光。超过 0.1 会明显发灰，卡通画风慎用。"},
			{"key": "glow_threshold", "label": "泛光阈值", "target": TARGET_ENV,
				"prop": "glow_hdr_threshold", "kind": "float",
				"min": 0.0, "max": 4.0, "step": 0.05, "fmt": "%.2f",
				"hint": "多亮才开始渗光。调低会把云也点亮，调高只剩太阳和水面高光。"},

			# ---- 环境遮蔽 -------------------------------------------------
			{"key": "ssao_enabled", "label": "环境遮蔽", "target": TARGET_ENV,
				"prop": "ssao_enabled", "kind": "bool",
				"hint": "墙角、船底、建筑夹缝里的暗部接触阴影。"},
			{"key": "ssao_intensity", "label": "遮蔽强度", "target": TARGET_ENV,
				"prop": "ssao_intensity", "kind": "float",
				"min": 0.0, "max": 2.0, "step": 0.01, "fmt": "%.2f",
				"hint": "接触阴影有多黑。0.46 是出厂值。"},
			{"key": "ssao_radius", "label": "遮蔽半径", "target": TARGET_ENV,
				"prop": "ssao_radius", "kind": "float",
				"min": 0.1, "max": 8.0, "step": 0.05, "fmt": "%.2f",
				"hint": "遮蔽探索的距离（米）。半径越大，阴影越宽越糊。"},
			{"key": "ssao_light", "label": "遮蔽受光", "target": TARGET_ENV,
				"prop": "ssao_light_affect", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.01, "fmt": "%.2f",
				"hint": "环境遮蔽对直射光的抵消比例。调高会让受光面也压暗。"},

			# ---- 雾 ------------------------------------------------------
			{"key": "fog_enabled", "label": "雾", "target": TARGET_ENV,
				"prop": "fog_enabled", "kind": "bool",
				"hint": "远景的空气雾。出厂是 depth 模式且密度为 0，靠下面的起止距离控制。"},
			{"key": "fog_color", "label": "雾色", "target": TARGET_ENV,
				"prop": "fog_light_color", "kind": "color",
				"hint": "雾的颜色，出厂和海面同色，所以远景会融进海平线。"},
			{"key": "fog_energy", "label": "雾受光", "target": TARGET_ENV,
				"prop": "fog_light_energy", "kind": "float",
				"min": 0.0, "max": 4.0, "step": 0.01, "fmt": "%.2f",
				"hint": "雾被太阳照亮的程度。"},
			{"key": "fog_begin", "label": "雾起点", "target": TARGET_ENV,
				"prop": "fog_depth_begin", "kind": "float",
				"min": 0.0, "max": 600.0, "step": 5.0, "fmt": "%.0f", "unit": "m",
				"hint": "从多远开始起雾。近处不该有雾，不然船的轮廓会被糊掉。"},
			{"key": "fog_end", "label": "雾终点", "target": TARGET_ENV,
				"prop": "fog_depth_end", "kind": "float",
				"min": 10.0, "max": 1500.0, "step": 10.0, "fmt": "%.0f", "unit": "m",
				"hint": "到这个距离完全变成雾色。必须大于雾起点。"},
			{"key": "fog_curve", "label": "雾曲率", "target": TARGET_ENV,
				"prop": "fog_depth_curve", "kind": "float",
				"min": 0.0, "max": 3.0, "step": 0.05, "fmt": "%.2f",
				"hint": "起雾的过渡曲线。小于 1 更早变浓，大于 1 更晚。"},
			{"key": "fog_sky", "label": "雾及天空", "target": TARGET_ENV,
				"prop": "fog_sky_affect", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.01, "fmt": "%.2f",
				"hint": "雾覆盖天空的比例。0 = 天空不受雾影响，海平线接缝会露出来。"},
		],
	},
	{
		"id": "sun",
		"label": "太阳",
		"note": "World/Lights/Sun 这盏平行光。高度角改的是朝向，阴影框和阴影浓度跟着它走。",
		"rows": [
			{"key": "sun_energy", "label": "太阳强度", "target": TARGET_SUN,
				"prop": "light_energy", "kind": "float",
				"min": 0.0, "max": 3.0, "step": 0.01, "fmt": "%.2f",
				"hint": "主光亮度。0.54 是出厂值，配合环境光 0.36 定下的整体曝光。"},
			{"key": "sun_color", "label": "太阳颜色", "target": TARGET_SUN,
				"prop": "light_color", "kind": "color",
				"hint": "出厂的暖白（1, 0.955, 0.8）偏黄昏一点，别调太黄会把水面染成绿的。"},
			{"key": "sun_angular", "label": "太阳角径", "target": TARGET_SUN,
				"prop": "light_angular_distance", "kind": "float",
				"min": 0.0, "max": 10.0, "step": 0.05, "fmt": "%.2f", "unit": "°",
				"hint": "光源的视直径。越大阴影边缘越软；0 是硬边阴影。"},
			{"key": "sun_elevation", "label": "高度角", "target": TARGET_SUN,
				"prop": "dir:elevation", "kind": "float",
				"min": 1.0, "max": 89.0, "step": 0.5, "fmt": "%.1f", "unit": "°",
				"hint": "太阳离海平面的高度。低角度拉长影子、水面高光拉成一条路。"},
			{"key": "sun_azimuth", "label": "方位角", "target": TARGET_SUN,
				"prop": "dir:azimuth", "kind": "float",
				"min": -180.0, "max": 180.0, "step": 0.5, "fmt": "%.1f", "unit": "°",
				"hint": "太阳绕一圈的位置（0 = 正前方）。改它等于换个时段和投影方向。"},
			{"key": "sun_shadow", "label": "投射阴影", "target": TARGET_SUN,
				"prop": "shadow_enabled", "kind": "bool",
				"hint": "关掉整个场景就没有投影，只留照明。"},
			{"key": "sun_shadow_opacity", "label": "阴影浓度", "target": TARGET_SUN,
				"prop": "shadow_opacity", "kind": "float",
				"min": 0.0, "max": 1.0, "step": 0.01, "fmt": "%.2f",
				"hint": "1 = 全黑阴影。卡通画风通常留在 0.8 上下，留一点环境光透进去。"},
			{"key": "sun_shadow_blur", "label": "阴影模糊", "target": TARGET_SUN,
				"prop": "shadow_blur", "kind": "float",
				"min": 0.0, "max": 8.0, "step": 0.1, "fmt": "%.1f",
				"hint": "阴影边缘的柔化。和「太阳角径」叠加生效。"},
			{"key": "sun_shadow_bias", "label": "阴影偏移", "target": TARGET_SUN,
				"prop": "shadow_bias", "kind": "float",
				"min": 0.0, "max": 0.5, "step": 0.005, "fmt": "%.3f",
				"hint": "防止自阴影痤疮。太小出现条纹噪点，太大会让阴影和物体脱开。"},
			{"key": "sun_shadow_normal", "label": "法线偏移", "target": TARGET_SUN,
				"prop": "shadow_normal_bias", "kind": "float",
				"min": 0.0, "max": 3.0, "step": 0.05, "fmt": "%.2f",
				"hint": "沿法线方向推开采样点，专治薄面（船帆、栏杆）的阴影撕裂。"},
			{"key": "sun_shadow_distance", "label": "阴影距离", "target": TARGET_SUN,
				"prop": "directional_shadow_max_distance", "kind": "float",
				"min": 20.0, "max": 400.0, "step": 5.0, "fmt": "%.0f", "unit": "m",
				"hint": "阴影覆盖到多远。相机在 108 m 外，小于 150 会让远处建筑掉出阴影框。"},
		],
	},
]


## 摊平成 key → row。面板按 key 找行，避免每次遍历分组。
static func flat() -> Dictionary:
	var out := {}
	for g in GROUPS:
		for row in g.rows:
			out[String(row.key)] = row
	return out


## 键盘的顺序（分组的声明顺序，不能靠字典 key 顺序）。
static func keys() -> Array[String]:
	var out: Array[String] = []
	for g in GROUPS:
		for row in g.rows:
			out.append(String(row.key))
	return out


## 某一页的存档段名。写进 `user://filter.cfg`。
static func section_of(target: String) -> String:
	return "environment" if target == TARGET_ENV else "sun"
