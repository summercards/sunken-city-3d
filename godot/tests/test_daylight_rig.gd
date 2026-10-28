extends SceneTree
## 昼夜光照专项。
##
## 这个专项守两件事，都是「玩家一眼能看出来、逻辑测试却全绿」的那类：
##
## 1. **屏幕蒙版不许回来。** 2026-10-27 之前夜晚是一张全屏深蓝色块。它能把画面
##    压暗，但影子方向、水面高光、天空颜色在「夜里」全是正午 —— 整幅画面看着
##    像蒙了一层脏玻璃。现在时段由真实光照做，任何回到全屏填充的做法都是回退。
##
## 2. **09:00必须恢复原有基准。** 资源文件里的值（太阳 0.54、环境光 0.36、天空
##    倍率 1.0、水面的天空三色）是美术调过的定版数值。时变只能在它们之上做
##    乘性调制，09:00 的系数必须严格是 1.0，否则等于偷偷改了定版。
##
## 顺带断言曲线的方向和边界：白天太阳高、天蓝；夜里太阳落、天暗、环境光转冷。

var checks := 0
var failures := 0
const Presenter = preload("res://src/weather/weather_presenter.gd")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func near(a: float, b: float, eps := 0.002) -> bool:
	return absf(a - b) <= eps

func _init() -> void: call_deferred("run")

