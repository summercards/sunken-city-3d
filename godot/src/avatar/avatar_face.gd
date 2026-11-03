extends RefCounted
## Original SEA source authored 2026-11-03; no external character artwork.
## Original surface-conforming cosmetics. Coordinates are native AvatarHead units.
## Every coloured facial layer follows the same ellipsoid as the skin; changing
## head scale therefore cannot detach the eyes, blush or facial hair.
const Catalog = preload("res://src/avatar/avatar_catalog.gd")
const RADII := Vector3(0.258, 0.25, 0.253)
const TEXTURE_ROOT := "res://assets/textures/avatar/"
var _materials: Dictionary = {}
var _report: Dictionary = {}

func build(parent: Node3D, appearance: Dictionary, morphs: Dictionary) -> void:
	_materials.clear()
	_report = {"eye_centers": [], "blush_textures": [], "blush_surface_offset": 0.003,
		"beard_style": str(appearance.get("beard", "none")), "eye_surface": "ellipsoid_conformal"}
	var root := Node3D.new()
	root.name = "FaceDetails"
	parent.add_child(root)
	var spacing := lerpf(0.070, 0.105, clampf(float(morphs.get("eye_spacing", 0.5)), 0.0, 1.0))
	var hair := Catalog.color(appearance, "hair_color")
	for side in [-1, 1]:
		var center := Vector2(side * spacing, 0.005)
		_report.eye_centers.append([center.x, center.y])
		_eye(root, center, side, str(appearance.get("eyes", "round")), Catalog.color(appearance, "eye_color"))
		var blush := str(appearance.get("blush", "none"))
		if blush != "none":
			var texture_name := "freckles.png" if blush == "freckles" else "blush_soft.png"
			var tint := Color("#ae7453") if blush == "freckles" else Color("#e88981")
			var node := _grid(root, "BlushLeft" if side < 0 else "BlushRight", Vector2(side * 0.160, -0.070), Vector2(0.052, 0.033), 0.003, _textured(tint, texture_name), "blush")
			node.set_meta("texture_path", TEXTURE_ROOT + texture_name)
			node.set_meta("side", side)
			_report.blush_textures.append(TEXTURE_ROOT + texture_name)
	_beard(root, appearance, hair)
	_nose(root, appearance)
	_expression_shapes(root, appearance, spacing)
	_mouth(root,str(appearance.get("mouth","smile")))
	if str(appearance.get("glasses", "none")) != "none":
		_glasses(root, spacing, str(appearance.glasses))
	root.set_meta("avatar_face_metrics", _report.duplicate(true))

func metrics() -> Dictionary:
	return _report.duplicate(true)

func build_dive_mask(parent: Node3D) -> void:
	# The caller owns visibility and applies the same head scale as AvatarHead.
	# Rounded corners leave more room for wide-set spectacles than an ellipse,
	# while the upper edge stays below the lowest supported fringe.
	var center := Vector2(0, 0.002)
	var radius := Vector2(0.188, 0.077)
	var path := PackedVector2Array()
	for i in 65:
		var angle := TAU * i / 64.0
		path.append(center + Vector2(signf(cos(angle)) * pow(absf(cos(angle)), 0.25), signf(sin(angle)) * pow(absf(sin(angle)), 0.25)) * radius)
	var lens := _disk(parent, "DiveMaskLens", center, radius - Vector2(0.003, 0.003), 0.040, Color(0.37, 0.72, 0.79, 0.20), "dive_mask", false, 0.25)
	var glass := lens.material_override.duplicate() as StandardMaterial3D
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	glass.roughness = 0.23
	glass.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	lens.material_override = glass
	lens.set_meta("mask_layer", "lens")
	var rubber := Color("#365653")
	var frame := _stroke(parent, "DiveMaskFrame", path, 0.012, 0.044, rubber, "dive_mask")
	frame.set_meta("mask_layer", "frame")
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in path.size():
		vertices.append(_point(path[i], 0.027))
		vertices.append(_point(path[i], 0.044))
		uvs.append(Vector2(0, i / 64.0))
		uvs.append(Vector2(1, i / 64.0))
		if i > 0:
			var a := (i - 1) * 2
			indices.append_array([a, a + 1, a + 3, a, a + 3, a + 2])
	var gasket := _mesh(parent, "DiveMaskGasket", vertices, uvs, indices, _material(rubber.darkened(0.12)), "dive_mask")
	gasket.set_meta("mask_layer", "gasket")
	parent.set_meta("avatar_mask_offsets", {"lens": 0.040, "frame": 0.044, "gasket_back": 0.027})

