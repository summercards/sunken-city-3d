extends "res://src/building_attachments/forms.gd"

const Glyphs = preload("res://src/building_attachments/glyphs.gd")
var text_stats: Array[Dictionary] = []

func _init(geometry: RefCounted, data: Dictionary) -> void:
	super(geometry, data)

func build() -> bool:
	match str(recipe.type_id):
		"sign_fascia": fascia()
		"sign_vertical": vertical()
		"sign_projecting": projecting()
		"sign_rooftop": rooftop()
		"sign_letters": letters()
		"sign_lightbox": lightbox()
		"sign_arrow": arrow()
		"sign_hanging": hanging()
		_:
			g.errors.append("招牌不支持的类型：" + str(recipe.type_id))
			return false
	style_trim()
	return g.errors.is_empty()

func text_at(center: Vector3, width: float, height: float, host: String, rotation: Vector3 = Vector3.ZERO, is_vertical: bool = false) -> void:
	var depth: float = maxf(0.025, minf(d.z * 0.15, 0.095))
	var basis: Basis = Basis.from_euler(rotation)
	var suffix: String = "%02d" % text_stats.size()
	var support: String = "text_carrier_" + suffix
	var bridge: String = "text_carrier_mount_" + suffix
	var back: Vector3 = center + basis.z * depth * 0.55
	var host_center := Vector3.ZERO
	var found: bool = false
	for part: Dictionary in g.parts:
		if part.name == host:
			host_center = Vector3(float(part.center[0]), float(part.center[1]), float(part.center[2]))
			if part.kind == "original_extruded_polygon":
				host_center.x = center.x
				host_center.y = center.y
			found = true
	if not found:
		g.errors.append("承字板缺少保留宿主：" + host)
		return
	# 全档保留薄承字板，文字每笔后缘嵌入；破损只作用于外饰板域。
	g.box(support, back, Vector3(width * 1.08, height * 1.10, depth * 0.5), "SEA_Matte", rotation, true, 0.035, true, 2)
	g.active_part.support_for_text = true
	g.active_part.damage_policy = "preserved_text_load_path"
	g.require_connection(bridge, back)
	g.beam(bridge, back, host_center, maxf(0.012, depth * 0.6), "SEA_Metal")
	g.require_connection(host, host_center)
	text_stats.append(Glyphs.add(g, recipe.text, center, width, height, depth, rotation, is_vertical, "SEA_Gloss", support))

func board(name: String, center: Vector3, width: float, height: float, depth: float) -> void:
	# 三段实体板留真实缺口，不用重着色冒充损坏。
	for i: int in range(3):
		if condition == 2 and i == 2:
			continue
		var x: float = center.x + (float(i) - 1.0) * width / 3.0
		var h: float = height * (0.67 if condition > 0 and i == 2 else 1.0)
		b(name + "_%d" % i, Vector3(x, center.y - (height - h) * 0.5, center.z), Vector3(width / 3.0 - CLEARANCE, h, depth))
		if i > 0:
			g.contact(name + "_%d" % (i - 1))

func fascia() -> void:
	board("fascia_board", p(0, 0.5, 0), d.x * 0.94, d.y * 0.82, d.z * 0.48)
	frame("fascia_rim", p(0, 0.5, -0.27), d.x * 0.92, d.y * 0.83, d.y * 0.08, d.z * 0.16, condition)
	bar("rear_rail", p(-0.4, 0.5, 0.4), p(0.4 - 0.13 * condition, 0.5, 0.4), 0.10)
	for x: float in [-0.33, 0.33]:
		bar("rear_standoff_%s" % x, p(x, 0.5, 0.24), p(x, 0.5, 0.42), 0.09)
	text_at(p(0, 0.49, -0.38), d.x * 0.78, d.y * 0.63, "fascia_board_1")

func vertical() -> void:
	for i: int in range(4):
		if condition == 2 and i == 0:
			continue
		b("vertical_board_%d" % i, p(0, 0.13 + i * 0.24, 0), p(0.78, 0.23, 0.48))
	for side: int in [-1, 1]:
		bar("vertical_side_%d" % side, p(side * 0.45, 0.08, -0.1), p(side * 0.43, 0.95 - 0.13 * condition * maxi(side, 0), -0.1), 0.075)
	for y: float in [0.19, 0.81]:
		bar("vertical_wall_%s" % y, p(0, y, 0.23), p(0, y, 0.49), 0.11)
	text_at(p(0, 0.51, -0.38), d.x * 0.62, d.y * 0.8, "vertical_board_2", Vector3.ZERO, true)

func projecting() -> void:
	# 牌面沿YZ，正反两面都是真实字形，但共享最终角色网格。
	b("projecting_spine", p(0, 0.42, -0.13), p(0.25, 0.78 if condition < 2 else 0.48, 0.72))
	for x_side: int in [-1, 1]:
		var side: float = float(x_side)
		var center: Vector3 = p(side * 0.22, 0.43, -0.13)
		var rotation := Vector3(0, -side * PI * 0.5, 0)
		text_at(center, d.z * 0.61, d.y * 0.52, "projecting_spine", rotation)
	bar("projecting_wall_plate", p(0, 0.1, 0.47), p(0, 0.95, 0.47), 0.12)
	bar("projecting_upper_arm", p(0, 0.87, 0.46), p(0, 0.87, -0.48), 0.11)
	bar("projecting_lower_arm", p(0, 0.19, 0.46), p(0, 0.19 - condition * 0.035, -0.39 + condition * 0.1), 0.10)
	bar("projecting_front_rail", p(0, 0.08, -0.5), p(0, 0.83 - condition * 0.14, -0.5), 0.08)

