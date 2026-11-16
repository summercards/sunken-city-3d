extends "res://src/building_attachments/forms.gd"

func _init(geometry: RefCounted, data: Dictionary) -> void:
	super(geometry, data)

func build() -> bool:
	match str(recipe.type_id):
		"tank_round_short": round_tank()
		"tank_tower_cone": return tower()
		"tank_horizontal": horizontal()
		"tank_rect": rect_tank()
		"pipe_downspout": downspout()
		"pipe_elbow": elbow()
		"pipe_t_valve": valve()
		"pipe_bundle": bundle()
		_:
			g.errors.append("水务不支持的类型：" + str(recipe.type_id))
			return false
	return g.errors.is_empty()

func round_tank() -> void:
	feet("round_tank", 0.14, 0.28)
	var radius: float = minf(d.x, d.z) * 0.43
	drum("round_tank_body", p(0, 0.52, 0), radius, d.y * 0.72, "SEA_Matte", Vector3.ZERO, condition > 0, condition * 2)
	if condition == 0:
		drum("round_tank_lid", p(0, 0.91, 0), radius * 0.94, d.y * 0.06, "SEA_Metal", Vector3.ZERO, false, 0, true, -0.035)
	else:
		drum("round_tank_torn_lip", p(0, 0.89, 0), radius * 0.96, d.y * 0.045, "SEA_Metal", Vector3.ZERO, true, condition * 2)
	drum("round_tank_bottom", p(0, 0.15, 0), radius * 1.01, d.y * 0.055)
	tube("round_tank_outlet", p(0.35, 0.22, 0), p(0.49, 0.22, 0), d.x * 0.045)
	if condition < 2:
		drum("round_tank_hatch", p(-0.12, 0.965, 0.06), radius * 0.22, d.y * 0.06)

func tower() -> bool:
	feet("tower", 0.53, 0.30, condition == 2)
	for side: int in [-1, 1]:
		bar("tower_cross_%d" % side, p(side * 0.30, 0.07, -0.3), p(side * 0.28, 0.49, 0.28), 0.055)
	var radius: float = minf(d.x, d.z) * 0.43
	drum("tower_tank", p(0, 0.69, 0), radius, d.y * 0.32, "SEA_Matte", Vector3.ZERO, condition > 0, condition * 2)
	drum("tower_floor", p(0, 0.52, 0), radius * 1.02, d.y * 0.035)
	# 锥顶由十片真实斜屋面组成；不将直筒改尺寸当成新类型。
	g.begin("tower_conical_roof", "SEA_Metal", p(0, 0.86, 0), Vector3(radius * 2.0, d.y * 0.13, radius * 2.0), Vector3.ZERO, "conical_roof", 0.05, true)
	g.active_part.bevel_segments = 0
	g.active_part.taper = 1.0
	g.active_part.rho = 1.0
	g.active_part.top = [0.0, d.y * 0.13, 0.0]
	g.active_part.taper_along = 1
	g.active_part.form_role = "functional_conical_cap"
	g.active_part.form_exception = "功能性锥顶收尖，实测rho=1；不适用普通体量或杆件线性收分约束"
	g.active_part.bevel_exception = "十片锥顶低面曲面，真实厚度"
	for i: int in range(10 - condition * 2):
		var a: float = TAU * i / 10.0
		var end: float = TAU * (i + 1) / 10.0
		var pa := Vector3(cos(a) * radius, 0, sin(a) * radius)
		var pb := Vector3(cos(end) * radius, 0, sin(end) * radius)
		var peak := Vector3(0, d.y * 0.13, 0)
		var thick := Vector3(0, -0.025, 0)
		g.triangle(pa, pb, peak, Vector3.UP)
		g.triangle(pa + thick, peak + thick, pb + thick, Vector3.DOWN)
		g.quad(pa, pa + thick, pb + thick, pb, Vector3(cos(a), 0, sin(a)))
		if condition > 0 and i == 0:
			g.quad(pa, peak, peak + thick, pa + thick, Vector3.FORWARD)
		if condition > 0 and i == 9 - condition * 2:
			g.quad(pb, pb + thick, peak + thick, peak, Vector3(-sin(end), 0, cos(end)))
		g.proxy([pa, pb, peak, pa + thick, pb + thick, peak + thick])
	tube("tower_drain", p(0.29, 0.52, 0.0), p(0.29, 0.08 + condition * 0.08, 0.0), d.x * 0.04)
	return g.errors.is_empty()

