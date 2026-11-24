@tool
extends Node3D
## 区块场景根节点。
##
## 一个区块 = 一个 tscn，地面/泊位与独立物件均在场景里编辑：
##   Models       建筑几何（glb 实例节点，编辑器里可直接选中/移动/替换）
##   WalkAreas    共用行走地面；Landing_* 是地面子节点，定义上岸点与停船锚点
##   Plants       植物（通用 + 专用，按摆放表生成，随建造等级显隐）
##   Objects      独立玩法物件（菜箱场景实例等）
##
## 场景实例变换决定实际摆位，zones.json 保存初摆参考。

const PlantField = preload("res://src/ambient/plant_field.gd")
const BlockerSet = preload("res://src/world/blocker_set.gd")
const GroundSpace = preload("res://src/navigation/ground_space.gd")

@export var zone_id := ""
@export var zone_label := ""
## 水层归属。区块与海上结构物一律是空间实体，所以这里只有层没有 role。
## 规则见 docs/standards/水层分类与空间职责.md；空串表示未登记，由 water-layer 专项报错。
@export_enum("surface", "amphibious", "submerged", "backdrop") var water_layer := ""
@export var water_layer_role := "entity"
var walk_areas: Array = []
var models: Node3D = null
var plants: Node3D = null
var water_block_rects: Array[Rect2] = []
var _timed: Array = []
var ground_space: Node3D


func _ready() -> void:
	_register()
	if not Engine.is_editor_hint():
		preload("res://src/ambient/lily_migration.gd").install(self,get_node_or_null("Models"))
		ground_space = GroundSpace.new()
		ground_space.name = "GroundSpace"
		add_child(ground_space)
		ground_space.configure(walk_areas)
	_ensure_blockers()
	_collect_timed()


## 阻挡归属组件：Models 下每个可见的组件根自己带一份 BlockerSet。
## 这里只在缺的时候补一个，不覆盖场景里手工声明的。
## 退休的 unit（visible=false）不加 —— 它们已经不参与画面，也不该继续挡船。
func _ensure_blockers() -> void:
	# 阻挡是运行时派生数据，不写回场景：编辑器里自动加节点会把 TSCN 标记成已修改。
	if Engine.is_editor_hint() or models == null:
		return
	for child in models.get_children():
		if not (child is Node3D):
			continue
		var root := child as Node3D
		if not root.is_visible_in_tree():
			continue
		if _has_blocker(root):
			continue
		var blocker := BlockerSet.new()
		blocker.name = "Blockers"
		blocker.mode = "auto"
		root.add_child(blocker)


func _has_blocker(node: Node) -> bool:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.get_script() == BlockerSet:
			return true
		stack.append_array(n.get_children())
	return false


## 重新派生本区块的水面阻挡（main 在水面参数就绪后调用一次）。
func rebuild_blockers(water_y: float, height := 1.6) -> void:
	water_block_rects.clear()
	if models == null:
		return
	var stack: Array = [models]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.get_script() == BlockerSet:
			var blocker := n as Node3D
			blocker.rebuild(water_y, height)
			for r in blocker.rects_world:
				water_block_rects.append(r)
		stack.append_array(n.get_children())


func _register() -> void:
	walk_areas.clear()
	models = null
	plants = null
	for child in get_children():
		if child.name == "Models":
			models = child
		elif child.get_script() == PlantField:
			plants = child
	_collect_walk_areas(self)


func _collect_walk_areas(root: Node) -> void:
	for node in root.get_children():
		if node.has_method("surface_faces") and node.has_method("outlines"):
			if not walk_areas.has(node):
				walk_areas.append(node)
		_collect_walk_areas(node)


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


## Height-aware query for movement, interaction and saved poses. The legacy XZ
## query remains available to authoring tools, never selects a stacked floor.
func area_at(point: Vector3, tolerance: float=0.5) -> Variant:
	if is_instance_valid(ground_space): return ground_space.area_at(point,tolerance)
	var best: Node3D
	var distance := INF
	for area in walk_areas:
		var support: Vector3 = area.surface_point(point)
		if support.is_finite() and absf(support.y-point.y) <= minf(tolerance,distance):
			best = area; distance = absf(support.y-point.y)
	return best

func rebuild_ground(area: Node3D=null) -> void:
	if is_instance_valid(ground_space): ground_space.rebuild(area)


func area_containing(x: float, z: float) -> Variant:
	for area in walk_areas:
		if area.contains_world(x, z):
			return area
	return null


## 站在某点时应该踩的高度；不在任何区域内返回 NAN。
func floor_height_at(x: float, z: float) -> float:
	var area: Variant = area_containing(x, z)
	return area.floor_y() if area != null else NAN


func set_zone_level(level: int, instant := false) -> void:
	if plants != null and plants.has_method("set_zone_level"):
		plants.set_zone_level(level, instant)
	if models != null:
		var stack: Array = [models]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			if node.has_method("set_upgrade_level"): node.set_upgrade_level(level)
			stack.append_array(node.get_children())


func update_time(t: float) -> void:
	for mat in _timed:
		mat.set_shader_parameter("u_time", t)


func landing_points() -> Array:
	var result: Array = []
	for area in walk_areas:
		if not area.active:
			continue
		for child in area.get_children():
			if child.has_method("stand_position") and child.has_method("data"):
				result.append(child)
	return result

func landing_point(id: String) -> Node3D:
	for point in landing_points():
		if point.landing_id == id:
			return point
	return null