func _point(xy: Vector2, offset: float) -> Vector3:
	var q := pow(xy.x / RADII.x, 2.0) + pow(xy.y / RADII.y, 2.0)
	if q > 0.995:
		xy *= sqrt(0.995 / q)
	var p := Vector3(xy.x, xy.y, RADII.z * sqrt(maxf(0.0, 1.0 - pow(xy.x / RADII.x, 2.0) - pow(xy.y / RADII.y, 2.0))))
	return p + _normal(p) * offset

func _normal(p: Vector3) -> Vector3:
	return Vector3(p.x / (RADII.x * RADII.x), p.y / (RADII.y * RADII.y), p.z / (RADII.z * RADII.z)).normalized()

func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.95
		material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = material
	return _materials[key]

func _textured(color: Color, file: String) -> StandardMaterial3D:
	var material := _material(color).duplicate() as StandardMaterial3D
	var path := TEXTURE_ROOT + file
	if ResourceLoader.exists(path):
		material.albedo_texture = load(path) as Texture2D
	else:
		var source := Image.load_from_file(path)
		if source != null: material.albedo_texture = ImageTexture.create_from_image(source)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return material

func _mesh(parent: Node3D, id: String, vertices: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, material: Material, part: String) -> MeshInstance3D:
	var normals := PackedVector3Array()
	for p in vertices: normals.append(_normal(p))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.name = id
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta("avatar_part", part)
	parent.add_child(node)
	return node

func _disk(parent: Node3D, id: String, center: Vector2, radius: Vector2, offset: float, color: Color, part: String, almond: bool = false, roundedness: float = 1.0) -> MeshInstance3D:
	var vertices := PackedVector3Array([_point(center, offset)])
	var uvs := PackedVector2Array([Vector2(0.5, 0.5)])
	var indices := PackedInt32Array()
	const STEPS := 40
	const RINGS := 4
	for ring in range(1, RINGS + 1):
		for i in STEPS:
			var angle := TAU * i / float(STEPS)
			var x := signf(cos(angle)) * pow(absf(cos(angle)), roundedness)
			var y := signf(sin(angle)) * pow(absf(sin(angle)), roundedness)
			if almond: y *= sqrt(absf(y))
			var delta := Vector2(x, y) * radius * (ring / float(RINGS))
			vertices.append(_point(center + delta, offset))
			uvs.append(Vector2(0.5, 0.5) + delta / radius * 0.5)
	for i in STEPS: indices.append_array([0, 1 + (i + 1) % STEPS, 1 + i])
	for ring in range(RINGS - 1):
		for i in STEPS:
			var a := 1 + ring * STEPS + i
			var b := 1 + ring * STEPS + (i + 1) % STEPS
			var c := a + STEPS
			var d := b + STEPS
			indices.append_array([a, b, d, a, d, c])
	return _mesh(parent, id, vertices, uvs, indices, _material(color), part)

func _grid(parent: Node3D, id: String, center: Vector2, radius: Vector2, offset: float, material: Material, part: String) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	const COLS := 24
	const ROWS := 16
	for row in ROWS + 1:
		for col in COLS + 1:
			var uv := Vector2(col / float(COLS), row / float(ROWS))
			vertices.append(_point(center + Vector2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0) * radius, offset))
			uvs.append(uv)
	for row in ROWS:
		for col in COLS:
			var a := row * (COLS + 1) + col
			indices.append_array([a, a + 1, a + COLS + 2, a, a + COLS + 2, a + COLS + 1])
	return _mesh(parent, id, vertices, uvs, indices, material, part)

