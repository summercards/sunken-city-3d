@tool
extends "res://src/world/zone_scene.gd"

const LAYOUT := preload("res://scenes/components/facilities/rooftop_ranch/v012/repair_layout.json")
const ConstructionAnimation := preload("res://src/building/construction_animation.gd")
const CONSTRUCTION := &"construction"
const ACTOR_SOLID := 8192
const FPS := 30.0

@onready var _player: AnimationPlayer = $BuildingAnimation
@onready var _ground: Node3D = $WalkAreas/Walk_rooftop_ranch_access
var _done := {}
var _running := &""
var _parts: Dictionary = {}
var _floors: Array[CollisionShape3D] = []

func _ready() -> void:
	if Engine.is_editor_hint():
		super._ready()
		return
	for floor in $Models.find_children("Floor", "CollisionShape3D", true, false):
		if floor.get_meta("walk_surface", false):
			_floors.append(floor)
	var library := AnimationLibrary.new()
	for area: String in LAYOUT.data.clips:
		var window: Array = LAYOUT.data.clips[area].frames
		var clip := Animation.new()
		var start := int(window[0]) - 1
		var end := int(window[1])
		clip.length = (end - start) / FPS
		clip.step = 1.0 / FPS
		var growth := _ruin_growth(area)
		if growth != null:
			var clear := _discrete(clip, NodePath(str(get_path_to(growth)) + ":visible"))
			clip.track_insert_key(clear, 0.0, true)
			clip.track_insert_key(clear, minf(7.0 / FPS, clip.length), false)
		var parts: Array[Node3D] = []
		for part: Dictionary in LAYOUT.data.placements:
			if part.area != area:
				continue
			var node := get_node(NodePath("Models/" + part.node)) as Node3D
			parts.append(node)
			if area == CONSTRUCTION:
				_add_construction(clip, node, part.states, start)
				continue
			_add_tracks(clip, node, part.states, start)
			# Solids on installed pieces join the roof when the clip completes.
			# Clearing debris leaves its own solid in place until it disappears.
			if not part.states.back()[4]:
				var solid := node.get_node_or_null("Solid") as StaticBody3D
				if solid != null:
					var track := _discrete(clip, NodePath(str(get_path_to(solid)) + ":collision_layer"))
					clip.track_insert_key(track, 0.0, solid.collision_layer)
					clip.track_insert_key(track, (int(part.states.back()[0]) - start) / FPS, 0)
		_parts[area] = parts
		library.add_animation(StringName(area), clip)
	_player.add_animation_library(&"", library)
	_player.animation_finished.connect(_finish_repair)
	_update_walk_surface()
	super._ready()

func can_repair(area: StringName) -> bool:
	if _running != &"" or _done.has(area) or not _player.has_animation(area):
		return false
	return area != CONSTRUCTION or _done.size() == LAYOUT.data.clips.size() - 1

func play_repair(area: StringName) -> bool:
	if not can_repair(area):
		return false
	_running = area
	_player.play(area)
	_player.advance(0.0)
	return true

func repair_progress(area: StringName) -> StringName:
	if _done.has(area):
		return &"complete"
	return &"playing" if area == _running else &"ready"

func restored_footing(saved_point: Vector3, actor: CharacterBody3D) -> Vector3:
	var transfer := preload("res://src/navigation/berth_transfer.gd").new()
	var footing := transfer.safe_feet(actor, saved_point, 0.45, 0.45)
	if footing.is_finite():
		return footing
	var berth := landing_point("main")
	var shifted := saved_point + Vector3.DOWN * float(get_meta("lowered_m", 0.0))
	if _ground.contains_position(shifted, 0.18):
		footing = transfer.safe_feet(actor, shifted, 0.13, 0.13)
		if footing.is_finite() and not ground_space.native_route(footing, berth.global_position).is_empty():
			return footing
	return transfer.safe_feet(actor, berth.global_position, 0.25, 0.25)

