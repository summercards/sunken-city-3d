extends VBoxContainer
## P 键调试面板的「测试」页（SEA-TOOL）。
##
## 这是**测试用**工具，不是玩法入口。它守三条线：
##
##   1. 只调既有所有者已经公开的接口 —— 加物品、改时刻、换天气、回体力。
##      不新增状态、不写存档字段、不改任何规则或资源文件。
##   2. 所有外部能力都由 `bind()` 注入 Callable。本文件不认识 Economy /
##      Main / HUD：拿不到端口就整页禁用并写明原因，不静默失败。
##   3. 自绘紧凑皮肤并打 `island_label` 标记，让 Cozy 主题整棵跳过。
##      不跳的话每个按钮会被顶到 44 px 高、字号 18 —— 五组控件能把面板撑出屏幕。
##
## 注入端口（全部可选，缺哪项就禁用对应的那一组）：
##
##   catalog()               -> Array[{id, label}]  可加的物品，含货币
##   count(id)               -> int
##   give(amounts)           -> void               Dictionary{id: 数量}
##   clock()                 -> {day, hour, text}
##   set_time(day, seconds)  -> void
##   weather()               -> String
##   set_weather(id)         -> bool
##   energy()                -> {current, maximum}
##   refill_energy()         -> void

const Slots = preload("res://src/rendering/daylight_slots.gd")
const UiFontLib = preload("res://src/ui/ui_font.gd")

## 点一次加多少。10 够把「差一点」的建造或升级顶过去，又不至于一按就撑爆背包。
const STEP := 10
## 右键的倍数。材料一格堆 20–40，×10 刚好一次给满。
const STEP_BIG := 10
## 资源格子的列数。窗口里面板实际宽 700，四列每格 155 px；窄屏回落到
## 352 时每格仍有 78 px，「木板 12」放得下。
const COLUMNS := 4
## 时段按钮的列数。八段排两行 —— 一行八格时每格 68 px，「黎明前」会被截断。
const SLOT_COLUMNS := 4

const ROW_H := 24
## 面板是常开的，物品数量会被采集/交易改掉，所以定时回读一次；
## 0.3 秒比人手点一下快得多，又不用每帧去查 9 个数字。
const REFRESH_SECONDS := 0.3

## 奶油配色跟侧栏一致：这一页贴在同一张淡紫纸卡上，
## 深色调试皮肤会变成一块压不住的黑洞。
const PILL := Color("#eee9d5")
const PILL_OFF := Color("#e7e1cc")
const INK := Color("#625744")
const DIM := Color("#9a8e76")
const GOLD := Color("#f7d879")

var _ports := {}
var _font: Font
## [{id, label}]。货币也在里面 —— 加的时候一并处理，显示时才分开放。
var _catalog: Array = []
var _labels := {}

var _coins_label: Label
var _items_box: GridContainer
var _item_buttons := {}
var _time_label: Label
var _weather_label: Label
var _weather_buttons := {}
var _energy_label: Label
var _hint: Label
var _refresh_left := 0.0


func _ready() -> void:
	_font = UiFontLib.make(PackedStringArray(["Hiragino Sans GB", "PingFang SC", "Heiti SC", "Microsoft YaHei", "Helvetica Neue"]))
	# 见文件头第 3 条：整棵子树交给自己排，不让 Cozy 主题放大。
	set_meta("island_label", true)
	add_theme_constant_override("separation", 6)
	_build()
	if not _ports.is_empty() and _items_box != null:
		_bind_ports()


## 主场景把「真的改游戏」的那几个入口注进来。重复调用会重建资源格子，
## 所以换场景/重连端口不需要重建整页。
func bind(ports: Dictionary) -> void:
	_ports = ports
	if is_inside_tree() and _items_box != null:
		_bind_ports()


