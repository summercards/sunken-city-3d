extends SceneTree
## SEA-WORKSHOP 独立 Panel 真实渲染验收。
## 不加载主场景、不修改 core/ui/runner；只通过 load() 实例化工坊 Panel。

const PANEL_PATH: String = "res://src/workshop/panel.gd"
const REPORT_PATH: String = "res://outputs/workshop_report.json"
const OUTPUT_ROOT: String = "res://outputs"

var panel: Node = null
var preview: Node = null
var session: Object = null
var checks: int = 0
var failures: Array[String] = []
var captures: Array[String] = []
var visual_checks: Array[String] = []
var requested_dimensions: Array[Vector2i] = [Vector2i(1280, 800), Vector2i(1600, 1000), Vector2i(1920, 1080)]
var recipe_snapshot: Dictionary = {}

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL [workshop-render] ", message)

func wait_frames(count: int = 4) -> void:
	for index: int in range(count):
		await process_frame

func set_window_extent(extent: Vector2i) -> void:
	root.size = extent
	root.content_scale_size = extent

func setup_panel() -> bool:
	var loaded_panel: Resource = load(PANEL_PATH)
	check(loaded_panel is Script, "Panel 通过 load() 获得脚本资源，未依赖 class cache")
	if not loaded_panel is Script:
		return false
	var panel_script: Script = loaded_panel as Script
	var created: Variant = panel_script.new()
	check(created is Node, "Panel 脚本可独立 new")
	if not created is Node:
		return false
	panel = created as Node
	panel.name = "WorkshopPanelCapture"
	root.add_child(panel)
	if not panel.is_node_ready():
		await panel.ready
	else:
		await process_frame
	current_scene = panel
	check(current_scene == panel and panel.is_node_ready(), "Panel 加入 root 并 ready 后成为 current_scene")
	if panel.has_method("configure"):
		panel.call("configure", {"standalone": false, "export_root": "user://building_workshop/capture"})
	else:
		check(false, "Panel 存在 configure 接口")
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	check(panel.process_mode == Node.PROCESS_MODE_ALWAYS, "Panel process_mode 为 PROCESS_MODE_ALWAYS")
	var preview_value: Variant = panel.get("preview")
	check(preview_value is Node, "Panel 持有独立 Preview")
	if preview_value is Node:
		preview = preview_value as Node
	var session_value: Variant = panel.get("session")
	check(session_value is Object, "Panel 持有独立 Session")
	if session_value is Object:
		session = session_value as Object
	return preview != null and session != null

