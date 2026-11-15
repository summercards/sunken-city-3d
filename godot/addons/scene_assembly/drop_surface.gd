@tool
extends Control

var assembly: EditorPlugin
var viewport_index: int

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	set_meta("can_drop_seen", true)
	return data is Dictionary and data.get("type", "") == "sea_scene_candidate" and assembly.can_insert()

func _drop_data(at_position: Vector2, data: Variant) -> void:
	set_meta("drop_seen", true)
	if not _can_drop_data(at_position, data): return
	var viewport := EditorInterface.get_editor_viewport_3d(viewport_index)
	var camera := viewport.get_camera_3d()
	var point := at_position * Vector2(viewport.size) / size
	var origin := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
	var hit: Variant = Plane(Vector3.UP, assembly.drop_height.value).intersects_ray(origin, direction)
	if hit == null:
		assembly.report("视线与放置平面平行或背向，请调整视角。")
		return
	assembly.insert_candidate(data.entry, hit)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		hide()
