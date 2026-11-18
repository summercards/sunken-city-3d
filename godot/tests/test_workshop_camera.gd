@tool
extends SceneTree

const HousePreviewScript = preload("res://addons/building_workshop/editor_preview.gd")
const PlantPreviewScript = preload("res://addons/plant_editor/preview.gd")
const DIMENSIONS := [Vector2i(1280, 800), Vector2i(1000, 700), Vector2i(860, 600), Vector2i(600, 860)]
const VIEWS := ["front", "back", "top", "bottom", "perspective"]
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var artifacts: Array[String] = []

func _init() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	rows.append({"label": label, "passed": value, "mode": "camera_logic"})
	if not value:
		failures.append(label)
		printerr("FAIL [workshop-camera] ", label)

func run() -> void:
	if not str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sea-verification/") or FileAccess.file_exists("res://scenes/main.tscn"):
		printerr("相机专项只允许统一 runner 的无 Main 隔离工程")
		quit(1)
		return
	await test_house()
	await test_plant()
	var exit_code := 0 if failures.is_empty() else 1
	var report := {"suite": "workshop-camera", "checks": checks, "failures": failures, "passed": failures.is_empty(), "camera_logic": rows, "artifacts": artifacts, "real_rendering": "实际Camera3D投影逻辑；非headless时输出植物中心截图，真实toolbar另由editor专项覆盖", "expected_failures": [], "unexecuted": ["人工输入", "真实工具栏 GUI 路由", "生产 Main", "真实渲染目检"], "exit_code": exit_code}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs"))
	var file := FileAccess.open("res://outputs/workshop_camera_report.json", FileAccess.WRITE)
	if file == null:
		printerr("无法写入相机报告")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[workshop-camera] %d checks, %d failures" % [checks, failures.size()])
	quit(exit_code)

func mesh_box(parent: Node3D, node_name: String, center: Vector3, dimensions: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(0))
	node.mesh = array_mesh
	parent.add_child(node)
	node.position = center
	return node

func add_multi(parent: Node3D, center: Vector3) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.name = "ActualMultiMesh"
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2, 3, 1)
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(0))
	multi.mesh = array_mesh
	multi.instance_count = 2
	multi.set_instance_transform(0, Transform3D(Basis.IDENTITY, center))
	multi.set_instance_transform(1, Transform3D(Basis.IDENTITY, Vector3(9000, 9000, 9000)))
	multi.visible_instance_count = 1
	node.multimesh = multi
	parent.add_child(node)
	return node

func projection(camera: Camera3D, dimensions: Vector2i, box: AABB, label: String, fit: bool = true) -> void:
	camera.force_update_transform()
	var center: Vector2 = camera.unproject_position(box.get_center())
	check(center.distance_to(Vector2(dimensions) * 0.5) < 0.05, label + " 实际投影中心=viewport中心")
	check(camera.global_transform.is_finite() and is_finite(camera.size) and is_finite(camera.near) and is_finite(camera.far) and camera.near > 0.0 and camera.far > camera.near, label + " 变换/size/near/far有限")
	check(absf(camera.global_basis.determinant() - 1.0) < 0.001, label + " 相机基正交且无上下极点奇异")
	if not fit: return
	var inverse := camera.global_transform.affine_inverse()
	var contained := true
	var clipped := false
	for index: int in 8:
		var point := box.get_endpoint(index)
		var projected := camera.unproject_position(point)
		contained = contained and projected.is_finite() and projected.x >= -0.05 and projected.x <= dimensions.x + 0.05 and projected.y >= -0.05 and projected.y <= dimensions.y + 0.05
		var depth: float = -(inverse * point).z
		clipped = clipped or depth <= camera.near or depth >= camera.far
	check(contained, label + " 适配后八角全部入镜")
	check(not clipped, label + " 八角均在近远裁剪面内")

