extends Node3D
## Authoring adapter. State and transactions stay in the injected owners.
const Catalog = preload("res://src/building/building_catalog.gd")
const World = preload("res://src/building/building_world.gd")
const ProgressPresenter = preload("res://src/building/ui/building_progress_presenter.gd")
const Pointer = preload("res://src/building/building_pointer.gd")
const ARRIVE := 0.8
const WAIT_LIMIT := 8.0
## A rendering budget, never a construction limit.
const MAX_FRONTIER_GHOSTS := 96
const PREVIEW_CACHE_MS := 180
var service: RefCounted
var world: Node3D
var camera: Camera3D
var hud: CanvasLayer
var cancel_actor: Callable
var inventory_query: Callable
var approach_point: Callable
var stand_point: Callable
var actor_state: Callable
var pending: Dictionary = {}
var pending_stand := Vector3.INF
var pending_left := 0.0
var pending_age := 0.0
var book: Control
var overlay: Control
var hint: Label
var guide: Panel
var guide_title: Label
var guide_back: Button
var selection_outline: MeshInstance3D
var _outline_key := ""
var preview_root: Node3D
var canvas: CanvasLayer
var active := false
var recipe := ""
var turn := 0
var build_level := 0.0
var view: Control
var _hint_text := ""
var preview: Dictionary = {}
var progress := {}
var progress_presenter := ProgressPresenter.new()
var candidate_ghosts: Array = []
var moving_id := ""
var hovered_id := ""
var precision_held := false
var focus_ghost: Node3D
var _focus_kind := ""
var _revision := 0
var _preview_cache := {}
var _frontier_refresh_left := 0.0
var _rows_cache: Array = []
var _working_ids: Array[String] = []
var _render_recipe := ""
var demolition: Control
var manual_level := false
var snap_assist := true
var _mesh_faces: Dictionary={}
var keyboard_mode := false
var keyboard_cursor := Vector3.INF
var keyboard_target_id := ""
var _held_keys: Dictionary={}
var _submit_frame := -1
const INPUT_HANDLED_META := "building_controller_input_handled"

## 组合根的 K 入口；只打开手册，不在这里注册全局快捷键。
func open_keyboard() -> void:
	keyboard_mode=true
	keyboard_cursor=Vector3.INF
	open()
	_seed_keyboard_cursor()
	book.restore_focus()

## GUI 前拦截建造键，避免 ui_accept 先被按钮消费或落入世界交互。
func _input(event: InputEvent) -> void:
	if service==null or get_tree().paused: return
	if event.get_meta(INPUT_HANDLED_META,false): return
	if event is InputEventKey:
		var code: int=event.physical_keycode if event.physical_keycode else event.keycode
		if not event.pressed and _held_keys.has(code):
			_held_keys.erase(code)
			if code==KEY_SHIFT: precision_held=false
			get_viewport().set_input_as_handled();return
		if active and handle_input(event): get_viewport().set_input_as_handled()
	elif active and (event is InputEventMouseButton or (event is InputEventMouseMotion and event.relative!=Vector2.ZERO)):
		keyboard_mode=false
		demolition.keyboard_mode=false

func _camera_direction(axis: Vector2) -> Vector3:
	var right:=camera.global_basis.x;right.y=0.0
	var forward:=-camera.global_basis.z;forward.y=0.0
	if forward.length_squared()<0.001: forward=Vector3.FORWARD
	if right.length_squared()<0.001: right=Vector3.RIGHT
	return (right.normalized()*axis.x-forward.normalized()*axis.y).normalized()

func _seed_keyboard_cursor() -> void:
	if keyboard_cursor.is_finite(): return
	var state: Dictionary=actor_state.call() if actor_state.is_valid() else {}
	var at: Vector3=state.get("position",Catalog.ORIGIN)
	keyboard_cursor=at+_camera_direction(Vector2.UP)*(3.0 if _afloat() else 1.5)
	keyboard_cursor.y=Catalog.ORIGIN.y+float(build_level)*Catalog.LAYER_HEIGHT

func _cycle_keyboard_target(offset: int) -> void:
	keyboard_mode=true;demolition.keyboard_mode=true
	var rows: Array=_rows_cache.duplicate()
	var state: Dictionary=actor_state.call() if actor_state.is_valid() else {}
	var at: Vector3=state.get("position",Catalog.ORIGIN)
	rows.sort_custom(func(a: Dictionary,b: Dictionary):
		var da: float=world.position_for(a).distance_squared_to(at)
		var db: float=world.position_for(b).distance_squared_to(at)
		return str(a.id)<str(b.id) if is_equal_approx(da,db) else da<db)
	if rows.is_empty(): keyboard_target_id="";return
	var index: int=-1
	for i in rows.size():
		if str(rows[i].id)==keyboard_target_id: index=i;break
	keyboard_target_id=str(rows[posmod(index+offset,rows.size())].id)

