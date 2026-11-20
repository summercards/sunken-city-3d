@tool
extends RefCounted
## 作品外挂只保存配方、安装说明与当前局部姿态，不信任旁车中的场景路径。

const Recipe = preload("res://src/building_attachments/recipe.gd")
const Generator = preload("res://src/building_attachments/generator.gd")
const META := "sea_attachment"
const CANONICAL_META := "sea_attachment_canonical"
const MAX_INSTANCES := 256
const MAX_JSON_BYTES := 8 * 1024 * 1024

static func empty_snapshot() -> Dictionary:
	return {"schema_version": 1, "layer_transform": _encode_transform(Transform3D.IDENTITY), "instances": []}

static func capture(layer: Node3D) -> Dictionary:
	if layer == null: return empty_snapshot()
	if layer.get_script() != null or not layer.scene_file_path.is_empty():
		return {"capture_error": "外挂层必须为无脚本本地节点"}
	var snapshot := empty_snapshot()
	snapshot.layer_transform = _encode_transform(layer.transform)
	for node: Node in layer.get_children():
		if not node is Node3D or not node.has_meta(META) or not _static_tree(node):
			return {"capture_error": "外挂层含非外挂节点、外链或运行脚本"}
		var metadata: Variant = node.get_meta(META)
		var canonical_meta: Variant = node.get_meta(CANONICAL_META, "")
		if not metadata is Dictionary: return {"capture_error": "外挂元数据不是对象"}
		# 静态TSCN会把普通metadata中的浮点写成real_t精度。若当前
		# metadata仍与原始canonical副本相同，优先读取canonical副本；若
		# 用户/编辑器显式改过metadata，则保留当前值并重新canonicalize，
		# 不能用旧副本吞掉真实metadata修改。
		var current_canonical := _canonical(metadata)
		if canonical_meta is String and not canonical_meta.is_empty():
			var parser := JSON.new()
			if parser.parse(canonical_meta) == OK and parser.data is Dictionary and _native_metadata_equal(metadata, parser.data):
				# 只把TSCN real_t回读造成的机器精度漂移还原为JSON权威值；
				# 显式metadata改动必须保留，不能被旧canonical副本吞掉。
				metadata = parser.data
		metadata = metadata.duplicate(true)
		node.set_meta(CANONICAL_META, _canonical(metadata))
		# 现场元数据先规范化到1e-9十进制定点，避免Node3D float32
		# 重载后的说明字段漂移；这不是对Transform3D的相对容差放宽。
		var metadata_parser := JSON.new()
		if metadata_parser.parse(_canonical(metadata)) == OK and metadata_parser.data is Dictionary:
			metadata = metadata_parser.data
		# 旧独立场景的宿主提示只是说明文字，绝不用于查找或构造节点。
		if metadata.get("host_path") is NodePath: metadata.host_path = str(metadata.host_path)
		snapshot.instances.append({"transform": _encode_transform(node.transform), META: metadata})
	return snapshot

static func validate(snapshot: Dictionary) -> String:
	if snapshot.has("capture_error"): return str(snapshot.capture_error)
	if snapshot.size() != 3 or not snapshot.has_all(["schema_version", "layer_transform", "instances"]):
		return "外挂快照字段不完整或含未知字段"
	if not Recipe.number(snapshot.schema_version) or float(snapshot.schema_version) != 1.0:
		return "外挂快照只支持 schema_version=1"
	var reason := _json_reason(snapshot)
	if not reason.is_empty(): return reason
	if JSON.stringify(snapshot).to_utf8_buffer().size() > MAX_JSON_BYTES: return "外挂快照超过8MiB容量"
	if not _valid_transform(snapshot.layer_transform): return "外挂层变换非有限、奇异或镜像"
	if not snapshot.instances is Array or snapshot.instances.size() > MAX_INSTANCES:
		return "外挂实例须为数组且不超过256件"
	var ids: Dictionary = {}
	for item: Variant in snapshot.instances:
		if not item is Dictionary or item.size() != 2 or not item.has_all(["transform", META]):
			return "外挂实例必须仅含transform和sea_attachment"
		if not _valid_transform(item.transform): return "外挂实例变换非有限、奇异或镜像"
		var metadata: Variant = item[META]
		if not metadata is Dictionary: return "sea_attachment须为对象"
		if not Recipe.number(metadata.get("schema_version")) or float(metadata.schema_version) != 1.0:
			return "外挂实例元数据版本不支持"
		var id: Variant = metadata.get("instance_id", metadata.get("instanceid"))
		if not id is String or not _safe_id(id): return "外挂instance_id须为1..128位安全ASCII标识"
		if metadata.has("instance_id") and metadata.has("instanceid") and metadata.instance_id != metadata.instanceid:
			return "外挂instance_id与兼容instanceid不一致"
		if ids.has(id): return "同一外挂层含重复instance_id：" + id
		ids[id] = true
		for key: String in metadata:
			if key not in ["schema_version", "instance_id", "instanceid", "recipe", "host_path", "host_instance_id", "host_revision", "anchor", "stats"]:
				return "外挂元数据含未知字段：" + key
		for key: String in ["host_path", "host_instance_id", "host_revision"]:
			if metadata.has(key) and not metadata[key] is String: return "外挂宿主提示必须为字符串：" + key
		if metadata.has("stats") and not metadata.stats is Dictionary: return "外挂stats须为JSON对象"
		if not metadata.get("recipe") is Dictionary: return "外挂实例缺少配方"
		reason = Recipe.validate(metadata.recipe)
		if not reason.is_empty(): return reason
		reason = _anchor_reason(metadata.get("anchor"))
		if not reason.is_empty(): return reason
	return ""