func configure_recipe() -> bool:
	if session == null or not session.has_method("apply_patch"):
		check(false, "Session 存在 apply_patch 接口")
		return false
	var bindings: Dictionary = {
		"wall": "wall_sun",
		"slab": "slab_warm",
		"frame": "frame_timber",
		"glass": "glass_blue",
		"pillar": "pillar_timber",
		"plant": "plant_vine"
	}
	var patch: Dictionary = {
		"building_id": "workshop_lshape_capture",
		"display_name": "破旧L形绿色楼房",
		"shape": "l",
		"floors": 3,
		"damage": 0.5,
		"aging": 0.4,
		"vegetation_density": 0.8,
		"component_bindings": bindings
	}
	var patch_result: Variant = session.call("apply_patch", patch)
	check(patch_result is Dictionary and bool((patch_result as Dictionary).get("ok", false)), "配方应用 L 形/三层/破损/老化/植物参数与替代组件")
	if not patch_result is Dictionary or not bool((patch_result as Dictionary).get("ok", false)):
		return false
	var snapshot_result: Variant = session.call("snapshot")
	check(snapshot_result is Dictionary, "Session 返回配方快照")
	if not snapshot_result is Dictionary:
		return false
	recipe_snapshot = snapshot_result as Dictionary
	check(str(recipe_snapshot.get("shape", "")) == "l", "配方 shape 为 l")
	check(int(recipe_snapshot.get("floors", 0)) == 3, "配方 floors 为 3")
	check(is_equal_approx(float(recipe_snapshot.get("damage", 0.0)), 0.5), "配方 damage 为 0.5")
	check(is_equal_approx(float(recipe_snapshot.get("aging", 0.0)), 0.4), "配方 aging 为 0.4")
	check(is_equal_approx(float(recipe_snapshot.get("vegetation_density", 0.0)), 0.8), "配方 vegetation_density 为 0.8")
	var controls_value: Variant = panel.get("controls")
	check(controls_value is Dictionary, "Panel 左页参数 controls 可读取")
	if controls_value is Dictionary:
		var controls: Dictionary = controls_value as Dictionary
		var shape_control: Variant = controls.get("shape", null)
		var damage_control: Variant = controls.get("damage", null)
		var aging_control: Variant = controls.get("aging", null)
		var vegetation_control: Variant = controls.get("vegetation_density", null)
		check(shape_control is OptionButton and damage_control is SpinBox and aging_control is SpinBox and vegetation_control is SpinBox, "左页展示形状/破损/老化/植物控件")
	var actual_bindings: Variant = recipe_snapshot.get("component_bindings", {})
	check(actual_bindings is Dictionary and str((actual_bindings as Dictionary).get("wall", "")) == "wall_sun" and str((actual_bindings as Dictionary).get("plant", "")) == "plant_vine", "配方使用替代 wall_sun/plant_vine 组件绑定")
	return true

func open_panel() -> bool:
	if panel == null or not panel.has_method("open"):
		check(false, "Panel 存在 open 接口")
		return false
	paused = false
	panel.call("open")
	await wait_frames(5)
	check(bool(panel.get("standalone")) == false, "Panel standalone 明确为 false")
	var panel_visible: bool = bool(panel.get("visible"))
	check(bool(panel.get("_open")) and panel_visible, "Panel 已打开")
	check(paused, "Panel 打开后 SceneTree paused")
	return bool(panel.get("_open")) and panel_visible

func layout_nodes() -> Array:
	var result: Array = []
	if panel == null:
		return result
	var layout: Node = panel.get_node_or_null("WorkshopBackground/WorkshopLayout")
	if layout == null or layout.get_child_count() == 0:
		return result
	var page: Node = layout.get_child(0) as Node
	if page == null or page.get_child_count() < 2:
		return result
	var columns: Node = page.get_child(1) as Node
	if columns == null or columns.get_child_count() < 3:
		return result
	for index: int in range(3):
		var child: Variant = columns.get_child(index)
		if child is Control:
			result.append(child as Control)
	return result

func assert_layout(extent: Vector2i) -> void:
	set_window_extent(extent)
	await wait_frames(4)
	check(root.size == extent, "root.size 为 " + str(extent))
	check(root.content_scale_size == extent, "root.content_scale_size 为 " + str(extent))
	var nodes: Array = layout_nodes()
	check(nodes.size() == 3, "三栏布局节点齐全 " + str(extent))
	if nodes.size() != 3 or preview == null:
		return
	var left: Control = nodes[0] as Control
	var preview_control: Control = preview as Control
	var right: Control = nodes[2] as Control
	var visible_rect: Rect2 = root.get_visible_rect()
	var left_rect: Rect2 = left.get_global_rect()
	var preview_rect: Rect2 = preview_control.get_global_rect()
	var right_rect: Rect2 = right.get_global_rect()
	check(visible_rect.encloses(left_rect), "左参数页完整入镜 " + str(extent))
	check(visible_rect.encloses(preview_rect), "预览完整入镜 " + str(extent))
	check(visible_rect.encloses(right_rect), "右预览页完整入镜 " + str(extent))
	check(not left_rect.intersects(preview_rect), "左参数页不遮挡预览 " + str(extent))
	check(not preview_rect.intersects(right_rect), "预览不遮挡右预览页 " + str(extent))
	check(not left_rect.intersects(right_rect), "左右面板不互相遮挡 " + str(extent))
	var id_edit_value: Variant = panel.get("_id_edit")
	var name_edit_value: Variant = panel.get("_name_edit")
	check(id_edit_value is LineEdit and name_edit_value is LineEdit, "左页身份参数控件存在 " + str(extent))
	if id_edit_value is LineEdit and name_edit_value is LineEdit:
		var id_edit: LineEdit = id_edit_value as LineEdit
		var name_edit: LineEdit = name_edit_value as LineEdit
		check(id_edit.get_theme_font_size("font_size") >= 16 and name_edit.get_theme_font_size("font_size") >= 16, "左页文字字号至少16 " + str(extent))