func _refresh_current_preview() -> void:
	update_preview(Vector2.ZERO if keyboard_mode else get_viewport().get_mouse_position())

## 两种输入只调用这一个提交入口，规则、接近、扣费和退款仍归原请求通道。
func submit_preview(screen: Vector2=Vector2.INF) -> void:
	if not active or book.visible or demolition.confirmation_open() or not pending.is_empty(): return
	var frame:=Engine.get_process_frames()
	if _submit_frame==frame: return
	_submit_frame=frame
	_preview_cache.clear()
	if screen.is_finite(): update_preview(screen)
	else: _refresh_current_preview()
	if preview.is_empty():
		hud.toast("请选择自建物件；原有平台和固定设施不能拆回或搬移")
		return
	if recipe=="move" and moving_id=="":
		if float(preview.left)>0: hud.toast("施工完成后才能搬移")
		elif not Catalog.RECIPES[preview.kind].get("movable",false): hud.toast("此构件不能搬移，请先安全拆回再重新建造")
		else:
			moving_id=preview.id;turn=int(preview.turn)
			build_level=Catalog.elevation(preview)/Catalog.LAYER_HEIGHT;manual_level=true
			keyboard_cursor=world.position_for(preview);preview={};_preview_cache.clear();_refresh_ghosts()
	elif recipe=="move": _request_action(preview,"move",moving_id)
	elif recipe=="remove":
		var reason:=_preview_reason(preview,"remove",hovered_id)
		if reason!="": hud.toast(reason)
		else: demolition.ask(preview,Catalog.RECIPES[preview.kind].cost)
	else: _request_build(preview)
	_refresh_current_preview()

func configure(model: RefCounted, projection: Node3D, camera_view: Camera3D, ui: CanvasLayer, items: Callable, cancel: Callable, stand: Callable = Callable(), approach: Callable = Callable(), actor: Callable = Callable()) -> void:
	service=model; world=projection; camera=camera_view; hud=ui
	inventory_query=items; cancel_actor=cancel; stand_point=stand; approach_point=approach; actor_state=actor
	hud.owned_modal_query=func(): return active
	hud.owned_modal_close=close; hud.owned_modal_input=handle_input
	preview_root=Node3D.new(); add_child(preview_root)
	canvas=CanvasLayer.new(); canvas.layer=30; add_child(canvas)
	overlay=Control.new(); overlay.set_meta("cozy_skip",true)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE; canvas.add_child(overlay)
	view=preload("res://src/building/ui/building_view.gd").new()
	view.inventory_query=items;overlay.add_child(view)
	view.action_requested.connect(_ui_action)
	book=view.book;demolition=view.demolition
	guide=view.guide;guide_title=view.guide_title;guide_back=view.guide_back;hint=view.hint
	demolition.confirmed.connect(_confirm_demolition)
	demolition.cancelled.connect(show_book)
	hud.owned_modal_camera_query=allows_camera
	selection_outline=MeshInstance3D.new();add_child(selection_outline);selection_outline.hide()
	service.changed.connect(_layout_changed)
	_cache_layout()
	service.completed.connect(func(id):
		var row: Dictionary=service.row(id)
		if not row.is_empty(): hud.toast(Catalog.RECIPES[row.kind].name+"建造完成"))

func open() -> void:
	cancel_actor.call(); _clear_pending(); hud.close_card(); hud.set_external_modal(true,false)
	active=true; recipe=""; moving_id=""; hovered_id=""
	demolition.set_active(false);manual_level=false;_inherit_actor_level()
	book.refresh(); book.show();_hint_text=""
	selection_outline.hide();_clear_ghosts();_sync_view()
	book.restore_focus()

func close() -> void:
	if not pending.is_empty(): cancel_actor.call()
	active=false; recipe=""; preview={}; moving_id=""; hovered_id=""; precision_held=false
	demolition.set_active(false)
	book.hide(); hint.hide();guide.hide();selection_outline.hide(); _clear_ghosts(); hud.set_external_modal(false,false); _clear_pending()
	_sync_view()
	var focused:=get_viewport().gui_get_focus_owner()
	if focused!=null and view.is_ancestor_of(focused): focused.release_focus()

