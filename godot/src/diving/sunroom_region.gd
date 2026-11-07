@tool
extends Node3D
## Independent authored scene, not a replacement for any of the nine dive maps.
@export var water_level := 1.12
@export var city_bounds := Rect2(-120,-120,240,240)
@export var terrain_bounds := Rect2(-512,-512,1024,1024)
@export var lowest_seabed_y := -62.0
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
var collision_runtime: RegionCollision

## 家园海底：与海面共用世界坐标，因此没有固定出生点，只有下水点换算。
@export var map_id := "dive_home_seabed"
@export var chest_id_base := 900
@export var map_label := "家园海底"
## 入水深度要越过换气层（DiveAir 的 5 m 水面带），否则一入水就一直满氧。
@export var entry_drop := 6.0
@export var entry_search_radius := 30.0
@export var swim_speed := 4.2
@export var exit_seconds := 0.55

signal depth_changed(depth: float)
signal zone_changed(label: String)
signal air_changed(ratio: float, lamp_on: bool, found: int, total: int)
signal message(text: String)
signal exited

var air = DiveAirScript.new()
## 潜水会话的通用注入点；家园海底没有宝箱，保留空接口以免会话写属性报错。
var give_resource: Callable
var give_rewards: Callable
var phase := "surface"
var diver_pos := Vector3.ZERO
var depth := 0.0
var _diving := false
var _exit_left := -1.0
var _swimming := false
var _swim_target := Vector3.ZERO
var _air_emit := 0.0
var _lamp: SpotLight3D
## 入水点是否已在物理提交后复核过净空；Terrain3D 碰撞是延后提交的。
var entry_verified := false
var _surface_entry := Vector3.ZERO
var _entry_face := Vector3.ZERO

func _ready() -> void:
	if Engine.is_editor_hint(): return
	_build_surface_index()
	_ground_ecology()
	_localize_underwater_materials()
	_build_water_fog()
	collision_runtime = RegionCollision.new()
	collision_runtime.name = "RegionCollision"
	add_child(collision_runtime)
	collision_runtime.setup(self)
	var camera: Camera3D = $Camera
	_yaw = camera.rotation.y
	_pitch = camera.rotation.x
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

func _build_water_fog() -> void:
	var environment: Environment = $WorldEnvironment.environment
	environment.fog_enabled = false
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2,2)
	var pass_node := MeshInstance3D.new()
	pass_node.name = "WaterFogPass"
	pass_node.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/sunroom_underwater_fog.gdshader")
	mat.render_priority = -128
	pass_node.material_override = mat
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
			node.set_surface_override_material(surface,local_materials[key])
	# The reef material cache owns lamp/depth globals in old maps. A local copy
	# leaves those globals untouched and lets the same environment fog handle it.
	for cluster in $Ecology/CoralClusters.get_children():
		var visual: MeshInstance3D = cluster.get_node("Visual")
		for surface in visual.mesh.get_surface_count():
			var old: ShaderMaterial = visual.get_active_material(surface)
			var mat := ShaderMaterial.new()
			mat.shader = preload("res://shaders/sunroom_underwater_palette.gdshader")
			mat.set_shader_parameter("has_palette",false)
			var linear: Color = old.get_shader_parameter("albedo_color")
			mat.set_shader_parameter("base_color",linear.linear_to_srgb())
			mat.set_shader_parameter("roughness_value",old.get_shader_parameter("roughness"))
			mat.set_shader_parameter("metallic_value",old.get_shader_parameter("metallic"))
			visual.set_surface_override_material(surface,mat)

func _build_surface_index() -> void:
	_surfaces.clear()
	for owner_node in [$ExistingModels/SunkenCity,$ExistingModels/SolarCabinBase]:
		for raw in owner_node.find_children("*","MeshInstance3D",true,false):
			var mi := raw as MeshInstance3D
			if mi.mesh == null: continue
			_surfaces.append({"node":mi,"bounds":mi.global_transform*mi.mesh.get_aabb()})
		for raw in owner_node.find_children("*","MultiMeshInstance3D",true,false):
			var mi := raw as MultiMeshInstance3D
			if mi.multimesh == null: continue
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
	if Engine.is_editor_hint(): return
	_clock+=delta
	if _notice != null: _notice.text="水深 %.1f 米 · 旧城 240 × 240 米" % maxf(0,water_level-$Camera.position.y)
	$Water.material_override.set_shader_parameter("elapsed",_clock)
	var environment: Environment = $WorldEnvironment.environment
	var view_depth := maxf(0.0,water_level-$Camera.global_position.y)
	environment.sky.sky_material.set_shader_parameter("region_view_depth",view_depth)
	$Camera/WaterFogPass.material_override.set_shader_parameter("region_view_depth",view_depth)
	$Atmosphere.set_view_depth(view_depth)
	environment.ambient_light_energy = lerpf(0.48,0.29,smoothstep(18.0,60.0,view_depth))
	$SunRays.light_energy = lerpf(0.60,0.30,smoothstep(14.0,60.0,view_depth))
	if _diving: _update_dive(delta,view_depth)

