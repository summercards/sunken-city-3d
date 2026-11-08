@tool
extends Node3D
## Independent authored scene, not a replacement for any of the nine dive maps.
## 水面 = 上街面(−18.412558) + 120 m。这个值让 119.32 m 的最高塔顶落在水面下 0.68 m，
## 于是「海面到底部 120 m」和「最高处贴着水面下方」两件事同时成立。
@export var water_level := 101.587442
@export var city_bounds := Rect2(-120,-120,240,240)
@export var terrain_bounds := Rect2(-512,-512,1024,1024)
@export_category("Local depth contract")
## Collision runtime keeps a 0.8m capsule clearance above this terrain reference.
@export var lowest_seabed_y := -19.212558
@export var viewer_min_y := -18.412558
## 2026-11-08 第二轮：水面再抬到 101.587442，上街面到水面变成 120 米整。
@export var target_depth_m := 120.0
@export var viewer_floor_clearance := 0.8
var grounding_results: Array = []
var _surfaces: Array = []
var _mesh_cache := {}
var _clock := 0.0
var _yaw := 0.0
var _pitch := -0.12
var _drag := false
var _notice: Label
const RegionCollision = preload("res://src/diving/sunroom_region_collision.gd")
const DiveAirScript = preload("res://src/diving/dive_air.gd")
const DiveControllerScript = preload("res://src/diving/dive_runtime_controller.gd")
const MaterialLib = preload("res://src/diving/uw_materials.gd")
const DAY_SUN_DIRECTION := Vector3(0.5191, 0.7787, -0.3523)
const DAY_SUN_COLOR := Color(1.0, 0.955, 0.8)
var _sun_direction := DAY_SUN_DIRECTION.normalized()
var _sun_color := DAY_SUN_COLOR
var _sun_strength := 1.0
var _palette_materials: Array[ShaderMaterial] = []
var _surface_material: ShaderMaterial
var _sky_material: ShaderMaterial
var _fog_material: ShaderMaterial
var _environment: Environment
var collision_runtime: RegionCollision
var dive_controller: Node
var _compat_phase_machine = preload("res://src/core/state_machine.gd").new()
var phase_machine:
	get: return dive_controller.machine if is_instance_valid(dive_controller) else _compat_phase_machine
var phase: String:
	get:
		var current: String = phase_machine.current
		return current if not current.is_empty() else "surface"
	set(value): phase_machine.change(value)
var _exit_start := Vector3.ZERO
var _exit_surface := Vector3.ZERO

## 家园海底：与海面共用世界坐标，因此没有固定出生点，只有下水点换算。
@export var map_id := "dive_home_seabed"
@export var chest_id_base := 900
@export var map_label := "家园海底"
## 入水深度要越过换气层（DiveAir 的 5 m 水面带），否则一入水就一直满氧。
@export var entry_drop := 6.0
## 2026-11-08 用户要求「下水后的位置在水下 1 米」：入水点直接停在水面下方这个深度，
## 先看到 120 米深沟的全貌再往下游，而不是一进去就贴在街面上。
## 代价必须记明：前 4 米仍在水面换气带内，满氧是预期行为，不是漏气。
@export var entry_depth_below_surface := 1.0
## 旧城上街面高度（= water_level - 120）。只在「水下 1 米找不到净空」时兜底落回街面。
@export var entry_street_y := -18.412558
@export var entry_rise := 10.0
@export var entry_search_radius := 60.0
@export var swim_speed := 4.2
@export var exit_seconds := 0.55

signal depth_changed(depth: float)
signal zone_changed(label: String)
signal air_changed(ratio: float, lamp_on: bool, found: int, total: int)
signal message(text: String)
signal exited

var air = DiveAirScript.new()
## 入水点就在水下 1 米；换气带必须收窄到它以内，否则贴水面的玩家永远满氧。
const LOCAL_SURFACE_DEPTH := 0.5
## 潜水会话的通用注入点；家园海底没有宝箱，保留空接口以免会话写属性报错。
var give_resource: Callable
var give_rewards: Callable
var diver_pos := Vector3.ZERO
var depth := 0.0
var _diving := false
var _exit_left := -1.0
var _lamp: SpotLight3D
## 入水点是否已在物理提交后复核过净空；Terrain3D 碰撞是延后提交的。
var entry_verified := false
var _surface_entry := Vector3.ZERO
var _entry_face := Vector3.ZERO

