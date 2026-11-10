extends Node
class_name WorkshopHost
## SEA-WORKSHOP 生命周期适配器：只负责面板、暂停和模态端口，不拥有业务状态。

const PanelScript = preload("res://src/workshop/panel.gd")

var panel
var _ports: Dictionary = {}
var _previous_modal_query: Callable
var _previous_modal_close: Callable
var _previous_modal_input: Callable
var _previous_modal_camera_query: Callable

func _ready() -> void:
	panel = PanelScript.new()
	panel.name = "WorkshopPanel"
	add_child(panel)
	panel.closed.connect(_on_panel_closed)
	panel.opened.connect(_on_panel_opened)

func configure(ports: Dictionary = {}) -> void:
	_ports = ports.duplicate()
	if panel == null:
		return
	var parent_port: Variant = ports.get("parentNode", ports.get("parent_node", null))
	if parent_port is Node and panel.get_parent() != parent_port:
		var parent_node: Node = parent_port
		panel.reparent(parent_node)
	panel.configure(ports)
	if ports.has("hud") and ports["hud"] != null:
		_bind_hud(ports["hud"])

func open() -> Dictionary:
	if is_open():
		return {"ok": true, "reason": "", "already_open": true}
	var gate := _can_open()
	if not gate.get("ok", false):
		return gate
	if _ports.has("before_open") and _ports["before_open"] is Callable and _ports["before_open"].is_valid():
		_ports["before_open"].call()
	panel.open()
	return {"ok": true, "reason": ""}

func request_close() -> void:
	if panel != null:
		panel.request_close()

func close_now() -> void:
	if panel != null:
		panel.close_now()

func is_open() -> bool:
	return panel != null and panel.is_open()

func handle_input(event: InputEvent) -> bool:
	return panel != null and panel.handle_input(event)

func dispose() -> void:
	if panel != null:
		panel.close_now()
		panel.queue_free()
		panel = null
	_ports.clear()

func _can_open() -> Dictionary:
	if not _ports.has("can_open"):
		return {"ok": true, "reason": ""}
	var result: Variant = _ports["can_open"].call() if _ports["can_open"] is Callable else true
	if result is Dictionary:
		var gate: Dictionary = result.duplicate()
		gate["ok"] = bool(gate.get("ok", gate.get("allowed", false)))
		gate["reason"] = str(gate.get("reason", ""))
		return gate
	if result is String:
		return {"ok": result.is_empty(), "reason": result}
	return {"ok": bool(result), "reason": "" if bool(result) else "当前状态不允许打开楼房工坊"}

func _bind_hud(owner_hud: Node) -> void:
	if not ("owned_modal_query" in owner_hud):
		return
	_previous_modal_query = owner_hud.owned_modal_query
	_previous_modal_close = owner_hud.owned_modal_close
	_previous_modal_input = owner_hud.owned_modal_input
	_previous_modal_camera_query = owner_hud.owned_modal_camera_query
	owner_hud.owned_modal_query = Callable(self, "_owned_modal_query")
	owner_hud.owned_modal_close = Callable(self, "_owned_modal_close")
	owner_hud.owned_modal_input = Callable(self, "_owned_modal_input")
	owner_hud.owned_modal_camera_query = Callable(self, "_owned_modal_camera_query")

func _owned_modal_query() -> bool:
	return is_open() or (_previous_modal_query.is_valid() and _previous_modal_query.call())

func _owned_modal_close() -> void:
	if is_open():
		request_close()
	elif _previous_modal_close.is_valid():
		_previous_modal_close.call()

func _owned_modal_input(event: InputEvent) -> bool:
	if is_open():
		return handle_input(event)
	return _previous_modal_input.is_valid() and _previous_modal_input.call(event)

func _owned_modal_camera_query() -> bool:
	return is_open() or (_previous_modal_camera_query.is_valid() and _previous_modal_camera_query.call())

func _on_panel_opened() -> void:
	var owner_hud: Node = _ports.get("hud")
	if owner_hud != null and owner_hud.has_method("set_external_modal"):
		owner_hud.set_external_modal(true, false)

func _on_panel_closed() -> void:
	var owner_hud: Node = _ports.get("hud")
	if owner_hud != null and owner_hud.has_method("set_external_modal"):
		owner_hud.set_external_modal(_previous_modal_query.is_valid() and _previous_modal_query.call(), false)
	if _ports.has("after_close") and _ports["after_close"] is Callable and _ports["after_close"].is_valid():
		_ports["after_close"].call()