func horizontal() -> void:
	for x: float in [-0.3, 0.3]:
		b("horizontal_saddle_%s" % x, p(x, 0.12, 0), p(0.15, 0.24, 0.68), "SEA_Metal")
	var length: float = d.x * (0.90 - condition * 0.17)
	var center: Vector3 = p(-condition * 0.075, 0.59, 0)
	drum("horizontal_barrel", center, minf(d.y * 0.36, d.z * 0.44), length, "SEA_Matte", Vector3(0, 0, PI * 0.5), condition > 0, condition * 2)
	for x: float in [-0.28, 0.27]:
		drum("horizontal_band_%s" % x, p(x, 0.59, 0), minf(d.y * 0.37, d.z * 0.45), d.x * 0.035, "SEA_Metal", Vector3(0, 0, PI * 0.5), true, condition * 2)
	if condition < 2:
		drum("horizontal_hatch", p(-0.12, 0.96, 0), d.z * 0.12, d.y * 0.10)
	tube("horizontal_outlet", p(-0.44, 0.34, 0), p(-0.49, 0.20, 0), d.z * 0.055)

func rect_tank() -> void:
	feet("rect_tank", 0.14)
	b("rect_floor", p(-0.10 * condition, 0.17, 0), p(0.94 - 0.16 * condition, 0.08, 0.91), "SEA_Metal")
	b("rect_back", p(0, 0.57, 0.40), p(0.90, 0.73, 0.08))
	b("rect_left", p(-0.43, 0.57, 0), p(0.08, 0.73, 0.73))
	if condition < 2:
		b("rect_right", p(0.43, 0.57, 0.02), p(0.08, 0.73 - condition * 0.25, 0.68))
		b("rect_roof", p(-0.10 * condition, 0.96, 0), p(0.95 - condition * 0.30, 0.055, 0.90))
	for x_index: int in range(3):
		for y_index: int in range(2):
			if condition > 0 and x_index == 2:
				continue
			if condition == 2 and y_index == 1:
				continue
			b("rect_panel_%d_%d" % [x_index, y_index], p(-0.30 + x_index * 0.30, 0.37 + y_index * 0.36, -0.41), p(0.28, 0.33, 0.06))
	for y: float in [0.25, 0.80]:
		bar("rect_band_%s" % y, p(-0.45, y, -0.45), p(0.45 - condition * 0.18, y, -0.45), 0.03)
	if condition < 2:
		drum("rect_hatch", p(-0.2, 0.998, 0), d.x * 0.11, d.y * 0.035)

func downspout() -> void:
	var radius: float = d.x * 0.15
	# 漏斗口为开口变径短管，出口分段并保留可见内壁。
	g.round_part("downspout_funnel", p(0, 0.91, 0.04), radius, radius * 1.08, d.y * 0.15, "SEA_Matte", Vector3.ZERO, true, condition, true)
	if condition == 0:
		tube("downspout_main", p(0, 0.83, 0.04), p(0, 0.12, 0.04), radius)
	else:
		tube("downspout_upper_broken", p(0, 0.83, 0.04), p(0, 0.48 + 0.08 * condition, 0.04), radius, condition)
		if condition == 1:
			tube("downspout_lower_broken", p(0, 0.41, 0.04), p(0, 0.12, 0.04), radius)
	if condition < 2:
		tube("downspout_kick", p(0, 0.12, 0.04), p(0.27, 0.025, -0.35), radius)
	for y: float in [0.25, 0.72]:
		drum("downspout_clamp_%s" % y, p(0, y, 0.04), radius * 1.13, d.y * 0.025, "SEA_Metal", Vector3.ZERO, true)
		bar("downspout_wall_tie_%s" % y, p(0, y, 0.20), p(0, y, 0.49), 0.08)

