extends RefCounted
## Height and mesh picking for the editor, with no layout writes.
const Catalog=preload("res://src/building/building_catalog.gd")

static func plane_point(screen: Vector2,camera: Camera3D,height: float) -> Vector3:
	var origin:=camera.project_ray_origin(screen)
	var direction:=camera.project_ray_normal(screen)
	if absf(direction.y)<0.00001: return Vector3.INF
	var distance: float=(Catalog.ORIGIN.y+height-origin.y)/direction.y
	return origin+direction*distance if distance>0.0 else Vector3.INF

## A visible platform selects its own plane. A staircase selects its upper
## landing while laying boards, so the player can extend it without finding U.
static func surface_height(screen: Vector2,camera: Camera3D,rows: Array,fallback: float,platform: bool) -> float:
	var origin:=camera.project_ray_origin(screen)
	var direction:=camera.project_ray_normal(screen)
	var distance:=INF
	var result:=fallback
	var base_point:=plane_point(screen,camera,0.0)
	if base_point.is_finite() and Catalog.BASE.has_point(Vector2(base_point.x-Catalog.ORIGIN.x,base_point.z-Catalog.ORIGIN.z)):
		distance=origin.distance_squared_to(base_point);result=0.0
	for row in rows:
		if float(row.left)>0.0: continue
		var height:=Catalog.elevation(row)
		var rect:=Catalog.footprint_rect(row)
		if Catalog.is_platform(str(row.kind)):
			var point:=plane_point(screen,camera,height)
			if point.is_finite() and (rect.grow(1.3) if platform else rect).has_point(Vector2(point.x-Catalog.ORIGIN.x,point.z-Catalog.ORIGIN.z)):
				var near:=origin.distance_squared_to(point)
				if near<distance: distance=near;result=height
		elif platform and str(Catalog.RECIPES[row.kind].get("profile",""))=="stairs":
			var rise:=Catalog.stair_rise(row)
			var box:=AABB(Catalog.ORIGIN+Vector3(rect.position.x,height,rect.position.y),Vector3(rect.size.x,rise,rect.size.y))
			var hit: Variant=box.intersects_ray(origin,direction)
			if hit is Vector3:
				var near:=origin.distance_squared_to(hit)
				if near<distance: distance=near;result=height+rise
			var upper:=plane_point(screen,camera,height+rise)
			if upper.is_finite():
				var edge:=Catalog.stairs_top_edge(row)
				var tip: Vector2=(edge[0]+edge[1])/2
				if Vector2(upper.x-Catalog.ORIGIN.x,upper.z-Catalog.ORIGIN.z).distance_to(tip)<1.8:
					var near:=origin.distance_squared_to(upper)
					if near<distance: distance=near;result=height+rise
	return result

static func mesh_hit(origin: Vector3,direction: Vector3,root_node: Node3D,cache: Dictionary) -> float:
	var best:=INF
	for node in root_node.find_children("*","MeshInstance3D",true,false):
		var mesh_node:=node as MeshInstance3D
		if mesh_node.mesh==null or not mesh_node.is_visible_in_tree(): continue
		var mesh_id:=mesh_node.mesh.get_instance_id()
		if not cache.has(mesh_id): cache[mesh_id]=mesh_node.mesh.get_faces()
		var inverse:=mesh_node.global_transform.affine_inverse()
		var local_origin: Vector3=inverse*origin
		var local_direction: Vector3=inverse.basis*direction
		if not mesh_node.mesh.get_aabb().intersects_ray(local_origin,local_direction) is Vector3: continue
		var faces: PackedVector3Array=cache[mesh_id]
		for i in range(0,faces.size()-2,3):
			var hit: Variant=Geometry3D.ray_intersects_triangle(local_origin,local_direction,faces[i],faces[i+1],faces[i+2])
			if hit is Vector3: best=minf(best,origin.distance_squared_to(mesh_node.global_transform*hit))
	return best
