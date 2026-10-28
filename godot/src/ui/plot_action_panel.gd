extends RefCounted
## One plot, inventory queries and explicit commands; never owns crop state.
const Rows = preload("res://src/ui/home_loop_panel.gd")

static func build(body: VBoxContainer, farm: Node, inventory: RefCounted, plot_id: String, perform: Callable) -> void:
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = farm.status_text(plot_id)
	body.add_child(status)
	match farm.phase(plot_id):
		"empty":
			status.text = "选择背包里的种子 · 点击播种\n每天浇水，3个早晨后成熟；缺水只停长。"
			var found := false
			for key in farm.crop_definitions():
				var crop: Dictionary = farm.crop_def(key)
				var id := str(key)
				var count: int = inventory.count(str(crop.seed))
				if count <= 0: continue
				found = true
				Rows.row(body,"%s种子 ×%d" % [crop.name,count],"种植",func(): perform.call("plant",id))
				var row: HBoxContainer = body.get_child(body.get_child_count()-1)
				var seed := preload("res://src/ui/ac_icon.gd").new()
				seed.pocket = true
				seed.kind = str(crop.seed)
				seed.font = preload("res://src/ui/ui_font.gd").embedded()
				seed.tooltip_text = "种植"+str(crop.name)
				seed.set_meta("seed_choice",id)
				row.add_child(seed)
				row.move_child(seed,0)
				seed.pressed.connect(func(): perform.call("plant",id))
			if not found: status.text += "\n背包里没有种子。可从仓库取出，或到商店购买。"
		"growing":
			Rows.row(body,"水壶 %d / 12 · 浇过水的土会变深" % farm.watering_can,"浇水",func(): perform.call("water",""),farm.is_dry(plot_id) and farm.watering_can>0)
			if farm.watering_can<=0:
				Rows.row(body,"免费补满淡水后，再选择浇水","补水",func(): perform.call("refill",""))
		"ready":
			Rows.row(body,"成熟了，收获会放进背包","收获",func(): perform.call("harvest",""))
