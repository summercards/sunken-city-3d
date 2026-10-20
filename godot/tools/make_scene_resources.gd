extends SceneTree
## 生成场景里可手动编辑的资源文件：世界环境 + 水面材质。
##
## 为什么用脚本导出而不是手写 .tres：
## Environment 的属性名与枚举值在版本间会变（fog_mode / tonemap_mode / ambient_light_source），
## ShaderMaterial 的着色器参数更是要靠 set_shader_parameter 才准确。脚本构造一次再保存，
## 保证与运行时逐项一致。
##
## 用法：Godot --headless --path . --script res://tools/make_scene_resources.gd

const OUT_DIR := "res://assets/materials/"
const WATER_SHADER := "res://shaders/water.gdshader"
const WATER_LEVEL := 1.12


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save_env()
	_save_water()
	quit()


func _save_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#176d9a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#fff6d6")
	env.ambient_light_energy = 0.56
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.96
	# 滤镜默认值：1.0 = 不改变。P 键面板调的就是这三个。
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.0
	env.adjustment_saturation = 1.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("#176d9a")
	env.fog_density = 0.0
	env.fog_depth_begin = 200.0
	env.fog_depth_end = 520.0
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0
	env.ssao_enabled = false
	env.glow_enabled = false
	var path := OUT_DIR + "world_env.tres"
	ResourceSaver.save(env, path)
	print("[resources] %s  ambient=%.2f sun-independent" % [path, env.ambient_light_energy])


func _save_water() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load(WATER_SHADER)
	mat.render_priority = 2
	mat.set_shader_parameter("u_time", 0.0)
	mat.set_shader_parameter("water_level", WATER_LEVEL)
	mat.set_shader_parameter("fog_color", Color("#176d9a"))
	mat.set_shader_parameter("fog_range", Vector2(200, 520))
	mat.set_shader_parameter("surface_contrast", 0.25)
	var path := OUT_DIR + "water.tres"
	ResourceSaver.save(mat, path)
	print("[resources] %s" % path)