func _stroke(parent: Node3D, id: String, path: PackedVector2Array, width: float, offset: float, color: Color, part: String) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in path.size():
		var tangent := path[mini(i + 1, path.size() - 1)] - path[maxi(0, i - 1)]
		var normal := Vector2(-tangent.y, tangent.x).normalized() * width * 0.5
		vertices.append(_point(path[i] + normal, offset))
		vertices.append(_point(path[i] - normal, offset))
		uvs.append(Vector2(0, i / float(path.size() - 1)))
		uvs.append(Vector2(1, i / float(path.size() - 1)))
		if i > 0:
			var a := (i - 1) * 2
			indices.append_array([a, a + 2, a + 3, a, a + 3, a + 1])
	return _mesh(parent, id, vertices, uvs, indices, _material(color), part)

func _arc_path(center: Vector2, radius: Vector2, start: float, end: float) -> PackedVector2Array:
	var path := PackedVector2Array()
	for i in 33:
		var a := lerpf(start, end, i / 32.0)
		path.append(center + Vector2(cos(a), sin(a)) * radius)
	return path

func _eye(parent: Node3D, center: Vector2, side: int, style: String, color: Color) -> void:
	var root := Node3D.new()
	root.name = "EyeLeft" if side < 0 else "EyeRight"
	root.set_meta("avatar_part", "eye"); root.set_meta("side", side); root.set_meta("eye_center", center)
	parent.add_child(root)
	var ids := ["round","oval","sleepy","smile","almond","wide","soft","cat","sparkle","dot","lidded","bright"]
	var index := maxi(0,ids.find(style))
	var material := ShaderMaterial.new(); material.shader=preload("res://shaders/avatar_eye.gdshader")
	material.set_shader_parameter("eye_atlas",load(TEXTURE_ROOT+"graphic_eyes.png"))
	material.set_shader_parameter("tile_origin",Vector2((index%4)*0.25,(index/4)* (1.0/3.0)))
	material.set_shader_parameter("side",float(side))
	material.set_shader_parameter("ink_color",color.darkened(0.62))
	var node:=_grid(root,"GraphicEye",center,Vector2(0.052,0.070),0.006,material,"eye")
	node.set_meta("side",side); node.set_meta("texture_path",TEXTURE_ROOT+"graphic_eyes.png")
	node.set_meta("eye_tile",index)

func _expression_shapes(parent: Node3D, appearance: Dictionary, spacing: float) -> void:
	var ink:=Color("#302724")
	for mode in ["neutral","happy","focused","surprised","concerned","calm"]:
		var root:=Node3D.new(); root.name="Expression_"+mode
		root.set_meta("avatar_expression",mode); root.visible=mode=="neutral"; parent.add_child(root)
		for side in [-1,1]:
			var center:=Vector2(side*spacing,0.005)
			if mode=="neutral": _brow(root,center,side,str(appearance.get("brows","soft")),ink)
			else:
				var path:=PackedVector2Array()
				for i in 17:
					var t:=i/16.0*2.0-1.0
					var y:=0.092
					if mode=="happy": y+=0.012*(1.0-t*t)
					elif mode=="focused": y+=side*t*0.018
					elif mode=="concerned": y-=side*t*0.018
					elif mode=="surprised": y+=0.016+0.008*(1.0-t*t)
					path.append(Vector2(center.x+t*0.037,y))
				_stroke(root,"Brow"+str(side),path,0.013,0.006,ink,"brow")
func _brow(parent: Node3D, center: Vector2, side: int, style: String, color: Color) -> void:
	var path := PackedVector2Array()
	for i in 17:
		var t := i / 16.0 * 2.0 - 1.0
		var arch := 0.010 * (1.0 - t * t) if style == "arch" else 0.0
		var slope := -side * t * 0.006 if style == "soft" else 0.0
		path.append(Vector2(center.x + t * 0.035, 0.096 + arch + slope))
	_stroke(parent, "BrowLeft" if side < 0 else "BrowRight", path, 0.013, 0.006, color, "brow")

func _nose(parent: Node3D, appearance: Dictionary) -> void:
	var color:=Catalog.color(appearance,"skin").darkened(0.23)
	var style:=str(appearance.get("nose","button"))
	if style=="oval": _disk(parent,"Nose",Vector2(0,-0.044),Vector2(0.020,0.023),0.008,color,"nose")
	elif style=="tiny": _stroke(parent,"Nose",PackedVector2Array([Vector2(-0.009,-0.048),Vector2(0.009,-0.048)]),0.009,0.008,color,"nose")
	else:
		var points:=PackedVector3Array([_point(Vector2(-0.020,-0.032),0.008),_point(Vector2(0.020,-0.032),0.008),_point(Vector2(0,-0.061),0.008)])
		_mesh(parent,"Nose",points,PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE]),PackedInt32Array([0,1,2]),_material(color),"nose")

