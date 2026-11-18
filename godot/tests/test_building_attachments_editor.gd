@tool
extends RefCounted
## GUI输入与直接调用分开记证据；只覆盖首个3D视口，不声称人工验收。
const Recipe = preload("res://src/building_attachments/recipe.gd")
const BuildingRecipe = preload("res://src/workshop/recipe.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const BuildingStore = preload("res://addons/building_workshop/editor_store.gd")
const Library = preload("res://addons/scene_assembly/library.gd")
const Surface = preload("res://addons/scene_assembly/attachment_surface.gd")
const AttachmentGenerator = preload("res://src/building_attachments/generator.gd")
const AttachmentController = preload("res://addons/scene_assembly/attachment_controller.gd")
const AttachmentCatalog = preload("res://src/building_attachments/catalog.gd")
var plugin: EditorPlugin
var controller: Node
var panel: Control
var checks := 0
var failures: Array[String] = []
var evidence: Dictionary = {"gui_input": [], "direct_calls": [], "layouts": [], "screenshots": [], "scope": "首个3D视口；非人工；不覆盖原生gizmo拖轴"}
var previous_on_top := false
var fixture := "res://outputs/building_attachments_editor_fixture.tscn"

static func run(p: EditorPlugin) -> void:
	var suite = load("res://tests/test_building_attachments_editor.gd").new()
	suite.plugin = p
	await suite.execute()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL [building-attachments-editor] ", label)

func frames(count: int = 5) -> void:
	for i: int in count: await plugin.get_tree().process_frame

func select(node: Node) -> void:
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(node)

func mouse(point: Vector2, pressed: bool, motion: bool = false) -> void:
	plugin.dock.get_viewport().warp_mouse(point)
	var event: InputEventMouse
	if motion:
		var move := InputEventMouseMotion.new()
		move.relative = Vector2(12, 8)
		move.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event = move
	else:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event = button
	event.window_id = plugin.get_window().get_window_id()
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)

func reveal(control: Control) -> void:
	var child: Node = control
	while child.get_parent() != null:
		var parent := child.get_parent()
		if parent is TabContainer: parent.current_tab = child.get_index()
		if parent is ScrollContainer:
			parent.ensure_control_visible(control)
			await frames(3)
			parent.ensure_control_visible(control)
		child = parent
	await frames()

func click(control: Control) -> void:
	await reveal(control)
	var rect := control.get_global_rect()
	check(control.is_visible_in_tree() and rect.size.x > 8 and rect.size.y > 8, "真实Control可见非零尺寸：" + str(control.name))
	var point: Vector2 = rect.get_center()
	mouse(point, false, true)
	await frames(2)
	var hovered: Control = control.get_viewport().gui_get_hovered_control()
	check(hovered == control or (hovered != null and control.is_ancestor_of(hovered)), "真实GUI悬停目标：%s rect=%s hovered=%s" % [control.name, str(rect), str(hovered.get_path()) if hovered != null else "null"])
	mouse(point, true)
	await frames(2)
	mouse(point, false)
	await frames(4)
	evidence.gui_input.append({"control": str(control.get_path()), "position": str(point), "size": str(rect.size), "method": "Input.parse_input_event_mouse"})

func button(text: String) -> Button:
	for child: Node in panel.find_children("*", "Button", true, false):
		if child.text == text: return child
	return null

func press(text: String) -> void:
	var control := button(text)
	check(control != null, "按钮存在：" + text)
	if control != null: await click(control)

func choose_type(type_id: String) -> void:
	await press("图库")
	# 搜索文本赋值仅作为fixture准备；图库选择必须走真实mouse按下/释放。
	panel.search.text = type_id
	panel.refresh_gallery()
	await frames(8)
	check(panel.gallery.item_count == 1, "图库搜索唯一：" + type_id)
	if panel.gallery.item_count != 1: return
	await reveal(panel.gallery)
	var point: Vector2 = panel.gallery.global_position + panel.gallery.get_item_rect(0).get_center()
	mouse(point, false, true)
	await frames(2)
	check(panel.gallery.get_viewport().gui_get_hovered_control() == panel.gallery, "图库真实悬停：" + type_id)
	mouse(point, true)
	await frames(2)
	mouse(point, false)
	await frames(5)
	check(panel.draft.type_id == type_id and panel.gallery.is_visible_in_tree(), "真实Gallery单击选中且拖放源保持可见：" + type_id)
	await press("编辑组件")
	check(panel.editor_panel.is_visible_in_tree(), "真实编辑组件按钮进入编辑：" + type_id)
	evidence.gui_input.append({"type_id": type_id, "method": "gallery_mouse_press_release", "point": str(point)})

func surface_point(mode: String) -> Vector2:
	var surface: Control = plugin.surfaces[0]
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var camera := viewport.get_camera_3d()
	for y: int in range(10, 91, 4):
		for x: int in range(10, 91, 4):
			var fraction := Vector2(x / 100.0, y / 100.0)
			var local := fraction * Vector2(viewport.size)
			var hit: Dictionary = Surface.raycast(controller.host_asset, camera.project_ray_origin(local), camera.project_ray_normal(local), mode)
			if hit.ok and controller.validate_installation(panel.input_recipe(), hit).ok:
				return surface.global_position + fraction * surface.size
	return Vector2(-1, -1)

