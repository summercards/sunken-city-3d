extends RefCounted
class_name UnderwaterSurfaceParams
## P 键「水下海面」页唯一参数清单。
## 这些值只控制从水下仰视海面的材质表现；水位、日照来源和水下场景切换不在此处改写。

const GROUPS := [
	{
		"name": "wave",
		"label": "波场与法线",
		"note": "复用水上波场；调大尺度先看形，再调法线细节。",
		"rows": [
			{"key":"underside_normal_metres","label":"法线尺度","kind":"float","min":1.0,"max":160.0,"step":0.5,"unit":"m","fmt":"%.1f","default":28.0},
			{"key":"underside_normal_strength","label":"法线强度","kind":"float","min":0.0,"max":2.0,"step":0.01,"default":0.36},
			{"key":"underside_wave_scale_x","label":"波场 X 尺度","kind":"float","min":0.05,"max":2.0,"step":0.01,"default":0.42},
			{"key":"underside_wave_scale_z","label":"波场 Z 尺度","kind":"float","min":0.05,"max":2.0,"step":0.01,"default":0.82},
			{"key":"underside_wave_time_scale","label":"波场时间倍率","kind":"float","min":0.0,"max":2.0,"step":0.01,"default":0.55},
			{"key":"underside_normal_scroll_x","label":"法线漂移 X","kind":"float","min":-0.05,"max":0.05,"step":0.0005,"fmt":"%.4f","default":0.006},
			{"key":"underside_normal_scroll_z","label":"法线漂移 Z","kind":"float","min":-0.05,"max":0.05,"step":0.0005,"fmt":"%.4f","default":0.003},
			{"key":"underside_normal_b_scale_x","label":"法线副层 X","kind":"float","min":0.1,"max":2.0,"step":0.01,"default":0.83},
			{"key":"underside_normal_b_scale_z","label":"法线副层 Z","kind":"float","min":0.1,"max":2.0,"step":0.01,"default":1.13},
			{"key":"underside_normal_b_scroll","label":"副层漂移倍率","kind":"float","min":-2.0,"max":2.0,"step":0.01,"default":0.73},
			{"key":"underside_normal_b_offset","label":"副层偏移","kind":"vec2","min":-1.0,"max":1.0,"step":0.01,"sub":["X","Z"],"default":Vector2(0.37,0.61)},
			{"key":"underside_wave_slope","label":"波坡法线倍率","kind":"float","min":0.0,"max":2.0,"step":0.01,"default":0.65},
			{"key":"underside_normal_influence","label":"视线扰动","kind":"float","min":0.0,"max":2.0,"step":0.01,"default":0.9},
			{"key":"underside_incident_normal_mix","label":"仰视混合","kind":"float","min":0.0,"max":1.0,"step":0.01,"default":0.55},
			]
	},
	{
		"name": "crest",
		"label": "波脊亮纹",
		"note": "只增加亮部，不乘黑污纹；亮纹太密时先收窄波脊阈值。",
		"rows": [
			{"key":"underside_wave_light","label":"波光强度","kind":"float","min":0.0,"max":2.0,"step":0.01,"default":0.85},
			{"key":"underside_ridge_low","label":"波脊起点","kind":"float","min":-0.5,"max":0.5,"step":0.005,"default":0.025},
			{"key":"underside_ridge_high","label":"波脊终点","kind":"float","min":-0.5,"max":0.8,"step":0.005,"default":0.105},
			{"key":"underside_ridge_strip_mix","label":"法线混入波脊","kind":"float","min":0.0,"max":0.2,"step":0.001,"fmt":"%.3f","default":0.018},
			{"key":"underside_break_low","label":"断续起点","kind":"float","min":0.0,"max":1.0,"step":0.01,"default":0.43},
			{"key":"underside_break_high","label":"断续终点","kind":"float","min":0.0,"max":1.0,"step":0.01,"default":0.58},
			{"key":"underside_break_floor","label":"最低覆盖","kind":"float","min":0.0,"max":1.0,"step":0.01,"default":0.35},
			{"key":"underside_break_gain","label":"断续变化量","kind":"float","min":0.0,"max":1.0,"step":0.01,"default":0.65},
			{"key":"underside_crest_up_low","label":"仰角起点","kind":"float","min":-1.0,"max":1.0,"step":0.01,"default":0.02},
			{"key":"underside_crest_up_high","label":"仰角终点","kind":"float","min":-1.0,"max":1.0,"step":0.01,"default":0.55},
		]
	},
	{
		"name": "colour",
		"label": "蓝面颜色",
		"note": "调色先保持蓝面干净；不要用黑色压纹制造脏感。",
		"rows": [
			{"key":"underside_body_bottom","label":"底部蓝色","kind":"color","default":Color(0.045,0.31,0.66,1)},
			{"key":"underside_body_top","label":"顶部蓝色","kind":"color","default":Color(0.13,0.57,0.86,1)},
			{"key":"underside_crest_colour","label":"波脊颜色","kind":"color","default":Color(0.77,0.97,1.0,1)},
			{"key":"underside_crest_depth_min","label":"深处波脊下限","kind":"float","min":0.0,"max":2.0,"step":0.01,"default":0.65},
			{"key":"underside_crest_depth_max","label":"浅处波脊上限","kind":"float","min":0.0,"max":2.0,"step":0.01,"default":1.0},
			{"key":"underside_daylight_floor","label":"无日光底亮","kind":"float","min":0.0,"max":1.0,"step":0.01,"default":0.16},
			{"key":"underside_depth_near","label":"深度减光起点","kind":"float","min":0.0,"max":40.0,"step":0.1,"unit":"m","default":2.0},
			{"key":"underside_depth_far","label":"深度减光终点","kind":"float","min":1.0,"max":200.0,"step":0.5,"unit":"m","default":120.0},
			{"key":"underside_depth_light_shallow","label":"浅层减光倍率","kind":"float","min":0.0,"max":2.0,"step":0.01,"default":1.0},
			{"key":"underside_depth_light_deep","label":"深层减光倍率","kind":"float","min":0.0,"max":2.0,"step":0.01,"default":0.46},
		]
	},
	{
		"name": "sun",
		"label": "太阳高光",
		"note": "太阳方向和强度仍来自主场景 Sun；这里调的是水面高光形状。",
		"rows": [
			{"key":"underside_sun_light","label":"太阳光强度","kind":"float","min":0.0,"max":2.0,"step":0.01,"default":0.80},
			{"key":"underside_sun_ior","label":"水面 IOR","kind":"float","min":1.0,"max":1.5,"step":0.001,"fmt":"%.3f","default":1.333},
			{"key":"underside_sun_sharpness","label":"高光锐度","kind":"float","min":1.0,"max":2000.0,"step":1.0,"fmt":"%.0f","default":360.0},
			{"key":"underside_sun_variance_divisor","label":"高光抗闪除数","kind":"float","min":1.0,"max":100.0,"step":0.5,"default":24.0},
			{"key":"underside_sun_lobe_gain","label":"高光峰值","kind":"float","min":0.0,"max":10.0,"step":0.01,"default":2.2},
			{"key":"underside_sun_core_mix","label":"太阳核心占比","kind":"float","min":0.0,"max":2.0,"step":0.01,"default":0.75},
			{"key":"underside_sun_halo_power","label":"太阳晕锐度","kind":"float","min":1.0,"max":80.0,"step":0.5,"default":24.0},
			{"key":"underside_sun_halo_mix","label":"太阳晕占比","kind":"float","min":0.0,"max":2.0,"step":0.01,"default":0.26},
			{"key":"underside_sun_max_mix","label":"高光最大混合","kind":"float","min":0.0,"max":1.0,"step":0.01,"default":0.88},
			{"key":"underside_sun_display_colour","label":"高光颜色","kind":"color","default":Color(0.94,0.99,1.0,1)},
		]
	},
	{
		"name": "edge",
		"label": "边界与时间",
		"note": "远处水面提前融进统一水雾；不要用边界参数修近处脏纹。",
		"rows": [
			{"key":"underside_surface_edge_near","label":"边界淡出起点","kind":"float","min":0.0,"max":250.0,"step":0.5,"unit":"m","default":125.0},
			{"key":"underside_surface_edge_far","label":"边界淡出终点","kind":"float","min":1.0,"max":300.0,"step":0.5,"unit":"m","default":190.0},
			{"key":"underside_edge_gradient_mix","label":"水雾融合量","kind":"float","min":0.0,"max":1.0,"step":0.01,"default":1.0},
			{"key":"underside_display_max","label":"显示色上限","kind":"float","min":0.1,"max":1.0,"step":0.001,"fmt":"%.3f","default":0.98},
		]
	},
]

static func flat() -> Dictionary:
	var out := {}
	for group in GROUPS:
		for row in group.rows:
			var item: Dictionary = row.duplicate(true)
			item["group"] = group.name
			out[item.key] = item
	return out

static func defaults() -> Dictionary:
	var out := {}
	for key in flat().keys():
		var spec: Dictionary = flat()[key]
		if spec.has("default"):
			out[key] = spec.default
	return out