func _mouth(parent: Node3D, style: String) -> void:
	var ids: Array=["smile","wide","calm","oh","open","grin","frown","smirk","cat","joy","laugh","pout","fang","tongue","kiss","zigzag"]
	var index:=maxi(0,ids.find(style))
	var material:=ShaderMaterial.new(); material.shader=preload("res://shaders/avatar_mouth.gdshader")
	material.set_shader_parameter("mouth_atlas",load(TEXTURE_ROOT+"graphic_mouths.png"))
	material.set_shader_parameter("tile_origin",Vector2((index%4)*0.25,(index/4)*0.25))
	material.set_shader_parameter("glyph_scale",0.74 if index in [3,14] else (0.86 if index==9 else 1.0))
	var mouth:=_grid(parent,"GraphicMouth",Vector2(0,-0.110),Vector2(0.064,0.086),0.012,material,"mouth")
	mouth.set_meta("mouth_tile",index); mouth.set_meta("texture_path",TEXTURE_ROOT+"graphic_mouths.png")

func _beard(parent: Node3D, appearance: Dictionary, hair: Color) -> void:
	var style := str(appearance.get("beard", "none"))
	if style == "none": return
	var color := Catalog.color(appearance, "beard_color") if not Catalog.options("beard_color").is_empty() else hair
	if style == "stubble":
		# Chin decals stop above the collar envelope even for the smallest head
		# and widest torso. Do not wrap rectangular corners beneath the jaw.
		_grid(parent, "Stubble", Vector2(0, -0.157), Vector2(0.151, 0.047), 0.0035, _textured(color, "stubble.png"), "beard")
	elif style == "moustache":
		for side in [-1, 1]:
			_disk(parent, "MoustacheLeft" if side < 0 else "MoustacheRight", Vector2(side * 0.026, -0.080), Vector2(0.031, 0.010), 0.005, color, "beard")
	elif style == "goatee":
		_disk(parent, "Goatee", Vector2(0, -0.178), Vector2(0.047, 0.027), 0.005, color, "beard")
	elif style == "full":
		# U-shaped surface band leaves the complete mouth opening unobstructed.
		var path := PackedVector2Array()
		for i in 49:
			var angle := lerpf(PI * 0.94, TAU + PI * 0.06, i / 48.0)
			path.append(Vector2(cos(angle) * 0.129, -0.116 + sin(angle) * 0.065))
		_stroke(parent, "FullBeard", path, 0.038, 0.005, color, "beard")
		_disk(parent, "ChinBeard", Vector2(0, -0.181), Vector2(0.060, 0.024), 0.005, color, "beard")

func _glasses(parent: Node3D, spacing: float, style: String) -> void:
	var frame := Color("#6b6259")
	for side in [-1, 1]:
		var path := PackedVector2Array()
		for i in 49:
			var angle := TAU * i / 48.0
			var x := cos(angle)
			var y := sin(angle)
			if style != "round":
				x = signf(x) * pow(absf(x), 0.45)
				y = signf(y) * pow(absf(y), 0.45)
			path.append(Vector2(side * spacing + x * 0.049, 0.008 + y * (0.060 if style == "round" else 0.047)))
		_stroke(parent, "GlassesLeft" if side < 0 else "GlassesRight", path, 0.006, 0.018, frame, "glasses")
		_stroke(parent, "GlassesTempleLeft" if side < 0 else "GlassesTempleRight", PackedVector2Array([Vector2(side * (spacing + 0.049), 0.019), Vector2(side * 0.231, 0.025)]), 0.005, 0.017, frame, "glasses")
	_stroke(parent, "GlassesBridge", PackedVector2Array([Vector2(-spacing + 0.049, 0.020), Vector2(0, 0.027), Vector2(spacing - 0.049, 0.020)]), 0.005, 0.019, frame, "glasses")
