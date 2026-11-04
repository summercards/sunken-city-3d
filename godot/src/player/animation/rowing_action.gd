extends RefCounted
## The seat and real oar grips own the pose targets, including at rest.
const Dimensions = preload("res://src/avatar/avatar_dimensions.gd")
func sample(a, _delta: float) -> void:
	var rowing := Vector2(a._t*3.4,1.0)
	if a.rowing_query.is_valid(): rowing=a.rowing_query.call()
	var seat := Transform3D(a.global_basis,a.global_position)
	var contacts := {}
	if a.rowing_pose_query.is_valid():
		contacts=a.rowing_pose_query.call()
		seat=contacts.seat
	var local_seat: Transform3D=a.global_transform.affine_inverse()*seat
	var lean := (0.035+sin(rowing.x)*0.055)*rowing.y
	var body_basis := local_seat.basis*Basis(Vector3.RIGHT,lean)
	var hip_height: float=a._avatar_factors.hip_y
	a.body_pivot.basis=body_basis
	# Rotate about the pelvis, so boat roll does not lift the seat.
	a.body_pivot.position=local_seat.origin+local_seat.basis*Vector3(0,0.05,0)-body_basis*Vector3(0,hip_height,0)
	for pair in [[a.left_leg,a.left_knee],[a.right_leg,a.right_knee]]:
		pair[0].rotation=Vector3(-1.50-lean,0,0)
		pair[1].rotation=Vector3(1.52,0,0)
	for side in [-1,1]:
		var arm: Node3D=a.left_arm if side<0 else a.right_arm
		var elbow: Node3D=a.left_elbow if side<0 else a.right_elbow
		var target: Vector3=contacts["left_grip" if side<0 else "right_grip"] if not contacts.is_empty() else a.body_pivot.to_global(Vector3(side*0.27,hip_height+0.24,0.18))
		pose_arm(arm,elbow,a.body_pivot.to_local(target),side,float(a._avatar_factors.arm_length))

func pose_arm(arm: Node3D, elbow: Node3D, target: Vector3, side: int, length_scale: float) -> void:
	var upper := Dimensions.UPPER_ARM*length_scale
	var lower := Dimensions.LOWER_ARM*length_scale
	var offset := target-arm.position
	var distance := maxf(offset.length(),0.0001)
	var direction := offset/distance
	var axis := Vector3(side*0.8,-1.0,-0.25)
	var bend := (axis-direction*axis.dot(direction)).normalized()
	var along := clampf((distance*distance+upper*upper-lower*lower)/(2.0*distance),0.0,upper)
	var joint := arm.position+direction*along+bend*sqrt(maxf(0.0,upper*upper-along*along))
	elbow.position=Vector3(0,-upper,0)
	elbow.get_node("Hand").position=Vector3(0,-lower,0)
	arm.quaternion=Quaternion(Vector3.DOWN,(joint-arm.position).normalized())
	elbow.quaternion=Quaternion(Vector3.DOWN,(arm.basis.inverse()*(target-joint)).normalized())