func run() -> void:
	# ---- 屏幕蒙版不得回归 ---------------------------------------------
	# 源码级断言：只要 `weather_presenter.gd` 里再出现全屏填充，这里就红。
	var src := FileAccess.get_file_as_string("res://src/weather/weather_presenter.gd")
	check(not src.contains("draw_rect"), "屏幕氛围层不画全屏填充（蒙版不得回归）")
	var presenter = Presenter.new()
	check(not presenter.has_method("screen_tint") and not presenter.has_method("night_amount"),
		"屏幕层不再提供夜色叠加查询")
	presenter.free()

	# ---- 场景装配 ------------------------------------------------------
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	# 关掉主循环的驱动，改为在本专项里显式 `apply(hour)`：
	# 否则读到的值随时可能被下一帧的 `_process` 覆盖，断言不可复现。
	main.set_process(false)
	main.world_clock.paused = true
	var rig = main.daylight_rig
	check(rig != null, "主场景装配了昼夜光照装置")
	if rig == null:
		print("[daylight] %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	var sun: DirectionalLight3D = main.get_node("World/Lights/Sun")
	var env: Environment = (main.get_node("World/WorldEnvironment") as WorldEnvironment).environment
	var water: ShaderMaterial = main._active_water_mat()
	check(sun != null and env != null and water != null, "太阳 / 环境 / 水面材质均可解析")

	# 基准 = 资源文件里的定版值。抄错基准，后面所有时变都在错的底上加系数。
	var base_energy := float(rig.base_of("sun", "light_energy"))
	var base_ambient := float(rig.base_of("env", "ambient_light_energy"))
	var base_sky := float(rig.base_of("env", "background_energy_multiplier"))
	var base_top: Color = rig.base_of("water", "sky_top_color")
	var base_dir: Vector3 = rig.base_of("water", "sun_direction")
	check(near(base_energy, 0.54, 0.001), "太阳基准 %.3f = main.tscn 的 0.54" % base_energy)
	check(near(base_ambient, 0.36, 0.001), "环境光基准 %.3f = world_env.tres 的 0.36" % base_ambient)
	check(near(base_sky, 1.0, 0.001), "天空亮度基准 %.3f = 1.0" % base_sky)

	# ---- 正午：逐位等于基准 ---------------------------------------------
	rig.apply(9.0)
	check(near(sun.light_energy, base_energy), "09:00 太阳强度回到基准（%.4f）" % sun.light_energy)
	check(near(env.ambient_light_energy, base_ambient), "09:00 环境光回到基准（%.4f）" % env.ambient_light_energy)
	check(near(env.background_energy_multiplier, base_sky), "09:00 天空亮度回到基准")
	check(sun.light_color.is_equal_approx(Color(1, 0.955, 0.8)),
		"09:00 太阳色温回到基准 %s" % sun.light_color)
	check(water.get_shader_parameter("sky_top_color").is_equal_approx(base_top),
		"09:00 水面天顶色回到基准")
	# 方向允许 1e-4 的三角/归一化往返误差；这里要守的是「没有被镜像或被重新瞄准」，
	# 不是逐位相等（`is_equal_approx` 的 1e-5 卡在这个往返误差上）。
	var written_dir: Vector3 = water.get_shader_parameter("sun_direction")
	check((written_dir - base_dir).length() < 1e-4,
		"09:00 水面太阳方向回到基准（写 %s / 基准 %s）" % [str(written_dir), str(base_dir)])

	# ---- 上午：太阳低、方位偏 -------------------------------------------
	var noon_elevation: float = rig.arc_angles(12.0).x
	var morning_elevation: float = rig.arc_angles(8.0).x
	check(morning_elevation < noon_elevation - 5.0,
		"08:00 太阳比正午低（%.1f° < %.1f°）" % [morning_elevation, noon_elevation])
	check(absf(rig.arc_angles(8.0).y - rig.arc_angles(12.0).y) > 20.0,
		"08:00 太阳方位与正午不同（影子会转向）")
	rig.apply(8.0)
	check(near(sun.light_energy,base_energy), "08:00 保持09:00太阳基准（%.3f）" % sun.light_energy)
	check(sun.light_color.r > sun.light_color.b, "08:00 太阳偏暖")
	check(env.ambient_light_energy > base_ambient * 0.8, "08:00 环境光仍在白昼量级")
	for hour in [7.0,8.0,9.0,10.0,11.0]:
		rig.apply(hour)
		check(near(sun.light_energy,base_energy) and sun.global_basis.is_equal_approx(rig._sun_basis),"07–11完整保留上午方向与强度 %s" % hour)
		check(water.get_shader_parameter("body_deep")==rig.base_of("water","body_deep"),"07–11水色基准 %s" % hour)
	for hour in [19.0,20.0,23.5,0.0]:
		rig.apply(hour)
		check(sun.light_energy==0.0 and env.ambient_light_energy>0.0 and env.background_energy_multiplier>0.0,"19点后无日光、保留月色环境与天空 %s" % hour)
		check((water.get_shader_parameter("body_deep") as Color).get_luminance()<0.00001,"19点后水体自发光归零 %s" % hour)
		for entry in rig._fill_lights:check(entry.node.light_energy>0.0 and entry.node.light_color.b>entry.node.light_color.r,"19点后补光为冷月色 %s" % entry.node.name)

	# ---- 深夜：太阳落、天暗、环境光转冷 ---------------------------------
	rig.apply(21.0)
	check(sun.light_energy <= 0.001, "21:00 太阳已落（%.4f）" % sun.light_energy)
	check(env.ambient_light_energy < base_ambient * 0.6,
		"21:00 环境光降到 %.3f（基准 %.2f）" % [env.ambient_light_energy, base_ambient])
	check(env.background_energy_multiplier < 0.2,
		"21:00 天空亮度降到 %.3f" % env.background_energy_multiplier)
	check(env.ambient_light_color.b > env.ambient_light_color.r,
		"21:00 环境光转冷（B>R）")
	var night_top: Color = water.get_shader_parameter("sky_top_color")
	check(night_top.get_luminance() < base_top.get_luminance() * 0.35,
		"21:00 水面天顶色明显变暗（亮度 %.3f）" % night_top.get_luminance())
	check(float(water.get_shader_parameter("sky_sun_glow")) <= 0.001, "21:00 水面日晕归零")
	check(float(water.get_shader_parameter("sun_highlight_strength")) <= 0.0001,
		"21:00 水面太阳高光归零（太阳落了不该还有亮斑）")

	# ---- 曲线形状：入夜单调变暗 -----------------------------------------
	var previous := 999.0
	var monotonic := true
	for hour in [15.0, 16.5, 17.5, 19.0, 20.0, 22.0]:
		rig.apply(hour)
		var value: float = sun.light_energy
		if value > previous + 0.0001: monotonic = false
		previous = value
	check(monotonic, "入夜过程太阳强度单调不增")

	# ---- 写回资源文件时不许把夜晚烧进去 ---------------------------------
	rig.apply(21.0)
	var night_energy := sun.light_energy
	rig.suspend()
	check(near(sun.light_energy, base_energy),
		"暂停时太阳铺回基准（%.3f），存盘不会写入夜里的暗值" % sun.light_energy)
	check(near(env.ambient_light_energy, base_ambient), "暂停时环境光铺回基准")
	rig.resume()
	check(near(sun.light_energy, night_energy), "恢复后回到当前时刻的光照")

	# ---- 面板读写基准 ---------------------------------------------------
	# 面板直接写场景对象会被下一帧覆盖，所以它必须走 `adopt`。
	rig.adopt("sun", "light_energy", 0.8)
	check(near(float(rig.base_of("sun", "light_energy")), 0.8), "面板改的是基准值")
	rig.apply(9.0)
	check(near(sun.light_energy, 0.8), "改完基准，09:00就输出 0.8")

	# Every captured property returns exactly to the 09:00 baseline, including sky halo.
	rig.adopt("sun","light_energy",base_energy)
	# 用容差而不是 `==`：`light_energy` 之类是 32 位属性，而基准字典里存的是
	# GDScript 的 64 位 float，写进去再读回来必然差最后几位（0.8 → 0.80000001）。
	# 要守的是「没有被时变乘过」，不是位级相等。
	rig.apply(9.0)
	for target in ["sun","env","water","sky"]:
		for key in rig._base[target]:
			if key.begins_with("dir:"): continue
			var obj = {"sun":sun,"env":env,"water":water,"sky":rig._sky}[target]
			var actual = obj.get_shader_parameter(key) if target=="water" else obj.get(key)
			var expected = rig.base_of(target,key)
			var same: bool = near(float(actual), float(expected)) if typeof(expected) in [TYPE_FLOAT, TYPE_INT] else actual == expected
			check(same,"09:00 exact baseline "+target+"/"+key)
	var presets = preload("res://src/rendering/daylight_presets.gd")
	# User-approved noon and sunset snapshots from before this atmosphere task.
	for row in [
		[12.0,[1.30,1.08,1.18,1.06,0.0,0.0,1.60,42.0]],
		[14.0,[1.30,1.08,1.18,1.06,0.0,0.0,1.60,42.0]],
		[17.0,[0.56,0.48,0.55,0.52,1.0,0.0,0.21,115.0]],
		[18.3,[0.40,0.32,0.38,0.36,1.0,0.0,0.10,122.0]],
	]:
		var approved: Dictionary=presets.sample(row[0])
		for i in presets.KEYS.size():check(near(float(approved[presets.KEYS[i]]),float(row[1][i]),0.00001),"approved daypart retained %s/%s" % [row[0],presets.KEYS[i]])
	for edge in [0.0,5.5,6.0,7.0,11.0,12.0,14.0,14.2,16.0,17.0,18.3,19.0,24.0]:
		var left: Dictionary = presets.sample(edge-0.0001)
		var right: Dictionary = presets.sample(edge+0.0001)
		for key in presets.KEYS: check(absf(left[key]-right[key])<0.02,"smooth boundary %s %s" % [edge,key])
	check(sun.global_basis.is_equal_approx(rig._sun_basis),"09:00 restores original sun basis")
	var exposure := env.tonemap_exposure
	rig.apply(0.0)
	check(env.tonemap_exposure==exposure,"night never changes baseline exposure")
	# Switching back to a material already darkened at night must reuse its original base.
	var first: ShaderMaterial=water.duplicate()
	var second: ShaderMaterial=water.duplicate()
	var active := [first]
	var probe=preload("res://src/rendering/daylight_rig.gd").new()
	var empty:=Node.new()
	root.add_child(empty)
	empty.add_child(probe)
	var original: Color=first.get_shader_parameter("body_deep")
	probe.capture(empty,func(): return active[0])
	probe.apply(21.0)
	active[0]=second
	probe.apply(21.0)
	active[0]=first
	probe.apply(9.0)
	check(first.get_shader_parameter("body_deep")==original,"material switch back does not recapture darkened water")
	empty.queue_free()
	print("[daylight] %d checks, %d failures" % [checks, failures])
	main.queue_free()
	quit(1 if failures else 0)