func select_recipe(kind: String) -> void:
	var reason: String=service.context_reason()
	if reason!="" and kind not in ["move","remove"]: hud.toast(reason); return
	if not Catalog.RECIPES.has(kind) and kind not in ["move","remove"]: return
	if Catalog.RECIPES.has(kind) and not Catalog.enabled(kind): hud.toast("该内容已停用");return
	if not pending.is_empty(): cancel_actor.call()
	_clear_pending(); moving_id=""; hovered_id=""; preview={}
	demolition.set_active(kind=="remove")
	recipe=kind;book.hide();_hint_text=""
	_sync_view()
	_seed_keyboard_cursor();demolition.keyboard_mode=keyboard_mode
	if keyboard_mode and kind in ["move","remove"]: _cycle_keyboard_target(1)
	_refresh_ghosts();_refresh_current_preview()
	var focused:=get_viewport().gui_get_focus_owner()
	if focused!=null and book.is_ancestor_of(focused): focused.release_focus()

func show_book() -> void:
	if not pending.is_empty(): cancel_actor.call()
	_clear_pending(); moving_id=""; hovered_id=""; preview={}; recipe=""
	demolition.set_active(false)
	_clear_ghosts();book.refresh();book.show();selection_outline.hide()
	_hint_text="";_sync_view()
	book.restore_focus()

func open_demolition() -> void:
	if active and recipe=="remove": close();return
	open();select_recipe("remove")

func _confirm_demolition(id: String) -> void:
	if not active or recipe!="remove": return
	var item: Dictionary=service.row(id)
	if item.is_empty(): hud.toast("物件已经不存在");return
	_request_action(item,"remove",id)

func allows_camera() -> bool:
	return active and not book.visible and not demolition.confirmation_open()

func _inherit_actor_level() -> void:
	if not actor_state.is_valid(): return
	var state: Dictionary=actor_state.call()
	var point: Vector3=state.get("position",Catalog.ORIGIN)
	var height:=maxf(0.0,point.y-Catalog.ORIGIN.y) if int(state.get("mode",0))==0 else 0.0
	var nearest:=0.0;var distance:=INF
	for level: float in Catalog.placement_levels(_rows_cache):
		if absf(level-height)<distance: nearest=level;distance=absf(level-height)
	build_level=nearest/Catalog.LAYER_HEIGHT

func _cycle_level() -> void:
	var levels: Array=Catalog.placement_levels(_rows_cache)
	var current_height:=build_level*Catalog.LAYER_HEIGHT
	var next:=float(levels[0])
	for level: float in levels:
		if level>current_height+0.001: next=level;break
	build_level=next/Catalog.LAYER_HEIGHT
	manual_level=true;_preview_cache.clear()

func _ui_action(action: String) -> void:
	if action=="exit": close();return
	if demolition.confirmation_open(): return
	match action:
		"book": show_book()
		"level": _cycle_level()
		"auto": manual_level=false;_preview_cache.clear()
		"snap": snap_assist=not snap_assist;_preview_cache.clear()
		"rotate": turn=(turn+1)%4;_preview_cache.clear()
		_: select_recipe(action)
	if active and not book.visible: _refresh_current_preview()
	_sync_view()

func _sync_view() -> void:
	var title:="家园营造"
	if recipe=="remove": title="拆除模式 · 选择物件后确认"
	elif recipe=="move": title="搬移模式 · "+("选择新位置" if moving_id!="" else "选择摆件")
	elif recipe!="": title="建造 · "+str(Catalog.RECIPES[recipe].name)
	var height:=float(preview.get("py",build_level*Catalog.LAYER_HEIGHT))
	view.set_state({"active":active,"book_open":book.visible,"recipe":recipe,"title":title,
		"height":height,"manual_level":manual_level,"snap_assist":snap_assist,"hint":_hint_text})

func _place_book() -> void:
	view.layout(get_viewport().get_visible_rect().size)

func _layout_changed() -> void:
	_revision+=1; _preview_cache.clear(); _cache_layout()
	if moving_id!="" and service.row(moving_id).is_empty(): moving_id=""
	_refresh_ghosts()

func _cache_layout() -> void:
	# Do not duplicate an unlimited layout on every pointer/progress frame.
	# Structural rows change only on the service signal; live timers are read
	# individually from the service's indexed row query.
	_rows_cache=service.query(); _working_ids.clear()
	for row in _rows_cache:
		if float(row.left)>0.0: _working_ids.append(str(row.id))

func _clear_ghosts() -> void:
	for node in preview_root.get_children(): preview_root.remove_child(node); node.queue_free()
	candidate_ghosts.clear(); focus_ghost=null; _focus_kind=""; _render_recipe=""

func _is_furnishing(kind: String) -> bool:
	return Catalog.is_furnishing(kind)

