extends RefCounted
## Temporary portrait framing, independent of the orbit camera implementation.
var _saved: Dictionary = {}

func begin(camera: Camera3D, player: Node3D) -> void:
	_saved={"transform":camera.global_transform,"fov":camera.fov,"mode":camera.process_mode,"near":camera.near}
	camera.process_mode=Node.PROCESS_MODE_DISABLED
	camera.near=0.05

func portrait(camera: Camera3D, player: Node3D, progress: float, origin: Transform3D, fov: float, focus: String="body") -> void:
	var front:=player.global_basis*Vector3(0.15,0.18,1)
	front.y=0.18; front=front.normalized()
	var center:=player.global_position+Vector3.UP*0.70
	if focus=="face": center=player.head_pivot.global_position+Vector3.UP*0.02
	var portrait_scale: float=player.avatar_portrait_scale() if player.has_method("avatar_portrait_scale") else 1.0
	var destination:=Transform3D(Basis.looking_at(-front,Vector3.UP),center+front*(1.95*portrait_scale if focus=="face" else 3.9))
	# Shift target right in world camera space: subject appears in the left pane.
	destination.origin += destination.basis.x*(0.35*portrait_scale if focus=="face" else 0.72)
	camera.global_transform=origin.interpolate_with(destination,progress)
	camera.fov=lerpf(fov,31.0,progress)

func blend_back(camera: Camera3D, progress: float, origin: Transform3D, fov: float) -> void:
	camera.global_transform=origin.interpolate_with(_saved.transform,progress)
	camera.fov=lerpf(fov,float(_saved.fov),progress)

func finish(camera: Camera3D) -> void:
	if _saved.is_empty(): return
	camera.global_transform=_saved.transform; camera.fov=_saved.fov
	camera.near=_saved.near; camera.process_mode=_saved.mode
	_saved.clear()