func rooftop() -> void:
	var y: float = 0.65
	board("rooftop_board", p(0, y, -0.25), d.x * 0.94, d.y * 0.55, d.z * 0.15)
	frame("rooftop_rim", p(0, y, -0.35), d.x * 0.93, d.y * 0.55, d.y * 0.035, d.z * 0.09, condition)
	for side: int in [-1, 1]:
		var x: float = float(side) * 0.34
		bar("rooftop_post_%d" % side, p(x, 0.025, -0.25), p(x, 0.93 - 0.12 * condition, -0.25), 0.08)
		bar("rooftop_foot_%d" % side, p(x, 0.025, -0.45), p(x, 0.025, 0.45), 0.10)
		bar("rooftop_diagonal_%d" % side, p(x, 0.04, 0.42), p(x, 0.75 - condition * 0.12, -0.20), 0.07)
	text_at(p(0, y, -0.43), d.x * 0.78, d.y * 0.39, "rooftop_board_1")

func letters() -> void:
	# 保留完整承字背轨与薄底载；外饰轨道仍可破损，不能删承字路径。
	b("letters_spine", p(0, 0.55, 0.21), p(1.0, 0.09, 0.09), "SEA_Metal")
	for side: int in [-1, 1]:
		bar("letters_load_post_%d" % side, p(side * 0.31, 0.0, 0.21), p(side * 0.31, 0.55, 0.21), 0.06)
		g.require_connection("letters_spine", p(side * 0.31, 0.55, 0.21))
	text_at(p(0, 0.55, -0.16), d.x * 0.96, d.y * 0.86, "letters_spine")
	for i: int in range(3 - condition):
		bar("letters_rail_%d" % i, p(-0.47, 0.15 + i * 0.25, 0.21), p(0.45 - condition * 0.08, 0.15 + i * 0.25, 0.21), 0.10)
	for side: int in [-1, 1]:
		bar("letters_mount_%d" % side, p(side * 0.31, 0.0, 0.3), p(side * 0.31, 0.68 - 0.13 * condition, 0.24), 0.10)

func lightbox() -> void:
	board("lightbox_face", p(0, 0.5, -0.32), d.x * 0.88, d.y * 0.78, d.z * 0.11)
	frame("lightbox_shell", p(0, 0.5, 0.0), d.x * 0.9, d.y * 0.82, d.y * 0.1, d.z * 0.72, condition)
	for i: int in range(3 - condition):
		b("lightbox_glow_%d" % i, p(-0.3 + i * 0.3, 0.86, -0.39), p(0.23, 0.035, 0.05), "SEA_Emission" if condition < 2 else "SEA_Metal")
	bar("lightbox_back", p(-0.35, 0.5, 0.45), p(0.35, 0.5, 0.45), 0.1)
	text_at(p(0, 0.49, -0.43), d.x * 0.76, d.y * 0.59, "lightbox_face_1")

func arrow() -> void:
	var left: float = -0.47 + condition * 0.10
	var polygon: Array[Vector2] = [Vector2(left * d.x, 0.26 * d.y), Vector2(0.12 * d.x, 0.26 * d.y), Vector2(0.12 * d.x, 0.07 * d.y), Vector2(0.49 * d.x, 0.50 * d.y), Vector2(0.12 * d.x, 0.93 * d.y), Vector2(0.12 * d.x, 0.74 * d.y), Vector2(left * d.x, 0.74 * d.y)]
	g.panel("arrow_silhouette", polygon, 0, d.z * 0.52)
	bar("arrow_chevron_upper", p(0.16, 0.9, -0.29), p(0.48, 0.5, -0.29), 0.08)
	bar("arrow_chevron_lower", p(0.48, 0.5, -0.29), p(0.16, 0.10 + condition * 0.07, -0.29), 0.08)
	bar("arrow_mount", p(-0.26, 0.5, 0.23), p(-0.26, 0.5, 0.48), 0.12)
	text_at(p(-0.12, 0.5, -0.38), d.x * 0.49, d.y * 0.39, "arrow_silhouette")

func hanging() -> void:
	var polygon: Array[Vector2] = [Vector2(-d.x * 0.44, d.y * 0.12), Vector2(d.x * (0.44 - condition * 0.12), d.y * 0.12), Vector2(d.x * (0.44 - condition * 0.12), d.y * 0.52)]
	for i: int in range(1, 7):
		var angle: float = PI * float(i) / 6.0
		polygon.append(Vector2(cos(angle) * d.x * 0.44, d.y * (0.52 + sin(angle) * 0.24)))
	g.panel("hanging_arch", polygon, -d.z * 0.13, d.z * 0.38)
	bar("hanging_wall_beam", p(-0.48, 0.97, 0.39), p(0.48, 0.97, 0.39), 0.11)
	for side: int in [-1, 1]:
		var x: float = float(side) * 0.31
		bar("hanging_arm_%d" % side, p(x, 0.97, 0.4), p(x, 0.97, -0.14), 0.07)
		bar("hanging_drop_%d" % side, p(x, 0.96, -0.14), p(x + condition * side * 0.025, 0.68, -0.14), 0.06)
	text_at(p(0, 0.40, -0.42), d.x * 0.71, d.y * 0.27, "hanging_arch")

func style_trim() -> void:
	if recipe.style == "block":
		b("style_block_badge", p(-0.39, 0.16, -0.48), p(0.09, 0.09, 0.07), "SEA_Metal", Vector3(0, 0, -0.10))
	elif recipe.style == "marquee":
		for i: int in range(6):
			if condition > 0 and i % 3 == 1:
				continue
			drum("style_marquee_%d" % i, p(-0.4 + i * 0.16, 0.07, -0.45), minf(d.x, d.y) * 0.035, d.z * 0.05, "SEA_Emission" if condition < 2 else "SEA_Metal", Vector3(PI * 0.5, 0, 0), false, 0, false)
