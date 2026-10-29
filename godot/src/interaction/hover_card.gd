extends CanvasLayer
## 屏幕投影只负责命中与小操作图标；动态操作气泡由HUD拥有。
## 不显示物体名、状态文案或原先的悬停说明卡。
##
## 命中范围（2026-10-29 二次修）：**按模型本体算** —— 从相机发一条射线，
## 打到物体的三角形才算命中。
##
## 走过的两个弯路，都留在这里当反例：
##   1. 只认「距图标中心 30 像素」。图标是命中之后才画的，
##      等于「你得先点中它才看得见它」，物体本体反而点不中。
##   2. 改成「物体在屏幕上的 AABB」。zone5 六个土箱两两相邻，缝只有十几像素宽，
##      各自 AABB 再外扩 10 px，整条缝被两侧盖满 —— 点甲板空地会被判成点土箱，
##      于是走不了路。用户截图红框标的正是这条缝。
##
## 所以现在真的按模型做：AABB 只用来粗筛，命中靠三角形求交。

const PropsScript = preload("res://src/pickups/sea_props.gd")

## 没有几何的纯逻辑交互点（睡眠点等），放弃射线，退回「距图标多少像素内可点」。
const HOVER_RADIUS := 30.0
## 图标贴边时保留的内缩（图标半径 19 + 一点呼吸位）。
const EDGE_INSET := 28.0
## 右上角（菜单格子）与右下角（回到角色）两颗 72px 圆按钮，外加呼吸位。
## 出屏目标的图标一旦被挤到这两个角上，就会压住常驻入口 ——
## 那颗图标是「给远处物体的提示」，不该抢 HUD 的位置。
const HUD_CORNER := 112.0
## 单个网格的三角形上限。超过就放弃三角形、只用贴合模型的 OBB 粗筛，
## 免得某个高模物件把悬停拖到卡顿。实测本工程最大的是出货箱 752 面。
const TRI_LIMIT := 1500
var camera: Camera3D
var markers: CanvasLayer
var props: Node3D
## 为 false 时（面板打开 / 潜水 / 航行中）不显示，也不改指针。
var enabled := true
## 当前所在区块，用来区分上岸桩是「前往」还是「已经在这里」。
var current_zone := "zone1"

var target: Dictionary = {}

## 玩家够不够得着这个物体（`func(spot) -> String`，空串表示够得着）。
##
## 走不到的目标**不给入口**：不画悬浮图标、不改指针、点了也不弹操作菜单。
## 2026-10-29 之前是「照弹菜单，再把每一项涂灰写原因」—— 玩家看到的仍然是一个
## 能操作的东西，只是被拒绝了，读起来像界面坏了。现在从源头不给。
## 点击时仍会单独查一次并给一句提示，避免「点了完全没反应」。
var reach_gate: Callable

## 可达性缓存：路径查询不算便宜，别每帧对每个候选都跑一遍。
## key = 实例 ID，value = {"at": 玩家位置, "reason": 原因, "stamp": 毫秒}。
var _reach_cache := {}
const REACH_TTL_MS := 350

var _card: PanelContainer
var _canvas: Control
var _shown := false
## 三角形缓存：mesh 实例 ID → 每 3 个顶点一组的局部空间三角形。
## 网格资源不变，缓存可以一直用；超过上限整体清掉（重建几百面很便宜，
## 而任由它长下去会在长时间游玩里慢慢吃内存）。
var _tri_cache := {}
const TRI_CACHE_LIMIT := 96


func _ready() -> void:
	set_meta("cozy_skip",true)
	layer = 12
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.custom_minimum_size = Vector2(38,38)
	var style := StyleBoxFlat.new()
	style.bg_color=Color("#438f83");style.set_corner_radius_all(19)
	style.border_color=Color("#fff9e7");style.set_border_width_all(2)
	style.content_margin_left=8;style.content_margin_right=8
	style.content_margin_top=8;style.content_margin_bottom=8
	_card.add_theme_stylebox_override("panel",style)
	_canvas.add_child(_card)
	var icon := TextureRect.new()
	icon.texture=preload("res://src/ui/illustrated_icons.gd").texture("hand",true)
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_card.add_child(icon)
	_card.hide()


## 每帧由 main 驱动。`screen` 是鼠标在视口里的位置。
func update_hover(screen: Vector2) -> void:
	if not enabled or camera == null or not is_instance_valid(camera):
		_clear_cursor()
		return
	var hit := _pick(screen)
	target = hit
	if hit.is_empty():
		_clear_cursor()
		_hide()
		return
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	if str(hit.get("type",""))=="landing":
		_hide()
		return
	_show(hit, screen)


