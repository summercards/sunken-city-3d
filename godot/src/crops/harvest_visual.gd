extends RefCounted
## Detached visual copies only. Never move, hide or modify the planted crop.
const Catalog = preload("res://src/crops/crop_catalog.gd")
const Stage = preload("res://src/crops/crop_stage.gd")

static func supports(crop_id: String) -> bool:
	return crop_id in ["lettuce","tomato","pumpkin"]

static func create(crop_id: String) -> Node3D:
	var catalog := Catalog.new()
	if not supports(crop_id) or not catalog.reload() or not catalog.has(crop_id): return null
	var path := catalog.model_scene(crop_id)
	if not ResourceLoader.exists(path): return null
	var packed = load(path)
	if not packed is PackedScene: return null
	var source: Node3D = packed.instantiate()
	var stage: Node3D = source.get_node(Stage.node_name(Stage.HARVEST))
	if stage == null:
		source.free()
		return null
	var meshes: Array[MeshInstance3D] = []
	_collect(stage, meshes)
	var selected: Array[MeshInstance3D] = []
	if crop_id == "lettuce":
		var hearts: Array[MeshInstance3D] = []
		for mesh in meshes:
			if str(mesh.name).begins_with("菜心"): hearts.append(mesh)
		if not hearts.is_empty():
			for mesh in meshes:
				var center := _bounds(mesh, source).get_center()
				var nearest: MeshInstance3D = hearts[0]
				var distance := INF
				for heart in hearts:
					var at := _bounds(heart, source).get_center()
					var d := Vector2(center.x-at.x, center.z-at.z).length_squared()
					if d < distance: nearest = heart; distance = d
				if nearest == hearts[0]: selected.append(mesh)
	else:
		# One fruit, with its own stem on pumpkin; no entire bush or soil.
		var names: Array = ["果实"] if crop_id == "tomato" else ["南瓜", "瓜蒂"]
		for mesh in meshes:
			if str(mesh.name) in names: selected.append(mesh)
	if selected.is_empty():
		source.free()
		return null
	var result := Node3D.new()
	result.name = "HarvestProduce"
	result.set_meta("crop_id", crop_id)
	var bounds := _bounds(selected[0], source)
	for mesh in selected: bounds = bounds.merge(_bounds(mesh, source))
	var diameter := 0.32 if crop_id == "tomato" else 0.40
	var factor := diameter / maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	for mesh in selected:
		var copy := MeshInstance3D.new()
		copy.name = mesh.name
		copy.mesh = mesh.mesh
		copy.material_override = mesh.material_override
		var xf := _relative(mesh, source)
		xf.origin -= bounds.get_center()
		copy.transform = Transform3D(xf.basis.scaled(Vector3.ONE*factor), xf.origin*factor)
		result.add_child(copy)
	source.free()
	return result

static func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D: out.append(node)
	for child in node.get_children(): _collect(child, out)

static func _relative(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := node.transform
	var parent := node.get_parent()
	while parent != ancestor:
		if parent is Node3D: xf = parent.transform * xf
		parent = parent.get_parent()
	return xf

static func _bounds(mesh: MeshInstance3D, ancestor: Node3D) -> AABB:
	return _relative(mesh, ancestor) * mesh.get_aabb()
