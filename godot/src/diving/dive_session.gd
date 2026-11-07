extends Node3D
## Stable save owner and transactional surface <-> independent dive-map router.
const Catalog = preload("res://src/diving/dive_map_catalog.gd")
const Air = preload("res://src/diving/dive_air.gd")
signal depth_changed(depth: float)
signal zone_changed(label: String)
signal air_changed(ratio: float, lamp_on: bool, found: int, total: int)
signal message(text: String)
signal exited
var give_resource: Callable
var give_rewards: Callable
var _closing := false
var source_query: Callable
var runtime: Node3D
var active := false
var switching := false
var source_id := ""
var map_id := ""
var air = Air.new()
var _host: Node3D
var _surface_parent: Node
var _surface_index := 0
var _previous_current: Node
var _surface_camera: Camera3D
var _economy_ticking := true
var _progress := {"found":[],"opened":[]}
var _entry_point := Vector3.ZERO
var _surface_connections: Array = []
var _visibility: Array = []
var _top_level_nodes: Array = []
var _native_terrain: Array = []

func configure(host: Node3D) -> void:
	_host = host
	assert(Catalog.validate() == "", Catalog.validate())

func _get(property: StringName) -> Variant:
	if is_instance_valid(runtime): return runtime.get(property)
	if property == &"phase": return "surface"
	return null

func _set(property: StringName, value: Variant) -> bool:
	if is_instance_valid(runtime):
		for field in runtime.get_property_list():
			if field.name == property:
				runtime.set(property,value)
				return true
	return false

func _process(delta: float) -> void:
	if not active: air.update(delta,0.0,false,false)

## Public legacy adapter: display labels are never map keys; production injects position resolution.
## `surface_point` is the actor's real dive-in point; world-aligned maps turn it into the entry spot.
func dive(surface_point: Vector3, source := "") -> bool:
	_entry_point = surface_point
	var resolved := source
	if resolved.is_empty() and source_query.is_valid():
		resolved = str(source_query.call(surface_point))
	return enter_map(resolved)

func enter_map(id: String) -> bool:
	if active or switching or not is_instance_valid(_host) or not _host.is_inside_tree(): return false
	if not air.can_dive():
		message.emit("刚上浮，先喘口气（%.0f 秒）" % ceil(air.recover))
		return false
	var entry := Catalog.get_map(id)
	if entry.is_empty():
		message.emit("此海域尚未配置海底地图")
		return false
	var packed := load(str(entry.scene_path)) as PackedScene
	if packed == null: return false
	var candidate := packed.instantiate() as Node3D
	if candidate == null: return false
	# World-aligned maps share the surface coordinate system and own a viewer
	# camera instead of the swim-region rig (Regions/Deco/Chests/DiveCamera).
	var aligned := bool(entry.get("world_aligned",false))
	var required: Array = ["Camera","WorldEnvironment","Water"] if aligned else ["Regions","Deco","Chests","DiveCamera","WorldEnvironment"]
	for node_name in required:
		if not candidate.has_node(node_name):
			candidate.free()
			message.emit("海底地图结构不完整，未离开海面")
			return false
	if candidate.map_id != entry.map_id or candidate.chest_id_base != entry.chest_id_base:
		candidate.free()
		message.emit("海底地图登记不一致，未离开海面")
		return false
	if aligned and not candidate.has_method("begin_dive"):
		candidate.free()
		message.emit("海底地图无法按海面坐标入水，未离开海面")
		return false
	# Preflight before detaching the user's hand-placed surface scene.
	if not aligned:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate.swim_data_path))
		if not data is Dictionary or not data.has("chests") or not data.has("solids"):
			candidate.free()
			message.emit("海底地图数据不可用，未离开海面")
			return false
	switching = true
	source_id = id
	map_id = str(entry.map_id)
	runtime = candidate
	runtime.air = air
	runtime.give_resource = give_resource
	runtime.give_rewards = give_rewards
	preload("res://src/diving/uw_materials.gd").freeze_time(-1.0)
	preload("res://src/diving/uw_materials.gd").set_lamp(false,Vector3.ZERO,Vector3.FORWARD)
	_surface_parent = _host.get_parent()
	_surface_index = _host.get_index()
	var tree := get_tree()
	_surface_camera = get_viewport().get_camera_3d()
	_previous_current = tree.current_scene
	_economy_ticking = bool(tree.root.get_node("Economy").ticking)
	_host.set_meta("dive_map_suspended",true)
	# The owner leaves with its host otherwise; keep just this lightweight router alive.
	reparent(tree.root,false)
	_surface_connections.clear()
	_visibility.clear()
	_top_level_nodes.clear()
	_native_terrain.clear()
	_capture_surface_state(_host)
	# Terrain3D chooses a viewport camera in native enter-tree. Reattach it only
	# after Main's camera is back; never let it latch onto an exiting dive camera.
	for state in _native_terrain: state.parent.remove_child(state.node)
	_surface_parent.remove_child(_host)
	tree.root.get_node("Economy").ticking = false
	tree.root.add_child(runtime)
	tree.current_scene = runtime
	var environment: WorldEnvironment = runtime.get_node("WorldEnvironment")
	# World-aligned scenes finish their own setup in _ready (they are the authored
	# surface twin), so only swim-region maps run the legacy setup handshake.
	if not aligned and not runtime.setup([],environment):
		active = true
		_commit_return()
		message.emit("海底地图校验未通过，已返回海面")
		return false
	runtime.from_dict(_progress)
	runtime.depth_changed.connect(func(value: float): depth_changed.emit(value))
	runtime.zone_changed.connect(func(value: String): zone_changed.emit(value))
	runtime.air_changed.connect(func(ratio: float, lamp: bool, found: int, total: int): air_changed.emit(ratio,lamp,found,total))
	runtime.message.connect(func(text: String): message.emit(text))
	runtime.exited.connect(_request_return)
	var overlay := preload("res://src/diving/dive_map_hud.gd").new()
	overlay.session = self
	runtime.add_child(overlay)
	runtime.tree_exited.connect(_runtime_tree_exited,CONNECT_ONE_SHOT)
	active = true
	if aligned:
		if not runtime.begin_dive(_entry_point):
			_commit_return()
			message.emit("这段水下没有可入水的空间，已返回海面")
			return false
	else:
		runtime.dive(Vector3.ZERO,str(entry.label))
	switching = false
	return true

