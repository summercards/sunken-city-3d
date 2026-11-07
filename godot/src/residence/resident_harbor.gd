@tool
extends "res://src/world/zone_scene.gd"
## SEA-RESIDENCE：只投影住所空间，不持有居民业务或另一套移动系统。
const DIRECTORY := "res://assets/data/npc/residences.json"
var _space_pose := Transform3D.IDENTITY
var _sync_pending := false

func _ready() -> void:
	_prepare_surface()
	super._ready()
	_space_pose = global_transform
	set_notify_transform(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_node_ready() and not Engine.is_editor_hint():
		if not _sync_pending:
			_sync_pending = true
			call_deferred("refresh_space")

## 编辑器挪动子房屋后也可显式重建；不修改任何作者布局。
func refresh_space() -> void:
	_sync_pending = false
	_prepare_surface()
	if is_instance_valid(ground_space):
		ground_space.rebuild()
	_space_pose = global_transform

func _prepare_surface() -> void:
	var area: Node3D = get_node("WalkAreas/Community")
	var free: Array[Rect2] = [Rect2(-15, -15, 30, 33), Rect2(15, -1.5, 4, 3)]
	for house: Node3D in get_node("Models/Homes").get_children():
		for obstacle: Node3D in house.find_children("*", "Node3D", true, false):
			if not obstacle.has_meta("walk_obstacle"): continue
			var local_rect: Rect2 = obstacle.get_meta("walk_obstacle")
			var cut := Rect2()
			var first := true
			for corner: Vector2 in [local_rect.position, Vector2(local_rect.end.x, local_rect.position.y), local_rect.end, Vector2(local_rect.position.x, local_rect.end.y)]:
				var p: Vector3 = area.to_local(obstacle.to_global(Vector3(corner.x, 0, corner.y)))
				if first: cut = Rect2(Vector2(p.x, p.z), Vector2.ZERO); first = false
				else: cut = cut.expand(Vector2(p.x, p.z))
			var start := cut.position.snapped(Vector2.ONE*0.0001)
			var finish := cut.end.snapped(Vector2.ONE*0.0001)
			free = _subtract(free, Rect2(start, finish-start))
	# 保留稀疏矩形：GroundSpace 统一焊接/烘焙并派生真实地板和边界。
	# 不将整片社区栅格化，否则其通用边界求交会被无意义的内部边拖慢。
	var faces := PackedVector3Array()
	for rect in free:
		var a := Vector3(rect.position.x, 0, rect.position.y)
		var b := Vector3(rect.position.x, 0, rect.end.y)
		var c := Vector3(rect.end.x, 0, rect.end.y)
		var d := Vector3(rect.end.x, 0, rect.position.y)
		faces.append_array(PackedVector3Array([a,b,c,a,c,d]))
	area.rects = free
	area.surface_triangles = faces
	area.surface_y = area.global_position.y
	area.span_min = area.surface_y - 0.3
	area.span_max = area.surface_y + 0.3

func _subtract(source: Array[Rect2], cut: Rect2) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for rect in source:
		if not rect.intersects(cut): result.append(rect); continue
		var hit := rect.intersection(cut)
		for part: Rect2 in [Rect2(rect.position, Vector2(hit.position.x-rect.position.x,rect.size.y)), Rect2(Vector2(hit.end.x,rect.position.y),Vector2(rect.end.x-hit.end.x,rect.size.y)), Rect2(Vector2(hit.position.x,rect.position.y),Vector2(hit.size.x,hit.position.y-rect.position.y)), Rect2(Vector2(hit.position.x,hit.end.y),Vector2(hit.size.x,rect.end.y-hit.end.y))]:
			if part.size.x > 0.0001 and part.size.y > 0.0001: result.append(part)
	return result

## 返回副本。稳定 ID -> 世界站位、所属 zone、共用 WalkArea 与 GroundSpace。
func anchor_snapshot() -> Dictionary:
	if _space_pose != global_transform: refresh_space()
	var result := {}
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY))
	for row: Dictionary in data.residences:
		for kind: String in ["home", "work", "social", "rest", "door"]:
			var marker: Marker3D = get_node(NodePath(row[kind + "_marker"]))
			var id: String = row[kind + "_anchor_id"]
			result[id] = {"anchor_id":id, "position":marker.global_position, "zone":zone_id, "zone_id":zone_id, "ground":get_node("WalkAreas/Community"), "ground_space":ground_space, "residence_id":row.id, "kind":kind}
	return result

## 日程兼容名只在世界住所边界解析；NPC规则不依赖坐标。
func resolve_anchor(anchor_id: String) -> Dictionary:
	var aliases := {
		"anchor_dock": "residence_dock_workshop_work",
		"anchor_planter": "residence_sunroom_greenhouse_work",
		"anchor_salvage": "residence_salvage_cabin_work",
		"anchor_building": "residence_builder_loft_work",
		"anchor_old_rail": "residence_lantern_archive_work",
		"anchor_solar_room": "residence_lantern_archive_social",
		"anchor_home_dock": "residence_dock_workshop_social"
	}
	var id: String = str(aliases.get(anchor_id, anchor_id))
	return anchor_snapshot().get(id, {}).duplicate()

func route(from: Vector3, to: Vector3) -> Array:
	if _space_pose != global_transform: refresh_space()
	return ground_space.route(from, to) if is_instance_valid(ground_space) else []
