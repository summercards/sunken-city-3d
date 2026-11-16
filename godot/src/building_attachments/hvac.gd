extends "res://src/building_attachments/forms.gd"

func _init(geometry: RefCounted, data: Dictionary) -> void:
	super(geometry, data)

func build() -> bool:
	match str(recipe.type_id):
		"ac_wall_single": wall_ac(false)
		"ac_wall_twin": wall_ac(true)
		"ac_roof_upflow": roof_ac()
		"fan_wall": wall_fan()
		"utility_junction": junction()
		"utility_meter_pair": meters()
		"satellite_dish": return satellite()
		"tv_antenna": antenna()
		_:
			g.errors.append("HVAC不支持的类型：" + str(recipe.type_id))
			return false
	return g.errors.is_empty()

func wall_ac(twin: bool) -> void:
	wall_brackets("ac_bracket", 0.33, 0.08, 0.75)
	b("ac_lower_pan", p(0, 0.2, -0.03), p(0.93, 0.12, 0.75), "SEA_Metal")
	b("ac_back", p(0, 0.56, 0.29), p(0.91, 0.62, 0.09))
	b("ac_left_shell", p(-0.45, 0.56, -0.03), p(0.08, 0.67, 0.7))
	if condition < 2:
		b("ac_top_cover", p(-condition * 0.1, 0.9, -0.03), p(0.94 - condition * 0.23, 0.09, 0.75))
	if condition == 0:
		b("ac_right_shell", p(0.45, 0.56, -0.03), p(0.08, 0.66, 0.7))
	if twin:
		fan("ac_left_fan", p(-0.24, 0.55, -0.35), minf(d.x * 0.20, d.y * 0.30), d.z * 0.14)
		if condition < 2:
			fan("ac_right_fan", p(0.24, 0.55, -0.35), minf(d.x * 0.20, d.y * 0.30), d.z * 0.14)
		else:
			bar("ac_right_empty_diagonal", p(0.04, 0.26, 0.0), p(0.40, 0.81, 0.0), 0.07)
		b("ac_central_partition", p(0, 0.53, 0), p(0.035, 0.57, 0.58), "SEA_Metal")
	else:
		fan("ac_single_fan", p(0.14, 0.55, -0.35), minf(d.x * 0.26, d.y * 0.30), d.z * 0.14)
		slats("ac_service_slats", p(-0.31, 0.55, -0.34), d.x * 0.17, d.y * 0.43, d.z * 0.08, 4)
		drum("ac_compressor", p(-0.32, 0.41, 0.0), d.x * 0.105, d.y * 0.35)
	tube("ac_drain", p(-0.32, 0.17, 0.03), p(-0.32, 0.015, 0.03), d.x * 0.025)

func roof_ac() -> void:
	feet("roof_ac", 0.18)
	b("roof_ac_pan", p(0, 0.20, 0), p(0.91, 0.09, 0.87), "SEA_Metal")
	b("roof_ac_rear", p(0, 0.54, 0.39), p(0.88, 0.59, 0.08))
	for side: int in [-1, 1]:
		if condition == 2 and side == 1:
			continue
		b("roof_ac_side_%d" % side, p(side * 0.42, 0.55, 0), p(0.07, 0.60, 0.75))
	fan("roof_ac_upflow", p(-0.11, 0.88, 0.0), minf(d.x, d.z) * 0.30, d.y * 0.11, true)
	slats("roof_ac_heat_exchanger", p(-0.1, 0.52, -0.39), d.x * 0.65, d.y * 0.42, d.z * 0.07, 6)
	drum("roof_ac_compressor", p(0.27, 0.47, 0), d.x * 0.12, d.y * 0.43)
	if condition > 0:
		bar("roof_ac_bent_cover", p(-0.43, 0.82, -0.35), p(0.12, 0.70 - 0.08 * condition, -0.39), 0.055)

func wall_fan() -> void:
	frame("wall_fan_mount", p(0, 0.51, 0.23), d.x * 0.86, d.y * 0.85, d.x * 0.07, d.z * 0.19, condition)
	fan("wall_axial", p(0, 0.5, -0.13), minf(d.x, d.y) * 0.44, d.z * 0.60)
	for side: int in [-1, 1]:
		bar("wall_fan_tie_%d" % side, p(side * 0.31, 0.17, 0.25), p(0, 0.5, 0.07), 0.065)

func junction() -> void:
	b("junction_back", p(0, 0.57, 0.31), p(0.84, 0.70, 0.10), "SEA_Metal")
	b("junction_left", p(-0.43, 0.55, 0), p(0.08, 0.73, 0.59))
	if condition < 2:
		b("junction_door", p(-0.07 * condition, 0.56 - 0.08 * condition, -0.32), p(0.78 - 0.18 * condition, 0.65 - 0.18 * condition, 0.1), "SEA_Matte", Vector3(0, 0.08 * condition, 0))
		b("junction_latch", p(0.25, 0.48, -0.42), p(0.08, 0.18, 0.06), "SEA_Metal")
	b("junction_sloping_cap", p(0, 0.93, 0), p(0.96, 0.10, 0.83), "SEA_Metal", Vector3(0.12, 0, 0))
	b("junction_cable_entry", p(0, 0.235, 0.12), p(0.77, 0.075, 0.43), "SEA_Metal")
	g.require_connection("junction_back", p(0, 0.235, 0.285))
	for i: int in range(3):
		b("junction_terminal_%d" % i, p(-0.24 + i * 0.24, 0.55, 0.12), p(0.11, 0.16, 0.12), "SEA_Metal")
		tube("junction_lower_wire_%d" % i, p(-0.24 + i * 0.24, 0.25, 0.02), p(-0.24 + i * 0.24, 0.01 + 0.03 * condition * i, 0.1), d.x * 0.025)
		var wire_axis: Vector3 = (p(0, 0.01 + 0.03 * condition * i, 0.1) - p(0, 0.25, 0.02)).normalized()
		var radial: Vector3 = Vector3.RIGHT * d.x * 0.023
		g.require_connection("junction_cable_entry", p(-0.24 + i * 0.24, 0.25, 0.02) + wire_axis * d.y * 0.012 + radial)

