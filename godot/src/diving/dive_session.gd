extends Node3D
## Stable save owner and transactional surface <-> independent dive-map router.
const Catalog = preload("res://src/diving/dive_map_catalog.gd")
const Air = preload("res://src/diving/dive_air.gd")
const UnderwaterSurfaceDebugScript = preload("res://src/rendering/underwater_surface_debug.gd")
signal depth_changed(depth: float)
signal zone_changed(label: String)
signal air_changed(ratio: float, lamp_on: bool, found: int, total: int)
signal message(text: String)
signal exited
signal transition_started(phase: String)
signal transition_phase(phase: String)
signal transition_completed(phase: String)
signal transition_failed(reason: String)
var give_resource: Callable
var give_rewards: Callable
var curtain: CanvasLayer
var _closing := false
var _transition_pending := false
var _curtain_session := false
var _return_requested := false
var _transition_stage := "idle"
var trace: Dictionary = {"events":[],"load_begin":{},"commit_return":{}}
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
var _curtain_parent: Node
var _curtain_index := 0
var _curtain_focus: Callable
var _surface_process_mode := Node.PROCESS_MODE_INHERIT
var _surface_frozen := false
var _surface_modes: Array = []
var _air_before_entry: Dictionary = {}
var _closed_draw: Dictionary = {}
var underwater_surface_debug

func configure(host: Node3D) -> void:
	_host = host
	assert(Catalog.validate() == "", Catalog.validate())
	underwater_surface_debug = UnderwaterSurfaceDebugScript.new()
	underwater_surface_debug.name = "UnderwaterSurfaceDebug"
	add_child(underwater_surface_debug)

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
	if not active and not switching: air.update(delta,0.0,false,false)

## Public legacy adapter: display labels are never map keys; production injects position resolution.
## `surface_point` is the actor's real dive-in point; world-aligned maps turn it into the entry spot.
func dive(surface_point: Vector3, source := "") -> bool:
	if _closing or active or switching: return false
	_entry_point = surface_point
	var resolved := source
	if resolved.is_empty() and source_query.is_valid():
		resolved = str(source_query.call(surface_point))
	return enter_map(resolved)

## 生产入口：只表示请求已接受；真正的切图在 deferred 协程中执行。
func request_dive(surface_point: Vector3, source := "") -> bool:
	if _closing or active or switching or not is_instance_valid(_host) or not _host.is_inside_tree(): return false
	if not air.can_dive():
		message.emit("刚上浮，先喘口气（%.0f 秒）" % ceil(air.recover))
		return false
	if is_instance_valid(curtain) and curtain.phase != "idle": return false
	var resolved := source
	if resolved.is_empty() and source_query.is_valid():
		resolved = str(source_query.call(surface_point))
	if Catalog.get_map(resolved).is_empty():
		message.emit("此海域尚未配置海底地图")
		return false
	_entry_point = surface_point
	switching = true
	_return_requested = false
	if not is_instance_valid(curtain):
		_begin_legacy_request.call_deferred(resolved)
	else:
		_transition_pending = true
		_air_before_entry = _air_snapshot()
		_begin_production_dive.call_deferred(resolved)
	return true

func _begin_legacy_request(id: String) -> void:
	if _closing: return
	if not _enter_legacy_map(id): switching = false

func enter_map(id: String) -> bool:
	if _closing or active or switching or not is_instance_valid(_host) or not _host.is_inside_tree(): return false
	return _enter_legacy_map(id)

func _enter_legacy_map(id: String) -> bool:
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
	if not _validate_candidate(candidate,entry):
		if is_instance_valid(candidate): candidate.free()
		return false
	return _enter_map_core(id,entry,candidate,false)

