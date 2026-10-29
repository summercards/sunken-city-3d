extends Node3D
## Interaction adapter. Injected scene services; no global Economy/Main reads.
const Catalog = preload("res://src/building/building_catalog.gd")
const World = preload("res://src/building/building_world.gd")
const ThinBar = preload("res://src/ui/thin_progress_bar.gd")
var service: RefCounted
var world: Node3D
var camera: Camera3D
var hud: CanvasLayer
var cancel_actor: Callable
## 施工要先走过去（2026-10-29）。
##
## 以前点虚影当场扣材料开工，人还站在平台另一头，木板上就自己长出了进度条 ——
## 建造像在 map 上点按钮，而不是「我在这个家上动手」。
## 现在点击只记下意图：先让角色走到那一格边上，站定了才真正 begin。
var approach_point: Callable   # func(world_point) -> bool，开始走过去
var stand_point: Callable      # func(tile_center) -> Vector3，该格旁最近的落脚点（INF=没有）
var actor_state: Callable      # func() -> Dictionary{position: Vector3, walking: bool}
var pending: Dictionary = {}
var pending_stand := Vector3.INF
var pending_left := 0.0
var pending_age := 0.0
## 到位判定半径（米）。角色半径约 0.35，留出半个身位的余量。
const ARRIVE := 0.8
## 走过去的最长等待。到点还没开始，就当这条路走不通，别让玩家一直等。
const WAIT_LIMIT := 8.0
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

func configure(model: RefCounted, projection: Node3D, view: Camera3D, ui: CanvasLayer, inventory_query: Callable, cancel: Callable, stand: Callable = Callable(), approach: Callable = Callable(), actor: Callable = Callable()) -> void:
	service=model;world=projection;camera=view;hud=ui;cancel_actor=cancel
	stand_point=stand;approach_point=approach;actor_state=actor
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
	_clear_pending()
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
		# 贴边越界时吸回最近的合法格点；重叠或压到角色仍照常报红。
		if not preview.is_empty(): preview=service.snap_planter(preview)
		if not candidate_ghosts.is_empty():
			var node: Node3D=candidate_ghosts[0].node;node.visible=not preview.is_empty()
			if node.visible: node.position=world.position_for(preview);node.rotation.y=turn*PI/2
	var reason: String=service.can_place(preview) if not preview.is_empty() else "选择绿色虚影" if recipe=="deck" else "把光标移到新木板上选择位置"
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
			# 已有一处等待开工时，重复点只换目标，不再叠加：材料只够一份，
			# 叠加会让「走到第一处就开工、第二处又扣一次」变成扣两次材料。
			if not preview.is_empty():
				_request_build(preview)
		return true
	return false

## 点击虚影：先检查能不能建，再让角色走过去，站定了才开工。
##
## 已在旁边就直接开工 —— 玩家站在工地边缘点一下，不该再看他走两步。
func _request_build(request: Dictionary) -> void:
	var reason: String=service.can_place(request)
	if reason!="": hud.toast(reason);return
	var center: Vector3=world.position_for(request)
	var stand: Vector3=stand_point.call(center) if stand_point.is_valid() else center
	if stand==Vector3.INF or not stand.is_finite():
		hud.toast("这里没有能站的位置");return
	var state: Dictionary=actor_state.call() if actor_state.is_valid() else {}
	var at: Vector3=state.get("position",Vector3.INF)
	if at.is_finite() and Vector2(at.x-stand.x,at.z-stand.z).length()<=ARRIVE:
		_begin_now(request);return
	if not approach_point.is_valid() or not bool(approach_point.call(stand)):
		hud.toast("走不到施工位置，换个地方建");return
	pending=request.duplicate(true);pending_stand=stand
	pending_left=WAIT_LIMIT;pending_age=0.0
	preview=pending.duplicate(true)
	hint.text="走到木板边再开工    ·    Esc 取消"

func _begin_now(request: Dictionary) -> void:
	_clear_pending()
	var result: Dictionary=service.begin(request)
	if not result.ok: hud.toast(result.reason);return
	preview={}

func _clear_pending() -> void:
	pending={};pending_stand=Vector3.INF;pending_left=0.0;pending_age=0.0

## 每帧确认「到了没有」。到位即开工；走不到（停下但没到、或超时）就取消并说明。
##
## 判定要求「停下 + 站在范围内」两个条件同时成立：只看距离会在角色还滑进去的
## 最后半米就开工，进度条追着人跑；只看停下则可能在半路被别的东西截停。
func _sync_pending(delta: float) -> void:
	if pending.is_empty(): return
	pending_left-=delta
	pending_age+=delta
	var state: Dictionary=actor_state.call() if actor_state.is_valid() else {}
	var at: Vector3=state.get("position",Vector3.INF)
	var walking:=bool(state.get("walking",true))
	var near:=at.is_finite() and Vector2(at.x-pending_stand.x,at.z-pending_stand.z).length()<=ARRIVE
	if near and not walking:
		var request:=pending.duplicate(true)
		_begin_now(request)
		return
	if pending_left<=0.0 or (not walking and pending_age>0.4):
		_clear_pending();preview={}
		hud.toast("没走到施工位置，已取消")

func tick(delta: float) -> void:
	service.tick(delta)
	_place_book()
	_sync_pending(delta)
	if active and not book.visible:
		if service.context_reason()!="": close()
		# 等待开工期间锁住虚影：鼠标一动就换位置，玩家会以为刚才点的那格没记住。
		elif pending.is_empty(): update_preview(get_viewport().get_mouse_position())
		elif hint!=null: hint.text="走到木板边再开工    ·    Esc 取消"
	var live := {}
	for item in service.query():
		if item.left<=0: continue
		live[item.id]=true
		if not progress.has(item.id):
			# 用共享的细条（自绘），不再用 ProgressBar：
			# ProgressBar 的 content margin 会把条撑到约 20px 高，粗得压不住画面。
			var bar:=ThinBar.new()
			bar.configure(ThinBar.BUILD_WIDTH,ThinBar.BUILD_HEIGHT,ThinBar.BUILD_FILL,ThinBar.BUILD_TRACK)
			overlay.add_child(bar);progress[item.id]=bar
		var point: Vector3=world.position_for(item)+Vector3.UP*0.8
		var bar: ThinBar=progress[item.id]
		bar.visible=not camera.is_position_behind(point)
		bar.place_at(camera.unproject_position(point),12.0)
		bar.set_ratio(1.0-float(item.left)/float(Catalog.RECIPES[item.kind].seconds))
	for id in progress.keys():
		if not live.has(id): progress[id].queue_free();progress.erase(id)