func meters() -> void:
	b("meter_mounting_board", p(0, 0.61, 0.34), p(0.95, 0.62, 0.09))
	for side: int in [-1, 1]:
		var x: float = side * 0.24
		var damage: int = condition if side == 1 else 0
		drum("meter_ring_%d" % side, p(x, 0.65, -0.05), d.x * 0.20, d.z * 0.50, "SEA_Metal", Vector3(PI * 0.5, 0, 0), true, damage * 2)
		if damage < 2:
			drum("meter_face_%d" % side, p(x, 0.65, -0.34), d.x * 0.15, d.z * 0.045, "SEA_Gloss", Vector3(PI * 0.5, 0, 0), false, 0, false)
			bar("meter_pointer_%d" % side, p(x, 0.65, -0.4), p(x + 0.08, 0.73 - damage * 0.06, -0.4), 0.035)
		tube("meter_conduit_%d" % side, p(x, 0.39, 0.12), p(x, 0.03 + 0.05 * damage, 0.12), d.x * 0.04)
	b("meter_bottom_bus", p(0, 0.13, 0.12), p(0.75 - 0.12 * condition, 0.13, 0.25), "SEA_Metal")

func satellite() -> bool:
	feet("dish_tripod", 0.35, 0.22, condition == 2)
	bar("dish_mast", p(0, 0.28, 0.17), p(0, 0.66, 0.10), 0.09)
	# 双面凹碟按同心环带建模；不是缩放圆盘或球体。
	var center: Vector3 = p(0, 0.63, 0.03)
	var radius: float = d.x * 0.47
	g.begin("dish_concave_shell", "SEA_Matte", center, Vector3(radius * 2, radius * 2, d.z * 0.2), Vector3(-0.28, 0, 0), "original_concave_dish", 0.035, true)
	g.active_part.radial_segments = 10
	g.active_part.bevel_segments = 0
	g.active_part.bevel_exception = "原创十段碟曲面，真实双层厚度"
	var segments: int = 10 - condition * 2
	for ring: int in range(2):
		var r0: float = radius * (0.07 + ring * 0.465)
		var r1: float = radius * (0.535 + ring * 0.465)
		var z0: float = -0.19 * d.z * pow(r0 / radius, 2)
		var z1: float = -0.19 * d.z * pow(r1 / radius, 2)
		for i: int in range(segments):
			var aa: float = TAU * i / 10.0
			var ab: float = TAU * (i + 1) / 10.0
			var a := Vector3(cos(aa) * r0, sin(aa) * r0, z0)
			var end := Vector3(cos(ab) * r0, sin(ab) * r0, z0)
			var c := Vector3(cos(ab) * r1, sin(ab) * r1, z1)
			var e := Vector3(cos(aa) * r1, sin(aa) * r1, z1)
			var thick := Vector3(0, 0, 0.025)
			g.quad(a, end, c, e, Vector3.FORWARD)
			g.quad(a + thick, e + thick, c + thick, end + thick, Vector3.BACK)
			if ring == 1:
				g.quad(e, c, c + thick, e + thick, Vector3(cos(aa), sin(aa), 0))
			if ring == 0:
				g.quad(a, a + thick, end + thick, end, Vector3(-cos(aa), -sin(aa), 0))
			if condition > 0 and i == 0:
				g.quad(a, e, e + thick, a + thick, Vector3.DOWN)
			if condition > 0 and i == segments - 1:
				g.quad(end, end + thick, c + thick, c, Vector3(-sin(ab), cos(ab), 0))
			g.proxy([a, end, c, e, a + thick, end + thick, c + thick, e + thick])
	bar("dish_feed_arm", p(0, 0.39, 0), p(0, 0.55 - condition * 0.06, -0.45 + condition * 0.10), 0.065)
	if condition < 2:
		drum("dish_feed", p(0, 0.57 - condition * 0.06, -0.45 + condition * 0.10), d.x * 0.055, d.y * 0.1, "SEA_Metal", Vector3(PI * 0.5, 0, 0))
	return g.errors.is_empty()

func antenna() -> void:
	feet("antenna", 0.18, 0.19)
	b("antenna_base", p(0, 0.17, 0), p(0.45, 0.08, 0.45), "SEA_Metal")
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			g.require_connection("antenna_leg_%d_%d" % [sx, sz], p(sx * 0.19 * 0.91, 0.18, sz * 0.19 * 0.91))
	bar("antenna_mast", p(0, 0.07, 0), p(0, 0.95 - condition * 0.12, 0), 0.048)
	g.require_connection("antenna_base", p(0, 0.17, 0))
	bar("antenna_spine", p(0, 0.83, -0.47), p(0, 0.83 - condition * 0.035, 0.46 - condition * 0.14), 0.046)
	for i: int in range(6 - condition):
		if condition == 2 and i == 1:
			continue
		var z: float = -0.4 + i * 0.16
		var half: float = 0.43 - i * 0.045
		var broken: float = 0.45 if condition > 0 and i % 2 == 1 else 1.0
		bar("antenna_element_%d" % i, p(-half, 0.83, z), p(half * broken, 0.83 - 0.04 * condition * (1.0 - broken), z), 0.025)
	tube("antenna_cable", p(0.025, 0.78, 0.04), p(0.025, 0.10 + condition * 0.04, 0.04), minf(d.x, d.z) * 0.012)
