extends SceneTree
const Profile = preload("res://src/avatar/avatar_profile.gd")
const Catalog = preload("res://src/avatar/avatar_catalog.gd")
const Save = preload("res://src/save/save_game.gd")
var checks:=0
var failures:=0
var main: Node

func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("[avatar] ","PASS " if ok else "FAIL ",label)
func wait_phase(target: String) -> void:
	var deadline:=Time.get_ticks_msec()+6000
	while main.avatar_session.phase!=target and Time.get_ticks_msec()<deadline: await process_frame
	check(main.avatar_session.phase==target,"session reaches "+target)

func run() -> void:
	main=load("res://scenes/main.tscn").instantiate(); root.add_child(main)
	main._autosave_on=false
	var profile=main.avatar_profile
	check(not profile.query().completed,"new profile starts uncompleted")
	var detached: Dictionary=profile.query(); detached.appearance.skin="deep"
	check(profile.query().appearance.skin=="peach","queries cannot mutate committed state")
	for bad in ["", "   ","十三个汉字十三个汉字十三个汉字","a\nb","[mark]","name/unsafe"]:
		check(Profile.name_error(bad)!="","reject invalid name "+bad.replace("\n","\\n"))
	for good in ["小海","Sea 12","旅人·风","十二个字十二个字十二个字"]: check(Profile.name_error(good)=="","accept name "+good)
	var baseline: Dictionary=profile.query()
	for field in baseline:
		if field=="morphs": continue # Optional extension on intact original v1 profiles.
		var broken:=baseline.duplicate(true); broken.erase(field)
		check(Profile.validate_snapshot(broken)!="","reject missing field "+field)
	for broken in [[],null,{"version":2}, {"appearance":[]}]: check(Profile.validate_snapshot(broken)!="","reject malformed profile")
	var before_motor: Transform3D=main.player.transform
	var collider: Node=main.player.get_node("BodyCollision") if main.player.has_node("BodyCollision") else null
	var shape: Resource=collider.shape if collider!=null else null
	for slot in Catalog.data().slots:
		for option in slot.options:
			var appearance:=Catalog.defaults(); appearance[slot.id]=option.id
			main.player.apply_appearance(appearance)
			check(main.player.get_meta("avatar_appearance")[slot.id]==option.id,"visual resolves "+slot.id+"/"+option.id)
	check(main.player.transform==before_motor,"cosmetics preserve actor transform")
	if collider!=null: check(collider.shape==shape,"cosmetics preserve collision resource")
	main.player.apply_appearance(baseline.appearance)
	main._place_new_traveler()
	var position: Vector3=main.player.global_position
	main._begin_avatar_edit(); await wait_phase("editing")
	var editor=main.avatar_session.editor
	editor.draft.name="海风小满"; editor.draft.appearance.hair_style="twin"; editor.draft.appearance.skin="honey"; editor.draft.appearance.glasses="round"
	editor.draft.design_refs={"top":"design:future/sea-001"}; editor.draft.extensions={"diy":{"revision":7,"tags":["sea"]}}
	main.player.apply_appearance(editor.draft.appearance)
	check(profile.query().name=="旅人","preview leaves profile uncommitted")
	main.avatar_session.cancel(); await wait_phase("idle")
	check(profile.query()==baseline,"cancel preserves full committed data")
	check(main.player.get_meta("avatar_appearance")==baseline.appearance,"cancel restores visible appearance")
	check(main.player.global_position.is_equal_approx(position) and not main._title_active,"cancel restores world and releases input")
	main._begin_avatar_edit(); await wait_phase("editing")
	editor=main.avatar_session.editor
	editor.draft.name="海风小满"; editor.draft.appearance.hair_style="twin"; editor.draft.appearance.skin="honey"; editor.draft.appearance.glasses="round"
	editor.draft.morphs.merge({"body_build":0.8,"head_size":0.7,"eye_spacing":0.3,"hair_length":1.0,"hair_volume":0.6,"hair_sweep":0.2},true)
	editor.draft.appearance.fringe="side"; editor.draft.appearance.beard="moustache"; editor.draft.appearance.hair_accessory="ribbon"
	editor.draft.design_refs={"top":"design:future/sea-001"}; editor.draft.extensions={"diy":{"revision":7,"tags":["sea"]}}
	var expected: Dictionary=editor.draft.duplicate(true); expected.completed=true
	var real_save: Callable=main.avatar_session.save
	main.avatar_session.save=func(): return {"ok":false,"reason":"模拟磁盘不可写"}
	editor.step=2; editor.render(); editor.advance()
	check(main.avatar_session.phase=="editing" and not editor.saving,"failed write keeps retryable editor")
	check(profile.query()==baseline,"failed write rolls committed profile back")
	check(editor.draft.name==expected.name and editor.status.text.contains("模拟磁盘不可写"),"failed write retains draft and visible reason")
	main.avatar_session.save=real_save
	editor.advance(); await wait_phase("idle")
	check(profile.query()==expected,"retry commits exact name, all options and DIY references")
	var disk:=Save.read(Save.SLOT_PATH)
	check(disk.get("ok",false) and disk.snapshot.profile==JSON.parse_string(JSON.stringify(expected)),"independent file read proves persistent profile")
	check(main.player.global_position.is_equal_approx(position),"editing and saving keep original world position")
	var malformed: Dictionary=disk.snapshot.duplicate(true); malformed.profile.appearance.erase("eyes")
	var old_state: Dictionary=main.save_registry.capture()
	check(not Save.restore(main,malformed).ok,"bad profile refused before world restore")
	check(main.save_registry.capture()==old_state,"bad restore leaves all modules unchanged")
	var future: Dictionary=expected.duplicate(true); future.appearance.hair_style="future:sea-curls"; future.appearance.extra_slot="future:thing"
	check(profile.commit(future).ok,"unknown future cosmetic IDs accepted")
	check(profile.query().appearance.hair_style=="future:sea-curls" and Catalog.effective(profile.query().appearance).hair_style=="bob","unknown ID retained with default rendering fallback")
	profile.from_dict(expected)
	var legacy: Dictionary=disk.snapshot.duplicate(true); legacy.erase("profile")
	var migrated:=Save.decode(JSON.stringify(legacy))
	check(migrated.ok and migrated.snapshot.profile.completed,"legacy v4 explicitly receives completed profile")
	check(Save.restore(main,legacy).ok and profile.query().completed,"direct legacy restore also migrates")
	profile.from_dict(expected)
	check(main.save_game("",true).ok,"seed saved for separate process restart")
	print("[avatar] %d checks, %d failures" % [checks,failures]); quit(0 if failures==0 else 1)
