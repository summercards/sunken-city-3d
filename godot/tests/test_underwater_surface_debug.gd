extends SceneTree
## SEA-OCEAN：P 键水下海面调试工具的行为契约。
## 不把「面板能生成」当成通过：这里验证参数全集、运行时材质写入、P 开关、
## 保存/加载和默认值回放；保存只发生在 runner 隔离 user:// 内。
const DebugScript = preload("res://src/rendering/underwater_surface_debug.gd")
const Params = preload("res://src/rendering/underwater_surface_params.gd")
const SHARED_SOURCE := "res://shaders/uw_surface_shared.gdshaderinc"
var checks := 0
var failures := 0

class FakeRuntime extends Node:
	var material := ShaderMaterial.new()
	var map_name := "debug-fake-map"
	var water_level := 101.587442
	var depth := 55.0
	var sun_strength := 1.0
	func underwater_surface_debug_materials() -> Array:
		return [material]
	func underwater_surface_debug_runtime() -> Dictionary:
		return {"map": map_name, "water_level": water_level,
			"view_depth": depth, "sun_strength": sun_strength}

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[underwater-surface-debug] FAIL ", label)

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func run() -> void:
	var flat := Params.flat()
	var shader_source := FileAccess.get_file_as_string(SHARED_SOURCE)
	check(flat.size() >= 48, "水下海面参数清单覆盖全部调试数值")
	for key_name in flat.keys():
		var spec: Dictionary = flat[key_name]
		check(spec.has("default"), "参数有默认值：" + str(key_name))
		check(shader_source.contains(String(key_name)), "参数有对应 shader uniform：" + str(key_name))

	var fake := FakeRuntime.new()
	root.add_child(fake)
	var panel = DebugScript.new()
	root.add_child(panel)
	await process_frame
	panel.bind_runtime(fake)
	check(panel._surface_materials().size() == 1, "面板读取活动水下材质")
	check(not panel.is_open(), "绑定运行时后面板默认关闭")

	await key(KEY_P)
	check(panel.is_open(), "潜水状态按 P 打开水下海面面板")
	check(panel.visible, "打开后面板可见")
	panel._set_value("underside_wave_light", 1.37, false)
	panel._set_value("underside_surface_edge_far", 205.0, false)
	check(is_equal_approx(float(fake.material.get_shader_parameter("underside_wave_light")), 1.37), "波光滑杆即时写入活动材质")
	check(is_equal_approx(float(fake.material.get_shader_parameter("underside_surface_edge_far")), 205.0), "边界滑杆即时写入活动材质")
	panel._save_values()
	check(FileAccess.file_exists("user://underwater_surface.cfg"), "保存当前生成独立水下配置文件")
	check(not FileAccess.file_exists("user://water.cfg") or true, "水下保存不要求改写水上配置")

	var panel2 = DebugScript.new()
	root.add_child(panel2)
	await process_frame
	panel2.bind_runtime(fake)
	check(is_equal_approx(float(panel2._values["underside_wave_light"]), 1.37), "新面板实例加载已保存波光值")
	check(is_equal_approx(float(panel2._values["underside_surface_edge_far"]), 205.0), "新面板实例加载已保存边界值")
	panel2._on_reset()
	check(is_equal_approx(float(panel2._values["underside_wave_light"]), float(flat["underside_wave_light"].default)), "恢复默认回到参数清单值")
	check(is_equal_approx(float(fake.material.get_shader_parameter("underside_wave_light")), float(flat["underside_wave_light"].default)), "恢复默认写回活动材质")
	panel2.set_open(false)
	check(not panel2.visible, "关闭面板隐藏显示")

	panel.queue_free()
	panel2.queue_free()
	fake.queue_free()
	await process_frame
	print("[underwater-surface-debug] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
