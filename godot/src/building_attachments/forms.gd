extends RefCounted
## 各语义族共享的几何操作，不借用房屋工坊或旧资产网格。

var g: RefCounted
var recipe: Dictionary
var d := Vector3.ONE
var condition: int = 0
const CLEARANCE := 0.008

func _init(geometry: RefCounted, data: Dictionary) -> void:
	g = geometry
	recipe = data
	d = g.dimensions
	condition = ["fresh", "damaged", "ruined"].find(str(recipe.condition))

func p(x: float, y: float, z: float) -> Vector3:
	return Vector3(x * d.x, y * d.y, z * d.z)

func b(name: String, center: Vector3, size: Vector3, role: String = "SEA_Matte", rotation: Vector3 = Vector3.ZERO, solid: bool = true) -> void:
	g.box(name, center, size, role, rotation, solid)

func bar(name: String, a: Vector3, end: Vector3, thickness: float = 0.055, role: String = "SEA_Metal", solid: bool = true) -> void:
	g.beam(name, a, end, minf(d.x, d.z) * thickness, role, solid)

func tube(name: String, a: Vector3, end: Vector3, radius: float, missing: int = 0) -> void:
	g.pipe_segment(name, a, end, radius, missing)

func drum(name: String, center: Vector3, radius: float, length: float, role: String = "SEA_Metal", rotation: Vector3 = Vector3.ZERO, hollow: bool = false, missing: int = 0, solid: bool = true, taper: float = 0.05) -> void:
	g.round_part(name, center, radius, radius * (1.0 - taper), length, role, rotation, hollow, missing, solid)

func frame(name: String, center: Vector3, width: float, height: float, thickness: float, depth: float, broken: int = 0) -> void:
	b(name + "_left", center + Vector3(-width * 0.5, 0, 0), Vector3(thickness, height, depth), "SEA_Metal")
	if broken < 2:
		b(name + "_right", center + Vector3(width * 0.5, -height * 0.12 * broken, 0), Vector3(thickness, height * (1.0 - 0.25 * broken), depth), "SEA_Metal")
	b(name + "_bottom", center + Vector3(-width * 0.1 * broken, -height * 0.5, 0), Vector3(width * (1.0 - 0.22 * broken), thickness, depth), "SEA_Matte")
	if broken == 0:
		b(name + "_top", center + Vector3(0, height * 0.5, 0), Vector3(width, thickness, depth), "SEA_Metal")
	elif broken == 1:
		bar(name + "_bent_top", center + Vector3(-width * 0.5, height * 0.5, 0), center + Vector3(width * 0.18, height * 0.39, -depth * 0.2), 0.04)

func wall_brackets(name: String, x_spread: float = 0.35, low: float = 0.12, high: float = 0.72) -> void:
	for side: int in [-1, 1]:
		var x: float = float(side) * x_spread
		bar(name + "_wall_%d" % side, p(x, low, 0.46), p(x, high, 0.46), 0.07)
		bar(name + "_seat_%d" % side, p(x, low, 0.43), p(x, low, -0.35), 0.07)
		bar(name + "_brace_%d" % side, p(x, low, -0.32), p(x, high * 0.66, 0.43), 0.055)
		g.contact(name + "_wall_%d" % side)

func feet(name: String, top: float, spread: float = 0.32, broken: bool = false) -> void:
	for x_side: int in [-1, 1]:
		for z_side: int in [-1, 1]:
			if broken and x_side == 1 and z_side == -1:
				continue
			var x: float = float(x_side) * spread
			var z: float = float(z_side) * spread
			b(name + "_pad_%d_%d" % [x_side, z_side], p(x, 0.025, z), p(0.16, 0.05, 0.15), "SEA_Matte")
			bar(name + "_leg_%d_%d" % [x_side, z_side], p(x, 0.05, z), p(x * 0.91, top, z * 0.91), 0.085)
			g.contact(name + "_pad_%d_%d" % [x_side, z_side])

func fan(name: String, center: Vector3, radius: float, depth: float, upward: bool = false, damage: int = -1) -> void:
	var level: int = condition if damage < 0 else damage
	var rotation := Vector3.ZERO if upward else Vector3(PI * 0.5, 0, 0)
	drum(name + "_ring", center, radius, depth, "SEA_Metal", rotation, true, level * 2)
	var basis: Basis = Basis.from_euler(rotation)
	drum(name + "_hub", center, radius * 0.19, depth * 1.15, "SEA_Metal", rotation)
	for i: int in range(4 - level):
		var angle: float = float(i) * TAU / 4.0 + 0.18
		var offset := Vector3(cos(angle) * radius * 0.47, 0, sin(angle) * radius * 0.47)
		var blade_basis: Basis = basis * Basis(Vector3.UP, -angle)
		b(name + "_blade_%d" % i, center + basis * offset, Vector3(radius * 0.62, depth * 0.26, radius * 0.28), "SEA_Matte", blade_basis.get_euler())
	# 稀疏护栅不是全黑盖板，断栅与叶片均为真实删减。
	for i: int in range(3 - level):
		var fraction: float = (float(i) - 1.0) * 0.38
		var a: Vector3 = center + basis * Vector3(-radius * 0.78, -depth * 0.63, radius * fraction)
		var end: Vector3 = center + basis * Vector3(radius * 0.78, -depth * 0.63, radius * fraction)
		bar(name + "_grille_%d" % i, a, end, 0.024)

func slats(name: String, center: Vector3, width: float, height: float, depth: float, count: int = 6) -> void:
	for i: int in range(count):
		if condition == 1 and i in [1, 4]:
			continue
		if condition == 2 and i not in [0, count - 1]:
			continue
		var y: float = center.y + (float(i) / float(count - 1) - 0.5) * height
		b(name + "_%d" % i, Vector3(center.x, y, center.z), Vector3(width, height / float(count) * 0.33, depth), "SEA_Metal", Vector3(-0.3 - 0.12 * condition, 0, 0))
