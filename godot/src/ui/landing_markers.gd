extends CanvasLayer
var zones: Node
## 每个上岸点的锚标（对齐网页版 gameplay.js 里的 .landing-marker）。
##
## 网页版把图标做成 DOM 元素，每帧用相机投影算屏幕坐标；这里用一个 Control
## 自绘全部图标，保证永远画在最上层，也不会被建筑挡住。

const Cozy = preload("res://src/ui/cozy_ui.gd")

const WATER_LEVEL := 1.12
const ICON_MIN := 30.0
const ICON_MAX := 44.0
const VISIBLE_RANGE := 190.0
## 名称字号走 `Cozy.world_text_size`，跟其它世界浮层字同一套倍数。
## 原来是 ThemeDB.fallback_font + 11px + 4px 描边：字体不是打包的那一份圆体，
## 描边又把笔画之间啃掉，于是又小又"沟"。现在换成打包圆体、放大、不描边。
const NAME_STEP := Cozy.WORLD_TEXT_LANDING

var items: Array = []
var camera: Camera3D
var current_zone := "zone1"
var _tex: Texture2D
var _font: Font
var _canvas: Control


func build(cam: Camera3D) -> void:
	camera = cam
	layer = 8
	_font = Cozy.world_font()
	_tex = _make_icon()
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)

	for z in zones.list:
		for l in z.get("landings", []):
			var p: Array = l.dockEdge
			items.append({
				"zone": z.id,
				"landing": l.id,
				"name": str(l.get("name", z.name)),
				"world": Vector3(p[0], float(p[1]) + 0.55, p[2]),
				"screen": Vector2.ZERO,
				"size": ICON_MAX,
				"visible": false
			})


func _make_icon() -> Texture2D:
	var s := 160
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(s * 0.5, s * 0.5)
	var navy := Color(0.043, 0.165, 0.271, 1.0)
	var ring := Color(0.30, 0.95, 0.88, 1.0)
	var fill := Color(0.99, 1.0, 1.0, 1.0)
	var ink := Color(0.043, 0.176, 0.29, 1.0)

	for y in s:
		for x in s:
			var d := Vector2(x - c.x, y - c.y).length()
			if d <= 74.0:
				# 深蓝外圈渐变，保证落在浅色建筑上也读得出来
				var a: float = (1.0 - clamp((d - 52.0) / 22.0, 0.0, 1.0)) * 0.30
				img.set_pixel(x, y, Color(navy.r, navy.g, navy.b, a))
			if d <= 52.0:
				img.set_pixel(x, y, navy)
			elif d <= 62.0:
				var b: float = clamp((62.0 - d) / 3.0, 0.0, 1.0)
				img.set_pixel(x, y, Color(ring.r, ring.g, ring.b, b))
			if d <= 50.0:
				img.set_pixel(x, y, fill)

	# 中央向上箭头
	for y in range(58, 106):
		for x in range(76, 84):
			img.set_pixel(x, y, ink)
	for i in range(20):
		for t in range(6):
			img.set_pixel(80 - i, 66 - i + t, ink)
			img.set_pixel(80 + i, 66 - i + t, ink)

	return ImageTexture.create_from_image(img)


func _process(_delta: float) -> void:
	if camera == null:
		return
	var vp := get_viewport().get_visible_rect().size
	_canvas.size = vp
	for it in items:
		var world: Vector3 = it.world
		it.visible = false
		if camera.is_position_behind(world):
			continue
		var dist: float = camera.global_position.distance_to(world)
		if dist > VISIBLE_RANGE:
			continue
		var sp: Vector2 = camera.unproject_position(world)
		if sp.x < -60 or sp.y < -60 or sp.x > vp.x + 60 or sp.y > vp.y + 60:
			continue
		it.screen = sp
		it.size = clamp(
			lerp(ICON_MAX, ICON_MIN, clamp((dist - 24.0) / 130.0, 0.0, 1.0)),
			ICON_MIN, ICON_MAX
		)
		it.visible = true
	_canvas.queue_redraw()


func _on_draw() -> void:
	for it in items:
		if not it.visible:
			continue
		var s: float = it.size
		var rect := Rect2(it.screen - Vector2(s * 0.5, s * 0.5), Vector2(s, s))
		var active: bool = it.zone == current_zone
		var col := Color(1, 1, 1, 1.0) if active else Color(0.95, 0.98, 1.0, 0.72)
		_canvas.draw_texture_rect(_tex, rect, false, col)
		if active:
			var text: String = it.name
			var font_size := Cozy.world_text_size(NAME_STEP)
			var w: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var pos := Vector2(it.screen.x - w * 0.5, it.screen.y + s * 0.5 + font_size)
			# 不描边：`draw_string_outline` 会在圆体笔画外侧勾一圈硬边，
			# 把字之间的小空隙糊掉，看起来又细又沟。可读性交给字号。
			_canvas.draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
				Color(1, 1, 1, 0.98))


## 屏幕命中：图标中心 26px 半径。
func pick(screen_pos: Vector2, radius: float = 26.0) -> Dictionary:
	var best := {}
	var best_d := radius
	for it in items:
		if not it.visible:
			continue
		var d: float = it.screen.distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = it
	return best


func set_highlight(zone_id: String) -> void:
	current_zone = zone_id