func elbow() -> void:
	var path: Array[Vector3] = [p(-0.45, 0.17, 0), p(-0.12, 0.17, 0), p(0.14, 0.30, 0), p(0.31, 0.55, 0), p(0.31, 0.94, 0)]
	for i: int in range(4):
		if condition > 0 and i == 2:
			continue
		if condition == 2 and i == 1:
			continue
		tube("elbow_segment_%d" % i, path[i], path[i + 1], d.z * 0.30, condition if i == 1 else 0)
	# 接头圈在转角截面，用开放环而不是实心堵头。
	drum("elbow_left_flange", p(-0.44, 0.17, 0), d.z * 0.43, d.x * 0.04, "SEA_Matte", Vector3(0, 0, PI * 0.5), true)
	drum("elbow_top_flange", p(0.31, 0.94, 0), d.z * 0.43, d.y * 0.04, "SEA_Metal", Vector3.ZERO, true, condition)

func valve() -> void:
	var radius: float = d.z * 0.18
	tube("valve_left", p(-0.46, 0.30, 0), p(-0.06, 0.30, 0), radius)
	tube("valve_right", p(0.06, 0.30, 0), p(0.46 - condition * 0.12, 0.30, 0), radius, condition)
	drum("valve_body", p(0, 0.32, 0), radius * 1.5, d.y * 0.26, "SEA_Matte")
	tube("valve_branch", p(0, 0.38, 0), p(0, 0.72 - condition * 0.05, 0), radius * 0.75)
	var wheel_y: float = 0.85 - condition * 0.05
	var shaft_bottom: float = 0.68 - condition * 0.05
	drum("valve_shaft", p(0, (shaft_bottom + wheel_y) * 0.5, 0), radius * 0.72, d.y * (wheel_y - shaft_bottom + 0.015))
	g.require_connection("valve_branch", p(0, 0.70 - condition * 0.05, 0) + Vector3(radius * 0.65, 0, 0))
	drum("valve_handwheel", p(0, wheel_y, 0), d.z * 0.42, d.y * 0.045, "SEA_Metal", Vector3.ZERO, true, condition * 2)
	for i: int in range(3 - condition):
		var a: float = TAU * i / 3.0
		var end: Vector3 = p(0, wheel_y, 0) + Vector3(cos(a), 0, sin(a)) * d.z * 0.38
		bar("valve_spoke_%d" % i, p(0, wheel_y, 0), end, 0.035)
		g.require_connection("valve_shaft", p(0, wheel_y, 0))
		g.require_connection("valve_handwheel", end)

func bundle() -> void:
	for i: int in range(3):
		var x: float = -0.31 + i * 0.31
		var end_y: float = 0.91 - i * 0.07
		if condition == 2:
			end_y = 0.42 + i * 0.15
		if condition == 1 and i == 1:
			tube("bundle_%d_lower" % i, p(x, 0.04, 0), p(x, 0.43, 0), d.x * 0.065)
			tube("bundle_%d_upper" % i, p(x, 0.55, 0), p(x, end_y, 0), d.x * 0.065, 1)
		else:
			tube("bundle_%d_main" % i, p(x, 0.04, 0), p(x, end_y, 0), d.x * 0.065, 1 if condition == 2 else 0)
		if condition < 2:
			tube("bundle_%d_offset" % i, p(x, end_y, 0), p(x + 0.08, end_y + 0.06, -0.28 + i * 0.08), d.x * 0.065)
	for y: float in [0.2, 0.72]:
		bar("bundle_wall_rail_%s" % y, p(-0.43, y, 0.36), p(0.43 - condition * 0.13, y, 0.36), 0.075)
		for i: int in range(3):
			var x: float = -0.31 + i * 0.31
			bar("bundle_tie_%s_%d" % [y, i], p(x, y, 0.08), p(x, y, 0.35), 0.045, "SEA_Matte")
