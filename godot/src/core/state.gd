extends RefCounted
var _machine: WeakRef
var _context: WeakRef
var machine:
	get: return _machine.get_ref() if _machine != null else null
	set(value): _machine = weakref(value) if value != null else null
var context:
	get: return _context.get_ref() if _context != null else null
	set(value): _context = weakref(value) if value != null else null
func enter(_payload: Dictionary) -> void: pass
func exit() -> void: pass
func tick(_delta: float) -> void: pass
func handle(_event: String, _payload: Dictionary) -> bool: return false