func _refresh_ghosts() -> void:
	_frontier_refresh_left=0.65
	if not active or book.visible:
		_clear_ghosts(); return
	if _render_recipe!=recipe:
		_clear_ghosts(); _render_recipe=recipe
	if recipe=="deck":
		# Reuse visible frontier meshes across pan/layout updates. A large shore
		# must not recreate up to 96 thirteen-board previews every 650ms.
		var previous: Dictionary={}
		for entry in candidate_ghosts:
			previous[Vector2i(int(entry.request.x),int(entry.request.z))]=entry
		var visible: Array=[]
		var viewport:=get_viewport().get_visible_rect().grow(80)
		for candidate in service.candidates():
			var point: Vector3=world.position_for(candidate)
			if camera.is_position_behind(point): continue
			if not viewport.has_point(camera.unproject_position(point)): continue
			visible.append(candidate)
		visible.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
			return camera.global_position.distance_squared_to(world.position_for(a))<camera.global_position.distance_squared_to(world.position_for(b)))
		var next: Array=[]
		for i in mini(visible.size(),MAX_FRONTIER_GHOSTS):
			var candidate: Dictionary=visible[i]
			var cell:=Vector2i(int(candidate.x),int(candidate.z))
			var entry: Dictionary=previous.get(cell,{})
			if entry.is_empty():
				var node: Node3D=World.Deck.instantiate(); node.ghost=true; node.position=world.position_for(candidate)
				preview_root.add_child(node); entry={"node":node,"request":candidate}
			else: previous.erase(cell)
			# Only selected previews need full candidate-layout/save-capacity and
			# approach checks. Frontier suggestions still check actual geometry,
			# building/dock/boat obstruction through the rule owner's cheap query.
			entry.invalid=service.preview_reason(candidate)!=""
			next.append(entry)
		for entry in previous.values(): preview_root.remove_child(entry.node); entry.node.queue_free()
		candidate_ghosts=next
	elif _is_furnishing(recipe):
		if candidate_ghosts.is_empty():
			var node: Node3D=load(Catalog.RECIPES[recipe].prefab).instantiate() if Catalog.is_kit(recipe) else World.ghost_planter()
			if Catalog.is_kit(recipe): node.ghost=true
			else: _size_ghost(node,recipe)
			preview_root.add_child(node); node.hide()
			candidate_ghosts.append({"node":node})

func _point(screen: Vector2) -> Vector3:
	var kind:=str(service.row(moving_id).get("kind",recipe)) if moving_id!="" else recipe
	var height:=float(build_level)*Catalog.LAYER_HEIGHT
	if not manual_level:
		var stairs:=str(Catalog.RECIPES.get(kind,{}).get("profile",""))=="stairs"
		height=Pointer.surface_height(screen,camera,_rows_cache,height,Catalog.is_platform(kind) or stairs)
		if kind=="upper_floor" and height<.1:
			var levels:=Catalog.placement_levels(_rows_cache)
			if levels.size()>1: height=float(levels[-1])
		# Roofs and beams can connect at actual wall/post tops.
		if Catalog.is_kit(kind) and str(Catalog.RECIPES[kind].get("placement",""))=="top":
			for item in _rows_cache:
				if item.left>0 or str(Catalog.RECIPES[item.kind].get("profile","")) not in ["post","wall","window","door","beam"]: continue
				var top:=Catalog.elevation(item)+Catalog.component_height(item)
				var probe:=Pointer.plane_point(screen,camera,top)
				if probe.is_finite() and Catalog.footprint_rect(item).grow(1.0).has_point(Vector2(probe.x-Catalog.ORIGIN.x,probe.z-Catalog.ORIGIN.z)):
					height=top-(float(Catalog.RECIPES[kind].height) if kind=="beam" else 0.0);break
	return Pointer.plane_point(screen,camera,height)

## The boat carries the material, so only it may start a lone platform.
func _afloat() -> bool:
	if not actor_state.is_valid(): return false
	var state: Dictionary=actor_state.call()
	return int(state.get("mode",0)) in [1,2]

func _deck_request(local: Vector2) -> Dictionary:
	var request:=Catalog.snap_deck(local,_rows_cache,_afloat(),float(build_level)*Catalog.LAYER_HEIGHT,0.01 if precision_held else 0.1,snap_assist,turn)
	request.origin="boat" if _afloat() else "shore"
	return request

