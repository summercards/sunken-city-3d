extends Node3D
## Colorful miniature fish school: compact scale, pastel-vibrant palette,
## and lively S-curve swimming with dart bursts, banking, and surface bobbing.
const COLORS = [
	"#ff785a", # 珊瑚鲜橙
	"#ffcf48", # 明亮金黄
	"#ff85b8", # 樱桃粉红
	"#5ce6d0", # 荧光薄荷青
	"#5ec8ff", # 晴空亮蓝
	"#a8eb70", # 鲜嫩青柠绿
]
var fish: Array[Node3D] = []
var motions: Array[Vector4] = []
var traits: Array[Vector3] = []
var ripple: MeshInstance3D

static func make_ripple(radius: float, phase: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "SurfaceRipple"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.0
	plane.subdivide_width = 12
	plane.subdivide_depth = 12
	node.mesh = plane
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/surface_ripple.gdshader")
	material.render_priority = 3
	material.set_shader_parameter("phase", phase)
	node.material_override = material
	return node

static func sync_ripple(node: MeshInstance3D, water: MeshInstance3D, time: float) -> void:
	var mat := node.material_override as ShaderMaterial
	mat.set_shader_parameter("u_time", water.time if water != null else time)
	if water != null:
		mat.set_shader_parameter("ocean_waves", water.ocean_waves)
		mat.set_shader_parameter("wave_scale", water.wave_scale)

func build(rng: RandomNumberGenerator, count: int, phase: float) -> void:
	var color_offset := int(round(phase * 3.0))
	for i in count:
		var col := Color(COLORS[(i + color_offset) % COLORS.size()])
		var f := _fish(col)
		f.name = "Fish%02d" % i
		var size_var := 0.88 + (i % 3) * 0.09
		f.scale = Vector3.ONE * size_var
		add_child(f)
		fish.append(f) # Do not rediscover duplicates by auto-renamed node names.
		# Keep rng call count (4 per fish) identical for deterministic seeding
		var p0 := rng.randf() * TAU
		var r0 := rng.randf_range(0.32, 0.82)
		var spd := rng.randf_range(0.75, 1.35)
		var depth_off := rng.randf_range(0.015, 0.055)
		motions.append(Vector4(p0, r0, spd, depth_off))
		# Derived lively traits (eccentricity, dart frequency, weave amplitude)
		var ecc := 0.68 + 0.24 * sin(p0 * 1.7 + float(i))
		var dart_freq := 1.35 + 0.45 * cos(p0 * 2.3 + float(i) * 1.1)
		var weave_amp := 0.055 + 0.030 * sin(p0 * 3.1)
		traits.append(Vector3(ecc, dart_freq, weave_amp))
	ripple = make_ripple(1.68, phase)
	add_child(ripple)

func animate(time: float, water: MeshInstance3D) -> void:
	for i in fish.size():
		var f := fish[i]
		var m := motions[i]
		var tr := traits[i]
		# Rhythmic darting: smooth speed modulation along orbit
		var dart_wave := sin(time * tr.y + m.x * 1.5)
		var a := time * m.z + m.x + 0.22 * dart_wave - 0.06 * sin(time * tr.y * 2.0 + m.x)
		var da := m.z + 0.22 * tr.y * cos(time * tr.y + m.x * 1.5)
		# Figure-8 / radial breathing modulation around the school center
		var r_breath := m.y * (1.0 + 0.14 * sin(a * 2.0 + m.x) + 0.08 * cos(time * 0.9 + float(i)))
		var dr := m.y * 0.28 * cos(a * 2.0 + m.x) * da
		var px := cos(a) * r_breath
		var pz := sin(a) * r_breath * tr.x
		# Velocity tangent for natural heading alignment
		var vx := -sin(a) * r_breath * da + cos(a) * dr
		var vz := cos(a) * r_breath * tr.x * da + sin(a) * tr.x * dr
		# Playful surface bobbing and occasional gentle crest leap (stays above water plane)
		var leap := maxf(0.0, sin(time * 1.85 + m.x * 2.1) - 0.45) * 0.065
		var py := 0.065 + sin(a * 1.9) * 0.016 + m.w * 0.5 + leap
		f.position = Vector3(px, py, pz)
		if water != null:
			var wp := global_position + f.position
			f.position.y += water.sample_surface(Vector2(wp.x, wp.z)).x
		var swim_freq := 9.5 + m.z * 3.5
		var swim_phase := time * swim_freq + m.x * 3.0
		var speed_boost := 1.0 + 0.35 * maxf(0.0, dart_wave)
		# Mesh nose is +Z; align to velocity vector plus subtle S-curve head yaw
		var base_yaw := atan2(vx, vz)
		var head_wiggle := sin(swim_phase) * tr.z * speed_boost
		f.rotation.y = base_yaw + head_wiggle
		# Pitch follows vertical bobbing/leaping, roll banks into turns and wiggles
		f.rotation.x = -cos(time * 1.85 + m.x * 2.1) * 0.10 - cos(a * 1.9) * 0.05
		f.rotation.z = -head_wiggle * 1.4 + sin(a) * 0.12
		# Body and tail S-wave undulation
		var body_node := f.get_node_or_null("Body") as Node3D
		if body_node != null:
			body_node.rotation.y = -sin(swim_phase - 0.6) * 0.12 * speed_boost
		var tail_node := f.get_node_or_null("Tail") as Node3D
		if tail_node != null:
			tail_node.rotation.y = sin(swim_phase - 1.3) * 0.38 * speed_boost
	sync_ripple(ripple, water, time)

func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, size: Vector3, unlit_boost := 0.34) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = pos
	part.scale = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.roughness = 1.0
	if unlit_boost > 0.0:
		mat.emission_enabled = true
		mat.emission = color * unlit_boost
	part.material_override = mat
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part

func _fish(color: Color) -> Node3D:
	var f := Node3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	# Compact, sleek silhouette (~62% of previous size)
	var body := _part(f, sphere, color, Vector3.ZERO, Vector3(0.098, 0.068, 0.185), 0.36)
	body.name = "Body"
	# Bright dorsal accent stripe for top-down readability
	_part(body, sphere, color.lightened(0.35), Vector3(0, 0.42, 0.05), Vector3(0.58, 0.42, 0.68), 0.42)
	# A flat fan tail reads clearly as a fish silhouette from the gameplay camera.
	var vertices := PackedVector3Array([Vector3(0, 0, 0), Vector3(-0.095, 0, -0.145), Vector3(0.095, 0, -0.145)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	var tail := ArrayMesh.new()
	tail.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var fin := _part(f, tail, color.lightened(0.18), Vector3(0, 0, -0.155), Vector3.ONE, 0.34)
	fin.name = "Tail"
	fin.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side in [-1.0, 1.0]:
		_part(f, sphere, Color("#1f3b44"), Vector3(side * 0.062, 0.038, 0.105), Vector3.ONE * 0.019, 0.0)
	return f