func clear() -> void:
	target = {}
	_clear_cursor()
	_hide()


## 物体在屏幕上的包围盒。**只给调试与取证用**，不参与命中判定。
##
## 命中走射线打模型三角形（见 `_ray_visual_t`）。留这个是为了探针能一眼看出
## 「物体在画面上占多大一块」，以及取证脚本定位物体的屏幕中心。
##
## 取世界 AABB 的 8 个角投影后求并集。部分角在相机背后时跳过该角 ——
## 那种极端情况本来就只能近似。
func _screen_bounds(spot: Node3D) -> Rect2:
	if not spot.has_method("visual_aabb"):
		return Rect2()
	var box: AABB = spot.visual_aabb()
	if box.size.length() < 0.001:
		return Rect2()
	var box_pos := box.position
	var box_end := box.end
	var found := false
	var lo := Vector2.INF
	var hi := -Vector2.INF
	for i in 8:
		var corner := Vector3(
			box_end.x if (i & 1) != 0 else box_pos.x,
			box_end.y if (i & 2) != 0 else box_pos.y,
			box_end.z if (i & 4) != 0 else box_pos.z)
		if camera.is_position_behind(corner):
			continue
		var p: Vector2 = camera.unproject_position(corner)
		if not p.is_finite():
			continue
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		found = true
	if not found:
		return Rect2()
	return Rect2(lo, hi - lo)


## 射线与物体可见网格的最近交点（世界射线参数，米）。未命中返回 -1。
##
## 从 `visual_root()` 往下遍历 MeshInstance3D —— 和 `visual_aabb()` 同一套可见性口径，
## 热区预览、阻挡体这些辅助节点不算模型。
##
## 先用「网格自身 AABB × 世界变换」得到的 OBB 粗筛：这一步很便宜，
## 且对 BoxMesh 类物件已经是精确的，能把绝大多数逐三角形测试省掉。
func _ray_visual_t(origin: Vector3, dir: Vector3, spot: Node3D) -> float:
	if not spot.has_method("visual_root"): return -1.0
	var root: Node3D = spot.visual_root()
	if root == null: return -1.0
	var best := -1.0
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.visible and mi.mesh != null:
				var t := _ray_mesh_t(origin, dir, mi)
				if t >= 0.0 and (best < 0.0 or t < best):
					best = t
		stack.append_array(node.get_children())
	return best


func _ray_mesh_t(origin: Vector3, dir: Vector3, mi: MeshInstance3D) -> float:
	# 粗筛用贴合模型的 OBB，不是全场景合并后的 AABB —— 后者会把相邻格子连成一片。
	var box: AABB = mi.global_transform * mi.get_aabb()
	if not box.grow(0.02).intersects_ray(origin, dir): return -1.0
	var tris: PackedVector3Array = _mesh_triangles(mi.mesh)
	if tris.is_empty(): return -1.0
	var inv: Transform3D = mi.global_transform.affine_inverse()
	var local_o: Vector3 = inv * origin
	# 方向只转不平移，且不归一化：这样参数 t 与世界射线的 t 是同一个刻度。
	var local_d: Vector3 = inv.basis * dir
	var best := -1.0
	var i := 0
	while i + 2 < tris.size():
		var t := _ray_triangle(local_o, local_d, tris[i], tris[i + 1], tris[i + 2])
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
		i += 3
	return best


## 取网格的三角形（局部空间，每 3 个顶点一组）。
## 缓存按 mesh 实例 ID 存；网格是资源，重建成本低，丢了也不影响正确性。
func _mesh_triangles(mesh: Mesh) -> PackedVector3Array:
	var key := mesh.get_instance_id()
	if _tri_cache.has(key): return _tri_cache[key]
	var out := PackedVector3Array()
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		if arrays.is_empty(): continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.is_empty(): continue
		var idx = arrays[Mesh.ARRAY_INDEX]
		if idx == null or (idx as PackedInt32Array).is_empty():
			out.append_array(verts)
		else:
			for i in (idx as PackedInt32Array):
				out.append(verts[i])
		# 高模物件不做逐三角形：清空后由 OBB 兜底，避免悬停被拖慢。
		if out.size() / 3 > TRI_LIMIT:
			out = PackedVector3Array()
			break
	if _tri_cache.size() > TRI_CACHE_LIMIT: _tri_cache.clear()
	_tri_cache[key] = out
	return out


