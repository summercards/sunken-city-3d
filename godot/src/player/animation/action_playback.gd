extends RefCounted
## Presentation-only one-shot clock. It owns no actor mode or gameplay state.
## Tokens distinguish repeated requests; capture() never exposes writable state.
var _active: Dictionary = {}
var _next_token := 1

func start(action_id: String, duration: float) -> Dictionary:
	if action_id.is_empty() or not is_finite(duration) or duration <= 0.0:
		return {}
	var previous := capture()
	var token := _next_token
	_next_token += 1
	_active = {"id":action_id,"token":token,"duration":duration,"elapsed":0.0}
	return {"token":token,"replaced":previous}

func advance(delta: float) -> Dictionary:
	if _active.is_empty() or not is_finite(delta) or delta < 0.0:
		return {}
	_active.elapsed = minf(float(_active.duration), float(_active.elapsed) + delta)
	if float(_active.elapsed) + 0.0000001 < float(_active.duration):
		return {}
	var completed := capture()
	_active = {}
	return completed

func cancel() -> Dictionary:
	var previous := capture()
	_active = {}
	return previous

func active() -> bool: return not _active.is_empty()
func remaining() -> float:
	return maxf(0.0, float(_active.duration) - float(_active.elapsed)) if active() else 0.0
func progress() -> float:
	return clampf(float(_active.elapsed) / float(_active.duration), 0.0, 1.0) if active() else 0.0
func capture() -> Dictionary:
	if not active(): return {}
	var result := _active.duplicate(true)
	result.remaining = remaining()
	result.progress = progress()
	return result
