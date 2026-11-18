@tool
extends RefCounted
## 派生静态输出。返回脱离树的宿主局部层，调用方负责把它放入 Work 的独立兄弟层。
## 草使用原 Library mesh/material；苔藤按源/空间块合并并裁入真实面，没有逐三角节点。

const Data = preload("res://addons/building_workshop/surface_paint_data.gd")
const Cache = preload("res://addons/building_workshop/surface_paint_surface.gd")
const Library = preload("res://src/ambient/vegetation/library.gd")
const MAX_CHUNKS := 128
const MAX_INSTANCES_PER_CHUNK := 512
const MAX_OUTPUT_VERTICES := 131072
const CHUNK_METRES := 2.0
# surface_moss_atlas_512：左上 round、右上 radial、左下 hanging、右下 ivy。
# 每个256px格仅采样8..247px的像素中心，避免基础过滤跨格；深层mip渗色仍需素材留边。
const ATLAS_INSET := 8.5 / 512.0
const ATLAS_SPAN := 239.0 / 512.0

## textures 为可信调用者提供的 Texture2D：moss_atlas / vine_atlas；不读取快照资源路径。
## options 仅允许 chunk_metres(0.5..8)。不加载主场景，不注册/写入任何全局风。
static func build_from_snapshot(snapshot: Dictionary, host: Node3D, textures: Dictionary = {}, options: Dictionary = {}, surface_cache: RefCounted = null) -> Dictionary:
	var reason := Data.validate(snapshot)
	if not reason.is_empty(): return _fail(reason)
	if options.size() > 1 or (not options.is_empty() and not options.has("chunk_metres")): return _fail("输出选项含未知字段")
	var chunk_metres: Variant = options.get("chunk_metres", CHUNK_METRES)
	if not Data.bounded(chunk_metres, 0.5, 8.0): return _fail("chunk_metres 必须为0.5..8米")
	var cache: RefCounted = surface_cache if surface_cache != null else Cache.new()
	var cached: Dictionary = cache.build_cache(host)
	if not cached.ok: return cached
	reason = cache.validate_snapshot_surface(snapshot)
	if not reason.is_empty(): return _fail(reason)
	var layer := Data.decode_transform(snapshot.layer_transform)
	var host_world: Transform3D = cache.host_transform()
	var world_to_layer := (host_world * layer).affine_inverse()
	var groups := {}
	var ordered: Array = snapshot.stamps.duplicate(true)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	for stamp: Dictionary in ordered:
		var world: Vector3 = host_world * Data.vec(stamp.center_local)
		# 米制分块不受宿主/层缩放影响；instance变换仍以层局部保存。
		var cell := Vector3i(floori(world.x / chunk_metres), floori(world.y / chunk_metres), floori(world.z / chunk_metres))
		var key := "%s_%d_%d_%d" % [stamp.source, cell.x, cell.y, cell.z]
		if not groups.has(key): groups[key] = []
		groups[key].append(stamp)
		if groups.size() > MAX_CHUNKS or groups[key].size() > MAX_INSTANCES_PER_CHUNK:
			return _fail("输出超过128块或单块512印记预算")
	var sources := {}
	for stamp: Dictionary in ordered:
		if sources.has(stamp.source): continue
		if stamp.kind == "grass":
			var entry: Variant = Library.catalog().get("grass_soft")
			if not entry is Dictionary or not entry.get("material") is String or not ResourceLoader.exists(entry.material, "Material"):
				return _fail("现有 grass_soft 原材质缺失或未导入")
			var mesh: Mesh = Library.mesh("grass_soft")
			var material: Material = Library.material("grass_soft")
			if mesh == null or mesh.get_surface_count() == 0 or material == null: return _fail("现有 grass_soft 网格或原材质不可用")
			if not material is ShaderMaterial or material.shader == null or material.shader.resource_path != "res://shaders/vegetation/soft_cards.gdshader":
				return _fail("grass_soft 必须保留原 soft_cards 材质契约")
			sources[stamp.source] = {"mesh": mesh, "material": material}
		else:
			var texture: Variant = textures.get(stamp.source)
			if not texture is Texture2D or texture.get_width() <= 0 or texture.get_height() <= 0:
				return _fail("缺少主线程提供的真实纹理：" + stamp.source + "；不生成占位素材")
			sources[stamp.source] = {"material": atlas_material(texture)}
	var root := Node3D.new()
	root.name = "SurfacePaint"
	root.transform = layer
	root.set_meta(Data.META, snapshot.duplicate(true))
	root.set_meta("visual_only", true)
	root.set_meta("world_derivation", "excluded_visual_only")
	root.set_meta("surface_paint_geometry_fingerprint", cache.fingerprint())
	root.set_meta("placement_space", "host_local")
	root.set_meta("wind_contract", "grass_soft 原材质只读共享 vegetation_*；独立预览需由宿主外的唯一风提供方供值，本层不注册 owner")
	var total_vertices := 0
	var keys: Array = groups.keys()
	keys.sort()
	for key: String in keys:
		var rows: Array = groups[key]
		var source: Dictionary = sources[rows[0].source]
		var origin: Vector3 = world_to_layer * (host_world * Data.vec(rows[0].center_local))
		var node: GeometryInstance3D
		if rows[0].kind == "grass":
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.use_custom_data = true
			multi.mesh = source.mesh
			multi.instance_count = rows.size()
			var bounds := AABB()
			for index: int in rows.size():
				var stamp: Dictionary = rows[index]
				var world_normal: Vector3 = (host_world.basis.inverse().transposed() * Data.vec(stamp.normal)).normalized()
				var world_basis := _world_basis(stamp, host_world, world_normal)
				var world: Vector3 = host_world * Data.vec(stamp.center_local) + world_normal * float(stamp.params.offset)
				var scale: Vector3 = Data.vec(stamp.scale) * (float(stamp.params.size) / 0.48)
				var scaled := Basis(world_basis.x * scale.x, world_basis.y * scale.y, world_basis.z * scale.z)
				var transform := world_to_layer * Transform3D(scaled, world)
				transform.origin -= origin
				multi.set_instance_transform(index, transform)
				var rng := RandomNumberGenerator.new()
				rng.seed = int(stamp.seed)
				multi.set_instance_custom_data(index, Color(rng.randf(), rng.randf(), 1.0, 1.0))
				var box: AABB = transform * multi.mesh.get_aabb()
				bounds = box if index == 0 else bounds.merge(box)
			multi.custom_aabb = bounds.grow(0.6 * world_to_layer.basis.get_scale().abs().length())
			var batch := MultiMeshInstance3D.new()
			batch.multimesh = multi
			batch.set_meta("surface_paint_shared_wind_material", true)
			batch.set_meta("asset_key", "grass_soft")
			node = batch
		else:
			var buffer := {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array()}
			for stamp: Dictionary in rows:
				var face: Dictionary = cache.triangle_for_stamp(stamp)
				var normal: Vector3 = face.normal
				var basis := _world_basis(stamp, host_world, normal)
				if stamp.kind == "moss":
					_append_clipped_card(buffer, stamp, host_world * Data.vec(stamp.center_local), basis, face, world_to_layer, origin)
				else:
					for index: int in range(1, stamp.path_points.size()):
						var a: Vector3 = host_world * Data.vec(stamp.path_points[index - 1])
						var b: Vector3 = host_world * Data.vec(stamp.path_points[index])
						var along := (b - a).normalized()
						var path_basis := Basis(normal.cross(along).normalized(), normal, along)
						_append_clipped_card(buffer, stamp, (a + b) * 0.5, path_basis, face, world_to_layer, origin, a.distance_to(b))
				if total_vertices + buffer.v.size() > MAX_OUTPUT_VERTICES:
					root.free()
					return _fail("苔藤裁切输出超过131072顶点预算")
			total_vertices += buffer.v.size()
			if buffer.v.is_empty():
				root.free()
				return _fail("苔藤印记没有真实面内面积")
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = buffer.v
			arrays[Mesh.ARRAY_NORMAL] = buffer.n
			arrays[Mesh.ARRAY_TEX_UV] = buffer.uv
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var batch := MeshInstance3D.new()
			batch.mesh = mesh
			node = batch
		node.name = key
		node.position = origin
		node.material_override = source.material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.set_meta("visual_only", true)
		node.set_meta("surface_paint_source", rows[0].source)
		var ids: Array[String] = []
		for stamp: Dictionary in rows: ids.append(stamp.id)
		node.set_meta("surface_paint_stamp_ids", ids)
		root.add_child(node)
		node.owner = root
	return {"ok": true, "reason": "", "root": root, "snapshot": snapshot.duplicate(true),
		"fingerprint": Data.fingerprint(snapshot), "host_world_transform": host_world,
		"chunks": groups.size(), "instances": ordered.size(), "patch_vertices": total_vertices}

