extends SceneTree
## 渲染预算归因：逐个关掉可疑的全屏/阴影开销，看帧时降多少。
## 只读诊断，不改工程配置；每档测量前先重建稳定状态。

var _main: Node = null
var _sun: DirectionalLight3D = null
var _env: Environment = null

func _init() -> void:
	call_deferred("run")

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _measure(tag: String, warm: int, sample: int) -> void:
	await _frames(warm)
	var times: Array = []
	var draws: Array = []
	var stamp := Time.get_ticks_usec()
	for i in sample:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - stamp) / 1000.0)
		stamp = now
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	times.sort()
	draws.sort()
	var sum := 0.0
	for t in times: sum += t
	print("[frame-budget] ", JSON.stringify({
		"mode": tag,
		"fps": float(sample) * 1000.0 / sum,
		"p50_ms": times[times.size() / 2],
		"p95_ms": times[int(times.size() * 0.95)],
		"draws": draws[draws.size() / 2],
	}))

func _apply(msaa: int, shadow: bool, ssao: bool, glow: bool, scale: float, deband: bool) -> void:
	root.msaa_3d = msaa
	root.scaling_3d_scale = scale
	root.use_debanding = deband
	_sun.shadow_enabled = shadow
	_env.ssao_enabled = ssao
	_env.glow_enabled = glow
	await _frames(3)

func run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_main._autosave_on = false
	_sun = _main.get_node_or_null("World/Lights/Sun") as DirectionalLight3D
	_env = (_main.get_node("World/WorldEnvironment") as WorldEnvironment).environment
	await _frames(20)
	var base_msaa := root.msaa_3d
	var base_scale := root.scaling_3d_scale
	var base_deband := root.use_debanding
	var base_shadow := _sun.shadow_enabled
	var base_ssao := _env.ssao_enabled
	var base_glow := _env.glow_enabled
	print("[frame-budget] state ", JSON.stringify({
		"viewport": str(root.get_visible_rect().size),
		"window": str(DisplayServer.window_get_size()),
		"screen_scale": DisplayServer.screen_get_scale(),
		"msaa_3d": base_msaa,
		"scaling_3d_scale": base_scale,
		"debanding": base_deband,
		"shadow": base_shadow,
		"ssao": base_ssao,
		"glow": base_glow,
		"shadow_sun_size": ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size"),
		"shadow_max_distance": _sun.directional_shadow_max_distance,
	}))

	await _measure("baseline", 30, 90)
	await _apply(base_msaa, false, base_ssao, base_glow, base_scale, base_deband)
	await _measure("shadow_off", 10, 60)
	await _apply(base_msaa, base_shadow, false, base_glow, base_scale, base_deband)
	await _measure("ssao_off", 10, 60)
	await _apply(Viewport.MSAA_DISABLED, base_shadow, base_ssao, base_glow, base_scale, base_deband)
	await _measure("msaa_off", 10, 60)
	await _apply(base_msaa, base_shadow, base_ssao, base_glow, 0.5, base_deband)
	await _measure("scale_50", 10, 60)
	await _apply(base_msaa, base_shadow, base_ssao, base_glow, base_scale, false)
	await _measure("deband_off", 10, 60)
	await _apply(Viewport.MSAA_DISABLED, false, false, false, 0.5, false)
	await _measure("all_off_scale50", 10, 60)
	await _apply(base_msaa, base_shadow, base_ssao, base_glow, base_scale, base_deband)
	await _measure("baseline_again", 10, 60)
	print("[frame-budget] complete")
	quit()
