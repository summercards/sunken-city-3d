extends Node3D
## Interaction adapter. Injected scene services; no global Economy/Main reads.
const Catalog = preload("res://src/building/building_catalog.gd")
const World = preload("res://src/building/building_world.gd")
var service: RefCounted
var world: Node3D
var camera: Camera3D
var hud: CanvasLayer
var cancel_actor: Callable
var book: Control
var overlay: Control
var hint: Label
var preview_root: Node3D
var canvas: CanvasLayer
var active := false
var recipe := ""
var turn := 0
var preview: Dictionary = {}
var progress := {}
var candidate_ghosts: Array=[]

func configure(model: RefCounted, projection: Node3D, view: Camera3D, ui: CanvasLayer, inventory_query: Callable, cancel: Callable) -> void:
	service=model;world=projection;camera=view;hud=ui;cancel_actor=cancel
	hud.owned_modal_query=func(): return active
	hud.owned_modal_close=close
	hud.owned_modal_input=handle_input
	preview_root=Node3D.new();add_child(preview_root)
	canvas=CanvasLayer.new();canvas.layer=30;add_child(canvas)
	overlay=Control.new();overlay.set_meta("cozy_skip",true);overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE;canvas.add_child(overlay)
	book=preload("res://src/building/building_book.gd").new();book.inventory_query=inventory_query;overlay.add_child(book);book.hide()
	book.selected.connect(select_recipe);book.closed.connect(close)
	hint=Label.new();hint.add_theme_font_override("font",book.font);hint.add_theme_font_size_override("font_size",23)
	hint.add_theme_color_override("font_color",Color("#fff2ca"));hint.add_theme_color_override("font_shadow_color",Color("#364b48"));hint.add_theme_constant_override("shadow_offset_x",2);hint.add_theme_constant_override("shadow_offset_y",2)
	overlay.add_child(hint);hint.hide()
	service.changed.connect(_refresh_ghosts)
	service.completed.connect(func(id): hud.toast(Catalog.RECIPES[service.row(id).kind].name+"建造完成"))
func open() -> void:
	cancel_actor.call();hud.close_card();hud.set_external_modal(true,false)
	active=true;recipe="";book.refresh();book.show();hint.hide();_clear_ghosts();_place_book()
func close() -> void:
	active=false;recipe="";preview={};book.hide();hint.hide();_clear_ghosts();hud.set_external_modal(false,false)
	var focused:=get_viewport().gui_get_focus_owner()
	if focused!=null and book.is_ancestor_of(focused): focused.release_focus()
func select_recipe(kind: String) -> void:
	var reason: String=service.context_reason()
	if reason!="": hud.toast(reason);return
	recipe=kind;book.hide();hint.show();_refresh_ghosts()
	update_preview(get_viewport().get_mouse_position())
func _place_book() -> void:
	var viewport:=get_viewport().get_visible_rect().size
	var fit:=minf(1.0,minf((viewport.x-48)/book.size.x,(viewport.y-80)/book.size.y))
	book.scale=Vector2.ONE*fit;book.position=(viewport-book.size*fit)/2
	hint.position=Vector2(50,viewport.y-70)
func _clear_ghosts() -> void:
	for node in preview_root.get_children(): preview_root.remove_child(node);node.queue_free()
	candidate_ghosts.clear()
func _refresh_ghosts() -> void:
	_clear_ghosts()
	if not active or book.visible: return
	if recipe=="deck":
		for candidate in service.candidates():
			var node=World.Deck.instantiate();node.ghost=true;node.position=world.position_for(candidate)
			preview_root.add_child(node);candidate_ghosts.append({"node":node,"request":candidate})
	else:
		var node:=World.ghost_planter();preview_root.add_child(node);candidate_ghosts.append({"node":node});node.hide()
func _point(screen: Vector2) -> Vector3:
	var origin:=camera.project_ray_origin(screen);var direction:=camera.project_ray_normal(screen)
	if absf(direction.y)<0.0001: return Vector3.INF
	var distance: float=(Catalog.ORIGIN.y-origin.y)/direction.y
	return origin+direction*distance if distance>0 else Vector3.INF
func update_preview(screen: Vector2) -> void:
	preview={}
	var point:=_point(screen)
	if point==Vector3.INF: return
	var local:=Vector2(point.x-Catalog.ORIGIN.x,point.z-Catalog.ORIGIN.z)
	if recipe=="deck":
		for entry in candidate_ghosts:
			if Catalog.tile_rect(entry.request.x,entry.request.z).has_point(local): preview=entry.request.duplicate(true)
	else:
		for item in service.query():
			if item.kind=="deck" and item.left<=0 and Catalog.tile_rect(item.x,item.z).has_point(local):
				preview={"kind":"planter","x":0,"z":0,"px":snappedf(local.x,0.1),"pz":snappedf(local.y,0.1),"turn":turn,"support":item.id}
		if not candidate_ghosts.is_empty():
			var node: Node3D=candidate_ghosts[0].node;node.visible=not preview.is_empty()
			if node.visible: node.position=world.position_for(preview);node.rotation.y=turn*PI/2
	var reason: String=service.can_place(preview) if not preview.is_empty() else "选择绿色虚影" if recipe=="deck" else "将种植区放在已完成的新木板上"
	hint.text=("点击施工" if reason=="" else reason)+"    ·    R 旋转种植区    ·    Esc 退出"
	for entry in candidate_ghosts:
		var selected: bool=not preview.is_empty() and (recipe=="planter" or (entry.request.x==preview.x and entry.request.z==preview.z))
		for mesh in entry.node.get_children():
			if mesh is MeshInstance3D:
				mesh.material_override.albedo_color=Color(0.94,0.45,0.35,0.55) if selected and reason!="" else Color(0.52,0.95,0.78,0.7 if selected else 0.35)
func handle_input(event: InputEvent) -> bool:
	if not active: return false
	if event is InputEventKey and event.pressed:
		if event.physical_keycode in [KEY_F5,KEY_F9]: return false
		if event.physical_keycode==KEY_ESCAPE: close()
		elif event.physical_keycode==KEY_R: turn=(turn+1)%4
		return true
	if event is InputEventMouseButton:
		if event.pressed and event.button_index==MOUSE_BUTTON_LEFT and not book.visible:
			update_preview(event.position)
			if not preview.is_empty():
				var result: Dictionary=service.begin(preview)
				if not result.ok: hud.toast(result.reason)
		return true
	return false
func tick(delta: float) -> void:
	service.tick(delta)
	_place_book()
	if active and not book.visible:
		if service.context_reason()!="": close()
		else: update_preview(get_viewport().get_mouse_position())
	var live := {}
	for item in service.query():
		if item.left<=0: continue
		live[item.id]=true
		if not progress.has(item.id):
			var bar:=ProgressBar.new();bar.size=Vector2(92,12);bar.show_percentage=false;bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
			bar.add_theme_stylebox_override("background",preload("res://src/ui/cozy_ui.gd").surface(Color("#584c38"),6))
			bar.add_theme_stylebox_override("fill",preload("res://src/ui/cozy_ui.gd").surface(Color("#e9c16b"),6))
			overlay.add_child(bar);progress[item.id]=bar
		var point: Vector3=world.position_for(item)+Vector3.UP*0.8
		var bar: ProgressBar=progress[item.id];bar.visible=not camera.is_position_behind(point)
		bar.position=camera.unproject_position(point)-Vector2(46,20)
		bar.value=100*(1-float(item.left)/float(Catalog.RECIPES[item.kind].seconds))
	for id in progress.keys():
		if not live.has(id): progress[id].queue_free();progress.erase(id)
