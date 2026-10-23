extends Node3D
## 一个海底区块。
##
## 海底不是一整张大地图，而是按内容拆成四个独立区块（岩盆 / 街区 / 珊瑚 / 海沟），
## 每个区块一个 tscn + 一份 glb 资产，各自可以单独替换、单独开关：
##
##   basin         岩盆 / 岩层 / 沙堆 / 珊瑚台地
##   neighborhood  沉没街区（12 栋民宅 / 断桥 / 路灯 / 车辆）
##   reef          珊瑚与海草
##   trench        北境海沟（海床 / 断崖 / 阶梯 / 海盗船）
##
## 区块内的单元由 manifest.json 驱动，坐标系与世界坐标一致（不做二次偏移）。

const MaterialLib = preload("res://src/diving/uw_materials.gd")

@export var region := ""
@export var region_label := ""
@export var manifest_path := ""

var units: Array = []
var instance_count := 0
var vertex_count := 0
var triangle_count := 0


func _ready() -> void:
	build()


func build() -> void:
	units.clear()
	if manifest_path.is_empty():
		push_warning("海底区块缺少 manifest_path")
		return
	var text := FileAccess.get_file_as_string(manifest_path)
	if text.is_empty():
		push_error("读不到 " + manifest_path)
		return
	var manifest: Variant = JSON.parse_string(text)
	if manifest == null or not (manifest is Dictionary):
		push_error("manifest 解析失败: " + manifest_path)
		return

	var dir := manifest_path.get_base_dir()
	for u in manifest.get("units", []):
		var path: String = dir + "/" + str(u.file)
		if not ResourceLoader.exists(path):
			push_warning("缺少海底模型 " + path)
			continue
		var packed: Variant = load(path)
		if packed == null:
			push_warning("海底模型加载失败 " + path)
			continue
		var node: Node3D = packed.instantiate()
		node.name = str(u.id)
		var o: Array = u.origin
		node.position = Vector3(float(o[0]), float(o[1]), float(o[2]))
		_apply_materials(node, u.get("slots", []))
		add_child(node)
		units.append(node)
		instance_count += int(u.get("instance_count", 0))
		vertex_count += int(u.get("vertices", 0))
		triangle_count += int(u.get("triangles", 0))


func _apply_materials(root: Node, slots: Array) -> void:
	for raw in _mesh_instances(root):
		var mi: MeshInstance3D = raw
		# imported material_override 优先级高于 surface override，必须先清除。
		mi.material_override = null
		var count: int = mi.mesh.get_surface_count()
		for i in count:
			if i >= slots.size():
				continue
			mi.set_surface_override_material(i, MaterialLib.get_material(slots[i]))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _mesh_instances(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	# glb 只有一个 MeshInstance3D，这里排序只是为了结果稳定
	out.sort_custom(func(a, b): return str(a.name) < str(b.name))
	return out


## 区块包围盒（世界坐标），用于相机/统计。
func world_bounds() -> AABB:
	var out := AABB()
	var first := true
	for u in units:
		for raw in _mesh_instances(u):
			var mi: MeshInstance3D = raw
			if mi.mesh == null:
				continue
			var b: AABB = mi.global_transform * mi.mesh.get_aabb()
			out = b if first else out.merge(b)
			first = false
	return out
