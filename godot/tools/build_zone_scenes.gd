extends SceneTree
## 把区块模型（assets/models/zones/<zone>/units/*.glb）落成区块场景里的真实节点。
##
## 以前区块 tscn 里只有 ModelRoot，几何是 model_zone.gd 在 _ready() 里读 manifest
## 现装的 —— 编辑器里能看但抓不住（运行时节点不落盘）。这里改成：
##
##   [node name="Models" type="Node3D"]
##     [node name="detail"  instance=glb]  ← 真实实例节点，可选中/移动/替换
##       root/detail: MeshInstance3D + surface_material_override（共享 .tres）
##
## 材质按 (贴图, 深染, unlit, 透明, 双面) 去重写成 assets/materials/models/*.tres，
## 与 BakeStore.material() 的参数逐项相同，画面不会变。
##
## 生成区间用 `; >>> models` / `; <<< models` 包住，重复运行只替换这一段。

const ZONES := [
	"zone1_home_harbor", "zone2_yokohama_station", "zone3_arc_farm",
	"zone4_far_shore", "zone5_aqua_platform",
]
const MAT_DIR := "res://assets/materials/models"
const WATER_LEVEL := 1.12
const BEGIN := "; >>> models（由 tools/build_zone_scenes.gd 生成，手改会被覆盖）"
const END := "; <<< models"

var mat_files := {}   # key -> file name
var mat_lines := {}   # key -> tres 文本


func _init() -> void:
	if not FileAccess.file_exists("res://.sea-generation-candidate"):
		printerr("Refusing to overwrite authored resources; use scripts/create_generation_candidate.py")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAT_DIR))
	for zone in ZONES:
		_build_zone(zone)
	_write_materials()
	print("[zone-scenes] materials=", mat_files.size())
	quit()


