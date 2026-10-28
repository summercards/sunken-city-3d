extends RefCounted
## Temporary composition uses the live world and restores the exact gameplay view.
var _saved: Dictionary = {}
var _from := Transform3D.IDENTITY

func begin(camera: Camera3D) -> void:
	_saved = {"transform":camera.global_transform,"fov":camera.fov,"process_mode":camera.process_mode}
	camera.process_mode = Node.PROCESS_MODE_DISABLED
	# House sits in the left third; the right half remains calm open water.
	var direction := Vector3(-0.50,0.53,0.69).normalized()
	var right := Vector3.UP.cross(direction).normalized()
	var up := direction.cross(right).normalized()
	# Translate down within the view plane: the house moves up without changing
	# the established angle, lens, distance or horizontal composition.
	var target := Vector3(0.5,6.8,4.0) + right*12.0 - up*3.4
	camera.position = target + direction*64.0
	camera.look_at(target)
	camera.fov = 31.0
	_from = camera.global_transform

func blend(camera: Camera3D, amount: float) -> void:
	camera.global_transform = _from.interpolate_with(_saved.transform,amount)
	camera.fov = lerpf(31.0,float(_saved.fov),amount)

func finish(camera: Camera3D) -> void:
	camera.global_transform = _saved.transform
	camera.fov = _saved.fov
	camera.process_mode = _saved.process_mode
	_saved.clear()
