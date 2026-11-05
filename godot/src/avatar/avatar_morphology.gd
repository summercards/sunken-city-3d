extends RefCounted
## Bounded visual dimensions. No world state, motor scaling or collision writes.
const Catalog = preload("res://src/avatar/avatar_catalog.gd")
const Dimensions = preload("res://src/avatar/avatar_dimensions.gd")
const REST_ELBOW_OUT := 0.045
const REST_SHOULDER_OUT := 0.50
const SHOULDER_DROP := 0.065*1.5

static func factors(raw: Dictionary, appearance: Dictionary) -> Dictionary:
	var m := Catalog.effective_morphs(raw)
	var build: float=m.body_build
	var width := remap(build,0.0,0.5,0.90,1.08) if build<=0.5 else remap(build,0.5,1.0,1.08,1.34)
	var depth := remap(build,0.0,0.5,0.95,1.07) if build<=0.5 else remap(build,0.5,1.0,1.07,1.32)
	var limb := remap(build,0.0,0.5,0.98,1.18) if build<=0.5 else remap(build,0.5,1.0,1.18,1.32)
	var arm: float=limb*lerpf(0.85,1.43,m.arm_girth)
	var leg: float=lerpf(0.74,0.98,m.leg_length)
	var hip_y:=0.035*Dimensions.SCALE+(Dimensions.THIGH+Dimensions.SHIN)*leg
	var hem:=hip_y+0.027*Dimensions.SCALE
	var top:=(Dimensions.SHIRT_CENTER+Dimensions.SHIRT_HALF.y)*Dimensions.SCALE
	var kind := str(appearance.get("body_type","balanced"))
	return {"width":width,"depth":depth,"limb":limb,"arm":arm,"leg_length":leg,"hip_y":hip_y,
		"arm_rest":REST_SHOULDER_OUT+maxf(arm-1.50,0.0)*0.45,
		"arm_length":1.0+(Dimensions.HIP_Y-hip_y)*0.70/(Dimensions.UPPER_ARM+Dimensions.LOWER_ARM),
		"head":lerpf(0.88,1.12,m.head_size),"head_width":lerpf(0.82,1.08,m.head_width),"kind":kind,
		"shirt_center":(top+hem)*0.5,"shirt_half_y":(top-hem)*0.5,
		"shoulder":(0.090*width+0.018*arm-0.003)*Dimensions.SCALE*(1.025 if kind=="athletic" else (0.975 if kind=="pear" else 1.0)),
		"hip":Dimensions.HIP_X*width*(1.045 if kind=="pear" else 1.0)}

static func shoulder(side: int, f: Dictionary) -> Vector3:
	return Vector3(side*float(f.shoulder),Dimensions.SHOULDER_Y-SHOULDER_DROP,0)

static func rest_hand(side: int, f: Dictionary) -> Vector3:
	var length: float=f.arm_length
	var angle: float=f.arm_rest
	var upper:=Vector3(side*Dimensions.UPPER_ARM*sin(angle),-Dimensions.UPPER_ARM*cos(angle),0)*length
	var lower:=Vector3(side*Dimensions.LOWER_ARM*sin(angle+REST_ELBOW_OUT),-Dimensions.LOWER_ARM*cos(angle+REST_ELBOW_OUT),0)*length+Vector3(0,0,.006*Dimensions.SCALE)
	return shoulder(side,f)+upper+lower

static func shirt_radius_at(y: float, shape: Dictionary) -> float:
	var unit_y: float=(y-float(shape.shirt_center))/float(shape.shirt_half_y)
	var rings:=shirt_rings()
	for i in rings.size()-1:
		if unit_y<=rings[i+1].x:
			return lerpf(shirt_radius(rings[i].x,rings[i].y,shape),shirt_radius(rings[i+1].x,rings[i+1].y,shape),inverse_lerp(rings[i].x,rings[i+1].x,unit_y))
	return 0.01

static func shirt_rings() -> Array[Vector2]:
	# A rounded shoulder joins the sleeve cap instead of exposing a triangular
	# gap between the old sharply tapered collar and the arm.
	return [Vector2(-1.01,0.01),Vector2(-1,0.94),Vector2(-0.95,1.08),Vector2(-0.82,1.10),Vector2(-0.20,0.87),Vector2(0.30,0.67),Vector2(0.65,0.64),Vector2(0.85,0.55),Vector2(1,0.34),Vector2(1.01,0.01)]

static func shirt_front(x: float, y: float, shape: Dictionary) -> float:
	var radius:=shirt_radius_at(y,shape)
	return Dimensions.SHIRT_HALF.z*Dimensions.SCALE*radius*sqrt(maxf(0.0,1.0-pow(x/(Dimensions.SHIRT_HALF.x*Dimensions.SCALE*radius),2)))

static func shirt_radius(y: float, original: float, f: Dictionary) -> float:
	# Broaden the shoulder socket with girth, while keeping the default exact.
	var radius := original
	match f.kind:
		"pear": radius*=lerpf(1.05,0.95,smoothstep(-0.75,0.65,y))
		"athletic": radius*=lerpf(0.93,1.045,smoothstep(-0.4,0.6,y))
		"soft": radius*=1.0+0.035*(1.0-absf(clampf(y,-1.0,1.0)))
	return radius

static func apply(actor, f: Dictionary) -> void:
	var s := Dimensions.SCALE
	actor.head_pivot.scale=Vector3.ONE*float(f.head)
	for id in ["AvatarHead","AvatarHat"]:
		if actor.head_pivot.has_node(id):
			var root: Node3D=actor.head_pivot.get_node(id)
			root.scale.x=Dimensions.HEAD_SCALE.x*float(f.head_width)*s
	if actor.mask: actor.mask.scale.x=Dimensions.HEAD_SCALE.x*float(f.head_width)*s
	actor.head_pivot.position.y=Dimensions.HEAD_CENTER+0.22*s*(float(f.head)-1.0)
	actor.left_arm.position=shoulder(-1,f); actor.right_arm.position=shoulder(1,f)
	if actor.animation_state()=="idle":
		actor.left_arm.rotation.z=-float(f.arm_rest)
		actor.right_arm.rotation.z=float(f.arm_rest)
	for elbow in [actor.left_elbow,actor.right_elbow]:
		elbow.position.y=-Dimensions.UPPER_ARM*float(f.arm_length)
		elbow.get_node("Hand").position.y=-Dimensions.LOWER_ARM*float(f.arm_length)
	actor.left_leg.position.x=-float(f.hip); actor.right_leg.position.x=float(f.hip)
	for leg in [actor.left_leg,actor.right_leg]: leg.position.y=float(f.hip_y)
	for knee in [actor.left_knee,actor.right_knee]:
		knee.position.y=-Dimensions.THIGH*float(f.leg_length)
		knee.get_node("Foot").position.y=-Dimensions.SHIN*float(f.leg_length)
	actor.limb_skinning.set_girth(float(f.limb),float(f.arm))
	if actor.gear and actor.gear.get_child_count()>0:
		actor.gear.get_child(0).position.z=-(Dimensions.SHIRT_HALF.z*float(f.depth)*s+0.112*s+0.020*s)
	actor._item_receive.fit_body(actor,f)
	actor.sync_visual_pose()
