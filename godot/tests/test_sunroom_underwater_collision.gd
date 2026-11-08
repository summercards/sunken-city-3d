extends SceneTree
## 独立区域的抽样物理回归，不宣称覆盖全部三角面或测量运行 FPS。
const SCENE_PATH := "res://scenes/underwater/sunroom_region.tscn"
const REPORT_PATH := "res://outputs/sunroom-collision-report.json"
const ROLES := ["city_structure", "city_bridge", "city_road", "city_decoration", "city_fixture", "solar_base", "facility_light", "coral"]
const SAMPLE_LIMIT := 40
const BASE_SAMPLE_LIMIT := 300
const REJECTION_DETAIL_LIMIT := 3
const MASK := 1
const TOLERANCE := 0.1
const FINAL_CONTACT_TOLERANCE := 0.03
const TRACE_CAST_TOLERANCE := 0.02
const CLEARANCE_SHRINK := 0.001
var checks := 0
var failures := 0
var scene: Node3D
var runtime: Node3D
var viewer: CharacterBody3D
var space: PhysicsDirectSpaceState3D
var capsule: CapsuleShape3D
var sphere: SphereShape3D
var sphere_body: CharacterBody3D
var categories: Dictionary = {}
var failure_labels: Array[String] = []
var report: Dictionary = {}
var wall_candidate: Dictionary = {}
var bridge_samples: Array = []
var verified_starts: Array[Vector3] = []


func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		failure_labels.append(label)
		printerr("FAIL ", label)


func category(key: String) -> Dictionary:
	if not categories.has(key):
		categories[key] = {"tested": 0, "blocked": 0, "skip_reason": {}, "rejection_details": {}, "sourcepaths": [], "cases": []}
	return categories[key]


func reject(key: String, reason: String, details: Dictionary = {}) -> void:
	var reasons: Dictionary = category(key)["skip_reason"]
	reasons[reason] = int(reasons.get(reason, 0)) + 1
	var recorded: Dictionary = category(key)["rejection_details"]
	if not details.is_empty():
		if not recorded.has(reason):
			recorded[reason] = []
		if recorded[reason].size() < REJECTION_DETAIL_LIMIT:
			var copy := details.duplicate(true)
			recorded[reason].append(copy)
			print("[sunroom-collision] reject %s %s %s" % [key, reason, JSON.stringify(copy)])


func hit_data(hit: Dictionary) -> Dictionary:
	var result := {"empty": hit.is_empty()}
	if hit.is_empty():
		return result
	var collider: Object = hit.get("collider")
	if collider == null:
		collider = instance_from_id(int(hit.get("collider_id", 0)))
	result["collider"] = str((collider as Node).get_path()) if collider is Node else str(collider)
	result["source_path"] = str(collider.get_meta("proxy_source_path", "")) if collider is Node else ""
	if hit.has("position"):
		result["point"] = vector_data(hit["position"])
	if hit.has("point"):
		result["point"] = vector_data(hit["point"])
	if hit.has("normal"):
		result["normal"] = vector_data(hit["normal"])
	return result


func vector_data(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func remember_source(key: String, path: String) -> void:
	var paths: Array = category(key)["sourcepaths"]
	if not paths.has(path):
		paths.append(path)


func query_shape(shape: Shape3D, position: Vector3, motion := Vector3.ZERO) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, position)
	query.motion = motion
	query.collision_mask = MASK
	query.collide_with_areas = false
	query.margin = 0.001
	query.exclude = [viewer.get_rid(), sphere_body.get_rid()]
	return query


func empty_at(shape: Shape3D, position: Vector3) -> bool:
	return space.intersect_shape(query_shape(shape, position), 8).is_empty()


func cast(shape: Shape3D, position: Vector3, motion: Vector3) -> PackedFloat32Array:
	return space.cast_motion(query_shape(shape, position, motion))


func ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, MASK)
	query.hit_back_faces = true
	query.exclude = [viewer.get_rid(), sphere_body.get_rid()]
	return space.intersect_ray(query)


func support(shape: Shape3D, normal: Vector3) -> float:
	if shape is CapsuleShape3D:
		var vertical := shape as CapsuleShape3D
		return vertical.radius + maxf(0.0, vertical.height * 0.5 - vertical.radius) * absf(normal.y)
	return (shape as SphereShape3D).radius


func in_viewer_bounds(point: Vector3) -> bool:
	var local := scene.to_local(point)
	var bounds: Rect2 = scene.get("terrain_bounds")
	return local.x > bounds.position.x + 1.01 and local.x < bounds.end.x - 1.01 and local.z > bounds.position.y + 1.01 and local.z < bounds.end.y - 1.01 and local.y > float(scene.get("lowest_seabed_y")) + 0.81 and local.y < float(scene.get("water_level")) - capsule.height * 0.5 - 0.03


func sample_points(sample: Dictionary) -> Array[Vector3]:
	var center: Vector3 = sample["position"]
	var points: Array[Vector3] = [center]
	var triangle: PackedVector3Array = sample["triangle"]
	for weight in [0.25, 0.5]:
		for vertex in triangle:
			points.append(center.lerp(vertex, weight))
	return points


func by_area(a: Dictionary, b: Dictionary) -> bool:
	return float(a["area"]) > float(b["area"])


func samples_for(role: String, axis := Vector3.ZERO, alignment := 0.8, limit := SAMPLE_LIMIT) -> Array:
	var samples: Array = runtime.call("surface_samples", role, limit, axis, alignment)
	samples.sort_custom(by_area)
	return samples