func _validate_candidate(candidate: Node3D, entry: Dictionary) -> bool:
	if candidate == null:
		return false
	var aligned := bool(entry.get("world_aligned",false))
	var required: Array = ["Camera","WorldEnvironment","Water"] if aligned else ["Regions","Deco","Chests","DiveCamera","WorldEnvironment"]
	for node_name in required:
		if not candidate.has_node(node_name):
			message.emit("海底地图结构不完整，未离开海面")
			return false
	if candidate.map_id != entry.map_id or candidate.chest_id_base != entry.chest_id_base:
		message.emit("海底地图登记不一致，未离开海面")
		return false
	if aligned and not candidate.has_method("begin_dive"):
		message.emit("海底地图无法按海面坐标入水，未离开海面")
		return false
	if not aligned:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate.swim_data_path))
		if not data is Dictionary or not data.has("chests") or not data.has("solids"):
			message.emit("海底地图数据不可用，未离开海面")
			return false
	return true

func _enter_map_core(id: String, entry: Dictionary, candidate: Node3D, production: bool) -> bool:
	switching = true
	var aligned := bool(entry.get("world_aligned",false))
	source_id = id
	map_id = str(entry.map_id)
	runtime = candidate
	runtime.set_meta("session_owned", true)
	if production:
		runtime.set_meta("request_surface_transition", Callable(self, "_request_return"))
	var sunlight := _surface_sunlight()
	if runtime.has_method("configure_underwater_light"):
		runtime.configure_underwater_light(sunlight)
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
	if not production: _economy_ticking = bool(tree.root.get_node("Economy").ticking)
	_host.set_meta("dive_map_suspended",true)
	if get_parent() != tree.root: reparent(tree.root,false)
	_surface_connections.clear()
	_visibility.clear()
	_top_level_nodes.clear()
	_native_terrain.clear()
	_capture_surface_state(_host)
	for state in _native_terrain: state.parent.remove_child(state.node)
	_surface_parent.remove_child(_host)
	tree.root.get_node("Economy").ticking = false
	tree.root.add_child(runtime)
	tree.current_scene = runtime
	var environment: WorldEnvironment = runtime.get_node("WorldEnvironment")
	if not aligned and not runtime.setup([],environment):
		active = true
		_commit_return(not production,false)
		if not production: switching = false
		message.emit("海底地图校验未通过，已返回海面")
		return false
	var profile = _host.get("avatar_profile")
	if profile != null and profile.has_method("query") and runtime.get("dive_controller") != null:
		runtime.dive_controller.character.apply_avatar(profile.query())
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
	if production: _set_runtime_transition_frozen(true)
	if aligned:
		if not runtime.begin_dive(_entry_point):
			if not production: _commit_return(true,false)
			message.emit("这段水下没有可入水的空间，已返回海面")
			return false
	else:
		runtime.dive(Vector3.ZERO,str(entry.label))
	if underwater_surface_debug != null:
		underwater_surface_debug.bind_runtime(runtime)
	if not production: switching = false
	return true