func _furnishing_request(local: Vector2,height: float=NAN) -> Dictionary:
	var step:=0.01 if precision_held or Input.is_physical_key_pressed(KEY_SHIFT) else 0.1
	var kind:=str(service.row(moving_id).get("kind","planter")) if moving_id!="" else recipe
	var request: Dictionary={"kind":kind,"x":0,"z":0,"px":snappedf(local.x,step),"pz":snappedf(local.y,step),
		"py":height if is_finite(height) else float(build_level)*Catalog.LAYER_HEIGHT,"turn":turn,"support":"","snap_step":step,"origin":"boat" if _afloat() else "shore"}
	if moving_id!="":
		var original: Dictionary=service.row(moving_id)
		original.merge(request,true);request=original;request.exclude_id=moving_id
	if str(Catalog.RECIPES.get(kind,{}).get("profile",""))=="stairs":
		return Catalog.snap_stairs(request,_rows_cache,snap_assist and not precision_held and step>=0.1)
	# All components use the same free surface placement. No forced metre grid.
	# Nearby structural endpoints are an optional alignment aid.
	if snap_assist and not precision_held and Catalog.is_frame(kind):
		var best:=.18
		for item in _rows_cache:
			if item.left>0 or not Catalog.is_frame(str(item.kind)) or not Catalog.same_level(Catalog.elevation(item),float(request.py)): continue
			for point in preload("res://src/building/assembly_rules.gd").joint_points(item):
				var own_points: Array=preload("res://src/building/assembly_rules.gd").joint_points(request)
				for own: Vector2 in own_points:
					var distance:=own.distance_to(point)
					if distance<best:
						request.px+=point.x-own.x;request.pz+=point.y-own.y;best=distance
	var supports:=preload("res://src/building/assembly_rules.gd").support_ids(request,_rows_cache)
	if not supports.is_empty():
		request.support=supports[0]
		for id: String in supports:
			var item: Dictionary=service.row(id) if id!="@base" else {}
			var rect: Rect2=Catalog.BASE if id=="@base" else Catalog.footprint_rect(item)
			if rect.has_point(local): request.support=id;break
	if snap_assist and not Catalog.is_kit(kind) and step>=0.1 and request.support!="": request=service.snap_planter(request)
	return request

func _item_at(local: Vector2,only_furnishing:=false) -> Dictionary:
	var deck: Dictionary={}
	for item in _rows_cache:
		if _is_furnishing(item.kind) and absf(Catalog.elevation(item)-build_level*Catalog.LAYER_HEIGHT)<0.5 and Catalog.plot_rect(item).has_point(local): return item
		if not only_furnishing and Catalog.is_deck(str(item.kind)) and Catalog.footprint_rect(item).has_point(local): deck=item
	return deck

func _selection_box(item: Dictionary) -> AABB:
	var rect:=Catalog.footprint_rect(item)
	var platform:=Catalog.is_deck(str(item.kind))
	var height:=Catalog.component_height(item)
	var bottom: float=Catalog.ORIGIN.y+Catalog.elevation(item)-(height if platform else 0.0)
	return AABB(Vector3(rect.position.x+Catalog.ORIGIN.x,bottom,rect.position.y+Catalog.ORIGIN.z),Vector3(rect.size.x,maxf(height,.15),rect.size.y))

## Select the visible volume, including walls, lamps and upper-floor pieces.
## Projecting every click onto the ground made their bodies impossible to hit.
func _item_under_cursor(screen: Vector2) -> Dictionary:
	var origin:=camera.project_ray_origin(screen)
	var direction:=camera.project_ray_normal(screen)
	var best: Dictionary={};var distance:=INF
	for item in _rows_cache:
		var node: Node3D=world.node_for(str(item.id)) if world.has_method("node_for") else null
		if node!=null:
			var near:=Pointer.mesh_hit(origin,direction,node,_mesh_faces)
			if near<distance: distance=near;best=item
		else:
			var hit: Variant=_selection_box(item).intersects_ray(origin,direction)
			if hit is Vector3:
				var near:=origin.distance_squared_to(hit)
				if near<distance: distance=near;best=item

	return best

func _highlight(item: Dictionary, invalid: bool) -> void:
	selection_outline.visible=not item.is_empty()
	if item.is_empty(): return
	var key:=str(item.id)+str(_revision)+str(invalid)
	if key==_outline_key: return
	_outline_key=key
	var box:=_selection_box(item).grow(.025)
	var lines:=ImmediateMesh.new()
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color("#e4765b") if invalid else Color("#86e4b6")
	lines.surface_begin(Mesh.PRIMITIVE_LINES,material)
	for corner in 8:
		var a:=box.position+box.size*Vector3(corner&1,(corner>>1)&1,(corner>>2)&1)
		for axis in [1,2,4]:
			if corner&axis: continue
			var other: int=corner|axis
			lines.surface_add_vertex(a)
			lines.surface_add_vertex(box.position+box.size*Vector3(other&1,(other>>1)&1,(other>>2)&1))
	lines.surface_end();selection_outline.mesh=lines

func _size_ghost(node: Node3D,kind: String) -> void:
	var request: Dictionary={"kind":kind,"px":0.0,"pz":0.0,"turn":0}
	var extent: Vector2=Catalog.plot_rect(request).size
	for mesh in node.get_children():
		if mesh is MeshInstance3D and mesh.mesh is BoxMesh: mesh.mesh.size=Vector3(extent.x,0.22,extent.y)