func _ready() -> void:
	if Engine.is_editor_hint(): return
	air.surface_depth = LOCAL_SURFACE_DEPTH
	_build_surface_index()
	_ground_ecology()
	_localize_underwater_materials()
	_environment = $WorldEnvironment.environment
	_surface_material = $Water.material_override as ShaderMaterial
	_sky_material = _environment.sky.sky_material as ShaderMaterial
	_environment.sky.process_mode = Sky.PROCESS_MODE_REALTIME
	_build_water_fog()
	$Atmosphere.configure_water(water_level)
	_apply_underwater_light()
	for school in $FishSchools.get_children():
		school.apply_underwater_materials(MaterialLib)
	$Water.show()
	collision_runtime = RegionCollision.new()
	collision_runtime.name = "RegionCollision"
	add_child(collision_runtime)
	collision_runtime.setup(self)
	dive_controller = DiveControllerScript.new()
	dive_controller.name = "DiveRuntimeController"
	add_child(dive_controller)
	dive_controller.configure(self, $Camera, $DiverVisual, "DiverCharacter")
	air = dive_controller.air
	_verify_depth_contract()
	var camera: Camera3D = $Camera
	_yaw = camera.rotation.y
	_pitch = camera.rotation.x
	_update_underwater_view()
	var label := Label.new()
	label.text = "阳光房下沉没旧城 · 独立水下区域"
	label.position = Vector2(24,20)
	label.add_theme_font_size_override("font_size",24)
	label.add_theme_font_override("font",preload("res://src/ui/ui_font.gd").embedded())
	$RegionHUD.add_child(label)
	_notice = Label.new()
	_notice.position = Vector2(24,55)
	_notice.add_theme_font_size_override("font_size",18)
	_notice.add_theme_font_override("font",preload("res://src/ui/ui_font.gd").embedded())
	$RegionHUD.add_child(_notice)

func _verify_depth_contract() -> void:
	var expected_viewer_min := water_level - target_depth_m
	var configured_viewer_min := lowest_seabed_y + viewer_floor_clearance
	var valid := is_equal_approx(viewer_min_y,expected_viewer_min) and is_equal_approx(viewer_min_y,configured_viewer_min)
	set_meta("depth_contract", "viewer_min_y=%.2fm; target_depth=%.1fm; lower_geometry_visual_only" % [viewer_min_y,target_depth_m])
	set_meta("viewer_min_y",viewer_min_y)
	set_meta("target_depth_m",target_depth_m)
	set_meta("lower_geometry_visual_only",true)
	if not valid:
		push_error("sunroom depth contract mismatch: viewer_min_y=%.3f expected=%.3f configured=%.3f" % [viewer_min_y,expected_viewer_min,configured_viewer_min])

## 日光注入：direction 是指向太阳的世界方向；缺省键恢复白天配置。
func configure_underwater_light(profile: Dictionary) -> void:
	var direction: Vector3 = profile.get("direction", DAY_SUN_DIRECTION)
	_sun_direction = direction.normalized() if direction.is_finite() and direction.length_squared() > 0.000001 else DAY_SUN_DIRECTION.normalized()
	_sun_color = profile.get("color", DAY_SUN_COLOR)
	var strength: float = profile.get("strength", 1.0)
	_sun_strength = clampf(strength, 0.0, 1.0) if is_finite(strength) else 0.0
	if Engine.is_editor_hint() or _surface_material == null: return
	_apply_underwater_light()
	_update_underwater_view()

func _apply_underwater_light() -> void:
	for mat in [_surface_material, _sky_material, _fog_material]:
		mat.set_shader_parameter("water_level", water_level)
		mat.set_shader_parameter("sun_direction", _sun_direction)
		mat.set_shader_parameter("sun_color", _sun_color)
		mat.set_shader_parameter("sun_strength", _sun_strength)
	for mat in _palette_materials:
		mat.set_shader_parameter("water_level", water_level)
		mat.set_shader_parameter("sun_strength", _sun_strength)
	$Atmosphere.set_sunlight(_sun_strength)

