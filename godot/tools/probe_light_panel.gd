extends SceneTree
## 光照页端到端探针：证明滑杆真的改到了引擎对象，而且存档/复位都闭合。
##
## 单元级的清单核对在 `check_light_params.gd`，它只管「名字对不对、范围包不包得住」。
## 这里管另一件更容易假通过的事：控件接上了没有、写出去的值是不是真落在
## `Environment` 与 `Sun` 节点上、关掉面板重开还在不在。
##
## 用法：
##   SEA_SHOT_DIR=<dir> Godot --path godot --script res://tools/probe_light_panel.gd
## 退出码：0 全通，1 有失败项。

const CFG := "user://filter.cfg"

var main: Node
var failures := 0
var checks := 0
var out_dir := ""


func _init() -> void:
	out_dir = OS.get_environment("SEA_SHOT_DIR")
	call_deferred("run")


func check(ok: bool, text: String) -> void:
	checks += 1
	if ok:
		print("[light-probe] PASS ", text)
		return
	failures += 1
	print("[light-probe] FAIL ", text)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func run() -> void:
	# 这一轮会写 user://filter.cfg，先把旧的挪走，跑完还原 ——
	# 不然探针会把开发者当前调好的值当成「出厂值」来比对。
	var backup := ""
	if FileAccess.file_exists(CFG):
		backup = FileAccess.get_file_as_string(CFG)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))

	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	await frames(90)

	var grade = main.grade
	if grade == null:
		print("[light-probe] FAIL 没有 grade 面板")
		quit(1)
		return
	var sun := main.get_node("World/Lights/Sun") as DirectionalLight3D
	var env: Environment = main.world_env.environment
	check(sun != null, "World/Lights/Sun 存在")
	check(grade._sun == null or grade._sun == sun, "面板还没解析太阳时不应误抓补光")

	grade.set_open(true)
	grade.set_tab("light")
	await frames(10)
	check(grade._sun == sun, "面板解析到的是 Sun，不是补光")
	check(grade._light_widgets.size() == 30, "光照页控件数 30（实际 %d）" % grade._light_widgets.size())

	# ---- 1. 滑杆 → 引擎对象 ---------------------------------------------------
	var sun_energy := sun.light_energy
	grade._light_write("sun_energy", 1.23)
	check(is_equal_approx(sun.light_energy, 1.23), "太阳强度写进 light_energy（%.2f）" % sun.light_energy)

	var ambient := env.ambient_light_energy
	grade._light_write("ambient_energy", 0.77)
	check(is_equal_approx(env.ambient_light_energy, 0.77), "环境光写进 ambient_light_energy（%.2f）" % env.ambient_light_energy)

	var fog_before := env.fog_enabled
	grade._light_write("fog_enabled", not fog_before)
	check(env.fog_enabled == (not fog_before), "布尔项写进 fog_enabled")
	grade._light_write("fog_enabled", fog_before)

	# ---- 2. 朝向：两个虚拟轴互不干扰 -----------------------------------------
	var dir0: Vector2 = grade._sun_angles()
	grade._light_write("sun_elevation", 20.0)
	await frames(2)
	var after_el: Vector2 = grade._sun_angles()
	check(absf(after_el.x - 20.0) < 0.01, "高度角改到 20°（实际 %.2f）" % after_el.x)
	check(absf(after_el.y - dir0.y) < 0.01, "改高度角不动方位角（%.2f → %.2f）" % [dir0.y, after_el.y])

	grade._light_write("sun_azimuth", -45.0)
	await frames(2)
	var after_az: Vector2 = grade._sun_angles()
	check(absf(after_az.y - -45.0) < 0.01, "方位角改到 -45°（实际 %.2f）" % after_az.y)
	check(absf(after_az.x - 20.0) < 0.01, "改方位角不动高度角（%.2f）" % after_az.x)
	# 光真的是从高度角 20° 打下来的：方向向量的 y 分量应约为 -sin20°。
	var d := -sun.global_transform.basis.z
	check(absf(d.y - -sin(deg_to_rad(20.0))) < 0.01, "光照方向与高度角一致（dy=%.3f）" % d.y)

	# ---- 3. 关面板 → 重开，值还在 --------------------------------------------
	grade.set_open(false)
	await frames(4)
	check(FileAccess.file_exists(CFG), "关面板写出了 user://filter.cfg")
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	check(cfg.has_section("environment") and cfg.has_section("sun"),
		"存档里同时有 [environment] 和 [sun]（实际 %s）" % str(cfg.get_sections()))
	check(absf(float(cfg.get_value("sun", "sun_energy", -1.0)) - 1.23) < 0.001, "太阳强度进了存档")

	# 把运行期值改坏，再打开面板：应当被存档盖回来。
	sun.light_energy = 0.1
	env.ambient_light_energy = 0.1
	grade.set_open(true)
	grade.set_tab("light")
	await frames(6)
	check(absf(sun.light_energy - 1.23) < 0.001, "重开面板恢复太阳强度（%.2f）" % sun.light_energy)
	check(absf(env.ambient_light_energy - 0.77) < 0.001, "重开面板恢复环境光（%.2f）" % env.ambient_light_energy)

	# ---- 4. 滤镜页不能再把光照存档冲掉 --------------------------------------
	grade.set_tab("filter")
	await frames(6)
	grade.set_open(false)
	await frames(4)
	cfg = ConfigFile.new()
	cfg.load(CFG)
	check(cfg.has_section("sun") and cfg.has_section("environment"),
		"拖滤镜值之后光照存档还在（实际 %s）" % str(cfg.get_sections()))

	# ---- 5. 复位回到场景出厂值 ----------------------------------------------
	grade.set_open(true)
	grade.set_tab("light")
	await frames(6)
	grade._on_light_reset()
	await frames(4)
	check(is_equal_approx(sun.light_energy, sun_energy), "复位回到出厂太阳强度（%.2f）" % sun.light_energy)
	check(is_equal_approx(env.ambient_light_energy, ambient), "复位回到出厂环境光（%.2f）" % env.ambient_light_energy)
	var restored: Vector2 = grade._sun_angles()
	check(absf(restored.x - dir0.x) < 0.05 and absf(restored.y - dir0.y) < 0.05,
		"复位回到出厂朝向（%.2f / %.2f）" % [restored.x, restored.y])

	# ---- 6. 复制参数 ---------------------------------------------------------
	# headless 下没有剪贴板（DisplayServer 直接报 ERROR），那一行不能算失败 ——
	# 只验到「按下去不崩、状态栏报出了行数」。
	if DisplayServer.get_name() == "headless":
		grade._on_light_copy()
		check(grade._status.text.contains("光照参数"), "复制参数在无剪贴板环境下不崩（%s）" % grade._status.text)
	else:
		grade._on_light_copy()
		var pasted := DisplayServer.clipboard_get()
		check(pasted.contains("environment/ambient_light_energy"), "复制内容含环境键")
		check(pasted.contains("sun/light_energy"), "复制内容含太阳键")

	if out_dir != "":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out_dir.path_join("light-probe.png"))

	grade.set_open(false)
	await frames(2)
	main.queue_free()
	await frames(2)

	# 还原存档现场。
	if backup == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	else:
		var f := FileAccess.open(CFG, FileAccess.WRITE)
		f.store_string(backup)
		f.close()

	print("[light-probe] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