func place_gui(type_id: String, mode: String) -> Node3D:
	await choose_type(type_id)
	await press("贴到宿主")
	await frames(5)
	check(controller.armed and plugin.surfaces[0].visible, "真实贴面按钮启用接收层：" + type_id)
	var point: Vector2 = surface_point(mode)
	check(point.x >= 0, "首视口找到真实" + mode + "面：" + type_id)
	if point.x < 0: return null
	mouse(point, false, true)
	await frames(6)
	check(bool(plugin.surfaces[0]._preview_ok), "真实输入触发有效表面预览：" + type_id)
	mouse(point, true)
	await frames(2)
	mouse(point, false)
	await frames(8)
	check(not controller.armed and not plugin.surfaces[0].visible, "放置后释放原生编辑器输入：" + type_id)
	var selected: Node3D = controller.selected
	check(selected != null and selected.has_meta("sea_attachment"), "真实surface click新增：" + type_id)
	evidence.gui_input.append({"type_id": type_id, "method": "surface_mouse_click", "mode": mode, "point": str(point)})
	return selected

func screenshot(label: String) -> void:
	await frames(8)
	var path := "res://outputs/building_attachments_editor_" + label + ".png"
	var image := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	check(image != null and image.save_png(path) == OK, "真实Editor截图：" + label)
	evidence.screenshots.append(ProjectSettings.globalize_path(path))

func test_arm_atomicity(host: Node3D, sibling: Node3D, layer: Node3D) -> void:
	var target: Node3D = controller.selected
	var before_count: int = layer.get_child_count()
	var before_transform: Transform3D = target.transform
	var before_metadata: Dictionary = target.get_meta("sea_attachment").duplicate(true)
	var recipe: Dictionary = before_metadata.recipe
	var first: Dictionary = controller.arm(recipe)
	check(first.ok and controller.validate_arm(first.token).ok, "arm锁定当前root/host/target有效")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await frames(5)
	check(not controller.armed and layer.get_child_count() == before_count, "真实Escape取消无场景改动")
	var armed: Dictionary = controller.arm(recipe)
	check(armed.ok, "重新启用贴面")
	select(sibling)
	await frames(5)
	check(not controller.armed and not controller.validate_arm(armed.token).ok, "另选兄弟取消旧事务/token")
	select(target)
	await frames()
	armed = controller.arm(recipe)
	check(armed.ok, "变换过期夹具arm")
	host.position.x += 0.125
	var stale: Dictionary = controller.validate_arm(armed.token)
	check(not stale.ok and not controller.armed, "宿主变换改变拒绝陈旧贴面")
	host.position.x -= 0.125
	armed = controller.arm(recipe)
	check(armed.ok, "metadata过期夹具arm")
	var metadata: Dictionary = target.get_meta("sea_attachment").duplicate(true)
	metadata.host_revision = "qa_stale"
	target.set_meta("sea_attachment", metadata)
	stale = controller.validate_arm(armed.token)
	check(not stale.ok and not controller.armed, "目标metadata改变拒绝陈旧贴面")
	target.set_meta("sea_attachment", before_metadata)
	check(target.transform == before_transform and layer.get_child_count() == before_count, "cancel/stale全部保持原节点与变换")
	var failed: Dictionary = controller.insert_at_ray(recipe, Vector3(10000, 10000, 10000), Vector3.UP)
	check(not failed.ok and layer.get_child_count() == before_count and target.get_meta("sea_attachment") == before_metadata, "真实miss射线拒绝且failure atomic")
	evidence.direct_calls.append("arm/validate_arm变换metadata过期负例与miss射线；取消Escape/选择走真实编辑器事件")

func fixture_mesh(parent: Node3D, name: String, faces: Array, material: Material = null) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	for face: Array in faces:
		for point: Vector3 in face: vertices.append(point)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material != null: mesh.surface_set_material(0, material)
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	parent.add_child(node)
	return node

func roof_faces(x0: float, x1: float, z0: float, z1: float) -> Array:
	# 独立数学约定：Godot顺时针，(c-a)x(b-a)=+Y。
	return [[Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1)], [Vector3(x0, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]]