## 世界对齐入水：海面 XZ 原样保留，只在水面下方找一处真实净空。
## 刚进树时物理空间还没有这座旧城的碰撞体，此刻选点等于闭眼——先占住水面点，
## 等碰撞提交后再真正定位，然后再开放游动与耗氧。
func begin_dive(surface_point: Vector3) -> bool:
	if _diving: return false
	_surface_entry = surface_point
	_diving = true
	phase = "enter"
	_swimming = false
	_exit_left = -1.0
	_air_emit = 0.0
	entry_verified = false
	diver_pos = Vector3(surface_point.x,water_level-float(entry_drop),surface_point.z)
	collision_runtime.set_viewer_position(diver_pos)
	air.refill()
	$RegionHUD.hide()
	if _lamp == null: _build_dive_lamp()
	_lamp.visible = air.lamp
	air_changed.emit(air.ratio(),air.lamp,0,0)
	zone_changed.emit(map_label)
	_resolve_entry.call_deferred()
	return true

## 等 Terrain3D 与逐 Mesh 碰撞真正提交后，再按「能站、能看、离得近」选入水点。
func _resolve_entry() -> void:
	# 判据必须确定：正常情形下从水面垂直向下一定能打到海床。打不到就说明碰撞
	# 还没进物理空间，此时选点等于闭眼——射线全返回「无遮挡」，会选中楼体内部。
	var space := get_world_3d().direct_space_state
	var probe := Vector3(_surface_entry.x,water_level-0.2,_surface_entry.z)
	var ready := false
	for attempt in 24:
		await get_tree().physics_frame
		if not _diving or phase!="enter": return
		if _ray_distance(space,probe,Vector3.DOWN,120.0) < 119.0:
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
			_face_city()
			entry_verified = true
			phase = "swim"
			depth_changed.emit(maxf(0.0,water_level-spot.y))
			air_changed.emit(air.ratio(),air.lamp,0,0)
			return
		await get_tree().physics_frame
	message.emit("这段水下没有可入水的空间，已返回海面")
	surface()

func _entry_spot(surface_point: Vector3) -> Vector3:
	# 用旧城自己的路面数据落地，而不是「空中随便找个不重叠的位置」：
	# 阳光房基座是个空腔，从水面往下看一片「无遮挡」，站进去只会看到内壁。
	# 落点还要满足「前方 20~40 米有楼」——这样一入水就是街景，而不是空广场。
	# 阳光房基座本身是一片实心轮廓（缩放后半径约 15 米），必须从轮廓外开始找，
	# 否则射线会把基座内壁当成「街道两侧的楼」。
	var search := float(entry_search_radius)
	var radii: Array = [16.0,18.0,20.0,24.0,28.0,search]
	var best := Vector3(0,NAN,0)
	var best_score := -INF
	var space := get_world_3d().direct_space_state
	for radius in radii:
		for step in 12:
			var angle := TAU*float(step)/12.0
			var column := Vector2(surface_point.x,surface_point.z)+Vector2(cos(angle),sin(angle))*float(radius)
			if not city_bounds.has_point(column): continue
			var road := surface_height(column.x,column.y,-18.0,9.0,9.0)
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
	# 完全没有街区支撑时（例如落在观赏区外），退回「只要净空」保证还能下水。
	for radius in radii:
		for step in 12:
			var angle := TAU*float(step)/12.0
			var column := Vector2(surface_point.x,surface_point.z)+Vector2(cos(angle),sin(angle))*float(radius)
			var candidate := Vector3(column.x,water_level-float(entry_drop),column.y)
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
	$Camera.rotation = Vector3(_pitch,_yaw,0)

func _build_dive_lamp() -> void:
	_lamp = SpotLight3D.new()
	_lamp.name = "DiveLamp"
	_lamp.light_color = Color(1.0,0.93,0.78)
	_lamp.light_energy = 2.2
	_lamp.spot_range = 26.0
	_lamp.spot_angle = 40.0
	_lamp.shadow_enabled = false
	$Camera.add_child(_lamp)

