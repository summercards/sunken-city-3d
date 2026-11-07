extends RefCounted
## 只拥有瞬态会话；分支结果到达终页后由服务一次提交。
signal page_changed(state: Dictionary)
signal completed(dialogue_id: String)
var _session: Dictionary = {}
var _serial := 0

static func validate_pages(pages: Variant) -> String:
	if not pages is Array or pages.is_empty() or pages.size() > 64: return "对白页数须为1至64"
	var ids := {}
	var choices := {}
	for page in pages:
		if not page is Dictionary: return "对白页须为对象"
		for key in page:
			if key not in ["id", "speaker", "text", "choices", "next"]: return "未知对白字段"
		for key in ["id", "speaker", "text"]:
			if not page.get(key) is String or page[key].strip_edges().is_empty(): return "对白缺少 " + key
		if ids.has(page.id): return "重复页面ID"
		ids[page.id] = true
		if page.has("next") and not page.next is String: return "下一页ID须为字符串"
		if page.has("choices"):
			if not page.choices is Array or page.choices.is_empty(): return "选项须为非空数组"
			for choice in page.choices:
				if not choice is Dictionary: return "选项须为对象"
				for key in choice:
					if key not in ["id", "text", "next", "effects"]: return "未知选项字段"
				for key in ["id", "text", "next"]:
					if not choice.get(key) is String or choice[key].is_empty(): return "无效选项字段"
				if choices.has(choice.id): return "事件内选项ID重复"
				choices[choice.id] = true
	for i in pages.size():
		var page: Dictionary = pages[i]
		var targets: Array = []
		if page.has("choices"):
			for choice in page.choices: targets.append(choice.next)
		else:
			targets.append(page.get("next", pages[i + 1].id if i + 1 < pages.size() else ""))
		for target in targets:
			if target == "": continue
			if not ids.has(target): return "分支引用未知页面"
			var target_index := -1
			for j in pages.size():
				if pages[j].id == target: target_index = j
			if target_index <= i: return "对白分支必须向前，禁止循环"
	var reachable := {pages[0].id: true}
	for i in pages.size():
		var page: Dictionary = pages[i]
		if not reachable.has(page.id): return "存在不可达页面"
		if page.has("choices"):
			for choice in page.choices: reachable[choice.next] = true
		else:
			reachable[page.get("next", pages[i + 1].id if i + 1 < pages.size() else "")] = true
	return ""

func start(dialogue_id: String, pages: Array, replay := false) -> Dictionary:
	if not _session.is_empty(): return {"ok": false, "reason": "已有进行中的对白"}
	var error := validate_pages(pages)
	if dialogue_id.is_empty() or error != "": return {"ok": false, "reason": error if error != "" else "对白ID为空"}
	_serial += 1
	_session = {"id": dialogue_id, "pages": pages.duplicate(true), "index": 0,
		"typing": true, "replay": replay, "choices": {}, "session_id": _serial}
	page_changed.emit(state())
	return {"ok": true, "state": state()}

func state() -> Dictionary:
	if _session.is_empty(): return {"active": false, "phase": "CLOSED", "input_locked": false}
	var page: Dictionary = _session.pages[_session.index].duplicate(true)
	# 对外只给展示字段，结算描述不泄漏成可写端口。
	for choice in page.get("choices", []): choice.erase("effects")
	return {"active": true, "dialogue_id": _session.id, "session_id": _session.session_id,
		"index": _session.index, "total": _session.pages.size(), "page": page,
		"replay": _session.replay, "input_locked": _session.pages.size() > 1,
		"typing": _session.typing, "phase": "TYPING" if _session.typing else ("WAIT_CHOICE" if page.has("choices") else "WAIT_INPUT"),
		"choices": _session.choices.duplicate(true)}

func choose(choice_id: String, session_id := -1) -> Dictionary:
	if _session.is_empty(): return {"ok": false, "reason": "没有进行中的对白"}
	if session_id != -1 and session_id != _session.session_id: return {"ok": false, "reason": "过期会话"}
	# 同会话重复投递不推进第二次；另一会话不会继承这个幂等集合。
	if _session.choices.values().has(choice_id): return {"ok": true, "already": true, "state": state()}
	if _session.typing: return {"ok": false, "reason": "请先补全当前文字"}
	var page: Dictionary = _session.pages[_session.index]
	for choice in page.get("choices", []):
		if choice.id == choice_id:
			_session.choices[page.id] = choice_id
			return _move(choice.next)
	return {"ok": false, "reason": "当前页无此选项"}

func advance(session_id := -1) -> Dictionary:
	if _session.is_empty(): return {"ok": false, "reason": "没有进行中的对白"}
	if session_id != -1 and session_id != _session.session_id: return {"ok": false, "reason": "过期会话"}
	if _session.typing:
		_session.typing = false
		page_changed.emit(state())
		return {"ok": true, "completed": false, "revealed": true, "state": state()}
	var page: Dictionary = _session.pages[_session.index]
	if page.has("choices"): return {"ok": false, "reason": "当前页必须选择"}
	var index := int(_session.index)
	return _move(page.get("next", _session.pages[index + 1].id if index + 1 < _session.pages.size() else ""))

func _move(target: String) -> Dictionary:
	if target.is_empty():
		var result := {"ok": true, "completed": true, "dialogue_id": _session.id,
			"replay": _session.replay, "choices": _session.choices.duplicate(true)}
		var id := str(_session.id)
		cancel()
		completed.emit(id)
		return result
	for i in _session.pages.size():
		if _session.pages[i].id == target:
			_session.index = i
			_session.typing = true
			page_changed.emit(state())
			return {"ok": true, "completed": false, "state": state()}
	return {"ok": false, "reason": "未知分支页面"}

func cancel() -> void:
	_session.clear()