static func _anchor_reason(value: Variant) -> String:
	var required := ["mode", "mesh_path", "surface", "triangle", "host_position", "host_normal", "local_position", "native", "declared_clearance_m", "offset_m", "angle_degrees"]
	if not value is Dictionary or not value.has_all(required): return "外挂anchor缺少完整安装字段"
	for key: String in value:
		if not required.has(key) and key != "hint": return "外挂anchor含未知字段：" + key
	if not value.mode is String or value.mode not in ["wall", "roof"]: return "外挂anchor.mode只允许wall/roof"
	for key: String in ["mesh_path", "hint"]:
		if value.has(key) and not value[key] is String: return "外挂anchor路径及提示只能为说明字符串：" + key
	for key: String in ["surface", "triangle"]:
		var number: Variant = value[key]
		if not Recipe.number(number) or float(number) < 0.0 or float(number) != floor(float(number)):
			return "外挂anchor索引必须为非负整数：" + key
	for key: String in ["local_position", "host_position", "host_normal"]:
		if not _finite_numbers(value[key], 3): return "外挂anchor须为3项有限数值：" + key
	var normal: Array = value.host_normal
	var length_squared := float(normal[0]) * float(normal[0]) + float(normal[1]) * float(normal[1]) + float(normal[2]) * float(normal[2])
	# 宿主法线来自Vector3.normalized，允许real_t舍入，但不接受零向量或非单位说明。
	if not is_finite(length_squared) or absf(length_squared - 1.0) > 0.000001: return "外挂anchor.host_normal必须为非零单位法线"
	if not Recipe.number(value.offset_m) or float(value.offset_m) < 0.0 or float(value.offset_m) > 0.5: return "外挂anchor.offset_m须为0..0.5"
	if not Recipe.number(value.angle_degrees) or absf(float(value.angle_degrees)) > 180.0: return "外挂anchor.angle_degrees须为-180..180"
	if not Recipe.number(value.declared_clearance_m) or absf(float(value.declared_clearance_m) - 0.012) > 0.000000001:
		return "外挂anchor.declared_clearance_m须为0.012"
	var native: Variant = value.native
	var native_keys := ["name", "position", "basis", "front_axis", "up_axis"]
	if not native is Dictionary or native.size() != native_keys.size() or not native.has_all(native_keys): return "外挂anchor.native字段不完整或未知"
	if not native.name is String or not _safe_id(native.name): return "外挂anchor.native.name必须为安全名称"
	if not _finite_numbers(native.position, 3) or not _finite_numbers(native.basis, 9): return "外挂anchor.native需要position3与basis9有限数值"
	var identity := [1, 0, 0, 0, 1, 0, 0, 0, 1]
	for index in 9:
		if absf(float(native.basis[index]) - float(identity[index])) > 0.000000001: return "外挂anchor.native.basis必须为单位基"
	if not native.front_axis is String or native.front_axis != "-Z" or not native.up_axis is String or native.up_axis != "+Y":
		return "外挂anchor.native轴声明必须为-Z/+Y"
	return ""

