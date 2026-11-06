extends Control
## 建筑界面只投影状态和发送动作，不持有布局或材料。
const Book = preload("res://src/building/ui/building_book.gd")
const Demolition = preload("res://src/building/ui/demolition_tool.gd")
signal action_requested(action: String)
var inventory_query: Callable
var book: Control
var demolition: Control
var guide: Panel
var guide_title: Label
var guide_back: Button
var hint: Label
var buttons: Dictionary = {}
var _state_hint := ""
var enabled := false
const TOOLBAR_SIZE := Vector2(1100,112)

func _ready() -> void:
	set_meta("cozy_skip",true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	book=Book.new();book.inventory_query=inventory_query;add_child(book);book.hide()
	book.selected.connect(func(kind: String): action_requested.emit(kind))
	book.closed.connect(func(): action_requested.emit("exit"))
	guide=Panel.new();guide.name="BuildingToolbar";guide.mouse_filter=Control.MOUSE_FILTER_STOP
	var paper:=StyleBoxFlat.new();paper.bg_color=Color("#f4ecd7");paper.set_corner_radius_all(20)
	paper.set_border_width_all(2);paper.border_color=Color("#b49a70")
	paper.shadow_color=Color(0.20,0.15,0.09,0.2);paper.shadow_size=6;paper.shadow_offset=Vector2(0,4)
	guide.add_theme_stylebox_override("panel",paper);add_child(guide)
	guide_title=book._label("家园营造",Vector2(20,12),24,guide)
	var actions: Array[String]=["book","move","remove","level","auto","snap","rotate","exit"]
	var labels: Array[String]=["建造手册","搬移","拆除","高度","自动","吸附","旋转","退出"]
	for i in actions.size():
		var action: String=actions[i]
		var button: Button=book._button(labels[i],Vector2(18+i*134,53),Vector2(128,38),guide)
		button.pressed.connect(func(): action_requested.emit(action));buttons[action]=button
	guide_back=buttons.book
	hint=book._label("",Vector2(20,92),18,guide);hint.size=Vector2(1060,28)
	hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;hint.hide()
	demolition=Demolition.new();add_child(demolition)
	# 保留旧锤子接口，但它现在只住在建筑工具栏的“拆除”槽中。
	demolition.launcher.reparent(guide,false)
	demolition.launcher.position=buttons.remove.position+Vector2(0,-4)
	demolition.launcher.scale=Vector2.ONE*0.62
	buttons.remove.text="    拆除"
	buttons.remove.tooltip_text="拆除 Delete · 选择物件后确认，默认保留"
	demolition.requested.connect(func(): action_requested.emit("remove"))
	set_state({"active":false})

func set_state(state: Dictionary) -> void:
	enabled=bool(state.get("active",false))
	if guide==null: return
	guide.visible=enabled
	var book_open:=bool(state.get("book_open",false))
	book.visible=enabled and book_open
	demolition.set_launcher_visible(enabled)
	if not enabled: return
	guide_title.text=str(state.get("title","家园营造"))+"  ·  高度 %.6f 米"%float(state.get("height",0.0))
	buttons.book.text="建造手册" if book_open else "返回手册"
	buttons.auto.text="自动 开" if not bool(state.get("manual_level",false)) else "自动 H"
	buttons.snap.text="吸附 开" if bool(state.get("snap_assist",true)) else "吸附 关"
	buttons.rotate.disabled=str(state.get("recipe","")) in ["","remove"]
	for action in ["book","move","remove"]:
		var selected: bool=book.visible if action=="book" else str(state.get("recipe",""))==action
		buttons[action].modulate=Color("#e5bd70") if selected else Color.WHITE
	_state_hint=str(state.get("hint",""));hint.text=_state_hint;hint.visible=_state_hint!=""
	layout(get_viewport().get_visible_rect().size)

func layout(extent: Vector2) -> void:
	if guide==null: return
	var fit:=minf(1.0,(extent.x-32.0)/TOOLBAR_SIZE.x)
	guide.size=TOOLBAR_SIZE;guide.scale=Vector2.ONE*fit
	guide.position=Vector2((extent.x-TOOLBAR_SIZE.x*fit)/2.0,extent.y-TOOLBAR_SIZE.y*fit-16)
	var top:=16.0
	var book_fit:=minf(1.0,minf((extent.x-48)/book.size.x,(guide.position.y-top-16)/book.size.y))
	book.scale=Vector2.ONE*book_fit
	book.position=Vector2((extent.x-book.size.x*book_fit)/2.0,top+(guide.position.y-top-16-book.size.y*book_fit)/2.0)
	demolition._layout()

func is_ui_point(point: Vector2) -> bool:
	return enabled and (book.visible or guide.get_global_rect().has_point(point) or demolition.is_ui_point(point))

func _exit_tree() -> void:
	if demolition!=null: demolition.set_active(false)
