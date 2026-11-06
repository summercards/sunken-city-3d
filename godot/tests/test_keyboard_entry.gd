extends SceneTree
## 只允许统一 runner 的隔离用户目录；所有验收操作使用真实按下/松开事件。
var checks := 0
var failures := 0
var main
var save_calls := 0
var reject_save := true

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[keyboard-entry] ","PASS " if ok else "FAIL ",label)

func send(code: int, pressed: bool, shift := false, echo := false, unicode_value := 0) -> void:
	var event := InputEventKey.new()
	event.keycode=code; event.physical_keycode=code; event.pressed=pressed
	event.shift_pressed=shift; event.echo=echo; event.unicode=unicode_value
	root.push_input(event,true)

func key(code: int, shift := false, unicode_value := 0) -> void:
	send(code,true,shift,false,unicode_value)
	await process_frame
	send(code,false,shift,false,unicode_value)
	await process_frame

func seek(editor, id: String) -> void:
	for attempt in editor.buttons.size()+1:
		if root.gui_get_focus_owner()==editor.buttons.get(id): return
		await key(KEY_TAB)
	check(false,"Tab 可达 "+id)

func wait_phase(target: String) -> void:
	var deadline := Time.get_ticks_msec()+8000
	while main.avatar_session.phase!=target and Time.get_ticks_msec()<deadline:
		await process_frame
	await process_frame
	check(main.avatar_session.phase==target,"流程到达 "+target)