func assert_recipe_controls() -> void:
	var controls_value: Variant = panel.get("controls")
	if not controls_value is Dictionary:
		check(false, "打开后的左页参数 controls 可读取")
		return
	var controls: Dictionary = controls_value as Dictionary
	var shape_value: Variant = controls.get("shape", null)
	var damage_value: Variant = controls.get("damage", null)
	var aging_value: Variant = controls.get("aging", null)
	var vegetation_value: Variant = controls.get("vegetation_density", null)
	check(shape_value is OptionButton and damage_value is SpinBox and aging_value is SpinBox and vegetation_value is SpinBox, "打开后的左页展示形状/破损/老化/植物控件")
	if shape_value is OptionButton:
		var shape_option: OptionButton = shape_value as OptionButton
		var shape_metadata: String = str(shape_option.get_item_metadata(shape_option.selected)) if shape_option.selected >= 0 else ""
		check(shape_metadata == "l", "左页形状控件展示 L 形")
	if damage_value is SpinBox:
		check(is_equal_approx((damage_value as SpinBox).value, 0.5), "左页破损控件展示 0.5")
	if aging_value is SpinBox:
		check(is_equal_approx((aging_value as SpinBox).value, 0.4), "左页老化控件展示 0.4")
	if vegetation_value is SpinBox:
		check(is_equal_approx((vegetation_value as SpinBox).value, 0.8), "左页植物密度控件展示 0.8")

func select_page(index: int) -> void:
	var picker_value: Variant = panel.get("_page_picker")
	if picker_value is OptionButton:
		var picker: OptionButton = picker_value as OptionButton
		picker.select(index)
	if panel.has_method("_select_page"):
		panel.call("_select_page", index)
	await wait_frames(3)

func set_preview_view(kind: String) -> bool:
	if preview == null or not preview.has_method("set_view"):
		check(false, "Preview 存在 set_view 接口 " + kind)
		return false
	preview.call("set_view", kind)
	await wait_frames(3)
	return true

func choose_slot() -> String:
	if preview == null:
		return ""
	var slots_value: Variant = preview.get("_slots")
	if not slots_value is Array:
		return ""
	var slots: Array = slots_value as Array
	for slot_value: Variant in slots:
		if slot_value is Dictionary:
			var slot: Dictionary = slot_value as Dictionary
			var slot_id: String = str(slot.get("id", ""))
			if str(slot.get("kind", "")) == "wall" and not slot_id.is_empty():
				return slot_id
	for slot_value: Variant in slots:
		if slot_value is Dictionary:
			var fallback_slot: Dictionary = slot_value as Dictionary
			var fallback_id: String = str(fallback_slot.get("id", ""))
			if not fallback_id.is_empty():
				return fallback_id
	return ""

func select_slot_for_capture() -> String:
	var slot_id: String = choose_slot()
	if slot_id.is_empty():
		check(false, "生成结果存在可选择槽位")
		return ""
	if panel != null and panel.has_method("select_slot"):
		panel.call("select_slot", slot_id)
	elif preview != null and preview.has_method("select_slot"):
		preview.call("select_slot", slot_id, false)
	else:
		check(false, "Panel/Preview 存在 select_slot 接口")
		return ""
	await wait_frames(2)
	var selected_value: Variant = preview.call("selected_slot") if preview != null and preview.has_method("selected_slot") else ""
	check(str(selected_value) == slot_id, "选中槽位真实同步 " + slot_id)
	return slot_id

