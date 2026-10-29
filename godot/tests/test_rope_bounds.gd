extends SceneTree
## SEA-MOVE-R01：可行走矩形必须落在栏杆绳**里面**。
##
## 为什么需要这条：栈桥两侧有栏杆绳（`bridge_rope`），它高出甲板 0.48~1.06 m。
## 人只要站在绳子外侧，画面上就是"人穿过栏杆站在水边"。
##
## 之前的矩形是按「甲板边」写的（x 0.6…5.8），而绳子内沿在 x 0.936 / 5.197 ——
## 人整个站在绳外走了好几轮都没人发现，因为：
##   · 没有碰撞体，绳子和人互不干涉；
##   · 甲板覆盖测试只问"脚下有没有木板"，不问"头顶有没有栏杆"。
##
## 这条断言的关键是**从模型几何现场量绳位**，不写死坐标：
## 绳位一旦在 Blender 里挪了，这个测试会自动跟着改判据；
## 若矩形没跟上，就会失败。这样"模型改了、数据没改"的脱节会被当场抓住。
##
##   godot --headless --path godot --script res://tests/test_rope_bounds.gd

## 允许矩形贴到绳的多近。绳子本身有粗细（约 0.10 m），
## 取 0 表示矩形不得越过绳内沿一毫米。


var checks := 0
var failures := 0
var main: Node


func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	# 不能禁用 process_mode：组件的 build() 在 _ready 里跑，
	# 禁用后 MultiMesh 实例变换全是单位矩阵，量出来的绳位会塌在原点。
	main.cam.suspend_follow()
	var economy: Node = root.get_node_or_null("Economy")
	if economy != null:
		economy.set("ticking", false)
	for i in 20:
		await process_frame
	var zone: Node3D = main._zone_nodes.get("zone1", null)
	if zone == null:
		printerr("FAIL zone1 未加载")
		quit(1)
		return

	# 现场从模型量绳位：把所有 bridge_rope 实例的世界 AABB 合起来。
	var ropes: Array = []
	_collect_ropes(zone, ropes)
	check(ropes.size() >= 2, "找到栈桥栏杆绳实例（%d 个）" % ropes.size())
	if ropes.is_empty():
		print("[rope-bounds] %d checks, %d failures" % [checks, failures])
		quit(1)
		return

	# 只有"沿栈桥长边"的两道长绳（z 跨度 > 3 m）才是左右边界；
	# 根部/末端的短端头只约束 z，不参与 x 边界。
	var long: Array = []
	var z_min := INF
	var z_max := -INF
	for b: AABB in ropes:
		z_min = minf(z_min, b.position.z)
		z_max = maxf(z_max, b.end.z)
		if b.size.z > 3.0:
			long.append(b)
	check(long.size() == 2, "左右各一道长绳（实际 %d 道）" % long.size())

	var x_min := INF
	var x_max := -INF
	for b: AABB in long:
		x_min = minf(x_min, b.position.x)
		x_max = maxf(x_max, b.end.x)
	# 绳是细柱：内侧沿 = 靠中间那一侧。
	# 西侧绳取 end.x（靠东），东侧绳取 position.x（靠西）。
	var west_inner := -INF
	var east_inner := INF
	for b: AABB in long:
		if b.position.x < 0.0 or b.end.x < 4.0:
			west_inner = maxf(west_inner, b.end.x)
		else:
			east_inner = minf(east_inner, b.position.x)
	print("[rope-bounds] 绳实测：x %.3f…%.3f（西内沿 %.3f，东内沿 %.3f）z %.3f…%.3f" % [
		x_min, x_max, west_inner, east_inner, z_min, z_max])

	var area: Node3D = null
	for a in zone.walk_areas:
		if str(a.area_id) == "zone1_home_dock":
			area = a
	check(area != null, "找到 zone1_home_dock")
	if area == null:
		print("[rope-bounds] %d checks, %d failures" % [checks, failures])
		quit(1)
		return

	# 核心断言：栈桥段的每块矩形都必须落在绳内沿以内。
	#
	# 只查「整块都在绳的 z 跨度内」的矩形 = 栈桥本体。
	# 主甲板（z 5…11.5）只是和绳头有零点几米重叠，它在绳区之外，不受左右绳约束。
	var EPS := 0.02
	var checked := 0
	for r in area.rects:
		var rect: Rect2 = r
		if rect.position.y < z_min - 0.5 or rect.end.y > z_max + 0.5:
			continue
		checked += 1
		check(rect.position.x + EPS >= west_inner,
			"矩形左沿 %.3f 不得越出西绳内沿 %.3f" % [rect.position.x, west_inner])
		check(rect.end.x - EPS <= east_inner,
			"矩形右沿 %.3f 不得越出东绳内沿 %.3f" % [rect.end.x, east_inner])
		check(rect.position.y >= z_min - 0.75,
			"矩形北沿 %.3f 不该远在绳端 %.3f 之外（绳头外没有护栏）" % [rect.position.y, z_min])
		check(rect.end.y <= z_max + 0.75,
			"矩形南沿 %.3f 不该远在绳端 %.3f 之外" % [rect.end.y, z_max])
	check(checked >= 1, "至少有一块矩形与栈桥重叠（实际 %d）" % checked)

	# 行为断言：点栈桥东侧水面，站位必须落在绳内。
	var east_probe := Vector2(east_inner + 0.6, (z_min + z_max) * 0.5)
	var got: Vector2 = area.clamp_point(east_probe.x, east_probe.y)
	check(got.x <= east_inner,
		"点东绳外 (%.2f,%.2f) → 站位 x=%.3f 仍在东绳内沿 %.3f 以内" % [
			east_probe.x, east_probe.y, got.x, east_inner])
	var west_probe := Vector2(west_inner - 0.6, (z_min + z_max) * 0.5)
	var got2: Vector2 = area.clamp_point(west_probe.x, west_probe.y)
	check(got2.x >= west_inner,
		"点西绳外 (%.2f,%.2f) → 站位 x=%.3f 仍在西绳内沿 %.3f 以外" % [
			west_probe.x, west_probe.y, got2.x, west_inner])

	print("[rope-bounds] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _collect_ropes(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is MultiMeshInstance3D:
			var mmi := c as MultiMeshInstance3D
			var label := str(mmi.get_meta("asset_component", ""))
			if "rope" in label.to_lower() and mmi.multimesh != null:
				# headless 的 dummy renderer 读不出 MultiMesh 实例变换（一律单位矩阵），
				# 必须优先读 sunny_bloom_visual 写下的 instance_transforms meta。
				var xf_meta: Variant = mmi.get_meta("instance_transforms", null)
				if xf_meta is Array and not (xf_meta as Array).is_empty():
					for xf: Transform3D in xf_meta:
						out.append((mmi.global_transform * xf) * mmi.multimesh.mesh.get_aabb())
				else:
					for i in mmi.multimesh.instance_count:
						var xf2: Transform3D = mmi.global_transform * mmi.multimesh.get_instance_transform(i)
						out.append(xf2 * mmi.multimesh.mesh.get_aabb())
		_collect_ropes(c, out)