func _build_zone(zone: String) -> void:
	var tscn := "res://scenes/zones/%s.tscn" % zone
	var manifest_path := "res://assets/models/zones/%s/manifest.json" % zone
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if manifest == null:
		push_error("manifest 读不到: " + manifest_path)
		return

	var txt := FileAccess.get_file_as_string(tscn)
	if txt.is_empty():
		push_error("场景读不到: " + tscn)
		return

	# 区块根的位置：模型单元的 origin 是世界坐标，节点要摆在相对位置。
	var base := _root_origin(txt)

	# 清掉旧的两样东西：ModelRoot 节点（运行时装配）与它引用的脚本。
	txt = txt.replace('[ext_resource type="Script" path="res://scripts/world/model_zone.gd" id="5_model"]\n', "")
	txt = _drop_block(txt, '[node name="ModelRoot"')

	var unit_exts := PackedStringArray()
	var mat_exts := PackedStringArray()
	var body := PackedStringArray()
	body.append(BEGIN)
	body.append('[node name="Models" type="Node3D" parent="."]')
	var mi_paths := 0

	var dir := manifest_path.get_base_dir()
	for u in manifest.units:
		var uid := str(u.id)
		var glb := dir + "/" + str(u.file)
		var packed: Variant = load(glb)
		if packed == null:
			push_error("模型加载失败: " + glb)
			continue
		var ext_id := "unit_" + uid
		unit_exts.append('[ext_resource type="PackedScene" path="%s" id="%s"]' % [glb, ext_id])

		var probe: Node = packed.instantiate()
		var meshes := _mesh_nodes(probe, "")
		probe.free()

		var origin: Array = u.origin
		var pos := Vector3(float(origin[0]), float(origin[1]), float(origin[2])) - base
		body.append("")
		body.append('[node name="%s" parent="Models" instance=ExtResource("%s")]' % [uid, ext_id])
		body.append("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.3f, %.3f, %.3f)"
			% [pos.x, pos.y, pos.z])

		var slots: Array = u.get("slots", [])
		for rec in meshes:
			var rel: String = rec.path
			var surfaces: int = rec.surfaces
			body.append("")
			var parent_dir := "Models/" + uid + rel.get_base_dir()
			while parent_dir.ends_with("/"):
				parent_dir = parent_dir.substr(0, parent_dir.length() - 1)
			body.append('[node name="%s" parent="%s"]' % [rel.get_file(), parent_dir])
			for i in surfaces:
				var s: Dictionary = slots[i] if i < slots.size() else {}
				var key := _mat_key(s)
				var mfile: String
				if mat_files.has(key):
					mfile = mat_files[key]
				else:
					mfile = "baked_t%s_%d%d%d%d.tres" % [
						("n" if int(s.get("tex", -1)) < 0 else str(int(s.get("tex", -1)))),
						int(bool(s.get("tint", false))), int(bool(s.get("unlit", false))),
						int(bool(s.get("alpha", false))), int(bool(s.get("double_side", false))),
					]
					mat_files[key] = mfile
					mat_lines[key] = _mat_text(s)
				# 材质 ext_resource 每个场景文件里都要声明一次（同名 id、同路径）。
				var mid := "mat_" + mfile.get_basename().trim_prefix("baked_")
				var mline := '[ext_resource type="ShaderMaterial" path="%s/%s" id="%s"]' % [MAT_DIR, mfile, mid]
				if not mat_exts.has(mline):
					mat_exts.append(mline)
				body.append("surface_material_override/%d = ExtResource(\"%s\")" % [i, mid])
			body.append("cast_shadow = 1")
			body.append("gi_mode = 0")
			mi_paths += 1
	body.append(END)

	# 组文件：header + ext_resource + 原有节点（去掉 Models 区间）+ 新 Models 区间
	var had := txt.contains(BEGIN)
	if had:
		var b := txt.find(BEGIN)
		var e := txt.find(END)
		txt = txt.substr(0, b) + txt.substr(e + END.length() + 1)
	var zone_ext := PackedStringArray()
	var rest := PackedStringArray()
	var header := ""
	for line in txt.split("\n"):
		if line.begins_with("[ext_resource"):
			zone_ext.append(line)
		elif line.begins_with("[gd_scene"):
			header = line
		else:
			rest.append(line)

	var merged_ext := PackedStringArray()
	for line in zone_ext:
		if not line.contains("ShaderMaterial"):
			merged_ext.append(line)
	for line in unit_exts:
		if not merged_ext.has(line):
			merged_ext.append(line)
	var merged_mats := PackedStringArray()
	for line in zone_ext:
		if line.contains("ShaderMaterial") and not merged_mats.has(line):
			merged_mats.append(line)
	for line in mat_exts:
		if not merged_mats.has(line):
			merged_mats.append(line)
	merged_ext.append_array(merged_mats)

	var rest_txt := "\n".join(rest)
	if not rest_txt.contains('[node name="Models"'):
		pass
	# 插到 WalkAreas 之前（没有就追加到末尾）
	var anchor := rest_txt.find('[node name="WalkAreas"')
	var insert := "\n".join(body)
	if anchor >= 0:
		rest_txt = rest_txt.substr(0, anchor) + insert + "\n\n" + rest_txt.substr(anchor)
	else:
		rest_txt = rest_txt.rstrip("\n") + "\n\n" + insert + "\n"

	# geometry_source 改 scene；load_steps 重算
	rest_txt = rest_txt.replace('geometry_source = "models"', 'geometry_source = "scene"')
	var steps := merged_ext.size() + 1
	if header.is_empty():
		header = "[gd_scene load_steps=%d format=3]" % steps
	else:
		header = "[gd_scene load_steps=%d format=3]" % steps

	var out := header + "\n\n" + "\n".join(merged_ext) + "\n\n" + _strip_blank_run(rest_txt).strip_edges() + "\n" 
	var f := FileAccess.open(tscn, FileAccess.WRITE)
	f.store_string(out)
	f.close()
	print("[zone-scenes] %s  units=%d  meshes=%d  ext=%d" % [zone, manifest.units.size(), mi_paths, merged_ext.size()])


