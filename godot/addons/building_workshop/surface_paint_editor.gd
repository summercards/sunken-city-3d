@tool
extends Node
## 表面层拥有独立快照；落笔期间只更新临时派生层，松键才提交一次历史。

signal changed
signal committed(before: Dictionary, after: Dictionary)
const Data = preload("res://addons/building_workshop/surface_paint_data.gd")
const Surface = preload("res://addons/building_workshop/surface_paint_surface.gd")
const Output = preload("res://addons/building_workshop/surface_paint_output.gd")
const PaintInput = preload("res://addons/building_workshop/surface_paint_input.gd")

var screen: Control
var preview: Control
var input: RefCounted
var cache: RefCounted
var brush: Dictionary = Data.brush_defaults()
var textures: Dictionary = {}
var saved_fingerprint := Data.fingerprint(Data.empty_snapshot())
var document_id := ""
var active := false
var armed := false
var _snapshot: Dictionary = Data.empty_snapshot()
var _pending: Dictionary = {}
var _staging: Node3D
var _staged_root: Node3D
var _stroke_id := ""
var _sequence := 0
var _seed := 0
var _previous: Variant = null
var _last_sample_usec := 0
var _timer: Timer
var _paint_button: Button
var _status: Label
var _mode_buttons: Dictionary = {}
var _ranges: Dictionary = {}
var _range_readouts: Dictionary = {}
var _cache_reason := ""

func configure(owner_screen: Control, page: VBoxContainer, view: Control, supplied_textures: Dictionary = {}) -> void:
	screen = owner_screen
	preview = view
	textures = supplied_textures.duplicate()
	cache = Surface.new()
	input = PaintInput.new()
	input.configure(preview, self)
	preview.surface_paint_input = input
	document_id = str(screen.snapshot().get("building_id", ""))
	_timer = Timer.new()
	_timer.wait_time = 1.0 / 30.0
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_build_ui(page)
	set_active(false)

func _build_ui(page: VBoxContainer) -> void:
	page.set_meta("cozy_skip", true)
	var title := Label.new()
	title.text = "表面植被 · 独立作品层"
	page.add_child(title)
	var modes := HFlowContainer.new()
	page.add_child(modes)
	var group := ButtonGroup.new()
	for entry: Array in [["grass", "草地"], ["moss", "苔藓"], ["vine", "藤蔓"], ["erase", "擦除"]]:
		var button := Button.new()
		button.text = entry[1]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = entry[0] == brush.kind
		button.pressed.connect(_set_kind.bind(str(entry[0])))
		modes.add_child(button)
		_mode_buttons[entry[0]] = button
	for entry: Array in [["radius", "球半径（米）", 0.01], ["density", "密度（印记/平方米）", 1.0], ["spacing", "采样间距（米）", 0.01], ["rate", "强度（每秒采样上限）", 1.0]]:
		var key: String = entry[0]
		var bounds: Array = Data.PARAM_BOUNDS[key]
		var label := Label.new()
		page.add_child(label)
		var slider := HSlider.new()
		slider.name = "SurfacePaint_" + key
		slider.min_value = bounds[0]
		slider.max_value = bounds[1]
		slider.step = entry[2]
		slider.value = brush[key]
		slider.allow_greater = false
		slider.allow_lesser = false
		var readout := func(value: float) -> void:
			label.text = "%s %.2f [%.2f..%.2f]" % [entry[1], value, bounds[0], bounds[1]]
			slider.tooltip_text = label.text
		_range_readouts[key] = readout
		var update := func(value: float) -> void:
			cancel_stroke()
			brush[key] = clampf(value, float(bounds[0]), float(bounds[1]))
			readout.call(brush[key])
			input.refresh_ghost()
		slider.value_changed.connect(update)
		readout.call(brush[key])
		page.add_child(slider)
		_ranges[key] = slider
	_paint_button = Button.new()
	_paint_button.text = "开始刷涂"
	_paint_button.toggle_mode = true
	_paint_button.toggled.connect(set_armed)
	page.add_child(_paint_button)
	var pending_actions := HBoxContainer.new()
	page.add_child(pending_actions)
	var accept := Button.new()
	accept.text = "提交暂停笔划"
	accept.pressed.connect(finish_stroke)
	pending_actions.add_child(accept)
	var discard := Button.new()
	discard.text = "取消本笔"
	discard.pressed.connect(cancel_stroke)
	pending_actions.add_child(discard)
	var history := HBoxContainer.new()
	page.add_child(history)
	for redo: bool in [false, true]:
		var button := Button.new()
		button.text = "重做" if redo else "撤销"
		button.pressed.connect(func() -> void: screen._undo(redo))
		history.add_child(button)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_status)
	report("点「开始刷涂」后左键点击/拖动；Shift、右键或 Esc 取消本笔。中/右键导航保留。草仅刷上朝面；擦除使用相同球采样。")

func _set_kind(kind: String) -> void:
	cancel_stroke()
	brush.kind = kind
	for key: String in _mode_buttons:
		_mode_buttons[key].set_pressed_no_signal(key == kind)
	input.refresh_ghost()
	changed.emit()

