extends Button
const Art = preload("res://src/ui/illustrated_icons.gd")
const Cozy = preload("res://src/ui/cozy_ui.gd")
var kind := "hand"
var item_icon := ""
## 圆下方的小胶囊文字（选种子时是「生菜 ×3」）。空串不画。
## 种子图标在 76px 的圆里只有 45px，生菜/番茄/南瓜几乎分不出，
## 名字与剩余数量必须给出来，否则二级菜单等于让玩家猜。
var caption := ""
var available := true
var selected := false
var motion: Tween
var entrance: Tween

func _ready() -> void:
	set_meta("cozy_skip",true)
	size = Vector2(76,76)
	custom_minimum_size = size
	pivot_offset = size/2
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal","hover","pressed","focus","disabled"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
	mouse_entered.connect(func(): _select(true))
	mouse_exited.connect(func(): _select(false))
	focus_entered.connect(func(): _select(true))
	focus_exited.connect(func(): _select(false))

func _select(on: bool) -> void:
	selected = on
	queue_redraw()
	if motion: motion.kill()
	if not Cozy.motion_enabled: return
	motion = create_tween()
	motion.tween_property(self,"scale",Vector2.ONE*(1.09 if on else 1.0),0.12).set_trans(Tween.TRANS_SINE)

func _draw() -> void:
	var r := size.x/2
	draw_circle(Vector2(r,r+4),r,Color(0.03,0.16,0.18,0.18),true,-1,true)
	draw_circle(Vector2(r,r),r,Color("#e6c36e") if selected else (Color("#438f83") if available else Color("#90a6a0")),true,-1,true)
	draw_arc(Vector2(r,r),r-2,0,TAU,64,Color("#fff9e7"),2,true)
	var icon: Texture2D = Art.texture(item_icon) if item_icon!="" else Art.texture(kind,true)
	if icon: draw_texture_rect(icon,Rect2(size*0.20,size*0.60),false,Color.WHITE)
	if caption != "": _draw_caption()

## 圆下方的奶油胶囊。位置在圆外，`cluster` 不裁剪，所以不会被 76px 的矩形切掉。
func _draw_caption() -> void:
	var font := Cozy.world_font()
	var font_size := 20
	var text_size := font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	var box := Rect2(Vector2(size.x*0.5-text_size.x*0.5-11.0,size.y-2.0),
		Vector2(text_size.x+22.0,font_size+13.0))
	draw_style_box(Cozy.surface(Color(1.0,0.976,0.91,0.97),12),box)
	draw_string(font,Vector2(box.position.x+11.0,box.position.y+font_size+2.0),
		caption,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Cozy.INK)