func _ghost(kind: String) -> Node3D:
	if focus_ghost!=null and _focus_kind==kind: return focus_ghost
	if focus_ghost!=null: preview_root.remove_child(focus_ghost); focus_ghost.queue_free()
	if Catalog.is_kit(kind):
		focus_ghost=load(Catalog.RECIPES[kind].prefab).instantiate();focus_ghost.ghost=true
	elif kind=="deck": focus_ghost=World.Deck.instantiate(); focus_ghost.ghost=true
	else: focus_ghost=World.ghost_planter(); _size_ghost(focus_ghost,kind)
	preview_root.add_child(focus_ghost); _focus_kind=kind
	return focus_ghost

func _color(node: Node3D,invalid: bool,selected: bool) -> void:
	for mesh in node.find_children("*","MeshInstance3D",true,false):
		if mesh.material_override is StandardMaterial3D:
			mesh.material_override.albedo_color=Color(0.94,0.45,0.35,0.65 if selected else 0.22) if invalid else Color(0.52,0.95,0.78,0.68 if selected else 0.25)

func _clean(request: Dictionary) -> Dictionary:
	var result:=request.duplicate(true)
	for key in ["_operation","_target_id"]: result.erase(key)
	return result

func _operation_reason(request: Dictionary,operation: String,id: String) -> String:
	if operation=="move": return service.can_move(id,_clean(request))
	if operation=="remove": return service.can_remove(id)
	return service.can_place(_clean(request))

func _materials_reason(request: Dictionary) -> String:
	if not inventory_query.is_valid(): return ""
	var items: Dictionary=inventory_query.call()
	for id in Catalog.RECIPES[request.kind].cost:
		var need: int=Catalog.RECIPES[request.kind].cost[id]
		if int(items.get(id,0))<need:
			return "%s不足：需要%d，现有%d"%[preload("res://src/inventory/item_db.gd").label(id),need,int(items.get(id,0))]
	return ""

func _preview_reason(request: Dictionary,operation: String,id: String) -> String:
	var state: Dictionary=actor_state.call() if actor_state.is_valid() else {}
	var actor: Vector3=state.get("position",Vector3.ZERO)
	var items_hash:=hash(inventory_query.call()) if inventory_query.is_valid() else 0
	var key:=JSON.stringify(request)+operation+id+str(_revision)+str(items_hash)+str(state.get("mode",0))+str(Vector2(actor.x,actor.z).snapped(Vector2(0.2,0.2)))
	var now:=Time.get_ticks_msec()
	if _preview_cache.get("key","")==key and now-int(_preview_cache.get("at",0))<PREVIEW_CACHE_MS: return _preview_cache.reason
	var reason:=_operation_reason(request,operation,id)
	if reason=="" and operation=="build": reason=_materials_reason(request)
	if reason=="" and stand_point.is_valid():
		var stand: Vector3=stand_point.call(world.position_for(request))
		if not stand.is_finite(): reason="走不到施工位置；可先乘船靠近"
	_preview_cache={"key":key,"at":now,"reason":reason}
	return reason