func _bind_ports() -> void:
	var catalog := _port("catalog")
	_catalog = catalog.call() if catalog.is_valid() else []
	_labels.clear()
	for row in _catalog:
		var id := str(row.get("id", ""))
		if id != "":
			_labels[id] = str(row.get("label", id))
	_rebuild_items()
	refresh()


# ---- 布局 -------------------------------------------------------------------

func _build() -> void:
	_build_currency()
	_build_items()
	_build_time()
	_build_weather()
	_build_energy()

	add_child(_separator())
	_hint = _text("改动只作用于当前这一局：不写资源文件，也不加存档字段。", 9, DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint)


## 货币单独一行。它在 `items.json` 里 `stack = 0`、不占背包格，
## 混进材料网格会让人以为它也是一格材料。
func _build_currency() -> void:
	var line := _row("货币")
	_coins_label = _text("0", 12, INK)
	_coins_label.custom_minimum_size = Vector2(64, 0)
	_coins_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(_coins_label)
	for step in [10, 100, 1000]:
		var amount := int(step)
		line.add_child(_pill("+" + str(amount),
			func() -> void: add_item("coins", amount), "瓶盖 +%d" % amount))
	# 把右半边空出来：三个按钮贴左，视线才不会跑到屏幕另一边。
	var pad := Control.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(pad)


func _build_items() -> void:
	var line := _row("资源")
	line.add_child(_pill("全部 +10", func() -> void: add_all(STEP), "每种物品各 +10"))
	line.add_child(_pill("全部 +50", func() -> void: add_all(STEP * 5), "每种物品各 +50"))
	var pad := Control.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(pad)

	# 格子内容在 `_bind_ports` 里按物品表填：表里加了新物品，这一页第二天就有了。
	_items_box = GridContainer.new()
	_items_box.columns = COLUMNS
	_items_box.add_theme_constant_override("h_separation", 4)
	_items_box.add_theme_constant_override("v_separation", 4)
	add_child(_items_box)


func _build_time() -> void:
	var line := _row("时间")
	_time_label = _text("—", 12, INK)
	_time_label.custom_minimum_size = Vector2(150, 0)
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(_time_label)
	line.add_child(_pill("−1 时", func() -> void: shift_hours(-1), "往回 1 小时"))
	line.add_child(_pill("+1 时", func() -> void: shift_hours(1), "往后 1 小时"))
	line.add_child(_pill("−1 天", func() -> void: shift_days(-1), "往前 1 天"))
	line.add_child(_pill("+1 天", func() -> void: shift_days(1), "往后 1 天"))
	var pad := Control.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(pad)

	# 八个时段直接跳。时段表的时刻归 `daylight_slots.gd`，这里只按钮，
	# 不另抄一份「几点算清晨」。
	#
	# 排 4 列两行，不排一行八格：700 px 面板里一行八格每格只剩 60 px，
	# 「黎明前」放不下会被截断 —— 真实渲染核对时最后一个按钮直接压出纸边。
	var tag := _text("时段", 10, DIM)
	# 组名单独一行、和网格同宽：塞进 `_row()` 的横排里会被挤成一条窄带，
	# 而这一组是两行网格，横排的基线也对不齐。
	add_child(tag)
	var grid := GridContainer.new()
	grid.columns = SLOT_COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	add_child(grid)
	for slot in Slots.SLOTS:
		var hour := float(slot.hour)
		var b := _pill(String(slot.label), func() -> void: jump_to_hour(hour),
			"跳到 %02d:00" % int(hour))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)