func _ruin_growth(area: StringName) -> Node3D:
	return get_node_or_null(NodePath("Models/RuinVegetation/Regions/" + area)) as Node3D

func _add_construction(clip: Animation, node: Node3D, states: Array, start: int) -> void:
	var first: Array = states.front()
	var final: Array = states.back()
	var path := get_path_to(node)
	var reveal := _discrete(clip, NodePath(str(path) + ":visible"))
	clip.track_insert_key(reveal, 0.0, false)
	for state: Array in states:
		if state[4]:
			var time := (int(state[0]) - start) / FPS
			var target := Vector3(final[1][0], final[1][1], final[1][2])
			var scale := Vector3(final[3][0], final[3][1], final[3][2])
			var height := float(first[1][1]) - target.y
			ConstructionAnimation.add_drop_tracks(clip, path, time, target, scale, height)
			clip.track_insert_key(reveal, time, true)
			break

func _finish_repair(area: StringName) -> void:
	if area != _running:
		return
	var growth := _ruin_growth(area)
	if growth != null:
		growth.hide()
	for node: Node3D in _parts[area]:
		var solid := node.get_node_or_null("Solid") as StaticBody3D
		if solid != null:
			solid.collision_layer = ACTOR_SOLID if node.visible else 0
	_done[area] = true
	_update_walk_surface()
	rebuild_ground(_ground)
	_running = &""

func _update_walk_surface() -> void:
	var faces := PackedVector3Array()
	for floor in _floors:
		var body := floor.get_parent() as StaticBody3D
		if body.collision_layer != ACTOR_SOLID:
			continue
		var placement := body.get_parent() as Node3D
		# Keep navigation outside the standing house. Its open doorway and
		# walls are still available to the player through physical movement.
		var p := placement.position
		if str(placement.get_meta("component_key", "")).begins_with("deck_tile_") \
				and p.x < -7.0 and p.z < 0.1:
			continue
		var pose := _ground.global_transform.affine_inverse() * floor.global_transform
		for point in (floor.shape as ConcavePolygonShape3D).get_faces():
			faces.append(pose * point)
	_ground.surface_triangles = faces

func _add_tracks(clip: Animation, node: Node3D, states: Array, start: int) -> void:
	var path := str(get_path_to(node))
	var movement := clip.add_track(Animation.TYPE_POSITION_3D)
	var rotation := clip.add_track(Animation.TYPE_ROTATION_3D)
	var sizing := clip.add_track(Animation.TYPE_SCALE_3D)
	clip.track_set_path(movement, NodePath(path))
	clip.track_set_path(rotation, NodePath(path))
	clip.track_set_path(sizing, NodePath(path))
	var visibility := _discrete(clip, NodePath(path + ":visible"))
	var previous: Array = []
	for state: Array in states:
		var frame := int(state[0])
		if not previous.is_empty() and int(previous[0]) < frame - 1:
			_transform_keys(clip, movement, rotation, sizing, maxf((frame - 1 - start) / FPS, 0.0), previous)
		var time := maxf((frame - start) / FPS, 0.0)
		_transform_keys(clip, movement, rotation, sizing, time, state)
		if previous.is_empty() or state[4] != previous[4]:
			clip.track_insert_key(visibility, time, state[4])
		previous = state

func _discrete(clip: Animation, path: NodePath) -> int:
	var track := clip.add_track(Animation.TYPE_VALUE)
	clip.track_set_path(track, path)
	clip.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
	return track

func _transform_keys(clip: Animation, movement: int, rotation: int, sizing: int, time: float, state: Array) -> void:
	var p: Array = state[1]
	var q: Array = state[2]
	var s: Array = state[3]
	clip.position_track_insert_key(movement, time, Vector3(p[0], p[1], p[2]))
	clip.rotation_track_insert_key(rotation, time, Quaternion(q[0], q[1], q[2], q[3]).normalized())
	clip.scale_track_insert_key(sizing, time, Vector3(s[0], s[1], s[2]))