func capture_view(viewport: SubViewport, label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var path := "res://outputs/camera_" + label + ".png"
	check(image != null and not image.is_empty() and image.save_png(path) == OK, label + "真实渲染PNG")
	artifacts.append(ProjectSettings.globalize_path(path))

func routed_input(control: Control, event: InputEventMouse) -> void:
	var point := control.get_global_rect().get_center()
	if event is InputEventMouseMotion:
		point = control.global_position + event.position
	event.position = point
	event.global_position = point
	event.window_id = root.get_window_id()
	root.push_input(event, true)
	await process_frame

func test_house() -> void:
	var preview = HousePreviewScript.new()
	root.add_child(preview)
	preview.stretch = false
	preview.size = Vector2(1000, 700)
	preview._world.transform = Transform3D(Basis(Vector3.UP, 0.23), Vector3(30, -4, 12))
	preview.get_work_root().transform = Transform3D(Basis(Vector3.UP, -0.31).scaled(Vector3(1.4, 0.7, 1.2)), Vector3(-5, 3, 8))
	var building := Node3D.new()
	building.set_meta("workshop_building_id", "camera_fixture")
	building.transform = Transform3D(Basis(Vector3.UP, 0.41), Vector3(9, 6, -7))
	var visual := Node3D.new()
	visual.name = "GeneratedVisual"
	building.add_child(visual)
	var structure := mesh_box(visual, "structure_union", Vector3(2, 7, -3), Vector3(12, 14, 9))
	var frame := mesh_box(visual, "frame_front_0_0", Vector3(8.8, 5, -8), Vector3(2, 3, 0.4))
	var semantic := Node3D.new()
	semantic.name = "wall_shell_0"
	semantic.set_meta("semantic_source_only", true)
	visual.add_child(semantic)
	var vegetation := Node3D.new()
	vegetation.name = "Vegetation"
	building.add_child(vegetation)
	mesh_box(vegetation, "FarVine", Vector3(2000, 300, 100), Vector3(20, 30, 20))
	preview.set_build_result({"root": building, "slots": [{"id": "window", "node_path": "GeneratedVisual/frame_front_0_0", "bounds_position": [500, 500, 500], "bounds_size": [1, 1, 1]}, {"id": "semantic", "node_path": "GeneratedVisual/wall_shell_0", "semantic_source_only": true, "bounds_position": [2, 3, -4], "bounds_size": [3, 2, 1]}]})
	preview.set_screen_visible(true)
	await process_frame
	await process_frame
	var attachment := mesh_box(preview.get_attachment_root(), "FarAttachment", Vector3(-1300, 0, 0), Vector3(30, 20, 30))
	mesh_box(preview.get_temporary_root(), "Ghost", Vector3(9000, 0, 0), Vector3.ONE * 100)
	mesh_box(preview._highlight_root, "Highlight", Vector3(0, 9000, 0), Vector3.ONE * 100)
	structure.force_update_transform()
	frame.force_update_transform()
	var expected: AABB = (structure.global_transform * structure.mesh.get_aabb()).merge(frame.global_transform * frame.mesh.get_aabb())
	check(preview.get_building_bounds().is_equal_approx(expected), "房屋仅真实GeneratedVisual含窗框，不合入植物/外挂/ghost/高亮/语义槽")
	check(preview.get_work_bounds().size.length() > expected.size.length() * 10.0, "完整作品总览独立含远处植物与外挂")
	for dimensions: Vector2i in DIMENSIONS:
		preview.viewport.size = dimensions
		for keep: int in [Camera3D.KEEP_WIDTH, Camera3D.KEEP_HEIGHT]:
			preview.camera.keep_aspect = keep
			for view: String in VIEWS:
				preview._target = Vector3(900, -300, 200)
				preview.set_view(view)
				projection(preview.camera, dimensions, expected, "房屋 %s %s keep%d" % [view, dimensions, keep])
				preview._yaw += 0.28
				preview._pitch = -0.38
				preview._fit_camera(false)
				projection(preview.camera, dimensions, expected, "房屋reset后orbit " + view, false)
	preview.viewport.size = Vector2i(1000, 700)
	preview.select_slot("window", false)
	preview.focus_selection()
	var selected: AABB = frame.global_transform * frame.mesh.get_aabb()
	projection(preview.camera, preview.viewport.size, selected, "房屋选Mesh按真实世界包络而非过期slot")
	preview._yaw += 0.4
	preview._fit_camera(false)
	projection(preview.camera, preview.viewport.size, selected, "房屋选Mesh后orbit保当前pivot", false)
	preview.select_slot("semantic", false)
	preview.focus_selection()
	projection(preview.camera, preview.viewport.size, building.global_transform * AABB(Vector3(2, 3, -4), Vector3(3, 2, 1)), "融合语义选槽仅使用root-local bounds一次变换")
	preview.highlight_attachment(attachment)
	preview.focus_selection()
	projection(preview.camera, preview.viewport.size, attachment.global_transform * attachment.mesh.get_aabb(), "外挂根本身是Mesh仍可选件聚焦")
	preview.focus_object(true)
	projection(preview.camera, preview.viewport.size, expected, "显式房屋聚焦忽略旧外挂选择")
	preview._pan_camera(Vector2(120, -70))
	var pan_target: Vector3 = preview._target
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	await routed_input(preview, wheel)
	check(preview._target.is_equal_approx(pan_target), "房屋pan后实际滚轮handler不重置中心")
	projection(preview.camera, preview.viewport.size, AABB(pan_target, Vector3.ZERO), "房屋pan pivot与屏幕中心一致", false)
	preview._navigation_button = MOUSE_BUTTON_RIGHT
	preview._last_mouse = Vector2(100, 100)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(140, 125)
	var previous_position: Vector3 = preview.camera.global_position
	await routed_input(preview, motion)
	check(preview.camera.global_position.distance_to(previous_position) < 0.001, "右键环视保持世界相机位置")
	var fly_target: Vector3 = preview._target
	await routed_input(preview, wheel)
	check(preview._target.is_equal_approx(fly_target), "右键环视后滚轮不跳回建筑中心")
	preview._target += preview.camera.global_basis * Vector3(2, 1, -6)
	preview._fit_camera(false)
	fly_target = preview._target
	await routed_input(preview, wheel)
	check(preview._target.is_equal_approx(fly_target), "模拟飞行位移后滚轮保留当前pivot（非物理按键测试）")
	preview.set_view("front")
	projection(preview.camera, preview.viewport.size, expected, "pan/右键后front明确回建筑中心")
	var multi := add_multi(visual, Vector3(24, 10, 3))
	multi.force_update_transform()
	var multi_box: AABB = multi.global_transform * multi.multimesh.get_instance_transform(0) * multi.multimesh.mesh.get_aabb()
	check(preview.get_building_bounds().is_equal_approx(expected.merge(multi_box)), "建筑实际MultiMesh及visible_instance_count纳入包络")
	preview.set_view("perspective")
	var saved_camera: Transform3D = preview.camera.global_transform
	var saved_target: Vector3 = preview._target
	var replacement := building.duplicate() as Node3D
	preview.set_build_result({"root": replacement, "slots": []})
	check(preview.camera.global_transform.is_equal_approx(saved_camera) and preview._target.is_equal_approx(saved_target), "同文档实时重建不重置相机")
	for scale_factor: float in [0.01, 1.0, 100.0]:
		var scale_box := AABB(Vector3(13, -7, 22), Vector3(1, 14, 3) * scale_factor)
		preview._frame_camera(preview.camera, preview.viewport.size, scale_box, true)
		projection(preview.camera, preview.viewport.size, scale_box, "房屋三尺度及细长包络 %s" % scale_factor)
	preview.free()

func test_plant() -> void:
	var preview = PlantPreviewScript.new()
	root.add_child(preview)
	preview.size = Vector2(1000, 700)
	preview.set_active(true)
	var tree := Node3D.new()
	tree.transform = Transform3D(Basis(Vector3.UP, -0.36).scaled(Vector3(1.2, 0.8, 1.4)), Vector3(4, 3, -5))
	var trunk := mesh_box(tree, "Trunk", Vector3(1, 4, -2), Vector3(2, 8, 2))
	var crown := mesh_box(tree, "Crown", Vector3(5, 9, -3), Vector3(10, 7, 8))
	var branch_bounds := AABB(Vector3(3, 6, -4), Vector3(5, 2, 3))
	check(preview.set_build({"root": tree, "branches": [{"id": "branch_00", "position": Vector3(70, 80, 90), "bounds": branch_bounds}]}), "树预览接受独立测试树")
	var host := Node3D.new()
	host.transform = Transform3D(Basis(Vector3.UP, 0.52), Vector3(130, -8, 45))
	mesh_box(host, "FarReference", Vector3(-2000, 0, 0), Vector3.ONE * 600)
	preview.set_host_reference(host)
	preview.set_plant_transform(Transform3D(Basis(Vector3.UP, -0.19), Vector3(-12, 5, 9)))
	await process_frame
	await process_frame
	preview._surface.stretch = false
	trunk.force_update_transform()
	crown.force_update_transform()
	var expected: AABB = (trunk.global_transform * trunk.mesh.get_aabb()).merge(crown.global_transform * crown.mesh.get_aabb())
	check(preview.get_plant_bounds().is_equal_approx(expected), "树包络只含当前树，排宿主且不重复旋转AABB")
	mesh_box(preview._plant_space, "GhostSibling", Vector3(7000, 0, 0), Vector3.ONE * 200)
	check(preview.get_plant_bounds().is_equal_approx(expected), "树父级临时兄弟不混入树包络")
	for dimensions: Vector2i in DIMENSIONS:
		preview.viewport.size = dimensions
		for keep: int in [Camera3D.KEEP_WIDTH, Camera3D.KEEP_HEIGHT]:
			preview.camera.keep_aspect = keep
			for view: String in VIEWS:
				preview.target = Vector3(-300, 500, 100)
				preview.set_view(view)
				projection(preview.camera, dimensions, expected, "树 %s %s keep%d" % [view, dimensions, keep])
				preview.yaw += 0.3
				preview.pitch = 0.4
				preview._update_camera()
				projection(preview.camera, dimensions, expected, "树reset后orbit " + view, false)
	preview.viewport.size = Vector2i(1000, 700)
	check(preview.focus_branch("branch_00"), "树选枝聚焦成功")
	projection(preview.camera, preview.viewport.size, tree.global_transform * branch_bounds, "枝偏移已在bounds中，不重复加position或父级transform")
	preview.target += Vector3(6, -3, 4)
	preview._update_camera()
	var panned: Vector3 = preview.target
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	await routed_input(preview._surface, wheel)
	check(preview.target.is_equal_approx(panned), "树pan后实际滚轮handler不重置中心")
	projection(preview.camera, preview.viewport.size, AABB(panned, Vector3.ZERO), "树pan pivot屏幕居中", false)
	preview.set_view("front")
	projection(preview.camera, preview.viewport.size, expected, "树pan/选枝后front回当前树而非宿主")
	var multi := add_multi(tree, Vector3(18, 14, 2))
	multi.force_update_transform()
	var multi_box: AABB = multi.global_transform * multi.multimesh.get_instance_transform(0) * multi.multimesh.mesh.get_aabb()
	check(preview.get_plant_bounds().is_equal_approx(expected.merge(multi_box)), "树MultiMesh按可见实例实际变换取包络")
	preview.set_view("top")
	projection(preview.camera, preview.viewport.size, expected.merge(multi_box), "树MultiMesh俯视适配")
	var saved_camera: Transform3D = preview.camera.global_transform
	var saved_target: Vector3 = preview.target
	var replacement := tree.duplicate() as Node3D
	check(preview.set_build({"root": replacement, "branches": []}), "树同文档替换成功")
	await process_frame
	check(preview.camera.global_transform.is_equal_approx(saved_camera) and preview.target.is_equal_approx(saved_target), "树实时重建及process不重置相机")
	for scale_factor: float in [0.01, 1.0, 100.0]:
		var scale_box := AABB(Vector3(13, -7, 22), Vector3(1, 14, 3) * scale_factor)
		preview.focus_bounds(scale_box)
		projection(preview.camera, preview.viewport.size, scale_box, "树三尺度及细长包络 %s" % scale_factor)
	preview.set_view("front")
	await capture_view(preview.viewport, "plant_front_center")
	preview.set_view("top")
	await capture_view(preview.viewport, "plant_top_center")
	preview.set_view("perspective")
	await capture_view(preview.viewport, "plant_perspective_center")
	var frame_rect: Rect2 = preview._surface.get_parent().get_global_rect()
	var tools_rect: Rect2 = preview._tools.get_global_rect()
	check(tools_rect.end.y <= frame_rect.position.y + 0.5, "旧导航工具栏仍独立位于渲染框外")
	for button: Node in preview._tools.get_children():
		if button is Button:
			check(button.is_visible_in_tree() and not button.disabled and button.mouse_filter != Control.MOUSE_FILTER_IGNORE and button.pressed.get_connections().size() == 1, "旧导航按钮可用且无重复连接 " + button.text)
	preview.free()
