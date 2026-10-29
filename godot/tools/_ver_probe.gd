extends SceneTree
## 只读探针：分别检查着色器能否枚举 uniform，以及材质里参数是否还在。
## 不写任何文件。

func _initialize() -> void:
	print("[ver] ", Engine.get_version_info()["string"])

	for p in [
		"res://shaders/sunny_palette.gdshader",
		"res://shaders/sunny_palette_gloss.gdshader",
		"res://shaders/water.gdshader",
		"res://shaders/toon.gdshader",
	]:
		var sh: Shader = load(p)
		if sh == null:
			print("[shader] ", p.get_file(), " LOAD FAIL")
			continue
		var ul := sh.get_shader_uniform_list()
		print("[shader] ", p.get_file(), " uniforms=", ul.size(),
			" code_lines=", sh.code.split("\n").size())

	for p in [
		"res://assets/materials/solar_cabin/sunny_matte.tres",
		"res://assets/materials/solar_cabin/sunny_metal.tres",
		"res://assets/materials/solar_cabin/sunny_gloss.tres",
		"res://assets/materials/solar_cabin/sunny_emission.tres",
		"res://assets/materials/water.tres",
	]:
		var mat: ShaderMaterial = load(p) as ShaderMaterial
		if mat == null:
			print("[mat] ", p.get_file(), " LOAD FAIL")
			continue
		var total := 0
		var set_n := 0
		if mat.shader != null:
			for u in mat.shader.get_shader_uniform_list():
				total += 1
				if mat.get_shader_parameter(u.get("name")) != null:
					set_n += 1
		print("[mat] ", p.get_file(),
			" shader=", (mat.shader != null),
			" uniforms=", total,
			" 有值=", set_n,
			" palette=", "<set>" if mat.get_shader_parameter("palette") != null else "<NULL>")
	quit()