## Möller–Trumbore。返回射线参数 t（>0 为在身前），未命中 -1。
static func _ray_triangle(o: Vector3, d: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var e1 := b - a
	var e2 := c - a
	var p := d.cross(e2)
	var det := e1.dot(p)
	if absf(det) < 1e-9: return -1.0
	var inv := 1.0 / det
	var tv := o - a
	var u := tv.dot(p) * inv
	if u < -0.0001 or u > 1.0001: return -1.0
	var q := tv.cross(e1)
	var v := d.dot(q) * inv
	if v < -0.0001 or u + v > 1.0001: return -1.0
	var t := e2.dot(q) * inv
	return t if t > 0.0001 else -1.0


## 带缓存的可达性查询。空串 = 够得着；否则是「为什么够不着」。
##
## 只按 350 毫秒过期，不存玩家位置：悬停层不该知道角色在哪，
## 而 350ms 的陈旧值在画面上完全察觉不到（走一步要 0.4 秒以上）。
func reach_reason(spot: Node3D) -> String:
	if not reach_gate.is_valid() or spot == null or not is_instance_valid(spot):
		return ""
	var key := spot.get_instance_id()
	var now := Time.get_ticks_msec()
	var entry: Dictionary = _reach_cache.get(key, {})
	if not entry.is_empty() and now - int(entry.get("stamp", 0)) < REACH_TTL_MS:
		return str(entry.get("reason", ""))
	# 物体被释放后 instance id 可能被复用，顺手清掉过期项免得缓存无限长。
	if _reach_cache.size() > 256:
		for id in _reach_cache.keys():
			if now - int(_reach_cache[id].get("stamp", 0)) >= REACH_TTL_MS:
				_reach_cache.erase(id)
	var probe: Variant = reach_gate.call(spot)
	var reason := str(probe) if probe is String else ""
	_reach_cache[key] = {"reason": reason, "stamp": now}
	return reason


## 世界点 → 图标真正落在屏幕上的点。
##
## 视口内的目标**原样返回**：正常距离下图标必须钉在物体上，不能因为靠近边缘就被吸走。
## 只有整块投影出屏时（隔水看对面平台的常态）才夹到边内 —— 否则
## `unproject_position` 会给出几千像素外的坐标，玩家既点不到、也读不出
## 「那边有个能操作的东西」。命中判定用的就是这里的返回值，画在哪就判在哪。
func _clamp_to_viewport(p: Vector2) -> Vector2:
	if not p.is_finite():
		return p
	var vp := get_viewport().get_visible_rect().size
	if Rect2(Vector2.ZERO, vp).has_point(p):
		return p
	var inset := Vector2(minf(EDGE_INSET, vp.x * 0.5), minf(EDGE_INSET, vp.y * 0.5))
	var p2 := Vector2(clampf(p.x, inset.x, vp.x - inset.x), clampf(p.y, inset.y, vp.y - inset.y))
	# 两个角上的常驻圆按钮要留出来：被夹到角上的图标会让位，不压 HUD。
	var top_right := Rect2(Vector2(vp.x - HUD_CORNER, 0.0), Vector2(HUD_CORNER, HUD_CORNER))
	if top_right.has_point(p2):
		p2.y = minf(vp.y - inset.y, top_right.end.y + EDGE_INSET)
	var bottom_right := Rect2(Vector2(vp.x - HUD_CORNER, vp.y - HUD_CORNER), Vector2(HUD_CORNER, HUD_CORNER))
	if bottom_right.has_point(p2):
		p2.y = maxf(inset.y, bottom_right.position.y - EDGE_INSET)
	return p2


## 悬停命中：射线打到模型三角形，或落在图标热区内。
##
## 两条路径的优先级：
##   - **打到模型**排在最前（score 为负），越近越优先；
##   - 图标热区（30 px）是补充：给没有几何的纯逻辑交互点用，
##     也让「鼠标正好停在图标上」不至于落空。
##
## `include_barred` 为 false（默认）时，走不到的目标直接跳过 —— 不给图标、不给指针。
## 点击分派会再用 true 查一次，只为了说一句「为什么过不去」，不弹菜单。
func _pick(screen: Vector2, include_barred := false) -> Dictionary:
	var best := {}
	var best_score := INF
	var vp := get_viewport().get_visible_rect().size
	var ray_o := camera.project_ray_origin(screen)
	var ray_d := camera.project_ray_normal(screen)

	# 1) 世界里的可交互物（采集点 / 施工牌 / 菜箱 / 绞盘）
	for raw in get_tree().get_nodes_in_group("interactable"):
		var spot: Node3D = raw
		if spot == null or not is_instance_valid(spot) or not spot.is_visible_in_tree():
			continue
		# 图标贴在热区锚点上，和判定、编辑器预览用同一个位置。菜箱是贴地的格子，
		# 抬高少一点；其余物件抬到物体上半身，避免图标被自己挡住。
		var base: Vector3 = spot.focus_position()
		var anchor: Vector3 = base + Vector3.UP * (0.18 if spot.is_in_group("farm_plots") else 0.75)
		if camera.is_position_behind(anchor):
			continue
		var shown := _clamp_to_viewport(camera.unproject_position(anchor))
		var icon_dist := shown.distance_to(screen)
		var body_t := _ray_visual_t(ray_o, ray_d, spot)
		var on_body := body_t >= 0.0
		if not on_body and icon_dist > HOVER_RADIUS:
			continue
		# 只有近处候选才查可达性：全场景每个都跑一次路径规划，悬停就卡了。
		var barred := ""
		if on_body or icon_dist <= HOVER_RADIUS + 50.0:
			barred = reach_reason(spot)
		if barred != "" and not include_barred:
			continue
		var blocked := ""
		if spot.has_method("blocked_reason"):
			blocked = str(spot.blocked_reason())
		# 命中模型的一律排在前面：-10 起算，按距离微调，任何像素距离都不及它。
		# 只在图标路径上保留 priority —— 同距离下让重要的物件先被选中。
		var score := (-10.0 + body_t * 0.01) if on_body else (icon_dist - float(spot.priority) * 2.2)
		if score < best_score:
			best_score = score
			best = {
				"type": "spot", "node": spot, "screen": shown, "world": anchor,
				"title": spot.focus_text(),
				"sub": "点击前往并操作" if blocked == "" else blocked,
				"warn": blocked != "",
				"barred": barred,
			}

	# 2) 上岸桩（图标本身就在屏幕空间）
	if markers != null and markers.has_method("pick"):
		var mh: Dictionary = markers.pick(screen)
		if not mh.is_empty():
			var dist2: float = (mh.get("screen", screen) as Vector2).distance_to(screen)
			if dist2 - 3.0 < best_score:
				best_score = dist2 - 3.0
				var here: bool = str(mh.zone) == current_zone
				best = {
					"type": "landing", "hit": mh, "screen": mh.get("screen", screen),
					"world": Vector3.ZERO,
					"title": str(mh.get("name", "上岸点")),
					"sub": "已经在这里" if here else "点击前往",
					"warn": false,
				}

	# 3) 海面漂流物 / 鱼群
	if props != null and props.has_method("pick"):
		var ph: Dictionary = props.pick(screen, camera)
		if not ph.is_empty():
			var dist3: float = (ph.get("screen", screen) as Vector2).distance_to(screen)
			if dist3 < best_score:
				best_score = dist3
				if ph.type == "fish":
					best = {"type": "prop", "hit": ph, "screen": ph.screen, "world": Vector3.ZERO,
						"title": "海面鱼群", "sub": "点击驶近", "warn": false}
				else:
					var spec: Dictionary = PropsScript.CRATE_KINDS.get(ph.item.kind, PropsScript.CRATE_KINDS.crate)
					var bits := PackedStringArray()
					for k in spec.reward.keys():
						bits.append("%d %s" % [int(spec.reward[k]), _item_label(str(k))])
					best = {"type": "prop", "hit": ph, "screen": ph.screen, "world": Vector3.ZERO,
						"title": str(spec.label), "sub": "点击划过去拾取 · " + "  ".join(bits),
						"warn": false}
	return best


func _show(hit: Dictionary, screen: Vector2) -> void:
	_card.visible = true
	_shown = true

	# 先让容器算出尺寸，再摆位置（否则第一次会摆在左上角闪一下）。
	_card.reset_size()
	var sz := _card.size
	var anchor: Vector2 = hit.screen
	if hit.type != "spot" and hit.type != "prop":
		anchor = screen
	var pos := Vector2(anchor.x - sz.x * 0.5, anchor.y - sz.y - 16.0)
	var vp := get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, 8.0, maxf(8.0, vp.x - sz.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, vp.y - sz.y - 8.0))
	_card.position = pos


func _hide() -> void:
	if _shown:
		_card.visible = false
		_shown = false


func _clear_cursor() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _item_label(id: String) -> String:
	return ItemDB.label(id)