func set_armed(value: bool) -> void:
	if value and not _pending.is_empty():
		_paint_button.set_pressed_no_signal(false)
		report("请先提交暂停笔划或取消本笔，再开始刷涂。")
		return
	cancel_stroke()
	armed = value and active
	_paint_button.set_pressed_no_signal(armed)
	_paint_button.text = "停止刷涂" if armed else "开始刷涂"
	input.refresh_ghost()
	changed.emit()

func set_active(value: bool) -> void:
	var activated := value and not active
	active = value
	if not active: pause()
	elif activated and _pending.is_empty(): house_rebuilt()

func pause() -> void:
	if _timer != null: _timer.stop()
	armed = false
	if _paint_button != null:
		_paint_button.set_pressed_no_signal(false)
		_paint_button.text = "开始刷涂"
	if input != null:
		input._left_owned = false
		input.hide_ghost()
	if is_instance_valid(_staging): _staging.hide()
	if is_instance_valid(preview):
		var layer: Node3D = preview.get_surface_paint_root()
		if is_instance_valid(layer): layer.visible = _cache_reason.is_empty()
	if not _pending.is_empty(): report("笔划已暂停、未写作品；返回后可提交暂停笔划或取消本笔。")

func report(text: String) -> void:
	if _status != null: _status.text = text

func get_surface_paint_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)

func has_unsaved() -> bool:
	return not _pending.is_empty() or Data.fingerprint(_snapshot) != saved_fingerprint

func recovery() -> Dictionary:
	return {"surface_paint_snapshot": get_surface_paint_snapshot(), "surface_paint_saved_fingerprint": saved_fingerprint,
		"surface_paint_document": document_id, "surface_paint_brush": brush.duplicate(true), "surface_paint_pending": _pending.duplicate(true)}

func restore_context(value: Dictionary, prepared_pending: Dictionary = {}) -> void:
	brush = value.get("surface_paint_brush", Data.brush_defaults()).duplicate(true)
	for key: String in _ranges:
		_ranges[key].set_value_no_signal(brush[key])
		_range_readouts[key].call(brush[key])
	for kind: String in _mode_buttons: _mode_buttons[kind].set_pressed_no_signal(kind == brush.kind)
	if not prepared_pending.is_empty():
		_pending = prepared_pending.snapshot.duplicate(true)
		_staging = Node3D.new()
		_staging.name = "SurfacePaintPending"
		preview.get_temporary_root().add_child(_staging)
		_staging.global_transform = preview.get_building_root().global_transform
		_staged_root = prepared_pending.root
		_staging.add_child(_staged_root)
	pause()
	changed.emit()

func get_context() -> Dictionary:
	return {"snapshot": get_surface_paint_snapshot(), "saved_fingerprint": saved_fingerprint,
		"document": document_id, "brush": brush.duplicate(true), "pending": not _pending.is_empty(),
		"active": active, "armed": armed, "timer_running": _timer != null and not _timer.is_stopped(), "reason": _cache_reason}

func save_block_reason() -> String:
	if not _pending.is_empty(): return "表面植被仍在落笔，请先松开左键或取消本笔。"
	var reason := Data.validate(_snapshot)
	if not reason.is_empty(): return reason
	var built: Dictionary = prepare(_snapshot, preview.get_building_root())
	if built.get("ok", false): built.root.free()
	return str(built.get("reason", ""))

func prepare(value: Variant, host: Node3D) -> Dictionary:
	if not value is Dictionary: return {"ok": false, "reason": "表面植被快照必须为对象"}
	return Output.build_from_snapshot(value, host, textures, {}, cache)

func commit(prepared: Dictionary, saved: bool = true, baseline: String = "") -> void:
	set_armed(false)
	_snapshot = prepared.snapshot.duplicate(true)
	preview.replace_surface_paint_root(prepared.root)
	document_id = str(screen.snapshot().get("building_id", ""))
	if not baseline.is_empty(): saved_fingerprint = baseline
	elif saved: saved_fingerprint = Data.fingerprint(_snapshot)
	else: saved_fingerprint = Data.fingerprint(Data.empty_snapshot())
	house_rebuilt()
	changed.emit()

func reset() -> Dictionary:
	var prepared: Dictionary = prepare(Data.empty_snapshot(), preview.get_building_root())
	if prepared.get("ok", false): commit(prepared)
	return prepared

func mark_saved() -> void:
	saved_fingerprint = Data.fingerprint(_snapshot)
	document_id = str(screen.snapshot().get("building_id", ""))
	changed.emit()

func house_rebuilt() -> void:
	cancel_stroke()
	input.hide_ghost()
	cache.invalidate_cache()
	var result: Dictionary = cache.build_cache(preview.get_building_root())
	_cache_reason = str(result.get("reason", ""))
	if result.get("ok", false): _cache_reason = cache.validate_snapshot_surface(_snapshot)
	preview.sync_surface_paint_host()
	var layer: Node3D = preview.get_surface_paint_root()
	if is_instance_valid(layer): layer.visible = _cache_reason.is_empty()
	if not _cache_reason.is_empty(): report("表面层保留但不可刷/保存：" + _cache_reason)