func candidate(key: String, samples: Array, shape: Shape3D, horizontal_only := false, top_only := false) -> Dictionary:
	for sample: Dictionary in samples:
		var body := scene.get_node_or_null(NodePath(str(sample["proxy_path"]))) as StaticBody3D
		if body == null:
			reject(key, "样本代理路径无效", {"target_source": sample["source_path"]})
			continue
		for side in [1.0, -1.0]:
			var seed_normal: Vector3 = sample["normal"] * float(side)
			for seed_point: Vector3 in sample_points(sample):
				var probe_start := seed_point + seed_normal * 2.0
				var details := {"seed_point": vector_data(seed_point), "start": vector_data(probe_start),
					"target_proxy": str(body.get_path()), "target_source": sample["source_path"],
					"shape": "capsule" if shape is CapsuleShape3D else "sphere", "side": side}
				# 最大三角面只用来找入口；同一个网格的前侧凸出面也是真实目标。
				var hit := ray(probe_start, seed_point - seed_normal * 0.1)
				details["ray"] = hit_data(hit)
				if hit.is_empty() or hit.get("collider") != body:
					reject(key, "入口射线首碰非目标源", details)
					continue
				var point: Vector3 = hit["position"]
				details["ray_hit_distance"] = probe_start.distance_to(point)
				var normal: Vector3 = hit["normal"]
				if normal.dot(probe_start - point) < 0.0:
					normal = -normal
				details["seed_to_ray_distance"] = point.distance_to(seed_point)
				details["point"] = vector_data(point)
				details["normal"] = vector_data(normal)
				if top_only and normal.y < 0.99999:
					reject(key, "桥面道路要求从水平真实顶面接近", details)
					continue
				if horizontal_only and (absf(normal.y) > 0.0001 or absf(normal.dot(seed_normal)) < 0.99999):
					reject(key, "真实首面不是水平轴墙面", details)
					continue
				var start := point + normal * 2.0
				details["start"] = vector_data(start)
				if not in_viewer_bounds(start) or not in_viewer_bounds(point + normal * (support(shape, normal) + 0.02)):
					reject(key, "接触位置受区域边界裁剪", details)
					continue
				if not empty_at(capsule, start) or not empty_at(shape, start):
					reject(key, "起点胶囊或所选形状非净空", details)
					continue
				var aligned_hit := ray(start, point - normal * 0.1)
				details["aligned_ray"] = hit_data(aligned_hit)
				var ray_distance := -1.0
				if not aligned_hit.is_empty():
					ray_distance = (aligned_hit["position"] as Vector3).distance_to(point)
				details["aligned_point_error"] = ray_distance
				if aligned_hit.is_empty() or aligned_hit.get("collider") != body or ray_distance > 0.02:
					reject(key, "沿真实法线重投无法复现同源点", details)
					continue
				var motion := -normal * 100.0
				if shape is CapsuleShape3D:
					var target := scene.to_local(start + motion)
					var bounds: Rect2 = scene.get("terrain_bounds")
					target.x = clampf(target.x, bounds.position.x + 1.0, bounds.end.x - 1.0)
					target.z = clampf(target.z, bounds.position.y + 1.0, bounds.end.y - 1.0)
					target.y = clampf(target.y, float(scene.get("lowest_seabed_y")) + 0.8, float(scene.get("water_level")) - capsule.height * 0.5 - 0.02)
					var clipped_motion := scene.to_global(target) - start
					details["clipped_motion"] = vector_data(clipped_motion)
					if clipped_motion.dot(-normal) < 2.0 or clipped_motion.slide(normal).length() > 0.1:
						reject(key, "100m 法线请求被区域边界改变方向或提前截停", details)
						continue
				# 短程仅定位首面，避免用100m扫掠量化误差筛掉所有本可测试的点。
				# 高速扫掠随后是强制断言，失败不能换候选掩盖。
				var fractions := cast(shape, start, motion)
				details["high_fractions"] = Array(fractions)
				if fractions.size() == 2:
					details["high_safe_distance"] = float(fractions[0]) * motion.length()
					details["high_unsafe_distance"] = float(fractions[1]) * motion.length()
				var short_motion := -normal * 3.0
				var short_fractions := cast(shape, start, short_motion)
				details["short_fractions"] = Array(short_fractions)
				var expected := 2.0 - support(shape, normal)
				details["expected_distance"] = expected
				if short_fractions.size() != 2 or short_fractions[0] >= 1.0:
					reject(key, "短程真实形状扫掠未命中", details)
					continue
				var safe_distance := float(short_fractions[0]) * 3.0
				var unsafe_distance := float(short_fractions[1]) * 3.0
				details["actual_safe_distance"] = safe_distance
				details["actual_unsafe_distance"] = unsafe_distance
				# 预期接触必须落入物理引擎返回的区间；只给形状margin/数值误差留量。
				if expected < safe_distance - 0.02 or expected > unsafe_distance + 0.02:
					reject(key, "短程首碰区间不包含目标面支撑距离", details)
					continue
				# unsafe 位姿可能已经越过薄双面三角形，不能用该位姿的 overlap
				# 缺失误判成无碰撞；用物理体 test_only 短扫确认首碰对象和旅行距离。
				var contact := space.get_rest_info(query_shape(shape, start + short_motion * float(short_fractions[1])))
				details["unsafe_rest_info"] = hit_data(contact)
				var probe_body: CharacterBody3D = viewer if shape is CapsuleShape3D else sphere_body
				probe_body.global_position = start
				var short_hit := probe_body.move_and_collide(short_motion, true, 0.001)
				if short_hit == null:
					reject(key, "短程物理体test_only无首碰", details)
					continue
				details["short_body_hit"] = hit_data({"collider": short_hit.get_collider(), "position": short_hit.get_position(), "normal": short_hit.get_normal()})
				details["short_body_travel"] = short_hit.get_travel().length()
				if short_hit.get_collider() != body:
					reject(key, "短程形状首碰来源非目标代理", details)
					continue
				var contact_normal := short_hit.get_normal()
				if contact_normal.dot(normal) < 0.98 or absf(short_hit.get_travel().length() - expected) > 0.02:
					reject(key, "短程形状首碰法线或距离并非目标面", details)
					continue
				return {"start": start, "point": point, "normal": normal, "motion": motion,
					"safe_fraction": fractions[0] if fractions.size() == 2 else -1.0,
					"unsafe_fraction": fractions[1] if fractions.size() == 2 else -1.0,
					"source_path": str(sample["source_path"]), "proxy_path": str(sample["proxy_path"]),
					"triangle_index": aligned_hit.get("face_index", -1), "seed_triangle_index": sample["triangle_index"],
					"side": side, "shape": shape, "body": body, "direct_normal": contact_normal,
					"expected_distance": expected, "short_fractions": Array(short_fractions),
					"candidate_details": details}
	return {}


func verify_motion_trace(key: String, start: Vector3, finish: Vector3, trace: Array) -> Dictionary:
	var valid := not trace.is_empty()
	check(valid, key + "：实际 move_viewer 轨迹非空")
	var previous := start
	var first_contact: Dictionary = {}
	var evidence: Array = []
	var clearance_shape := CapsuleShape3D.new()
	clearance_shape.radius = capsule.radius - CLEARANCE_SHRINK
	clearance_shape.height = capsule.height - CLEARANCE_SHRINK * 2.0
	for index in trace.size():
		var item: Dictionary = trace[index]
		var position: Vector3 = item["position"]
		var request: Vector3 = item["request"]
		var travel: Vector3 = item["travel"]
		var after: Vector3 = item["after"]
		var actual := after - position
		var contact: Dictionary = item["contact"]
		var fractions := cast(capsule, position, request)
		var cast_valid := fractions.size() == 2 and fractions[0] >= 0.0 and fractions[0] <= fractions[1] and fractions[1] <= 1.0
		var safe_distance := float(fractions[0]) * request.length() if cast_valid else -1.0
		var unsafe_distance := float(fractions[1]) * request.length() if cast_valid else -1.0
		var interval_ok := cast_valid and actual.length() <= unsafe_distance + TRACE_CAST_TOLERANCE
		# 保守早停不构成穿越；cast_motion 会忽略初始接触，不能要求它复现恢复碰撞。
		# safe/unsafe 均保留为证据，但任何超过 unsafe 的实际旅行仍必须失败。
		var conservative_stop := cast_valid and actual.length() < safe_distance - TRACE_CAST_TOLERANCE
		if first_contact.is_empty() and not contact.is_empty():
			interval_ok = interval_ok and cast_valid and fractions[0] < 1.0 and not conservative_stop
		# 另扫实际走过的线段，即使薄 mesh 后方的终点已净空，也不能放过中途穿越。
		var travel_fractions := cast(capsule, position, actual)
		var travel_ok := travel_fractions.size() == 2 and actual.length() <= float(travel_fractions[1]) * actual.length() + TRACE_CAST_TOLERANCE
		var recovery := actual - travel
		var continuous := position.distance_to(previous) < 0.0001 and recovery.length() <= 0.005
		var along_request := actual.distance_to(request.normalized() * actual.dot(request.normalized())) <= TRACE_CAST_TOLERANCE and actual.dot(request.normalized()) >= -0.005
		var clearance_query := query_shape(clearance_shape, after)
		clearance_query.margin = 0.0
		var overlaps := space.intersect_shape(clearance_query, 8)
		var clear := overlaps.is_empty()
		check(continuous, key + "：轨迹段%d连续且接触恢复量<=5mm" % index)
		check(along_request, key + "：轨迹段%d实际位移沿本次请求" % index)
		check(interval_ok, key + "：轨迹段%d实际 travel 在独立请求cast首碰范围内；travel=%.6f safe=%.6f unsafe=%.6f" % [index, actual.length(), safe_distance, unsafe_distance])
		check(travel_ok, key + "：轨迹段%d实际路径独立cast无穿越（包括薄mesh）" % index)
		check(clear, key + "：轨迹段%d终点缩小1mm胶囊真实净空" % index)
		valid = valid and continuous and along_request and interval_ok and travel_ok and clear
		var entry := {"step": item["step"], "slide": item["slide"], "position": vector_data(position),
			"request": vector_data(request), "travel": vector_data(travel), "after": vector_data(after),
			"contact": {}, "remainder": vector_data(item["remainder"]), "slide_remainder": vector_data(item["slide_remainder"]),
			"request_cast": Array(fractions), "safe_distance": safe_distance, "unsafe_distance": unsafe_distance,
			"actual_path_cast": Array(travel_fractions), "interval_ok": interval_ok, "path_clear": travel_ok,
			"endpoint_clear": clear, "conservative_stop": conservative_stop,
			"recovery": vector_data(recovery), "overlaps": []}
		for overlap: Dictionary in overlaps:
			entry["overlaps"].append(hit_data(overlap))
		if not contact.is_empty():
			entry["contact"] = {"point": vector_data(contact["point"]), "normal": vector_data(contact["normal"]),
				"collider": contact["collider"], "source_path": contact["source_path"]}
			if first_contact.is_empty():
				first_contact = entry.duplicate(true)
		evidence.append(entry)
		previous = after
	var complete := previous.distance_to(finish) < 0.0001
	check(complete, key + "：全轨迹覆盖实际终点")
	return {"valid": valid and complete, "motion_trace": evidence, "first_contact": first_contact}