func test_material_and_support(scene: Node3D) -> void:
	var host := Node3D.new()
	scene.add_child(host)
	var wall := [[Vector3(-2, -2, 0), Vector3(2, -2, 0), Vector3(0, 2, 0)]]
	var mesh: MeshInstance3D = fixture_mesh(host, "CullFixture", wall)
	for material_kind: String in ["standard", "shader"]:
		for cull: String in ["back", "front", "disabled"]:
			var material: Material
			if material_kind == "standard":
				var standard := StandardMaterial3D.new()
				standard.cull_mode = BaseMaterial3D.CULL_BACK if cull == "back" else BaseMaterial3D.CULL_FRONT if cull == "front" else BaseMaterial3D.CULL_DISABLED
				material = standard
			else:
				var shader := Shader.new()
				shader.code = "shader_type spatial; render_mode cull_%s;" % cull
				var shader_material := ShaderMaterial.new()
				shader_material.shader = shader
				material = shader_material
			mesh.material_override = material
			for side: int in [-1, 1]:
				var expected: bool = cull == "disabled" or (side == -1 if cull == "back" else side == 1)
				var hit: Dictionary = Surface.raycast(host, Vector3(0, 0, side * 2), Vector3(0, 0, -side), "wall")
				check(hit.ok == expected, "独立三角单双面期望：%s/%s/side%d" % [material_kind, cull, side])
				if hit.ok: check(hit.normal.is_equal_approx(Vector3(0, 0, side)), "可见面法线朝观察侧")
	mesh.free()
	var recipe: Dictionary = Recipe.defaults("tank_rect")
	var built: Dictionary = AttachmentGenerator.build(recipe)
	check(built.ok, "屋顶安装夹具真实heavy构建")
	if built.ok:
		var profile: Dictionary = Surface.installation_profile(built, "roof")
		check(profile.ok and profile.points.size() == 12, "四脚各三真实三角采样共12支点")
		var roof: MeshInstance3D = fixture_mesh(host, "RoofFixture", roof_faces(-4, 4, -4, 4))
		var pose := Transform3D(Basis.IDENTITY, Vector3(0, 0.012, 0))
		check(Surface.validate_installation(host, profile, pose, Vector3.UP, "roof", 0.012).ok, "独立宽平屋顶完整支撑正例")
		check(not Surface.validate_installation(host, profile, Transform3D(Basis.IDENTITY, Vector3(3.8, 0.012, 0)), Vector3.UP, "roof", 0.012).ok, "中心在屋顶但边缘脚悬空拒绝")
		roof.free()
		roof = fixture_mesh(host, "NarrowBeam", roof_faces(-0.12, 0.12, -4, 4))
		check(not Surface.validate_installation(host, profile, pose, Vector3.UP, "roof", 0.012).ok, "中心窄梁命中但四脚无承托拒绝")
		roof.free()
		var foot: Vector3 = profile.points[0]
		var hole_faces: Array = roof_faces(-4, foot.x - 0.1, -4, 4)
		hole_faces.append_array(roof_faces(foot.x + 0.1, 4, -4, 4))
		hole_faces.append_array(roof_faces(foot.x - 0.1, foot.x + 0.1, -4, foot.z - 0.1))
		hole_faces.append_array(roof_faces(foot.x - 0.1, foot.x + 0.1, foot.z + 0.1, 4))
		roof = fixture_mesh(host, "FootHole", hole_faces)
		check(not Surface.validate_installation(host, profile, pose, Vector3.UP, "roof", 0.012).ok, "中心可命中但脚下洞拒绝")
		roof.free()
		roof = fixture_mesh(host, "RoofWithAdjacentWall", roof_faces(-4, 4, -4, 4))
		var cross_wall := fixture_mesh(host, "IntersectingWall", [[Vector3(-4, 0.1, 0.65), Vector3(4, 0.1, 0.65), Vector3(4, 3, 0.65)], [Vector3(-4, 0.1, 0.65), Vector3(4, 3, 0.65), Vector3(-4, 3, 0.65)]])
		check(not Surface.validate_installation(host, profile, pose, Vector3.UP, "roof", 0.012).ok, "四脚有承托但邻墙穿过水箱实体拒绝")
		cross_wall.free()
		roof.free()
		var invalid: Dictionary = built.duplicate()
		invalid.mount_anchor = built.mount_anchor.duplicate(true)
		invalid.mount_anchor.basis[0] = 2
		check(not AttachmentController.anchor_error(invalid).is_empty(), "非单位anchor basis明确拒绝")
		built.root.free()
	host.owner = scene
	var any_wall := fixture_mesh(host, "AnyWall", [[Vector3(-5, -5, 0), Vector3(5, -5, 0), Vector3(5, 5, 0)], [Vector3(-5, -5, 0), Vector3(5, 5, 0), Vector3(-5, 5, 0)]])
	check(controller.set_host(host).ok, "any挂载夹具宿主锁定")
	controller.set_mount_options("wall")
	var any_recipe: Dictionary = Recipe.defaults("sign_letters")
	var any_inserted: Dictionary = controller.insert_at_ray(any_recipe, Vector3(0, 0, -10), Vector3.BACK)
	check(any_inserted.ok, "any实际墙面挂载正例：" + str(any_inserted.get("reason", "")))
	if any_inserted.ok:
		var original_any: Node3D = any_inserted.attachment
		var original_transform: Transform3D = original_any.transform
		controller.set_mount_options("roof")
		var refused: Dictionary = controller.edit_selected_recipe({"text": "OLD HARBOR"})
		check(not refused.ok and controller.selected == original_any and original_any.transform == original_transform, "any墙转屋顶apply拒绝且模型原子不改")
		any_wall.free()
		var any_roof := fixture_mesh(host, "AnyRoof", roof_faces(-5, 5, -5, 5))
		var reprojected: Dictionary = controller.reproject_selected(Vector3(0, 10, 0), Vector3.DOWN)
		check(reprojected.ok and reprojected.attachment.get_meta("sea_attachment").anchor.mode == "roof", "any必须显式重贴新屋顶")
		any_roof.free()
		controller.delete_selected()
	else: any_wall.free()
	host.set_meta("sea_placement", {"kind": "building", "revision": "qa"})
	var old_asset := Node3D.new()
	old_asset.name = "Asset"
	host.add_child(old_asset)
	old_asset.owner = scene
	check(controller.set_host(host).ok, "独立宿主Asset刷新夹具锁定")
	old_asset.free()
	var next_asset := Node3D.new()
	next_asset.name = "Asset"
	host.add_child(next_asset)
	next_asset.owner = scene
	check(controller._check_host().is_empty() and controller.host_asset == next_asset, "旧Asset已free仍先刷新新Asset再验证")
	host.free()
	evidence.direct_calls.append("独立单三角材质cull数学期望/12支点宽屋顶正例及边缘窄梁脚洞邻墙穿透负例，非GUI")

