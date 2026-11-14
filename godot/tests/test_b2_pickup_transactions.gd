extends SceneTree

const Props = preload("res://src/pickups/sea_props.gd")
const Bag = preload("res://src/inventory/inventory.gd")
const Registry = preload("res://src/save/snapshot_registry.gd")
const Save = preload("res://src/save/save_game.gd")
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL [b2-pickup-transactions] ", label)

# 磁盘JSON的浮点文本会舍入末位；ID/数量/随机流仍精确比较。
func same_disk_value(a: Variant, b: Variant) -> bool:
	if a is float and (b is float or b is int): return absf(a - float(b)) < 0.000000000001
	if a is int and (b is int or b is float): return a == b
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not same_disk_value(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in a.size():
			if not same_disk_value(a[index],b[index]): return false
		return true
	return a == b

func fixture(ocean_enabled := false, kind := "crate") -> SeaProps:
	var props := Props.new()
	props.zones = root.get_node("Zones")
	props.ocean_enabled = ocean_enabled
	root.add_child(props)
	props.set_process(false)
	var data := {
		"crates":[{"id":1,"slot":"6:6:wood:0","kind":kind,"wood_amount":3,"base":[400.0,1.12,400.0],"phase":0.2,"yaw":0.3}],
		"schools":[{"id":2,"slot":"6:6:fish:0","base":[410.0,1.12,410.0],"phase":0.4,"count":3}],
		"pending":[],"pending_fish":[],"rng":"20261113","fish_rng":"20261023","next_id":3,"anchor":0,"elapsed":2.0}
	if ocean_enabled:
		data.ocean = {"version":1,"cycle":1,"now":8.0,"missing":{},"harvested":{},"wood_yields":{"6:6:wood:0":3}}
	props.from_dict(data)
	return props

func reject_nested(props: SeaProps, crate: Dictionary, school: Dictionary, label: String) -> void:
	check(props.is_busy(), label + "：owner busy")
	check(props.collect_crate(crate).is_empty() and not props.collect_fish(school), label + "：同类和跨类collect重入拒绝")
	var before := props.to_dict()
	var ocean = props.ocean
	props.from_dict({"reset":true})
	props.from_dict(before)
	props.sync_population({"day":9,"hour":7.0}, Vector3(-900,1.12,-900))
	props.apply_population_scope()
	props.build()
	props._process(999.0)
	check(props.to_dict() == before and props.ocean == ocean and props.is_busy(), label + "：恢复/刷新/计时不破坏busy现场")

func test_capacity() -> void:
	for ocean_enabled in [false, true]:
		for kind in ["crate", "barrel"]:
			for free in [0, 1, 2]:
				var props := fixture(ocean_enabled, kind)
				var inv := Bag.new(2)
				inv.from_dict({"capacity":2,"counts":{"rope":20,"glass":20} if free == 0 else ({"rope":20} if free == 1 else {})})
				props.receive_all = inv.add_all
				props.can_receive = func(_id, _amount): return true
				var events := {"changed":0,"collected":0,"blocked":0}
				inv.changed.connect(func(_id, _delta): events.changed += 1)
				props.collected.connect(func(_kind, _label, _reward): events.collected += 1)
				props.blocked.connect(func(_reason): events.blocked += 1)
				var crate: Dictionary = props.crates[0]
				var node: Node3D = crate.root
				var before := props.to_dict()
				var counts: Dictionary = inv.to_dict()
				var reward: Dictionary = props.crate_spec(crate).reward
				if free == 1:
					check(inv.can_add("wood", int(reward.wood)) and inv.can_add("parts", int(reward.parts)), "反例：单项预检各自通过但争用唯一空格")
				var got := props.collect_crate(crate)
				var label := "%s ocean=%s 空格=%d" % [kind,ocean_enabled,free]
				if free < 2:
					check(got.is_empty() and inv.to_dict() == counts and props.to_dict() == before, label + "：整笔失败保留账本/随机流/冷却/实体")
					check(not node.is_queued_for_deletion() and events.changed == 0 and events.collected == 0 and events.blocked == 1, label + "：无库存/成功事件，目标未删除")
				else:
					check(got.reward == reward and inv.all() == reward and events.changed == 2 and events.collected == 1, label + "：两资源完整到账且成功一次")
					check(not props.crates.has(crate) and node.is_queued_for_deletion(), label + "：成功才消费实体")
					check(props.ocean.missing.has(crate.slot) if ocean_enabled else props._pending.size() == 1, label + "：成功才提交冷却")
					var after := props.to_dict()
					check(props.collect_crate(crate).is_empty() and props.to_dict() == after and inv.all() == reward, label + "：旧目标不重复")
				check(not props.is_busy(), label + "：返回后释放busy")
				props.free()
	for row in [
		{"capacity":2,"counts":{"wood":20},"ok":true},
		{"capacity":2,"counts":{"wood":20,"parts":15},"ok":true},
		{"capacity":2,"counts":{"wood":39,"parts":15},"ok":false}]:
		var props := fixture(true)
		var inv := Bag.new(2)
		inv.from_dict(row)
		props.receive_all = inv.add_all
		var before: Dictionary = inv.all()
		var got := props.collect_crate(props.crates[0])
		check(not got.is_empty() == row.ok, "半堆按整笔合并容量判定：" + str(row.counts))
		check(inv.count("wood") == int(before.wood) + 2 and inv.count("parts") == int(before.get("parts",0)) + 1 if row.ok else inv.all() == before, "半堆成功完整增加，失败零增加")
		props.free()

func test_retry() -> void:
	for fish in [false, true]:
		var props := fixture(true)
		var inv := Bag.new(2)
		inv.from_dict({"capacity":2,"counts":{"rope":20,"glass":20}})
		props.receive_all = inv.add_all
		props.can_receive = func(_id, _amount): return true
		props.give_resource = func(_id, _amount) -> void: check(false, "原子拒收后不回退legacy给物")
		var crate: Dictionary = props.crates[0]
		var school: Dictionary = props.schools[0]
		var before := props.to_dict()
		check(not props.collect_fish(school) if fish else props.collect_crate(crate).is_empty(), "真实满包拒收")
		check(props.to_dict() == before and not props.is_busy(), "满包拒收保持随机流与冷却")
		inv.clear()
		check(props.collect_fish(school) if fish else not props.collect_crate(crate).is_empty(), "腾空后原目标可重试")
		check(inv.all() == ({"fish":1} if fish else {"wood":2,"parts":1}), "拒收后重试只到账一次")
		props.free()

func test_callbacks() -> void:
	for ocean_enabled in [false, true]:
		for fish in [false, true]:
			var props := fixture(ocean_enabled)
			var inv := Bag.new(8)
			var crate: Dictionary = props.crates[0]
			var school: Dictionary = props.schools[0]
			var before := props.to_dict()
			var events := {"receive":0,"changed":0,"success":0}
			props.give_resource = func(_id, _amount): check(false, "原子路径不得调用legacy give")
			props.can_receive = func(_id, _amount): check(false, "原子路径不依赖逐项预检"); return false
			props.receive_all = func(reward: Dictionary) -> bool:
				events.receive += 1
				reject_nested(props, crate, school, "receive_all")
				check(props.to_dict() == before and not crate.root.is_queued_for_deletion() and not school.root.is_queued_for_deletion(), "入账之前实体和冷却仍完整")
				var result: bool = inv.add_all(reward)
				reward.clear()
				return result
			inv.changed.connect(func(_id, _delta):
				events.changed += 1
				reject_nested(props, crate, school, "Inventory.changed")
				check(props.to_dict() == before and inv.is_busy(), "库存通知期间目标尚未消费，双owner busy")
				check(inv.count("fish") == 1 if fish else inv.count("wood") == 2 and inv.count("parts") == 1, "首个changed已经可见完整奖励")
			)
			var success := func():
				events.success += 1
				reject_nested(props, crate, school, "成功信号")
				check(not inv.is_busy(), "库存已释放而拾取owner仍busy")
				var target: Dictionary = school if fish else crate
				check(target.root.is_queued_for_deletion(), "成功信号看到目标已消费")
				check(props.ocean.missing.has(target.slot) if ocean_enabled else (props._pending_fish.size() == 1 if fish else props._pending.size() == 1), "成功信号看到冷却已提交")
			props.collected.connect(func(_kind, _label, reward): success.call(); reward.clear())
			props.fish_collected.connect(func(_label): success.call())
			var accepted: bool
			if fish: accepted = props.collect_fish(school)
			else:
				var got := props.collect_crate(crate)
				accepted = got.get("reward", {}) == {"wood":2,"parts":1}
			check(accepted and events.receive == 1 and events.success == 1 and events.changed == (1 if fish else 2) and not props.is_busy(), "全部回调重入不重复且返回reward不受回调篡改")
			props.free()
	for fish in [false, true]:
		var props := fixture(true)
		var crate: Dictionary = props.crates[0]
		var school: Dictionary = props.schools[0]
		var before := props.to_dict()
		props.receive_all = func(reward):
			reject_nested(props, crate, school, "拒收端口")
			reward.clear()
			return false
		props.blocked.connect(func(_reason): reject_nested(props, crate, school, "blocked"))
		check(not props.collect_fish(school) if fish else props.collect_crate(crate).is_empty(), "端口失败明确拒收")
		check(props.to_dict() == before and not crate.root.is_queued_for_deletion() and not school.root.is_queued_for_deletion() and not props.is_busy(), "失败及blocked重入后现场完全保留")
		props.free()

func test_legacy() -> void:
	var props := fixture(false)
	var calls := {"preflight":0,"give":0}
	var crate: Dictionary = props.crates[0]
	var school: Dictionary = props.schools[0]
	props.give_resource = func(_id, _amount) -> void: calls.give += 1
	props.can_receive = func(_id, _amount): calls.preflight += 1; return true
	var before := props.to_dict()
	check(props.collect_crate(crate).is_empty() and props.to_dict() == before and calls.give == 0 and calls.preflight == 0, "legacy复合奖励安全拒绝，不能伪造合并原子保证")
	props.free()
	for fish in [false, true]:
		props = fixture(false, "planks")
		crate = props.crates[0]
		school = props.schools[0]
		var inv := Bag.new(2)
		props.can_receive = func(id, amount):
			reject_nested(props, crate, school, "legacy预检")
			return inv.can_add(id, amount)
		props.give_resource = func(id, amount) -> void:
			reject_nested(props, crate, school, "legacy Void给物")
			inv.add(id, amount)
		check(props.collect_fish(school) if fish else not props.collect_crate(crate).is_empty(), "legacy单资源预检+保证完整Void给物保持兼容")
		check(inv.all() == ({"fish":1} if fish else {"wood":3}) and not props.is_busy(), "legacy单资源实际数量准确")
		props.free()
	props = fixture(false, "planks")
	before = props.to_dict()
	props.can_receive = func(_id, _amount): return false
	props.give_resource = func(_id, _amount) -> void: check(false, "预检失败不能给物")
	check(props.collect_crate(props.crates[0]).is_empty() and not props.collect_fish(props.schools[0]) and props.to_dict() == before, "legacy预检拒绝保留箱和鱼")
	props.can_receive = Callable()
	props.give_resource = Callable()
	check(props.collect_crate(props.crates[0]).is_empty() and not props.collect_fish(props.schools[0]), "未装配任一入账端口安全拒绝")
	props.free()

func test_restore() -> void:
	for ocean_enabled in [false, true]:
		var props := fixture(ocean_enabled)
		var inv := Bag.new(4)
		props.receive_all = inv.add_all
		var registry := Registry.new()
		registry.busy_query = props.is_busy
		registry.register("pickups",props.to_dict,props.from_dict,{},props.to_dict(),Callable(),[props])
		registry.register("inventory",inv.to_dict,inv.from_dict,{},inv.to_dict(),Callable(),[inv])
		var before := registry.capture()
		props.collect_crate(props.crates[0])
		props.collect_fish(props.schools[0])
		var after := registry.capture()
		check(registry.restore(before).ok and registry.capture() == before, "正常恢复收取前的实体/随机流/库存")
		props.collect_crate(props.crates[0])
		props.collect_fish(props.schools[0])
		check(registry.capture() == after, "恢复后再次收取产生完全一致的奖励与冷却随机流")
		check(registry.restore(after).ok and props.crates.is_empty() and props.schools.is_empty() and inv.all() == {"wood":2,"parts":1,"fish":1}, "恢复收取后快照不会复活已消费目标")
		props.free()

func test_main_save() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	main._autosave_on = false
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	main.props.set_process(false)
	main.boat.set_process(false)
	main.world_clock.paused = true
	var economy = root.get_node("Economy")
	economy.set_process(false)
	await process_frame
	await process_frame
	var props: SeaProps = main.props
	# 父线程负责生产接线；这里只显式注入真实Inventory以验收端口及真实Main busy_query。
	props.receive_all = economy.inventory.add_all
	main.boat.place_at(Vector3(400,1.12,400), 0.0)
	props.sync_population(main.world_clock.query(),main.boat.position)
	economy.inventory.from_dict({"capacity":24,"counts":{}})
	var snapshot := Save.encode(main)
	check(not snapshot.get("pickups", {}).is_empty(), "真实Main registry能正常捕获pickups")
	var observations := {"changed":0,"collected":0}
	var path := "user://b2-pickup-busy.json"
	var probe := func(label):
		check(props.is_busy() and main.save_registry.is_busy() and main.save_registry.capture().is_empty(), label + "：真实Main busy阻断capture")
		check(not Save.write(path,main).ok and not Save.restore(main,snapshot).ok, label + "：真实Save拒绝write/restore")
		check(not FileAccess.file_exists(path) and not FileAccess.file_exists(path+".tmp") and not FileAccess.file_exists(path+".bak"), label + "：无半笔磁盘快照")
	var on_changed := func(_id, _delta): observations.changed += 1; probe.call("Inventory.changed")
	economy.inventory.changed.connect(on_changed)
	var on_collected := func(_kind, _label, _reward): observations.collected += 1; probe.call("collected")
	props.collected.connect(on_collected)
	var crate: Dictionary = props.crates[0]
	crate.kind = "crate"
	crate.erase("wood_amount")
	check(not props.collect_crate(crate).is_empty() and observations.changed == 2 and observations.collected == 1, "真实Main混合箱整笔入账且回调存读拒绝")
	economy.inventory.changed.disconnect(on_changed)
	props.collected.disconnect(on_collected)
	var saved := Save.write("user://b2-pickup-complete.json",main)
	check(not props.is_busy() and saved.ok, "收取完成后真实Main存档恢复可用：" + str(saved.get("reason", "")))
	if saved.ok:
		var loaded := Save.read("user://b2-pickup-complete.json",main.save_registry)
		var committed := props.to_dict()
		var inventory: Dictionary = economy.inventory.to_dict()
		check(loaded.ok and Save.restore(main,loaded.snapshot).ok, "完整收取后真实磁盘快照可恢复")
		check(same_disk_value(props.to_dict(),committed) and economy.inventory.to_dict() == inventory, "真实磁盘恢复保留整笔奖励及消耗/冷却，不复活箱子")
	main.queue_free()
	await process_frame

func run() -> void:
	var user: String = ProjectSettings.get_setting("application/config/custom_user_dir_name", "")
	if not user.begins_with("sea-verification/"):
		check(false, "必须通过正式runner隔离user数据")
	else:
		test_capacity()
		test_retry()
		test_callbacks()
		test_legacy()
		test_restore()
		await test_main_save()
	await process_frame
	print("[b2-pickup-transactions] %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
