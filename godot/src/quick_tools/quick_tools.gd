extends Node
## 快捷工具只拥有临时菜单编排；资格、场景和命令均由注入查询/回调提供。

var menu
var context_query: Callable
var execute: Callable
var notify: Callable
var _context := ""
var _opened_by_quick := false
var _session := 0

const OPTIONS := {
	"land": [
		{"id":"build", "label":"建造", "caption":"建造", "icon":"quick_build"},
		{"id":"demolish", "label":"拆除", "caption":"拆除", "icon":"quick_demolish"},
	],
	"boat": [
		{"id":"fish", "label":"钓鱼", "caption":"钓鱼", "icon":"quick_fish"},
		{"id":"dive", "label":"潜水", "caption":"潜水", "icon":"quick_dive"},
	],
}

func query() -> Dictionary:
	if not context_query.is_valid():
		return {"context":"", "blocked":true, "anchor":Vector2.INF}
	var value: Variant = context_query.call()
	return value if value is Dictionary else {"context":"", "blocked":true, "anchor":Vector2.INF}

func toggle() -> bool:
	if is_open():
		close()
		return false
	var snapshot := query()
	if not _usable(snapshot):
		return false
	_session += 1
	_context = str(snapshot.get("context", ""))
	var entries: Array = []
	for source in OPTIONS[_context]:
		entries.append(_make_option(source))
	if menu == null or not menu.has_method("open"):
		return false
	var anchor_query := func() -> Vector2:
		var current := query()
		var point: Variant = current.get("anchor", Vector2.INF)
		return point if point is Vector2 else Vector2.INF
	menu.open(anchor_query, entries, "", Vector2.INF, "quick")
	_opened_by_quick = true
	return true

func _make_option(source: Dictionary) -> Dictionary:
	var option: Dictionary = source.duplicate(true)
	var action_id := str(option.get("id", ""))
	var token := _session
	option["command"] = func(): _execute_checked(action_id, token)
	return option

func is_open() -> bool:
	return _opened_by_quick and menu != null and menu.presentation == "quick" and menu.is_open()

func close(immediate := false) -> void:
	_session += 1
	if menu != null and _opened_by_quick and menu.presentation == "quick":
		menu.close(immediate)
	_opened_by_quick = false
	_context = ""

func _usable(snapshot: Dictionary) -> bool:
	var context := str(snapshot.get("context", ""))
	var anchor: Variant = snapshot.get("anchor", Vector2.INF)
	return context in OPTIONS and not bool(snapshot.get("blocked", false)) and anchor is Vector2 and (anchor as Vector2).is_finite()

func _execute_checked(action_id: String, token: int) -> void:
	# 必须仍是可选中的本会话；取消退场或被新菜单替代的回调无权关新界面。
	if token != _session or not is_open() or not menu.active: return
	# 先撤掉 modal，再重新取一次上下文，避免潜水/切换命令被旧菜单遮挡或过期执行。
	var expected_context := _context
	close(true)
	var snapshot := query()
	if not _usable(snapshot) or str(snapshot.get("context", "")) != expected_context:
		_context = ""
		return
	var command := execute
	if command.is_valid():
		command.call(action_id)
	_context = ""

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		close(true)

func _process(_delta: float) -> void:
	if not is_open():
		return
	var snapshot := query()
	if not _usable(snapshot) or str(snapshot.get("context", "")) != _context:
		close(true)
