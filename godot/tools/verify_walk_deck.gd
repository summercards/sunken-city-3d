extends SceneTree
## 断言：每块 WalkArea 的可行走矩形必须落在真实甲板上（SEA-MOVE-R01）。
##
## 本工程的走路不走物理碰撞 —— 站得住是因为 WalkArea.surface_y 直接把脚贴到那个高度。
## 所以「矩形越过甲板边缘」= 玩家能走进水里，而画面上看起来只是「又走到栏杆边」。
## 这个错误不会报错、不会崩，只会让人物站在水面上。
##
## 做法：给每个区块的可见网格临时建三角碰撞（只在本进程内存里），
## 在每块可行走矩形内按格采样，统计「脚下的确有 surface_y 附近的朝上实心面」的比例。
## 覆盖率低于 EXPECTED 里登记的基线就失败 —— 基线是实测值，不是拍脑袋的门槛；
## 允许覆盖率上升（说明矩形收得更准），只拦下降（矩形又越过甲板）。
##
## 必须用真实渲染跑（不加 --headless）：headless 的 dummy renderer 读不出
## MultiMesh 实例变换，木屋这类实例化组件会全部落在原点，量出来全是水。
##
##   godot --path godot --script res://tools/verify_walk_deck.gd

const ZONES := [
	["zone1", "zones/zone1_home_harbor.tscn"],
	["zone2", "zones/zone2_yokohama_station.tscn"],
	["zone3", "zones/zone3_arc_farm.tscn"],
	["zone4", "zones/zone4_far_shore.tscn"],
	["zone5", "zones/zone5_aqua_platform.tscn"],
]
const SAMPLE := 0.25
## 容忍高度差：站面 ±0.30 m 内、朝向接近水平朝上的面算甲板。
const Y_TOLERANCE := 0.30
const NORMAL_MIN := 0.55
## 每块区域登记的实测覆盖率基线（2026-10-29 实测，0.25 m 栅格 + 3×3 抖动）。
##
## 基线是实测值，不是门槛：覆盖率上升说明矩形收得更准，允许；
## 下降说明矩形又越过了甲板，失败。
##
## 已知残留（数字本身就这么低的原因，放宽必须在这里写清楚）：
##   zone2 / zone3 —— 旧手工矩形从未按实测甲板重做（见
##     docs/development/2026-10-26_sea_scene_blockers.md §4）；
##   zone4 —— 4 个废墟单元拼接的接缝；
##   zone1_home_dock —— rect1 北侧 z 5.0…6.0、x 0.4…1.4 有一块甲板缺口，
##     站在那儿是踩在结构缝里而不是水里，未纳入本次修复范围。
const EXPECTED := {
	"zone1/zone1_home_dock": 0.94,
	"zone1/zone1_salvage": 0.89,
	"zone2/zone2_station": 0.69,
	"zone3/zone3_ground": 0.39,
	"zone4/zone4_shore": 0.68,
	"zone5/zone5_aqua": 0.90,
}

var _space: PhysicsDirectSpaceState3D
var _bodies: Array = []
var _fails := 0
var _checks := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for pair in ZONES:
		var packed: Variant = load("res://scenes/%s" % pair[1])
		if packed == null:
			print("FAIL %s 场景加载失败" % pair[0])
			_fails += 1
			continue
		var zone: Node3D = (packed as PackedScene).instantiate()
		root.add_child(zone)
		await process_frame
		await physics_frame
		_space = root.world_3d.direct_space_state
		_build(zone)
		await physics_frame
		await physics_frame
		_walk_zone(str(pair[0]), zone)
		zone.queue_free()
		await process_frame
	for b in _bodies:
		(b as Node).queue_free()

	print("[walk-deck] %d checks, %d failures" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)


func _walk_zone(zone_id: String, zone: Node) -> void:
	var holder: Node = zone.get_node_or_null("WalkAreas")
	if holder == null:
		print("FAIL %s 没有 WalkAreas" % zone_id)
		_fails += 1
		return
	for area in holder.get_children():
		if not ("rects" in area):
			continue
		var key := "%s/%s" % [zone_id, str(area.area_id)]
		var sy := float(area.surface_y)
		var hit := 0
		var total := 0
		var wet := []
		for r in area.rects:
			var rect: Rect2 = r
			var nx := maxi(1, int(round(rect.size.x / SAMPLE)))
			var nz := maxi(1, int(round(rect.size.y / SAMPLE)))
			for j in nz:
				for i in nx:
					var x := rect.position.x + (float(i) + 0.5) * SAMPLE
					var z := rect.position.y + (float(j) + 0.5) * SAMPLE
					total += 1
					# 每格抖 3×3 点取多数：木板缝会让单条射线漏下去，产生假空洞。
					var n := 0
					for ox in [-0.07, 0.0, 0.07]:
						for oz in [-0.07, 0.0, 0.07]:
							if _deck(area.to_global(Vector3(x + ox, 0.0, z + oz)), sy):
								n += 1
					if n >= 5:
						hit += 1
					else:
						wet.append(Vector2(x, z))
		var cover := float(hit) / float(maxi(1, total))
		var base := float(EXPECTED.get(key, 1.0))
		_checks += 1
		var tag := "OK  "
		if cover + 0.0001 < base:
			tag = "FAIL"
			_fails += 1
		print("%s %s cover=%.3f base=%.3f cells=%d wet=%d" % [
			tag, key, cover, base, total, wet.size()])
		if not wet.is_empty():
			var sample := []
			for k in mini(wet.size(), 12):
				sample.append([snappedf(wet[k].x, 0.05), snappedf(wet[k].y, 0.05)])
			print("     wet@ " + JSON.stringify(sample))


func _deck(p: Vector3, sy: float) -> bool:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, sy + 0.8, p.z), Vector3(p.x, sy - 0.6, p.z))
	q.collide_with_areas = false
	var h: Dictionary = _space.intersect_ray(q)
	if h.is_empty():
		return false
	var y := (h.position as Vector3).y
	return absf(y - sy) <= Y_TOLERANCE and absf((h.normal as Vector3).y) > NORMAL_MIN


func _build(node: Node) -> void:
	for child in node.get_children():
		if child is MultiMeshInstance3D:
			var mmi := child as MultiMeshInstance3D
			if mmi.is_visible_in_tree() and mmi.multimesh != null:
				var shape: Shape3D = mmi.multimesh.mesh.create_trimesh_shape()
				if shape != null:
					for i in mmi.multimesh.instance_count:
						_attach(shape, mmi.global_transform * mmi.multimesh.get_instance_transform(i))
		elif child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.is_visible_in_tree() and mi.mesh != null:
				var shape2: Shape3D = mi.mesh.create_trimesh_shape()
				if shape2 != null:
					_attach(shape2, mi.global_transform)
		_build(child)


func _attach(shape: Shape3D, xf: Transform3D) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.global_transform = xf
	root.add_child(body)
	_bodies.append(body)