func _update_underwater_view() -> void:
	var viewer_y: float = dive_position().y if _diving else $Camera.global_position.y
	var view_depth := maxf(0.0, water_level - viewer_y)
	for mat in [_surface_material, _sky_material, _fog_material]:
		mat.set_shader_parameter("view_depth", view_depth)
		mat.set_shader_parameter("region_view_depth", view_depth)
		mat.set_shader_parameter("dive_depth", view_depth)
	$Atmosphere.set_view_depth(view_depth)
	# 与 shader 的 uw_depth_light 相同，不调整曝光、设施灯或头灯。
	var depth_light := lerpf(1.0, 0.26, smoothstep(5.0, 120.0, view_depth))
	_environment.ambient_light_energy = (1.9 / PI) * depth_light * lerpf(0.24, 1.0, _sun_strength)
	# 仅活动地图更新共享缓存，不向海面鱼群替换材质。
	MaterialLib.set_depth(view_depth)
	MaterialLib.set_water_level(water_level)
	MaterialLib.set_sun(_sun_direction, _sun_color, _sun_strength)
	MaterialLib.set_lamp(_diving and air.lamp, $Camera.global_position, -$Camera.global_basis.z)

func _build_water_fog() -> void:
	_environment.fog_enabled = false
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2,2)
	var pass_node := MeshInstance3D.new()
	pass_node.name = "WaterFogPass"
	pass_node.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/sunroom_underwater_fog.gdshader")
	mat.render_priority = -128
	pass_node.material_override = mat
	_fog_material = mat
	pass_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pass_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	pass_node.extra_cull_margin = 16384.0
	$Camera.add_child(pass_node)
	pass_node.position.z = -1.0

func _localize_underwater_materials() -> void:
	# Overrides belong only to this independent scene. Do not modify imported Mesh
	# surface materials or the shared dive cache used by the nine existing maps.
	var local_materials := {}
	for node in find_children("*","MeshInstance3D",true,false):
		if not $ExistingModels.is_ancestor_of(node): continue
		for surface in node.mesh.get_surface_count():
			var old: Material = node.get_active_material(surface)
			if not old is StandardMaterial3D: continue
			var key := old.get_instance_id()
			if not local_materials.has(key):
				var mat := ShaderMaterial.new()
				mat.shader = preload("res://shaders/sunroom_underwater_palette.gdshader")
				mat.set_shader_parameter("has_palette",old.albedo_texture!=null)
				if old.albedo_texture!=null: mat.set_shader_parameter("palette",old.albedo_texture)
				mat.set_shader_parameter("base_color",old.albedo_color)
				mat.set_shader_parameter("vertex_color",old.vertex_color_use_as_albedo)
				mat.set_shader_parameter("roughness_value",old.roughness)
				mat.set_shader_parameter("metallic_value",old.metallic)
				local_materials[key]=mat
				_palette_materials.append(mat)
			node.set_surface_override_material(surface,local_materials[key])
	# 珊瑚也按源材质复用本地副本，不改旧地图共享缓存中的材质。
	for cluster in $Ecology/CoralClusters.get_children():
		var visual: MeshInstance3D = cluster.get_node("Visual")
		for surface in visual.mesh.get_surface_count():
			var old: ShaderMaterial = visual.get_active_material(surface)
			var key := old.get_instance_id()
			if not local_materials.has(key):
				var mat := ShaderMaterial.new()
				mat.shader = preload("res://shaders/sunroom_underwater_palette.gdshader")
				mat.set_shader_parameter("has_palette",false)
				var linear: Color = old.get_shader_parameter("albedo_color")
				mat.set_shader_parameter("base_color",linear.linear_to_srgb())
				mat.set_shader_parameter("roughness_value",old.get_shader_parameter("roughness"))
				mat.set_shader_parameter("metallic_value",old.get_shader_parameter("metallic"))
				local_materials[key] = mat
				_palette_materials.append(mat)
			visual.set_surface_override_material(surface,local_materials[key])

func _is_canyon_ring(node: Node) -> bool:
	# 2026-11-08 回字型沟壁（tall_*）是新增的墙，不参与生态接地。
	# 珊瑚与设施灯属于旧城街面，若把塔身当成支撑面，会被抬到楼顶甚至水面以上。
	var current := node
	while current != null:
		if String(current.name).begins_with("tall_"):
			return true
		current = current.get_parent()
	return false


