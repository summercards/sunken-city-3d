extends Node
## Injected transaction boundary. Owns temporary presentation and disposable UI.
signal finished(saved: bool)
signal editing_started
const CameraRig = preload("res://src/onboarding/arrival_camera.gd")
var profile: RefCounted
var player: Node3D
var camera: Camera3D
var save: Callable
var editor: CanvasLayer
var phase := "idle"
var first_creation := false
var _rig = CameraRig.new()
var _tween: Tween
var _focus_tween: Tween
var _focus_mode := "body"

func active() -> bool: return phase!="idle"

func begin(first: bool, origin := Transform3D.IDENTITY, origin_fov:=31.0) -> bool:
	if active(): return false
	first_creation=first; phase="arriving"
	_rig.begin(camera,player)
	var from: Transform3D=camera.global_transform if not first else origin
	var fov: float=camera.fov if not first else origin_fov
	_tween=create_tween()
	_tween.tween_method(func(t: float): _rig.portrait(camera,player,t,from,fov),0.0,1.0,1.8 if first else 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_open_editor)
	return true

func _open_editor() -> void:
	phase="editing"
	editor=preload("res://src/avatar/avatar_editor.gd").new()
	editor.draft=profile.query(); editor.first_creation=first_creation
	editor.draft_preview_requested.connect(_preview)
	editor.focus_requested.connect(_focus)
	editor.rotate_requested.connect(player.set_preview_yaw)
	editor.expression_requested.connect(player.preview_expression)
	editor.cancel_requested.connect(cancel)
	editor.save_requested.connect(_commit)
	add_child(editor)
	editing_started.emit()

func _preview(draft: Dictionary) -> void:
	player.apply_avatar(draft)
	if _focus_mode=="face": _focus(_focus_mode)

func _focus(mode: String) -> void:
	if phase!="editing": return
	_focus_mode=mode
	if _focus_tween and _focus_tween.is_valid(): _focus_tween.kill()
	var origin:=camera.global_transform; var fov:=camera.fov
	_focus_tween=create_tween()
	_focus_tween.tween_method(func(t: float): _rig.portrait(camera,player,t,origin,fov,mode),0.0,1.0,0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _commit(draft: Dictionary) -> void:
	if phase!="editing": return
	var before: Dictionary=profile.query()
	var result: Dictionary=profile.commit(draft)
	if result.ok: result=save.call()
	if not result.get("ok",false):
		profile.from_dict(before)
		player.apply_avatar(draft)
		editor.save_failed(str(result.get("reason","存储失败")))
		return
	leave(true)

func cancel() -> void:
	if phase!="editing" or first_creation: return
	player.apply_avatar(profile.query())
	leave(false)

func leave(saved: bool) -> void:
	phase="leaving"
	player.preview_expression("auto")
	if _focus_tween and _focus_tween.is_valid(): _focus_tween.kill()
	player.set_preview_yaw(0.0)
	if is_instance_valid(editor): editor.queue_free()
	editor=null
	var origin:=camera.global_transform; var fov:=camera.fov
	_tween=create_tween()
	_tween.tween_method(func(t: float): _rig.blend_back(camera,t,origin,fov),0.0,1.0,1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(func(): _rig.finish(camera); phase="idle"; finished.emit(saved))

func _exit_tree() -> void:
	if _tween and _tween.is_valid(): _tween.kill()
	if _focus_tween and _focus_tween.is_valid(): _focus_tween.kill()
	if is_instance_valid(camera): _rig.finish(camera)
	save=Callable()
