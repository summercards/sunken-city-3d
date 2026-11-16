@tool
extends SubViewport

func _init() -> void:
	size = Vector2i(192, 160)
	own_world_3d = true
	gui_disable_input = true
	handle_input_locally = false
	transparent_bg = true
	render_target_update_mode = SubViewport.UPDATE_DISABLED

func capture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path): return null
	var packed := load(path) as PackedScene
	if packed == null: return null
	var root := packed.instantiate() as Node3D
	if root == null: return null
	return await capture_root(root)

# 仅供原生 Generator 已创建的可信静态 root；不读取候选资源路径。
func capture_root(root: Node3D, view_direction: Vector3 = Vector3(1, 0.65, 1.4)) -> Texture2D:
	if root == null: return null
	add_child(root)
	var bounds := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = node.global_transform * node.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if first or not bounds.position.is_finite() or not bounds.size.is_finite():
		root.free()
		return null
	var camera := Camera3D.new()
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(bounds.size.length() * 0.9, 1.0)
	var center := bounds.get_center()
	camera.position = center + view_direction.normalized() * maxf(bounds.size.length() * 2.0, 4.0)
	camera.look_at(center)
	camera.current = true
	var light := DirectionalLight3D.new()
	add_child(light)
	light.rotation_degrees = Vector3(-45, -35, 0)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	add_child(environment)
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = get_texture().get_image()
	var texture: Texture2D = ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.free()
	camera.free()
	light.free()
	environment.free()
	return texture
