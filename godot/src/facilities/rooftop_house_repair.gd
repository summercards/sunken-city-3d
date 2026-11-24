extends Node3D

const LAYOUT := preload("res://scenes/components/facilities/rooftop_ranch/house/v010/repair_layout.json")
const CLIP := &"repair"
const FPS := 30.0
const START_FRAME := 111
const FINISH_FRAME := 296

@onready var animation_player: AnimationPlayer = $BuildingAnimation
var repair_state := &"damaged"

func _ready() -> void:
	var clip := Animation.new()
	clip.length = _time(FINISH_FRAME)
	clip.step = 1.0 / FPS
	for part: Dictionary in LAYOUT.data.placements:
		_add_part(clip, part)
	var library := AnimationLibrary.new()
	library.add_animation(CLIP, clip)
	animation_player.add_animation_library(&"", library)
	animation_player.animation_finished.connect(_finish)

func play_repair() -> bool:
	if repair_state != &"damaged":
		return false
	repair_state = &"repairing"
	animation_player.play(CLIP)
	animation_player.seek(0.0, true)
	return true

func _finish(clip: StringName) -> void:
	if clip == CLIP:
		repair_state = &"restored"

func _time(frame: int) -> float:
	# Collapse the idle gap between structural repairs and furnishing.
	var effective := frame - clampi(frame - 147, 0, 65)
	return maxf((effective - START_FRAME) / FPS, 0.0)

func _add_part(clip: Animation, part: Dictionary) -> void:
	var node := get_node(NodePath(part.node)) as Node3D
	var path := str(get_path_to(node))
	var states: Array = part.states
	var solid := node.get_node_or_null("Solid") as StaticBody3D
	if solid != null:
		solid.collision_layer = 8192 if states[0][4] else 0
	if states.size() == 1:
		return
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
			_transform_keys(clip, movement, rotation, sizing, _time(frame - 1), previous)
		_transform_keys(clip, movement, rotation, sizing, _time(frame), state)
		if previous.is_empty() or state[4] != previous[4]:
			clip.track_insert_key(visibility, _time(frame), state[4])
		previous = state
	if solid != null and part.key in ["house_corner_patch", "entry_assembly"]:
		var collision := _discrete(clip, NodePath(path + "/Solid:collision_layer"))
		var collision_ready := 145 if part.key == "house_corner_patch" else 241
		clip.track_insert_key(collision, 0.0, 0)
		clip.track_insert_key(collision, _time(collision_ready), 8192)
		solid.collision_layer = 0

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
