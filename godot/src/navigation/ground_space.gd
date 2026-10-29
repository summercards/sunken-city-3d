extends Node3D
## Runtime ground projection. Owns only derived collision/navigation, never layout.
## Existing authored walking surfaces remain the migration input; new surfaces
## can provide arbitrary world-space triangles (floors, ramps and upper storeys).
const GROUND_LAYER := 256
const ACTOR_LAYER := 512
const ACTOR_RADIUS := 0.22
const ACTOR_HEIGHT := 1.30
const ENDPOINT_TOLERANCE := 0.25
const EPS := 0.0001
const GroundPath = preload("res://src/navigation/ground_path.gd")
const ActorCollision = preload("res://src/navigation/actor_collision_body.gd")

var revision := 0
var navigation_polygons := 0
var _areas: Array = []
var _map := RID()
var _regions: Array[RID] = []
var _meshes: Array[NavigationMesh] = []
var _bodies: Array[StaticBody3D] = []
var _signature := 0

func configure(areas: Array) -> void:
	clear()
	_areas = areas.duplicate()
	for area in _areas:
		if is_instance_valid(area): area.ground_space = self
	rebuild()

func clear() -> void:
	for area in _areas:
		if is_instance_valid(area) and area.ground_space == self: area.ground_space = null
	_areas.clear()
	_free_projection()
	_signature = 0

func _exit_tree() -> void:
	clear()

func _free_projection() -> void:
	for body in _bodies:
		if is_instance_valid(body):
			remove_child(body)
			body.free()
	_bodies.clear()
	for region in _regions: NavigationServer3D.free_rid(region)
	_regions.clear()
	_meshes.clear()
	if _map.is_valid(): NavigationServer3D.free_rid(_map)
	_map = RID()

func rebuild(_area: Node3D = null) -> void:
	var records: Array = []
	var signature_data: Array = []
	for area in _areas:
		if not is_instance_valid(area): continue
		var faces: PackedVector3Array = _upward_faces(area.surface_faces())
		records.append({"area": area, "faces": faces})
		signature_data.append([area.get_instance_id(), faces, float(area.body_radius)])
	var next_signature := hash(signature_data)
	if _map.is_valid() and next_signature == _signature: return
	_signature = next_signature
	_free_projection()
	revision += 1
	navigation_polygons = 0
	_map = NavigationServer3D.map_create()
	# Command/query interfaces can be used immediately by restore, construction
	# and deterministic state tests; this private map has no async consumers.
	NavigationServer3D.map_set_use_async_iterations(_map, false)
	NavigationServer3D.map_set_active(_map, true)
	NavigationServer3D.map_set_cell_size(_map, 0.05)
	NavigationServer3D.map_set_cell_height(_map, 0.02)
	NavigationServer3D.map_set_edge_connection_margin(_map, 0.01)
	var baked_faces := PackedVector3Array()
	var physical_records: Array=[]
	for record in records:
		var area: Node3D = record.area
		var faces: PackedVector3Array = record.faces
		if faces.is_empty(): continue
		var floor_faces := faces
		if float(area.body_radius) <= EPS:
			# This is already an actor-centre domain (dynamic building). Expand
			# the physical support only. Its exact nav mesh is deliberately not
			# eroded a second time or rasterised across the intervening ocean.
			floor_faces = _expanded_floor(area, faces)
			_add_region(_exact_rect_mesh(area, faces))
		else:
			baked_faces.append_array(faces)
		_add_body(floor_faces, "GroundFloor")
		physical_records.append({"area":area,"faces":floor_faces})
	if not baked_faces.is_empty():
		var mesh := NavigationMesh.new()
		mesh.cell_size = 0.05
		mesh.cell_height = 0.02
		mesh.agent_radius = ACTOR_RADIUS
		mesh.agent_height = ACTOR_HEIGHT
		mesh.agent_max_climb = 0.30
		mesh.agent_max_slope = 46.0
		mesh.region_min_size = 0.0
		mesh.region_merge_size = 0.0
		mesh.filter_ledge_spans = true
		mesh.filter_walkable_low_height_spans = true
		var source := NavigationMeshSourceGeometryData3D.new()
		# SourceGeometry uses Godot's clockwise front-face order; its importer
		# reverses indices for Recast. Physics faces above use cross-product UP.
		var navigation_faces := baked_faces.duplicate()
		for i in range(0,navigation_faces.size()-2,3):
			var swap := navigation_faces[i+1]
			navigation_faces[i+1] = navigation_faces[i+2]
			navigation_faces[i+2] = swap
		source.add_faces(navigation_faces, Transform3D.IDENTITY)
		NavigationServer3D.bake_from_source_geometry_data(mesh, source)
		_add_region(mesh)
	# Derive the boundary from the same compensated support union as the floor.
	# Offsetting individual centre-domain walls leaves their old endpoints
	# sticking into narrow paths; union first so real capsules can pass seams.
	_add_body(_boundary_faces(physical_records), "GroundBoundary")
	# All changes above run on the scene main thread. Keep immediate command
	# queries valid, including restore/build callbacks before the next frame.
	NavigationServer3D.map_force_update(_map)