func key_event(code: Key, unicode_value: int = 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.unicode = unicode_value
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)

func test_input_cancels() -> void:
	await choose_type("sign_letters")
	var baseline: Dictionary = panel.input_recipe()
	for field: String in ["text", "condition", "size", "collider", "mode"]:
		panel._load_inputs(baseline, {"mode": "wall"})
		await frames(3)
		var armed: Dictionary = controller.arm(panel.input_recipe())
		check(armed.ok, "input变化前arm：" + field)
		if field == "text":
			await click(panel.text_input)
			key_event(KEY_X, 88)
		elif field == "condition": await click(panel.choices.condition.buttons.damaged)
		elif field == "collider": await click(panel.collision)
		elif field == "mode": await click(panel.choices.mount_mode.buttons.roof)
		else:
			await click(panel.fields.scale.slider)
			key_event(KEY_RIGHT)
		await frames(5)
		check(not controller.armed, "真实GUI输入改变取消旧贴面：" + field)
		var input_changed: bool = panel.input_recipe() != baseline or panel.choices.mount_mode.value != "wall"
		check(input_changed, "取消后真实新输入保留：" + field)
		panel._load_inputs(baseline, {"mode": "wall"})
	evidence.gui_input.append({"method": "真实mouse/keyboard改变text condition scale collider mount_mode，取消arm保留输入"})

func test_attachment_color_editor() -> void:
	await choose_type("sign_fascia")
	var sign_before: Dictionary = panel.input_recipe()
	var sign_button: Button = panel.color_role_buttons.get("SEA_Matte")
	var sign_cell: Button = panel.color_buttons.get(3)
	check(sign_button != null and sign_cell != null and panel.color_grid.columns == 8, "招牌颜色编辑器角色与64格色板存在")
	if sign_button != null: await click(sign_button)
	if sign_cell != null: await click(sign_cell)
	var sign_after: Dictionary = panel.input_recipe()
	check(int(sign_after.colors.get("SEA_Matte", -1)) == 3 and sign_after.type_id == "sign_fascia", "招牌可实际选择PaletteUV色格")
	check(sign_after.dimensions == sign_before.dimensions and sign_after.text == sign_before.text, "招牌换色不改尺寸或文字")
	await choose_type("awning_slope")
	var canopy_before: Dictionary = panel.input_recipe()
	var metal_button: Button = panel.color_role_buttons.get("SEA_Metal")
	var metal_cell: Button = panel.color_buttons.get(21)
	check(metal_button != null and metal_cell != null, "顶棚颜色编辑器角色按钮与色格存在")
	if metal_button != null: await click(metal_button)
	if metal_cell != null: await click(metal_cell)
	var canopy_after: Dictionary = panel.input_recipe()
	check(int(canopy_after.colors.get("SEA_Metal", -1)) == 21 and canopy_after.type_id == "awning_slope", "顶棚可实际选择PaletteUV色格")
	check(canopy_after.dimensions == canopy_before.dimensions and canopy_after.condition == canopy_before.condition, "顶棚换色不改尺寸或状态")
	evidence.gui_input.append({"method": "real color role/cell clicks", "types": ["sign_fascia", "awning_slope"], "sign_matte": sign_after.colors.get("SEA_Matte"), "canopy_metal": canopy_after.colors.get("SEA_Metal")})