## 天气按钮改的是**游戏真实天气**（WeatherService），不是面板的预览上下文 ——
## 侧栏那三个按钮属于调色预览，两者别混。
##
## 当前值是**按钮前面的小字**，不是行尾的右对齐标签：行尾那个在 700 px 面板里
## 会被三个 `SIZE_EXPAND_FILL` 按钮挤出纸边缘，字被切一半（渲染核对时抓到过）。
func _build_weather() -> void:
	var line := _row("天气")
	_weather_label = _text("当前 —", 9, DIM)
	_weather_label.custom_minimum_size = Vector2(56, 0)
	_weather_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(_weather_label)
	for id in Slots.WEATHER_ORDER:
		var kind := String(id)
		var b := _pill(String(Slots.WEATHER_LABELS.get(kind, kind)),
			func() -> void: set_weather(kind),
			"把游戏天气切成「%s」" % String(Slots.WEATHER_LABELS.get(kind, kind)))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_weather_buttons[kind] = b
		line.add_child(b)


func _build_energy() -> void:
	var line := _row("体力")
	_energy_label = _text("—", 12, INK)
	_energy_label.custom_minimum_size = Vector2(90, 0)
	_energy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(_energy_label)
	line.add_child(_pill("回满", func() -> void: refill_energy(), "EnergyModel.refill()"))
	var pad := Control.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(pad)


func _row(title: String) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 5)
	add_child(line)
	var tag := _text(title, 10, DIM)
	tag.custom_minimum_size = Vector2(40, 0)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(tag)
	return line


func _rebuild_items() -> void:
	if _items_box == null:
		return
	for child in _items_box.get_children():
		_items_box.remove_child(child)
		child.queue_free()
	_item_buttons.clear()
	for row in _catalog:
		var id := str(row.get("id", ""))
		# 货币已经在上面单独一行，这里跳过，免得同一件事两个入口。
		if id == "" or id == "coins":
			continue
		var b := _item_button(id)
		_items_box.add_child(b)
		_item_buttons[id] = b


## 资源格子：左键 +10、右键 +100。两个都走同一个 `add_item`，
## 只是步长不同 —— 测试时「差一格」和「补满一格」是两种需求。
func _item_button(id: String) -> Button:
	var b := _pill("", func() -> void: add_item(id, STEP),
		"点一次 +%d，右键 +%d" % [STEP, STEP * STEP_BIG])
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_RIGHT:
			return
		add_item(id, STEP * STEP_BIG)
		accept_event())
	return b


# ---- 读状态 -----------------------------------------------------------------

func refresh() -> void:
	if _coins_label == null:
		return
	var wired := _port("give").is_valid()
	var count := _port("count")
	if count.is_valid():
		_coins_label.text = str(int(count.call("coins")))
		for id in _item_buttons.keys():
			(_item_buttons[id] as Button).text = "%s %d" % [
				String(_labels.get(id, id)), int(count.call(id))]
	else:
		_coins_label.text = "未接线"
	for id in _item_buttons.keys():
		(_item_buttons[id] as Button).disabled = not wired

	var clock := _port("clock")
	if _time_label != null:
		_time_label.text = String(clock.call().get("text", "—")) if clock.is_valid() else "未接线"

	var weather := _port("weather")
	if weather.is_valid():
		var kind := String(weather.call())
		_weather_label.text = "当前 " + String(Slots.WEATHER_LABELS.get(kind, kind))
		for id in _weather_buttons.keys():
			_style_pill(_weather_buttons[id] as Button, String(id) == kind)
	elif _weather_label != null:
		_weather_label.text = "未接线"

	var energy := _port("energy")
	if _energy_label != null:
		if energy.is_valid():
			var e: Dictionary = energy.call()
			_energy_label.text = "%d / %d" % [int(e.get("current", 0)), int(e.get("maximum", 0))]
		else:
			_energy_label.text = "未接线"

	if not wired and _hint != null:
		_hint.text = "未接线：主场景没有注入测试端口，这一页只读。"


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH_SECONDS
	refresh()


# ---- 动作 -------------------------------------------------------------------
#
# 这四个是页面全部「会改东西」的出口，也是验收脚本走的同一条路。
# 每个都先取端口再动手：缺端口时什么都不发生，不会写出半个状态。