func set_collision_overlay(enabled: bool) -> void:
	if preview != null and preview.has_method("set_collision_overlay"):
		preview.call("set_collision_overlay", enabled)
		await wait_frames(3)
		return
	check(false, "Preview 存在 set_collision_overlay 接口")

func image_luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722

func rendered_region_has_detail(image: Image, region: Rect2, label: String) -> bool:
	var x_start: int = maxi(0, int(floor(region.position.x)))
	var y_start: int = maxi(0, int(floor(region.position.y)))
	var x_end: int = mini(image.get_width() - 1, int(ceil(region.end.x)) - 1)
	var y_end: int = mini(image.get_height() - 1, int(ceil(region.end.y)) - 1)
	if x_start > x_end or y_start > y_end:
		check(false, "真实渲染区域有效 " + label)
		return false
	var colors: Dictionary = {}
	var minimum_luma: float = 1.0
	var maximum_luma: float = 0.0
	for y: int in range(y_start, y_end + 1, 12):
		for x: int in range(x_start, x_end + 1, 12):
			var color: Color = image.get_pixel(x, y)
			colors[color.to_html()] = true
			var luma: float = image_luminance(color)
			minimum_luma = minf(minimum_luma, luma)
			maximum_luma = maxf(maximum_luma, luma)
	var detailed: bool = colors.size() >= 8 and maximum_luma - minimum_luma > 0.05
	check(detailed, "真实渲染区域具有颜色/明暗细节，非仅 PNG 非空 " + label)
	if detailed:
		visual_checks.append(label)
	return detailed

func capture(tag: String, kind: String, page_index: int, extent: Vector2i, select_slot: bool, collision: bool) -> void:
	set_window_extent(extent)
	await select_page(page_index)
	await set_preview_view(kind)
	await set_collision_overlay(collision)
	var selected_id: String = ""
	if select_slot:
		selected_id = await select_slot_for_capture()
	else:
		if preview != null and preview.has_method("select_slot"):
			preview.call("select_slot", "", false)
		await wait_frames(1)
	await wait_frames(5)
	if DisplayServer.get_name() == "headless":
		check(false, "禁止在 headless DisplayServer 签署真实截图 " + tag)
		return
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image != null and not image.is_empty(), "真实 viewport image 有效 " + tag)
	check(image.get_width() == extent.x and image.get_height() == extent.y, "真实 viewport image 尺寸匹配 " + str(extent) + " " + tag)
	if image == null or image.is_empty():
		return
	var preview_control: Control = preview as Control
	var layout_node: Node = panel.get_node_or_null("WorkshopBackground/WorkshopLayout")
	var layout_control: Control = layout_node as Control
	var panel_rect: Rect2 = layout_control.get_global_rect() if layout_control != null else Rect2()
	var preview_rect: Rect2 = preview_control.get_global_rect()
	var panel_detail: bool = rendered_region_has_detail(image, panel_rect, tag + " panel")
	var preview_detail: bool = rendered_region_has_detail(image, preview_rect, tag + " preview")
	check(panel_detail and preview_detail, "面板与 3D 预览均为实际渲染内容 " + tag)
	var path: String = OUTPUT_ROOT + "/workshop_" + tag + ".png"
	var save_error: Error = image.save_png(path)
	check(save_error == OK and FileAccess.file_exists(path), "保存真实截图 " + path)
	if save_error == OK and FileAccess.file_exists(path):
		captures.append(path)
	print("[workshop-shot] ", path, " ", image.get_width(), "x", image.get_height(), " selected=", selected_id, " collision=", collision)

func close_panel() -> void:
	if panel != null and panel.has_method("close_now"):
		panel.call("close_now")
	await wait_frames(2)
	check(not paused, "Panel close_now 后恢复 paused=false")
	check(panel == null or not bool(panel.get("_open")), "Panel close_now 后关闭")

