extends Control
## Reference-shaped stationery. The owner remains responsible for input/layout.
var tint := Color("#fff9e8")
var accent := Color("#68b6a2")
var dialogue := false
var stitched := false
var phone := false
var shadow_blur := 10.0
var shadow_y := 5.0
var _cached_size := Vector2.ZERO
var _contour := PackedVector2Array()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	resized.connect(queue_redraw)

func _process(_delta: float) -> void:
	if not has_meta("paper_owner"): return
	var owner_panel: Control=get_meta("paper_owner")
	if not is_instance_valid(owner_panel): return
	position=owner_panel.position;size=owner_panel.size
	scale=owner_panel.scale;pivot_offset=owner_panel.pivot_offset
	visible=owner_panel.visible;modulate=owner_panel.modulate

func _outline() -> PackedVector2Array:
	if size == _cached_size and not _contour.is_empty(): return _contour
	_cached_size=size
	_contour.clear()
	# Dense, evenly sampled cubic curves avoid the old superellipse corner facets.
	var curve := Curve2D.new()
	if dialogue:
		curve.add_point(Vector2(0.08,0.08)*size,Vector2(-0.10,0.08)*size,Vector2(0.18,-0.09)*size)
		curve.add_point(Vector2(0.92,0.08)*size,Vector2(-0.18,-0.09)*size,Vector2(0.10,0.08)*size)
		curve.add_point(Vector2(0.97,0.70)*size,Vector2(0.07,-0.30)*size,Vector2(-0.03,0.15)*size)
		curve.add_point(Vector2(0.90,0.96)*size,Vector2(0.12,-0.03)*size,Vector2(-0.24,0.04)*size)
		curve.add_point(Vector2(0.10,0.96)*size,Vector2(0.24,0.04)*size,Vector2(-0.12,-0.03)*size)
		curve.add_point(Vector2(0.03,0.70)*size,Vector2(0.03,0.15)*size,Vector2(-0.07,-0.30)*size)
	else:
		curve.add_point(Vector2(0.10,0.03)*size,Vector2(-0.09,0.02)*size,Vector2(0.22,-0.035)*size)
		curve.add_point(Vector2(0.90,0.03)*size,Vector2(-0.22,-0.035)*size,Vector2(0.09,0.02)*size)
		curve.add_point(Vector2(0.99,0.50)*size,Vector2(0,-0.27)*size,Vector2(0,0.27)*size)
		curve.add_point(Vector2(0.90,0.97)*size,Vector2(0.09,-0.02)*size,Vector2(-0.22,0.035)*size)
		curve.add_point(Vector2(0.10,0.97)*size,Vector2(0.22,0.035)*size,Vector2(-0.09,-0.02)*size)
		curve.add_point(Vector2(0.01,0.50)*size,Vector2(0,0.27)*size,Vector2(0,-0.27)*size)
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
		draw_style_box(shell,Rect2(Vector2.ZERO,size))
		return
	var points := _outline()
	for i in range(6,0,-1):
		var shadow := PackedVector2Array()
		for point in points: shadow.append((point-size/2)*(1.0+i*0.002)+size/2+Vector2(0,shadow_y))
		draw_colored_polygon(shadow,Color(0,0,0,0.012))
	draw_colored_polygon(points,tint)
	var edge := points.duplicate();edge.append(points[0])
	draw_polyline(edge,tint,1.25,true)