func update_preview(screen: Vector2) -> void:
	preview={}; hovered_id=""
	if demolition.confirmation_open(): return
	var selecting: bool=recipe=="remove" or (recipe=="move" and moving_id=="")
	_seed_keyboard_cursor()
	if keyboard_mode:
		keyboard_cursor.y=Catalog.ORIGIN.y+build_level*Catalog.LAYER_HEIGHT
		if not selecting and not manual_level:
			var surface:=_point(camera.unproject_position(keyboard_cursor))
			if surface.is_finite(): keyboard_cursor.y=surface.y
	var point: Vector3=Catalog.ORIGIN if selecting else (keyboard_cursor if keyboard_mode else _point(screen))
	if not point.is_finite(): return
	var local:=Vector2(point.x-Catalog.ORIGIN.x,point.z-Catalog.ORIGIN.z)
	var operation:="build"; var reason:=""
	if Catalog.is_platform(recipe) and recipe!="deck":
		preview=Catalog.snap_foundation(recipe,local,turn,_rows_cache,_afloat(),point.y-Catalog.ORIGIN.y,0.01 if precision_held else 0.1,snap_assist)
		# 新平台与旧板共用船上独立起点资格；吸附位置不拥有施工来源。
		preview.origin="boat" if _afloat() else "shore"
	elif recipe=="deck":
		preview=Catalog.snap_deck(local,_rows_cache,_afloat(),point.y-Catalog.ORIGIN.y,0.01 if precision_held else 0.1,snap_assist,turn)
		preview.origin="boat" if _afloat() else "shore"
	elif _is_furnishing(recipe): preview=_furnishing_request(local,point.y-Catalog.ORIGIN.y)
	elif recipe=="move":
		operation="move"
		if moving_id=="":
			preview=service.row(keyboard_target_id) if keyboard_mode else _item_under_cursor(screen); hovered_id=str(preview.get("id",""))
			reason=""
			if not preview.is_empty():
				if float(preview.left)>0: reason="施工完成后才能搬移"
				elif not Catalog.RECIPES[preview.kind].get("movable",false): reason="此构件不能搬移，请先安全拆回再重新建造"
		else: preview=_furnishing_request(local,point.y-Catalog.ORIGIN.y)
	elif recipe=="remove":
		operation="remove"; preview=service.row(keyboard_target_id) if keyboard_mode else _item_under_cursor(screen); hovered_id=str(preview.get("id",""))
		if preview.is_empty(): reason=""
	if not preview.is_empty() and not (recipe=="move" and moving_id==""):
		reason=_preview_reason(preview,operation,moving_id if operation=="move" else hovered_id)
	var context_reason: String=service.context_reason()
	_hint_text=reason
	if context_reason!="": _hint_text=context_reason+"；请先关闭手册前往自建平台，或乘船靠近"
	_sync_view()
	if operation in ["move","remove"] and moving_id=="": _highlight(preview,reason!="" and not reason.begins_with("点击选取") and not reason.begins_with("Enter / E 选取"))
	else: _highlight({},false)
	for entry in candidate_ghosts:
		entry.node.visible=recipe=="deck" and Catalog.same_level(Catalog.elevation(preview),0.0) and moving_id==""
		_color(entry.node,bool(entry.get("invalid",false)),false)
	if not preview.is_empty() and (operation=="build" or (operation=="move" and moving_id!="")):
		var ghost:=_ghost(str(preview.kind));ghost.show();ghost.position=world.position_for(preview)
		ghost.rotation.y=int(preview.get("turn",0))*PI/2
		if str(Catalog.RECIPES[preview.kind].get("profile",""))=="stairs":
			ghost.scale.y=Catalog.stair_rise(preview)/float(Catalog.RECIPES[preview.kind].height)
		_color(ghost,reason!="",true)
	elif focus_ghost!=null: focus_ghost.hide()
	if recipe=="remove": demolition.set_target(preview,reason)

func handle_input(event: InputEvent) -> bool:
	if not active: return false
	if event.get_meta(INPUT_HANDLED_META,false): return true
	event.set_meta(INPUT_HANDLED_META,true)
	if event is InputEventKey:
		var code: int=event.physical_keycode if event.physical_keycode else event.keycode
		if code in [KEY_F5,KEY_F9]: return false
		if event.pressed: _held_keys[code]=true
		if code==KEY_SHIFT:
			precision_held=event.pressed;_preview_cache.clear()
			if not book.visible: _refresh_current_preview()
			return true
		if not event.pressed or event.echo: return true
		if demolition.confirmation_open():
			if code==KEY_ESCAPE:
				demolition.dismiss();_sync_view();return true
			if _submit_frame==Engine.get_process_frames(): return true
			_submit_frame=Engine.get_process_frames()
			demolition.handle_input(event);_sync_view();return true
		if code==KEY_ESCAPE:
			if not pending.is_empty():
				cancel_actor.call();_clear_pending();_refresh_current_preview()
			elif moving_id!="":
				moving_id="";preview={};_preview_cache.clear();_refresh_current_preview()
			elif book.visible: close()
			else: show_book()
		elif code==KEY_M:
			keyboard_mode=true;select_recipe("move")
		elif code==KEY_DELETE:
			keyboard_mode=true;select_recipe("remove")
		elif book.visible:
			keyboard_mode=true;_submit_frame=Engine.get_process_frames();book.handle_key(event)
		elif code in [KEY_ENTER,KEY_KP_ENTER,KEY_E]: submit_preview()
		elif code in [KEY_LEFT,KEY_A,KEY_RIGHT,KEY_D,KEY_UP,KEY_W,KEY_DOWN,KEY_S,KEY_TAB]:
			if not pending.is_empty(): return true
			if recipe=="remove" or (recipe=="move" and moving_id==""):
				_cycle_keyboard_target(-1 if code in [KEY_LEFT,KEY_A,KEY_UP,KEY_W] or (code==KEY_TAB and event.shift_pressed) else 1)
			elif code!=KEY_TAB:
				if not keyboard_mode and not preview.is_empty(): keyboard_cursor=world.position_for(preview)
				keyboard_mode=true;demolition.keyboard_mode=true;_seed_keyboard_cursor()
				var axis:=Vector2.ZERO
				if code in [KEY_LEFT,KEY_A]: axis=Vector2.LEFT
				elif code in [KEY_RIGHT,KEY_D]: axis=Vector2.RIGHT
				elif code in [KEY_UP,KEY_W]: axis=Vector2.UP
				else: axis=Vector2.DOWN
				keyboard_cursor+=_camera_direction(axis)*(0.01 if precision_held or event.shift_pressed else 0.1)
			_preview_cache.clear();_refresh_current_preview()
		elif code==KEY_R: _ui_action("rotate")
		elif code==KEY_U: _ui_action("level")
		elif code==KEY_G: _ui_action("snap")
		elif code==KEY_H: _ui_action("auto")
		_sync_view();return true
	if demolition.handle_input(event): return true
	if event is InputEventMouseMotion:
		if event.relative!=Vector2.ZERO: keyboard_mode=false;demolition.keyboard_mode=false
		return false
	if event is InputEventMouseButton:
		keyboard_mode=false;demolition.keyboard_mode=false
		if view.is_ui_point(event.position): return true
		if event.button_index==MOUSE_BUTTON_RIGHT:
			if event.pressed: show_book()
			return true
		if event.button_index!=MOUSE_BUTTON_LEFT: return false
		if event.pressed:
			precision_held=event.shift_pressed or Input.is_physical_key_pressed(KEY_SHIFT)
			submit_preview(event.position)
		return true
	return false