func _build_surface_index() -> void:
	_surfaces.clear()
	var base := get_node_or_null("ExistingModels/SolarCabinBase")
	if base == null:
		base = get_node_or_null("ExistingModels/SolarCabinBase2")
	for owner_node in [$ExistingModels/SunkenCity, base]:
		if owner_node == null: continue
		for raw in owner_node.find_children("*","MeshInstance3D",true,false):
			var mi := raw as MeshInstance3D
			if mi.mesh == null: continue
			if _is_canyon_ring(mi): continue
			_surfaces.append({"node":mi,"bounds":mi.global_transform*mi.mesh.get_aabb()})
		for raw in owner_node.find_children("*","MultiMeshInstance3D",true,false):
			var mi := raw as MultiMeshInstance3D
			if mi.multimesh == null: continue
			if _is_canyon_ring(mi): continue
			for i in mi.multimesh.instance_count:
				var pose := mi.global_transform*mi.multimesh.get_instance_transform(i)
				_surfaces.append({"node":mi,"mesh":mi.multimesh.mesh,"pose":pose,"bounds":pose*mi.multimesh.mesh.get_aabb()})

func surface_height(x: float,z: float,expected: float,up := 3.0,down := 5.0) -> float:
	var best := NAN
	var difference := INF
	for record in _surfaces:
		var box: AABB = record.bounds
		if x<box.position.x-0.001 or x>box.end.x+0.001 or z<box.position.z-0.001 or z>box.end.z+0.001: continue
		if box.position.y>expected+up or box.end.y<expected-down: continue
		var node: Node3D = record.node
		var mesh: Mesh = record.get("mesh",node.mesh if node is MeshInstance3D else null)
		var pose: Transform3D = record.get("pose",node.global_transform)
		var key: int = mesh.get_instance_id()
		if not _mesh_cache.has(key):
			var triangles := TriangleMesh.new()
			triangles.create_from_faces(mesh.get_faces())
			_mesh_cache[key]=triangles
		var inverse := pose.affine_inverse()
		var origin := inverse*Vector3(x,expected+up+0.001,z)
		var direction := inverse.basis*Vector3.DOWN
		var hit: Dictionary = _mesh_cache[key].intersect_ray(origin,direction.normalized())
		if hit.is_empty(): continue
		var point: Vector3 = pose*hit.position
		if point.y>expected+up or point.y<expected-down: continue
		if absf(point.y-expected)<difference:
			difference=absf(point.y-expected)
			best=point.y
	return best

func _ground_ecology() -> void:
	grounding_results.clear()
	for group in [$Ecology/CoralClusters,$Ecology/FacilityLights]:
		for node in group.get_children():
			var expected: float = node.position.y
			var up: float = node.get_meta("grounding_search_up",5.0)
			var down: float = node.get_meta("grounding_search_down",12.0)
			var height := surface_height(node.position.x,node.position.z,expected,up,down)
			if not is_finite(height):
				# A guessed terrace may not exist at this XZ. Prefer another real
				# model support before falling back below the road to terrain.
				height = surface_height(node.position.x,node.position.z,expected,80.0,80.0)
			if not is_finite(height):
				height = $ExistingModels/SunkenSeabed.data.get_height(Vector3(node.position.x,0,node.position.z))
			var offset := 0.015 if group.name=="CoralClusters" else 0.01
			var ok := is_finite(height) and height+offset<water_level
			if ok: node.position.y=height+offset
			grounding_results.append({"node":str(node.get_path()),"expected_y":expected,"height":height,"ok":ok,"position":[node.position.x,node.position.y,node.position.z]})

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_visible_in_tree(): return
	_clock+=delta
	_update_underwater_view()
	if _notice != null:
		var viewer_y: float = dive_position().y if _diving else $Camera.global_position.y
		_notice.text="水深 %.1f 米 · 旧城 240 × 240 米" % maxf(0.0,water_level-viewer_y)
	_surface_material.set_shader_parameter("elapsed",_clock)

## 世界对齐入水：海面 XZ 原样保留，只在水面下方找一处真实净空。
## 刚进树时物理空间还没有这座旧城的碰撞体，此刻选点等于闭眼——先占住水面点，
## 等碰撞提交后再真正定位，然后再开放游动与耗氧。
func begin_dive(surface_point: Vector3) -> bool:
	if _diving or dive_controller == null: return false
	_surface_entry = surface_point
	_diver_reset_for_entry(surface_point)
	if not dive_controller.begin({"surface_point": surface_point}):
		_diving = false
		return false
	_diving = true
	$RegionHUD.hide()
	zone_changed.emit(map_label)
	_resolve_entry.call_deferred()
	return true

