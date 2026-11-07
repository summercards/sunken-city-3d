extends Node3D
## Presentation-only camera-side oval. Shares the roof's room entry decision,
## preserves per-instance material references, and never changes visibility/space.
const MASK = preload("res://shaders/shop_sightline.gdshader")
const Dimensions = preload("res://src/avatar/avatar_dimensions.gd")
const WALL_IDS := ["GLASS-BAY", "BACK-PANEL", "COLUMN", "BACK-DOOR", "CURVED-GLASS", "ENTRY-FRAME"]
const FURNITURE_IDS := ["ROOF-PIPE", "ELECTRICAL-BOX", "LIFE-RING", "POSTCARD-RACK", "MAILBOX", "ICE-BOX", "BIN", "SHELF", "BOTTLE", "GIFT", "CARD", "POT"]
@export var horizontal_radius := 4.3
@export var vertical_radius := 3.8
@export var feather := 0.22
@export var ghost_opacity := 0.08
@export var transition_seconds := 0.35
var _visual: Node3D
var _roof: Node3D
var _subject: Node3D
var _camera: Camera3D
var _candidates: Array = []
var _materials: Array[ShaderMaterial] = []
var _amount := 0.0
var _focus_local := Vector3.ZERO
var _center := Vector2.ZERO
var _radius := Vector2.ZERO
var _depth := 0.0
var _near_direction := Vector2.ZERO
var _active_meshes := 0

func _ready() -> void:
	process_priority = 50
	_visual = get_node_or_null("../Visual") as Node3D
	_roof = get_node_or_null("../RoofReveal") as Node3D
	if _visual == null or _roof == null:
		return
	var roots: Array[Node] = []
	for branch in ["Structure", "Furnishings"]:
		for node in _visual.get_node(branch).get_children():
			if node.get_meta("roof_reveal", false):
				continue
			var key: String = str(node.get_meta("asset_id", "")).trim_prefix("SEA-SCENE-GKS-")
			if key in (WALL_IDS if branch == "Structure" else FURNITURE_IDS):
				roots.append(node)
	for branch in ["Interior/Furnishings", "Interior/Plants"]:
		var group := _visual.get_node_or_null(branch)
		if group != null:
			roots.append_array(group.get_children())
	var cache := {}
	var glass_shader := Shader.new()
	glass_shader.code = MASK.code.replace("cull_back", "cull_disabled")
	for node in roots:
		for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null:
				continue
			var bindings := []
			for surface in mesh.mesh.get_surface_count():
				var source := mesh.get_active_material(surface) as StandardMaterial3D
				if source == null:
					continue
				var id := source.get_instance_id()
				if not cache.has(id):
					var material := ShaderMaterial.new()
					material.shader = glass_shader if source.cull_mode == BaseMaterial3D.CULL_DISABLED else MASK
					material.set_shader_parameter("palette", source.albedo_texture)
					material.set_shader_parameter("tint", source.albedo_color)
					material.set_shader_parameter("surface_roughness", source.roughness)
					material.set_shader_parameter("surface_metallic", source.metallic)
					material.set_shader_parameter("glow_tint", source.emission if source.emission_enabled else Color.BLACK)
					material.set_shader_parameter("glow_energy", source.emission_energy_multiplier if source.emission_enabled else 0.0)
					cache[id] = material
					_materials.append(material)
				bindings.append({"surface":surface, "original":mesh.get_surface_override_material(surface), "mask":cache[id]})
			_candidates.append({"mesh":mesh, "bindings":bindings, "active":false})

func configure_subject(actor: Node3D, camera: Camera3D = null) -> void:
	_subject = actor
	_camera = camera

func _process(delta: float) -> void:
	advance(delta)

func _set_candidate(candidate: Dictionary, active: bool) -> void:
	if candidate.active == active:
		return
	var mesh: MeshInstance3D = candidate.mesh
	if is_instance_valid(mesh):
		for binding in candidate.bindings:
			mesh.set_surface_override_material(binding.surface, binding.mask if active else binding.original)
	candidate.active = active

func advance(delta: float) -> void:
	if not is_instance_valid(_visual) or not is_finite(delta) or delta < 0:
		return
	var camera := _camera if is_instance_valid(_camera) else get_viewport().get_camera_3d()
	var wanted := is_instance_valid(_subject) and is_instance_valid(camera) and is_instance_valid(_roof) and bool(_roof.snapshot().inside)
	if wanted:
		var focus := _subject.global_position + Vector3.UP * Dimensions.CAMERA_FOCUS
		wanted = not camera.is_position_behind(focus)
		if wanted:
			_focus_local = _visual.to_local(focus)
	_amount = move_toward(_amount, 1.0 if wanted else 0.0, delta / maxf(transition_seconds, 0.01))
	_active_meshes = 0
	if _amount <= 0.000001 or not is_instance_valid(camera):
		for candidate in _candidates:
			_set_candidate(candidate, false)
		return
	var focus := _visual.to_global(_focus_local)
	var size := camera.get_viewport().get_visible_rect().size
	_center = camera.unproject_position(focus) / size
	var right := camera.global_basis.x.normalized() * horizontal_radius
	var up := camera.global_basis.y.normalized() * vertical_radius
	_radius = Vector2(absf((camera.unproject_position(focus + right) / size).x - _center.x), absf((camera.unproject_position(focus + up) / size).y - _center.y))
	var camera_inverse := camera.global_transform.affine_inverse()
	_depth = -(camera_inverse * focus).z
	var delta_xz := Vector2(camera.global_position.x - focus.x, camera.global_position.z - focus.z)
	_near_direction = delta_xz.normalized() if delta_xz.length() > 0.15 else Vector2.ZERO
	for candidate in _candidates:
		var mesh: MeshInstance3D = candidate.mesh
		if not is_instance_valid(mesh):
			continue
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		var nearest_xz := Vector2(bounds.end.x if _near_direction.x >= 0 else bounds.position.x, bounds.end.z if _near_direction.y >= 0 else bounds.position.z)
		var near_side := (nearest_xz - Vector2(focus.x, focus.z)).dot(_near_direction) > -0.35
		var view_bounds: AABB = (camera_inverse * mesh.global_transform) * mesh.get_aabb()
		var active: bool = mesh.is_visible_in_tree() and _near_direction != Vector2.ZERO and near_side and -view_bounds.end.z < _depth + 0.18
		_set_candidate(candidate, active)
		if active:
			_active_meshes += 1
	for material in _materials:
		material.set_shader_parameter("window_center", _center)
		material.set_shader_parameter("window_radius", _radius)
		material.set_shader_parameter("reveal_amount", _amount)
		material.set_shader_parameter("feather", feather)
		material.set_shader_parameter("ghost_opacity", ghost_opacity)
		material.set_shader_parameter("focus_xz", Vector2(focus.x, focus.z))
		material.set_shader_parameter("near_direction", _near_direction)
		material.set_shader_parameter("focus_depth", _depth)

func snapshot() -> Dictionary:
	return {"amount":_amount, "candidates":_candidates.size(), "active_meshes":_active_meshes, "materials":_materials.size(), "center_uv":_center, "radius_uv":_radius, "focus_depth":_depth, "near_direction":_near_direction}

func _exit_tree() -> void:
	for candidate in _candidates:
		_set_candidate(candidate, false)