func _request_build(request: Dictionary) -> void:
	_request_action(request,"build","")

func _request_action(request: Dictionary,operation: String,id: String) -> void:
	var reason:=_operation_reason(request,operation,id)
	if reason=="" and operation=="build": reason=_materials_reason(request)
	if reason!="": hud.toast(reason); return
	var center: Vector3=world.position_for(request)
	var stand: Vector3=stand_point.call(center) if stand_point.is_valid() else center
	if not stand.is_finite(): hud.toast("走不到施工位置；可先乘船靠近"); return
	var state: Dictionary=actor_state.call() if actor_state.is_valid() else {}
	var at: Vector3=state.get("position",Vector3.INF)
	var action:=request.duplicate(true); action._operation=operation; action._target_id=id
	if at.is_finite() and not bool(state.get("walking",false)) and at.distance_to(stand)<=ARRIVE:
		_begin_now(action); return
	if not approach_point.is_valid() or not bool(approach_point.call(stand)): hud.toast("走不到施工位置，换个地方建"); return
	pending=action; pending_stand=stand
	var distance: float=Vector2(at.x-stand.x,at.z-stand.z).length() if at.is_finite() else 0.0
	pending_left=maxf(WAIT_LIMIT,distance/1.5+8.0); pending_age=0.0; preview=request.duplicate(true)
	_hint_text="施工中：正在接近施工位置";_sync_view()

func _begin_now(request: Dictionary) -> void:
	var operation:=str(request.get("_operation","build")); var id:=str(request.get("_target_id",""))
	_clear_pending()
	var result: Dictionary
	if operation=="move": result=service.move(id,_clean(request))
	elif operation=="remove": result=service.remove(id)
	else: result=service.begin(_clean(request))
	if not result.ok: hud.toast(result.reason); return
	if operation=="move": moving_id=""; hud.toast("已搬移，作物状态保留")
	elif operation=="remove": hud.toast("已拆回，材料已返还口袋")
	preview={}; hovered_id=""; _preview_cache.clear()

func _clear_pending() -> void:
	pending={}; pending_stand=Vector3.INF; pending_left=0.0; pending_age=0.0

func _sync_pending(delta: float) -> void:
	if pending.is_empty(): return
	pending_left-=delta; pending_age+=delta
	var state: Dictionary=actor_state.call() if actor_state.is_valid() else {}
	var at: Vector3=state.get("position",Vector3.INF); var walking:=bool(state.get("walking",true))
	var near:=at.is_finite() and at.distance_to(pending_stand)<=ARRIVE
	if near and not walking: _begin_now(pending.duplicate(true)); return
	if pending_left<=0.0 or (not walking and pending_age>0.4): _clear_pending(); preview={}; hud.toast("没到施工位置，已取消")

func tick(delta: float) -> void:
	service.tick(delta); _place_book(); _sync_pending(delta)
	if active and not book.visible:
		if service.context_reason()!="" and recipe not in ["move","remove"]: close()
		elif pending.is_empty():
			_frontier_refresh_left-=delta
			if recipe=="deck" and _frontier_refresh_left<=0: _refresh_ghosts()
			_refresh_current_preview()
		else: _hint_text="施工中：正在接近施工位置";_sync_view()
	progress_presenter.sync(_working_ids,service,world,camera,overlay)
	progress=progress_presenter.progress