static func _world_basis(stamp: Dictionary, host_world: Transform3D, normal: Vector3) -> Basis:
	var tangent: Vector3 = host_world.basis * Basis(Data.quat(stamp.orientation)).x
	tangent = (tangent - normal * tangent.dot(normal)).normalized()
	return Basis(tangent, normal, tangent.cross(normal).normalized())

## 真实素材的固定贴面 alpha clip，不套旧凸苔模型；不写共享材质或创建新图。
static func atlas_material(texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "SurfacePaintAtlas"
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.42
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.roughness = 1.0
	return material

static func _append_clipped_card(buffer: Dictionary, stamp: Dictionary, center: Vector3, basis: Basis, face: Dictionary, world_to_layer: Transform3D, origin: Vector3, path_length: float = -1.0) -> void:
	var width := float(stamp.params.size) * float(stamp.scale[0])
	var length := path_length if path_length > 0.0 else float(stamp.params.size) * float(stamp.scale[2])
	var x := basis.x * width * 0.5
	var z := basis.z * length * 0.5
	# 顺时针正面 +Y；以宿主三角边裁切卡片，洞口/檐口不向空中伸出平面贴片。
	var polygon: Array[Vector3] = [center - x - z, center + x - z, center + x + z, center - x + z]
	var corners: Array[Vector3] = [face.a, face.b, face.c]
	for edge: int in 3:
		var a := corners[edge]
		var b := corners[(edge + 1) % 3]
		var inward: Vector3 = (b - a).cross(face.normal).normalized()
		var clipped: Array[Vector3] = []
		for index: int in polygon.size():
			var start := polygon[index]
			var end := polygon[(index + 1) % polygon.size()]
			var ds := inward.dot(start - a)
			var de := inward.dot(end - a)
			if ds >= 0.0: clipped.append(start)
			if (ds >= 0.0) != (de >= 0.0): clipped.append(start.lerp(end, ds / (ds - de)))
		polygon = clipped
		if polygon.size() < 3: return
	var normal: Vector3 = (world_to_layer.basis.inverse().transposed() * face.normal).normalized()
	for index: int in range(1, polygon.size() - 1):
		for vertex: int in [0, index, index + 1]:
			var point := polygon[vertex]
			buffer.v.append(world_to_layer * (point + face.normal * float(stamp.params.offset)) - origin)
			buffer.n.append(normal)
			var card_uv := Vector2(0.5 + (point - center).dot(basis.x) / width, 0.5 + (point - center).dot(basis.z) / length)
			buffer.uv.append(_atlas_uv(str(stamp.kind), int(stamp.seed), card_uv))

static func _atlas_uv(kind: String, seed: int, card_uv: Vector2) -> Vector2:
	# 不消费随机流：同一kind/seed跨重建、裁切顶点和藤段保持同格。
	var tile := Vector2(float(seed % 2), 0.0 if kind == "moss" else 1.0)
	var clipped := card_uv.clamp(Vector2.ZERO, Vector2.ONE)
	return tile * 0.5 + Vector2.ONE * ATLAS_INSET + clipped * ATLAS_SPAN

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "root": null}
