extends "res://src/building_attachments/forms.gd"

func _init(geometry: RefCounted, data: Dictionary) -> void:
	super(geometry, data)

func build() -> bool:
	match str(recipe.type_id):
		"duct_straight": straight_duct()
		"duct_elbow": elbow_duct()
		"vent_louver": louver()
		"vent_mushroom": return mushroom()
		"chimney": chimney()
		"awning_slope": slope_awning()
		"awning_barrel": barrel_awning()
		"canopy_entry": canopy()
		_:
			g.errors.append("棚架通风不支持的类型：" + str(recipe.type_id))
			return false
	return g.errors.is_empty()

func duct_section(name: String, center: Vector3, width: float, height: float, length: float, rotation: Vector3 = Vector3.ZERO, broken: int = 0) -> void:
	var basis: Basis = Basis.from_euler(rotation)
	var wall: float = minf(width, height) * 0.075
	var side_height: float = height * 0.83
	var side_width: float = width * 0.83
	for side: int in [-1, 1]:
		if broken == 2 and side == 1:
			continue
		b(name + "_side_%d" % side, center + basis * Vector3(side * width * 0.46, 0, 0), Vector3(wall, side_height, length), "SEA_Matte", rotation)
		if broken > 0 and side == 1:
			continue
		b(name + "_horizontal_%d" % side, center + basis * Vector3(0, side * height * 0.46, 0), Vector3(side_width, wall, length), "SEA_Metal", rotation)
	# 四条实心角缝做斜切，空腔没有总包围代理。
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			if broken > 0 and sx == 1 and sy == 1:
				continue
			var bevel_rotation: Basis = basis * Basis(Vector3.BACK, sx * sy * PI * 0.25)
			b(name + "_corner_%d_%d" % [sx, sy], center + basis * Vector3(sx * width * 0.418, sy * height * 0.418, 0), Vector3(wall, wall * 1.6, length), "SEA_Metal", bevel_rotation.get_euler())

func straight_duct() -> void:
	var center: Vector3 = p(0, 0.5, -condition * 0.10)
	var length: float = d.z * (0.9 - condition * 0.2)
	duct_section("straight_duct", center, d.x * 0.9, d.y * 0.85, length, Vector3.ZERO, condition)
	for side: int in [-1, 1]:
		var first: int = g.parts.size()
		var end_z: float = center.z + side * (length * 0.5 - d.z * 0.015)
		frame("straight_duct_flange_%d" % side, Vector3(0, center.y, end_z), d.x * 0.84, d.y * 0.80, d.y * 0.065, d.z * 0.035, condition if side == 1 else 0)
		var left: Dictionary = g.parts[first]
		g.active_part = left
		g.require_connection("straight_duct_side_-1", Vector3(-d.x * 0.9 * 0.46, center.y, end_z))

func elbow_duct() -> void:
	duct_section("elbow_duct_in", p(-0.22, 0.5, 0.22), d.x * 0.42, d.y * 0.85, d.z * 0.51, Vector3.ZERO, condition)
	duct_section("elbow_duct_out", p(0.22, 0.5, -0.22), d.z * 0.42, d.y * 0.85, d.x * (0.51 - condition * 0.09), Vector3(0, PI * 0.5, 0), condition)
	bar("elbow_outer_fold", p(-0.44, 0.94, 0.03), p(-0.03 + condition * 0.10, 0.94 - condition * 0.05, -0.44), 0.05)
	frame("elbow_inlet_flange", p(-0.22, 0.5, 0.48), d.x * 0.46, d.y * 0.91, d.y * 0.06, d.z * 0.035, condition)

func louver() -> void:
	frame("louver_outer_frame", p(0, 0.5, 0.17), d.x * 0.90, d.y * 0.87, d.y * 0.09, d.z * 0.57, condition)
	slats("louver_blade", p(0, 0.5, -0.04), d.x * 0.80, d.y * 0.73, d.z * 0.60, 6)
	bar("louver_middle_stay", p(0, 0.09, 0.19), p(0, 0.92 - condition * 0.24, 0.19), 0.055)