func _begin_production_dive(id: String) -> void:
	if _closing: return
	_curtain_session = true
	_borrow_curtain()
	# Session 与幕先留在 root，海面整棵树才可以冻结且不影响圆幕 tween。
	reparent(get_tree().root,false)
	_freeze_surface()
	_transition_started("dive")
	await curtain.cover_blank()
	if _closing: return
	await _await_curtain_draw()
	if _closing: return
	_trace("load_begin")
	var entry := Catalog.get_map(id)
	var path := str(entry.scene_path)
	var error := ResourceLoader.load_threaded_request(path,"PackedScene")
	if error != OK:
		await _fail_transition("海底地图加载失败，未离开海面")
		return
	var deadline := Time.get_ticks_msec() + 30000
	var status: int = ResourceLoader.load_threaded_get_status(path)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if _closing: return
		status = ResourceLoader.load_threaded_get_status(path)
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		await _fail_transition("海底地图加载失败或超时，未离开海面")
		return
	var packed := ResourceLoader.load_threaded_get(path) as PackedScene
	var candidate := packed.instantiate() as Node3D if packed != null else null
	if not _validate_candidate(candidate,entry):
		if is_instance_valid(candidate): candidate.free()
		await _fail_transition("海底地图校验未通过，已返回海面")
		return
	if not _enter_map_core(id,entry,candidate,true):
		await _fail_transition("海底地图校验未通过，已返回海面")
		return
	_transition_phase("preparing")
	var ready := await _await_runtime_ready()
	if _closing: return
	if not ready:
		await _fail_transition("海底入口准备失败或超时，已返回海面")
		return
	# 碰撞与入口选点已准备，但尚未播放下沉；提交初始角色/相机后展开。
	await get_tree().process_frame
	if _closing: return
	await _await_curtain_draw()
	if _closing: return
	_trace("entry_ready")
	_transition_phase("opening")
	await curtain.uncover_blank()
	if _closing: return
	# 圆幕完全打开才释放可见入水；仍属于同一 enter 阶段和切图事务。
	# 玩家能看见扑通/下沉，期间输入、日期、耗氧和写盘继续冻结。
	_transition_phase("entering")
	var controller: Node = runtime.get("dive_controller") if is_instance_valid(runtime) else null
	if controller != null: controller.release_entry()
	if not await _await_entry_complete():
		if _closing: return
		await curtain.cover_blank()
		await _await_curtain_draw()
		await _fail_transition("入水动作未完成，已返回海面")
		return
	if _closing: return
	_set_runtime_transition_frozen(false)
	_air_before_entry.clear()
	_transition_pending = false
	switching = false
	_transition_complete("dive")
	if _return_requested: _request_return()

func _await_runtime_ready() -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if _closing or not is_instance_valid(runtime) or not runtime.is_inside_tree(): return false
		var controller: Node = runtime.get("dive_controller")
		var phase := str(controller.machine.current) if controller != null else str(runtime.get("phase"))
		if phase in ["surface","exit"]: return false
		var ready: bool = controller.entry_is_prepared() if controller != null else phase == "swim"
		var verified: Variant = runtime.get("entry_verified")
		if verified != null: ready = ready and bool(verified)
		if ready: return true
		await get_tree().process_frame
	trace.events.append({"event":"runtime_ready_timeout","phase":str(runtime.get("phase")) if is_instance_valid(runtime) else "freed"})
	return false

func _await_entry_complete() -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if _closing or not is_instance_valid(runtime) or not runtime.is_inside_tree(): return false
		var controller: Node = runtime.get("dive_controller")
		if controller == null or controller.machine.current in ["surface", "exit"]: return false
		if controller.machine.current == "swim": return true
		await get_tree().process_frame
	return false

func _await_curtain_draw() -> void:
	_closed_draw.clear()
	var before := Engine.get_process_frames()
	var drawn_before := Engine.get_frames_drawn()
	if DisplayServer.get_name() == "headless": await get_tree().process_frame
	else: await RenderingServer.frame_post_draw
	if _closing or not is_instance_valid(curtain): return
	if curtain.visible and curtain.phase == "closed" and is_zero_approx(curtain.openness):
		_closed_draw = {"barrier":"process_frame" if DisplayServer.get_name() == "headless" else "frame_post_draw",
			"process_before":before,"process_after":Engine.get_process_frames(),
			"frames_drawn_before":drawn_before,"frames_drawn":Engine.get_frames_drawn(),"curtain_id":curtain.get_instance_id()}
	# Return to a normal process-frame boundary before loading, detaching scenes,
	# restoring Terrain3D or rebaking navigation. Never mutate the render world
	# inside the RenderingServer post-draw signal dispatch stack.
	await get_tree().process_frame

func _set_runtime_transition_frozen(value: bool) -> void:
	if not is_instance_valid(runtime): return
	var controller: Node = runtime.get("dive_controller")
	if controller != null: controller.transition_frozen = value