func _add_region(mesh: NavigationMesh) -> void:
	if mesh.get_polygon_count() == 0: return
	navigation_polygons += mesh.get_polygon_count()
	var region := NavigationServer3D.region_create()
	NavigationServer3D.region_set_use_async_iterations(region, false)
	NavigationServer3D.region_set_enabled(region, true)
	NavigationServer3D.region_set_navigation_layers(region, 1)
	NavigationServer3D.region_set_navigation_mesh(region, mesh)
	NavigationServer3D.region_set_map(region, _map)
	_regions.append(region)
	_meshes.append(mesh)

func _add_body(faces: PackedVector3Array, label: String) -> void:
	if faces.is_empty(): return
	var body := ActorCollision.new()
	body.name = label
	body.collision_layer = GROUND_LAYER
	body.collision_mask = ACTOR_LAYER
	body.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	# Faces are world space; the derived body must not inherit a zone transform.
	body.top_level = true
	body.global_transform = Transform3D.IDENTITY
	_bodies.append(body)

func area_at(point: Vector3, tolerance: float = 0.5) -> Node3D:
	if not point.is_finite() or tolerance < 0.0: return null
	var selected: Node3D
	var distance := tolerance + EPS
	for area in _areas:
		if not is_instance_valid(area): continue
		var at: Vector3 = area.surface_point(point)
		if not at.is_finite(): continue
		var difference := absf(at.y - point.y)
		if difference < distance:
			selected = area
			distance = difference
	return selected

func surface_point(point: Vector3, tolerance: float = 0.5) -> Vector3:
	var area := area_at(point, tolerance)
	return Vector3.INF if area == null else area.surface_point(point)

func body_point(point: Vector3) -> Vector3:
	var area := area_at(point,0.5)
	if area == null: return point
	var normal: Vector3 = area.surface_normal(point)
	# A capsule resting on a slope touches off-centre. Its bottom origin is
	# slightly above the point directly underneath; do not chase into the ramp.
	return point + Vector3.UP * ACTOR_RADIUS * (1.0/maxf(normal.y,0.65)-1.0)