## 区块根的平移（Transform3D 的 9+3 个数里最后三个），没有 transform 就当原点。
func _root_origin(txt: String) -> Vector3:
	var i := txt.find("transform = Transform3D(")
	if i < 0:
		return Vector3.ZERO
	var open := txt.find("(", i)
	var j := txt.find(")", open)
	var nums := txt.substr(open + 1, j - open - 1).split(",")
	if nums.size() < 12:
		return Vector3.ZERO
	return Vector3(float(nums[9]), float(nums[10]), float(nums[11]))


## 删掉以 marker 开头的整个节点块（到下一个同级 [node ...] 为止）。
func _drop_block(txt: String, marker: String) -> String:
	var i := txt.find(marker)
	if i < 0:
		return txt
	var j := txt.find("\n[node ", i + marker.length())
	if j < 0:
		return txt.substr(0, i)
	return txt.substr(0, i) + txt.substr(j + 1)


## glb 实例里的 MeshInstance3D：路径相对 glb 根（用于 tscn 的 parent）与节点名。
func _mesh_nodes(root: Node, rel: String) -> Array:
	var out: Array = []
	for c in root.get_children():
		var child_rel := rel + "/" + str(c.name) if rel != "" else "/" + str(c.name)
		if c is MeshInstance3D:
			out.append({"path": child_rel, "name": str(c.name),
				"surfaces": (c as MeshInstance3D).mesh.get_surface_count()})
		out.append_array(_mesh_nodes(c, child_rel))
	return out


func _mat_key(s: Dictionary) -> String:
	return "%d|%d|%d|%d|%d" % [int(s.get("tex", -1)), int(bool(s.get("tint", false))),
		int(bool(s.get("unlit", false))), int(bool(s.get("alpha", false))),
		int(bool(s.get("double_side", false)))]


func _mat_text(s: Dictionary) -> String:
	var tex := int(s.get("tex", -1))
	var unlit := bool(s.get("unlit", false))
	var alpha := bool(s.get("alpha", false))
	var shader := "res://shaders/unlit.gdshader" if unlit else "res://shaders/toon.gdshader"
	if alpha:
		shader = shader.replace(".gdshader", "_alpha.gdshader")
	var ext := PackedStringArray()
	ext.append('[ext_resource type="Shader" path="%s" id="1_shader"]' % shader)
	var steps := 2
	if tex >= 0:
		ext.append('[ext_resource type="Texture2D" path="res://assets/baked/textures/tex_%d.png" id="2_tex"]' % tex)
		steps = 3
	var res := PackedStringArray()
	res.append("[resource]")
	res.append("render_priority = %d" % (1 if alpha else 0))
	res.append('shader = ExtResource("1_shader")')
	res.append("shader_parameter/use_texture = %s" % ("true" if tex >= 0 else "false"))
	if tex >= 0:
		res.append('shader_parameter/albedo_tex = ExtResource("2_tex")')
	res.append("shader_parameter/depth_tint = %s" % ("true" if bool(s.get("tint", false)) else "false"))
	res.append("shader_parameter/water_level = %.2f" % WATER_LEVEL)
	if bool(s.get("double_side", false)):
		res.append("shader_parameter/double_side = true")
	return "[gd_resource type=\"ShaderMaterial\" load_steps=%d format=3]\n\n%s\n\n%s\n" % [
		steps, "\n".join(ext), "\n".join(res)]


func _write_materials() -> void:
	for key in mat_files.keys():
		var path := "%s/%s" % [MAT_DIR, mat_files[key]]
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(mat_lines[key])
		f.close()
	print("[zone-scenes] 写入材质 ", mat_files.size(), " 个")


func _strip_blank_run(s: String) -> String:
	while s.contains("\n\n\n\n"):
		s = s.replace("\n\n\n\n", "\n\n\n")
	return s
