extends SceneTree
## 光照页端到端探针：证明滑杆真的改到了引擎对象，而且「分时段」这件事真的分得开。
##
## 单元级的清单核对在 `check_light_params.gd`，它只管「名字对不对、范围包不包得住」。
## 这里管另外几件更容易假通过的事：
##   1. 控件接上了没有、写出去的值是不是真落在 `Environment` 与 `Sun` 节点上；
##   2. 改「上午」不会动「夕阳」—— 分时段调参的全部意义就在这一条；
##   3. 关面板重开还在不在，复位只清当前这一段。
##
## 用法：
##   SEA_SHOT_DIR=<dir> Godot --path godot --script res://tools/probe_light_panel.gd
## 退出码：0 全通，1 有失败项。

const CFG := "user://light_slots.cfg"
## 开场时刻 07:00 落在「上午」，所以这一段是默认选中的那一套。
const SEC := "spring|clear|morning"
const SEC_SUNSET := "spring|clear|sunset"
## 存档里的键名把 `/` 换成 `__`（见 `daylight_rig._encode_key`）。
const KEY_SUN := "sun__light_energy"

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
	# 这一轮会写 user://light_slots.cfg，先把旧的挪走，跑完还原 ——
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
	var rig = main.daylight_rig
	check(sun != null, "World/Lights/Sun 存在")
	check(rig != null, "场景里有昼夜装置（分时段偏移的唯一写入者）")

	grade.set_open(true)
	grade.set_tab("light")
	await frames(10)
	check(grade._sun == sun, "面板解析到的是 Sun，不是补光")
	# 30 项环境+太阳，7 项天空盒。天空盒是这一轮补的：玩家抬头看到的那层
	# 以前在面板里根本没有入口。
	check(grade._light_widgets.size() == 37, "光照页控件数 37（实际 %d）" % grade._light_widgets.size())
	check(grade._slot == "morning", "打开面板站在当前时段「上午」（实际 %s）" % grade._slot)

	# ---- 1. 滑杆 → 引擎对象 ---------------------------------------------------
	var sun_energy := sun.light_energy
	var ambient := env.ambient_light_energy
	grade._light_write("sun_energy", 1.23)
	check(is_equal_approx(sun.light_energy, 1.23), "太阳强度写进 light_energy（%.2f）" % sun.light_energy)

	grade._light_write("ambient_energy", 0.77)
	check(is_equal_approx(env.ambient_light_energy, 0.77), "环境光写进 ambient_light_energy（%.2f）" % env.ambient_light_energy)

	var fog_before := env.fog_enabled
	grade._light_write("fog_enabled", not fog_before)
	check(env.fog_enabled == (not fog_before), "布尔项写进 fog_enabled")
	grade._light_write("fog_enabled", fog_before)

	# ---- 2. 只改这一段：切到夕阳，太阳强度不能是刚刚那个 1.23 ---------------
	grade._pick_slot("slot", "sunset")
	await frames(4)
	check(grade._slot == "sunset", "侧栏切到「夕阳」")
	check(absf(sun.light_energy - 1.23) > 0.01,
		"夕阳段没有被上午的改动染上（实际 %.2f）" % sun.light_energy)
	var sunset_natural := sun.light_energy
	check(sunset_natural < sun_energy, "夕阳太阳本来就比上午弱（%.2f < %.2f）" % [sunset_natural, sun_energy])

	# 在夕阳段改一个不同的值，两段各存各的。
	grade._light_write("sun_energy", 0.66)
	await frames(4)
	check(absf(sun.light_energy - 0.66) < 0.01, "夕阳段改成 0.66（实际 %.2f）" % sun.light_energy)

	grade._pick_slot("slot", "morning")
	await frames(4)
	check(absf(sun.light_energy - 1.23) < 0.01, "切回上午还是 1.23（实际 %.2f）" % sun.light_energy)
	check(rig.offset_count("spring", "clear", "sunset") > 0, "夕阳段存下了自己的偏移")
	check(rig.offset_count("spring", "clear", "morning") > 0, "上午段也存下了自己的偏移")

	# ---- 3. 朝向：两个虚拟轴互不干扰 -----------------------------------------
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

	# ---- 4. 关面板 → 画面回到实际时刻，偏移落盘 ------------------------------
	grade.set_open(false)
	await frames(6)
	check(not rig.is_suspended(), "写盘期间没有把装置永久停在暂停态")
	check(FileAccess.file_exists(CFG), "关面板写出了 user://light_slots.cfg")
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	check(cfg.has_section(SEC), "存档里有上午这一段（实际 %s）" % str(cfg.get_sections()))
	check(cfg.has_section(SEC_SUNSET), "存档里有夕阳这一段")
	var saved := float(cfg.get_value(SEC, KEY_SUN, -999.0))
	check(absf(saved - (1.23 - sun_energy)) < 0.01, "上午存的是差值 %.3f（实际 %.3f）" % [1.23 - sun_energy, saved])

	# ---- 5. 重新读盘 → 值还在 ------------------------------------------------
	rig.load_offsets({})
	await frames(2)
	check(absf(sun.light_energy - sun_energy) < 0.01, "清空偏移后回到基准（%.2f）" % sun.light_energy)
	grade._reload_light_cfg()
	await frames(2)
	grade.set_open(true)
	grade.set_tab("light")
	await frames(6)
	check(absf(sun.light_energy - 1.23) < 0.01, "重读存档恢复上午的太阳强度（%.2f）" % sun.light_energy)
	check(absf(env.ambient_light_energy - 0.77) < 0.001, "重读存档恢复环境光（%.2f）" % env.ambient_light_energy)

	# ---- 6. 滤镜页不能把光照偏移冲掉 ----------------------------------------
	grade.set_tab("filter")
	await frames(6)
	grade.set_open(false)
	await frames(6)
	cfg = ConfigFile.new()
	cfg.load(CFG)
	check(cfg.has_section(SEC), "拖滤镜值之后光照偏移还在（实际 %s）" % str(cfg.get_sections()))

	# ---- 7. 复位只清当前这一段 ----------------------------------------------
	grade.set_open(true)
	grade.set_tab("light")
	await frames(6)
	check(grade._slot == "morning", "重开面板又站回当前时段")
	grade._on_light_reset()
	await frames(4)
	check(absf(sun.light_energy - sun_energy) < 0.01, "复位回到场景出厂太阳强度（%.2f）" % sun.light_energy)
	check(absf(env.ambient_light_energy - ambient) < 0.01, "复位回到场景出厂环境光（%.2f）" % env.ambient_light_energy)
	check(rig.offset_count("spring", "clear", "morning") == 0, "上午的偏移被清空")
	check(rig.offset_count("spring", "clear", "sunset") > 0, "夕阳的偏移没被连坐")
	var restored: Vector2 = grade._sun_angles()
	check(absf(restored.x - dir0.x) < 0.05 and absf(restored.y - dir0.y) < 0.05,
		"复位回到出厂朝向（%.2f / %.2f）" % [restored.x, restored.y])

	# ---- 8. 天空盒：按段调 ---------------------------------------------------
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
	check(sky_mat != null, "环境挂的是 ProceduralSkyMaterial（天空盒可调）")
	if sky_mat != null:
		grade._pick_slot("slot", "sunset")
		await frames(4)
		grade._light_write("sky_horizon", Color(1.0, 0.30, 0.10))
		await frames(4)
		check(sky_mat.sky_horizon_color.is_equal_approx(Color(1.0, 0.30, 0.10)),
			"天空盒地平线色真写进材质（%s）" % sky_mat.sky_horizon_color.to_html(false))
		grade._pick_slot("slot", "noon")
		await frames(4)
		check(not sky_mat.sky_horizon_color.is_equal_approx(Color(1.0, 0.30, 0.10)),
			"正午的天空没被夕阳的改动染上（%s）" % sky_mat.sky_horizon_color.to_html(false))
		check(rig.offset_count("spring", "clear", "sunset") > 0, "夕阳段记下了天空盒偏移")

	# ---- 9. 水面：海水色也按段调 ---------------------------------------------
	# 这一段最要紧：水面着色器是纯 EMISSION，海水色是它唯一的亮度来源，
	# 而它以前走 `adopt` 改的是全天基准 —— 调夕阳会把白天一起改掉。
	grade.set_tab("water")
	await frames(6)
	var water_mat: ShaderMaterial = null
	grade._ensure_water()
	water_mat = grade._water_mat
	check(water_mat != null, "面板解析到水面 ShaderMaterial")
	if water_mat != null:
		grade._pick_slot("slot", "sunset")
		await frames(4)
		var sun_body := Color(1.0, 0.22, 0.06)
		grade._water_write("body_shallow", sun_body)
		await frames(4)
		check((water_mat.get_shader_parameter("body_shallow") as Color).is_equal_approx(sun_body),
			"浅水色真写进着色器（%s）" % (water_mat.get_shader_parameter("body_shallow") as Color).to_html(false))
		grade._pick_slot("slot", "noon")
		await frames(4)
		check(not (water_mat.get_shader_parameter("body_shallow") as Color).is_equal_approx(sun_body),
			"正午的海水没被夕阳的改动染上（%s）" % (water_mat.get_shader_parameter("body_shallow") as Color).to_html(false))
		check(rig.offset_count("spring", "clear", "sunset") > 0, "夕阳段记下了水面偏移")

	# ---- 9b. 只拖水面时偏移也必须自己落盘（回归项） --------------------------
	# 以前 `_water_write` 只置 `_water_dirty`，而落盘走 `_save_light_cfg()`，
	# 那个被 `_light_dirty` 卡着。于是「只调水面」的用户关掉面板时，
	# 一条差值都没写进 `light_slots.cfg` —— 面板里看着生效、重开全没了，
	# 而写入按钮照报成功。这一条盯的就是那个组合。
	grade.set_tab("water")
	grade._pick_slot("slot", "dawn")
	await frames(4)
	grade._light_dirty = false  # 模拟「从头到尾只碰过水面页」
	grade._water_write("body_deep", Color(0.9, 0.30, 0.20))
	await frames(2)
	grade.set_open(false)
	await frames(6)
	cfg = ConfigFile.new()
	cfg.load(CFG)
	check(cfg.has_section("spring|clear|dawn"),
		"只调水面、关面板也写出了 dawn 这一段（实际 %s）" % str(cfg.get_sections()))
	check(cfg.has_section_key("spring|clear|dawn", "water__body_deep"),
		"水面差值进了 light_slots.cfg（键 water__body_deep）")

	# ---- 9c. 「写入 watertres」不得假装改了东西 ------------------------------
	# 海水色这一批存的是差值，文件里那一行是 09:00 基准。旧实现把基准原样
	# 抄回去、还报「已写入 N 项」，用户回游戏一看没变化，只能怀疑按钮坏了。
	var mat_path := "res://assets/materials/water.tres"
	var mat_before := FileAccess.get_file_as_string(mat_path)
	grade.set_open(true)
	grade.set_tab("water")
	await frames(6)
	grade._on_water_save()
	await frames(2)
	check(grade._status.text.contains("light_slots.cfg"),
		"状态栏说清了改动存在 light_slots.cfg（%s）" % grade._status.text)
	check(not grade._status.text.begins_with("已写入 的 0"),
		"状态栏不再给出空头承诺")
	# 无论写没写，恢复文件原文（验证工程把 assets 目录联接回仓库，
	# 写穿过去就是改真文件 —— 这条探针不许在仓库里留下痕迹）。
	if FileAccess.get_file_as_string(mat_path) != mat_before:
		var restore := FileAccess.open(mat_path, FileAccess.WRITE)
		if restore != null:
			restore.store_string(mat_before)
			restore.close()
	check(FileAccess.get_file_as_string(mat_path) == mat_before,
		"water.tres 逐字节没有被本次探针改动")

	# ---- 10. 滤镜页的对比度不再被昼夜覆盖 ------------------------------------
	# 回归项：`_apply_env` 每帧把 `adjustment_contrast` 按 night 重算，
	# 旧实现直接写 `_env` 只能闪一帧。这条断言就是盯那件事的。
	grade.set_tab("filter")
	grade._pick_slot("slot", "night")
	await frames(4)
	grade._write("contrast", 1.42)
	rig.apply(19.0)
	await frames(2)
	check(absf(env.adjustment_contrast - 1.42) < 0.01,
		"对比度改完跑过一帧仍在 1.42（实际 %.2f）" % env.adjustment_contrast)
	grade.set_tab("light")
	await frames(4)

	# ---- 11. 天气 / 季节：点一下立刻换渲染上下文 -----------------------------
	# 回归项：偏移按 `季节|天气|时段` 三键存，而 `_apply_offsets` 以前只读游戏
	# 实际那一组。游戏里是晴的时候点「多云」，差值落进 `spring|cloudy|*`，
	# 画面却还在读 `spring|clear|*` —— 滑杆看起来是死的，存下来的数在游戏里
	# 也永远看不到。这一组断言盯的就是「面板说切了，画面真的切了」。
	grade._pick_slot("slot", "noon")
	await frames(4)
	var noon_clear := sun.light_energy
	check(rig.effective_weather() == "clear", "面板打开时预览上下文 = 游戏实际天气（%s）" % rig.effective_weather())

	grade._pick_slot("weather", "cloudy")
	await frames(4)
	check(rig.effective_weather() == "cloudy",
		"点「多云」渲染上下文立刻切过去（实际 %s）" % rig.effective_weather())
	check(rig.weather() == "clear", "游戏实际天气没被面板改掉（%s）" % rig.weather())
	check(absf(sun.light_energy - noon_clear) < 0.01,
		"多云这套还没调过时画面与晴一致（%.2f）" % sun.light_energy)
	check(grade._status.text.contains("预览中"), "状态栏说出了正在预览（%s）" % grade._status.text)

	grade._light_write("sun_energy", 1.11)
	await frames(4)
	check(absf(sun.light_energy - 1.11) < 0.01, "多云段的滑杆立刻生效（实际 %.2f）" % sun.light_energy)
	check(rig.offset_count("spring", "cloudy", "noon") > 0, "差值存进 spring|cloudy|noon")
	check(rig.offset_count("spring", "clear", "noon") == 0, "晴这一套没被连带写上")

	grade._pick_slot("weather", "clear")
	await frames(4)
	check(absf(sun.light_energy - noon_clear) < 0.01, "切回晴立刻回到晴那一套（%.2f）" % sun.light_energy)
	check(rig.offset_count("spring", "cloudy", "noon") > 0, "切回晴没抹掉多云的偏移")

	grade._pick_slot("season", "summer")
	await frames(4)
	check(rig.effective_season() == "summer", "点「夏」渲染上下文切到夏季（实际 %s）" % rig.effective_season())
	grade._light_write("sun_energy", 0.83)
	await frames(4)
	check(absf(sun.light_energy - 0.83) < 0.01, "夏季段的滑杆立刻生效（实际 %.2f）" % sun.light_energy)
	check(rig.offset_count("summer", "clear", "noon") > 0, "差值存进 summer|clear|noon")
	grade._pick_slot("season", "spring")
	await frames(4)
	check(absf(sun.light_energy - noon_clear) < 0.01, "切回春回到春季那一套（%.2f）" % sun.light_energy)

	# 关面板必须把「渲染上下文」也放掉，否则游戏会一直停在面板最后点的天气上。
	grade.set_open(false)
	await frames(6)
	check(not rig.is_previewing(), "关面板放掉了预览上下文")
	check(rig.effective_weather() == "clear" and rig.effective_season() == "spring",
		"关面板后渲染回到游戏实际季节/天气（%s / %s）" % [rig.effective_season(), rig.effective_weather()])
	cfg = ConfigFile.new()
	cfg.load(CFG)
	check(cfg.has_section("spring|cloudy|noon"), "多云的偏移落盘了（%s）" % str(cfg.get_sections()))
	grade.set_open(true)
	grade.set_tab("light")
	await frames(6)

	# ---- 12. 复制参数 ---------------------------------------------------------
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

	# 截图只在真实渲染下拍：headless 没有 `frame_post_draw` 这个信号，
	# 走到 `await` 会一直等下去，最后以 180 秒超时退出（表现为 exit=124，
	# 日志里却全是 PASS，很容易被当成通过）。
	if out_dir != "" and DisplayServer.get_name() != "headless":
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
