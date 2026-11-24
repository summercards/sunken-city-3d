extends Node3D
## The Blender drop is a presentation clip. Gameplay can invoke it explicitly.

const CLIP := &"construction"
const FPS := 30.0
const END_FRAME := 225

@onready var animation_player: AnimationPlayer = $BuildingAnimation

func _ready() -> void:
	var animation := Animation.new()
	animation.length = (END_FRAME - 1) / FPS
	animation.step = 1.0 / FPS
	for module in get_children():
		if not "construction_parts" in module:
			continue
		for part in module.construction_parts:
			_add_tracks(animation, part)
		# The plant anchors retain their repair/season visibility.
		for plant_visual in module.find_children("*", "MultiMeshInstance3D", true, false):
			if plant_visual.get_meta("category", "") == "flora":
				_add_visibility(animation, NodePath(str(get_path_to(plant_visual)) + ":visible"), animation.length)
	_add_visibility(animation, NodePath("VegetationTurf:visible"), animation.length)
	_add_visibility(animation, NodePath("家园夜灯:visible"), animation.length)
	var library := AnimationLibrary.new()
	library.add_animation(CLIP, animation)
	animation_player.add_animation_library(&"", library)

func _add_tracks(animation: Animation, part: Dictionary) -> void:
	var path := String(get_path_to(part.node))
	var start: int = part.start
	var height: Array = part.rise
	var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(position_track, NodePath(path))
	for offset in height.size():
		animation.position_track_insert_key(position_track, (start + offset - 1) / FPS,
			Vector3.UP * float(height[offset]))
	_add_visibility(animation, NodePath(path + ":visible"), (start - 1) / FPS)

func _add_visibility(animation: Animation, path: NodePath, reveal_time: float) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, path)
	animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
	animation.track_insert_key(track, 0.0, false)
	animation.track_insert_key(track, reveal_time, true)
	if reveal_time < animation.length:
		animation.track_insert_key(track, animation.length, true)

func play_construction() -> void:
	animation_player.stop(true)
	animation_player.play(CLIP)
	animation_player.seek(0.0, true)

func finish_construction() -> void:
	animation_player.play(CLIP)
	animation_player.seek(animation_player.get_animation(CLIP).length, true)
	animation_player.stop(true)