func test_gallery_drag() -> void:
	var original_host: Node3D = controller.host_container
	var scene: Node3D = EditorInterface.get_edited_scene_root()
	var camera := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	var test_host := Node3D.new()
	test_host.name = "GalleryDragSolidWall"
	scene.add_child(test_host)
	test_host.owner = scene
	var center: Vector3 = camera.global_position - camera.global_basis.z * 15.0
	var outward: Vector3 = Vector3(camera.global_basis.z.x, 0, camera.global_basis.z.z).normalized()
	var z: Vector3 = -outward
	test_host.global_transform = Transform3D(Basis(Vector3.UP.cross(z).normalized(), Vector3.UP, z), center)
	var material := StandardMaterial3D.new()
	material.cull_mode = BaseMaterial3D.CULL_BACK
	fixture_mesh(test_host, "ActualSolidWall", [[Vector3(-10, -10, 0), Vector3(10, -10, 0), Vector3(10, 10, 0)], [Vector3(-10, -10, 0), Vector3(10, 10, 0), Vector3(-10, 10, 0)]], material)
	select(test_host)
	check(controller.set_host(test_host).ok, "真实Gallery拖放正例锁定可见20m实体墙")
	await choose_type("sign_fascia")
	panel.fields.offset.slider.value = 0.03
	panel.fields.angle.slider.value = 7.0
	await press("图库")
	await click(panel.choices.gallery_condition.buttons.damaged)
	panel.search.text = "sign_fascia"
	panel.refresh_gallery()
	await frames(8)
	await reveal(panel.gallery)
	var start: Vector2 = panel.gallery.global_position + panel.gallery.get_item_rect(0).position + Vector2(24, 20)
	mouse(start, false, true)
	await frames(2)
	mouse(start, true)
	await frames(2)
	mouse(start + Vector2(32, 12), true, true)
	await frames(4)
	check(panel.get_viewport().gui_is_dragging(), "真实Gallery mouse motion启动拖放")
	check(controller.armed_recipe.get("condition") == "damaged" and is_equal_approx(controller.offset, 0.03) and is_equal_approx(controller.angle_degrees, 7.0), "prepare_drag同步condition/offset/angle")
	var surface: Control = plugin.surfaces[0]
	var end := Vector2(-1, -1)
	# 拖放保持按住，使用实际接收层绿色ghost确认位置，不把预测命中代替GUI命中。
	for y: int in range(10, 91, 4):
		if end.x >= 0: break
		for x: int in range(10, 91, 4):
			var candidate: Vector2 = surface.global_position + surface.size * Vector2(x / 100.0, y / 100.0)
			mouse(candidate, true, true)
			await frames(2)
			if surface._preview_ok:
				end = candidate
				break
	check(end.x >= 0, "真实拖放找到满足安装门禁的墙面")
	if end.x < 0:
		key_event(KEY_ESCAPE)
		controller.set_host(original_host)
		select(original_host)
		test_host.free()
		return
	surface.set_meta("drop_seen", false)
	surface.set_meta("can_drop_seen", false)
	mouse(end, true, true)
	await frames(4)
	var hovered: Control = panel.get_viewport().gui_get_hovered_control()
	var drag_detail := {"before_release": {"dragging": panel.get_viewport().gui_is_dragging(), "armed": controller.armed, "can_drop_seen": surface.get_meta("can_drop_seen", false), "surface_visible": surface.visible, "surface_rect": str(surface.get_global_rect()), "hovered": str(hovered.get_path()) if hovered != null else "null", "status": panel.status.tooltip_text, "preview_ok": surface._preview_ok}}
	check(bool(surface.get_meta("can_drop_seen", false)), "真实Gallery移动触发surface can_drop")
	mouse(end, false)
	await frames(8)
	drag_detail.after_release = {"dragging": panel.get_viewport().gui_is_dragging(), "armed": controller.armed, "drop_seen": surface.get_meta("drop_seen", false), "selected": str(controller.selected), "status": panel.status.tooltip_text}
	evidence.gallery_drag_detail = drag_detail
	print("[gallery-drag-detail] ", JSON.stringify(drag_detail))
	check(bool(surface.get_meta("drop_seen", false)) and controller.selected != null, "真实Gallery释放经过surface drop：" + JSON.stringify(drag_detail))
	if controller.selected != null:
		check(controller.selected.get_meta("sea_attachment").recipe.condition == "damaged", "实际新增节点消费损坏状态")
		controller.delete_selected()
	controller.cancel_arm(false)
	plugin.get_undo_redo().clear_history()
	controller.set_host(original_host)
	select(original_host)
	test_host.free()
	await choose_type("sign_fascia")
	panel.fields.offset.slider.value = 0.0
	panel.fields.angle.slider.value = 0.0
	panel._choice_value("condition", "fresh")
	panel.gallery_condition = "fresh"
	panel._choice_value("gallery_condition", "fresh")
	evidence.gui_input.append({"method": "gallery mouse drag/drop", "start": str(start), "end": str(end)})

