@tool
extends Node3D
## 区块植物场。
##
## 读取本区块的摆放表（assets/data/plants_<zone>.json），按 archetype 实例化：
##   通用植物   scenes/plants/common/<id>.tscn      任何区块都能复用
##   专用植物   scenes/plants/zones/<zone>/<id>.tscn 与区块绑定（自带摆动/特效参数）
##
## 对外两个入口：
##   set_zone_level(level)      按建造等级驱动生长
##   spawn(arch, position)      临时种一株（通用植物互用就靠这个）

const PlantEffect = preload("res://src/ambient/plant_effect.gd")

@export var zone_id := ""
@export var placement_path := ""
@export var max_level := 3

var plants: Array = []
var effect_node: Node3D = null

var _level := 1
var _scene_cache: Dictionary = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		_build_for_editor()
		return
	spawn_from_placements()


## 编辑器里按「建成态」铺一遍：满级、不走生长动画，方便直接看最终画面。
## 这些节点 owner 为空，保存场景时不会写进文件，运行时仍由 spawn_from_placements() 生成。
func _build_for_editor() -> void:
	for c in get_children():
		c.queue_free()
	plants.clear()
	effect_node = null
	var f := FileAccess.open(placement_path, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data == null:
		return
	for row in data.get("plants", []):
		var node := spawn(str(row.a), str(row.scope), _vec(row.p))
		if node == null:
			continue
		if node.has_method("set_growth"):
			node.set_growth(1.0)
		# 编辑器里不加特效发射器：粒子在静态预览里只会糊成一片。


func spawn_from_placements() -> void:
	var f := FileAccess.open(placement_path, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data == null:
		return
	var effects: Array = []
	for row in data.get("plants", []):
		var node := spawn(row.a, row.scope, _vec(row.p))
		if node == null:
			continue
		var start := float(row.get("g", 0.2))
		node.set_growth(0.0)
		# 错峰生长：原版每个 layer 有自己的 start，这里用摆放表里的 g 延迟
		var target := _growth_for_level(_level)
		var delay := start
		# 用 bind 而不是闭包捕获：区块卸载/场景重载时节点会先被释放，
		# 闭包再引用它就报 "Lambda capture was freed"。
		create_tween().tween_interval(delay).finished.connect(
			_grow_bound.bind(node, target))
		if not effects.has(node.effect) and node.effect != "":
			effects.append(node.effect)
	for e in effects:
		_spawn_effect(e)


func _grow_bound(node: Variant, target: float) -> void:
	if is_instance_valid(node) and not (node as Node).is_queued_for_deletion():
		node.grow_to(target)


func spawn(arch: String, scope: String, position: Vector3) -> Node3D:
	var path := "res://scenes/plants/%s/%s.tscn" % [scope, arch]
	if not _scene_cache.has(path):
		var packed: Variant = load(path)
		if packed == null:
			push_warning("缺少植物场景: " + path)
			return null
		_scene_cache[path] = packed
	var node: Node3D = (_scene_cache[path] as PackedScene).instantiate()
	node.position = position
	add_child(node)
	plants.append(node)
	return node


func set_zone_level(level: int, instant := false) -> void:
	_level = maxi(0, level)
	var target := _growth_for_level(_level)
	for p in plants:
		if instant:
			p.set_growth(target)
		else:
			p.grow_to(target)


func _growth_for_level(level: int) -> float:
	# 0 级 = 还没修，只有一点点苗；满级 = 完全长开
	return clampf(0.22 + 0.78 * float(level) / float(max_level), 0.0, 1.0)


func _spawn_effect(effect_name: String) -> void:
	if effect_node != null:
		return
	effect_node = PlantEffect.new()
	effect_node.name = "PlantEffect"
	effect_node.effect = effect_name
	effect_node.position = _zone_center()
	add_child(effect_node)


func _zone_center() -> Vector3:
	var parent := get_parent()
	if parent != null and parent.name.begins_with("Zone"):
		for child in parent.get_children():
			if child.name == "WalkAreas" and child.get_child_count() > 0:
				var walk = child.get_child(0)
				if walk.has_method("center_world"):
					var c: Vector3 = walk.center_world()
					return to_local(c)
	return Vector3.ZERO


func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
