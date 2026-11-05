@tool
extends Node3D
## Baked local placements, separated by asset and spatial cells. No runtime scatter/physics.
const Library = preload("res://src/ambient/vegetation/library.gd")
@export_file("*.json") var layout_path := ""
@export_enum("Low", "Standard", "High") var quality := 1
var batches: Array[MultiMeshInstance3D] = []
var placement_count := 0
var _tick := 0.0
var _bands := {}
var _grass_batches: Array[MultiMeshInstance3D] = []
var _last_camera_position := Vector3.INF
var _last_view := Vector3.ZERO
func _ready() -> void:
	rebuild()
func rebuild() -> void:
	for node in batches: node.free()
	batches.clear(); _grass_batches.clear(); _bands.clear(); placement_count = 0
	_last_camera_position = Vector3.INF
	if layout_path.is_empty(): return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
	var groups := {}
	for item in data.instances:
		var p: Array = item.position
		var cell_size: float = data.get("chunk_metres", 8.0)
		var cell := "%s/%s/%s/%s" % [item.asset, floori(p[0]/cell_size), floori(p[1]/2), floori(p[2]/cell_size)]
		if not groups.has(cell): groups[cell] = []
		groups[cell].append(item)
	for cell in groups:
		var rows: Array = groups[cell]
		var key: String = rows[0].asset
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = Library.mesh(key)
		mm.instance_count = rows.size()
		var origin := Vector3(rows[0].position[0], rows[0].position[1], rows[0].position[2])
		var bounds := AABB()
		var transforms: Array[Transform3D] = []
		for i in rows.size():
			var row: Dictionary = rows[i]
			var p := Vector3(row.position[0], row.position[1], row.position[2]) - origin
			var s: Array = row.scale
			var basis := Basis(Vector3.UP, row.yaw).scaled(Vector3(s[0], s[1], s[2]))
			var xf := Transform3D(basis, p)
			mm.set_instance_transform(i, xf)
			transforms.append(xf)
			mm.set_instance_custom_data(i, Color(row.phase, row.get("variation", 0.5), 1.0, 1.0))
			var box: AABB = xf * mm.mesh.get_aabb()
			bounds = box if i == 0 else bounds.merge(box)
		mm.custom_aabb = bounds.grow(0.6)
		var batch := MultiMeshInstance3D.new()
		batch.name = cell.replace("/", "_")
		batch.position = origin
		batch.multimesh = mm
		batch.material_override = Library.material(key)
		batch.set_meta("asset_id", Library.catalog()[key].asset_id)
		batch.set_meta("asset_key", key)
		batch.set_meta("visual_only", true)
		batch.set_meta("authored_transforms", transforms)
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(batch); batches.append(batch)
		if key.begins_with("grass"): _grass_batches.append(batch)
		placement_count += rows.size()
	set_process(not Engine.is_editor_hint())
func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.35 or not is_visible_in_tree(): return
	_tick = 0.0
	update_quality(get_viewport().get_camera_3d())
func update_quality(camera: Camera3D, force := false) -> void:
	if camera == null: return
	var pixels := float(get_viewport().get_visible_rect().size.y)
	var view := Vector3(pixels, camera.fov, quality)
	if not force and camera.global_position.is_equal_approx(_last_camera_position) and view == _last_view: return
	_last_camera_position = camera.global_position; _last_view = view
	var projection := 0.48 * pixels / (2.0 * tan(deg_to_rad(camera.fov)*0.5))
	for batch in _grass_batches:
		var distance := maxf(1.0, camera.global_position.distance_to(batch.global_position))
		var projected := projection / distance
		var band: int = _bands.get(batch.name, 2)
		# Hysteresis avoids flickering density while zooming. Ground cover stays present.
		if projected > 5.5: band = 2
		elif projected < 4.0 and projected > 1.5: band = 1
		elif projected < 1.1: band = 0
		_bands[batch.name] = band
		# Standard keeps the full authored soft carpet; Low thins density only.
		# Preserve the broad grass silhouette even at maximum camera distance.
		var fraction := ([0.45, 0.80, 1.0][band] as float) * ([0.65, 1.0, 1.0][quality] as float)
		var count := int(batch.multimesh.instance_count * fraction)
		if batch.multimesh.visible_instance_count != count: batch.multimesh.visible_instance_count = count
