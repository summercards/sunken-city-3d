extends SceneTree
const Save=preload("res://src/save/save_game.gd")
var main: Node
var checks:=0
var failures:=0
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("[onboarding] ","PASS " if ok else "FAIL ",label)
func wait_phase(value: String) -> void:
	var deadline:=Time.get_ticks_msec()+6000
	while main.avatar_session.phase!=value and Time.get_ticks_msec()<deadline: await process_frame
	check(main.avatar_session.phase==value,"reaches "+value)
func run() -> void:
	main=load("res://scenes/main.tscn").instantiate(); root.add_child(main)
	main._autosave_on=false
	main._begin_title()
	var clock: Dictionary=main.world_clock.to_dict()
	var inventory: Dictionary=root.get_node("Economy").inventory.to_dict()
	main._enter_game()
	check(main.avatar_session.phase=="arriving","new game transitions to arrival")
	var session_id: int=main.avatar_session.get_instance_id()
	main._enter_game()
	check(main.avatar_session.get_instance_id()==session_id and main.arrival_flow.phase=="arriving","repeat start cannot create another session")
	check(main.actor_controller.mode()==0 and main.player.get_parent()==main,"player stands on actual dock rather than boat")
	check(main.player.global_basis.z.dot(Vector3.FORWARD)>0.95,"player faces solar cabin (-Z) rather than boat")
	check(main.validate_world_state(main.capture_world_state())=="","arrival position is valid walkable ground")
	await wait_phase("editing")
	check(main.cam.global_position.z>main.player.global_position.z,"portrait camera frames solar cabin behind traveler")
	check(main.world_clock.to_dict()==clock and root.get_node("Economy").inventory.to_dict()==inventory,"arrival freezes calendar and economy")
	check(main._title_active and not main.hud.visible and not main.interactor.active,"HUD and world input stay blocked")
	var pos: Vector3=main.player.global_position
	main._on_click_command("bag"); main._on_click_command("craft")
	check(main.player.global_position==pos and not main.building_controller.active,"world commands blocked during creation")
	var editor=main.avatar_session.editor
	editor.back(); check(main.avatar_session.phase=="editing" and editor.step==0,"first creation cannot be silently cancelled")
	editor.advance(); check(editor.step==0,"Enter on untouched blank field cannot accept hidden default name")
	editor.name_input.text=""; editor.name_input.text_changed.emit("")
	check(editor.next_button.disabled,"blank name blocks progression")
	editor.name_input.text="小海"; editor.name_input.text_changed.emit("小海"); editor.advance()
	check(editor.step==1,"valid name advances to appearance")
	editor.buttons["group/hair"].pressed.emit()
	editor.buttons["hair_style/wave"].pressed.emit()
	check(main.player.get_meta("avatar_appearance").hair_style=="wave" and main.avatar_profile.query().appearance.hair_style=="bob","selection previews without committing")
	editor.advance(); check(editor.step==2,"appearance reaches traveler card")
	editor.back(); check(editor.step==1 and editor.draft.name=="小海","back preserves draft")
	editor.advance(); editor.advance(); await wait_phase("idle")
	check(not main._title_active and main.hud.visible and main.cam.process_mode!=Node.PROCESS_MODE_DISABLED,"successful save restores HUD and camera lifecycle")
	check(main.hud.dialogue!=null and main.hud.dialogue.panel.visible and main.hud.dialogue.speaker_label.text.contains("小海"),"initial indie monologue appears after first creation")
	var dialogue=main.hud.dialogue
	check(main.hud.narrative_active() and main.input_blocked(),"arrival monologue blocks world and camera input")
	var bag:=InputEventKey.new(); bag.keycode=KEY_B; bag.physical_keycode=KEY_B; bag.pressed=true
	root.push_input(bag,true); await process_frame
	check(not main.hud.is_panel_open() and main.player.global_position==pos,"real bag key cannot interrupt arrival monologue")
	dialogue.line_label.visible_ratio=0.25
	dialogue._advance()
	check(dialogue._index==0 and dialogue.line_label.visible_ratio==1.0,"first advance reveals current line without skipping it")
	dialogue._advance()
	check(dialogue._index==1 and dialogue.panel.visible,"second initial monologue line advances")
	dialogue._advance(); dialogue._advance()
	check(dialogue._index==2 and dialogue.panel.visible,"third initial monologue line advances")
	dialogue._advance(); dialogue._advance()
	check(not dialogue.panel.visible and not main.hud.narrative_active(),"initial monologue closes cleanly and releases input")
	check(not main.hud._zoom.visible,"view percentage never overlaps narrative footer")
	var world_yaw: float=main.player.rotation.y
	main._begin_avatar_edit(); await wait_phase("editing")
	check(main.avatar_session._focus_mode=="body","repeat edit resets portrait focus")
	var from: float=main.player.body_pivot.rotation.y
	main.avatar_session._rotate_preview(from+0.6,0.3)
	# Headless frames need not have real-time cadence. Sample the actual tween
	# deterministically instead of assuming an 80ms timer ends between frames.
	main.avatar_session._yaw_tween.pause()
	main.avatar_session._yaw_tween.custom_step(0.08)
	var intermediate: float=main.player.body_pivot.rotation.y
	var angular_delta:=absf(wrapf(intermediate-from,-PI,PI))
	check(angular_delta>0.001 and angular_delta<0.59,"preview turn interpolates rather than snapping")
	main.avatar_session.cancel(); await wait_phase("idle")
	check(main.player.rotation.y==world_yaw and main.player.body_pivot.rotation.y==0.0,"cancel preserves gameplay facing and clears portrait yaw")
	var disk:=Save.read(Save.SLOT_PATH)
	check(disk.ok and disk.snapshot.profile.name=="小海" and disk.snapshot.profile.appearance.hair_style=="wave","created name and appearance saved")
	check(disk.snapshot.game.mode==0 and disk.snapshot.game.player.size()==3,"first save includes actual dock standing pose")
	check(main.player.body_pivot.rotation.y==0.0,"preview rotation leaves no residual pose")
	main._on_click_command("reset")
	check(main.avatar_session.phase=="arriving" and not main.avatar_profile.query().completed,"confirmed reset starts new creation")
	await wait_phase("editing")
	var archived:=DirAccess.get_files_at("user://")
	var found:=false
	for file in archived:
		if file.begins_with("save_slot_0_pre_reset-"):
			var old:=Save.read("user://"+file)
			if old.ok and old.snapshot.profile.name=="小海": found=true
	check(found,"reset archive preserves old character together with progress")
	print("[onboarding] %d checks, %d failures" % [checks,failures]); quit(0 if failures==0 else 1)
