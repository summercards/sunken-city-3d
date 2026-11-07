@tool
extends "res://src/npc/npc_rooftop_anchors.gd"
## 浮店只读站位适配；Objects是刚性支撑坐标系，作者根与地面仍归原区块。
@export var zone_path := NodePath("../..")
@export var walk_path := NodePath("WalkAreas/Walk_sea_supply_deck")

func _ready() -> void:
	configure(get_node_or_null(zone_path) as Node3D)

func _ground_context() -> Dictionary:
	var zone: Node3D = _zone.get_ref() if _zone != null else null
	if not is_instance_valid(zone) or Engine.is_editor_hint(): return {}
	var area := zone.get_node_or_null(walk_path)
	var space: Node3D = zone.get("ground_space")
	var frame := get_parent() as Node3D
	if not is_instance_valid(area) or not is_instance_valid(space) or not is_instance_valid(frame): return {}
	# heave不属于布局修订；数组原地编辑、根摆位、active及外部revision仍会使缓存失效。
	var signature: Array = [zone.global_transform, area, area.transform, area.get("active"), space,
		area.get("ground_space"), space.get("revision"), area.get("rects"), area.get("polygons"),
		area.get("surface_triangles"), area.get("physical_surface_triangles"), area.get("body_radius"),
		area.get("open_surface_junctions"),
		snappedf(float(area.get("surface_y")) - frame.global_position.y, 0.00001),
		snappedf(float(area.get("span_min")) - frame.global_position.y, 0.00001),
		snappedf(float(area.get("span_max")) - frame.global_position.y, 0.00001)]
	if signature != _surface_signature:
		_support_cache.clear()
		_surface_signature = signature.duplicate(true)
	if area.get("active") != true or area.get("ground_space") != space: return {}
	return {"zone": zone, "ground": area, "ground_space": space, "revision": space.get("revision"), "frame": frame}

func anchor_snapshot() -> Dictionary:
	_metrics.snapshot_requests += 1
	var context := _ground_context()
	if context.is_empty(): return {}
	var result := {}
	var frame: Node3D = context.frame
	var zone_id := str(context.zone.get("zone_id"))
	for station in get_children():
		if not station is Node3D or not station.has_meta("npc_id"): continue
		var residence_id := str(station.name)
		for kind: String in KINDS:
			var marker := station.get_node_or_null(NodePath(kind.capitalize())) as Marker3D
			if marker == null or not bool(marker.get_meta("active", true)): continue
			var key := marker.get_instance_id()
			var pose: Transform3D = transform * station.transform * marker.transform
			var cached: Dictionary = _support_cache.get(key, {})
			var local: Vector3
			if cached.get("pose") == pose and cached.get("revision") == context.revision:
				_metrics.support_cache_hits += 1
				local = cached.support
			else:
				var support := _supported(marker.global_position, context)
				local = frame.to_local(support) if support.is_finite() else Vector3.INF
				_support_cache[key] = {"pose": pose, "revision": context.revision, "support": local}
			if not local.is_finite(): continue
			var id := residence_id if kind == "home" else residence_id + "_" + kind
			if kind == "work": id = str(station.get_meta("work_anchor_id", id))
			result[id] = {"anchor_id": id, "position": frame.to_global(local), "position_local": local,
				"support_frame": frame, "support_origin": frame.global_position, "site_pose": context.zone.global_transform,
				"zone": zone_id, "zone_id": zone_id, "ground": context.ground, "ground_space": context.ground_space,
				"residence_id": residence_id, "npc_id": str(station.get_meta("npc_id")), "kind": kind,
				"support_validated": true, "support_revision": context.revision}
	return result
