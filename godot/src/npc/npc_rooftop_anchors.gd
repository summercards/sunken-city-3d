@tool
extends Node3D
## 天台草地暂驻端口；作者站位只来自TSCN，不创建地面、房屋或Marker。
const KINDS := ["home", "work", "social", "rest", "door"]
const SUPPORT_TOLERANCE := 0.05
const ALIASES := {
	"anchor_dock": "residence_dock_workshop_work",
	"anchor_planter": "residence_sunroom_greenhouse_work",
	"anchor_salvage": "residence_salvage_cabin_work",
	"anchor_building": "residence_builder_loft_work",
	"anchor_old_rail": "residence_lantern_archive_work",
	"anchor_solar_room": "residence_lantern_archive_social",
	"anchor_home_dock": "residence_dock_workshop_social",
	"residence_flower_shop_work": "anchor_flower_shop",
	"residence_general_store_work": "anchor_general_store",
}
var _zone: WeakRef
var _space_pose := Transform3D.IDENTITY
var _surface_signature: Array = []
var _support_cache: Dictionary = {}
var _metrics := {"snapshot_requests": 0, "support_projections": 0, "support_cache_hits": 0}

func performance_metrics() -> Dictionary:
	return _metrics.duplicate()

func canonical_anchor_id(anchor_id: String) -> String:
	return str(ALIASES.get(anchor_id, anchor_id))

func _ready() -> void:
	configure(get_parent() as Node3D)

func configure(zone: Node3D) -> void:
	_zone = weakref(zone) if is_instance_valid(zone) else null
	_space_pose = zone.global_transform if is_instance_valid(zone) else Transform3D.IDENTITY
	_surface_signature = []
	_support_cache.clear()

## 只复用原区块的WalkArea/GroundSpace；未就绪或编辑器中不派生任何节点。
func _ground_context() -> Dictionary:
	var zone: Node3D = _zone.get_ref() if _zone != null else null
	if not is_instance_valid(zone) or Engine.is_editor_hint(): return {}
	var area := zone.get_node_or_null("WalkAreas/Walk_rooftop_ranch_access")
	var space: Node3D = zone.get("ground_space")
	if not is_instance_valid(area) or not is_instance_valid(space): return {}
	# 直接比较作者数据副本，可发现原地改数组；不把昂贵surface_faces当签名。
	var surface: Array = [zone.global_transform, area, area.global_transform, area.get("active"),
		area.get("ground_space"), space, area.get("surface_y"), area.get("span_min"), area.get("span_max"),
		area.get("body_radius"), area.get("rects"), area.get("polygons"), area.get("surface_triangles"),
		area.get("physical_surface_triangles"), area.get("open_surface_junctions")]
	if surface != _surface_signature:
		_support_cache.clear()
		space.rebuild()
		_space_pose = zone.global_transform
		_surface_signature = surface.duplicate(true)
	if area.get("active") != true or area.get("ground_space") != space: return {}
	return {"zone": zone, "ground": area, "ground_space": space, "revision": space.get("revision")}

## 失效点返回INF，不吸附到边界、水面或别的楼层。
func _supported(point: Vector3, context: Dictionary) -> Vector3:
	if not point.is_finite(): return Vector3.INF
	_metrics.support_projections += 1
	var support: Vector3 = context.ground.surface_point(point)
	if not support.is_finite() or support.distance_to(point) > SUPPORT_TOLERANCE: return Vector3.INF
	if context.ground_space.area_at(support, SUPPORT_TOLERANCE) != context.ground: return Vector3.INF
	return support

## 稳定ID -> 可踩世界点；每次重读手摆Marker，随原根的transform移动。
func anchor_snapshot() -> Dictionary:
	_metrics.snapshot_requests += 1
	var context := _ground_context()
	if context.is_empty(): return {}
	var result := {}
	var zone_id := str(context.zone.get("zone_id"))
	for station in get_children():
		if not station is Node3D or not station.has_meta("npc_id"): continue
		var residence_id := str(station.name)
		for kind: String in KINDS:
			var marker := station.get_node_or_null(NodePath(kind.capitalize())) as Marker3D
			if marker == null: continue
			if marker.has_meta("active") and not bool(marker.get_meta("active")): continue
			var key := marker.get_instance_id()
			var pose := marker.global_transform
			var cached: Dictionary = _support_cache.get(key, {})
			var support: Vector3
			if cached.get("pose") == pose and cached.get("revision") == context.revision:
				_metrics.support_cache_hits += 1
				support = cached.support
			else:
				support = _supported(marker.global_position, context)
				_support_cache[key] = {"pose": pose, "revision": context.revision, "support": support}
			if not support.is_finite(): continue
			var id := residence_id if kind == "home" else residence_id + "_" + kind
			if kind == "work": id = str(station.get_meta("work_anchor_id", id))
			result[id] = {"anchor_id": id, "position": support, "zone": zone_id, "zone_id": zone_id,
				"ground": context.ground, "ground_space": context.ground_space,
				"residence_id": residence_id, "npc_id": str(station.get_meta("npc_id")), "kind": kind,
				"support_validated": true, "support_revision": context.revision}
	return result

## 所有旧日程名只解释到天台站位；未知或失效锚点明确返回空字典。
func resolve_anchor(anchor_id: String) -> Dictionary:
	var id := str(ALIASES.get(anchor_id, anchor_id))
	return anchor_snapshot().get(id, {}).duplicate()

func route(from: Vector3, to: Vector3) -> Array:
	var context := _ground_context()
	if context.is_empty(): return []
	var start := _supported(from, context)
	var goal := _supported(to, context)
	if not start.is_finite() or not goal.is_finite(): return []
	return context.ground_space.route(start, goal)

func home_labels() -> Dictionary:
	var labels := {}
	for station in get_children():
		if station is Node3D and station.has_meta("npc_id"):
			labels[str(station.name)] = str(station.get_meta("home_label", "天台草地 · 暂驻"))
	return labels
