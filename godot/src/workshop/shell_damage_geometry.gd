@tool
extends RefCounted
## 仅门窗非承重填充件的确定性破损；不删除墙/楼板，不参与布局或植物随机流。

const WindowGeometry = preload("res://src/workshop/shell_window_geometry.gd")

static func _variant(seed: int, suffix: String) -> Dictionary:
	var value: int = (str(seed) + ":shell_damage:" + suffix).sha256_text().substr(0, 8).hex_to_int()
	return {"mirror": (value & 1) != 0, "center": 0.46 + float((value >> 1) % 1001) * 0.00008}

## 单个凹多边形挤出成薄实体；每条凹边都有厚度封边，不是裂纹贴图或碎盒。
static func _extrude(buffer: Dictionary, profile: Array[Vector2], run: Dictionary, near: float, far: float, geometry: Script) -> void:
	if not geometry._simple_polygon(profile): return
	if Geometry2D.triangulate_polygon(PackedVector2Array(profile)).size() != (profile.size() - 2) * 3: return
	var a: Array[Vector3] = geometry._run_ring(profile, run, near)
	var b: Array[Vector3] = geometry._run_ring(profile, run, far)
	var n2: Vector2 = run.outward
	var normal: Vector3 = Vector3(n2.x, 0.0, n2.y)
	geometry._profile_face(buffer, a, profile, normal)
	geometry._profile_face(buffer, b, profile, -normal)
	geometry._join_profile(buffer, a, b, profile, run, false)

## 单位方形左侧开口；缺失面积随damage连续增大，保留右侧连通的整片玻璃。
static func _glass_outline(damage: float, center: float) -> Array[Vector2]:
	var reach: float = 0.035 + 0.78 * damage
	var span: float = 0.04 + 0.74 * damage
	var low: float = center - span * 0.5
	var high: float = center + span * 0.5
	return [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0),
		Vector2(0.0, high), Vector2(reach * 0.22, high - span * 0.12),
		Vector2(reach * 0.56, high - span * 0.08), Vector2(reach, center + span * 0.08),
		Vector2(reach * 0.68, center - span * 0.10), Vector2(reach * 0.86, low + span * 0.19),
		Vector2(reach * 0.28, low + span * 0.10), Vector2(0.0, low)]

## 单位方形底边木纤维缺口；仍是一块完整连通门扇，不切散为几根木条。
static func _door_outline(damage: float, center: float) -> Array[Vector2]:
	var width: float = 0.07 + 0.24 * damage
	var rise: float = 0.025 + 0.24 * damage
	var low: float = center - width * 0.5
	return [Vector2(0.0, 0.0), Vector2(low, 0.0),
		Vector2(low + width * 0.12, rise * 0.40), Vector2(low + width * 0.32, rise),
		Vector2(low + width * 0.49, rise * 0.65), Vector2(low + width * 0.70, rise * 0.82),
		Vector2(low + width, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]

## 双线性映射跟随同一个opening pull，含上宽下窄；镜像后恢复CCW剖面。
static func _fit(outline: Array[Vector2], quad: Array[Vector2], mirror: bool) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for point in outline:
		var u: float = 1.0 - point.x if mirror else point.x
		result.append(quad[0].lerp(quad[3], point.y).lerp(quad[1].lerp(quad[2], point.y), u))
	if mirror: result.reverse()
	return result

static func glass(buffer: Dictionary, hole: Dictionary, run: Dictionary, suffix: String, damage: float, seed: int, geometry: Script) -> void:
	var moving: bool = hole.has("settings") and str(hole.settings.type) != "fixed"
	var pane: Dictionary = WindowGeometry._sash_hole(hole) if moving else hole
	var settings: Dictionary = pane.get("settings", {})
	var gap: float = 0.002
	var quad: Array[Vector2] = geometry._opening_quad(float(pane.cx), float(pane.sill) + gap,
		float(pane.width) - gap * 2.0, float(pane.height) - gap * 2.0, 0.0, float(pane.get("pull", 0.0)))
	var variant: Dictionary = _variant(seed, suffix)
	var profile: Array[Vector2] = _fit(_glass_outline(damage, float(variant.center)), quad, bool(variant.mirror))
	var recess: float = float(settings.get("recess", float(run.depth) * 0.5))
	var half: float = float(settings.get("glass_thickness", 0.02)) * 0.5
	_extrude(buffer, profile, run, recess - half, recess + half, geometry)
	# 先在同一门窗局部平面裁口，再走与原玻璃相同的铰链旋转，最后由_part统一taper。
	if moving: WindowGeometry._rotate(buffer, WindowGeometry._hinge(hole, run))

static func door(buffer: Dictionary, hole: Dictionary, run: Dictionary, suffix: String, damage: float, seed: int, geometry: Script) -> void:
	var gap: float = float(geometry.DOOR_LEAF_GAP)
	var quad: Array[Vector2] = geometry._opening_quad(float(hole.cx), float(hole.sill) + gap,
		float(hole.width) - gap * 2.0, float(hole.height) - gap * 2.0, 0.0, float(hole.get("pull", 0.0)))
	var variant: Dictionary = _variant(seed, suffix)
	var profile: Array[Vector2] = _fit(_door_outline(damage, float(variant.center)), quad, bool(variant.mirror))
	var near: float = float(geometry.DOOR_LEAF_RECESS)
	_extrude(buffer, profile, run, near, near + float(geometry.DOOR_LEAF_THICKNESS), geometry)