func _transition_started(kind: String) -> void:
	_closed_draw.clear()
	trace.events.append({"event":"transition_started","phase":kind})
	transition_started.emit(kind)
	_transition_phase("closing")

func _transition_phase(value: String) -> void:
	_transition_stage = value
	trace.events.append({"event":"transition_phase","phase":value})
	transition_phase.emit(value)

func _transition_complete(kind: String) -> void:
	_transition_stage = "idle"
	trace.events.append({"event":"transition_completed","phase":kind})
	transition_completed.emit(kind)

func _trace(event: String) -> void:
	var closed: bool = is_instance_valid(curtain) and curtain.visible and curtain.phase == "closed" and is_zero_approx(curtain.openness)
	var evidence := {"event":event,"curtain_closed":closed,"curtain_drawn":closed and not _closed_draw.is_empty(),
		"draw_evidence":_closed_draw.duplicate(),"process_frame":Engine.get_process_frames()}
	trace.events.append(evidence)
	trace[event] = evidence

func _borrow_curtain() -> void:
	if not is_instance_valid(curtain) or is_instance_valid(_curtain_parent): return
	_curtain_parent = curtain.get_parent()
	_curtain_index = curtain.get_index()
	_curtain_focus = curtain.focus_query
	curtain.focus_query = _curtain_runtime_focus
	curtain.reparent(get_tree().root,false)

func _curtain_runtime_focus() -> Vector2:
	if is_instance_valid(runtime) and runtime.is_inside_tree():
		var controller: Node = runtime.get("dive_controller")
		if controller != null and is_instance_valid(controller.camera):
			return controller.camera.unproject_position(runtime.dive_position() + Vector3.UP * 0.4)
	# 只在 Main 仍在树中时调用原来的海面取景端口。
	if is_instance_valid(_host) and _host.is_inside_tree() and _curtain_focus.is_valid(): return _curtain_focus.call()
	return get_viewport().get_visible_rect().size * 0.5

func _restore_curtain() -> void:
	if not _curtain_session: return
	if is_instance_valid(curtain):
		curtain.focus_query = _curtain_focus
		if is_instance_valid(_curtain_parent):
			curtain.reparent(_curtain_parent,false)
			_curtain_parent.move_child(curtain,mini(_curtain_index,_curtain_parent.get_child_count()-1))
	_curtain_parent = null
	_curtain_focus = Callable()
	_curtain_session = false

func _freeze_surface() -> void:
	if _surface_frozen: return
	_surface_frozen = true
	_surface_process_mode = _host.process_mode
	_economy_ticking = bool(get_tree().root.get_node("Economy").ticking)
	_freeze_surface_nodes(_host)
	_host.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.get_node("Economy").ticking = false

func _freeze_surface_nodes(node: Node) -> void:
	# HUD 等 ALWAYS 子节点不继承 Main 的禁用，须逐一保存并冻结。
	for child in node.get_children():
		if child.process_mode != Node.PROCESS_MODE_INHERIT:
			_surface_modes.append({"node":child,"mode":child.process_mode})
			child.process_mode = Node.PROCESS_MODE_DISABLED
		_freeze_surface_nodes(child)

func _thaw_surface() -> void:
	if not _surface_frozen: return
	for state in _surface_modes:
		if is_instance_valid(state.node): state.node.process_mode = state.mode
	_surface_modes.clear()
	if is_instance_valid(_host): _host.process_mode = _surface_process_mode
	if is_inside_tree(): get_tree().root.get_node("Economy").ticking = _economy_ticking
	_surface_frozen = false

