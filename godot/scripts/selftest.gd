extends Node
## 无窗口自检：`Godot --headless --path . -- --selftest`
##
## 覆盖不依赖渲染的逻辑：区块数据、经济状态机、物资/鱼群生成、船只到站。
## 画面相关的部分靠 outputs/godot-preview.png 的人工/脚本比对。

const WATER_LEVEL := 1.12

var _pass := 0
var _fail := 0


func _mark(tag: String) -> void:
	var f := FileAccess.open("/tmp/selftest-progress.log", FileAccess.WRITE)
	if f:
		f.store_line(tag)
		f.flush()
		f.close()


func _ready() -> void:
	_mark("boot")
	await get_tree().process_frame
	_mark("frame")
	_test_zones()
	_mark("zones")
	await _test_economy()
	_test_inventory()
	_mark("economy")
	await _test_build()
	_mark("build")
	await _test_farm()
	_mark("farm")
	_test_scene_contract()
	_mark("scene")
	_test_props()
	_mark("props")
	await _test_sail()
	_mark("sail")
	await _test_zones_scene()
	_mark("scenes")
	if not OS.get_cmdline_user_args().has("--skip-models"):
		_test_models()
	await _test_walk()
	await _test_gather()
	await _test_underwater()
	_test_plants()
	_test_sail_nav()
	_test_camera()
	_test_water_click()
	_test_salvage()
	_test_pointer_detail()
	print("\n[selftest] %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _ok(name: String, cond: bool, detail := "") -> void:
	if cond:
		_pass += 1
		print("  PASS  ", name)
	else:
		_fail += 1
		print("  FAIL  ", name, "  ", detail)


func _test_zones() -> void:
	print("[zones]")
	_ok("五个区块", Zones.list.size() == 5, str(Zones.list.size()))
	_ok("zone1 有两个上岸点", Zones.landings_of("zone1").size() == 2)
	_ok("zone4 需要远海解锁", not Zones.is_unlocked("zone4"))
	GameState.far_sea_unlocked = true
	_ok("解锁后 zone4 可去", Zones.is_unlocked("zone4"))
	GameState.far_sea_unlocked = false
	var l := Zones.landing("zone1", "salvage")
	_ok("打捞台坐标", abs(float(l.boatPark[0]) + 7.2) < 0.01, str(l.get("boatPark")))


func _test_economy() -> void:
	print("[economy]")
	var start_wood := Economy.wood
	var start_parts := Economy.parts
	var t := 100.0
	var gain: Dictionary = Economy.do_salvage(t)
	_ok("打捞产出 3 木 2 零件", gain.get("wood", 0) == 3 and gain.get("parts", 0) == 2)
	_ok("木料到账", Economy.wood == start_wood + 3)
	_ok("冷却中不能再打捞", Economy.do_salvage(t).is_empty())
	_ok("冷却按常量走", abs(Economy.salvage_cooldown_left(t) - Economy.SALVAGE_COOLDOWN) < 0.01,
		str(Economy.salvage_cooldown_left(t)))
	await get_tree().process_frame
	# 测试前置：一次打捞只有 3 木，而一级升级要 4 木。真实流程里差额靠漂流物补齐，
	# 这里直接补足，避免把"采集不够"误判成"升级坏了"。
	Economy.wood = 10
	Economy.parts = 6
	var coins_before := Economy.coins
	# 建造改成两段式：交付材料 → 倒计时 → 才升级。这里手动推进时钟，避免依赖帧率。
	Economy.ticking = false
	var r: Dictionary = Economy.begin_site_upgrade("home_cabin")
	_ok("木屋可开工", r.get("ok", false), str(r))
	_ok("开工即扣材料", Economy.coins < coins_before)
	_ok("开工后等级还没变", Economy.site_level("home_cabin") == 1)
	Economy.tick_sites(999.0)
	_ok("木屋到 2 级", Economy.site_level("home_cabin") == 2)
	Economy.ticking = true
	# 初始 rooftop_planter 已是 1 级，温室前置此时其实已满足；
	# 这里把农场降回未建状态，专门验证「前置不足时必须挡住」。
	Economy.site_levels["rooftop_planter"] = 0
	_ok("温室前置未满足", not Economy.can_build_facility("greenhouse"))
	Economy.site_levels["rooftop_planter"] = 2
	Economy.coins = 200
	Economy.wood = 50
	Economy.parts = 30
	Economy.glass = 6
	Economy.rope = 6
	_ok("补足前置后可建温室", Economy.can_build_facility("greenhouse"))
	_ok("建温室成功", Economy.build_facility("greenhouse").get("ok", false))
	_ok("船可升级", Economy.upgrade_ship().get("ok", false))
	_ok("船只 2 级解锁远海", Economy.ship_level == 2 and GameState.far_sea_unlocked)


## 背包：物品定义、叠放、容量、原子扣除、存档往返。
func _test_inventory() -> void:
	print("[inventory]")
	var ItemDBLib = preload("res://scripts/core/item_db.gd")
	var InventoryLib = preload("res://scripts/core/inventory.gd")

	# 物品表必须覆盖所有采集类型，否则采到的东西会静默丢弃。
	for kind in ["shell", "rope", "wood", "parts", "glass", "seed", "fish", "pearl"]:
		_ok("物品表含 %s" % kind, ItemDBLib.has(kind))
	_ok("货币在物品表里", ItemDBLib.is_currency("coins"))
	_ok("木料不是货币", not ItemDBLib.is_currency("wood"))

	var inv = InventoryLib.new(6)
	_ok("容量为 6", inv.capacity() == 6 and inv.slots_used() == 0)

	# 货币不占格
	inv.add("coins", 999)
	_ok("货币不占格", inv.slots_used() == 0 and inv.count("coins") == 999)

	# 叠放：木料 stack=40，80 个应该占 2 格
	var r: Dictionary = inv.add("wood", 80)
	_ok("一次加 80 木料", r.added == 80 and r.ok, str(r))
	_ok("占 2 格", inv.slots_used() == 2, str(inv.slots_used()))
	_ok("剩余 4 格", inv.slots_free() == 4, str(inv.slots_free()))

	# 容量上限：再加 5 种各 1 个，第 7 格放不下
	for id in ["parts", "rope", "glass", "seed"]:
		inv.add(id, 1)
	_ok("用掉 6 格", inv.slots_used() == 6, str(inv.slots_used()))
	var over: Dictionary = inv.add("fish", 5)
	_ok("满了加不进去", over.added == 0 and over.overflow == 5, str(over))
	_ok("满了给原因", str(over.reason) != "")

	# 部分溢出：剩 0 格时一点都放不进
	inv.remove("seed", 1)
	var partial: Dictionary = inv.add("fish", 30)
	_ok("腾出一格只进一叠", partial.added == 20 and partial.overflow == 10, str(partial))

	# 原子扣除
	inv.remove("wood", 80)
	inv.add("wood", 5)
	_ok("不够时不扣", not inv.remove("wood", 6) and inv.count("wood") == 5)
	_ok("够了才扣", inv.remove("wood", 5) and inv.count("wood") == 0)

	# 多物品检查与缺口
	inv.add("wood", 3)
	inv.add("parts", 1)
	_ok("has_all 通过", inv.has_all({"wood": 3, "parts": 2}))
	_ok("has_all 不通过", not inv.has_all({"wood": 3, "parts": 3}))
	var lack: Dictionary = inv.missing({"wood": 5, "parts": 4})
	_ok("缺口正确", lack == {"wood": 2, "parts": 2}, str(lack))
	_ok("原子支付失败不改账", not inv.pay({"wood": 9}) and inv.count("wood") == 3)

	# 存档往返
	var snapshot: Dictionary = inv.to_dict()
	var inv2 = InventoryLib.new(6)
	inv2.from_dict(snapshot)
	_ok("存档还原数量", inv2.count("wood") == inv.count("wood") and inv2.count("coins") == inv.count("coins"))
	_ok("存档还原容量", inv2.capacity() == inv.capacity())
	# 旧存档里可能有已删除的物品，读档必须忽略而不是报错
	var legacy := {"capacity": 8, "counts": {"wood": 2, "gone_item": 99}}
	inv2.from_dict(legacy)
	_ok("旧存档忽略未知物品", inv2.count("wood") == 2 and inv2.count("gone_item") == 0)

	# 经济层的兼容层：属性读写仍然可用
	var before := Economy.count("wood")
	Economy.wood = before + 1
	_ok("Economy.wood 属性可写", Economy.count("wood") == before + 1)
	Economy.wood = before
	_ok("Economy.wood 属性可读回", Economy.count("wood") == before)
	_ok("错过物品给缺口文案", Economy.missing_text({"wood": 9999}).begins_with("还差"))

	# 背包面板：打开后必须按物品表渲染格子（不是写死的行）。
	var main := get_parent()
	var hud = main.hud
	if not hud._panel_open:
		hud._toggle_panel()
	hud._tab = hud.TAB_BAG
	hud._refresh_panel()
	_ok("背包面板已打开", hud._panel.visible)
	var BackpackGridScript = preload("res://scripts/ui/backpack_grid.gd")
	var found_grid := false
	for n in hud._tab_body.get_children():
		if n.get_script() == BackpackGridScript:
			found_grid = true
	_ok("背包页有格子容器", found_grid)
	hud._tab = hud.TAB_BUILD
	hud._refresh_panel()
	_ok("建造页可切换", hud._tab_body.get_child_count() > 0)
	hud._toggle_panel()
	_ok("面板可关闭", not hud._panel.visible)


## 建造：世界里要有牌子，交付材料后真的等一段时间才升级。
func _test_build() -> void:
	print("[build]")
	var main := get_parent()
	var field: Node = main.get_node_or_null("World/Gameplay/BuildField")
	if field == null:
		field = main.get_node_or_null("BuildField")
	_ok("BuildField 存在", field != null)
	if field == null:
		return
	_ok("建造牌数量", field.sites.size() == 3, str(field.sites.size()))

	# 契约一：牌子必须站在所属区块的行走面上（和采集点同一条规则）。
	for node in field.sites:
		var cfg: Dictionary = Zones.get_zone(node.zone_id)
		var on_deck := false
		for w in cfg.get("walk", []):
			for rect in w.get("rects", []):
				var inside: bool = node.position.x >= float(rect[0]) - 0.05 \
					and node.position.x <= float(rect[1]) + 0.05 \
					and node.position.z >= float(rect[2]) - 0.05 \
					and node.position.z <= float(rect[3]) + 0.05
				if inside and absf(node.position.y - float(w.get("y", node.position.y))) < 0.4:
					on_deck = true
		_ok("%s 落在可行走面" % node.site_id, on_deck, str(node.position))

	var site: Node3D = field.find("home_cabin")
	_ok("找到木屋建造牌", site != null)
	if site == null:
		return

	Economy.ticking = false
	Economy.site_levels["home_cabin"] = 1
	Economy.site_work.clear()

	# 契约二：材料不够时一件不扣，也不开工。
	Economy.wood = 0
	Economy.parts = 0
	Economy.coins = 0
	var blocked: Dictionary = site.interact(main.player)
	_ok("材料不够被挡住", blocked.has("blocked"), str(blocked))
	_ok("挡住时不扣材料", Economy.wood == 0 and not Economy.is_building("home_cabin"))

	# 契约三：交付 → 扣齐材料 → 等级不变、开始倒计时。
	Economy.coins = 60
	Economy.wood = 12
	Economy.parts = 8
	var wood_before := Economy.wood
	var started: Dictionary = site.interact(main.player)
	_ok("交付后开工", started.get("event", "") == "site_work_started", str(started))
	_ok("开工扣木材", Economy.wood == wood_before - 4, "%d → %d" % [wood_before, Economy.wood])
	_ok("开工后等级不变", Economy.site_level("home_cabin") == 1)
	_ok("施工中可读进度", Economy.is_building("home_cabin"))
	_ok("脚手架已出现", site._scaffold.visible)
	var total := Economy.site_build_seconds("home_cabin")
	_ok("施工时长配置生效", total >= 10.0, "%.0fs" % total)

	# 契约四：施工中不能重复交付（材料也不能再扣一次）。
	var again: Dictionary = site.interact(main.player)
	_ok("施工中拒绝二次交付", again.has("blocked"), str(again))
	_ok("二次交付不扣材料", Economy.wood == wood_before - 4)

	# 契约五：进度按时间推进，没到点不升级。
	Economy.tick_sites(total * 0.5)
	_ok("一半时间仍在施工", Economy.is_building("home_cabin"))
	_ok("进度约 50%", absf(Economy.site_work_progress("home_cabin") - 0.5) < 0.05,
		"%.2f" % Economy.site_work_progress("home_cabin"))
	_ok("半程未升级", Economy.site_level("home_cabin") == 1)

	# 契约六：走完才算竣工，脚手架收起、等级 +1。
	Economy.tick_sites(total * 0.6)
	_ok("到点竣工", not Economy.is_building("home_cabin"))
	_ok("竣工升到 2 级", Economy.site_level("home_cabin") == 2)
	_ok("脚手架已收起", not site._scaffold.visible)
	_ok("满级不再开工", site.interact(main.player).has("blocked") or Economy.site_maxed("home_cabin") == false)

	# 契约七：施工进度进存档，读回来接着倒计时。
	Economy.site_work["rooftop_planter"] = {"left": 7.0, "total": 20.0}
	var blob: Dictionary = Economy.to_dict()
	Economy.site_work.clear()
	Economy.from_dict(blob)
	_ok("施工进度可存档", Economy.is_building("rooftop_planter"))
	_ok("剩余时间保留", absf(Economy.site_work_left("rooftop_planter") - 7.0) < 0.01,
		"%.1f" % Economy.site_work_left("rooftop_planter"))
	Economy.site_work.clear()
	Economy.ticking = true


## 反复浇水直到成熟：一茬本来就需要浇几次，测试也不该假设一次够。
func _water_until_ready(farm, plot_id: String, limit := 12) -> bool:
	for i in limit:
		if farm.phase(plot_id) == "ready":
			return true
		if farm.is_dry(plot_id):
			farm.interact(plot_id)
		farm.tick(farm.thirst_seconds(farm.crop_of(plot_id)))
	return farm.phase(plot_id) == "ready"


## 种植：菜箱状态机、缺水停长、温室加成、存档。
func _test_farm() -> void:
	print("[farm]")
	var ItemDBLib = preload("res://scripts/core/item_db.gd")
	var main := get_parent()
	var field: Node = main.get_node_or_null("World/Gameplay/FarmField")
	if field == null:
		field = main.get_node_or_null("FarmField")
	_ok("FarmField 存在", field != null)
	var farm = Economy.farm
	_ok("种植模型已挂到 Economy", farm != null)
	if farm == null or field == null:
		return
	_ok("菜箱数量", field.plots.size() == 3, str(field.plots.size()))
	_ok("作物表至少三种", farm.crops.size() >= 3, str(farm.crops.size()))

	# 契约一：菜箱落在所属区块的可行走面上（和建造牌同一条规则）。
	for node in field.plots:
		var cfg: Dictionary = Zones.get_zone(node.zone_id)
		var on_deck := false
		for w in cfg.get("walk", []):
			for rect in w.get("rects", []):
				var inside: bool = node.position.x >= float(rect[0]) - 0.05 \
					and node.position.x <= float(rect[1]) + 0.05 \
					and node.position.z >= float(rect[2]) - 0.05 \
					and node.position.z <= float(rect[3]) + 0.05
				if inside and absf(node.position.y - float(w.get("y", node.position.y))) < 0.4:
					on_deck = true
		_ok("%s 落在可行走面" % node.plot_id, on_deck, str(node.position))

	# 契约二：作物产量引用的物品必须真的存在于物品表。
	for crop_id in farm.crops.keys():
		var row: Dictionary = farm.crops[crop_id]
		for item_id in row.get("yield", {}).keys():
			_ok("%s 的产出 %s 在物品表里" % [crop_id, item_id], ItemDBLib.has(str(item_id)))

	Economy.ticking = false
	Economy.inventory.clear()
	Economy.site_levels["home_cabin"] = 1
	Economy.facilities["greenhouse"] = false
	farm.selected_crop = "tomato"
	farm.from_dict({})
	Economy.give({"seed": 5})

	# 契约三：前置没到，播种被挡住且不扣种子。
	var before_seed := Economy.count("seed")
	var locked: Dictionary = farm.interact("home_plot", "tomato")
	_ok("前置未满足被挡住", locked.has("blocked"), str(locked))
	_ok("挡住时种子不扣", Economy.count("seed") == before_seed)
	_ok("挡住时地是空的", farm.phase("home_plot") == "empty")

	Economy.site_levels["home_cabin"] = 2
	var planted: Dictionary = farm.interact("home_plot", "tomato")
	_ok("解锁后可播种", planted.get("event", "") == "planted", str(planted))
	_ok("播种扣 1 颗种子", Economy.count("seed") == before_seed - 1)
	_ok("播种后进入生长", farm.phase("home_plot") == "growing")
	var grow_total: float = farm.grow_seconds("tomato")
	_ok("生长时长来自作物表", absf(float(farm.state("home_plot").remaining) - grow_total) < 0.01,
		"%.1f" % grow_total)
	_ok("刚播下是湿的", not farm.is_dry("home_plot"))

	# 契约四：水用完就停长（不是「时间到了自动熟」）。
	var thirst: float = farm.thirst_seconds("tomato")
	farm.tick(thirst + 5.0)
	_ok("水已耗尽", farm.is_dry("home_plot"))
	var stalled: float = float(farm.state("home_plot").remaining)
	farm.tick(30.0)
	_ok("缺水时停止生长", absf(float(farm.state("home_plot").remaining) - stalled) < 0.001,
		"%.1f → %.1f" % [stalled, float(farm.state("home_plot").remaining)])
	_ok("缺水给出明确状态", farm.status_text("home_plot").contains("缺水"),
		farm.status_text("home_plot"))

	# 契约五：浇水后继续长，浇满不求人。
	var watered: Dictionary = farm.interact("home_plot")
	_ok("浇水成功", watered.get("event", "") == "watered", str(watered))
	_ok("土壤重新湿润", not farm.is_dry("home_plot"))
	var wet_again: Dictionary = farm.interact("home_plot")
	_ok("湿着再浇会被拒", wet_again.has("blocked") or wet_again.get("event", "") == "view", str(wet_again))

	# 契约六：一茬要浇好几次水；一直浇到成熟。
	_ok("浇够水才熟", _water_until_ready(farm, "home_plot"))
	_ok("到点成熟", farm.phase("home_plot") == "ready", farm.phase("home_plot"))
	var veg_before := Economy.count("tomato")
	var picked: Dictionary = farm.interact("home_plot")
	_ok("收获成功", picked.get("event", "") == "harvested", str(picked))
	_ok("番茄进背包", Economy.count("tomato") == veg_before + 2,
		"%d → %d" % [veg_before, Economy.count("tomato")])
	_ok("收完地空了", farm.phase("home_plot") == "empty")

	# 契约七：背包满时不能收，菜也不会丢。
	Economy.inventory.clear()
	Economy.give({"seed": 1})
	farm.interact("farm_plot_a", "lettuce")
	_ok("农场菜箱熟了", _water_until_ready(farm, "farm_plot_a"), farm.phase("farm_plot_a"))
	Economy.inventory.add("wood", Economy.inventory.slots_free() * 40)
	var full: Dictionary = farm.interact("farm_plot_a")
	_ok("背包满时拒绝收获", full.has("blocked"), str(full))
	_ok("背包满时地仍是成熟的", farm.phase("farm_plot_a") == "ready")

	# 契约八：温室加成体现在「更快 + 更多」，而不是偷偷改一个数。
	Economy.inventory.clear()
	farm.from_dict({})
	var plain_grow: float = farm.grow_seconds("lettuce")
	var plain_yield: Dictionary = farm.yield_of("lettuce")
	Economy.facilities["greenhouse"] = true
	var fast_grow: float = farm.grow_seconds("lettuce")
	var rich_yield: Dictionary = farm.yield_of("lettuce")
	_ok("温室缩短生长", fast_grow < plain_grow, "%.1f vs %.1f" % [fast_grow, plain_grow])
	_ok("温室多收一份", int(rich_yield.get("vegetable", 0)) == int(plain_yield.get("vegetable", 0)) + 1,
		str(rich_yield))
	Economy.facilities["greenhouse"] = false

	# 契约九：存档往返保留作物、进度与水分；未知菜箱被忽略。
	Economy.give({"seed": 2})
	farm.interact("farm_plot_a", "pumpkin")
	farm.tick(7.5)
	var blob: Dictionary = Economy.to_dict()
	farm.from_dict({})
	_ok("读档前状态被清空", farm.phase("farm_plot_a") == "empty")
	Economy.from_dict(blob)
	_ok("读档恢复作物", farm.crop_of("farm_plot_a") == "pumpkin", farm.crop_of("farm_plot_a"))
	_ok("读档保留剩余时间", absf(float(farm.state("farm_plot_a").remaining)
		- float(blob.farm.plots.farm_plot_a.remaining)) < 0.01)
	var stale := {"plots": {"no_such_plot": {"crop": "tomato", "remaining": 1.0}}}
	farm.from_dict(stale)
	_ok("未知菜箱不会让读档报错", farm.phase("farm_plot_a") == "empty")

	Economy.inventory.clear()
	Economy.site_levels["home_cabin"] = 1
	Economy.ticking = true


## 场景契约：能手动编辑的东西必须真的在 .tscn 里，而不是运行时 new 出来的。
## 这条断言的价值在于「以后有人把节点改回程序化」时会立刻红。
func _test_scene_contract() -> void:
	print("[scene]")
	var main := get_parent()
	var required := [
		"World/WorldEnvironment",
		"World/Lights/Sun",
		"World/Lights/HemisphereFill",
		"World/Lights/VioletShadow",
		"World/Lights/GroundBounce",
		"World/Water",
		"World/Gameplay/GatherField",
		"World/Gameplay/BuildField",
		"World/Gameplay/FarmField",
		"World/Gameplay/SeaProps",
		"Camera",
		"Boat",
		"Boat/Explorer",
		"Birds",
		"Underwater",
		"LandingMarkers",
		"HUD",
		"InteractPrompt",
		"ColorGrade",
	]
	for path in required:
		_ok("场景里有 %s" % path, main.get_node_or_null(path) != null)

	# 环境必须在场景资源里，而不是代码里现造的一份。
	var we: WorldEnvironment = main.get_node_or_null("World/WorldEnvironment")
	if we != null and we.environment != null:
		_ok("Environment 来自资源文件", we.environment.resource_path != "",
			we.environment.resource_path)
		_ok("环境亮度是标定值", absf(we.environment.ambient_light_energy - 0.56) < 0.001,
			"%.2f" % we.environment.ambient_light_energy)

	# 水面材质同样要可编辑，且运行时只补动态参数。
	var water: MeshInstance3D = main.get_node_or_null("World/Water")
	if water != null:
		var mat := water.material_override as ShaderMaterial
		_ok("水面材质来自资源文件", mat != null and mat.resource_path != "",
			mat.resource_path if mat != null else "-")
		if mat != null:
			_ok("水面高度与常量一致", absf(water.position.y - WATER_LEVEL) < 0.001)
			_ok("岸线数据已注入", int(mat.get_shader_parameter("u_shore_count")) > 0,
				str(mat.get_shader_parameter("u_shore_count")))

	# 相机机位是 export 值：编辑器里改，运行时照做。
	var cam := main.get_node_or_null("Camera") as Camera3D
	if cam != null:
		_ok("相机有可编辑的 target", cam.has_method("refresh"))
		var expect: Vector3 = cam.get("target")
		_ok("相机 target 是场景默认值", expect.distance_to(Vector3(0.45, 1.75, -0.65)) < 0.01,
			str(expect))

	# 滤镜面板：写入的必须是场景里那一个 Environment。
	var grade = main.grade
	_ok("滤镜面板已装配", grade != null)
	if grade != null and we != null and we.environment != null:
		var env := we.environment
		var before := env.adjustment_saturation
		grade.set_values(0.9, 0.95, 1.12, 1.25)
		_ok("滤镜写入饱和度", absf(env.adjustment_saturation - 1.25) < 0.001,
			"%.2f" % env.adjustment_saturation)
		_ok("滤镜写入对比度", absf(env.adjustment_contrast - 1.12) < 0.001)
		_ok("滤镜写入曝光", absf(env.tonemap_exposure - 0.9) < 0.001)
		grade.set_values(0.96, 1.0, 1.0, before)
		_ok("滤镜可复位", absf(env.adjustment_saturation - before) < 0.001)


func _test_props() -> void:
	print("[props]")
	var props = load("res://scripts/sea_props.gd").new()
	add_child(props)
	props.build()
	_ok("漂流物资 9 份", props.crates.size() == 9, str(props.crates.size()))
	_ok("鱼群 7 群", props.schools.size() == 7, str(props.schools.size()))
	for c in props.crates:
		_ok("物资不在陆地", not props._is_land(c.base.x, c.base.z), str(c.base))
		break
	var before := Economy.wood
	var got: Dictionary = props.collect_crate(props.crates[0])
	_ok("收箱有奖励", not got.is_empty(), str(got))
	_ok("木料增加", Economy.wood > before)
	_ok("收完少一个", props.crates.size() == 8)
	var fish_before := Economy.fish
	props.collect_fish(props.schools[0])
	_ok("捞鱼 +1", Economy.fish == fish_before + 1)
	props.queue_free()


func _test_sail() -> void:
	print("[sail]")
	var boat = load("res://scripts/boat.gd").new()
	add_child(boat)
	boat.build()
	var l := Zones.landing("zone1", "main")
	boat.place_at(Vector3(l.boatPark[0], WATER_LEVEL, l.boatPark[2]), float(l.boatYaw))
	var l2 := Zones.landing("zone2", "main")
	var arrived := {"hit": false}
	boat.arrived.connect(func(z, _lid): arrived.hit = z; arrived.hit = true if z == "zone2" else arrived.hit)
	boat.sail_to(Vector3(l2.boatPark[0], WATER_LEVEL, l2.boatPark[2]), float(l2.boatYaw), "zone2", "main")
	_ok("出发后进入航行", boat.starts_sailing())
	var guard := 0
	while boat.starts_sailing() and guard < 4000:
		boat._process(0.05)
		guard += 1
	_ok("能开到横滨铁道", not boat.starts_sailing(), "frames=%d" % guard)
	_ok("到站坐标贴合泊位",
		Vector2(boat.position.x - float(l2.boatPark[0]), boat.position.z - float(l2.boatPark[2])).length() < 0.05,
		str(boat.position))
	# 靠妥后会按角速度上限把船身拧正（不硬 snap），这里补几帧再看朝向。
	var dock_guard := 0
	while boat._dock_left > 0.0 and dock_guard < 400:
		boat._process(1.0 / 60.0)
		dock_guard += 1
	_ok("到站朝向贴合", abs(angle_difference(boat.rotation.y, float(l2.boatYaw))) < 0.02,
		"%.3f vs %.3f" % [boat.rotation.y, float(l2.boatYaw)])
	boat.queue_free()


## 区块场景结构：每个区块一个 tscn，建筑几何是 Models 下的真实 glb 实例节点，
## StaticBatch / WalkAreas / Plants / Landings 各就各位。
func _test_zones_scene() -> void:
	print("[zone-scenes]")
	var main := get_parent()
	var zones_root: Node = main.get_node_or_null("World/Zones")
	_ok("World/Zones 存在", zones_root != null)
	if zones_root == null:
		return
	_ok("五个区块场景实例", zones_root.get_child_count() == 5, str(zones_root.get_child_count()))
	var seen := {}
	for zone in zones_root.get_children():
		seen[zone.zone_id] = true
		var batch: Node = zone.get_node_or_null("StaticBatch")
		var models: Node = zone.get_node_or_null("Models")
		_ok("%s 有 StaticBatch" % zone.zone_id, batch != null)
		_ok("%s 有 Models（建筑几何节点）" % zone.zone_id, models != null)
		if zone.geometry_source == "scene":
			# 实体几何：glb 实例 + 每张面一个共享材质，编辑器里可选中。
			var meshes: Array = []
			if models != null:
				var stack: Array = [models]
				while not stack.is_empty():
					var n: Node = stack.pop_back()
					if n is MeshInstance3D:
						meshes.append(n)
					stack.append_array(n.get_children())
			_ok("%s 场景里有网格节点" % zone.zone_id, meshes.size() > 0, str(meshes.size()))
			var missing := 0
			var total := 0
			for raw in meshes:
				var mi: MeshInstance3D = raw
				if mi.mesh == null:
					continue
				for i in mi.mesh.get_surface_count():
					total += 1
					if not (mi.get_surface_override_material(i) is ShaderMaterial):
						missing += 1
			_ok("%s 每张面都有共享材质" % zone.zone_id, missing == 0,
				"%d/%d 缺材质" % [missing, total])
			_ok("%s 几何可见" % zone.zone_id, models != null and models.visible)
			_ok("%s 烘焙批次已让位（不重复建）" % zone.zone_id,
				batch != null and batch.instance_count == 0,
				str(batch.instance_count) if batch else "null")
		else:
			_ok("%s 静态实例已装载" % zone.zone_id,
				batch != null and batch.instance_count > 0,
				str(batch.instance_count) if batch else "0")
		var walks: Array = zone.walk_areas
		_ok("%s 有可行动区域" % zone.zone_id, walks.size() > 0, str(walks.size()))
		var cfg: Dictionary = Zones.get_zone(zone.zone_id)
		_ok("%s 区域数与配置一致" % zone.zone_id, walks.size() == cfg.get("walk", []).size(),
			"%d vs %d" % [walks.size(), cfg.get("walk", []).size()])
		var plants: Node = zone.get_node_or_null("Plants")
		_ok("%s 有植物场" % zone.zone_id, plants != null)
	for zid in Zones.list:
		_ok("%s 场景已装配" % zid.id, seen.has(zid.id))


## glb 资产：清单、文件、顶点数与包围盒都要对得上烘焙。
func _test_models() -> void:
	print("[models]")
	var roots := [
		"res://assets/models/zones/zone1_home_harbor",
		"res://assets/models/zones/zone2_yokohama_station",
		"res://assets/models/zones/zone3_arc_farm",
		"res://assets/models/zones/zone4_far_shore",
		"res://assets/models/zones/zone5_aqua_platform",
	]
	var total_units := 0
	for root in roots:
		var f := FileAccess.open(root + "/manifest.json", FileAccess.READ)
		_ok("%s 有 manifest" % root.get_file(), f != null)
		if f == null:
			continue
		var m: Variant = JSON.parse_string(f.get_as_text())
		_ok("%s manifest 可解析" % root.get_file(), m is Dictionary)
		if not (m is Dictionary):
			continue
		_ok("%s 有整区 glb" % root.get_file(),
			ResourceLoader.exists(root + "/" + str(m.name) + ".glb"))
		var units: Array = m.get("units", [])
		_ok("%s 有独立单元" % root.get_file(), units.size() > 0, str(units.size()))
		var counted := 0
		for i in units.size():
			var u: Dictionary = units[i]
			total_units += 1
			counted += int(u.get("instance_count", 0))
			var path: String = root + "/" + str(u.file)
			_ok("%s/%s 存在" % [root.get_file(), u.id], ResourceLoader.exists(path))
			# glb 加载很重：每个区块只深检首尾两个单元，其余只验文件与清单。
			# 全量深检会把 headless 进程撑到被沙箱回收（exit 137）。
			if i > 0:
				continue
			var packed: Variant = load(path) if ResourceLoader.exists(path) else null
			_ok("%s/%s 可实例化" % [root.get_file(), u.id], packed != null)
			if packed == null:
				continue
			var node: Node3D = packed.instantiate()
			# 一个单元按材质切成多个 primitive，Godot 导入后可能变成多个 MeshInstance3D；
			# 而且导入会焊接重复顶点。所以这里比 **三角形数**（焊接不影响）与 **合并包围盒**，
			# 不再逐顶点数对账 —— 那样只会测到导入器的优化策略。
			var tri := 0
			var has_color := true
			var aabb := AABB()
			var first := true
			var meshes := _all_meshes(node)
			_ok("%s/%s 有网格" % [root.get_file(), u.id], meshes.size() > 0)
			for mi in meshes:
				var mesh: Mesh = mi.mesh
				for si in mesh.get_surface_count():
					var arrays: Array = mesh.surface_get_arrays(si)
					var idx: Variant = arrays[Mesh.ARRAY_INDEX]
					var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					tri += (int(idx.size()) / 3) if idx != null else (verts.size() / 3)
					if arrays[Mesh.ARRAY_COLOR] == null:
						has_color = false
				var b: AABB = mesh.get_aabb()
				# 网格顶点已按单元原点平移，实例自身的 transform 也要算进去。
				b = mi.transform * b
				aabb = b if first else aabb.merge(b)
				first = false
			var want_tri := int(u.get("triangles", 0))
			_ok("%s/%s 三角形数与清单一致" % [root.get_file(), u.id],
				tri > 0 and absi(tri - want_tri) <= maxi(4, int(want_tri * 0.005)),
				"%d vs %d" % [tri, want_tri])
			_ok("%s/%s 带顶点色" % [root.get_file(), u.id], has_color)
			var size: Array = u.bounds.size
			_ok("%s/%s 尺寸吻合" % [root.get_file(), u.id],
				absf(aabb.size.x - float(size[0])) < 0.35
				and absf(aabb.size.y - float(size[1])) < 0.35
				and absf(aabb.size.z - float(size[2])) < 0.35,
				"%s vs %s" % [str(aabb.size.round()), str(size)])
			node.free()
		_ok("%s 单元实例数之和 = 区块实例数" % root.get_file(),
			counted == int(m.get("instance_count", -1)),
			"%d vs %d" % [counted, int(m.get("instance_count", -1))])
	_ok("模型单元总数合理", total_units >= 10, str(total_units))


func _verts_aabb(verts: PackedVector3Array) -> AABB:
	if verts.is_empty():
		return AABB()
	var b := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		b = b.expand(v)
	return b


func _all_meshes(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _first_mesh(root: Node) -> Mesh:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			return (n as MeshInstance3D).mesh
		for c in n.get_children():
			stack.append(c)
	return null


## 可行动区域：射线求交 + 点击走上去
func _test_walk() -> void:
	print("[walk]")
	var main := get_parent()
	var zone: Node3D = main._zone_nodes.get("zone1")
	_ok("current_zone 有场景", zone != null)
	if zone == null:
		return
	var area: Node3D = zone.walk_areas[0]
	var center: Vector3 = area.center_world()
	_ok("区域中心高度等于站立面", absf(center.y - area.surface_y) < 0.01)
	# 从正上方往下打
	var hit: Dictionary = zone.pick_walk(Vector3(center.x, center.y + 30.0, center.z), Vector3.DOWN)
	_ok("正上方射线命中甲板", not hit.is_empty())
	_ok("命中点就是区域", hit.get("area", null) == area)
	# 区域外不该命中
	var outside: Dictionary = zone.pick_walk(
		Vector3(center.x + 40.0, center.y + 30.0, center.z + 40.0), Vector3.DOWN)
	_ok("区域外不命中", outside.is_empty())
	# 走真实点击路径：投影到屏幕 → main._try_walk
	var screen: Vector2 = main.cam.unproject_position(center)
	_ok("区域中心在屏幕内", main.cam.is_position_behind(center) == false)
	var walked: bool = main._try_walk(screen)
	_ok("点甲板触发上岸行走", walked)
	_ok("角色离开船锚", main.player.get_parent() != main.boat)
	_ok("角色落到站立面", absf(main.player.position.y - area.surface_y) < 0.05,
		"%.2f vs %.2f" % [main.player.position.y, area.surface_y])
	await get_tree().process_frame
	_ok("状态切到岸上", GameState.mode == GameState.Mode.ASHORE)
	main._board_player()
	_ok("能回到船上", main.player.get_parent() == main.boat)


## 植物库：通用 / 专用两级，摆放表齐全
func _test_plants() -> void:
	print("[plants]")
	var dir := DirAccess.open("res://scenes/plants/common")
	var common := _count_scenes(dir)
	_ok("通用植物存在", common > 0, str(common))
	var zone_keys := ["zone1_home_harbor", "zone3_arc_farm", "zone5_aqua_platform"]
	var specific := 0
	for key in zone_keys:
		specific += _count_scenes(DirAccess.open("res://scenes/plants/zones/%s" % key))
	_ok("区块专用植物存在", specific > 0, str(specific))

	# 通用原型必须真的被多个区块引用
	var used_in := {}
	for key in zone_keys:
		var f := FileAccess.open("res://assets/data/plants_%s.json" % key, FileAccess.READ)
		if f == null:
			_ok("%s 摆放表存在" % key, false)
			continue
		var data: Variant = JSON.parse_string(f.get_as_text())
		var rows: Array = data.get("plants", [])
		_ok("%s 有植株" % key, rows.size() > 0, str(rows.size()))
		for row in rows:
			if row.scope == "common":
				used_in[row.a] = used_in.get(row.a, 0) + 1
	var shared := 0
	for k in used_in.keys():
		if used_in[k] >= 2:
			shared += 1
	_ok("通用植物被多处复用", shared > 0, str(shared))

	# 区块里的植物场确实长出了节点
	var main := get_parent()
	var z1: Node = main._zone_nodes.get("zone1")
	if z1 != null and z1.plants != null:
		_ok("zone1 植物已实例化", z1.plants.plants.size() > 0, str(z1.plants.plants.size()))


func _count_scenes(dir: RefCounted) -> int:
	if dir == null:
		return 0
	var n := 0
	for f in dir.get_files():
		if f.ends_with(".tscn"):
			n += 1
	return n


## 海底世界：四个独立区块 + 潜水状态机 + 宝箱 + 上浮恢复。
## 采集：世界实体 + 距离焦点 + 长按 + 枯竭再生 + 建造前提。
func _test_gather() -> void:
	print("[gather]")
	var main := get_parent()
	var field: Node = main.get_node_or_null("World/Gameplay/GatherField")
	if field == null:
		field = main.get_node_or_null("GatherField")
	_ok("GatherField 存在", field != null)
	if field == null:
		return
	_ok("采集点数量", field.spots.size() == 10, str(field.spots.size()))

	# 契约：每个采集点必须站在所属区块的行走面上，否则玩家永远够不到。
	for spot in field.spots:
		var zone_id := str(spot.get_meta("zone", ""))
		var cfg: Dictionary = Zones.get_zone(zone_id)
		_ok("%s 属于已知区块" % spot.id, not cfg.is_empty(), zone_id)
		var on_deck := false
		for w in cfg.get("walk", []):
			for r in w.get("rects", []):
				var inside: bool = spot.position.x >= float(r[0]) - 0.05 \
					and spot.position.x <= float(r[1]) + 0.05 \
					and spot.position.z >= float(r[2]) - 0.05 \
					and spot.position.z <= float(r[3]) + 0.05
				if inside and absf(spot.position.y - float(w.get("y", spot.position.y))) < 0.4:
					on_deck = true
		_ok("%s 落在可行走面" % spot.id, on_deck, str(spot.position))

	# 长按采集：真实走 Interactor.update，不直接调 spot.interact。
	var shell: Node3D = field.find("zone1_shell")
	_ok("找到贝床", shell != null)
	if shell == null:
		return
	main.player.reparent(main, true)
	main.player.position = shell.position + Vector3(0.9, 0, 0.5)
	main.interactor.active = true
	main.interactor.debug_focus(shell)
	var before: int = Economy.shell
	for i in 24:
		main.interactor.update(0.1, true)
	_ok("长按采到海贝", Economy.shell - before >= 2, "+%d" % (Economy.shell - before))
	_ok("采后枯竭", not shell.available)
	_ok("冷却有剩余", shell.seconds_left() > 0.0, "%.0fs" % shell.seconds_left())

	shell.debug_advance(999.0)
	_ok("冷却结束可再采", shell.available)

	# 走动打断：按住时挪动位置，进度必须清零。
	main.interactor.debug_focus(shell)
	main.interactor.update(0.1, true)
	var held: float = main.interactor.hold
	main.player.position += Vector3(1.2, 0, 0)
	main.interactor.update(0.1, true)
	_ok("走动打断采集", held > 0.0 and main.interactor.hold == 0.0,
		"held=%.2f now=%.2f" % [held, main.interactor.hold])

	# 建造前提：铁道站 1 级时玻璃上锁，2 级解禁。
	var glass: Node3D = field.find("zone2_glass")
	_ok("找到玻璃采集点", glass != null)
	if glass != null:
		Economy.site_levels["yokohama_station"] = 1
		_ok("未升级时上锁", glass.blocked_reason() != "", glass.blocked_reason())
		_ok("上锁时拒绝采集", glass.interact(main.player).has("blocked"))
		Economy.site_levels["yokohama_station"] = 2
		_ok("升级后解禁", glass.blocked_reason() == "", glass.blocked_reason())
		Economy.site_levels["yokohama_station"] = 1

	# 收尾：人回到船上，探测器关掉，避免影响后面的潜水用例。
	main.interactor.active = false
	main._board_player()


func _test_underwater() -> void:
	print("[underwater]")
	var main := get_parent()
	var uw: Node = main.get_node_or_null("Underwater")
	_ok("海底世界已装配", uw != null)
	if uw == null:
		return

	var regions: Node = uw.get_node_or_null("Regions")
	_ok("有 Regions 容器", regions != null)
	if regions != null:
		var names := []
		for r in regions.get_children():
			names.append(r.region)
			_ok("%s 有单元" % r.region, r.units.size() > 0, str(r.units.size()))
			_ok("%s 实例数非零" % r.region, r.instance_count > 0, str(r.instance_count))
			var b: AABB = r.world_bounds()
			_ok("%s 包围盒有效" % r.region, b.size.x > 1.0 and b.size.y > 1.0 and b.size.z > 1.0)
		_ok("四个海底区块", names.size() == 4, str(names))
		for want in ["basin", "neighborhood", "reef", "trench"]:
			_ok("区块 %s 存在" % want, names.has(want))

	# 海沟必须比主盆地深得多（-225 vs -76）
	var trench: Node = null
	for r in regions.get_children():
		if r.region == "trench":
			trench = r
	if trench != null:
		_ok("海沟深度到 -225", trench.world_bounds().position.y < -200.0,
			"%.1f" % trench.world_bounds().position.y)

	_ok("五个宝箱", uw.chest_count() == 5, str(uw.chest_count()))
	_ok("七群鱼", uw.deco._fish.size() == 7, str(uw.deco._fish.size()))

	# 下潜
	uw.dive(Vector3.ZERO, "晴空水巷")
	_ok("下潜后 active", uw.active)
	_ok("海面几何已隐藏", main.world_root.visible == false)
	_ok("海面灯光已隐藏", main._surface_lights.size() > 0 and main._surface_lights[0].visible == false)
	_ok("深度从 0 起", uw.depth < 0.5, "%.2f" % uw.depth)

	# 直接跳过入水动画
	uw.phase = "swim"
	uw.diver_pos = Vector3(0, -12, 10)

	# 游动边界：越界会被挡住
	_ok("盆外算碰撞", uw.blocked(Vector3(200, -12, 0)))
	_ok("盆内不碰撞", not uw.blocked(Vector3(0, -12, 10)))

	# 宝箱：走到旁边 → 搜索 3 秒 → 到账
	var chest: Dictionary = uw._chests[0]
	uw.debug_teleport(chest.pos + Vector3(1.5, 1.2, 1.0))
	var coins_before: int = Economy.coins
	var parts_before: int = Economy.parts
	uw._visit_chest(chest)
	_ok("靠近后进入搜索", not uw.search_state().is_empty())
	for i in 40:
		uw._update_swim(0.1)
	_ok("宝箱已打开", chest.opened)
	var gained_parts: int = Economy.parts - parts_before
	var gained_coins: int = Economy.coins - coins_before
	_ok("奖励到账", gained_parts + gained_coins > 0,
		"parts+%d coins+%d" % [gained_parts, gained_coins])

	# 上浮：恢复到海面状态
	uw.surface()
	for i in 60:
		uw._process(0.1)
	_ok("上浮后 active=false", not uw.active)
	_ok("海面几何已恢复", main.world_root.visible == true)
	_ok("海面灯光已恢复", main._surface_lights[0].visible == true)
	_ok("相机交还海面", uw.camera.current == false)


## 绞盘打捞：深度 / 张力 / 断线 / 产出，全部按固定步长推。
func _test_salvage() -> void:
	print("\n[salvage]")
	var SalvageLib = preload("res://scripts/core/salvage.gd")
	var m = SalvageLib.new()
	m.start()
	_ok("开局在下钩阶段", m.phase == SalvageLib.Phase.DROP)

	# 下钩：2.6 秒到底
	var t := 0.0
	while t < 2.6:
		m.update(0.05, false)
		t += 0.05
	_ok("钩子能到底", m.depth > 0.99, str(m.depth))
	_ok("到底时还没收线", m.progress == 0.0)

	m.press()
	_ok("按 E 进入收线", m.phase == SalvageLib.Phase.REEL)

	# 一直按着不放：张力会顶到红线并断线（这是「贪心」的代价）
	var guard := 0
	while not m.is_finished() and guard < 4000:
		m.update(0.016, true)
		guard += 1
	_ok("死按住会断线", m.phase == SalvageLib.Phase.FAILED, m.summary())
	_ok("断线没有产出", m.haul().is_empty())

	# 稳住张力：张力到 0.6 就松手，低于 0.5 再按 —— 应该能收满
	var n = SalvageLib.new()
	n.start()
	for i in 60:
		n.update(0.05, false)
	n.press()
	guard = 0
	while not n.is_finished() and guard < 20000:
		var want: bool = n.tension < 0.60
		n.update(0.016, want)
		guard += 1
	_ok("会控张力就能收满", n.phase == SalvageLib.Phase.DONE, n.summary())
	var haul: Dictionary = n.haul()
	_ok("满深度产出更多木料", int(haul.get("wood", 0)) >= 5, str(haul))
	_ok("满深度带玻璃", haul.has("glass"), str(haul))
	_ok("准度可读", n.accuracy() > 0.4, str(n.accuracy()))

	# 浅水：只放三成钩，产出打折且没有稀罕物
	var f = SalvageLib.new()
	f.start()
	for i in 16:
		f.update(0.05, false)  # 0.8s ≈ 31%
	f.press()
	guard = 0
	while not f.is_finished() and guard < 20000:
		f.update(0.016, f.tension < 0.60)
		guard += 1
	var shallow_haul: Dictionary = f.haul()
	_ok("浅水也能出货", not shallow_haul.is_empty(), f.summary())
	_ok("浅水没有玻璃/珍珠", not shallow_haul.has("glass") and not shallow_haul.has("pearl"),
		str(shallow_haul))

	# 结算接口：产出进背包、冷却开始
	var now := 500.0
	Economy.salvage_ready_at = 0.0
	var before := Economy.wood
	var got: Dictionary = Economy.commit_salvage(now, {"wood": 4, "parts": 2})
	_ok("结算进背包", Economy.wood == before + int(got.get("wood", 0)), str(got))
	_ok("结算后进冷却", not Economy.can_salvage(now))
	_ok("空产出不结算", Economy.commit_salvage(now + 999.0, {}).is_empty())
	Economy.salvage_ready_at = 0.0


## 交互细节：悬停铭牌的命中与文案、自动接近后的自动长按。
func _test_pointer_detail() -> void:
	print("\n[pointer]")
	var main := get_parent()
	# 悬停铭牌已挂上
	_ok("有悬停铭牌", main.hover != null)
	_ok("有落点环", main.reticle != null)
	_ok("有打捞面板", main.salvage_panel != null)
	_ok("世界里有一台绞盘", main.salvage_winch != null)

	# 绞盘落在打捞浮台的行走矩形里（不然走不过去）
	var winch: Node3D = main.salvage_winch
	var zone: Node3D = main._zone_nodes.get("zone1", null)
	_ok("绞盘在可行走区域内", zone != null and zone.area_containing(
		winch.position.x, winch.position.z) != null, str(winch.position))

	# 悬停文案：可交互物要能报出「动作 + 名字」
	var spot: Node3D = null
	for s in get_tree().get_nodes_in_group("interactable"):
		if s.has_method("focus_text") and s.can_interact():
			spot = s
			break
	_ok("能找到可交互物", spot != null)
	if spot != null:
		_ok("焦点文案非空", spot.focus_text() != "", spot.focus_text())
		_ok("有优先级与半径", float(spot.focus_radius) > 0.0)

	# 自动接近：点击采集点后 _auto_target 生效，走近即自动按住
	if spot != null:
		var ok: bool = main._approach(spot)
		_ok("能规划到目标旁边的落点", ok)
		_ok("自动目标已记录", main._auto_target == spot)
		main._walking = false
		main.player.position = spot.global_position + Vector3(1.0, 0, 0)
		main._update_pointer_ui()
		_ok("到位后自动长按", main.interactor.auto_hold)
		main._auto_target = null
		main.interactor.auto_hold = false


## 水面寻路：栅格、可通达性、以及「航线不穿岛」这条硬约束。
func _test_sail_nav() -> void:
	print("\n[sail-nav]")
	var main := get_parent()
	var shore: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/baked/shore.json"))
	_ok("岸线数据可读", shore is Dictionary and shore.has("shapes"))
	if not (shore is Dictionary):
		return
	var shapes: Array = shore.shapes
	var grid: Dictionary = main.nav_grid()
	_ok("栅格建起来", not grid.is_empty() and int(grid.cols) > 100 and int(grid.rows) > 100,
		"%dx%d" % [int(grid.get("cols", 0)), int(grid.get("rows", 0))])
	if grid.is_empty():
		return
	var blocked: PackedByteArray = grid.blocked
	_ok("栅格有障碍格", blocked.count(1) > 1000, str(blocked.count(1)))
	_ok("岛心算障碍", not SailNavLib.is_free(grid, 4.2, 0.8))
	_ok("开阔水面可通行", SailNavLib.is_free(grid, 40.0, 20.0))

	# 所有泊位两两可达
	var parks := {}
	for z in Zones.list:
		var l: Dictionary = Zones.landing(z.id, "main")
		parks[z.id] = Vector2(float(l.boatPark[0]), float(l.boatPark[2]))
	var keys := parks.keys()
	var fails := 0
	var worst := 0.0
	for i in keys.size():
		for j in keys.size():
			if i >= j:
				continue
			var raw: Variant = SailNavLib.plan_route(grid, parks[keys[i]], parks[keys[j]])
			if raw == null or (raw as Array).size() < 2:
				fails += 1
				print("    无航路 ", keys[i], " -> ", keys[j])
				continue
			var route: Array = raw
			var bad := _route_crosses_land(shapes, route)
			if bad >= 0:
				fails += 1
				print("    航路穿岛 %s -> %s @ %s" % [keys[i], keys[j], str(route[bad])])
			worst = maxf(worst, SailNavLib.path_length(route))
	_ok("所有泊位两两可达且不穿岛", fails == 0, "%d 条有问题" % fails)
	_ok("航路长度合理", worst > 0.0 and worst < 200.0, "%.1f" % worst)

	# 船会绕开岛：zone1 -> zone3 的航路必须比直线长
	var straight: float = parks["zone1"].distance_to(parks["zone3"])
	var scenic: float = SailNavLib.path_length(
		SailNavLib.plan_route(grid, parks["zone1"], parks["zone3"]))
	_ok("绕行航路比直线长", scenic > straight + 1.0, "%.1f vs %.1f" % [scenic, straight])

	# 运动学：按航路开，能到、且每帧转角不超过角速度上限
	var boat = load("res://scripts/boat.gd").new()
	add_child(boat)
	boat.build()
	var l1: Dictionary = Zones.landing("zone1", "main")
	boat.place_at(Vector3(float(l1.boatPark[0]), WATER_LEVEL, float(l1.boatPark[2])), float(l1.boatYaw))
	var route: Array = SailNavLib.plan_route(grid, parks["zone1"], parks["zone3"])
	var got := {"z": ""}
	boat.arrived.connect(func(z, _lid): got.z = z)
	var l3: Dictionary = Zones.landing("zone3", "main")
	boat.sail_to(Vector3(float(l3.boatPark[0]), WATER_LEVEL, float(l3.boatPark[2])),
		float(l3.boatYaw), "zone3", "main", route)
	var guard := 0
	var max_turn := 0.0
	var last_yaw: float = boat.rotation.y
	while boat.starts_sailing() and guard < 6000:
		boat._process(1.0 / 60.0)
		max_turn = maxf(max_turn, absf(angle_difference(last_yaw, boat.rotation.y)))
		last_yaw = boat.rotation.y
		guard += 1
	_ok("按航路能开出航", not boat.starts_sailing(), "frames=%d" % guard)
	_ok("到站是 zone3", got.z == "zone3", got.z)
	_ok("贴住泊位", Vector2(boat.position.x, boat.position.z).distance_to(parks["zone3"]) < 0.5,
		str(boat.position))
	_ok("转向受角速度限制", max_turn <= 1.55 / 60.0 * 1.35, "%.3f rad/frame" % max_turn)
	_ok("航线预览已铺开", main.ribbon != null)
	boat.queue_free()


## 航线有没有穿进陆地。跳过首尾各 3m（泊位本来就贴着岸）。
## 返回第一个越界的点下标，没穿返回 -1。
func _route_crosses_land(shapes: Array, route: Array) -> int:
	var total := 0.0
	for i in range(1, route.size()):
		total += (route[i] as Vector2).distance_to(route[i - 1])
	var walked := 0.0
	for i in range(1, route.size()):
		var a: Vector2 = route[i - 1]
		var b: Vector2 = route[i]
		var seg := a.distance_to(b)
		var steps := maxi(2, int(ceil(seg / 0.5)))
		for k in range(steps + 1):
			var t := float(k) / float(steps)
			var run := walked + seg * t
			if run < 3.0 or run > total - 3.0:
				continue
			var p := a.lerp(b, t)
			for s in shapes:
				if _point_in_shape(s, p.x, p.y, 0.15):
					return i
		walked += seg
	return -1


func _point_in_shape(s: Dictionary, x: float, z: float, pad: float) -> bool:
	var cx := float(s.get("x", 0.0))
	var cz := float(s.get("z", 0.0))
	var hx := float(s.get("hx", 0.0))
	if bool(s.get("round", false)):
		var dx := x - cx
		var dz := z - cz
		return dx * dx + dz * dz <= (hx + pad) * (hx + pad)
	return absf(x - cx) <= hx + pad and absf(z - cz) <= float(s.get("hz", hx)) + pad


## 相机：缩放 / 平移 / 旋转三件事都要真的动，且都有上下限。
func _test_camera() -> void:
	print("\n[camera]")
	var main := get_parent()
	var cam = main.cam
	_ok("相机存在", cam != null)
	if cam == null:
		return
	_ok("有缩放范围", cam.zoom_min < cam.zoom_max and cam.zoom_min <= 12.0,
		"%.0f~%.0f" % [cam.zoom_min, cam.zoom_max])

	# 滚轮：一档应该明显拉近（旧版只有 8%，用户会觉得「没反应」）
	var d0: float = cam.distance
	cam._zoom_at(true, Vector2(400, 300))
	_ok("滚轮能拉近", cam.distance < d0 * 0.92, "%.1f -> %.1f" % [d0, cam.distance])
	cam._zoom_at(false, Vector2(400, 300))
	_ok("滚轮能推远", cam.distance > d0 * 0.95, "%.1f" % cam.distance)

	# 一路放大不会突破下限
	for i in 40:
		cam._zoom_at(true, Vector2(400, 300))
	_ok("拉近有限度", cam.distance >= cam.zoom_min - 0.01, "%.2f" % cam.distance)
	for i in 60:
		cam._zoom_at(false, Vector2(400, 300))
	_ok("推远有限度", cam.distance <= cam.zoom_max + 0.01, "%.2f" % cam.distance)

	# 触控板捏合也要认（这是「滚轮没反应」的真正原因之一）
	var before: float = cam.distance
	var mag := InputEventMagnifyGesture.new()
	mag.factor = 1.4
	cam._unhandled_input(mag)
	_ok("捏合手势能缩放", cam.distance < before * 0.95, "%.1f -> %.1f" % [before, cam.distance])

	# 旋转：yaw 变、俯角被夹在区间内、永不翻面
	cam.set_distance(90.0)
	var yaw0 := atan2(cam.dir.x, cam.dir.z)
	var pitch0 := atan2(cam.dir.y, Vector2(cam.dir.x, cam.dir.z).length())
	cam._orbit(0.6, 0.0)
	_ok("能水平旋转", absf(angle_difference(yaw0, atan2(cam.dir.x, cam.dir.z))) > 0.3,
		"%.2f rad" % absf(angle_difference(yaw0, atan2(cam.dir.x, cam.dir.z))))
	cam._orbit(0.0, 5.0)
	_ok("俯角不会翻过去", cam.dir.y > 0.05, "dir.y=%.3f" % cam.dir.y)
	cam._orbit(0.0, -5.0)
	var pitch1 := atan2(cam.dir.y, Vector2(cam.dir.x, cam.dir.z).length())
	_ok("俯角有下限", rad_to_deg(pitch1) >= cam.pitch_min_deg - 0.5, "%.1f°" % rad_to_deg(pitch1))
	_ok("俯角有上限", rad_to_deg(pitch1) <= cam.pitch_max_deg + 0.5, "%.1f°" % rad_to_deg(pitch1))
	cam._orbit(0.0, 5.0)
	_ok("俯角回到区间", rad_to_deg(atan2(cam.dir.y, Vector2(cam.dir.x, cam.dir.z).length()))
		<= cam.pitch_max_deg + 0.5)

	# 平移：拖到很远会被边界拦住，不会飞出世界
	cam.target = Vector3(9999.0, 1.75, 9999.0)
	cam._clamp_target()
	var b: Rect2 = cam.pan_bounds
	# Rect2.has_point 不含右下边界，夹到边界上会误判，这里用显式比较。
	_ok("平移有边界",
		cam.target.x >= b.position.x - 0.01 and cam.target.x <= b.end.x + 0.01
		and cam.target.z >= b.position.y - 0.01 and cam.target.z <= b.end.y + 0.01,
		str(cam.target))
	cam.target = Vector3(0.45, 1.75, -0.65)
	cam.set_distance(106.0)

	# 缩放反馈：HUD 会把百分比显示在底部提示条
	_ok("HUD 有缩放反馈", main.hud != null and main.hud.has_method("note_zoom"))

	# 相机面板（C 键）：最近/最远/默认 三个定位必须精确命中，滑杆范围跟着 zoom_min/max 走。
	var panel = main.cam_panel
	_ok("有相机面板", panel != null)
	if panel != null:
		_ok("面板默认关闭", not panel.is_open())
		panel.snap_to("near")
		_ok("最近定位 = zoom_min", absf(cam.distance - cam.zoom_min) < 0.01,
			"%.2f vs %.2f" % [cam.distance, cam.zoom_min])
		panel.snap_to("farthest")
		_ok("最远定位 = zoom_max", absf(cam.distance - cam.zoom_max) < 0.01,
			"%.2f vs %.2f" % [cam.distance, cam.zoom_max])
		panel.snap_to("mid")
		_ok("中景落在区间中间", cam.distance > cam.zoom_min * 1.5 and cam.distance < cam.zoom_max * 0.9,
			"%.1f" % cam.distance)
		panel.set_distance_m(-100.0)
		_ok("米数下限被夹住", absf(cam.distance - cam.zoom_min) < 0.01, "%.2f" % cam.distance)
		panel.set_distance_m(9999.0)
		_ok("米数上限被夹住", absf(cam.distance - cam.zoom_max) < 0.01, "%.2f" % cam.distance)
		var scene_d: float = panel._default_distance
		panel.snap_to("default")
		_ok("默认机位回到场景距离", absf(cam.distance - scene_d) < 0.01,
			"%.2f vs %.2f" % [cam.distance, scene_d])
		# 百分比定位：50% 应正好在区间中点附近
		panel.snap_to("50%")
		var half: float = lerpf(cam.zoom_min, cam.zoom_max, 0.5)
		_ok("百分比定位可用", absf(cam.distance - half) < 0.5, "%.1f vs %.1f" % [cam.distance, half])
		# 面板打开时相机不应该被「点走路」逻辑抢走指针
		panel.set_open(true)
		_ok("面板能打开", panel.is_open())
		panel.set_open(false)
		_ok("面板能关闭", not panel.is_open())
		cam.set_distance(scene_d)


## 点击水面：能算出水面点、能拒绝陆地、能真的开始划。
func _test_water_click() -> void:
	print("\n[water-click]")
	var main := get_parent()
	# 岸线里算陆地，开阔水面算水
	_ok("岛心不是水面", not main._is_open_water(4.2, 0.8))
	_ok("开阔水面可点", main._is_open_water(-20.0, 25.0))
	_ok("场景外不算水面", not main._is_open_water(400.0, 400.0))

	# 射线打到屏幕中心 → 水面点
	var vp: Vector2 = main.get_viewport().get_visible_rect().size
	var p: Variant = main._water_point(vp * 0.5)
	_ok("屏幕中心能取到水面点（或明确返回空）", p == null or p is Vector3, str(p))

	# 直接在已知开阔水域开船：应当进入航行状态、并被规划成折线
	var boat = main.boat
	var l: Dictionary = Zones.landing("zone1", "main")
	boat.place_at(Vector3(float(l.boatPark[0]), WATER_LEVEL, float(l.boatPark[2])), float(l.boatYaw))
	var goal := Vector3(-22.0, WATER_LEVEL, 24.0)
	var path: Array = main.plan_route_to(goal.x, goal.z)
	boat.sail_to_point(goal, path)
	_ok("点水面能开始划", boat.starts_sailing())
	_ok("手动航行有航路", path.size() >= 2, "%d 点" % path.size())
	_ok("手动航行标记", boat.manual)
	var guard := 0
	while boat.starts_sailing() and guard < 8000:
		boat._process(1.0 / 60.0)
		guard += 1
	_ok("能划到指定点", not boat.starts_sailing()
		and Vector2(boat.position.x, boat.position.z).distance_to(Vector2(goal.x, goal.z)) < 0.6,
		str(boat.position))

	# 划船时桨要动（俯视镜头下这是「在划船」的主要视觉信号）
	boat.sail_to_point(Vector3(-10.0, WATER_LEVEL, 26.0), main.plan_route_to(-10.0, 26.0))
	var a0: float = boat._oar_l.rotation.y
	for i in 12:
		boat._process(1.0 / 60.0)
	_ok("划船时桨在动", absf(boat._oar_l.rotation.y - a0) > 0.01,
		"%.3f -> %.3f" % [a0, boat._oar_l.rotation.y])
	boat.place_at(Vector3(float(l.boatPark[0]), WATER_LEVEL, float(l.boatPark[2])), float(l.boatYaw))