static func _finite_numbers(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count: return false
	for number: Variant in value:
		if not Recipe.number(number): return false
	return true

static func fingerprint(snapshot: Dictionary) -> String:
	if not validate(snapshot).is_empty(): return ""
	return _canonical(snapshot).sha256_text()

static func build(snapshot: Dictionary) -> Dictionary:
	var reason := validate(snapshot)
	if not reason.is_empty(): return {"ok": false, "reason": reason, "root": null}
	var root := Node3D.new()
	root.name = "Attachments"
	root.transform = _decode_transform(snapshot.layer_transform)
	root.set_meta("visual_only", true)
	root.set_meta("world_derivation", "excluded_visual_only")
	for item: Dictionary in snapshot.instances:
		var metadata: Dictionary = item[META]
		var built: Dictionary = Generator.build(metadata.recipe.duplicate(true))
		if not built.get("ok", false):
			root.free()
			return {"ok": false, "reason": str(built.get("reason", "外挂生成失败")), "root": null}
		var node: Node3D = built.root
		if not _static_tree(node):
			node.free()
			root.free()
			return {"ok": false, "reason": "原生生成结果含脚本或外链", "root": null}
		node.name = "Attachment_" + str(metadata.get("instance_id", metadata.get("instanceid")))
		node.transform = _decode_transform(item.transform)
		node.set_meta(META, metadata.duplicate(true))
		node.set_meta(CANONICAL_META, _canonical(metadata))
		root.add_child(node)
		_own_local(node, root)
	return {"ok": true, "reason": "", "root": root}

static func _native_metadata_equal(expected: Variant, actual: Variant) -> bool:
	if expected is Dictionary:
		if not actual is Dictionary or expected.size() != actual.size(): return false
		for key: Variant in expected:
			if not actual.has(key) or not _native_metadata_equal(expected[key], actual[key]): return false
		return true
	if expected is Array:
		if not actual is Array or expected.size() != actual.size(): return false
		for index in expected.size():
			if not _native_metadata_equal(expected[index], actual[index]): return false
		return true
	if expected is int or expected is float:
		return (actual is int or actual is float) and is_finite(float(expected)) and is_finite(float(actual)) and absf(float(expected) - float(actual)) <= maxf(1.0, absf(float(expected))) * 0.00000095367431640625
	return typeof(expected) == typeof(actual) and expected == actual

static func _safe_id(value: String) -> bool:
	if value.is_empty() or value.length() > 128: return false
	for character: String in value:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".contains(character): return false
	return true

static func _json_reason(value: Variant, depth: int = 0) -> String:
	if depth > 32: return "外挂元数据嵌套过深"
	if value == null or value is bool or value is String: return ""
	if value is int or value is float:
		return "" if is_finite(float(value)) else "外挂元数据含非有限数值"
	if value is Dictionary:
		for key: Variant in value:
			if not key is String: return "外挂元数据键必须为字符串"
			if key.to_lower() in ["script", "script_path", "scriptpath", "script_source"]:
				return "外挂元数据不允许脚本字段"
			var reason := _json_reason(value[key], depth + 1)
			if not reason.is_empty(): return reason
		return ""
	if value is Array:
		for item: Variant in value:
			var reason := _json_reason(item, depth + 1)
			if not reason.is_empty(): return reason
		return ""
	return "外挂元数据必须为JSON安全值"

static func _encode_transform(value: Transform3D) -> Array:
	return [value.basis.x.x, value.basis.x.y, value.basis.x.z,
		value.basis.y.x, value.basis.y.y, value.basis.y.z,
		value.basis.z.x, value.basis.z.y, value.basis.z.z,
		value.origin.x, value.origin.y, value.origin.z]

static func _decode_transform(value: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(value[0], value[1], value[2]), Vector3(value[3], value[4], value[5]),
		Vector3(value[6], value[7], value[8])), Vector3(value[9], value[10], value[11]))

static func _valid_transform(value: Variant) -> bool:
	if not value is Array or value.size() != 12: return false
	for number: Variant in value:
		if not Recipe.number(number): return false
	var transform := _decode_transform(value)
	var determinant := transform.basis.determinant()
	return transform.is_finite() and is_finite(determinant) and determinant > 0.000000001

static func _canonical(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var parts: Array[String] = []
		for key: String in keys: parts.append(JSON.stringify(key) + ":" + _canonical(value[key]))
		return "{" + ",".join(parts) + "}"
	if value is Array:
		var parts: Array[String] = []
		for item: Variant in value: parts.append(_canonical(item))
		return "[" + ",".join(parts) + "]"
	if value is int or value is float:
		var text := "%.9f" % float(value)
		return "0" if float(text) == 0.0 else text
	return JSON.stringify(value)

static func _static_tree(node: Node) -> bool:
	if node.get_script() != null or not node.scene_file_path.is_empty(): return false
	for child: Node in node.get_children():
		if not _static_tree(child): return false
	return true

static func _own_local(node: Node, root: Node) -> void:
	node.owner = root
	for child: Node in node.get_children(): _own_local(child, root)