func add_item(id: String, amount: int) -> void:
	var give := _port("give")
	if not give.is_valid() or id == "" or amount <= 0:
		return
	give.call({id: amount})
	_note("已加 %s +%d" % [String(_labels.get(id, id)), amount])
	refresh()


func add_all(amount: int) -> void:
	var give := _port("give")
	if not give.is_valid() or amount <= 0 or _catalog.is_empty():
		return
	var amounts := {}
	for row in _catalog:
		var id := str(row.get("id", ""))
		if id != "":
			amounts[id] = amount
	give.call(amounts)
	_note("已给 %d 种物品各 +%d" % [amounts.size(), amount])
	refresh()


func shift_hours(hours: float) -> void:
	_shift(0, hours * 3600.0)


func shift_days(days: int) -> void:
	_shift(days, 0.0)


## 跳到某个时刻，日期不动。时段按钮用它 —— 测「夕阳长什么样」不该顺手过一天。
func jump_to_hour(hour: float) -> void:
	var clock := _port("clock")
	var set_time := _port("set_time")
	if not clock.is_valid() or not set_time.is_valid():
		return
	var now: Dictionary = clock.call()
	set_time.call(int(now.get("day", 1)), fposmod(hour, 24.0) * 3600.0)
	_note("已跳到 %02d:00" % int(fposmod(hour, 24.0)))
	refresh()


func set_weather(kind: String) -> void:
	var apply := _port("set_weather")
	if not apply.is_valid():
		return
	if not bool(apply.call(kind)):
		_note("天气切换失败：%s" % kind)
		return
	_note("天气已切成「%s」" % String(Slots.WEATHER_LABELS.get(kind, kind)))
	refresh()


func refill_energy() -> void:
	var fill := _port("refill_energy")
	if not fill.is_valid():
		return
	fill.call()
	_note("体力已回满")
	refresh()


## 把「天数 + 秒数」叠在现在这一刻上，跨午夜时把天数带过去。
## 往回跨到第 0 天时停在 1 日 —— 存档契约里 day >= 1，测试工具不该造出非法档。
func _shift(days: int, seconds: float) -> void:
	var clock := _port("clock")
	var set_time := _port("set_time")
	if not clock.is_valid() or not set_time.is_valid():
		return
	var now: Dictionary = clock.call()
	var day := int(now.get("day", 1)) + days
	var total := float(now.get("hour", 0.0)) * 3600.0 + seconds
	while total < 0.0:
		total += 86400.0
		day -= 1
	while total >= 86400.0:
		total -= 86400.0
		day += 1
	set_time.call(maxi(1, day), total)
	_note("时间已调到 " + String(clock.call().get("text", "—")))
	refresh()


# ---- 小工具 -----------------------------------------------------------------

func _port(name: String) -> Callable:
	var cb: Variant = _ports.get(name)
	if cb is Callable and (cb as Callable).is_valid():
		return cb as Callable
	return Callable()


func _note(text: String) -> void:
	if _hint != null:
		_hint.text = text


func _text(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _pill(text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 11)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, ROW_H)
	_style_pill(b, false)
	if tip != "":
		b.tooltip_text = tip
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## `active` 只给天气按钮用：它要显示「现在真的是哪一种」。
func _style_pill(b: Button, active: bool) -> void:
	b.add_theme_stylebox_override("normal", _box(GOLD if active else PILL))
	b.add_theme_stylebox_override("hover", _box(GOLD.lightened(0.16)))
	b.add_theme_stylebox_override("pressed", _box(GOLD.darkened(0.06)))
	b.add_theme_stylebox_override("disabled", _box(PILL_OFF))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, INK)
	b.add_theme_color_override("font_disabled_color", DIM)


func _box(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(11)
	s.content_margin_left = 7
	s.content_margin_right = 7
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	return s


func _separator() -> Control:
	var line := ColorRect.new()
	line.color = Color(0.38, 0.33, 0.25, 0.18)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line
