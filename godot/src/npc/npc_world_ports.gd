extends RefCounted
## 注入端口的弱引用适配；只消费住所提供的锚点与统一地面。
var _residence: WeakRef
var _queries: Dictionary = {}
var _anchors: Dictionary = {}
var _aliases: Dictionary = {}
var _resolved: Dictionary = {}
var _batch_ready := false
var metrics := {"anchor_snapshots": 0, "alias_resolutions": 0, "pathfinding": 0, "anchor_projections": 0}

## 每个检测批次只采一次；别名只缓存ID，绝不缓存失效站位。
func begin_batch() -> Dictionary:
	var owner = residence()
	metrics.anchor_snapshots += 1
	_anchors = owner.anchor_snapshot() if is_instance_valid(owner) else {}
	_resolved.clear()
	_batch_ready = true
	for id in _anchors.keys():
		var entry: Variant = _anchors[id]
		if not entry is Dictionary or not valid_anchor(entry):
			_anchors.erase(id)
			continue
		if not entry.get("support_validated", false):
			metrics.anchor_projections += 1
			var point: Vector3 = entry.ground.surface_point(entry.position)
			if not point.is_finite():
				_anchors.erase(id)
				continue
			entry = entry.duplicate()
			entry["position"] = point
			entry["support_validated"] = true
			_anchors[id] = entry
	return _anchors

static func valid_anchor(anchor: Dictionary) -> bool:
	if anchor.get("active", true) == false or anchor.get("ok", true) == false: return false
	if not anchor.get("position") is Vector3 or not anchor.position.is_finite(): return false
	var ground: Variant = anchor.get("ground")
	return is_instance_valid(ground) and ground.get("active") != false and ground.has_method("surface_point")

func configure(residence: Node3D, world_query: Callable, enabled_query: Callable) -> void:
	_residence = weakref(residence) if is_instance_valid(residence) else null
	_queries.clear()
	_anchors.clear()
	_aliases.clear()
	_resolved.clear()
	_batch_ready = false
	for key in metrics: metrics[key] = 0
	for pair in [["world", world_query], ["enabled", enabled_query]]:
		var callback: Callable = pair[1]
		if callback.is_valid() and not callback.is_custom() and callback.get_object() != null:
			_queries[pair[0]] = {"owner": weakref(callback.get_object()), "method": callback.get_method()}

func residence():
	return _residence.get_ref() if _residence != null else null

func query(key: String) -> Variant:
	if not _queries.has(key): return null
	var owner = _queries[key].owner.get_ref()
	return owner.call(_queries[key].method) if is_instance_valid(owner) else (false if key == "enabled" else null)

func anchors() -> Dictionary:
	if not _batch_ready: begin_batch()
	return _anchors

func resolve(anchor_id: String, npc: Dictionary, world: Dictionary, action: String) -> Dictionary:
	var owner = residence()
	if not is_instance_valid(owner): return {}
	var available := anchors()
	var night := action == "rest" and (float(world.get("hour", 8.0)) >= 21.5 or float(world.get("hour", 8.0)) < 6.0)
	var scoped: bool = owner.has_method("canonical_anchor_for_npc")
	var key := [anchor_id, npc.get("residence_id", "") if night or scoped else "", night]
	if _resolved.has(key): return _resolved[key]
	var target := {}
	# 夜间站在自家rest marker，而非床心；站位只来自住所快照。
	if night:
		for entry in available.values():
			if entry.get("residence_id") == npc.get("residence_id") and entry.get("kind") == "rest":
				target = entry
				break
	if target.is_empty():
		var canonical := str(_aliases.get(anchor_id, anchor_id))
		if scoped: canonical = str(owner.canonical_anchor_for_npc(anchor_id, npc))
		if available.has(canonical):
			target = available[canonical]
		elif not scoped and not _aliases.has(anchor_id):
			metrics.alias_resolutions += 1
			if owner.has_method("canonical_anchor_id"):
				canonical = str(owner.canonical_anchor_id(anchor_id))
			elif owner.has_method("resolve_anchor"):
				var value: Variant = owner.resolve_anchor(anchor_id)
				if value is Dictionary: canonical = str(value.get("anchor_id", anchor_id))
			if owner.has_method("canonical_anchor_id") or canonical != anchor_id: _aliases[anchor_id] = canonical
			target = available.get(canonical, {})
	_resolved[key] = target
	return target

func path(start: Vector3, target: Dictionary) -> Array:
	metrics.pathfinding += 1
	var ground: Variant = target.get("ground")
	if not is_instance_valid(ground) or not ground.has_method("path_between") or not ground.has_method("surface_point"): return []
	var goal: Vector3 = ground.surface_point(target.position)
	var support: Vector3 = ground.surface_point(start)
	if not goal.is_finite() or not support.is_finite() or support.distance_to(start) > 0.3: return []
	return ground.path_between(start, goal)

## 刚性支撑的瞬时世界高度不是站位布局修订。
static func anchor_layout(anchor: Dictionary) -> Dictionary:
	var result := anchor.duplicate()
	if result.has("position_local"):
		result.erase("position")
		result.erase("support_origin")
	return result

func layout_snapshot(available: Dictionary) -> Dictionary:
	var result := {}
	for id in available: result[id] = anchor_layout(available[id])
	return result

func home_labels() -> Dictionary:
	var provider = residence()
	if is_instance_valid(provider) and provider.has_method("home_labels"):
		var provided: Variant = provider.home_labels()
		if provided is Dictionary: return provided.duplicate()
	var labels := {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/npc/residences.json"))
	if data is Dictionary:
		for row in data.get("residences", []): labels[str(row.id)] = str(row.get("label", row.id))
	return labels
