extends RefCounted
## Water occupancy for world placement and scatter.
const BLOCK_INDEX_CELL := 6.0
var _block_index: Dictionary = {}
var shape_query: Callable
var allowed_area := Rect2()
func _water_shapes() -> Array: return shape_query.call()
func invalidate() -> void:
	_block_index.clear()

func is_open_water(x: float, z: float) -> bool:
	if allowed_area.has_area() and not allowed_area.has_point(Vector2(x,z)): return false
	return is_geometric_water(x,z)

func is_geometric_water(x: float, z: float) -> bool:
	if not is_finite(x) or not is_finite(z):
		return false
	if _block_index.is_empty():
		_build_block_index()
	var bucket: Array = _block_index.get(_block_key(x, z), [])
	for s: Dictionary in bucket:
		var cx := float(s.get("x", 0.0))
		var cz := float(s.get("z", 0.0))
		var hx := float(s.get("hx", 0.0)) + 0.9
		if bool(s.get("round", false)):
			var dx := x - cx
			var dz := z - cz
			if dx * dx + dz * dz <= hx * hx:
				return false
		else:
			var hz := float(s.get("hz", hx)) + 0.9
			if absf(x - cx) <= hx and absf(z - cz) <= hz:
				return false
	return true

func _block_key(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / BLOCK_INDEX_CELL)), int(floor(z / BLOCK_INDEX_CELL)))

func _build_block_index() -> void:
	_block_index.clear()
	for s: Dictionary in _water_shapes():
		var cx := float(s.get("x", 0.0))
		var cz := float(s.get("z", 0.0))
		var hx := float(s.get("hx", 0.0)) + 0.9
		var hz := float(s.get("hz", hx)) + 0.9
		var i0 := int(floor((cx - hx) / BLOCK_INDEX_CELL))
		var i1 := int(floor((cx + hx) / BLOCK_INDEX_CELL))
		var j0 := int(floor((cz - hz) / BLOCK_INDEX_CELL))
		var j1 := int(floor((cz + hz) / BLOCK_INDEX_CELL))
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var key := Vector2i(i, j)
				if not _block_index.has(key):
					_block_index[key] = []
				(_block_index[key] as Array).append(s)
