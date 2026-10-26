extends Control
## Reference-shaped stationery. The owner remains responsible for input/layout.
##
## 圆角不吃内容 —— 这是硬约束。
##
## 旧轮廓把圆角写成面板宽高的百分比（横向 0.10W、纵向 0.10H），于是面板越宽，
## 圆角按比例越大：980 px 宽的订单板圆角横吃 98 px，而内容边距只有 32 px，
## 「码头来信」四个字正好落在被吃掉的那块里，看起来像从纸边探出去。
## 断言都查「控件在不在面板矩形里」当然全过 —— 面板矩形比纸的轮廓大。
##
## 现在圆角由属主面板自己的内容边距反推（`_corner_radius()`），并且再加一圈
## 外扩 `outset`：纸比面板略大，字一个像素都不用挪，纸自己长大。
var tint := Color("#fff9e8")
var accent := Color("#68b6a2")
var dialogue := false
var stitched := false
var phone := false
var shadow_blur := 10.0
var shadow_y := 5.0
## 纸在四个方向上比属主面板多出来的像素。内容位置不变，纸变大。
var outset := 0.0
## 圆角与内容框之间至少留这么宽，留白再多一点，字才不会贴到弧线上。
const CORNER_GAP := 8.0
## 无论面板多大，圆角都不小于这个值，免得小卡片变成直角。
const CORNER_MIN := 14.0
var _cached_size := Vector2.ZERO
var _cached_radius := Vector2.ZERO
var _contour := PackedVector2Array()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	resized.connect(queue_redraw)

func _process(_delta: float) -> void:
	if not has_meta("paper_owner"): return
	var owner_panel: Control=get_meta("paper_owner")
	if not is_instance_valid(owner_panel): return
	var grow := Vector2(outset,outset)
	position=owner_panel.position-grow;size=owner_panel.size+grow*2
	scale=owner_panel.scale;pivot_offset=owner_panel.pivot_offset+grow
	visible=owner_panel.visible;modulate=owner_panel.modulate

## 属主面板的内容边距 —— 纸的圆角最多只能吃到这里。
func _content_margin() -> Vector2:
	var pad := Vector2(32,30)
	if has_meta("paper_owner"):
		var owner: Variant = get_meta("paper_owner")
		if is_instance_valid(owner) and owner is Control:
			var box: StyleBox = (owner as Control).get_theme_stylebox("panel")
			if box != null:
				pad = Vector2(maxf(box.content_margin_left,box.content_margin_right),
					maxf(box.content_margin_top,box.content_margin_bottom))
	return pad

## 圆角半径：既不长到吃字，也不小到失去纸的圆润感。
##
## 上限 =（内容边距 + 纸的外扩）− `CORNER_GAP`。这一项就是本文件开头的硬约束：
## 内容框永远落在纸的直边区里，跟面板被拉多宽多高无关。
func _corner_radius() -> Vector2:
	var room := _content_margin()+Vector2(outset,outset)-Vector2(CORNER_GAP,CORNER_GAP)
	var rx := clampf(size.x*0.10,0.0,maxf(room.x,0.0))
	var ry := clampf(size.y*0.10,0.0,maxf(room.y,0.0))
	rx = maxf(rx,minf(CORNER_MIN,maxf(room.x,0.0)))
	ry = maxf(ry,minf(CORNER_MIN,maxf(room.y,0.0)))
	# 半径再大也不能超过半条边，否则曲线会自交。
	return Vector2(minf(rx,size.x*0.45),minf(ry,size.y*0.45))

func _outline() -> PackedVector2Array:
	var r := _corner_radius()
	if size == _cached_size and r == _cached_radius and not _contour.is_empty(): return _contour
	_cached_size=size
	_cached_radius=r
	_contour.clear()
	# Dense, evenly sampled cubic curves avoid the old superellipse corner facets.
	var curve := Curve2D.new()
	var w := size.x
	var h := size.y
	var rx := r.x
	var ry := r.y
	var k := 0.55
	if dialogue:
		# 对话条：横长形，上下边微微往外鼓，才有「软纸条」的感觉。
		# 四角仍由同一个半径决定，内容框一律落在直边区里。
		var b := minf(h*0.06,6.0)
		curve.add_point(Vector2(rx,0),Vector2(-rx*k,0),Vector2(rx*k,-b))
		curve.add_point(Vector2(w-rx,0),Vector2(-rx*k,-b),Vector2(rx*k,0))
		curve.add_point(Vector2(w,ry),Vector2(0,-ry*k),Vector2(0,ry*k))
		curve.add_point(Vector2(w,h-ry),Vector2(0,-ry*k),Vector2(0,ry*k))
		curve.add_point(Vector2(w-rx,h),Vector2(rx*k,b),Vector2(-rx*k,0))
		curve.add_point(Vector2(rx,h),Vector2(rx*k,0),Vector2(-rx*k,b))
		curve.add_point(Vector2(0,h-ry),Vector2(0,ry*k),Vector2(0,-ry*k))
		curve.add_point(Vector2(0,ry),Vector2(0,ry*k),Vector2(0,-ry*k))
	else:
		# 四角半径故意不相等：一模一样就是圆角矩形，差几像素才像手工裁的纸。
		# 差异量小于 `CORNER_GAP`，不会把内容框再挤出去。
		var j := 0.94
		var tl := rx
		var tr := rx*j
		var br := rx*(2.0-j)
		var bl := rx*j
		curve.add_point(Vector2(tl,0),Vector2(-tl*k,0),Vector2(tl*k,0))
		curve.add_point(Vector2(w-tr,0),Vector2(-tr*k,0),Vector2(tr*k,0))
		curve.add_point(Vector2(w,ry),Vector2(0,-ry*k),Vector2(0,ry*k))
		curve.add_point(Vector2(w,h-ry),Vector2(0,-ry*k),Vector2(0,ry*k))
		curve.add_point(Vector2(w-br,h),Vector2(br*k,0),Vector2(-br*k,0))
		curve.add_point(Vector2(bl,h),Vector2(bl*k,0),Vector2(-bl*k,0))
		curve.add_point(Vector2(0,h-ry),Vector2(0,ry*k),Vector2(0,-ry*k))
		curve.add_point(Vector2(0,ry),Vector2(0,ry*k),Vector2(0,-ry*k))
	curve.add_point(curve.get_point_position(0),curve.get_point_in(0),curve.get_point_out(0))
	for segment in curve.point_count-1:
		for sample in 48: _contour.append(curve.sample(segment,sample/48.0))
	return _contour

func _draw() -> void:
	if size.x < 8 or size.y < 8: return
	if phone:
		var shell := StyleBoxFlat.new()
		shell.bg_color=tint;shell.set_corner_radius_all(40)
		shell.corner_detail=20;shell.anti_aliasing=true;shell.anti_aliasing_size=1.5
		shell.shadow_color=Color(0,0,0,0.18);shell.shadow_size=int(shadow_blur);shell.shadow_offset=Vector2(0,shadow_y)
		draw_style_box(shell,Rect2(Vector2(outset,outset),size-Vector2(outset,outset)*2))
		return
	var points := _outline()
	for i in range(6,0,-1):
		var shadow := PackedVector2Array()
		for point in points: shadow.append((point-size/2)*(1.0+i*0.002)+size/2+Vector2(0,shadow_y))
		draw_colored_polygon(shadow,Color(0,0,0,0.012))
	draw_colored_polygon(points,tint)
	var edge := points.duplicate();edge.append(points[0])
	draw_polyline(edge,tint,1.25,true)
