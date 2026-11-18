@tool
extends RefCounted
## 独立 surface_paint JSON；局部位置/法线/朝向以宿主为坐标系，世界中心仅记录落笔现场。
## layer_transform 也是宿主局部变换；不消费房屋或外挂 Recipe，不从快照加载外部路径。

const META := "surface_paint"
const MAX_STAMPS := 4096
const MAX_JSON_BYTES := 8 * 1024 * 1024
const MAX_PATH_POINTS := 32
const SOURCES := {"grass": "grass_soft", "moss": "moss_atlas", "vine": "vine_atlas"}
const PARAM_BOUNDS := {
	"radius": [0.05, 2.5, 0.35], "spacing": [0.01, 1.0, 0.08],
	"rate": [1.0, 60.0, 20.0], "density": [1.0, 256.0, 64.0],
	"size": [0.02, 1.0, 0.18], "offset": [0.001, 0.01, 0.002],
}

static func empty_snapshot() -> Dictionary:
	return {"schema_version": 1, "type": META, "coordinate_space": "host_local",
		"layer_transform": encode_transform(Transform3D.IDENTITY), "stamps": []}

static func brush_defaults(kind: String = "grass") -> Dictionary:
	var result := {"kind": kind}
	for key: String in PARAM_BOUNDS: result[key] = PARAM_BOUNDS[key][2]
	return result

static func validate_brush(value: Dictionary) -> String:
	if value.size() != PARAM_BOUNDS.size() + 1 or not value.has("kind"):
		return "笔刷字段不完整或未知"
	if not value.kind is String or value.kind not in ["grass", "moss", "vine", "erase"]:
		return "笔刷只支持 grass/moss/vine/erase"
	for key: String in PARAM_BOUNDS:
		if not value.has(key) or not bounded(value[key], PARAM_BOUNDS[key][0], PARAM_BOUNDS[key][1]):
			return "笔刷参数越界或非有限：" + key
	return ""

static func capture(layer: Node3D) -> Dictionary:
	if not is_instance_valid(layer): return empty_snapshot()
	if not _static_tree(layer) or not layer.has_meta(META):
		return {"capture_error": "只捕获带独立快照的无脚本本地 SurfacePaint 层"}
	var value: Variant = layer.get_meta(META)
	if not value is Dictionary: return {"capture_error": "surface_paint 元数据不是对象"}
	var result: Dictionary = value.duplicate(true)
	# 渲染节点是派生结果，不反推逐实例姿态；编辑必须先更新独立快照。
	if result.get("layer_transform") != encode_transform(layer.transform):
		return {"capture_error": "表面层变换已在快照外改变，请通过独立快照显式编辑"}
	var reason := validate(result)
	return result if reason.is_empty() else {"capture_error": reason}

static func validate(snapshot: Dictionary) -> String:
	if snapshot.has("capture_error"): return str(snapshot.capture_error)
	if not exact_keys(snapshot, ["schema_version", "type", "coordinate_space", "layer_transform", "stamps"]):
		return "表面快照字段不完整或未知"
	if not integer(snapshot.schema_version, 1, 1) or snapshot.type != META or snapshot.coordinate_space != "host_local":
		return "表面快照只支持 surface_paint v1 / host_local"
	if not valid_transform_array(snapshot.layer_transform): return "表面层变换非有限、镜像或奇异"
	if not snapshot.stamps is Array or snapshot.stamps.size() > MAX_STAMPS:
		return "表面印记必须为数组且不超过4096"
	var ids := {}
	for raw: Variant in snapshot.stamps:
		if not raw is Dictionary: return "印记必须为对象"
		var reason := _stamp_reason(raw)
		if not reason.is_empty(): return reason
		if ids.has(raw.id): return "重复印记 ID：" + raw.id
		ids[raw.id] = true
	if JSON.stringify(snapshot).to_utf8_buffer().size() > MAX_JSON_BYTES: return "表面快照超过8MiB"
	return ""

