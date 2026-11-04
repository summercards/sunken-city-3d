extends RefCounted
## Temporary portrait framing, independent of the orbit camera implementation.
## Frames the traveler in the left half of the viewport while revealing the
## solar cabin and sunny harbor deck in the background.
var _saved: Dictionary = {}

func begin(camera: Camera3D, _player: Node3D) -> void:
	_saved={"transform":camera.global_transform,"fov":camera.fov,"mode":camera.process_mode,"near":camera.near}
	camera.process_mode=Node.PROCESS_MODE_DISABLED
	camera.near=0.05

func portrait(camera: Camera3D, player: Node3D, progress: float, origin: Transform3D, fov: float, focus: String="body") -> void:
	# Traveler's visual front is +Z in local space; when facing the solar cabin (-Z),
	# global_basis.z points toward -Z. To show the solar cabin in the background behind
	# the traveler (and avoid looking back at the boat at +Z), the camera stands on the
	# seaward/harbor side (-forward, +Z) and looks toward the cabin (-Z), while the
	# traveler turns their preview pose toward the camera.
	var cabin_dir: Vector3 = player.global_basis.z
	cabin_dir.y = 0.0
	cabin_dir = cabin_dir.normalized() if cabin_dir.length_squared() > 0.001 else Vector3.FORWARD
	var right: Vector3 = cabin_dir.cross(Vector3.UP).normalized()
	var view_from: Vector3
	if focus == "face":
		view_from = (-cabin_dir * 0.94 - right * 0.24 + Vector3.UP * 0.14).normalized()
	elif focus == "card":
		view_from = (-cabin_dir * 0.88 - right * 0.36 + Vector3.UP * 0.22).normalized()
	else:
		view_from = (-cabin_dir * 0.92 - right * 0.28 + Vector3.UP * 0.18).normalized()
	var center: Vector3 = player.global_position + Vector3.UP * 0.72
	if focus == "face":
		center = player.head_pivot.global_position + Vector3.UP * 0.02
	elif focus == "card":
		center = player.global_position + Vector3.UP * 0.82 + cabin_dir * 0.35
	var portrait_scale: float = player.avatar_portrait_scale() if player.has_method("avatar_portrait_scale") else 1.0
	var dist := 3.65
	if focus == "face": dist = 1.88 * portrait_scale
	elif focus == "card": dist = 4.35
	var destination := Transform3D(Basis.looking_at(-view_from, Vector3.UP), center + view_from * dist)
	# Shift camera right in its own view plane so the character stands in the left third,
	# leaving the right half clear for the journal sheet and revealing the cabin behind.
	var pan_right := 0.68
	if focus == "face": pan_right = 0.34 * portrait_scale
	elif focus == "card": pan_right = 0.76
	destination.origin += destination.basis.x * pan_right
	camera.global_transform = origin.interpolate_with(destination, progress)
	var target_fov := 29.0 if focus == "face" else (32.5 if focus == "card" else 31.0)
	camera.fov = lerpf(fov, target_fov, progress)

func blend_back(camera: Camera3D, progress: float, origin: Transform3D, fov: float) -> void:
	camera.global_transform = origin.interpolate_with(_saved.transform, progress)
	camera.fov = lerpf(fov, float(_saved.fov), progress)

func finish(camera: Camera3D) -> void:
	if _saved.is_empty(): return
	camera.global_transform = _saved.transform; camera.fov = _saved.fov
	camera.near = _saved.near; camera.process_mode = _saved.mode
	_saved.clear()
