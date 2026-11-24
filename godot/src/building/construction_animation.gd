extends Node3D
## A temporary visual overlay. The finished instance keeps its pose and physics.

const DROP_TIME := 0.31
const SETTLE_TIME := 0.27

var _originals: Array[Node3D] = []

func play(component: Node3D, kind: String) -> void:
	var visual := component.get_node("Model")
	var meshes := visual.find_children("*", "MeshInstance3D", true, false)
	var rotor := component.get_node_or_null("Rotor")
	if rotor != null:
		meshes.append_array(rotor.find_children("*", "MeshInstance3D", true, false))

	var elements: Array[Dictionary] = []
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null or not mesh.visible:
			continue
		var pose := global_transform.affine_inverse() * mesh.global_transform
		var bounds := pose * mesh.get_aabb()
		var pivot := bounds.get_center()
		pivot.y = bounds.position.y
		elements.append({"mesh":mesh, "pose":pose, "pivot":pivot, "size":bounds.size,
			"stage":_stage(String(mesh.name), kind)})
	elements.sort_custom(_earlier)
	if elements.is_empty():
		queue_free()
		return

	var clip := Animation.new()
	var spacing := clampf(1.65 / elements.size(), 0.025, 0.37)
	var offset := 0.0
	var last_stage: int = elements[0].stage
	for i in elements.size():
		var part := elements[i]
		if part.stage != last_stage:
			offset += maxf(0.0, DROP_TIME - spacing)
			last_stage = part.stage
		_add_element(clip, part, offset, i)
		offset += spacing
	clip.length = offset - spacing + DROP_TIME + SETTLE_TIME

	for accessory_name in ["WarmLamp", "ContactShadow", "Crop"]:
		var accessory := component.get_node_or_null(accessory_name) as Node3D
		if accessory != null and accessory.visible:
			accessory.hide()
			_originals.append(accessory)

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	add_child(player)
	var lib := AnimationLibrary.new()
	lib.add_animation(&"construction", clip)
	player.add_animation_library(&"", lib)
	player.animation_finished.connect(_finish, CONNECT_ONE_SHOT)
	player.play(&"construction")
	player.advance(0.0)

func _stage(part: String, kind: String) -> int:
	if kind == "workshop_dock":
		if part.begins_with("Joist"): return 0
		if part.begins_with("Plank"): return 1
		if "Bollard" in part or "Cap" in part: return 2
		return 3
	if kind.begins_with("stairs"):
		if part.begins_with("stringer") or part.begins_with("StairSupport"):
			return 0
		return 1
	if kind == "lamp_post":
		if part == "foot": return 0
		if part.begins_with("post"): return 1
		return 2
	if kind == "windmill":
		if part == "mast": return 0
		if part == "hub": return 1
		return 2
	return 0

func _earlier(a: Dictionary, b: Dictionary) -> bool:
	if a.stage != b.stage:
		return a.stage < b.stage
	var p: Vector3 = a.pivot
	var q: Vector3 = b.pivot
	var low := roundi(p.y * 100.0)
	var high := roundi(q.y * 100.0)
	if low != high:
		return low < high
	var x := roundi(p.x * 100.0)
	var other_x := roundi(q.x * 100.0)
	if x != other_x:
		return x < other_x
	return p.z < q.z

func _add_element(clip: Animation, part: Dictionary, start: float, index: int) -> void:
	var moving := Node3D.new()
	moving.name = "Part%03d" % index
	moving.position = part.pivot
	moving.hide()
	add_child(moving)
	var original: MeshInstance3D = part.mesh
	# Copy just the renderable. Interaction, gameplay and collision stay on the owner.
	var model := MeshInstance3D.new()
	model.name = original.name
	model.mesh = original.mesh
	model.material_override = original.material_override
	model.cast_shadow = original.cast_shadow
	model.set_meta("construction_overlay", true)
	for i in original.mesh.get_surface_count():
		model.set_surface_override_material(i, original.get_surface_override_material(i))
	moving.add_child(model)
	var model_pose: Transform3D = part.pose
	model_pose.origin -= moving.position
	model.transform = model_pose
	original.hide()
	original.set_meta("construction_hidden", true)
	_originals.append(original)

	var path := NodePath(str(moving.name))
	var visible := clip.add_track(Animation.TYPE_VALUE)
	clip.track_set_path(visible, NodePath(str(path) + ":visible"))
	clip.value_track_set_update_mode(visible, Animation.UPDATE_DISCRETE)
	if start > 0.0:
		clip.track_insert_key(visible, 0.0, false)
	clip.track_insert_key(visible, start, true)

	var length: Vector3 = part.size
	var height := clampf(0.9 + length.length() * 0.22, 0.9, 2.3)
	add_drop_tracks(clip, path, start, part.pivot, Vector3.ONE, height)

static func add_drop_tracks(clip: Animation, path: NodePath, start: float,
		target: Vector3, final_scale: Vector3, height: float) -> void:
	var position := clip.add_track(Animation.TYPE_POSITION_3D)
	clip.track_set_path(position, path)
	clip.position_track_insert_key(position, start, target + Vector3.UP * height)
	clip.position_track_insert_key(position, start + DROP_TIME * 0.55, target + Vector3.UP * height * 0.72)
	clip.position_track_insert_key(position, start + DROP_TIME, target)

	var scale_track := clip.add_track(Animation.TYPE_SCALE_3D)
	clip.track_set_path(scale_track, path)
	var impact := start + DROP_TIME
	clip.scale_track_insert_key(scale_track, start, final_scale * 0.86)
	clip.scale_track_insert_key(scale_track, impact, final_scale * 0.93)
	clip.scale_track_insert_key(scale_track, impact + 0.08, final_scale * 1.12)
	clip.scale_track_insert_key(scale_track, impact + 0.18, final_scale * 0.985)
	clip.scale_track_insert_key(scale_track, impact + SETTLE_TIME, final_scale)

func _finish(_clip: StringName) -> void:
	for original in _originals:
		if is_instance_valid(original):
			original.show()
			if original.has_meta("construction_hidden"):
				original.remove_meta("construction_hidden")
	hide()
	queue_free()