func blocked_case(key: String, sample: Dictionary, use_sphere := false) -> bool:
	var record := category(key)
	record["tested"] += 1
	var shape: Shape3D = sample["shape"]
	var start: Vector3 = sample["start"]
	var normal: Vector3 = sample["normal"]
	var point: Vector3 = sample["point"]
	var motion: Vector3 = sample["motion"]
	var clear := empty_at(capsule, start) and empty_at(shape, start)
	var high_valid := true
	var high_body_details: Dictionary = {}
	if sample.has("expected_distance"):
		var safe_fraction := float(sample["safe_fraction"])
		var unsafe_fraction := float(sample["unsafe_fraction"])
		var expected := float(sample["expected_distance"])
		var high_hit := safe_fraction >= 0.0 and safe_fraction < 1.0 and unsafe_fraction >= safe_fraction and unsafe_fraction <= 1.0
		check(high_hit, key + "：100m direct_space_state.cast_motion 必须真实命中")
		var interval_matches := high_hit and expected >= safe_fraction * motion.length() - 0.02 and expected <= unsafe_fraction * motion.length() + 0.02
		check(interval_matches, key + "：100m 首碰区间包含同源实面距离；safe=%.6f unsafe=%.6f expected=%.6f" % [safe_fraction * motion.length(), unsafe_fraction * motion.length(), expected])
		high_valid = high_hit and interval_matches
		if clear:
			var probe_body: CharacterBody3D = sphere_body if use_sphere else viewer
			probe_body.global_position = start
			var high_collision := probe_body.move_and_collide(motion, true, 0.001)
			var same_source: bool = high_collision != null and high_collision.get_collider() == sample["body"]
			check(same_source, key + "：100m物理体test_only首碰仍是目标源")
			high_valid = high_valid and same_source
			if high_collision != null:
				high_body_details = hit_data({"collider": high_collision.get_collider(), "position": high_collision.get_position(), "normal": high_collision.get_normal()})
				high_body_details["travel"] = high_collision.get_travel().length()
				var travel := high_collision.get_travel().length()
				var high_signed_plane := (start + high_collision.get_travel() - point).dot(normal)
				var interval_travel := high_hit and travel >= safe_fraction * motion.length() - 0.02 and travel <= unsafe_fraction * motion.length() + 0.02
				var no_penetration := high_signed_plane >= support(shape, normal) - 0.02
				var same_normal := high_collision.get_normal().dot(normal) >= 0.98
				high_body_details["signed_plane"] = high_signed_plane
				high_body_details["support_error"] = high_signed_plane - support(shape, normal)
				# 原生长扫二分返回的是保守safe位置，不等同最终motor的贴面精度。
				check(interval_travel, key + "：原生100m首碰旅行落在safe/unsafe合理区间")
				check(no_penetration, key + "：原生100m首碰保守停靠不穿面")
				check(same_normal, key + "：原生100m首碰法线仍匹配短程实面")
				high_valid = high_valid and interval_travel and no_penetration and same_normal
		if not high_valid:
			var details: Dictionary = sample["candidate_details"].duplicate(true)
			details["high_fractions"] = [safe_fraction, unsafe_fraction]
			details["high_safe_distance"] = safe_fraction * motion.length()
			details["high_unsafe_distance"] = unsafe_fraction * motion.length()
			details["high_body_hit"] = high_body_details
			reject(key, "已执行候选的100m真实扫掠失败，不改挑其它样本", details)
	check(clear, key + "：起点胶囊与所选形状 intersect_shape 为空")
	if not clear:
		reject(key, "执行时起点失去净空")
		return false
	if not verified_starts.has(start):
		verified_starts.append(start)
	var finish: Vector3
	var movement: Vector3
	var source_confirmed := true
	var trace_result: Dictionary = {}
	var short_body_details: Dictionary = {}
	var curved := key == "coral" and not use_sphere
	if not use_sphere and sample.has("expected_distance"):
		viewer.global_position = start
		var short_collision := viewer.move_and_collide(-normal * 3.0, true, 0.001)
		var short_precise := false
		if short_collision != null:
			var short_center := start + short_collision.get_travel()
			var short_error := short_center.distance_to(point + normal * support(shape, normal))
			short_precise = short_collision.get_collider() == sample["body"] and short_error <= FINAL_CONTACT_TOLERANCE
			short_body_details = hit_data({"collider": short_collision.get_collider(), "position": short_collision.get_position(), "normal": short_collision.get_normal()})
			short_body_details["travel"] = vector_data(short_collision.get_travel())
			short_body_details["center"] = vector_data(short_center)
			short_body_details["ideal_error"] = short_error
		check(short_precise, key + "：首次3m短扫同源且接触中心精度<=0.03m")
		high_valid = high_valid and short_precise
	if use_sphere:
		sphere_body.global_position = start
		var collision := sphere_body.move_and_collide(motion)
		finish = sphere_body.global_position
		movement = finish - start
		source_confirmed = collision != null and collision.get_collider() == sample["body"]
		check(source_confirmed, key + "：真实球刚体扫掠首碰目标来源")
	else:
		scene.call("set_viewer_position", start)
		runtime.set("trace_enabled", true)
		movement = scene.call("move_viewer", motion)
		runtime.set("trace_enabled", false)
		finish = viewer.global_position
		trace_result = verify_motion_trace(key, start, finish, runtime.get("motion_trace"))
		var first_contact: Dictionary = trace_result["first_contact"]
		source_confirmed = not first_contact.is_empty() and first_contact["contact"]["collider"] == str((sample["body"] as Node).get_path())
		check(source_confirmed, key + "：实际全轨迹首次contact仍是目标源")
		check(movement.distance_to(finish - start) < 0.0001, key + "：move_viewer 返回真实位移")
		check((scene.get_node("Camera") as Camera3D).global_position.distance_to(finish) < 0.0001, key + "：相机跟随真实胶囊")
	var signed_plane := (finish - point).dot(normal)
	var projected_support := support(shape, normal)
	var distance := finish.distance_to(start)
	var final_tolerance := TOLERANCE if use_sphere else FINAL_CONTACT_TOLERANCE
	var support_error := signed_plane - projected_support
	var ideal_center := point + normal * projected_support
	var ideal_distance := finish.distance_to(ideal_center)
	var reached_surface := absf(support_error) <= final_tolerance
	if not use_sphere and not curved and sample.has("expected_distance"):
		check(ideal_distance <= FINAL_CONTACT_TOLERANCE, key + "：分段move_viewer末位距理想接触中心<=0.03m，实际 %.6f" % ideal_distance)
		reached_surface = reached_surface and ideal_distance <= FINAL_CONTACT_TOLERANCE
	var penetration_tolerance := TOLERANCE if use_sphere else 0.005
	var not_through := signed_plane >= projected_support - penetration_tolerance
	var trace_valid := use_sphere or bool(trace_result.get("valid", false))
	var geometry_valid := not_through and reached_surface and distance < 2.0
	if curved:
		# 凹曲面可合法沿切线离开首次三角面的无限平面；是否穿越由逐段真实扫掠裁决。
		geometry_valid = trace_valid
	else:
		check(reached_surface, key + "：最终实际位置距理想support<=%.3fm，不能用原生长扫早停冒充，误差=%.6f" % [final_tolerance, support_error])
		check(not_through, key + "：%.3fm 请求后不穿首面，signed=%.4f support=%.4f" % [motion.length(), signed_plane, projected_support])
		check(distance < 2.0, key + "：实际移动不足 2m，实际 %.4f" % distance)
	var blocked := high_valid and source_confirmed and trace_valid and geometry_valid and distance > 0.02 and distance < motion.length() - 0.02
	check(distance < motion.length() - 0.02, key + "：实际位移被物理首面截短")
	check(distance > 0.02, key + "：净空中真实接近表面，不是假静止")
	if blocked:
		record["blocked"] += 1
	remember_source(key, str(sample["source_path"]))
	record["cases"].append({"kind": "sphere_move_and_collide" if use_sphere else "viewer_capsule_sweep",
		"start": vector_data(start), "surface": vector_data(point), "normal": vector_data(normal),
		"direct_normal": vector_data(sample["direct_normal"]), "motion": vector_data(motion),
		"finish": vector_data(finish), "actual_distance": distance, "signed_plane": signed_plane,
		"projected_support": projected_support, "support_error": support_error,
		"ideal_center": vector_data(ideal_center), "ideal_distance": ideal_distance,
		"final_contact_tolerance": final_tolerance, "penetration_tolerance": penetration_tolerance,
		"safe_fraction": sample["safe_fraction"],
		"unsafe_fraction": sample["unsafe_fraction"], "source_path": sample["source_path"],
		"proxy_path": sample["proxy_path"], "triangle_index": sample["triangle_index"], "normal_side": sample["side"],
		"short_fractions": sample.get("short_fractions", []), "high_body_hit": high_body_details,
		"short_body_hit": short_body_details, "curved_path_criterion": curved,
		"motion_trace": trace_result.get("motion_trace", []), "first_contact": trace_result.get("first_contact", {}),
		"trace_valid": trace_valid, "candidate_details": sample.get("candidate_details", {})})
	return blocked


