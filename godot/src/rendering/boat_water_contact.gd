extends RefCounted
## Dynamic vessel contact belongs to WaterSurface; Boat exposes visual queries only.
const MAX_OUTLINE := 24
## One live channel per oar. Blade entries used to be pooled in `u_ripples`,
## which made the ocean draw its generic ripple ring over the same point, so
## every stroke came out as a bullseye inside a bullseye.
const MAX_BLADES := 8
var outline := PackedVector2Array()
var world_outline := PackedVector4Array()
var blade_uniform := PackedVector4Array()
var _model_id := 0
var _wet := [false, false]
var _last_touch := [-100.0, -100.0]
var _previous := Vector2.INF
var touch_count := 0
var last_touches: Array[Dictionary] = []

func _init() -> void:
	blade_uniform.resize(MAX_BLADES)
	blade_uniform.fill(Vector4(0.0, 0.0, -100.0, 0.0))

func update(t: float, boat: Node3D, surface: MeshInstance3D) -> void:
	var visual: Node3D = boat.model
	var mat := surface.material_override as ShaderMaterial
	if mat == null:
		return
	if visual == null or not visual.is_visible_in_tree() or not boat.is_visible_in_tree():
		mat.set_shader_parameter("boat_hull_count",0)
		return
	if visual.get_instance_id()!=_model_id:
		_model_id=visual.get_instance_id()
		outline=_waterline(boat.hull_visual(),visual) if boat.has_method("hull_visual") else PackedVector2Array()
		_wet=[false,false]
	world_outline.resize(MAX_OUTLINE)
	world_outline.fill(Vector4.ZERO)
	for i in outline.size():
		var p: Vector3=visual.global_transform*Vector3(outline[i].x,0.0,outline[i].y)
		world_outline[i]=Vector4(p.x,p.z,p.y,0)
	mat.set_shader_parameter("boat_hull_points",world_outline)
	mat.set_shader_parameter("boat_hull_count",outline.size())
	var position := Vector2(boat.global_position.x,boat.global_position.z)
	if _previous.is_finite() and position.distance_to(_previous)>8.0:
		_wet=[false,false]
		_last_touch=[t,t]
	_previous=position
	var effort: float=boat.rowing_state().y
	if not boat.starts_sailing() or effort<0.15:
		_wet=[false,false]
		mat.set_shader_parameter("boat_blade_points",blade_uniform)
		mat.set_shader_parameter("boat_blade_count",MAX_BLADES)
		return
	var blades: PackedVector3Array=boat.oar_blade_positions()
	for i in mini(blades.size(),2):
		var p: Vector3=blades[i]
		if not p.is_finite():
			_wet[i]=false
			continue
		var sea_y: float=surface.global_position.y+surface.sample_surface(Vector2(p.x,p.z)).x
		var depth := sea_y-p.y
		if depth < -0.06:
			_wet[i]=false
			continue
		if depth >= -0.015:
			# A blade does not splash once and stop: while it is in the water it
			# keeps dragging it. Recording only the entry instant left one fleck
			# behind the moving boat, which read as debris rather than a stroke.
			# Refreshing the timestamp every wet frame keeps the splash under the
			# blade; releasing it lets the age clock fade it out in place.
			if not _wet[i]:
				_wet[i]=true
				if t-float(_last_touch[i])<0.35:continue
				_last_touch[i]=t
				touch_count+=1
				last_touches.append({"side":i,"position":p,"surface_y":sea_y,"time":t})
				if last_touches.size()>16:last_touches.pop_front()
			blade_uniform[i]=Vector4(p.x,p.z,t,lerpf(0.65,1.0,effort))
	mat.set_shader_parameter("boat_blade_points",blade_uniform)
	mat.set_shader_parameter("boat_blade_count",MAX_BLADES)

func _waterline(hull: Node3D, model: Node3D) -> PackedVector2Array:
	var points := PackedVector2Array()
	if hull==null:return points
	for visual in hull.find_children("*","MeshInstance3D",true,false):
		if visual.mesh==null:continue
		var transform: Transform3D=model.global_transform.affine_inverse()*visual.global_transform
		var faces: PackedVector3Array=visual.mesh.get_faces()
		for i in range(0,faces.size()-2,3):
			var triangle := [transform*faces[i],transform*faces[i+1],transform*faces[i+2]]
			for j in 3:
				var a: Vector3=triangle[j]
				var b: Vector3=triangle[(j+1)%3]
				if (a.y<=0 and b.y>0) or (b.y<=0 and a.y>0):
					var p := a.lerp(b,-a.y/(b.y-a.y))
					points.append(Vector2(p.x,p.z))
	if points.size()<3:return PackedVector2Array()
	var result := Geometry2D.convex_hull(points)
	if result[0].is_equal_approx(result[-1]):result.remove_at(result.size()-1)
	# Remove the least significant corner, retaining pointed bow and flat transom.
	while result.size()>MAX_OUTLINE:
		var smallest := INF
		var remove := 0
		for i in result.size():
			var a: Vector2=result[(i-1+result.size())%result.size()]
			var b: Vector2=result[i]
			var c: Vector2=result[(i+1)%result.size()]
			var area := absf((b-a).cross(c-a))
			if area<smallest:smallest=area;remove=i
		result.remove_at(remove)
	return result