func write_report() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_ROOT))
	var failure_copy: Array[String] = failures.duplicate()
	var dimensions_text: Array[String] = []
	for extent: Vector2i in requested_dimensions:
		dimensions_text.append("%dx%d" % [extent.x, extent.y])
	var report: Dictionary = {
		"runner": "visual-workshop",
		"marker": "workshop-render",
		"status": "passed" if failures.is_empty() else "failed",
		"execution": "isolated_runner_real_renderer",
		"display_server": DisplayServer.get_name(),
		"requested_dimensions": dimensions_text,
		"checks": checks,
		"failures": failure_copy,
		"captures": captures.duplicate(),
		"visual_checks": visual_checks.duplicate(),
		"recipe": recipe_snapshot.duplicate(true),
		"panel_path": PANEL_PATH,
		"output_pattern": OUTPUT_ROOT + "/workshop_*.png"
	}
	var file: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
		print("[workshop-report] ", REPORT_PATH)
	else:
		printerr("FAIL [workshop-render] 无法写入报告 ", REPORT_PATH)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_ROOT))
	check(DisplayServer.get_name() != "headless", "DisplayServer 必须为 real，禁止 headless")
	if not await setup_panel():
		await close_panel()
		write_report()
		print("[workshop-render] %d checks, %d failures" % [checks, failures.size()])
		quit(1)
		return
	check(bool(panel.get("standalone")) == false, "配置后的 standalone=false")
	var recipe_ok: bool = configure_recipe()
	if recipe_ok and panel.has_method("refresh_preview"):
		var refresh_result: Variant = panel.call("refresh_preview")
		check(refresh_result is Dictionary and bool((refresh_result as Dictionary).get("ok", false)), "真实生成器生成配方预览")
	else:
		check(false, "Panel 存在 refresh_preview 接口")
	await wait_frames(4)
	if not await open_panel():
		await close_panel()
		write_report()
		print("[workshop-render] %d checks, %d failures" % [checks, failures.size()])
		quit(1)
		return
	assert_recipe_controls()
	for extent: Vector2i in requested_dimensions:
		await assert_layout(extent)
	var background_value: Variant = panel.get_node_or_null("WorkshopBackground")
	check(background_value is ColorRect and (background_value as ColorRect).color.r < 0.2, "Panel 使用黑底主题")
	var layout_value: Variant = panel.get_node_or_null("WorkshopBackground/WorkshopLayout")
	var title_value: Variant = null
	if layout_value is Control:
		var page_value: Variant = (layout_value as Control).get_child(0) if (layout_value as Control).get_child_count() > 0 else null
		if page_value is Control and (page_value as Control).get_child_count() > 0:
			var toolbar_value: Variant = (page_value as Control).get_child(0)
			if toolbar_value is Control and (toolbar_value as Control).get_child_count() > 0:
				title_value = (toolbar_value as Control).get_child(0)
	check(title_value is Label and (title_value as Label).get_theme_font_size("font_size") >= 16, "Panel 标题字号至少16且可见")
	await capture("overview_front", "front", 0, Vector2i(1280, 800), false, false)
	await capture("overview_back", "back", 0, Vector2i(1600, 1000), false, false)
	await capture("lshape_top", "top", 2, Vector2i(1920, 1080), false, false)
	await capture("damaged_lshape_selected", "front", 2, Vector2i(1600, 1000), true, false)
	await capture("green_building_collision", "perspective", 3, Vector2i(1920, 1080), true, true)
	await capture("alternative_perspective", "back", 3, Vector2i(1280, 800), false, false)
	check(captures.size() >= 6, "至少产出6张有效 Workshop 真实渲染图")
	check(visual_checks.size() >= 12, "每张图同时通过 Panel 与 3D 预览细节检查")
	await close_panel()
	write_report()
	print("[workshop-render] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