func mushroom() -> bool:
	drum("mushroom_base", p(0, 0.055, 0), d.x * 0.32, d.y * 0.11)
	drum("mushroom_neck", p(0, 0.42 - condition * 0.05, 0), d.x * 0.19, d.y * (0.62 - condition * 0.10), "SEA_Metal", Vector3.ZERO, true, condition)
	var cap_y: float = 0.80 - condition * 0.10
	var neck_length: float = d.y * (0.62 - condition * 0.10)
	var neck_top: float = d.y * (0.73 - condition * 0.10)
	var neck_wall: float = minf(d.x * 0.19 * 0.17, 0.045)
	var neck_radius: float = (d.x * 0.19 * (1.0 - 0.05 * (1.0 - d.y * 0.04 / neck_length)) - neck_wall * 0.5) * cos(PI / 10.0)
	var cap_points: Array[Vector3] = []
	for i: int in range(4 - condition):
		# 取存活扇片中点，连接点嵌入实际颈壁与帽壳厚度中部。
		var angle: float = TAU * (i * 2 + 0.5) / 10.0
		var a := Vector3(cos(angle) * neck_radius, neck_top - d.y * 0.04, sin(angle) * neck_radius)
		var end: Vector3 = p(cos(angle) * 0.25 * cos(PI / 10.0), cap_y + 0.17 * (1.0 - 0.25 / 0.48), sin(angle) * 0.25 * cos(PI / 10.0)) + Vector3.DOWN * 0.0125
		cap_points.append(end)
		bar("mushroom_hat_stay_%d" % i, a, end, 0.04)
		g.require_connection("mushroom_neck", a)
		g.require_connection("mushroom_cap", end)
	# 帽顶为十段浅圆锥，半径明显大于开口颈管。
	g.begin("mushroom_cap", "SEA_Matte", p(0, cap_y, 0), p(0.98, 0.2, 0.98), Vector3.ZERO, "low_conical_cap", 0.05, true)
	g.require_connection("mushroom_hat_stay_0", cap_points[0])
	g.active_part.bevel_segments = 0
	g.active_part.bevel_exception = "十段实体薄锥帽，保留帽檐厚度"
	g.active_part.taper = 1.0
	g.active_part.rho = 1.0
	g.active_part.top = [0.0, d.y * 0.17, 0.0]
	g.active_part.taper_along = 1
	g.active_part.form_role = "functional_conical_cap"
	g.active_part.form_exception = "功能性锥帽收尖，实测rho=1；不适用普通体量或杆件线性收分约束"
	for i: int in range(10 - condition * 2):
		var aa: float = TAU * i / 10.0
		var ab: float = TAU * (i + 1) / 10.0
		var a: Vector3 = p(cos(aa) * 0.48, 0, sin(aa) * 0.48)
		var end: Vector3 = p(cos(ab) * 0.48, 0, sin(ab) * 0.48)
		var peak: Vector3 = p(0, 0.17, 0)
		var thickness := Vector3(0, -0.025, 0)
		g.triangle(a, end, peak, Vector3.UP)
		g.triangle(a + thickness, peak + thickness, end + thickness, Vector3.DOWN)
		g.quad(a, a + thickness, end + thickness, end, Vector3(cos(aa), 0, sin(aa)))
		if condition > 0 and i == 0:
			g.quad(a, peak, peak + thickness, a + thickness, Vector3.FORWARD)
		if condition > 0 and i == 9 - condition * 2:
			g.quad(end, end + thickness, peak + thickness, peak, Vector3(-sin(ab) * d.z, 0, cos(ab) * d.x))
		g.proxy([a, end, peak, a + thickness, end + thickness, peak + thickness])
	return g.errors.is_empty()

func chimney() -> void:
	b("chimney_plinth", p(0, 0.06, 0), p(0.98, 0.12, 0.97), "SEA_Metal")
	var height: float = 0.79 - condition * 0.20
	b("chimney_back", p(0, 0.14 + height * 0.5, 0.31), p(0.67, height, 0.10))
	b("chimney_left", p(-0.32, 0.14 + height * 0.5, 0), p(0.10, height, 0.51))
	if condition < 2:
		b("chimney_right", p(0.32, 0.14 + height * 0.5, 0), p(0.10, height - 0.10 * condition, 0.51))
	b("chimney_front", p(-0.05 * condition, 0.14 + height * 0.5, -0.31), p(0.67 - condition * 0.13, height * (1.0 - 0.12 * condition), 0.10))
	for x: float in [-0.36, 0.36]:
		if condition == 2 and x > 0:
			continue
		b("chimney_lip_x_%s" % x, p(x, 0.17 + height, 0), p(0.12, 0.065, 0.76), "SEA_Metal")
	for z: float in [-0.36, 0.36]:
		b("chimney_lip_z_%s" % z, p(-condition * 0.06, 0.17 + height, z), p(0.70 - condition * 0.14, 0.065, 0.12), "SEA_Metal")