func _capture_surface_state(node: Node) -> void:
	# Live singleton/viewport signals must never invoke detached controls. Keep the
	# precise callable and flags, then restore once, without replaying _ready.
	if node is Node3D or node is CanvasLayer or node is CanvasItem:
		_visibility.append({"node":node,"visible":node.visible})
	if node.get_class() == "Terrain3D":
		_native_terrain.append({"node":node,"parent":node.get_parent(),"index":node.get_index()})
	if node is Node3D and node.top_level:
		_top_level_nodes.append(node)
		node.top_level = false
	var scripted_methods := {}
	if node.get_script() != null:
		for method in node.get_script().get_script_method_list(): scripted_methods[method.name] = true
	# Terrain3D wires its own C++ signals on native enter-tree; detaching and
	# re-adding it restores them natively, so hand-capturing would duplicate.
	var self_managed := node.get_class() == "Terrain3D"
	for connection in node.get_incoming_connections():
		if self_managed: continue
		# Native Control/Label/Font links reconnect automatically on tree entry.
		var method: StringName = connection.callable.get_method()
		if not scripted_methods.has(method) and not (connection.callable.is_custom() and str(method).is_empty()): continue
		# Object-less lambdas cannot be reconnected by hand; leave them alone.
		var receiver: Object = connection.callable.get_object()
		if receiver == null or not is_instance_valid(receiver): continue
		var signal_ref: Signal = connection.signal
		var emitter: Object = signal_ref.get_object()
		if emitter is Node and (emitter == _host or _host.is_ancestor_of(emitter)): continue
		if signal_ref.is_connected(connection.callable):
			_surface_connections.append({"signal":signal_ref,"callable":connection.callable,"flags":connection.flags,
				"receiver_id":receiver.get_instance_id(),"emitter_id":emitter.get_instance_id()})
			signal_ref.disconnect(connection.callable)
	for child in node.get_children(): _capture_surface_state(child)

func _request_return() -> void:
	if switching: return
	switching = true
	_commit_return.call_deferred()

func _commit_return() -> void:
	if not active or not is_instance_valid(runtime): return
	_merge_progress(runtime.to_dict())
	var tree := get_tree()
	var previous := runtime
	runtime = null
	tree.current_scene = null
	tree.root.remove_child(previous)
	previous.queue_free()
	_surface_parent.add_child(_host)
	_surface_parent.move_child(_host,mini(_surface_index,_surface_parent.get_child_count()-1))
	if is_instance_valid(_surface_camera): _surface_camera.make_current()
	for state in _native_terrain:
		state.parent.add_child(state.node)
		state.parent.move_child(state.node,mini(state.index,state.parent.get_child_count()-1))
	_native_terrain.clear()
	for node in _top_level_nodes:
		if is_instance_valid(node): node.top_level = true
	_top_level_nodes.clear()
	if is_instance_valid(_previous_current) and _previous_current.is_inside_tree(): tree.current_scene = _previous_current
	else: tree.current_scene = _host
	for connection in _surface_connections:
		# A long dive can free deferred nodes; reconnect only live pairs and never
		# probe a dead callable (that is what raises "Parameter obj is null").
		if not is_instance_id_valid(int(connection.receiver_id)) or not is_instance_id_valid(int(connection.emitter_id)): continue
		var signal_ref: Signal = connection.signal
		if signal_ref.is_null(): continue
		if signal_ref.is_connected(connection.callable): continue
		signal_ref.connect(connection.callable,connection.flags)
	_surface_connections.clear()
	for state in _visibility:
		if is_instance_valid(state.node): state.node.visible = state.visible
	_visibility.clear()
	_host.remove_meta("dive_map_suspended")
	_host.resume_after_dive_map()
	tree.root.get_node("Economy").ticking = _economy_ticking
	if is_instance_valid(_surface_camera): _surface_camera.make_current()
	active = false
	switching = false
	source_id = ""
	map_id = ""
	reparent(_host,false)
	exited.emit()