func run() -> void:
	if not str(ProjectSettings.get_setting("application/config/custom_user_dir_name","")).begins_with("sea-verification/"):
		printerr("[keyboard-entry] 必须通过隔离 runner 运行")
		quit(2); return
	root.content_scale_size=Vector2i(1600,1000)
	main=load("res://scenes/main.tscn").instantiate(); root.add_child(main)
	main._autosave_on=false
	check(not main.avatar_profile.query().completed,"隔离新档未完成创建")
	main.avatar_session.save=func():
		save_calls+=1
		return {"ok":false,"reason":"键盘验收模拟失败"} if reject_save else {"ok":true}
	if main.start_screen==null: main._begin_title()
	var clock: Dictionary=main.world_clock.to_dict()
	var title=main.start_screen
	check(title.start_button.has_focus(),"开始按钮取得默认焦点")
	await create_timer(0.25).timeout
	check(title.start_button.modulate.a<0.01,"focus 反馈不提前打断延迟淡入")
	title._pulse.pause(); title._pulse.custom_step(0.25)
	check(is_equal_approx(title.start_hint.position.x,52.0) and is_equal_approx(title.start_button.modulate.r,title.SoftGold.r),"focus 与 hover 使用相同暖金/右移反馈")
	send(KEY_KP_ENTER,true,false,true)
	await process_frame
	check(not title._entering,"开始按钮忽略重复回车")
	send(KEY_KP_ENTER,false)
	await key(KEY_KP_ENTER)
	await wait_phase("editing")
	var editor=main.avatar_session.editor
	check(editor.name_input.has_focus() and editor.next_button.disabled,"首创姓名默认焦点与空名保护")
	await key(KEY_ESCAPE)
	check(editor.step==0 and main._title_active,"首创 Esc 不跳过建档")
	await key(KEY_S,false,115); await key(KEY_E,false,101); await key(KEY_A,false,97)
	check(editor.name_input.text=="sea" and not editor.next_button.disabled,"真键事件输入姓名")
	await key(KEY_KP_ENTER)
	check(editor.step==1 and editor.buttons["group/body"].has_focus(),"姓名提交进入外观分类焦点")
	await key(KEY_TAB); await key(KEY_TAB,true)
	check(editor.buttons["group/body"].has_focus(),"Tab 与 Shift+Tab 对称切换焦点")
	await key(KEY_RIGHT)
	check(editor.buttons["group/skin"].has_focus(),"方向键可切换相邻分类")
	await key(KEY_LEFT)
	await seek(editor,"morph/body_build")
	var before: float=editor.draft.morphs.body_build
	await key(KEY_RIGHT)
	check(is_equal_approx(editor.draft.morphs.body_build,before+0.01),"滑杆方向键微调且不跳焦点")
	await seek(editor,"group/hair"); await key(KEY_ENTER)
	check(editor.group_id=="hair" and editor.buttons["group/hair"].has_focus(),"切换分类重建后保留稳定 ID 焦点")
	await seek(editor,"hair_accessory/ribbon")
	await process_frame
	var option: Control=editor.buttons["hair_accessory/ribbon"]
	check(editor.options_scroll.scroll_vertical>0 and editor.options_scroll.get_global_rect().encloses(option.get_global_rect()),"Tab 到底部选项自动滚动可见")
	await key(KEY_SPACE)
	check(editor.draft.appearance.hair_accessory=="ribbon" and option.has_focus(),"选项确认保留焦点与草稿")
	await seek(editor,"next"); await key(KEY_ENTER)
	check(editor.step==2,"键盘进入旅人证")
	await key(KEY_ESCAPE)
	check(editor.step==1 and editor.buttons.next.has_focus(),"返回外观恢复原稳定 ID 焦点")
	await key(KEY_KP_ENTER)
	await key(KEY_KP_ENTER)
	check(save_calls==1 and not editor.saving and editor.next_button.has_focus(),"保存失败保留草稿并恢复重试焦点")
	check(not main.avatar_profile.query().completed,"保存失败不提交档案")
	check(main.world_clock.to_dict()==clock,"建档全程世界时间冻结")
	reject_save=false
	await key(KEY_KP_ENTER)
	send(KEY_KP_ENTER,true,false,true); await process_frame; send(KEY_KP_ENTER,false)
	await wait_phase("idle")
	check(save_calls==2 and main.avatar_profile.query().name=="sea" and main.avatar_profile.query().appearance.hair_accessory=="ribbon","重试仅一次提交姓名与外观")
	check(main.hud.visible and not main._title_active and main.hud.narrative_active(),"新档创建后恢复 HUD 并进入开场台词")
	var dialogue=main.hud.dialogue
	dialogue.line_label.visible_ratio=0.1
	await key(KEY_KP_ENTER)
	check(dialogue._index==0 and dialogue.line_label.visible_ratio==1.0,"台词小键盘回车首击只补全")
	await key(KEY_SPACE)
	check(dialogue._index==1,"台词空格次击推进")
	for attempt in 6:
		if not dialogue.is_blocking(): break
		await key(KEY_ENTER)
	check(not dialogue.is_blocking(),"三句开场台词可全程键盘结束")
	var committed: Dictionary=main.avatar_profile.query()
	await key(KEY_ESCAPE)
	await seek_menu("appearance")
	await key(KEY_ENTER)
	await wait_phase("editing")
	editor=main.avatar_session.editor
	await key(KEY_X,false,120)
	check(editor.name_input.text!=committed.name,"再次编辑仅改草稿")
	await key(KEY_ESCAPE)
	await wait_phase("idle")
	check(main.avatar_profile.query()==committed and save_calls==2,"姓名框 Esc 取消修改且不调用保存")
	check(main.player.get_meta("avatar_appearance")==committed.appearance and main.hud.visible,"取消恢复角色外观与 HUD")
	await key(KEY_ESCAPE)
	await seek_menu("settings"); await key(KEY_ENTER)
	check(main.hud.menu.page=="settings" and main.hud.menu.buttons.motion.has_focus(),"设置页可由键盘进入并取得焦点")
	await key(KEY_DOWN); await key(KEY_DOWN); await key(KEY_DOWN)
	var volume=root.gui_get_focus_owner()
	check(volume is HSlider,"设置音量滑杆可由方向键到达")
	if volume is HSlider:
		var level: float=volume.value
		await key(KEY_LEFT)
		check(volume.value<level,"设置音量方向键调节")
	await key(KEY_ESCAPE)
	await seek_menu("reset"); await key(KEY_ENTER)
	check(main.hud.menu.page=="reset" and main.hud.menu.buttons.cancel.has_focus(),"重置安全确认默认聚焦取消")
	await key(KEY_KP_ENTER)
	check(main.hud.menu.page=="pause" and main.avatar_profile.query()==committed,"重置默认回车只取消，不变更档案")
	await seek_menu("reset"); await key(KEY_ENTER); await key(KEY_ESCAPE)
	check(main.hud.menu.page=="pause" and main.avatar_profile.query()==committed,"重置 Esc 返回且无副作用")
	await key(KEY_ESCAPE)
	check(not FileAccess.file_exists("user://save_slot_0.json"),"保存端口内存替身不创建存档文件")
	print("[keyboard-entry] %d checks, %d failures" % [checks,failures])
	main.queue_free(); await process_frame
	quit(0 if failures==0 else 1)

func seek_menu(id: String) -> void:
	for attempt in main.hud.menu.buttons.size()+1:
		if root.gui_get_focus_owner()==main.hud.menu.buttons.get(id): return
		await key(KEY_DOWN)
	check(false,"方向键可达暂停菜单 "+id)