func probe(ray: Dictionary) -> Dictionary:
	if not _cache_reason.is_empty(): return {"ok": false, "reason": _cache_reason}
	# 核心无 hover 端口：对空快照执行擦除探测，不落印记、不改作品或消耗序号。
	var probe_brush := brush.duplicate(true)
	probe_brush.kind = "erase"
	var result: Dictionary = cache.apply_brush_command(Data.empty_snapshot(), {"brush": probe_brush,
		"origin": ray.origin, "direction": ray.direction, "stroke_id": "hover", "sequence": 0, "seed": 0, "elapsed": 0.0})
	if result.get("ok", false) and brush.kind == "grass" and (result.normal_world as Vector3).y < 0.7:
		result.ok = false
		result.reason = "草只允许世界向上 dot>=0.7 的真实面"
	return result

func begin_stroke(position: Vector2) -> void:
	if not active or not armed or not _pending.is_empty(): return
	_pending = _snapshot.duplicate(true)
	_stroke_id = "brush_%d_%d" % [Time.get_ticks_usec(), get_instance_id()]
	_sequence = 0
	_seed = int(Time.get_ticks_usec() % 2147483648)
	_previous = null
	_last_sample_usec = Time.get_ticks_usec()
	_sample(position)
	_timer.start()
	changed.emit()

func _tick() -> void:
	if not active or not armed or not preview.is_visible_in_tree():
		pause()
		return
	if Input.is_key_pressed(KEY_SHIFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		set_armed(false)
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		# 视口外松键不能提交最后一次旧落点。
		cancel_stroke()
		return
	if input.pointer_inside: _sample(input.pointer_position)

func _sample(position: Vector2) -> void:
	var hit: Dictionary = input.update_ghost(position)
	if not hit.get("ok", false):
		_previous = null
		report(str(hit.get("reason", "拒绝落点")))
		return
	var ray: Dictionary = preview.ray_from_local_position(position)
	var command := {"brush": brush.duplicate(true), "origin": ray.origin, "direction": ray.direction,
		"stroke_id": _stroke_id, "sequence": _sequence, "seed": _seed,
		"elapsed": minf(3600.0, float(Time.get_ticks_usec() - _last_sample_usec) / 1000000.0)}
	if _previous is Vector3: command.previous_world = _previous
	var result: Dictionary = cache.apply_brush_command(_pending, command)
	if not result.get("ok", false):
		report(str(result.get("reason", "采样被拒绝")))
		return
	if not result.get("changed", false): return
	var built: Dictionary = prepare(result.snapshot, preview.get_building_root())
	if not built.get("ok", false):
		report(str(built.get("reason", "派生输出失败；采样未提交")))
		return
	if is_instance_valid(_staging): _staging.free()
	_staging = Node3D.new()
	_staging.name = "SurfacePaintPending"
	preview.get_temporary_root().add_child(_staging)
	_staging.global_transform = preview.get_building_root().global_transform
	_staged_root = built.root
	_staging.add_child(_staged_root)
	var layer: Node3D = preview.get_surface_paint_root()
	if is_instance_valid(layer): layer.hide()
	_pending = result.snapshot.duplicate(true)
	_previous = result.center_world
	_last_sample_usec = Time.get_ticks_usec()
	_sequence += 1
	report("本笔待提交 · 印记 %d；松开左键提交一次历史，Shift/右键取消。" % _pending.stamps.size())

func finish_stroke() -> void:
	_timer.stop()
	if _pending.is_empty(): return
	if _pending != _snapshot and is_instance_valid(_staged_root):
		var before := _snapshot.duplicate(true)
		_snapshot = _pending.duplicate(true)
		_staging.remove_child(_staged_root)
		preview.replace_surface_paint_root(_staged_root)
		_staged_root = null
		committed.emit(before, get_surface_paint_snapshot())
	cancel_stroke()
	report("表面植被 %d 个印记；尚未保存。" % _snapshot.stamps.size())

func cancel_stroke() -> void:
	if _timer != null: _timer.stop()
	_pending.clear()
	_previous = null
	if is_instance_valid(_staging): _staging.free()
	_staging = null
	_staged_root = null
	if is_instance_valid(preview):
		var layer: Node3D = preview.get_surface_paint_root()
		if is_instance_valid(layer): layer.visible = _cache_reason.is_empty()
	changed.emit()

func replay(value: Dictionary) -> bool:
	set_armed(false)
	var built: Dictionary = prepare(value, preview.get_building_root())
	if not built.get("ok", false):
		report(str(built.get("reason", "撤销/重做失败，当前层保持")))
		return false
	_snapshot = value.duplicate(true)
	preview.replace_surface_paint_root(built.root)
	house_rebuilt()
	changed.emit()
	return true

func _exit_tree() -> void:
	cancel_stroke()
	if input != null: input.dispose()
	if is_instance_valid(preview): preview.surface_paint_input = null