## Capture the existing daylight source before Main is detached. No second clock.
func _surface_sunlight() -> Dictionary:
	var profile := {"direction":Vector3(0.5191,0.7787,-0.3523), "color":Color(1.0,0.955,0.8), "strength":1.0}
	var sun := _host.get_node_or_null("World/Lights/Sun") as DirectionalLight3D
	if sun != null:
		profile.direction = sun.global_basis.z.normalized()
		profile.color = sun.light_color
		profile.strength = clampf(sun.light_energy, 0.0, 1.0)
	# Read the active surface before detaching Main. Only optical inputs cross
	# the boundary; never share the live material or shore/depth dependencies.
	var water := _host.get_node_or_null("World/Water") as MeshInstance3D
	if water != null:
		var surface := {}
		if water.get("ocean_waves") != null: surface.ocean_waves = water.get("ocean_waves")
		if water.get("wave_scale") != null: surface.wave_scale = water.get("wave_scale")
		var material := water.material_override as ShaderMaterial
		if material != null:
			var normal_texture: Variant = material.get_shader_parameter("large_wave_normals")
			if normal_texture is Texture2D: surface.large_wave_normals = normal_texture
		profile.surface = surface
	return profile

func _air_snapshot() -> Dictionary:
	var data := {}
	for field in ["air","lamp","low_warned","crit_warned","emptied","recover","surface_depth"]: data[field] = air.get(field)
	return data

func _fail_transition(text: String) -> void:
	if _closing: return
	if active and is_instance_valid(runtime):
		# 入口异步校验可能仍在等待 physics_frame；先让控制器收束到 surface，
		# 避免直接 free 后地图协程访问已脱树的 SceneTree。
		_set_runtime_transition_frozen(true)
		if runtime.has_method("abort_to_surface"): runtime.abort_to_surface()
		# 即使 begin 被拒绝，地图 ready 安排的物理校验也必须先完成。
		for _i in 3:
			await get_tree().physics_frame
			if _closing: return
		await get_tree().process_frame
		if _closing: return
		if active and is_instance_valid(runtime): _commit_return(false,false)
	for field in _air_before_entry: air.set(field,_air_before_entry[field])
	_air_before_entry.clear()
	_transition_phase("opening")
	await curtain.uncover_blank()
	if _closing: return
	_restore_curtain()
	_thaw_surface()
	if get_parent() != _host: reparent(_host,false)
	_transition_pending = false
	_return_requested = false
	switching = false
	_transition_stage = "idle"
	trace.events.append({"event":"transition_failed","message":text})
	transition_failed.emit(text)
	message.emit(text)

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
	if _transition_pending or switching:
		_return_requested = true
		return
	if not active or not is_instance_valid(runtime): return
	_return_requested = true
	switching = true
	if not _curtain_session:
		_commit_return.call_deferred()
	else:
		get_tree().paused = false
		_transition_pending = true
		_set_runtime_transition_frozen(true)
		_return_with_curtain.call_deferred()

func _return_with_curtain() -> void:
	if _closing: return
	_set_runtime_transition_frozen(true)
	_transition_started("return")
	await curtain.cover_blank()
	if _closing: return
	await _await_curtain_draw()
	if _closing: return
	_commit_return(false)
	await get_tree().process_frame
	if _closing: return
	_transition_phase("opening")
	await curtain.uncover_blank()
	if _closing: return
	_restore_curtain()
	_thaw_surface()
	reparent(_host,false)
	_transition_pending = false
	_return_requested = false
	switching = false
	_transition_complete("return")
	exited.emit()

func _commit_return(finish := true, merge := true) -> void:
	if not active or not is_instance_valid(runtime): return
	if underwater_surface_debug != null:
		underwater_surface_debug.clear_runtime()
	if _curtain_session: _trace("commit_return")
	if merge: _merge_progress(runtime.to_dict())
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
	if not _surface_frozen: tree.root.get_node("Economy").ticking = _economy_ticking
	if is_instance_valid(_surface_camera): _surface_camera.make_current()
	active = false
	source_id = ""
	map_id = ""
	if finish:
		switching = false
		_return_requested = false
		reparent(_host,false)
		exited.emit()