func surface() -> void:
	if is_instance_valid(runtime) and not switching: runtime.surface()
func abort_to_surface() -> void:
	if is_instance_valid(runtime) and not switching:
		if runtime.has_method("abort_to_surface"): runtime.abort_to_surface()
		else: runtime.phase_machine.change("surface",{},true)
func swim_to(destination: Vector3) -> bool:
	return runtime.swim_to(destination) if is_instance_valid(runtime) else false
func cancel_navigation() -> void:
	if is_instance_valid(runtime): runtime.cancel_navigation()
func toggle_lamp() -> void:
	if is_instance_valid(runtime): runtime.toggle_lamp()
func uses_underwater_environment() -> bool:
	return runtime.uses_underwater_environment() if is_instance_valid(runtime) else false
func debug_teleport(point: Vector3) -> void:
	if is_instance_valid(runtime): runtime.debug_teleport(point)
func debug_discover(index: int) -> void:
	if is_instance_valid(runtime): runtime.debug_discover(index)
func freeze_time(value: float) -> void:
	if is_instance_valid(runtime): runtime.freeze_time(value)
func set_facing_debug(on: bool) -> void:
	if is_instance_valid(runtime): runtime.set_facing_debug(on)
func chest_count() -> int:
	return runtime.chest_count() if is_instance_valid(runtime) else 0
func opened_chests() -> int:
	return runtime.opened_chests() if is_instance_valid(runtime) else 0
func discovered_count() -> int:
	return runtime.discovered_count() if is_instance_valid(runtime) else 0
func region_nodes() -> Array:
	return runtime.region_nodes() if is_instance_valid(runtime) else []
func region_node(id: String) -> Node3D:
	return runtime.region_node(id) if is_instance_valid(runtime) else null
func search_state() -> Dictionary:
	return runtime.search_state() if is_instance_valid(runtime) else {}

func _merge_progress(data: Dictionary) -> void:
	for key in ["found","opened"]:
		for id in data.get(key,[]):
			if not _progress[key].has(int(id)): _progress[key].append(int(id))
		_progress[key].sort()

func to_dict() -> Dictionary:
	if is_instance_valid(runtime): _merge_progress(runtime.to_dict())
	return _progress.duplicate(true)

func from_dict(data: Dictionary) -> void:
	_progress = {"found":[],"opened":[]}
	_merge_progress(data)
	if is_instance_valid(runtime): runtime.from_dict(_progress)

func _runtime_tree_exited() -> void:
	# Unexpected scene replacement must not leave a detached live Main or owner.
	if active and not switching and not _closing: dispose()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE: _release_suspended_host()

func _release_suspended_host() -> void:
	for state in _native_terrain:
		if is_instance_valid(state.node) and not state.node.is_inside_tree(): state.node.free()
	_native_terrain.clear()
	if is_instance_valid(_host) and not _host.is_inside_tree():
		_host.remove_meta("dive_map_suspended")
		if _host.actor_controller != null:
			_host.actor_controller.ports.clear()
			_host.actor_controller.after_walk = Callable()
		_host.save_registry.clear()
		_host.navigation.shape_query = Callable()
		if _host.npc_service != null: _host.npc_service.dispose()
		_host.free()
	_host = null

func dispose() -> void:
	if _closing: return
	_closing = true
	var was_active := active
	active = false
	switching = true
	if is_instance_valid(runtime) and runtime.is_inside_tree(): runtime.queue_free()
	runtime = null
	if was_active and is_inside_tree():
		get_tree().paused = false
		get_tree().root.get_node("Economy").ticking = _economy_ticking
	_release_suspended_host()
	_surface_connections.clear()
	_visibility.clear()
	_top_level_nodes.clear()
	source_query = Callable()
	give_resource = Callable()
	give_rewards = Callable()
	if was_active and is_inside_tree(): queue_free()