func route(start: Vector3, goal: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if not _map.is_valid() or _regions.is_empty(): return result
	if NavigationServer3D.map_get_iteration_id(_map) == 0:
		NavigationServer3D.map_force_update(_map)
		if NavigationServer3D.map_get_iteration_id(_map) == 0: return result
	var from := surface_point(start, 0.5)
	var to := surface_point(goal, 0.5)
	if not from.is_finite() or not to.is_finite(): return result
	if from.distance_squared_to(to) < 0.00000001:
		return [from, to]
	var mapped_from := NavigationServer3D.map_get_closest_point(_map, from)
	var mapped_to := NavigationServer3D.map_get_closest_point(_map, to)
	if from.distance_to(mapped_from) > ENDPOINT_TOLERANCE or to.distance_to(mapped_to) > ENDPOINT_TOLERANCE:
		return result
	var path := NavigationServer3D.map_get_path(_map, mapped_from, mapped_to, true, 1)
	if path.is_empty() or path[path.size()-1].distance_to(mapped_to) > 0.05: return result
	# Start and goal belong to the declared surface, never an unrelated floor
	# selected solely because NavigationServer can find a nearby polygon.
	result.append(from)
	for point: Vector3 in path:
		var projected := surface_point(point, 0.35)
		if not projected.is_finite(): return []
		if result.back().distance_to(projected) > 0.001: result.append(projected)
	if result.back().distance_to(to) > 0.001: result.append(to)
	else: result[result.size()-1] = to
	return result

static func _upward_faces(source: PackedVector3Array) -> PackedVector3Array:
	var faces := source.duplicate()
	for i in range(0, faces.size()-2, 3):
		if (faces[i+1]-faces[i]).cross(faces[i+2]-faces[i]).y < 0.0:
			var swap := faces[i+1]
			faces[i+1] = faces[i+2]
			faces[i+2] = swap
	return faces

static func _world_rects(area: Node3D, grow: float = 0.0) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for value: Rect2 in area.rects:
		var rect := value.grow(grow)
		var a: Vector3 = area.to_global(Vector3(rect.position.x, 0.0, rect.position.y))
		var b: Vector3 = area.to_global(Vector3(rect.end.x, 0.0, rect.end.y))
		result.append(Rect2(Vector2(minf(a.x,b.x), minf(a.z,b.z)), Vector2(absf(b.x-a.x),absf(b.z-a.z))))
	return result

static func _rect_faces(rects: Array[Rect2], y: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	for rect in rects:
		var a := Vector3(rect.position.x,y,rect.position.y)
		var b := Vector3(rect.position.x,y,rect.end.y)
		var c := Vector3(rect.end.x,y,rect.end.y)
		var d := Vector3(rect.end.x,y,rect.position.y)
		result.append_array(PackedVector3Array([a,b,c,a,c,d]))
	return result

static func _expanded_floor(area: Node3D, faces: PackedVector3Array) -> PackedVector3Array:
	if area.rects.is_empty(): return faces
	return _rect_faces(_world_rects(area, ACTOR_RADIUS), faces[0].y)

static func _exact_rect_mesh(area: Node3D, faces: PackedVector3Array) -> NavigationMesh:
	var mesh := NavigationMesh.new()
	mesh.cell_size = 0.05
	mesh.cell_height = 0.02
	if area.rects.is_empty():
		mesh.vertices = faces
		for i in range(0,faces.size()-2,3): mesh.add_polygon(PackedInt32Array([i,i+1,i+2]))
		return mesh
	# Sparse coordinate partition, not an ocean-sized raster. All rectangles
	# share cut vertices, so partial tile seams connect in the engine mesh.
	var rects := _world_rects(area)
	var xset := {}
	var zset := {}
	for rect in rects:
		xset[snappedf(rect.position.x,EPS)] = true
		xset[snappedf(rect.end.x,EPS)] = true
		zset[snappedf(rect.position.y,EPS)] = true
		zset[snappedf(rect.end.y,EPS)] = true
	var xs: Array = xset.keys(); xs.sort()
	var zs: Array = zset.keys(); zs.sort()
	var cells := {}
	for rect in rects:
		var x0 := xs.bsearch(snappedf(rect.position.x,EPS))
		var x1 := xs.bsearch(snappedf(rect.end.x,EPS))
		var z0 := zs.bsearch(snappedf(rect.position.y,EPS))
		var z1 := zs.bsearch(snappedf(rect.end.y,EPS))
		for x in range(x0,x1):
			for z in range(z0,z1): cells[Vector2i(x,z)] = true
	var vertices := PackedVector3Array()
	var indices := {}
	var polygons: Array[PackedInt32Array] = []
	for cell: Vector2i in cells:
		var polygon := PackedInt32Array()
		for offset: Vector2i in [Vector2i.ZERO,Vector2i(0,1),Vector2i(1,1),Vector2i(1,0)]:
			var key := cell+offset
			if not indices.has(key):
				indices[key] = vertices.size()
				vertices.append(Vector3(xs[key.x],faces[0].y,zs[key.y]))
			polygon.append(indices[key])
		polygons.append(polygon)
	mesh.vertices = vertices
	for polygon in polygons: mesh.add_polygon(polygon)
	return mesh

func _boundary_faces(records: Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	var edges := {}
	var points := {}
	for record in records:
		var faces: PackedVector3Array = record.faces
		for i in range(0,faces.size()-2,3):
			for k in 3:
				var a: Vector3 = faces[i+k].snapped(Vector3.ONE*EPS)
				var b: Vector3 = faces[i+(k+1)%3].snapped(Vector3.ONE*EPS)
				points[a] = true; points[b] = true
				var key := str(a)+"/"+str(b) if a < b else str(b)+"/"+str(a)
				if not edges.has(key): edges[key] = {"a":a,"b":b,"count":0,"area":record.area}
				edges[key].count += 1
	for edge in edges.values():
		if edge.count != 1: continue
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var direction := b-a
		if direction.length_squared() < EPS: continue
		var cuts: Array[float] = [0.0,1.0]
		for p: Vector3 in points:
			var t := (p-a).dot(direction)/direction.length_squared()
			var axis_edge := absf(direction.y)<EPS and (absf(direction.x)<EPS or absf(direction.z)<EPS)
			if t>EPS and t<1.0-EPS and (axis_edge or a.lerp(b,t).distance_to(p)<EPS*2.0): cuts.append(t)
		cuts.sort()
		var normal := Vector3(-direction.z,0.0,direction.x).normalized()
		for i in range(1,cuts.size()):
			if cuts[i]-cuts[i-1]<EPS: continue
			var start := a.lerp(b,cuts[i-1])
			var end := a.lerp(b,cuts[i])
			var middle := (start+end)*0.5
			var left := _supports(middle+normal*0.002,records)
			var right := _supports(middle-normal*0.002,records)
			if left == right: continue
			var bottom := Vector3.DOWN*0.15
			var top := Vector3.UP*1.4
			result.append_array(PackedVector3Array([start+bottom,end+bottom,end+top,start+bottom,end+top,start+top]))
	return result

func _supports(point: Vector3, records: Array) -> bool:
	for record in records:
		var faces: PackedVector3Array=record.faces
		for i in range(0,faces.size()-2,3):
			var a:=faces[i];var b:=faces[i+1];var c:=faces[i+2]
			var normal: Vector3=(b-a).cross(c-a)
			if absf(normal.y)<EPS: continue
			var y:=a.y-(normal.x*(point.x-a.x)+normal.z*(point.z-a.z))/normal.y
			if absf(y-point.y)>=0.02: continue
			var outline:=PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)])
			if GroundPath.contains([outline],Vector2(point.x,point.z)): return true
	return false
