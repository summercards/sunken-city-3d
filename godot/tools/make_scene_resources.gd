extends SceneTree
## 重新保存场景可编辑资源，保留当前海洋环境及美术调参。
## 正本是 assets/materials/*.tres；不再从旧网页版硬编码默认值重置。
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
	# The authored resource is now the source of truth; never reset the ocean sky,
	# light balance or a user's grade to the old web-port defaults.
	var env := (load(OUT_DIR + "world_env.tres") as Environment).duplicate() as Environment
	var path := OUT_DIR + "world_env.tres"
	ResourceSaver.save(env, path)
	print("[resources] %s  ambient=%.2f sun-independent" % [path, env.ambient_light_energy])


func _save_water() -> void:
	var mat := (load(OUT_DIR + "water.tres") as ShaderMaterial).duplicate() as ShaderMaterial
	var path := OUT_DIR + "water.tres"
	ResourceSaver.save(mat, path)
	print("[resources] %s" % path)
