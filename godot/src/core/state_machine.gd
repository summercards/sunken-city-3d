extends RefCounted
## Synchronous finite state machine. One owner, explicit edges, exit before enter.
signal transitioned(previous: String, current: String)
var states: Dictionary = {}
var edges: Dictionary = {}
var current := ""
var _context: WeakRef
var context:
	get: return _context.get_ref() if _context != null else null
	set(value): _context = weakref(value) if value != null else null
var _changing := false
var _pending: Array = []

func configure(owner, nodes: Dictionary, transitions: Dictionary, initial: String) -> void:
	assert(nodes.has(initial))
	context = owner
	states = nodes
	edges = transitions
	for state in states.values():
		state.machine = self
		state.context = context
	change(initial, {}, true)

func change(next: String, payload: Dictionary = {}, force := false) -> bool:
	if not states.has(next): return false
	if current == next and not force: return true
	if not force and current != "" and not next in edges.get(current, []): return false
	if _changing:
		_pending.append([next, payload.duplicate(), force])
		return true
	_pending.append([next, payload.duplicate(), force])
	_changing = true
	var budget := 16
	while not _pending.is_empty() and budget > 0:
		var request: Array = _pending.pop_front()
		budget -= 1
		if not request[2] and current != "" and request[0] != current and not request[0] in edges.get(current, []): continue
		if request[0] == current and not request[2]: continue
		var previous := current
		if states.has(previous): states[previous].exit()
		current = request[0]
		states[current].enter(request[1])
		transitioned.emit(previous, current)
	_pending.clear()
	_changing = false
	return true

func tick(delta: float) -> void:
	if is_finite(delta) and delta >= 0.0 and states.has(current): states[current].tick(delta)

func handle(event: String, payload: Dictionary = {}) -> bool:
	return bool(states[current].handle(event, payload)) if states.has(current) else false