func slope_awning() -> void:
	wall_brackets("awning", 0.37, 0.05, 0.90)
	for i: int in range(7):
		if condition == 1 and i in [2, 5]:
			continue
		if condition == 2 and i not in [0, 1, 6]:
			continue
		b("awning_slope_strip_%d" % i, p(-0.43 + i * 0.143, 0.63, -0.02), p(0.134, 0.07, 0.95), "SEA_Matte" if i % 2 == 0 else "SEA_Metal", Vector3(-0.30, 0, 0))
	bar("awning_front_bar", p(-0.49, 0.37, -0.48), p(0.49 - condition * 0.17, 0.37 - condition * 0.05, -0.48), 0.07)
	bar("awning_wall_rail", p(-0.49, 0.89, 0.43), p(0.49, 0.89, 0.43), 0.08)

func arch_strip(name: String, x: float, width: float, missing_start: int = -1, missing_end: int = -1, role: String = "SEA_Matte") -> void:
	# 六片厚板组成拱形剖面，各片实际旋转而非平盒拉长。
	for segment: int in range(6):
		if segment >= missing_start and segment <= missing_end:
			continue
		var aa: float = PI * float(segment) / 6.0
		var ab: float = PI * float(segment + 1) / 6.0
		var za: float = cos(aa) * d.z * 0.46
		var zb: float = cos(ab) * d.z * 0.46
		var ya: float = d.y * (0.24 + sin(aa) * 0.68)
		var yb: float = d.y * (0.24 + sin(ab) * 0.68)
		var mid := Vector3(x, (ya + yb) * 0.5, (za + zb) * 0.5)
		var length: float = Vector2(ya - yb, za - zb).length() - CLEARANCE
		var rotation := Vector3(-atan2(yb - ya, zb - za), 0, 0)
		b(name + "_%d" % segment, mid, Vector3(width, d.y * 0.04, length), role, rotation)

func barrel_awning() -> void:
	for i: int in range(5):
		if condition == 2 and i in [1, 2, 3]:
			continue
		arch_strip("barrel_panel_%d" % i, (-0.4 + i * 0.2) * d.x, d.x * 0.19, 2 if condition > 0 and i == 2 else -1, 4 if condition > 0 and i == 2 else -1, "SEA_Matte" if i % 2 == 0 else "SEA_Metal")
	for side: int in [-1, 1]:
		arch_strip("barrel_rib_%d" % side, d.x * side * 0.49, d.x * 0.035, 2 if condition == 2 and side == 1 else -1, 3 if condition == 2 and side == 1 else -1, "SEA_Metal")
	bar("barrel_rear_wall_bar", p(-0.48, 0.25, 0.48), p(0.48, 0.25, 0.48), 0.07)

func canopy() -> void:
	for side: int in [-1, 1]:
		b("canopy_pad_%d" % side, p(side * 0.40, 0.02, -0.36), p(0.15, 0.04, 0.17), "SEA_Metal")
		bar("canopy_front_column_%d" % side, p(side * 0.40, 0.04, -0.36), p(side * 0.39, 0.80 - condition * 0.02 * maxi(side, 0), -0.36), 0.095, "SEA_Matte")
		bar("canopy_side_rail_%d" % side, p(side * 0.39, 0.79, -0.42), p(side * 0.39, 0.79, 0.47), 0.075)
		bar("canopy_wall_tie_%d" % side, p(side * 0.39, 0.80, 0.43), p(side * 0.39, 0.58, 0.43), 0.065)
	for side: int in [-1, 1]:
		if condition == 2 and side == 1:
			continue
		for i: int in range(3):
			if condition == 1 and side == 1 and i == 0:
				continue
			var x: float = side * (0.08 + i * 0.16)
			var y: float = 0.98 - absf(x) * 0.34
			b("canopy_roof_%d_%d" % [side, i], p(x, y, 0), p(0.155, 0.035, 0.98), "SEA_Matte", Vector3(0, 0, -side * 0.31))
	bar("canopy_ridge", p(0, 0.995, -0.49), p(0, 0.995 - 0.08 * condition, 0.49 - 0.17 * condition), 0.065)
	bar("canopy_front_lintel", p(-0.46, 0.79, -0.39), p(0.46 - condition * 0.08, 0.79, -0.39), 0.08)