func test_role(role: String) -> void:
	var limit := BASE_SAMPLE_LIMIT if role == "solar_base" else SAMPLE_LIMIT
	var samples := samples_for(role, Vector3.ZERO, 0.8, limit)
	category(role)["surface_samples"] = samples.size()
	category(role)["sample_limit"] = limit
	check(not samples.is_empty(), role + "：真实最大面候选非空")
	if role in ["city_bridge", "city_road"]:
		var top := samples_for(role, Vector3.UP, 0.95)
		if role == "city_bridge":
			bridge_samples = top
		samples = top
	if role == "solar_base":
		# 基座大批顶部在水上；扩大同源代理范围并另取侧面，而非改动运行时采样器。
		for axis in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3.DOWN]:
			samples.append_array(samples_for(role, axis, 0.95, BASE_SAMPLE_LIMIT))
		category(role)["expanded_surface_samples"] = samples.size()
	var selected := candidate(role, samples, capsule, false, role in ["city_bridge", "city_road"])
	if selected.is_empty() and role not in ["city_bridge", "city_road", "solar_base"]:
		for axis in [Vector3.UP, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			var alternate := samples_for(role, axis, 0.95)
			samples.append_array(alternate)
			selected = candidate(role, alternate, capsule)
			if not selected.is_empty():
				break
		category(role)["expanded_surface_samples"] = samples.size()
	if not selected.is_empty():
		blocked_case(role, selected)
	elif role == "facility_light":
		# 小灯杆最大面不一定允许竖直人体贴靠；仍要求真实球形扫掠，不能仅射线通过。
		selected = candidate(role, samples, sphere)
		if not selected.is_empty():
			blocked_case(role, selected, true)
	check(int(category(role)["tested"]) >= 1, role + "：至少一个可复现的真实物理样本；不可整类跳过")
	check(int(category(role)["blocked"]) >= 1, role + "：至少一个实际阻挡成立")


func test_wall_axis(key: String, axis: Vector3) -> void:
	category(key)
	var samples := samples_for("city_structure", axis, 0.99999)
	var selected := candidate(key, samples, capsule, true)
	if selected.is_empty():
		selected = candidate(key, samples_for("city_structure", -axis, 0.99999), capsule, true)
	check(not selected.is_empty(), key + "：墙外净空与真实首碰样本存在")
	if selected.is_empty():
		return
	check(absf((selected["normal"] as Vector3).dot(axis)) > 0.99999, key + "：独立水平轴墙面")
	blocked_case(key, selected)
	if wall_candidate.is_empty():
		wall_candidate = selected


func rejected_position_case(key: String, position: Vector3, reason: String) -> void:
	var camera := scene.get_node("Camera") as Camera3D
	var before := viewer.global_transform
	var camera_before := camera.global_transform
	var velocity_before := viewer.velocity
	var accepted: bool = runtime.call("try_set_viewer_position", position)
	category(key)["tested"] += 1
	category(key)["blocked"] += int(not accepted)
	check(not accepted, key + "：拒绝" + reason)
	check(viewer.global_transform.is_equal_approx(before), key + "：拒绝后胶囊位姿不变：" + reason)
	check(camera.global_transform.is_equal_approx(camera_before), key + "：拒绝后相机位姿不变：" + reason)
	check(viewer.velocity.is_equal_approx(velocity_before), key + "：拒绝后速度不变：" + reason)
	category(key)["cases"].append({"reason": reason, "position": vector_data(position), "accepted": accepted,
		"viewer_unchanged": viewer.global_transform.is_equal_approx(before),
		"camera_unchanged": camera.global_transform.is_equal_approx(camera_before)})


func test_position_entry() -> void:
	var key := "try_set_viewer_position"
	category(key)
	check(runtime.has_method("try_set_viewer_position"), key + "：正式安全定位入口存在")
	if not runtime.has_method("try_set_viewer_position"):
		return
	if wall_candidate.is_empty():
		check(false, key + "：缺少可复现的墙面净空/重叠样本")
		return
	var start: Vector3 = wall_candidate["start"]
	var point: Vector3 = wall_candidate["point"]
	var normal: Vector3 = wall_candidate["normal"]
	var fixture_clear := in_viewer_bounds(start) and empty_at(capsule, start)
	check(fixture_clear, key + "：raw fixture起点在范围内且真实净空")
	if not fixture_clear:
		return
	var valid := start
	var origin := Vector3.ZERO
	var origin_found := false
	for verified: Vector3 in verified_starts:
		if verified.distance_to(valid) > 0.1 and in_viewer_bounds(verified) and empty_at(capsule, verified):
			origin = verified
			origin_found = true
			break
	check(origin_found, key + "：另一已verified point作为起点，不假设法线偏移净空")
	if not origin_found:
		return
	# raw set仅用于另一已验证的合法fixture；合法目标复用已验证的墙面start。
	scene.call("set_viewer_position", origin)
	check(viewer.global_position.distance_to(origin) < 0.0001, key + "：raw set设置另一合法净空fixture")
	viewer.velocity = Vector3(0.2, 0.3, 0.4)
	var accepted: bool = runtime.call("try_set_viewer_position", valid)
	category(key)["tested"] += 1
	check(accepted, key + "：接受合法净空位置")
	check(viewer.global_position.distance_to(valid) < 0.0001, key + "：接受后真实胶囊移动到目标")
	check((scene.get_node("Camera") as Camera3D).global_position.distance_to(valid) < 0.0001, key + "：接受后相机同步")
	check(viewer.velocity.is_zero_approx(), key + "：接受后清零速度")
	category(key)["cases"].append({"reason": "合法净空", "position": vector_data(valid), "accepted": accepted})
	var overlap_found := false
	for offset in [0.0, 0.1, -0.1]:
		var overlap := point + normal * float(offset)
		if not in_viewer_bounds(overlap):
			continue
		var hits := space.intersect_shape(query_shape(capsule, overlap), 64)
		var source_hit := false
		for hit: Dictionary in hits:
			if hit.get("collider") == wall_candidate["body"]:
				source_hit = true
		if not source_hit:
			continue
		check(not hits.is_empty(), key + "：被拒绝重叠点由真实intersect_shape确认")
		remember_source(key, str(wall_candidate["source_path"]))
		viewer.velocity = Vector3(0.2, 0.3, 0.4)
		rejected_position_case(key, overlap, "同源墙面胶囊重叠")
		overlap_found = true
		break
	check(overlap_found, key + "：至少一个范围内真实同源重叠拒绝样本")
	var bounds: Rect2 = scene.get("terrain_bounds")
	var local := scene.to_local(valid)
	var lowest := float(scene.get("lowest_seabed_y")) + capsule.height * 0.5
	var highest := float(scene.get("water_level")) - capsule.height * 0.5 - 0.02
	var outside: Array[Dictionary] = [
		{"position": Vector3(bounds.position.x + 0.5, local.y, local.z), "reason": "X下界越界"},
		{"position": Vector3(bounds.end.x - 0.5, local.y, local.z), "reason": "X上界越界"},
		{"position": Vector3(local.x, local.y, bounds.position.y + 0.5), "reason": "Z下界越界"},
		{"position": Vector3(local.x, local.y, bounds.end.y - 0.5), "reason": "Z上界越界"},
		{"position": Vector3(local.x, lowest - 0.05, local.z), "reason": "最低海床范围越界"},
		{"position": Vector3(local.x, highest + 0.05, local.z), "reason": "水面胶囊半高范围越界"}]
	for item: Dictionary in outside:
		rejected_position_case(key, scene.to_global(item["position"]), str(item["reason"]))
	viewer.velocity = Vector3.ZERO


func test_wall_slide() -> void:
	var key := "wall_diagonal_slide"
	category(key)
	if wall_candidate.is_empty():
		check(false, key + "：无墙面样本")
		return
	var normal: Vector3 = wall_candidate["normal"]
	var tangent := Vector3.UP.cross(normal).normalized()
	for side in [1.0, -1.0]:
		var start: Vector3 = wall_candidate["start"]
		var near: Vector3 = wall_candidate["point"] + normal * (support(capsule, normal) + 0.04)
		var lateral: Vector3 = tangent * float(side) * 1.2
		if not empty_at(capsule, near) or not empty_at(capsule, near + lateral):
			reject(key, "贴墙滑移端点非净空")
			continue
		var clear_path := cast(capsule, near, lateral)
		if clear_path.size() != 2 or clear_path[0] < 0.999:
			reject(key, "贴墙切线另有物体")
			continue
		check(empty_at(capsule, start), key + "：起点胶囊无重叠")
		scene.call("set_viewer_position", start)
		var requested: Vector3 = -normal * 3.0 + lateral
		var first := cast(capsule, start, requested)
		check(first.size() == 2 and first[0] < 1.0, key + "：斜向直扫实际命中墙")
		var moved: Vector3 = scene.call("move_viewer", requested)
		var signed_plane := (viewer.global_position - (wall_candidate["point"] as Vector3)).dot(normal)
		var along := moved.dot(tangent * side)
		var blocked := signed_plane >= support(capsule, normal) - TOLERANCE
		category(key)["tested"] += 1
		category(key)["blocked"] += int(blocked)
		check(blocked, key + "：斜滑仍在首面外侧")
		check(along > 0.9 and absf(moved.y) < 0.05, key + "：实际保留水平切向位移而非完全卡住")
		remember_source(key, str(wall_candidate["source_path"]))
		category(key)["cases"].append({"start": vector_data(start), "requested": vector_data(requested),
			"moved": vector_data(moved), "signed_plane": signed_plane, "tangent_distance": along,
			"source_path": wall_candidate["source_path"]})
		return
	check(false, key + "：两侧均无可复现滑移通道")


func free_move(key: String, start: Vector3, motion: Vector3, source_path: String) -> bool:
	if not in_viewer_bounds(start) or not in_viewer_bounds(start + motion):
		reject(key, "空处通道受区域边界裁剪")
		return false
	if not empty_at(capsule, start) or not empty_at(capsule, start + motion):
		reject(key, "空处通道端点胶囊非净空")
		return false
	var fractions := cast(capsule, start, motion)
	if fractions.size() != 2 or fractions[0] < 0.99999:
		reject(key, "真实胶囊直扫存在阻挡")
		return false
	category(key)["tested"] += 1
	check(empty_at(capsule, start), key + "：起点 intersect_shape 为空")
	scene.call("set_viewer_position", start)
	var moved: Vector3 = scene.call("move_viewer", motion)
	var passed := moved.distance_to(motion) < 0.03
	check(passed, key + "：净空横移不被整块 AABB 封死")
	check(empty_at(capsule, viewer.global_position), key + "：移动后仍净空")
	remember_source(key, source_path)
	category(key)["cases"].append({"start": vector_data(start), "requested": vector_data(motion),
		"moved": vector_data(moved), "safe_fraction": fractions[0], "passed": passed, "source_path": source_path})
	return true


func test_open_spaces() -> void:
	var key := "junction_open_space"
	category(key)
	var old_point := Vector3(-84.0, -14.812558, 84.0)
	var exercised := false
	for motion in [Vector3(4, 0, 0), Vector3(-4, 0, 0), Vector3(0, 0, 4), Vector3(0, 0, -4)]:
		if free_move(key, old_point, motion, "ExistingModels/SunkenCity；旧路口确切点"):
			exercised = true
			break
	check(exercised, key + "：旧路口确切点至少完成一次 4m 横移")
	key = "under_bridge_open_space"
	category(key)
	exercised = false
	for sample: Dictionary in bridge_samples:
		var normal: Vector3 = sample["normal"]
		if normal.dot(Vector3.UP) < 0.95:
			continue
		for point in sample_points(sample):
			# 顶面下方逐层寻找实际净空；不把梁、墩或桥面自身当作空洞。
			for depth in [1.5, 2.2, 3.0, 4.0, 5.5]:
				var start: Vector3 = point + Vector3.DOWN * float(depth)
				var overhead := ray(start, point + Vector3.UP * 0.2)
				if overhead.is_empty() or overhead.get("collider") != scene.get_node_or_null(NodePath(str(sample["proxy_path"]))):
					reject(key, "候选上方无同源真实桥体")
					continue
				for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
					if free_move(key, start, direction * 4.0, str(sample["source_path"])):
						exercised = true
						break
				if exercised:
					break
			if exercised:
				break
		if exercised:
			break
	check(exercised, key + "：至少一个上方确有桥体的净空通道完成 4m 横移")


func test_terrain() -> void:
	var key := "seabed"
	category(key)
	var terrain := scene.get_node("ExistingModels/SunkenSeabed")
	var city_bounds: Rect2 = scene.get("city_bounds")
	var selected := false
	var reachable_candidates := 0
	var boundary_candidates: Array[Dictionary] = []
	for x in [-160.0, 160.0, -240.0, 240.0, -320.0, 320.0, -400.0, 400.0]:
		for z in [-160.0, 0.0, 160.0, -280.0, 280.0, -400.0, 400.0]:
			if city_bounds.has_point(Vector2(x, z)):
				continue
			var hit := ray(Vector3(x, -1.0, z), Vector3(x, -80.0, z))
			if hit.is_empty() or hit.get("collider") != terrain:
				reject(key, "城外向下射线未命中 Terrain3D 节点")
				continue
			var point: Vector3 = hit["position"]
			var normal: Vector3 = hit["normal"]
			if normal.dot(Vector3.UP) < 0.5:
				reject(key, "城外地形实际法线非朝上")
				continue
			var start := point + normal * 2.0
			var motion := -normal * 3.0
			var boundary_sample := {"point": point, "normal": normal}
			if not in_viewer_bounds(start) or not in_viewer_bounds(point + normal * (support(capsule, normal) + 0.03)):
				boundary_candidates.append(boundary_sample)
				reject(key, "Terrain 首面低于 viewer 有效边界", {"point": vector_data(point), "viewer_min_y": scene.get("viewer_min_y")})
				continue
			# 城外地形额外做沿真实法线的 3m 向下扫掠，不把坡面滑移或最低限位
			# 当成碰撞。100m 高速回归由各网格角色和两个墙轴独立执行。
			if not in_viewer_bounds(start + motion):
				boundary_candidates.append(boundary_sample)
				reject(key, "Terrain 扫掠终点受最低边界裁剪，不能作为物理证据")
				continue
			reachable_candidates += 1
			if not empty_at(capsule, start):
				reject(key, "Terrain 起点胶囊非净空")
				continue
			var approach := 2.0 - support(capsule, normal)
			var fractions := cast(capsule, start, motion)
			if fractions.size() != 2 or fractions[0] >= 1.0:
				reject(key, "Terrain 真实胶囊向下扫掠未命中")
				continue
			var contact_query := query_shape(capsule, start + motion * (float(fractions[1]) + 0.0001))
			contact_query.margin = 0.01
			var contact := space.get_rest_info(contact_query)
			if contact.is_empty() or int(contact.get("collider_id", 0)) != terrain.get_instance_id():
				reject(key, "Terrain 真实胶囊首碰来源不匹配")
				continue
			var physical_normal: Vector3 = contact["normal"]
			if physical_normal.dot(normal) < 0.99 or absf(float(fractions[0]) * motion.length() - approach) > 0.08:
				reject(key, "Terrain 胶囊首面与射线法线不一致")
				continue
			var sample := {"start": start, "point": point, "normal": normal, "motion": motion,
				"safe_fraction": fractions[0], "unsafe_fraction": fractions[1], "source_path": "ExistingModels/SunkenSeabed",
				"proxy_path": "ExistingModels/SunkenSeabed", "triangle_index": -1, "side": 1.0,
				"shape": capsule, "body": terrain, "direct_normal": physical_normal}
			check(normal.dot(Vector3.UP) > 0.5, key + "：使用真实物理地形法线而非 metadata")
			blocked_case(key, sample)
			selected = true
			break
		if selected:
			break
	category(key)["reachable_candidates"] = reachable_candidates
	category(key)["boundary_candidates"] = boundary_candidates.size()
	if not selected and reachable_candidates == 0 and not boundary_candidates.is_empty():
		# 仅合法边界使所有有效候选不可达时启用；可达候选物理失败不能改走底层探针。
		category(key)["coverage"] = "仅底层 Terrain 碰撞，不证明玩家可到；viewer 下界另测"
		selected = terrain_probe_case(terrain, boundary_candidates)
		test_terrain_viewer_boundary(boundary_candidates)
	else:
		category(key)["coverage"] = "真实 scene.move_viewer 可达地形首碰"
	check(selected and int(category(key)["blocked"]) >= 1, key + "：至少一处城外 Terrain3D 真实向下扫掠阻挡")


func terrain_probe_case(terrain: Node, samples: Array[Dictionary]) -> bool:
	var key := "seabed"
	var fixture: Dictionary = {}
	for sample: Dictionary in samples:
		var point: Vector3 = sample["point"]
		var normal: Vector3 = sample["normal"]
		var start := point + normal * 2.0
		var aligned := ray(start, point - normal * 0.1)
		if aligned.is_empty() or aligned.get("collider") != terrain or (aligned["position"] as Vector3).distance_to(point) > 0.02:
			reject(key, "底层球探针沿法线首碰不能复现同源 Terrain 点")
			continue
		if not empty_at(sphere, start):
			reject(key, "底层球探针起点非净空")
			continue
		fixture = {"point": point, "normal": normal, "start": start}
		break
	check(not fixture.is_empty(), key + "：边界外仍须有同源且净空的真实物理探针样本")
	if fixture.is_empty():
		return false
	# 使用已同步的独立球体，不借用 viewer，不调用区域裁剪，也不改变地形或边界。
	var before_failures := failures
	var same_space := sphere_body.get_world_3d() == scene.get_world_3d() and (terrain as Node3D).get_world_3d() == scene.get_world_3d()
	check(same_space, key + "：独立球探针与目标 Terrain 在同一真实物理空间")
	var point: Vector3 = fixture["point"]
	var normal: Vector3 = fixture["normal"]
	var start: Vector3 = fixture["start"]
	var motion := -normal * 3.0
	var expected := 2.0 - sphere.radius
	var fractions := cast(sphere, start, motion)
	var cast_hit := fractions.size() == 2 and fractions[0] >= 0.0 and fractions[0] < 1.0 and fractions[1] >= fractions[0] and fractions[1] <= 1.0
	check(cast_hit, key + "：底层球探针 cast_motion 必须实际命中；不命中仍 fail")
	var safe_distance := float(fractions[0]) * motion.length() if cast_hit else -1.0
	var unsafe_distance := float(fractions[1]) * motion.length() if cast_hit else -1.0
	check(cast_hit and expected >= safe_distance - TRACE_CAST_TOLERANCE and expected <= unsafe_distance + TRACE_CAST_TOLERANCE, key + "：底层首碰区间包含同源 Terrain 支撑距离")
	sphere_body.global_position = start
	var collision := sphere_body.move_and_collide(motion, false, 0.001)
	var finish := sphere_body.global_position
	var actual := finish - start
	var same_source := collision != null and collision.get_collider() == terrain
	check(same_source, key + "：底层球体实际 move_and_collide 首碰必须是目标 Terrain")
	var contact: Dictionary = {}
	if collision != null:
		contact = hit_data({"collider": collision.get_collider(), "position": collision.get_position(), "normal": collision.get_normal()})
		contact["travel"] = vector_data(collision.get_travel())
		check(actual.distance_to(collision.get_travel()) <= 0.005, key + "：底层球体实际位移匹配碰撞 travel，恢复量<=5mm")
		check(collision.get_normal().dot(normal) >= 0.99, key + "：底层球体接触法线匹配同源射线实面")
		check(collision.get_position().distance_to(point) <= FINAL_CONTACT_TOLERANCE, key + "：底层球体实际接触点距同源实面点<=0.03m")
	var ideal := point + normal * sphere.radius
	var signed_plane := (finish - point).dot(normal)
	check(actual.length() > 0.02 and actual.length() < motion.length() - 0.02, key + "：底层球体真实接近并被物理截短，不是假静止")
	check(cast_hit and actual.length() >= safe_distance - TRACE_CAST_TOLERANCE and actual.length() <= unsafe_distance + TRACE_CAST_TOLERANCE, key + "：底层实际位移不越独立 cast 首碰区间")
	check(finish.distance_to(ideal) <= FINAL_CONTACT_TOLERANCE, key + "：底层球体实际接触中心精度<=0.03m")
	check(signed_plane >= sphere.radius - 0.005, key + "：底层球体不越过 Terrain 首面，穿透容差<=5mm")
	var actual_cast := cast(sphere, start, actual)
	check(actual_cast.size() == 2 and actual.length() <= float(actual_cast[1]) * actual.length() + TRACE_CAST_TOLERANCE, key + "：底层球体实际经过路径独立 cast 无穿越")
	var clearance_shape := SphereShape3D.new()
	clearance_shape.radius = sphere.radius - CLEARANCE_SHRINK
	var clearance_query := query_shape(clearance_shape, finish)
	clearance_query.margin = 0.0
	check(space.intersect_shape(clearance_query, 8).is_empty(), key + "：底层球体终点缩小1mm后真实净空")
	var blocked := failures == before_failures
	category(key)["tested"] += 1
	category(key)["blocked"] += int(blocked)
	remember_source(key, "ExistingModels/SunkenSeabed")
	category(key)["cases"].append({"kind": "terrain_physics_only_sphere_move_and_collide",
		"coverage": "仅底层 Terrain 碰撞，不证明玩家可到", "uses_viewer_bounds": false,
		"same_physics_space": same_space, "start": vector_data(start), "surface": vector_data(point),
		"normal": vector_data(normal), "motion": vector_data(motion), "finish": vector_data(finish),
		"actual_travel": vector_data(actual), "expected_distance": expected, "cast_fractions": Array(fractions),
		"safe_distance": safe_distance, "unsafe_distance": unsafe_distance, "actual_path_cast": Array(actual_cast),
		"contact": contact, "ideal_center": vector_data(ideal), "ideal_distance": finish.distance_to(ideal),
		"signed_plane": signed_plane, "support_error": signed_plane - sphere.radius,
		"final_contact_tolerance": FINAL_CONTACT_TOLERANCE, "penetration_tolerance": 0.005,
		"source_path": "ExistingModels/SunkenSeabed", "blocked": blocked})
	return blocked


func test_terrain_viewer_boundary(samples: Array[Dictionary]) -> void:
	var key := "terrain_viewer_lower_boundary"
	category(key)["coverage"] = "仅证明 viewer 下潜受设定边界拦截，不作为 Terrain 碰撞证据"
	var minimum := float(scene.get("viewer_min_y"))
	check(is_equal_approx(minimum, float(scene.get("lowest_seabed_y")) + capsule.height * 0.5), key + "：声明下界与实际胶囊限位一致")
	var fixture: Dictionary = {}
	for sample: Dictionary in samples:
		var local := scene.to_local(sample["point"])
		local.y = minimum + 2.0
		var start := scene.to_global(local)
		local.y = minimum - 1.0
		var motion := scene.to_global(local) - start
		# 未裁剪请求本身也真实净空，才能把提前截停归因于边界，而非地形或其它代理。
		var fractions := cast(capsule, start, motion)
		if not in_viewer_bounds(start) or not empty_at(capsule, start) or not empty_at(capsule, start + motion) or fractions.size() != 2 or fractions[0] < 1.0:
			reject(key, "跨下界请求不是完整真实净空通道")
			continue
		fixture = {"start": start, "motion": motion, "fractions": Array(fractions)}
		break
	check(not fixture.is_empty(), key + "：必须找到跨下界的真实净空通道，不可整类跳过")
	if fixture.is_empty():
		return
	var before_failures := failures
	var start: Vector3 = fixture["start"]
	var motion: Vector3 = fixture["motion"]
	scene.call("set_viewer_position", start)
	runtime.set("trace_enabled", true)
	var moved: Vector3 = scene.call("move_viewer", motion)
	runtime.set("trace_enabled", false)
	var finish := viewer.global_position
	var trace: Array = runtime.get("motion_trace")
	var trace_result := verify_motion_trace(key, start, finish, trace)
	var no_contact := true
	var within_boundary := true
	for item: Dictionary in trace:
		no_contact = no_contact and (item["contact"] as Dictionary).is_empty()
		within_boundary = within_boundary and scene.to_local(item["position"]).y >= minimum - 0.0001 and scene.to_local(item["after"]).y >= minimum - 0.0001
	var expected_local := scene.to_local(start)
	expected_local.y = minimum
	check(finish.distance_to(scene.to_global(expected_local)) < 0.0001, key + "：scene.move_viewer 恰停在设定下界")
	check(within_boundary, key + "：实际全轨迹均不越 viewer 下界")
	check(no_contact and bool(trace_result["valid"]), key + "：净空轨迹没有物理 contact，边界截停不是 Terrain 证据")
	check(moved.distance_to(finish - start) < 0.0001 and moved.length() > 0.02 and moved.length() < motion.length() - 0.02, key + "：返回真实非零位移且请求确被边界截短")
	check((scene.get_node("Camera") as Camera3D).global_position.distance_to(finish) < 0.0001, key + "：边界截停后相机同步真实 viewer")
	category(key)["tested"] += 1
	category(key)["blocked"] += int(failures == before_failures)
	category(key)["cases"].append({"kind": "viewer_lower_boundary_only", "terrain_collision_evidence": false,
		"viewer_min_y": minimum, "start": vector_data(start), "motion": vector_data(motion),
		"finish": vector_data(finish), "moved": vector_data(moved), "unclipped_cast": fixture["fractions"],
		"no_physics_contact": no_contact, "within_boundary": within_boundary, "motion_trace": trace_result["motion_trace"]})


func check_sources(terrain: Node, original_data: Variant, original_directory: String) -> void:
	var counts: Dictionary = {}
	var sources: Dictionary = {}
	var invalid: Array[String] = []
	var proxy_count := 0
	for child in runtime.get_children():
		if not child is StaticBody3D:
			continue
		proxy_count += 1
		var role := str(child.get_meta("collision_role", ""))
		counts[role] = int(counts.get(role, 0)) + 1
		var path := str(child.get_meta("proxy_source_path", ""))
		var source := scene.get_node_or_null(NodePath(path)) if not path.is_empty() else null
		if not sources.has(role):
			sources[role] = []
		if not sources[role].has(path):
			sources[role].append(path)
		var collider := child.get_node_or_null("ExactMesh") as CollisionShape3D
		if source == null or not (source is MeshInstance3D or source is MultiMeshInstance3D) or collider == null or not collider.shape is ConcavePolygonShape3D or child.collision_layer != MASK:
			invalid.append(str(child.get_path()))
		elif not (collider.shape as ConcavePolygonShape3D).backface_collision or (collider.shape as ConcavePolygonShape3D).get_faces().is_empty():
			invalid.append(str(child.get_path()))
	check(invalid.is_empty(), "所有代理均指向存在的真实源节点及非空双面三角碰撞：" + str(invalid))
	var all_roles := true
	for role in ROLES:
		var nonzero := int(counts.get(role, 0)) > 0
		check(nonzero, role + "：真实代理数非零")
		all_roles = all_roles and nonzero
	check(proxy_count == 758 or all_roles, "758 个预期代理或全部角色真实代理非零")
	check(int(runtime.get("stats").get("proxy_count", -1)) == proxy_count, "代理统计与真实 StaticBody3D 数量一致")
	check(int(terrain.get("collision_mode")) == 3, "Terrain3D 节点实际 collision_mode 为 FullGame(3)")
	check(int(terrain.get("collision_layer")) == MASK, "Terrain3D 节点实际物理层为 1")
	check(terrain.get("data") == original_data, "碰撞 setup 保留同一个 Terrain3D data 资源")
	check(str(terrain.get("data_directory")) == original_directory and original_directory == "res://terrain/sunken_seabed", "保留真实地形 data_directory 源")
	check(int(terrain.get("data").get_region_count()) == 4, "真实地形 data 保留四区域")
	report["proxy_count"] = proxy_count
	report["expected_proxy_count"] = 758
	report["proxy_count_matches_baseline"] = proxy_count == 758
	report["roles"] = counts
	report["colliderstats"] = runtime.get("stats").duplicate(true)
	report["sourcepaths"] = sources
	report["terrain"] = {"source_node": str(scene.get_path_to(terrain)), "data_directory": original_directory,
		"collision_mode": terrain.get("collision_mode"), "regions": terrain.get("data").get_region_count()}


func run() -> void:
	report = {"runner_key": "sunroom-collision", "scene": SCENE_PATH, "sample_limit_per_call": SAMPLE_LIMIT,
		"coverage": "真实物理抽样回归；非全部组件/三角面穷举；非 FPS 基准", "physics_sync_frames": 0}
	var load_start := Time.get_ticks_usec()
	var packed := load(SCENE_PATH) as PackedScene
	check(packed != null, "独立区域场景可加载")
	if packed == null:
		finish()
		return
	scene = packed.instantiate() as Node3D
	var instantiated := Time.get_ticks_usec()
	var terrain := scene.get_node("ExistingModels/SunkenSeabed")
	var original_data: Variant = terrain.get("data")
	var original_directory := str(terrain.get("data_directory"))
	var tree_start := Time.get_ticks_usec()
	root.add_child(scene)
	var tree_end := Time.get_ticks_usec()
	current_scene = scene
	scene.set_process(false)
	scene.set_physics_process(false)
	report["timing_ms"] = {"load_and_instantiate": float(instantiated - load_start) / 1000.0,
		"add_child_and_ready_including_ecology_and_collision_setup": float(tree_end - tree_start) / 1000.0}
	runtime = scene.get("collision_runtime") as Node3D
	check(runtime != null, "区域正式 ready 创建 collision_runtime")
	if runtime == null:
		finish()
		return
	viewer = runtime.get("viewer") as CharacterBody3D
	check(viewer != null and scene.has_method("move_viewer") and scene.has_method("set_viewer_position"), "正式 viewer 与区域移动接口存在")
	if viewer == null:
		finish()
		return
	var viewer_shape := viewer.get_node_or_null("ViewerCapsule") as CollisionShape3D
	check(viewer_shape != null and viewer_shape.shape is CapsuleShape3D, "正式 viewer 使用竖直胶囊")
	if viewer_shape == null or not viewer_shape.shape is CapsuleShape3D:
		finish()
		return
	capsule = viewer_shape.shape as CapsuleShape3D
	check(is_equal_approx(capsule.radius, 0.35) and is_equal_approx(capsule.height, 1.6), "正式胶囊半径 0.35m、总高 1.6m")
	check(viewer_shape.transform.is_equal_approx(Transform3D.IDENTITY), "胶囊中心及竖直轴与 support 投影一致")
	check(viewer.collision_mask == MASK, "viewer 实际掩码包含区域静态物理层")
	sphere = SphereShape3D.new()
	sphere.radius = 0.08
	sphere_body = CharacterBody3D.new()
	sphere_body.name = "CollisionTestSmallSphere"
	sphere_body.collision_layer = 0
	sphere_body.collision_mask = MASK
	var sphere_shape := CollisionShape3D.new()
	sphere_shape.shape = sphere
	sphere_body.add_child(sphere_shape)
	root.add_child(sphere_body)
	for i in 3:
		await physics_frame
		await process_frame
		report["physics_sync_frames"] += 1
	check(int(report["physics_sync_frames"]) >= 2, "建树后至少同步两个真实 physics_frame")
	space = scene.get_world_3d().direct_space_state
	check_sources(terrain, original_data, original_directory)
	for role in ROLES:
		test_role(role)
	test_wall_axis("wall_x_100m", Vector3.RIGHT)
	test_wall_axis("wall_z_100m", Vector3.BACK)
	test_position_entry()
	test_wall_slide()
	test_terrain()
	test_open_spaces()
	finish()


func finish() -> void:
	for key in categories:
		var item: Dictionary = categories[key]
		print("[sunroom-collision] %s tested=%d blocked=%d skip_reason=%s sourcepaths=%s" % [key, item["tested"], item["blocked"], JSON.stringify(item["skip_reason"]), JSON.stringify(item["sourcepaths"])])
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs"))
	check(directory_error == OK, "报告输出目录可创建")
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	check(file != null, "JSON 报告文件可写")
	report["checks"] = checks
	report["failures"] = failures
	report["failure_labels"] = failure_labels
	report["categories"] = categories
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	if is_instance_valid(sphere_body):
		sphere_body.queue_free()
	if is_instance_valid(scene):
		scene.queue_free()
	print("[sunroom-collision] %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