func _diver_reset_for_entry(surface_point: Vector3) -> void:
	_exit_left = -1.0
	entry_verified = false
	# 占位与最终落点用同一个高度（水面下 1 米），中间不再有「先空白水柱再瞬移」。
	diver_pos = Vector3(surface_point.x, water_level - float(entry_depth_below_surface), surface_point.z)
	if collision_runtime != null:
		collision_runtime.set_viewer_position(diver_pos)
	if _lamp == null: _build_dive_lamp()
	_lamp.visible = air.lamp
	air_changed.emit(air.ratio(), air.lamp, 0, 0)

func dive_water_level() -> float:
	return water_level

func dive_begin(_payload: Dictionary) -> void:
	_diving = true
	$Water.show()
	_update_underwater_view()

func dive_entry_tick(_dt: float) -> bool:
	return entry_verified

func dive_exit_begin() -> void:
	_exit_left = 0.0
	_exit_start = dive_position()
	_exit_surface = Vector3(_exit_start.x, water_level, _exit_start.z)

func dive_exit_tick(dt: float) -> bool:
	_exit_left += dt
	var blend := smoothstep(0.0, 1.0, minf(_exit_left / maxf(0.05, exit_seconds), 1.0))
	dive_set_position(_exit_start.lerp(_exit_surface, blend))
	return blend >= 1.0

func dive_end() -> void:
	$Water.hide()
	_finish_dive()

func dive_position() -> Vector3:
	return diver_pos

func dive_set_position(p: Vector3) -> void:
	if not p.is_finite(): return
	diver_pos = p
	if collision_runtime != null and collision_runtime.viewer != null:
		collision_runtime.set_viewer_position(p)

func dive_move(displacement: Vector3) -> Vector3:
	if collision_runtime == null: return Vector3.ZERO
	var moved := collision_runtime.move_viewer(displacement)
	diver_pos = collision_runtime.viewer.global_position
	return moved

func dive_route(dest: Vector3) -> Array:
	if collision_runtime == null or not dest.is_finite():
		return []
	var start := dive_position()
	if not _dive_point_in_bounds(dest):
		return []
	if _dive_segment_clear(start, dest):
		return [dest]
	var offsets := [
		Vector3(8, 0, 0), Vector3(-8, 0, 0), Vector3(0, 0, 8), Vector3(0, 0, -8),
		Vector3(8, 4, 0), Vector3(-8, 4, 0), Vector3(0, 4, 8), Vector3(0, 4, -8),
		Vector3(8, -4, 0), Vector3(-8, -4, 0), Vector3(0, -4, 8), Vector3(0, -4, -8)]
	for offset in offsets:
		var waypoint: Vector3 = start + offset
		if _dive_point_in_bounds(waypoint) and _dive_segment_clear(start, waypoint) and _dive_segment_clear(waypoint, dest):
			return [waypoint, dest]
	return []

func _dive_point_in_bounds(point: Vector3) -> bool:
	return point.y >= viewer_min_y and point.y <= water_level - 0.82 \
		and terrain_bounds.has_point(Vector2(point.x, point.z))

func _dive_segment_clear(start: Vector3, end: Vector3) -> bool:
	if not _dive_point_in_bounds(start) or not _dive_point_in_bounds(end):
		return false
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, start)
	query.motion = end - start
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	if collision_runtime.viewer != null:
		query.exclude = [collision_runtime.viewer.get_rid()]
	var cast := get_world_3d().direct_space_state.cast_motion(query)
	return cast.is_empty() or float(cast[0]) >= 0.999

func dive_cancel_content() -> void:
	pass

func dive_content_tick(_dt: float) -> void:
	diver_pos = dive_position()
	depth = maxf(0.0, water_level - diver_pos.y)
	depth_changed.emit(depth)
	zone_changed.emit(map_label)
	if _lamp != null:
		_lamp.visible = air.lamp and _diving
	air_changed.emit(air.ratio(), air.lamp, 0, 0)