func test_all_mounts(scene: Node3D) -> void:
	var rows: Array[Dictionary] = []
	var host := Node3D.new()
	host.name = "AllMountFixture"
	scene.add_child(host)
	host.owner = scene
	var material := StandardMaterial3D.new()
	material.cull_mode = BaseMaterial3D.CULL_BACK
	var wall_faces: Array = [[Vector3(-10, -10, 0), Vector3(10, -10, 0), Vector3(10, 10, 0)], [Vector3(-10, -10, 0), Vector3(10, 10, 0), Vector3(-10, 10, 0)]]
	for entry: Dictionary in AttachmentCatalog.entries():
		var modes: Array = ["wall", "roof"] if entry.mount_mode == "any" else [str(entry.mount_mode)]
		for condition: String in AttachmentCatalog.CONDITIONS:
			for mode: String in modes:
				var row := {"type_id": entry.type_id, "condition": condition, "mode": mode, "profile_ok": false, "installation_ok": false, "insert_ok": false, "delete_undo_ok": false, "reason": ""}
				var mesh := fixture_mesh(host, "MountPlane", wall_faces if mode == "wall" else roof_faces(-10, 10, -10, 10), material)
				var recipe: Dictionary = Recipe.defaults(entry.type_id)
				recipe.condition = condition
				controller.set_host(host)
				controller.set_mount_options(mode, 0.0, 0.0)
				var built: Dictionary = AttachmentGenerator.build(recipe)
				if built.ok:
					var profile: Dictionary = Surface.installation_profile(built, mode)
					row.profile_ok = profile.ok
					row.reason = profile.reason
					row.support_points = profile.get("points", []).size()
					var origin := Vector3(0, 0, -10) if mode == "wall" else Vector3(0, 10, 0)
					var direction := Vector3.BACK if mode == "wall" else Vector3.DOWN
					var hit: Dictionary = Surface.raycast(host, origin, direction, mode)
					if profile.ok and hit.ok:
						var installation: Dictionary = controller.validate_installation(recipe, hit, built)
						row.installation_ok = installation.ok
						row.reason = installation.reason
						row.support_checks = installation.get("support_checks", 0)
						if installation.ok:
							var inserted: Dictionary = controller.insert_at_ray(recipe, origin, direction)
							row.insert_ok = inserted.ok
							row.reason = inserted.reason
							if inserted.ok:
								var node: Node3D = inserted.attachment
								var history := plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(scene))
								var deleted: Dictionary = controller.delete_selected()
								var removed: bool = not node.is_inside_tree()
								history.undo()
								row.delete_undo_ok = deleted.ok and removed and node.is_inside_tree() and node.owner == scene
								history.redo()
								plugin.get_undo_redo().clear_history()
					built.root.free()
				else: row.reason = built.reason
				var passed: bool = row.profile_ok and row.installation_ok and row.insert_ok and row.delete_undo_ok
				row.passed = passed
				check(passed, "全类型实际挂载 %s/%s/%s：%s" % [entry.type_id, condition, mode, row.reason])
				rows.append(row)
				mesh.free()
				var layer := host.get_node_or_null("Attachments")
				if layer != null: layer.free()
				controller.selected = null
				print("[all-mount] ", JSON.stringify(row))
				var partial := FileAccess.open("res://outputs/building_attachments_all_mounts.json", FileAccess.WRITE)
				partial.store_string(JSON.stringify({"rows": rows, "actual_cases": rows.size()}, "\t", true, true))
				partial.close()
	evidence.all_mounts = rows
	evidence.all_mount_case_count = rows.size()
	host.free()
	print("[attachments-editor-stage] all mounts complete cases=", rows.size())

