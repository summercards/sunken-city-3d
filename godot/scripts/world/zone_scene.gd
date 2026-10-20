@tool
extends Node3D
## 区块场景根节点。
##
## 一个区块 = 一个 tscn，里面固定是五块：
##   Models       建筑几何（glb 实例节点，编辑器里可直接选中/移动/替换）
##   StaticBatch  烘焙实例批次（MultiMesh，不可编辑；对比/回退用）
##   WalkAreas    可以行走的区域（每块甲板/平台一个节点）
##   Plants       植物（通用 + 专用，按摆放表生成，随建造等级显隐）
##   Landings     上岸点（供点击导航）
##
## 区块内的坐标全部相对本节点；本节点的 transform 就是 zones.json 的 origin。

const ZoneBatch = preload("res://scripts/world/zone_batch.gd")
const WalkArea = preload("res://scripts/world/walk_area.gd")
const PlantField = preload("res://scripts/plants/plant_field.gd")

@export var zone_id := ""
@export var zone_label := ""
## 静态几何来源：
##   scene —— Models 节点里的 glb 实例（场景资产，默认，可手动编辑）
##   baked —— assets/zones/*/instances.bin（实例批次，回退/对比用）
@export_enum("scene", "baked") var geometry_source := "scene"

var walk_areas: Array = []
var batch: Node3D = null
var models: Node3D = null
var plants: Node3D = null
var _timed: Array = []


func _enter_tree() -> void:
	# 子节点的 _ready 比父节点早，必须在 _enter_tree 里先决定谁生效，
	# 否则烘焙批次会和场景里的建筑各建一份。
	var b := get_node_or_null("StaticBatch")
	if b != null and "enabled" in b:
		b.enabled = geometry_source == "baked"
	var m := get_node_or_null("Models")
	if m is Node3D:
		(m as Node3D).visible = geometry_source != "baked"


func _ready() -> void:
	_register()
	_collect_timed()


func _register() -> void:
	walk_areas.clear()
	batch = null
	models = null
	plants = null
	for child in get_children():
		if child.name == "Models":
			models = child
		elif child is ZoneBatch or child.get_script() == ZoneBatch:
			batch = child
		elif child.get_script() == PlantField:
			plants = child
		elif child.name == "WalkAreas":
			for walk in child.get_children():
				if walk.get_script() == WalkArea:
					walk_areas.append(walk)


## 场景里的材质是共享 .tres（一个材质给多个单元用），收集一次即可。
func _collect_timed() -> void:
	_timed.clear()
	if models == null:
		return
	var seen := {}
	var stack: Array = [models]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				for i in mi.mesh.get_surface_count():
					var m := mi.get_surface_override_material(i)
					if m is ShaderMaterial and not seen.has(m.get_instance_id()):
						seen[m.get_instance_id()] = true
						_timed.append(m)
		stack.append_array(n.get_children())


## 运行时切换几何来源（对比验收用）。
func set_geometry_source(src: String) -> void:
	# 旧的调试参数还会传 "models"，现在实体几何就是那条路。
	if src == "models":
		src = "scene"
	if src == geometry_source:
		return
	geometry_source = src
	if batch != null:
		batch.enabled = src == "baked"
		for c in batch.get_children():
			c.queue_free()
		batch.batch_count = 0
		batch.instance_count = 0
		if src == "baked":
			batch.build()
	if models != null:
		models.visible = src != "baked"


## 命中最靠前的可行走区域，返回 {area, point, distance}；没有命中返回 {}。
func pick_walk(origin: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	var best_t := INF
	for area in walk_areas:
		var t: float = area.pick(origin, dir)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = {"area": area, "distance": t, "point": origin + dir * t}
	return best


func area_containing(x: float, z: float) -> Variant:
	for area in walk_areas:
		if area.contains_world(x, z):
			return area
	return null


## 站在某点时应该踩的高度；不在任何区域内返回 NAN。
func floor_height_at(x: float, z: float) -> float:
	var area: Variant = area_containing(x, z)
	return area.surface_y if area != null else NAN


func set_zone_level(level: int, instant := false) -> void:
	if plants != null and plants.has_method("set_zone_level"):
		plants.set_zone_level(level, instant)


func update_time(t: float) -> void:
	if batch != null and batch.has_method("update_time"):
		batch.update_time(t)
	for mat in _timed:
		mat.set_shader_parameter("u_time", t)