func dive_camera_clip(target: Vector3, desired: Vector3, radius: float) -> Vector3:
	var distance_to_target := target.distance_to(desired)
	if distance_to_target <= 0.001 or collision_runtime == null:
		return desired
	var shape := SphereShape3D.new()
	shape.radius = maxf(0.05, radius)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, target)
	query.motion = desired - target
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	if collision_runtime.viewer != null:
		query.exclude = [collision_runtime.viewer.get_rid()]
	var cast := get_world_3d().direct_space_state.cast_motion(query)
	if cast.is_empty() or float(cast[0]) >= 0.999:
		return desired
	return target.lerp(desired, maxf(0.0, float(cast[0]) - 0.02))

func dive_zone_label() -> String:
	return map_label

## 等 Terrain3D 与逐 Mesh 碰撞真正提交后，再按「能站、能看、离得近」选入水点。
func _resolve_entry() -> void:
	# 判据必须确定：正常情形下从水面垂直向下一定能打到海床。打不到就说明碰撞
	# 还没进物理空间，此时选点等于闭眼——射线全返回「无遮挡」，会选中楼体内部。
	var space := get_world_3d().direct_space_state
	var probe := Vector3(_surface_entry.x,water_level-0.2,_surface_entry.z)
	var ready := false
	# 水面到上街面现在是 120 米整，射线长度必须留出余量，否则永远等不到碰撞就绪。
	for attempt in 24:
		await get_tree().physics_frame
		if not _diving or dive_controller == null or dive_controller.machine.current != "enter": return
		if _ray_distance(space,probe,Vector3.DOWN,220.0) < 215.0:
			ready = true
			break
	if not ready:
		message.emit("海底碰撞未就绪，已返回海面")
		surface()
		return
	for attempt in 6:
		var spot := _entry_spot(_surface_entry)
		if spot.is_finite() and collision_runtime.try_set_viewer_position(spot):
			diver_pos = spot
			dive_set_position(spot)
			_face_city()
			entry_verified = true
			depth_changed.emit(maxf(0.0,water_level-spot.y))
			air_changed.emit(air.ratio(),air.lamp,0,0)
			return
		await get_tree().physics_frame
	message.emit("这段水下没有可入水的空间，已返回海面")
	surface()

## 水面下 1 米的悬停点：这个高度没有路面可踩，是自由游动的起点。
## 只做两件硬校验——胶囊不与实体重叠、头顶 3 米是水（能立刻上浮回海面）。
func _entry_spot_below_surface(surface_point: Vector3) -> Vector3:
	var entry_y: float = water_level - float(entry_depth_below_surface)
	var space := get_world_3d().direct_space_state
	var radii: Array = [0.0, 3.0, 6.0, 10.0, 15.0, 22.0, 30.0, 40.0, 52.0, float(entry_search_radius)]
	for radius in radii:
		var steps: int = 1 if float(radius) == 0.0 else 12
		for step in steps:
			var angle := TAU * float(step) / 12.0
			var column := Vector2(surface_point.x, surface_point.z) + Vector2(cos(angle), sin(angle)) * float(radius)
			if not city_bounds.has_point(column): continue
			var candidate := Vector3(column.x, entry_y, column.y)
			if _ray_distance(space, candidate, Vector3.UP, 3.0) < 2.0: continue
			if not collision_runtime.try_set_viewer_position(candidate): continue
			# 朝向沟心：一入水就能看到对面的楼墙，而不是贴着一面墙。
			var inward := Vector3(-column.x, 0.0, -column.y)
			_entry_face = inward.normalized() if inward.length() > 1.0 else Vector3(0.0, 0.0, -1.0)
			if OS.get_environment("SEA_DIVE_TRACE") == "1":
				print("[entry] shallow r=", radius, " pos=", candidate, " depth=", water_level - candidate.y)
			return candidate
	return Vector3(0, NAN, 0)


