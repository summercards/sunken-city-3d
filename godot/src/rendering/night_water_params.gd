extends RefCounted
## Runtime defaults let old user-saved materials acquire the new night controls
## without rewriting their existing daylight values or requiring a source save.
const DEFAULTS := {
	"night_albedo":Color(0.40,0.48,0.59,1.0),
	"night_deep_albedo":Color(0.18,0.29,0.44,1.0),
	"night_depth_distance":5.0,
	"night_shallow_opacity":0.32,
	"night_roughness":0.36,
}
const GROUP := {
	"name":"night","label":"夜间受光与水深",
	"note":"真实灯光照射波面；浅水透视、深水渐暗。只影响夜间。",
	"rows":[
		{"key":"night_albedo","label":"夜间浅水色","kind":"color"},
		{"key":"night_deep_albedo","label":"夜间深水色","kind":"color"},
		{"key":"night_depth_distance","label":"夜间深水距离","kind":"float","min":1.0,"max":16.0,"step":0.1},
		{"key":"night_shallow_opacity","label":"夜间浅水不透明度","kind":"float","min":0.1,"max":0.9,"step":0.01},
		{"key":"night_roughness","label":"夜海粗糙度","kind":"float","min":0.08,"max":1.0,"step":0.01},
	],
}
static func ensure_defaults(material: ShaderMaterial) -> void:
	for key in DEFAULTS:
		if material.get_shader_parameter(key)==null:
			material.set_shader_parameter(key,DEFAULTS[key])
