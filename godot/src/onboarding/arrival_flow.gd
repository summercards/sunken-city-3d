extends Node
## Lifecycle coordinator: scene-specific movement and suspension arrive as ports.
signal finished
var session: Node
var place_at_dock: Callable
var release_title_camera: Callable
var phase := "idle"

func begin(camera: Camera3D) -> bool:
	if phase!="idle" or session.active(): return false
	phase="arriving"
	var origin:=camera.global_transform; var fov:=camera.fov
	release_title_camera.call()
	place_at_dock.call()
	session.editing_started.connect(_editing,CONNECT_ONE_SHOT)
	session.finished.connect(_finished,CONNECT_ONE_SHOT)
	session.begin(true,origin,fov)
	return true

func _editing() -> void: phase="editing"
func _finished(_saved: bool) -> void:
	phase="idle"; finished.emit()

func _exit_tree() -> void:
	place_at_dock=Callable(); release_title_camera=Callable()