func _entry_spot(surface_point: Vector3) -> Vector3:
	# 2026-11-08 用户要求「下水后的位置在水下 1 米」：优先用浅水悬停点，
	# 让玩家一眼看到 120 米深沟的全貌，再自己往下游。
	var shallow := _entry_spot_below_surface(surface_point)
	if shallow.is_finite(): return shallow
	# 兜底：浅水层被楼体占住时，落回旧城街面层，复用原有净空/顶空判据。
	var search := float(entry_search_radius)
	var radii: Array = [16.0,18.0,20.0,24.0,28.0,36.0,44.0,52.0,search]
	var best := Vector3(0,NAN,0)
	var best_score := -INF
	var space := get_world_3d().direct_space_state
	for radius in radii:
		for step in 12:
			var angle := TAU*float(step)/12.0
			var column := Vector2(surface_point.x,surface_point.z)+Vector2(cos(angle),sin(angle))*float(radius)
			if not city_bounds.has_point(column): continue
			var road := surface_height(column.x,column.y,entry_street_y,9.0,9.0)
			if not is_finite(road) or road > -8.0: continue
			# 楼层之间：比路面高 6~12 米，低于屋顶，视线正好平着看街道两侧。
			for rise in [12.0,10.0,8.0,6.0]:
				var candidate := Vector3(column.x,road+rise,column.y)
				if candidate.y > water_level-float(entry_drop): continue
				# 真正的街景必须头顶是水：向上看不到楼板/屋檐。
				if _ray_distance(space,candidate,Vector3.UP,18.0) < 16.0: continue
				if not collision_runtime.try_set_viewer_position(candidate): continue
				# 只检查「胶囊不重叠」会放过贴着楼面的点：胶囊很细，站得下但镜头贴墙。
				# 这里用一个半径 12 米的球做净空检查，等价于「站在街心/广场，四周有余地」。
				if not _wide_clearance(candidate,12.0): continue
				# 朝向要有一栋 18~38 米的楼：贴墙会顶满画面，纯广场又只剩空水面，
				# 中景才有「沉没街区」的纵深。
				var face := Vector3.ZERO
				var best_gap := INF
				for index in 24:
					var angle2 := TAU*float(index)/24.0
					var direction := Vector3(cos(angle2),0.0,sin(angle2))
					var distance := _ray_distance(space,candidate,direction,42.0)
					if distance < 18.0 or distance > 38.0: continue
					if absf(distance-26.0) < absf(best_gap-26.0):
						best_gap = distance
						face = direction
				if face == Vector3.ZERO: continue
				var score: float = -absf(best_gap-26.0)*0.8 + float(rise)*1.2 - float(radius)*0.3
				if OS.get_environment("SEA_DIVE_TRACE")=="1":
					print("[entry] street r=",radius," pos=",candidate," road=",road," gap=",best_gap," score=",score)
				if score>best_score:
					best_score = score
					best = candidate
					_entry_face = face
		if best.is_finite(): break
	if best.is_finite(): return best
	# 没有街景支撑时也不能把人放在水面下 6m：那会把角色留在阳光房
	# 基座的空腔或屋顶下。保底仍落到旧城街面层，并复用同一净空/顶空判据；
	# 找不到真正开阔的街面就拒绝这次入水，由会话安全返回海面，不把坏取景当成功。
	for radius in radii:
		for step in 12:
			var angle := TAU*float(step)/12.0
			var column := Vector2(surface_point.x,surface_point.z)+Vector2(cos(angle),sin(angle))*float(radius)
			if not city_bounds.has_point(column): continue
			var road := surface_height(column.x,column.y,entry_street_y,9.0,9.0)
			var fallback_y := road + entry_rise if is_finite(road) else entry_street_y + entry_rise
			var candidate := Vector3(column.x,fallback_y,column.y)
			if candidate.y > water_level-float(entry_drop): continue
			if _ray_distance(space,candidate,Vector3.UP,18.0) < 16.0: continue
			if not collision_runtime.try_set_viewer_position(candidate): continue
			# The authored city can be denser than the ideal cinematic ring. The
			# capsule and ceiling tests above are the hard safety contract; the
			# shared camera clip handles a close lateral wall and the player can
			# immediately swim into wider water.
			return candidate
	# Last bounded fallback: a real street-level capsule with open headroom is
	# preferable to failing the dive; the shared camera clip handles the close
	# lateral wall and the player can immediately swim into wider water.
	for radius in radii:
		for step in 12:
			var angle := TAU * float(step) / 12.0
			var column := Vector2(surface_point.x, surface_point.z) + Vector2(cos(angle), sin(angle)) * float(radius)
			if not city_bounds.has_point(column): continue
			var road := surface_height(column.x, column.y, entry_street_y, 80.0, 80.0)
			var candidate := Vector3(column.x, road + entry_rise if is_finite(road) else entry_street_y + entry_rise, column.y)
			if candidate.y > water_level - float(entry_drop): continue
			if _ray_distance(space, candidate, Vector3.UP, 18.0) < 16.0: continue
			if collision_runtime.try_set_viewer_position(candidate): return candidate
	return Vector3(0,NAN,0)