func _update_dive(delta: float, view_depth: float) -> void:
	diver_pos = collision_runtime.viewer.global_position
	depth = view_depth
	if phase=="swim":
		var moving: bool = _swimming or _drag
		var sprint: bool = _drag and Input.is_physical_key_pressed(KEY_SHIFT)
		var event: String = air.update(delta,view_depth,moving,sprint)
		if event=="empty":
			message.emit("氧气耗尽 · 强制上浮")
			surface()
		elif event=="crit": message.emit("氧气危急 · 立刻上浮")
		elif event=="low": message.emit("余气不多了")
		if _lamp != null: _lamp.visible = air.lamp
		_air_emit -= delta
		if _air_emit<=0.0:
			_air_emit = 0.25
			air_changed.emit(air.ratio(),air.lamp,0,0)
	depth_changed.emit(depth)

func surface() -> void:
	if not _diving or phase=="exit": return
	phase = "exit"
	_swimming = false
	_exit_left = float(exit_seconds)

func abort_to_surface() -> void:
	surface()

func _finish_dive() -> void:
	_diving = false
	phase = "surface"
	_swimming = false
	_exit_left = -1.0
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
	if not _diving or phase!="swim": return false
	if not destination.is_finite(): return false
	_swim_target = destination
	_swimming = true
	return true

func cancel_navigation() -> void:
	_swimming = false

func toggle_lamp() -> void:
	air.lamp = not air.lamp
	if _lamp != null: _lamp.visible = air.lamp and _diving
	air_changed.emit(air.ratio(),air.lamp,0,0)

func move_viewer(displacement: Vector3) -> Vector3:
	return collision_runtime.move_viewer(displacement)

func set_viewer_position(world_position: Vector3) -> void:
	collision_runtime.set_viewer_position(world_position)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	if _diving:
		_dive_move(delta)
		return
	if not _drag: return
	var direction := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): direction.z-=1
	if Input.is_physical_key_pressed(KEY_S): direction.z+=1
	if Input.is_physical_key_pressed(KEY_A): direction.x-=1
	if Input.is_physical_key_pressed(KEY_D): direction.x+=1
	if Input.is_physical_key_pressed(KEY_E): direction.y+=1
	if Input.is_physical_key_pressed(KEY_Q): direction.y-=1
	var speed := 18.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 8.0
	move_viewer($Camera.global_basis*direction.normalized()*speed*delta)

func _dive_move(delta: float) -> void:
	if phase=="enter": return
	if phase=="exit":
		_exit_left -= delta
		# 上浮是一小段可见的上升，不是瞬移；到水面后由会话恢复海面实例。
		move_viewer(Vector3.UP*maxf(0.0,depth)/maxf(0.05,float(exit_seconds))*delta)
		if _exit_left<=0.0: _finish_dive()
		return
	var direction := Vector3.ZERO
	if _swimming:
		var to_target: Vector3 = _swim_target-diver_pos
		if to_target.length()<=0.35:
			_swimming = false
		else:
			direction = to_target.normalized()
			if not _drag:
				move_viewer(direction*float(swim_speed)*delta)
				return
	if _drag:
		if Input.is_physical_key_pressed(KEY_W): direction+= $Camera.global_basis*Vector3.FORWARD
		if Input.is_physical_key_pressed(KEY_S): direction+= $Camera.global_basis*Vector3.BACK
		if Input.is_physical_key_pressed(KEY_A): direction-= $Camera.global_basis*Vector3.RIGHT
		if Input.is_physical_key_pressed(KEY_D): direction+= $Camera.global_basis*Vector3.RIGHT
		if Input.is_physical_key_pressed(KEY_E): direction+=Vector3.UP
		if Input.is_physical_key_pressed(KEY_Q): direction-=Vector3.UP
	if direction.length_squared()>0.0:
		var speed: float = 7.0 if Input.is_physical_key_pressed(KEY_SHIFT) else float(swim_speed)
		move_viewer(direction.normalized()*speed*delta)

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint(): return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT:
		_drag=event.pressed
	elif event is InputEventMouseMotion and _drag:
		_yaw-=event.relative.x*0.004
		_pitch=clampf(_pitch-event.relative.y*0.004,-1.4,1.4)
		$Camera.rotation=Vector3(_pitch,_yaw,0)