static func _stamp_reason(stamp: Dictionary) -> String:
	var required := ["id", "kind", "source", "center_world", "center_local", "normal", "orientation",
		"scale", "seed", "params", "mesh_fingerprint", "mesh_path", "surface", "triangle", "path_points"]
	if not stamp.has_all(required) or stamp.size() < required.size() or stamp.size() > required.size() + 1:
		return "印记字段不完整或未知"
	for key: Variant in stamp:
		if not key is String or (key not in required and key != "condition"): return "印记含未知字段"
	if not safe_id(stamp.id): return "印记 ID 必须为1..128位安全 ASCII"
	if not stamp.kind is String or not SOURCES.has(stamp.kind) or stamp.source != SOURCES[stamp.kind]:
		return "印记源不是内置白名单键"
	if stamp.has("condition") and stamp.condition not in ["fresh", "damaged", "ruined"]: return "印记状态不支持"
	for key: String in ["center_world", "center_local", "normal", "scale"]:
		if not finite_array(stamp[key], 3): return "印记向量非有限或不是3项：" + key
	if vec(stamp.center_world).length() > 1000000.0 or vec(stamp.center_local).length() > 1000000.0:
		return "印记中心超过米制范围"
	if absf(vec(stamp.normal).length_squared() - 1.0) > 0.00001: return "印记法线必须为单位向量"
	for component: Variant in stamp.scale:
		if not bounded(component, 0.01, 4.0): return "印记缩放必须为0.01..4"
	if not finite_array(stamp.orientation, 4): return "朝向必须为4项有限四元数"
	var rotation := quat(stamp.orientation)
	if absf(rotation.length_squared() - 1.0) > 0.00001: return "朝向四元数必须归一化"
	if (Basis(rotation).y - vec(stamp.normal)).length() > 0.0001: return "朝向 +Y 必须与宿主局部法线一致"
	if not integer(stamp.seed, 0, 2147483647): return "印记 seed 必须为31位非负整数"
	if not stamp.params is Dictionary or not exact_keys(stamp.params, PARAM_BOUNDS.keys()): return "印记 params 字段不完整"
	for key: String in PARAM_BOUNDS:
		if not bounded(stamp.params[key], PARAM_BOUNDS[key][0], PARAM_BOUNDS[key][1]): return "印记参数越界：" + key
	if not digest(stamp.mesh_fingerprint): return "网格指纹必须为 SHA256"
	if not relative_mesh_path(stamp.mesh_path): return "网格路径必须为 GeneratedVisual 下的相对定位说明，不允许外部路径"
	if not integer(stamp.surface, 0, 255) or not integer(stamp.triangle, 0, 131071): return "表面/三角索引越界"
	if not stamp.path_points is Array or stamp.path_points.size() > MAX_PATH_POINTS: return "藤路径超过32点"
	if stamp.kind == "vine":
		if stamp.path_points.size() < 2: return "藤路径至少2点"
		for index: int in stamp.path_points.size():
			var point: Variant = stamp.path_points[index]
			if not finite_array(point, 3) or vec(point).distance_to(vec(stamp.center_local)) > 5.0: return "藤路径非有限或超局部预算"
			if index > 0 and vec(point).distance_to(vec(stamp.path_points[index - 1])) < 0.00001: return "藤路径含重复点"
	elif not stamp.path_points.is_empty(): return "非藤印记不能携带路径"
	return ""

static func serialize(snapshot: Dictionary) -> Dictionary:
	var reason := validate(snapshot)
	return {"ok": reason.is_empty(), "reason": reason, "json": canonical(snapshot) if reason.is_empty() else ""}

static func deserialize(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_JSON_BYTES: return {"ok": false, "reason": "表面 JSON 超过8MiB"}
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary: return {"ok": false, "reason": "表面 JSON 不是合法对象"}
	var reason := validate(parser.data)
	return {"ok": reason.is_empty(), "reason": reason, "snapshot": parser.data if reason.is_empty() else {}}

static func fingerprint(snapshot: Dictionary) -> String:
	return canonical(snapshot).sha256_text() if validate(snapshot).is_empty() else ""

static func canonical(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var parts: Array[String] = []
		for key: String in keys: parts.append(JSON.stringify(key) + ":" + canonical(value[key]))
		return "{" + ",".join(parts) + "}"
	if value is Array:
		var parts: Array[String] = []
		for item: Variant in value: parts.append(canonical(item))
		return "[" + ",".join(parts) + "]"
	if value is int or value is float:
		var text := "%.9f" % float(value)
		return "0" if float(text) == 0.0 else text
	return JSON.stringify(value)

static func finite_array(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count: return false
	for item: Variant in value:
		if not number(item): return false
	return true

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func bounded(value: Variant, low: float, high: float) -> bool:
	return number(value) and float(value) >= low and float(value) <= high

static func integer(value: Variant, low: int, high: int) -> bool:
	return bounded(value, low, high) and float(value) == floor(float(value))

static func exact_keys(value: Dictionary, keys: Array) -> bool:
	return value.size() == keys.size() and value.has_all(keys)

static func safe_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 128: return false
	for character: String in value:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".contains(character): return false
	return true

static func digest(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for character: String in value:
		if not "0123456789abcdef".contains(character): return false
	return true

static func relative_mesh_path(value: Variant) -> bool:
	if not value is String or value.length() > 512 or not value.begins_with("GeneratedVisual/"): return false
	for part: String in value.split("/"):
		if part.is_empty() or part in [".", ".."]: return false
		for character: String in part:
			if character in [":", "\\", "@", "%"] or character.unicode_at(0) < 32: return false
	return true

static func vec(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func array_vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func quat(value: Array) -> Quaternion:
	return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3]))

static func encode_transform(value: Transform3D) -> Array:
	return [value.basis.x.x, value.basis.x.y, value.basis.x.z,
		value.basis.y.x, value.basis.y.y, value.basis.y.z,
		value.basis.z.x, value.basis.z.y, value.basis.z.z,
		value.origin.x, value.origin.y, value.origin.z]

static func decode_transform(value: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(value[0], value[1], value[2]), Vector3(value[3], value[4], value[5]),
		Vector3(value[6], value[7], value[8])), Vector3(value[9], value[10], value[11]))

static func valid_transform_array(value: Variant) -> bool:
	return finite_array(value, 12) and valid_transform(decode_transform(value))

static func valid_transform(value: Transform3D) -> bool:
	var determinant := value.basis.determinant()
	return value.is_finite() and is_finite(determinant) and determinant > 0.000000001 and determinant < 1000000000.0

static func _static_tree(node: Node) -> bool:
	if node.get_script() != null or not node.scene_file_path.is_empty(): return false
	if not (node is Node3D) or (node.get_class() not in ["Node3D", "MultiMeshInstance3D", "MeshInstance3D"]): return false
	for child: Node in node.get_children():
		if not _static_tree(child): return false
	return true