func execute() -> void:
	if not str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sea-verification/") or FileAccess.file_exists("res://scenes/main.tscn"):
		plugin.get_tree().quit(1)
		return
	controller = plugin.attachment_controller
	panel = plugin.attachment_panel
	previous_on_top = plugin.get_window().always_on_top
	plugin.get_window().always_on_top = true
	DisplayServer.window_move_to_foreground(plugin.get_window().get_window_id())
	plugin.get_window().grab_focus()
	check(Engine.is_editor_hint() and not EditorInterface.is_playing_scene(), "真实Editor非Play")
	var recipe: Dictionary = BuildingRecipe.authoring_defaults()
	recipe.building_id = "attachments_editor_house"
	var original_recipe: String = JSON.stringify(recipe, "", true, true)
	var house: Dictionary = BuildingStore.new().export_revision(recipe, Catalog.editor_catalog({}), "res://scenes/workshop_buildings")
	check(house.get("ok", false), "建筑fixture真实Store保存")
	if not house.get("ok", false):
		await finish()
		return
	var house_hash := FileAccess.get_sha256(house.recipe_path)
	var scene := Node3D.new()
	scene.name = "AttachmentEditorFixture"
	var light := DirectionalLight3D.new()
	scene.add_child(light)
	light.owner = scene
	light.rotation_degrees = Vector3(-40, -30, 0)
	var packed := PackedScene.new()
	packed.pack(scene)
	ResourceSaver.save(packed, fixture)
	scene.free()
	EditorInterface.open_scene_from_path(fixture)
	EditorInterface.set_main_screen_editor("3D")
	await frames(20)
	scene = EditorInterface.get_edited_scene_root()
	await test_all_mounts(scene)
	if not failures.is_empty():
		await finish()
		return
	await test_material_and_support(scene)
	var inserted: Dictionary = plugin.insert_candidate(Library.describe(house.recipe_path, "building"), Vector3.ZERO)
	check(inserted.get("ok", false), "直接调用准备建筑Placement，非GUI宣称")
	if not inserted.get("ok", false):
		await finish()
		return
	var host: Node3D = inserted.placement
	var sibling_result: Dictionary = plugin.insert_candidate(Library.describe(house.recipe_path, "building"), Vector3(30, 0, 0))
	var sibling: Node3D = sibling_result.placement
	var sibling_transform: Transform3D = sibling.transform
	var sibling_path: String = sibling.get_node("Asset").scene_file_path
	select(host)
	EditorInterface.set_main_screen_editor("3D")
	await frames(8)
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var focus := InputEventKey.new()
	focus.keycode = KEY_F
	focus.physical_keycode = KEY_F
	focus.pressed = true
	mouse(plugin.surfaces[0].global_position + plugin.surfaces[0].size * 0.5, false, true)
	Input.parse_input_event(focus)
	await plugin.get_tree().create_timer(1.0).timeout
	focus.pressed = false
	Input.parse_input_event(focus)
	await frames(12)
	evidence.direct_calls.append("fixture export/insert only; framing通过F输入；表面坐标只用真实camera投射寻找")
	plugin._show_attachment_page(true)
	await reveal(panel)
	await press("锁定选中节点为宿主")
	check(controller.host_container == host and controller.host_asset == host.get_node("Asset"), "宿主锁定真实建筑Asset")
	await test_input_cancels()
	await test_attachment_color_editor()
	await test_gallery_drag()
	var sign: Node3D = await place_gui("sign_fascia", "wall")
	if sign == null:
		await screenshot("failed_sign")
		await finish()
		return
	var sign_name := sign.name
	await click(panel.choices.condition.buttons.damaged)
	await press("应用到选中外挂")
	check(controller.selected.get_meta("sea_attachment").recipe.condition == "damaged", "真实状态按钮应用")
	var history := plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(scene))
	history.undo()
	await frames()
	check(controller.selected.get_meta("sea_attachment").recipe.condition == "fresh", "undo恢复原状态节点")
	history.redo()
	await frames()
	check(controller.selected.get_meta("sea_attachment").recipe.condition == "damaged", "redo恢复损坏节点")
	var before_bad: Node3D = controller.selected
	panel.text_input.text = "BAD中文"
	panel.text_input.text_changed.emit(panel.text_input.text)
	await press("应用到选中外挂")
	check(controller.selected == before_bad and panel.text_input.text == "BAD中文" and panel.status.text.contains("不支持"), "非法文字明确失败保留输入和原节点")
	panel.text_input.text = "SEA MARKET"
	panel.text_input.text_changed.emit(panel.text_input.text)
	await press("应用到选中外挂")
	check(controller.selected.get_meta("sea_attachment").recipe.text == "SEA MARKET", "真实按钮提交新字形")
	var tank: Node3D = await place_gui("tank_rect", "roof")
	if tank == null:
		await screenshot("failed_tank")
		await finish()
		return
	check(tank.get_meta("sea_attachment").recipe.collision_enabled, "重水箱默认碰撞true")
	var layer: Node3D = host.get_node("Attachments")
	check(layer.get_child_count() == 2 and layer.get_script() == null, "独立兄弟附件层两类型")
	await test_arm_atomicity(host, sibling, layer)
	var transforms: Dictionary = {}
	for node: Node3D in layer.get_children(): transforms[str(node.name)] = node.transform
	check(FileAccess.get_sha256(house.recipe_path) == house_hash and JSON.stringify(recipe, "", true, true) == original_recipe, "附件操作不改房屋recipe字节/输入")
	await press("保存独立候选新修订")
	var candidate_path: String = panel.candidate_path.text
	check(not candidate_path.is_empty() and FileAccess.file_exists(candidate_path), "真实候选保存按钮：" + str(panel.status.tooltip_text))
	await press("校验并打开候选 JSON")
	check(panel.input_recipe().type_id == "tank_rect", "真实候选JSON重开按钮")
	check(EditorInterface.save_scene() == OK, "Editor手动保存隔离fixture")
	await screenshot("two_types")
	# 两个工坊桥接由直接调用验证，明确不冒充GUI完整操作。
	print("[attachments-editor-stage] building bridge open")
	select(host)
	plugin.edit_selected()
	var screen: Control = plugin.bridges.building.screen
	if screen._confirm.visible:
		screen._confirm.hide()
		screen._confirm.confirmed.emit()
	await frames(10)
	check(not plugin.binding.is_empty() and plugin.binding.kind == "building", "建筑桥接建立绑定")
	var token: int = plugin.binding.get("token", -1)
	select(sibling)
	print("[attachments-editor-stage] building bridge save")
	var saved: Dictionary = screen.save_building()
	print("[attachments-editor-stage] building bridge saved")
	check(saved.get("ok", false) and host.get_node("Asset").scene_file_path != house.scene_path, "建筑换版只更新绑定宿主")
	check(plugin.binding.get("token", -2) == token, "选择兄弟不劫持绑定")
	check(sibling.transform == sibling_transform and sibling.get_node("Asset").scene_file_path == sibling_path, "兄弟建筑路径和变换保持")
	check(host.get_node("Attachments") == layer and layer.get_child_count() == 2, "房屋换版保留独立外挂siblings")
	for node: Node3D in layer.get_children(): check(node.transform == transforms[str(node.name)], "换版附件变换保持：" + str(node.name))
	check(FileAccess.get_sha256(house.recipe_path) == house_hash, "房屋旧配方不覆盖")
	evidence.direct_calls.append("建筑edit_selected/save_building桥接/绑定/sibling断言；非GUI")
	print("[attachments-editor-stage] bridge assertions done, switching 3D")
	EditorInterface.set_main_screen_editor("3D")
	print("[attachments-editor-stage] switching attachment page")
	plugin._show_attachment_page(true)
	print("[attachments-editor-stage] selecting sign")
	select(layer.get_node(NodePath(str(sign_name))))
	print("[attachments-editor-stage] waiting selection frames")
	await frames(8)
	print("[attachments-editor-stage] layout loop")
	for size: Vector2i in [Vector2i(1280, 800), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		print("[attachments-editor-stage] resize ", size)
		plugin.get_window().size = size
		await frames(12)
		print("[attachments-editor-stage] reveal ", size)
		await reveal(panel)
		var rect: Rect2 = plugin.dock.get_global_rect()
		var viewport_rect: Rect2 = EditorInterface.get_base_control().get_viewport_rect()
		check(rect.size.y < size.y - 70 and rect.size.x < size.x * 0.5, "dock不挤占nativeEditor：" + str(size))
		check(viewport_rect.encloses(rect), "dock位于真实窗口内：" + str(size))
		check(panel.editor_panel.size.y >= 180 and panel.size.y > 250, "可用编辑区实际高度：" + str(size))
		evidence.layouts.append({"window": str(size), "dock_rect": str(rect), "panel_size": str(panel.size), "editor_height": panel.editor_panel.size.y, "native_3d_surface_size": str(plugin.surfaces[0].size)})
		await screenshot("layout_%dx%d" % [size.x, size.y])
	check(EditorInterface.save_scene() == OK, "换版后手动保存")
	EditorInterface.reload_scene_from_path(fixture)
	await frames(25)
	scene = EditorInterface.get_edited_scene_root()
	var attachments: Array[Node] = []
	for node: Node in scene.find_children("*", "Node3D", true, false):
		if node.has_meta("sea_attachment"): attachments.append(node)
	check(attachments.size() == 2, "真实Editor重载恢复两附件")
	for node: Node3D in attachments:
		check(node.owner == scene and node.get_script() == null, "重载owner/静态无脚本")
		check(node.transform == transforms[str(node.name)], "重载变换保持")
	var old_binding_root: Node = plugin.binding.root.get_ref() if plugin.binding.has("root") else null
	check(plugin.binding.is_empty() or bool(plugin.binding.get("closed", false)) or old_binding_root != scene, "重载失效旧房屋绑定：清空/closed/旧root均不可继续写入")
	await screenshot("reloaded")
	await finish()

func finish() -> void:
	evidence.merge({"passed": failures.is_empty(), "checks": checks, "failures": failures, "expected_failures": [], "not_tested": ["四视口", "原生gizmo轴拖动", "生产Main", "人工使用验收", "游戏导航与水面阻挡"]})
	var file := FileAccess.open("res://outputs/building_attachments_editor_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "\t", true, true))
	file.close()
	plugin.get_window().always_on_top = previous_on_top
	print("[building-attachments-editor] %d checks, %d failures" % [checks, failures.size()])
	# 与既有scene-assembly专项一致：先清选择/历史并关闭场景，再卸载插件。
	var tree := plugin.get_tree()
	EditorInterface.get_selection().clear()
	EditorInterface.edit_node(EditorInterface.get_edited_scene_root())
	plugin.get_undo_redo().clear_history()
	EditorInterface.save_scene()
	var close_scene := InputEventKey.new()
	close_scene.keycode = KEY_W
	close_scene.physical_keycode = KEY_W
	close_scene.meta_pressed = OS.get_name() == "macOS"
	close_scene.ctrl_pressed = OS.get_name() != "macOS"
	close_scene.pressed = true
	Input.parse_input_event(close_scene)
	await tree.create_timer(1.0).timeout
	close_scene.pressed = false
	Input.parse_input_event(close_scene)
	await tree.create_timer(1.0).timeout
	EditorInterface.set_plugin_enabled("scene_assembly", false)
	EditorInterface.set_plugin_enabled("plant_editor", false)
	EditorInterface.set_plugin_enabled("building_workshop", false)
	await tree.create_timer(0.5).timeout
	tree.quit(0 if failures.is_empty() else 1)