func _ray_distance(space: PhysicsDirectSpaceState3D,point: Vector3,direction: Vector3,length: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(point,point+direction*length,1)
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	return length if hit.is_empty() else point.distance_to(hit.position)

## 球形净空：半径 r 内不得与任何结构相交，用来排除「贴墙站得下但镜头怼砖面」。
func _wide_clearance(point: Vector3,radius: float) -> bool:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY,point)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

## 入水后先按「最开阔方向」摆正镜头，避免一睁眼就是一面砖墙。
func _face_city() -> void:
	var facing := Vector2.ZERO
	if _entry_face.length_squared()>0.0001: facing = Vector2(_entry_face.x,_entry_face.z)
	if facing.length_squared()<0.0001: facing = Vector2(0,-1)
	facing = facing.normalized()
	# Godot 相机朝 -Z；yaw 让 -Z 指向该水平方向，略向下俯视街道。
	_yaw = atan2(-facing.x,-facing.y)
	# 略微平视：入水后先看清旧城轮廓，而不是低头看自己的脚和地砖。
	_pitch = -0.03
	if dive_controller != null:
		dive_controller.yaw = _yaw
		dive_controller.pitch = _pitch
		dive_controller.update_camera(0.0, true)

func _build_dive_lamp() -> void:
	_lamp = SpotLight3D.new()
	_lamp.name = "DiveLamp"
	_lamp.light_color = Color(1.0,0.93,0.78)
	_lamp.light_energy = 2.2
	_lamp.spot_range = 26.0
	_lamp.spot_angle = 40.0
	_lamp.shadow_enabled = false
	$Camera.add_child(_lamp)

func surface() -> void:
	if dive_controller != null:
		dive_controller.request_surface()

func abort_to_surface() -> void:
	surface()

func _finish_dive() -> void:
	_diving = false
	_exit_left = -1.0
	entry_verified = false
	if _lamp != null: _lamp.visible = false
	exited.emit()

## 家园海底没有宝箱：进度仍按旧 v4 结构返回空表，存档键不扩张。
func to_dict() -> Dictionary: return {"found":[],"opened":[]}
func from_dict(_data: Dictionary) -> void: pass
func chest_count() -> int: return 0
func discovered_count() -> int: return 0
func opened_chests() -> int: return 0
func uses_underwater_environment() -> bool: return _diving

func swim_to(destination: Vector3) -> bool:
	return dive_controller.swim_to(destination) if dive_controller != null else false

func swim_to_screen(screen: Vector2) -> bool:
	return dive_controller.swim_to_screen(screen) if dive_controller != null else false

func cancel_navigation() -> void:
	if dive_controller != null: dive_controller.cancel_navigation()

func navigate_path(points: Array) -> bool:
	return dive_controller.navigate_path(points) if dive_controller != null else false

func toggle_lamp() -> void:
	if dive_controller != null: dive_controller.toggle_lamp()

func debug_teleport(p: Vector3) -> void:
	if dive_controller != null: dive_controller.debug_teleport(p)

func snapshot() -> Dictionary:
	return dive_controller.snapshot() if dive_controller != null else {}

func move_viewer(displacement: Vector3) -> Vector3:
	return dive_move(displacement)

func set_viewer_position(world_position: Vector3) -> void:
	dive_set_position(world_position)

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _diving: return
	# F6 预览保留家园自己的 ViewerBody 移动；潜水输入由共享控制器独占。
	if not _drag: return
	var direction := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): direction.z -= 1
	if Input.is_physical_key_pressed(KEY_S): direction.z += 1
	if Input.is_physical_key_pressed(KEY_A): direction.x -= 1
	if Input.is_physical_key_pressed(KEY_D): direction.x += 1
	if Input.is_physical_key_pressed(KEY_E): direction.y += 1
	if Input.is_physical_key_pressed(KEY_Q): direction.y -= 1
	if direction.length_squared() > 0.0:
		var speed := 18.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 8.0
		move_viewer($Camera.global_basis * direction.normalized() * speed * _delta)

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or _diving: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_drag = event.pressed
	elif event is InputEventMouseMotion and _drag:
		_yaw -= event.relative.x * 0.004
		_pitch = clampf(_pitch - event.relative.y * 0.004, -1.4, 1.4)
		$Camera.rotation = Vector3(_pitch, _yaw, 0)
