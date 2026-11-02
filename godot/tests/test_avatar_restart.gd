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
	check(p.design_refs.get("top")=="design:future/sea-001" and p.extensions.diy.revision==7,"cold startup preserves future DIY references")
	check(main.player.get_meta("avatar_appearance")==p.appearance,"actual actor renders restored profile")
	main._begin_title(); main._enter_game()
	await create_timer(1.3).timeout
	check(not main._title_active and not main.avatar_session.active(),"completed profile bypasses new character creation")
	print("[avatar-restart] %d checks, %d failures" % [checks,failures]); quit(0 if failures==0 else 1)
