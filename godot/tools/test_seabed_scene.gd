extends "res://tools/author_seabed_terrain.gd"
## 统一runner内重开持久资源，全像素与真实道路三角网格验收。

func rendered_height(data: Terrain3DData, x: float, z: float) -> float:
	var gx := floorf(x / STEP) * STEP
	var gz := floorf(z / STEP) * STEP
	var fx := (x - gx) / STEP
	var fz := (z - gz) / STEP
	var a := data.get_height(Vector3(gx, 0, gz))
	var b := data.get_height(Vector3(gx + STEP, 0, gz))
	var c := data.get_height(Vector3(gx, 0, gz + STEP))
	var d := data.get_height(Vector3(gx + STEP, 0, gz + STEP))
	var bilinear := lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)
	var triangle_a := a + (b - a) * fx + (c - a) * fz if fx + fz <= 1.0 else d + (c - d) * (1.0 - fx) + (b - d) * (1.0 - fz)
	var triangle_b := a + (b - a) * fx + (d - b) * fz if fx >= fz else a + (d - c) * fx + (c - a) * fz
	return maxf(bilinear, maxf(triangle_a, triangle_b))

func run() -> void:
	read_ground_geometry()
	check(city.get_child_count() == 388, "旧城388实例未增删")
	check(grounds.size() == 100, "100个ground完整")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 100, 160)
	camera.make_current()
	var packed := load(SCENE_PATH) as PackedScene
	check(packed != null, "海床PackedScene可重开")
	if packed == null:
		quit(1)
		return
	var seabed := packed.instantiate() as Terrain3D
	root.add_child(seabed)
	await process_frame
	check(seabed != null, "原生Terrain3D实例")
	check(seabed.collision_mode == 0 and seabed.get_meta("visual_only", false), "纯视觉无碰撞")
	check(not seabed.free_editor_textures, "保留自定义shader所需编辑纹理，避免释放警告")
	check(seabed.region_size == SIZE and is_equal_approx(seabed.vertex_spacing, STEP), "256像素region与2m间距")
	var data := seabed.data
	check(data.get_region_count() == 4, "标准Terrain3DData四region")
	var total := 0
	var zeros := 0
	var invalid := 0
	var mismatch := 0
	var outer_count := 0
	var outer_wrong := 0
	var max_neighbor_delta := 0.0
	var height_low := INF
	var height_high := -INF
	for rz in range(-1, 1):
		for rx in range(-1, 1):
			var region := data.get_region(Vector2i(rx, rz))
			check(region != null, "region存在 " + str(Vector2i(rx, rz)))
			if region == null:
				continue
			check(region.resource_path.ends_with(".res"), "持久化标准res " + str(Vector2i(rx, rz)))
			var image: Image = region.height_map
			check(image.get_size() == Vector2i(SIZE, SIZE) and image.get_format() == Image.FORMAT_RF, "完整32bit浮点高度图")
			for iz in SIZE:
				for ix in SIZE:
					var x := float(rx * SIZE + ix) * STEP
					var z := float(rz * SIZE + iz) * STEP
					var h := image.get_pixel(ix, iz).r
					total += 1
					zeros += int(is_zero_approx(h))
					invalid += int(not is_finite(h))
					mismatch += int(absf(h - seabed_height(x, z)) > 0.0001)
					height_low = minf(height_low, h)
					height_high = maxf(height_high, h)
					var closest := Vector2(clampf(x, bounds.position.x, bounds.end.x), clampf(z, bounds.position.y, bounds.end.y))
					if Vector2(x, z).distance_to(closest) >= PLATFORM + SLOPE + 0.01:
						outer_count += 1
						outer_wrong += int(absf(h - OUTER_Y) > 0.00001)
					if x < 508.0:
						max_neighbor_delta = maxf(max_neighbor_delta, absf(h - data.get_height(Vector3(x + STEP, 0, z))))
					if z < 508.0:
						max_neighbor_delta = maxf(max_neighbor_delta, absf(h - data.get_height(Vector3(x, 0, z + STEP))))
	check(total == 262144 and zeros == 0 and invalid == 0, "262144高度全部有限且无未写0")
	check(mismatch == 0, "全部持久像素符合真实geometry函数")
	check(outer_count > 0 and outer_wrong == 0, "全部outer严格-62")
	check(max_neighbor_delta < 1.6, "全图含region接缝无竖边，相邻2m高差小于1.6m")
	var support_samples := 0
	var penetration := 0
	var gap_wrong := 0
	var profile_transition_samples := 0
	var thin_gap_low := INF
	var thin_gap_high := -INF
	var min_gap := INF
	var max_gap := -INF
	var min_surface_clearance := INF
	var penetration_examples := []
	var gap_examples := []
	var irregular_bottom_samples := 0
	var irregular_bottom_gap_low := INF
	var irregular_bottom_gap_high := -INF
	for ground in grounds:
		var lo: Vector3 = ground["min"]
		var hi: Vector3 = ground["max"]
		var misses := 0
		for iz in range(1, 48):
			for ix in range(1, 48):
				var x := lerpf(lo.x, hi.x, float(ix) / 48.0)
				var z := lerpf(lo.z, hi.z, float(iz) / 48.0)
				var hit := ground_hits(x, z)
				if not is_finite(hit.x):
					misses += 1
					continue
				var h: float = rendered_height(data, x, z)
				var gap := hit.x - h
				support_samples += 1
				min_gap = minf(min_gap, gap)
				max_gap = maxf(max_gap, gap)
				min_surface_clearance = minf(min_surface_clearance, hit.y - h)
				penetration += int(h >= hit.y - 0.0001)
				if h >= hit.y - 0.0001 and penetration_examples.size() < 15:
					penetration_examples.append([str(ground["id"]), str(ground["key"]), x, z, hit.x, hit.y, h])
				# 普通薄板与标准坡街验贴底；厚楔体/运河采用用户允许的连续断面，独立验表面净空。
				var profile_bottom := cached_hits(x, 84.0).x
				var safety_transition := h < profile_bottom - GAP - 0.002 and x > -90.0 and x < 66.0
				profile_transition_samples += int(safety_transition)
				if str(ground["key"]) in ["plaza_tile", "street_intact", "junction"] and not safety_transition:
					thin_gap_low = minf(thin_gap_low, gap)
					thin_gap_high = maxf(thin_gap_high, gap)
					gap_wrong += int(gap < 0.099 or gap > 0.201)
					if (gap < 0.099 or gap > 0.201) and gap_examples.size() < 15:
						gap_examples.append([str(ground["id"]), str(ground["key"]), x, z, hit.x, hit.y, h])
				else:
					irregular_bottom_samples += 1
					irregular_bottom_gap_low = minf(irregular_bottom_gap_low, gap)
					irregular_bottom_gap_high = maxf(irregular_bottom_gap_high, gap)
		check(misses == 0, "上下ray覆盖 " + str(ground["id"]))
	check(penetration == 0, "实际道路面零穿地")
	check(gap_wrong == 0, "普通板底间隙0.1–0.2m；连续断面安全过渡区独立报告，不以底间隙冒充路面净空")
	var slope_violations := 0
	var plateau_violations := 0
	var rays := 0
	for side in 4:
		for along in range(-120, 121, 2):
			var point := Vector2(float(along), bounds.position.y if side == 0 else bounds.end.y)
			var direction := Vector2(0, -1 if side == 0 else 1)
			if side >= 2:
				point = Vector2(bounds.position.x if side == 2 else bounds.end.x, float(along))
				direction = Vector2(-1 if side == 2 else 1, 0)
			var start := data.get_height(Vector3(point.x, 0, point.y))
			var previous := start
			for distance in range(2, 113, 2):
				var p := point + direction * float(distance)
				var h := data.get_height(Vector3(p.x, 0, p.y))
				slope_violations += int(h > previous + 0.0001)
				if distance <= 12:
					plateau_violations += int(absf(h - start) > 0.002)
				previous = h
			rays += 1
	# 四角按每5度放射取样，平台/缓坡和侧边共用同一距离场。
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			for angle in range(0, 91, 5):
				var corner := Vector2(bounds.position.x if sx < 0 else bounds.end.x, bounds.position.y if sz < 0 else bounds.end.y)
				var direction := Vector2(sx * cos(deg_to_rad(float(angle))), sz * sin(deg_to_rad(float(angle))))
				var previous := data.get_height(Vector3(corner.x, 0, corner.y))
				for distance in range(2, 113, 2):
					var p := corner + direction * float(distance)
					var h := data.get_height(Vector3(p.x, 0, p.y))
					slope_violations += int(h > previous + 0.002)
					previous = h
				rays += 1
	check(slope_violations == 0, "四边四角全部放射缓坡单调")
	check(plateau_violations == 0, "轮廓外12m平台连续")
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "city_instances": city.get_child_count(),
		"ground_count": grounds.size(), "region_count": data.get_region_count(), "written_samples": total, "zero_samples": zeros,
		"invalid_samples": invalid, "height_mismatch": mismatch, "outer_samples": outer_count, "outer_wrong": outer_wrong,
		"height_range": [height_low, height_high], "max_neighbor_delta_m": max_neighbor_delta, "support_samples": support_samples,
		"penetrations": penetration, "penetration_examples": penetration_examples, "gap_examples": gap_examples,
		"gap_violations": gap_wrong, "bottom_gap_range_m": [min_gap, max_gap],
		"ordinary_thin_bottom_gap_range_m": [thin_gap_low, thin_gap_high], "profile_safety_transition_samples": profile_transition_samples,
		"profile_limit": "连续断面会进入部分厚坡道内部，但不盖住实际路面；运河邻接薄板安全过渡区不保证逐点0.15m贴底", 
		"min_surface_clearance_m": min_surface_clearance, "irregular_bottom_samples": irregular_bottom_samples,
		"irregular_bottom_gap_range_m": [irregular_bottom_gap_low, irregular_bottom_gap_high],
		"slope_rays": rays, "slope_violations": slope_violations,
		"platform_violations": plateau_violations, "collision_mode": seabed.collision_mode}
	FileAccess.open("res://outputs/seabed-scene-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	seabed.queue_free()
	city.queue_free()
	await process_frame
	print("[seabed-scene] ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
