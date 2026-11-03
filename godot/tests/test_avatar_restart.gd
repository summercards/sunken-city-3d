extends SceneTree
var checks:=0
var failures:=0
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("[avatar-restart] ","PASS " if ok else "FAIL ",label)
func run() -> void:
	var main=load("res://scenes/main.tscn").instantiate(); root.add_child(main)
	main._autosave_on=false
	var p: Dictionary=main.avatar_profile.query()
	check(p.completed and p.name=="海风小满","cold startup restores completed Chinese name")
	check(p.appearance.hair_style=="twin" and p.appearance.skin=="honey" and p.appearance.glasses=="round","cold startup restores selected appearance")
	var expected: Dictionary=preload("res://src/avatar/avatar_catalog.gd").morph_defaults()
	expected.merge({"body_build":0.8,"head_size":0.7,"eye_spacing":0.3,"hair_length":1.0,"hair_volume":0.6,"hair_sweep":0.2},true)
	check(p.morphs==expected,"cold startup restores every non-default morph and new defaults")
	check(p.appearance.fringe=="side" and p.appearance.beard=="moustache" and p.appearance.hair_accessory=="ribbon","cold startup restores new modular hairstyle and beard slots")
	check(main.player.get_meta("avatar_morphs")==p.morphs,"actual actor consumes restored morphs")
	check(p.design_refs.get("top")=="design:future/sea-001" and p.extensions.diy.revision==7,"cold startup preserves future DIY references")
	check(main.player.get_meta("avatar_appearance")==p.appearance,"actual actor renders restored profile")
	main._begin_title(); main._enter_game()
	await create_timer(1.3).timeout
	check(not main._title_active and not main.avatar_session.active(),"completed profile bypasses new character creation")
	print("[avatar-restart] %d checks, %d failures" % [checks,failures]); quit(0 if failures==0 else 1)