func surface() -> void:
	if switching:
		_return_requested = true
		return
	if not is_instance_valid(runtime): return
	runtime.surface()
	if _curtain_session: _request_return()
func abort_to_surface() -> void:
	if not is_instance_valid(runtime) or switching: return
	if runtime.has_method("abort_to_surface"): runtime.abort_to_surface()
	else: runtime.phase_machine.change("surface",{},true)
	if _curtain_session: _request_return()
func swim_to(destination: Vector3) -> bool:
	return runtime.swim_to(destination) if is_instance_valid(runtime) and not switching else false
func cancel_navigation() -> void:
	if is_instance_valid(runtime) and not switching: runtime.cancel_navigation()
func toggle_lamp() -> void:
	if is_instance_valid(runtime) and not switching: runtime.toggle_lamp()
func uses_underwater_environment() -> bool:
	return runtime.uses_underwater_environment() if is_instance_valid(runtime) else false
func debug_teleport(point: Vector3) -> void:
	if is_instance_valid(runtime): runtime.debug_teleport(point)
func debug_discover(index: int) -> void:
	if is_instance_valid(runtime) and runtime.has_method("debug_discover"): runtime.debug_discover(index)
func freeze_time(value: float) -> void:
	if is_instance_valid(runtime) and runtime.has_method("freeze_time"): runtime.freeze_time(value)
func set_facing_debug(on: bool) -> void:
	if is_instance_valid(runtime) and runtime.has_method("set_facing_debug"): runtime.set_facing_debug(on)
func chest_count() -> int:
	return runtime.chest_count() if is_instance_valid(runtime) else 0
func opened_chests() -> int:
	return runtime.opened_chests() if is_instance_valid(runtime) else 0
func discovered_count() -> int:
	return runtime.discovered_count() if is_instance_valid(runtime) else 0
func region_nodes() -> Array:
	return runtime.region_nodes() if is_instance_valid(runtime) and runtime.has_method("region_nodes") else []
func region_node(id: String) -> Node3D:
	return runtime.region_node(id) if is_instance_valid(runtime) and runtime.has_method("region_node") else null
func search_state() -> Dictionary:
	return runtime.search_state() if is_instance_valid(runtime) and runtime.has_method("search_state") else {}

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

func underwater_surface_debug_is_open() -> bool:
	return underwater_surface_debug != null and underwater_surface_debug.is_open()

func _runtime_tree_exited() -> void:
	# Unexpected scene replacement must not leave a detached live Main or owner.
	if active and is_instance_valid(runtime) and not _closing: dispose()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE: _release_suspended_host()

func _release_suspended_host() -> void:
	for state in _native_terrain:
		if is_instance_valid(state.node) and not state.node.is_inside_tree(): state.node.free()
	_native_terrain.clear()
	var host := _host
	_host = null
	# 正常 Main 退树时 Session 仍是它的子节点，不能在 PREDELETE 中递归 free 宿主。
	if is_instance_valid(host) and not host.is_inside_tree() and bool(host.get_meta("dive_map_suspended",false)):
		host.remove_meta("dive_map_suspended")
		if host.actor_controller != null:
			host.actor_controller.ports.clear()
			host.actor_controller.after_walk = Callable()
		host.save_registry.clear()
		host.navigation.shape_query = Callable()
		if host.npc_service != null: host.npc_service.dispose()
		host.free()

func dispose() -> void:
	if _closing: return
	_closing = true
	var was_active := active
	var detached_session := get_parent() != _host
	active = false
	switching = true
	if is_instance_valid(runtime) and runtime.is_inside_tree(): runtime.queue_free()
	runtime = null
	_restore_curtain()
	_thaw_surface()
	if is_inside_tree() and is_instance_valid(curtain) and curtain.get_parent() == get_tree().root:
		curtain.focus_query = Callable()
		curtain.queue_free()
	curtain = null
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
	if detached_session and is_inside_tree(): queue_free()
