extends CanvasLayer
class_name ColorGradePanel
## 运行期调试面板（P 键开关），三页：
##
##   滤镜 —— 整幅画面的最终调色，改的是 `WorldEnvironment` 上那个 Environment：
##           曝光 → tonemap_exposure，亮度/对比度/饱和度 → adjustment_*。
##   光照 —— 环境与太阳。环境是同一个 Environment 的天空/环境光/泛光/遮蔽/雾，
##           太阳是 `World/Lights/Sun` 这盏平行光（强度、色温、朝向、阴影）。
##           清单在 `light_params.gd`，这里只负责生成控件。
##   水面 —— `assets/materials/water.tres` 上所有还能改的参数，按着色器的
##           group 分成水体 / 表面细节 / 天空反射 / 太阳高光 / 波纹 / 泡沫 /
##           波浪几何 / 输出。清单在 `water_params.gd`，这里只负责生成控件。
##
## 三页都遵守同一套约定：拖动即时生效、可一键复位、可复制、可写回资源文件、
## 数值记在 `user://` 下（`filter.cfg` / `water.cfg`），下次启动还是你调好的样子 ——
## 不然每次重启都要重调一遍。
##
## 场景里的默认值来自资源文件本身，所以「复位」回到的是那份文件的值，
## 不是硬编码的数字。
##
## 「滤镜」与「光照」改的是同一批引擎对象，但**不是同一批属性**：滤镜只有 4 个
## 最终调色项，光照是环境与太阳的整套参数。合成一页会变成三十多行的长列表，
## 把曝光埋到看不见的地方 —— 那正是最常调的一项。

const UiFontLib = preload("res://src/ui/ui_font.gd")
const ParamsLib = preload("res://src/rendering/water_params.gd")
const ParamsLibAbs = preload("res://src/rendering/water_params_absorption.gd")
const LightParamsLib = preload("res://src/rendering/light_params.gd")

const CFG_PATH := "user://filter.cfg"
const WATER_CFG_PATH := "user://water.cfg"
const WATER_MAT_PATH := "res://assets/materials/water.tres"
const ABSORPTION_MAT_PATH := "res://assets/materials/water_absorption.tres"
const ENV_MAT_PATH := "res://assets/materials/world_env.tres"
const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const SUN_NODE_PATH := "World/Lights/Sun"

## 两套水。各自有独立的参数表、材质资源、存档 section 和收藏，
## 面板同一时间只显示其中一套 —— 「方案」按哪个，下面的滑杆就是哪套的。
##
## 为什么不合并成一张表：两套的身体模型不一样，`absorption` 这个名字在两边
## 意义不同（旧方案是床面每米吸收多少，吸收式是被吃掉的波长颜色）。合成一张
## 表，"复位到出厂"就没有唯一答案了。
const SCHEME_ORIGINAL := "original"
const SCHEME_ABSORPTION := "absorption"
const SCHEME_ORDER := [SCHEME_ORIGINAL, SCHEME_ABSORPTION]
const SCHEME_LABELS := {
	SCHEME_ORIGINAL: "原版",
	SCHEME_ABSORPTION: "吸收式",
}
const SCHEME_MATS := {
	SCHEME_ORIGINAL: WATER_MAT_PATH,
	SCHEME_ABSORPTION: ABSORPTION_MAT_PATH,
}
## 每种方案在 `water.cfg` 里的 section。旧存档就在 `water` 这一段，
## 新方案另起一段，所以升级后原来的参数一个都不会丢。
const SCHEME_SECTIONS := {
	SCHEME_ORIGINAL: "water",
	SCHEME_ABSORPTION: "water_absorption",
}
## 收藏里记「这套属于哪个方案」的键。
const PRESET_SCHEME_KEY := "__scheme"

## 收藏的参数组合。和 `water.cfg` 分开放：那个记的是「上次调到哪」，
## 这个是「我特意存下来的几套」，性质不同。
const WATER_PRESET_PATH := "user://water_presets.cfg"

## 预设下拉里的第一项，永远指向当前方案的资源文件，不可删。
const PRESET_FACTORY := "出厂（材质文件）"
## `water.cfg` 里记出厂指纹的键。指纹变了说明 water.tres 换了另一套数，
## 旧存档立刻作废 —— 否则改了出厂值重启还是被老存档盖住。
const CFG_SIG_KEY := "__mat_sig"

const TAB_FILTER := "filter"
const TAB_LIGHT := "light"
const TAB_WATER := "water"

const EXPOSURE_MIN := 0.4
const EXPOSURE_MAX := 2.0
const ADJ_MIN := 0.0
const ADJ_MAX := 2.0

const PANEL_WIDTH := 352
## 名字列 / 数值列的宽度。窄一点才能给滑杆留出可拖的长度。
const NAME_W := 92
const VALUE_W := 48

var _env: Environment
var _defaults := {}
var _rows := {}

## 太阳光节点。可能找不到（别的场景没按约定摆放灯光），所有写入都先判空。
var _sun: DirectionalLight3D
## 光照页的出厂值快照：`env` / `sun` 两份属性字典 + `sun_dir` 两个角度。
## 在第一次 `_ensure_env` / `_ensure_sun` 时抓，那一刻还没套过存档。
var _light_defaults := {}
var _light_spec := {}
var _light_widgets := {}
var _light_dirty := false
## 存档是否已经套过。启动时 `_apply_saved_on_start` 会套一次，但那时场景可能
## 还没装好（环境 / 太阳都没解析到），所以打开面板时补一次，补过就不再补 ——
## 否则用户手改的值会被存档反复盖回去。
var _light_cfg_loaded := false

var _font: Font
var _panel: PanelContainer
var _body: VBoxContainer
var _filter_body: VBoxContainer
var _light_wrap: VBoxContainer
var _light_body: VBoxContainer
var _light_scroll: ScrollContainer
var _water_wrap: VBoxContainer
var _water_body: VBoxContainer
var _water_scroll: ScrollContainer
var _status: Label
var _tab := TAB_FILTER
var _tab_buttons := {}

## 参数清单摊平后的副本，省掉每次读盘都重新摊一次。
var _spec := {}
## 当前方案 id（`original` / `absorption`）。切换会重建整页控件。
var _scheme := SCHEME_ORIGINAL
## 方案 id -> 顶部那两个开关按钮，切换后要同步按下态。
var _scheme_buttons := {}
## 底部「写入 xxx.tres」按钮，切方案时要改文案。
var _save_button: Button
## 方案 id -> 参数清单脚本，`_ready` 里填。
var _scheme_params := {}
## 生成顺序（schema 的声明顺序，别用字典 key 顺序，那是乱的）。
var _order: Array[String] = []
## key -> 把值推回控件用的 Callable。
var _water_widgets := {}
## 回填控件时屏蔽回调，否则 `sync` 一个值就会触发一次写材质。
var _syncing := false

var _water_mat: ShaderMaterial
var _water_node: MeshInstance3D
## Water 节点上 `wave_scale` 的出厂值。它写在 `main.tscn` 的导出属性里，
## 不在 `water.tres` 里，所以「复位」得单独记一份，不能拿清单的 default 顶替。
var _factory_wave_scale := 1.0
var _factory_captured := false
## water.tres 里的出厂值，`_water_default()` 惰性填充。
var _file_defaults := {}
var _file_defaults_loaded := false
## 只有真的动过滑块才写 `user://water.cfg`。
## 否则「打开看一眼再关掉」就会把当时的值存成一套存档，
## 之后改 water.tres 的出厂值会全部被这份存档盖住。
var _water_dirty := false

## 收藏下拉当前列出的预设名（不含出厂那一项），顺序即显示顺序。
var _preset_names: Array[String] = []
## 下拉每一项的描述，index 与 OptionButton 的 item 一一对应。
## `kind` 取 factory / builtin / user，分隔线记成 sep（选中时忽略）。
var _preset_items: Array[Dictionary] = []
var _preset_option: OptionButton
var _preset_delete: Button
var _name_dialog: AcceptDialog
var _name_edit: LineEdit
var _delete_dialog: ConfirmationDialog


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 这是调试面板，不是玩家界面：深色皮肤自己画，别让 CozyUI 接管
	# （它会把分组标题染成珊瑚色、把每个按钮顶到 38 px 高，排版会散）。
	set_meta("cozy_skip", true)
	_font = UiFontLib.make(PackedStringArray(["Hiragino Sans GB", "PingFang SC", "Heiti SC", "Microsoft YaHei", "Helvetica Neue"]))
	_rebuild_spec()
	_light_spec = LightParamsLib.flat()
	_build()
	visible = false
	# 先读盘：读档值要盖回场景默认值，否则每次启动都回到 1.0。
	call_deferred("_apply_saved_on_start")


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var code := key.keycode if key.keycode != 0 else key.physical_keycode
	if code != KEY_P:
		return
	set_open(not visible)
	get_viewport().set_input_as_handled()


func set_open(open: bool) -> void:
	visible = open
	if open:
		_ensure_env()
		_sync_from_env()
		_refresh_labels()
		_ensure_sun()
		# 启动那次套存档可能没赶上（场景还没装完），这里补一次。
		if not _light_cfg_loaded:
			_apply_light_cfg()
		_sync_light()
		_ensure_water()
		_sync_water()
	else:
		_save_cfg()
		_save_light_cfg()
		_save_water_cfg()


## 供调试参数调用：`--grade` 启动就打开，`--grade=1.1,1.06,1.03` 直接套一组数。
func set_values(exposure: float, brightness: float, contrast: float, saturation: float) -> void:
	_ensure_env()
	if _env == null:
		return
	_env.tonemap_exposure = clampf(exposure, EXPOSURE_MIN, EXPOSURE_MAX)
	_env.adjustment_enabled = true
	_env.adjustment_brightness = clampf(brightness, ADJ_MIN, ADJ_MAX)
	_env.adjustment_contrast = clampf(contrast, ADJ_MIN, ADJ_MAX)
	_env.adjustment_saturation = clampf(saturation, ADJ_MIN, ADJ_MAX)
	_sync_from_env()
	_refresh_labels()


## `--water` 直接从「水面」页打开，方便截图和交接时直接指到那一页。
## `--light` 同理，指到光照页。
func set_tab(id: String) -> void:
	_set_tab(id)
	if not visible:
		return
	if _tab == TAB_WATER:
		_ensure_water()
		_sync_water()
	elif _tab == TAB_LIGHT:
		_ensure_sun()
		_sync_light()


# ---- 环境解析 ---------------------------------------------------------------

func _ensure_env() -> void:
	if _env != null:
		return
	var we: WorldEnvironment = null
	var scene := get_tree().current_scene
	if scene != null:
		we = scene.get_node_or_null("World/WorldEnvironment") as WorldEnvironment
	if we == null:
		# 兜底：场景没按约定摆放时，找树里第一个。
		for node in get_tree().get_nodes_in_group("world_environment"):
			we = node as WorldEnvironment
			if we != null:
				break
	if we == null:
		for node in get_tree().root.get_children():
			we = _find_env_recursive(node)
			if we != null:
				break
	if we != null and we.environment != null:
		_env = we.environment
		_defaults = _snapshot(_env)
		_capture_light_defaults()


## 太阳光的出厂快照。和环境的快照分开记：两者的来源不一样
## （环境来自 `world_env.tres`，太阳来自 `scenes/main.tscn` 的节点属性），
## 混在一个字典里，复位时就得靠属性名去猜它属于谁。
func _capture_light_defaults() -> void:
	var env := {}
	for key in LightParamsLib.keys():
		var spec: Dictionary = _light_spec.get(key, {})
		if spec.is_empty() or String(spec.target) != LightParamsLib.TARGET_ENV:
			continue
		var v: Variant = _light_read(key)
		if v != null:
			env[key] = v
	_light_defaults["env"] = env
	if is_instance_valid(_sun):
		var sun := {}
		for key in LightParamsLib.keys():
			var spec2: Dictionary = _light_spec.get(key, {})
			if spec2.is_empty() or String(spec2.target) != LightParamsLib.TARGET_SUN:
				continue
			var v2: Variant = _light_read(key)
			if v2 != null:
				sun[key] = v2
		_light_defaults["sun"] = sun
		_light_defaults["sun_dir"] = _sun_angles()


func _ensure_sun() -> void:
	if is_instance_valid(_sun):
		return
	var scene := get_tree().current_scene
	if scene != null:
		_sun = scene.get_node_or_null(SUN_NODE_PATH) as DirectionalLight3D
	if _sun == null:
		_sun = _find_sun_recursive(get_tree().root)
	if _sun != null:
		_capture_light_defaults()


func _find_sun_recursive(node: Node) -> DirectionalLight3D:
	var l := node as DirectionalLight3D
	# 只认名字：场景里还有三盏补光，随便挑一盏会让「太阳强度」改的是补光。
	if l != null and String(l.name) == "Sun":
		return l
	for c in node.get_children():
		var found := _find_sun_recursive(c)
		if found != null:
			return found
	return null


func _find_env_recursive(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node as WorldEnvironment
	for c in node.get_children():
		var found := _find_env_recursive(c)
		if found != null:
			return found
	return null


func _snapshot(env: Environment) -> Dictionary:
	return {
		"exposure": env.tonemap_exposure,
		"brightness": env.adjustment_brightness,
		"contrast": env.adjustment_contrast,
		"saturation": env.adjustment_saturation,
	}


# ---- 光照：环境 + 太阳 --------------------------------------------------------
#
# 这一层和「水面」那层的区别：水面读写的是一份 `ShaderMaterial` 的 uniform，
# 光照读写的是引擎对象的属性。写法统一在 `_light_read` / `_light_write` 两个口，
# 面板控件只跟 key 打交道 —— 这样加一个参数只改清单，不用碰 UI。

## 面板键 → 真正接鼠标的那个对象。找不到就返回 null，调用方自己判空。
func _light_target(target: String) -> Object:
	if target == LightParamsLib.TARGET_ENV:
		_ensure_env()
		return _env
	_ensure_sun()
	return _sun


func _light_read(key: String) -> Variant:
	var spec: Dictionary = _light_spec.get(key, {})
	if spec.is_empty():
		return null
	var prop := String(spec.prop)
	if prop.begins_with("dir:"):
		# 朝向的两个虚拟轴没有同名属性，只能从基算出来。
		if not is_instance_valid(_sun):
			return null
		var angles := _sun_angles()
		return angles.x if prop == "dir:elevation" else angles.y
	var obj := _light_target(String(spec.target))
	if obj == null:
		return null
	return obj.get_indexed(NodePath(prop))


func _light_write(key: String, value: Variant) -> void:
	var spec: Dictionary = _light_spec.get(key, {})
	if spec.is_empty():
		return
	var prop := String(spec.prop)
	var target := String(spec.target)
	if target == LightParamsLib.TARGET_SUN and prop.begins_with("dir:"):
		if not is_instance_valid(_sun):
			return
		# 两个虚拟轴各自只改自己那一维：另一维读当前朝向，
		# 这样先拖高度角再拖方位角不会互相抹掉。
		var angles := _sun_angles()
		if prop == "dir:elevation":
			_set_sun_angles(float(value), angles.y)
		else:
			_set_sun_angles(angles.x, float(value))
		_light_dirty = true
		return
	var obj := _light_target(target)
	if obj == null:
		return
	obj.set_indexed(NodePath(prop), _coerce_light(spec, value))
	_light_dirty = true


func _coerce_light(spec: Dictionary, value: Variant) -> Variant:
	match String(spec.kind):
		"float":
			return float(value)
		"bool":
			return bool(value)
		"color":
			return _as_color3(value)
	return value


## 太阳的朝向，用「相对海平面」的语义给出：高度角（正数朝上）与方位角（0 = +Z）。
## 不直接暴露 `rotation_degrees.x/y`：那是欧拉角，跟「太阳多高」隔着一层，
## 调参时脑子要换算一次，而且和场景里 look_at 出来的基不直观对应。
## 调用前先确认 `_sun` 有效 —— 没有太阳时这里的返回值没有意义。
func _sun_angles() -> Vector2:
	if not is_instance_valid(_sun):
		return Vector2.ZERO
	var d := -_sun.global_transform.basis.z
	var elevation := rad_to_deg(asin(clampf(-d.y, -1.0, 1.0)))
	var azimuth := rad_to_deg(atan2(d.x, d.z))
	return Vector2(elevation, azimuth)


func _set_sun_angles(elevation: float, azimuth: float) -> void:
	if not is_instance_valid(_sun):
		return
	# 高度角贴到 0 或 90 时 look_at 的 up 会退化，夹在 1..89 最稳。
	var el := deg_to_rad(clampf(elevation, 1.0, 89.0))
	var az := deg_to_rad(azimuth)
	var dir := Vector3(sin(az) * cos(el), -sin(el), cos(az) * cos(el))
	var origin := _sun.global_position
	_sun.look_at_from_position(origin, origin + dir, Vector3.UP)


func _sync_light() -> void:
	if _light_widgets.is_empty():
		return
	_syncing = true
	for key in _light_widgets.keys():
		var v: Variant = _light_read(key)
		if v == null:
			continue
		(_light_widgets[key] as Callable).call(v)
	_syncing = false


func _on_light_reset() -> void:
	var env: Dictionary = _light_defaults.get("env", {})
	var sun: Dictionary = _light_defaults.get("sun", {})
	if env.is_empty() and sun.is_empty():
		_flash("没抓到出厂值，无法复位（场景里找不到环境或太阳）")
		return
	_syncing = true
	for key in env.keys():
		_light_write(key, env[key])
	# 太阳先复位朝向再复位其余属性：`_light_write` 改朝向会重算基，
	# 但不会动 light_energy 之类，所以顺序不影响结果，只是读起来顺。
	if not sun.is_empty() and is_instance_valid(_sun):
		var dir: Vector2 = _light_defaults.get("sun_dir", Vector2.ZERO)
		_set_sun_angles(dir.x, dir.y)
	for key2 in sun.keys():
		_light_write(key2, sun[key2])
	_syncing = false
	_sync_light()
	_light_dirty = true
	_save_light_cfg()
	_flash("光照已回到场景默认值")


## 复制成能直接对账的文本。太阳朝向给的是两个角度，不是欧拉角 ——
## 抄进场景时用 `look_at` 那一套更不容易出错。
func _on_light_copy() -> void:
	var lines := PackedStringArray()
	for g in LightParamsLib.GROUPS:
		for row in g.rows:
			var key := String(row.key)
			var v: Variant = _light_read(key)
			if v == null:
				continue
			var target := String(row.target)
			if String(row.prop) == "dir:elevation" or String(row.prop) == "dir:azimuth":
				lines.append("# sun.%s = %s（虚拟轴，写回场景时会转成朝向）" % [key, var_to_str(v)])
				continue
			lines.append("%s/%s = %s" % ["environment" if target == LightParamsLib.TARGET_ENV else "sun",
				String(row.prop), var_to_str(v)])
	var text := "\n".join(lines)
	DisplayServer.clipboard_set(text)
	_flash("已复制 %d 行光照参数" % lines.size())


func _on_light_save() -> void:
	if OS.has_feature("template"):
		_flash("导出版无法写回 res://，请用「复制参数」")
		return
	var notes := PackedStringArray()
	var ok := 0
	_ensure_env()
	if _env != null:
		# `ResourceSaver` 一律用 LF 落盘，而仓库在 Windows 上是 CRLF 检出。
		# 不还原的话整份文件在 diff 里全变 —— 账本里记过一次「CRLF 行尾幻影」，
		# 就是这里踩的。改前记下原风格，存完照原样写回去。
		var before := FileAccess.get_file_as_string(ENV_MAT_PATH)
		var crlf := before.contains("\r\n")
		var err := ResourceSaver.save(_env, ENV_MAT_PATH)
		if err == OK:
			if crlf:
				_restore_crlf(ENV_MAT_PATH)
			ok += 1
			notes.append("world_env.tres")
		else:
			_flash("环境写入失败：%s" % error_string(err))
			return
	if is_instance_valid(_sun):
		var problem := _write_sun_to_scene()
		if problem == "":
			ok += 1
			notes.append("main.tscn 的 Sun")
		else:
			_flash("太阳写入失败：%s" % problem)
			return
	if ok == 0:
		_flash("既没找到环境也没找到太阳，无可写入")
		return
	_light_dirty = false
	_save_light_cfg()
	_flash("已写入 %s（重开游戏生效）" % "、".join(notes))


## 把一份刚被 `ResourceSaver` 写成 LF 的文件改回 CRLF。
## 只做换行替换，不碰内容 —— 所以它只会消掉 diff 里那些「整文件都变」的假改动。
func _restore_crlf(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() or text.contains("\r\n"):
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text.replace("\n", "\r\n"))
	f.close()


## 把太阳的属性写回 `scenes/main.tscn`。
##
## 为什么不整份重存：那会把场景里所有手工调过的节点、unique_id、资源引用
## 重新排一遍，diff 变成几千行，谁也不敢再提交。这里只改 Sun 这个节点块里
## 的几行属性，其余字节不动。
##
## 返回空串表示成功，否则是要报给用户的原因。
func _write_sun_to_scene() -> String:
	var text := FileAccess.get_file_as_string(MAIN_SCENE_PATH)
	if text.is_empty():
		return "读不到 %s" % MAIN_SCENE_PATH
	var eol := "\r\n" if text.contains("\r\n") else "\n"
	var lines := text.replace("\r\n", "\n").split("\n")

	var start := -1
	for i in lines.size():
		if String(lines[i]).begins_with("[node name=\"Sun\""):
			start = i
			break
	if start < 0:
		return "main.tscn 里找不到 Sun 节点"

	var stop := lines.size()
	for i in range(start + 1, lines.size()):
		if String(lines[i]).begins_with("["):
			stop = i
			break

	var values := {
		"transform": var_to_str(_sun.transform),
		"light_color": var_to_str(_sun.light_color),
		"light_energy": var_to_str(_sun.light_energy),
		"light_angular_distance": var_to_str(_sun.light_angular_distance),
		"shadow_enabled": var_to_str(_sun.shadow_enabled),
		"shadow_opacity": var_to_str(_sun.shadow_opacity),
		"shadow_blur": var_to_str(_sun.shadow_blur),
		"shadow_bias": var_to_str(_sun.shadow_bias),
		"shadow_normal_bias": var_to_str(_sun.shadow_normal_bias),
		"directional_shadow_max_distance": var_to_str(_sun.directional_shadow_max_distance),
	}

	for key in values.keys():
		var line := "%s = %s" % [key, values[key]]
		var prefix := "%s = " % key
		var found := false
		for i in range(start + 1, stop):
			if String(lines[i]).begins_with(prefix):
				lines[i] = line
				found = true
				break
		if not found:
			# 缺这一项就补在块末尾（`stop` 之前），以后 stop 要跟着后移一行，
			# 否则第二项补进来时会插到第一项前面。
			lines.insert(stop, line)
			stop += 1

	var out := eol.join(PackedStringArray(lines))
	var f := FileAccess.open(MAIN_SCENE_PATH, FileAccess.WRITE)
	if f == null:
		return "写入失败：%s" % error_string(FileAccess.get_open_error())
	f.store_string(out)
	f.close()

	# 兜底自检：还必须是场景文本，Sun 节点还在，节点数没变。
	# 任何一条不成立就整份还原 —— 坏掉的 main.tscn 会把整个世界弄没。
	var after := FileAccess.get_file_as_string(MAIN_SCENE_PATH)
	var nodes_before := text.count("[node name=")
	var nodes_after := after.count("[node name=")
	if not after.contains("[gd_scene") or not after.contains("[node name=\"Sun\"") or nodes_before != nodes_after:
		var undo := FileAccess.open(MAIN_SCENE_PATH, FileAccess.WRITE)
		if undo != null:
			undo.store_string(text)
			undo.close()
		return "写回结果不像场景文本，已还原原文件"
	return ""


func _apply_light_cfg() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		# 没有存档 = 从没调过，保持场景出厂值。不标记「已套过」也无所谓，
		# 每次打开重读一个不存在的文件几乎不要钱。
		return
	_light_cfg_loaded = true
	_syncing = true
	for g in LightParamsLib.GROUPS:
		var section := String(g.id)
		for row in g.rows:
			var key := String(row.key)
			if not cfg.has_section_key(section, key):
				continue
			var v: Variant = cfg.get_value(section, key)
			if v == null:
				continue
			_light_write(key, v)
	_syncing = false
	_light_dirty = false


func _save_light_cfg() -> void:
	# 和 `water.cfg` 同一个原则：没真动过就不写，否则「开面板看一眼」
	# 会把当时的值固化成存档，之后改 world_env.tres 的出厂值永远被它盖住。
	if not _light_dirty:
		return
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	for g in LightParamsLib.GROUPS:
		var section := String(g.id)
		for row in g.rows:
			var key := String(row.key)
			var v: Variant = _light_read(key)
			if v == null:
				continue
			cfg.set_value(section, key, v)
	cfg.save(CFG_PATH)



# ---- 方案 -------------------------------------------------------------------
#
# 两套水的参数表不合并（身体模型不同，同名参数意义不同）。这里用几个小分发
# 函数把「当前是哪套」收在一处，其它代码只跟 `_spec` / `_order` 打交道。

func _is_abs() -> bool:
	return _scheme == SCHEME_ABSORPTION


func _groups() -> Array:
	return ParamsLibAbs.GROUPS if _is_abs() else ParamsLib.GROUPS


func _flat() -> Dictionary:
	return ParamsLibAbs.flat() if _is_abs() else ParamsLib.flat()


func _builtin(name: String) -> Dictionary:
	return ParamsLibAbs.builtin(name) if _is_abs() else ParamsLib.builtin(name)


func _builtin_names() -> Array:
	return ParamsLibAbs.builtin_names() if _is_abs() else ParamsLib.builtin_names()


func _builtin_presets() -> Array:
	return ParamsLibAbs.BUILTIN_PRESETS if _is_abs() else ParamsLib.BUILTIN_PRESETS


func _mat_path() -> String:
	return String(SCHEME_MATS.get(_scheme, WATER_MAT_PATH))


## 按当前方案重建「扁平清单 + 顺序」。两套水的键集合完全不同，必须成对重建。
## 顺带把出厂值缓存清掉 —— 否则「复位」会拿回另一套方案在磁盘上的值。
func _rebuild_spec() -> void:
	_spec = _flat()
	_order.clear()
	for g in _groups():
		for row in g.rows:
			_order.append(row.key)
	_file_defaults.clear()
	_file_defaults_loaded = false


# ---- 水面材质解析 -----------------------------------------------------------

func _ensure_water() -> void:
	if is_instance_valid(_water_node) and is_instance_valid(_water_mat):
		# 切换方案时节点上的 `material_override` 换了另一份实例，这里要跟着换，
		# 否则所有写入还在往旧材质上打，看起来像「调了没反应」。
		var live: ShaderMaterial = _water_node.material_override as ShaderMaterial
		if live != null and live == _water_mat:
			return
	if not is_instance_valid(_water_node):
		var scene := get_tree().current_scene
		if scene != null:
			_water_node = scene.get_node_or_null("World/Water") as MeshInstance3D
		if _water_node == null:
			_water_node = _find_water_recursive(get_tree().root)
		if _water_node == null:
			return
	_water_mat = _water_node.material_override as ShaderMaterial
	if not _factory_captured:
		_factory_captured = true
		_factory_wave_scale = float(_water_node.get("wave_scale"))


func _find_water_recursive(node: Node) -> MeshInstance3D:
	var mi := node as MeshInstance3D
	if mi != null:
		var mat := mi.material_override as ShaderMaterial
		if mat != null and mat.shader != null:
			var path := String(mat.shader.resource_path)
			# 两套着色器都算水面：切到吸收式以后原来的判断会漏掉节点。
			if path.ends_with("water.gdshader") or path.ends_with("water_absorption.gdshader"):
				return mi
	for c in node.get_children():
		var found := _find_water_recursive(c)
		if found != null:
			return found
	return null


## 从资源文件重读一份材质，只用来取「出厂值」和写回时的干净底稿。
## `CACHE_MODE_IGNORE` 是关键：不加就会拿到运行时那份改过的实例。
func _load_water_file() -> ShaderMaterial:
	var res: Resource = ResourceLoader.load(_mat_path(), "", ResourceLoader.CACHE_MODE_IGNORE)
	return res as ShaderMaterial


func _water_read(key: String) -> Variant:
	var spec: Dictionary = _spec.get(key, {})
	if spec.is_empty():
		return null
	if spec.kind == "node":
		if is_instance_valid(_water_node):
			return _water_node.get("wave_scale")
		return float(spec.get("default", 1.0))
	var raw: Variant = null
	if is_instance_valid(_water_mat):
		raw = _water_mat.get_shader_parameter(key)
	if raw == null:
		# 材质上没这一项（资源文件漏写）时退回文件里的值，别让控件停在 0。
		raw = _water_default(key)
	if raw == null:
		return null
	match spec.kind:
		"color":
			return _as_color3(raw)
		"color4":
			return _as_color4(raw)
	return raw


## 出厂值：每次现读磁盘，读一次缓存起来。`CACHE_MODE_IGNORE` 是关键，
## 不加会拿到运行时改过的那份实例，于是「复位」毫无变化。
func _water_default(key: String) -> Variant:
	if not _file_defaults_loaded:
		_file_defaults_loaded = true
		var fresh := _load_water_file()
		if fresh != null:
			for k in _order:
				var v: Variant = fresh.get_shader_parameter(k)
				if v != null:
					_file_defaults[k] = v
	return _file_defaults.get(key)


func _water_write(key: String, value: Variant) -> void:
	var spec: Dictionary = _spec.get(key, {})
	if spec.is_empty():
		return
	if spec.kind == "node":
		if is_instance_valid(_water_node):
			# 节点上的 wave_scale 每帧由 water_surface.gd 同步进材质，
			# 所以这里改节点就够了，别绕过去直接写材质（会被覆盖）。
			_water_node.set("wave_scale", float(value))
			_water_dirty = true
		return
	if not is_instance_valid(_water_mat):
		return
	_water_dirty = true
	_water_mat.set_shader_parameter(key, _to_shader_value(spec, value))


## 面板里的值 → 着色器要的形式。
##
## `source_color` 的 vec3 必须存 Color，不能存 Vector3：存 Vector3 读出来一模一样，
## 但 `ResourceSaver` 认为它和属性声明的类型（COLOR）不符，保存时会写成一个
## `= null`，参数就没了。`vec4` 和普通 vec3/vec2 照原样即可。
func _to_shader_value(spec: Dictionary, value: Variant) -> Variant:
	match String(spec.kind):
		"color":
			var c := _as_color3(value)
			return Color(c.r, c.g, c.b, 1.0)
		"color4":
			return _as_color4(value)
		"bool":
			return bool(value)
	return value


func _as_color3(v: Variant) -> Color:
	if v is Color:
		return v as Color
	if v is Vector3:
		var t := v as Vector3
		return Color(t.x, t.y, t.z)
	return Color.WHITE


func _as_color4(v: Variant) -> Color:
	if v is Color:
		return v as Color
	if v is Vector3:
		var t := v as Vector3
		return Color(t.x, t.y, t.z, 1.0)
	if v is Vector4:
		var q := v as Vector4
		return Color(q.x, q.y, q.z, q.w)
	return Color.WHITE


# ---- UI ---------------------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	# 放到标题下面：左上角是品牌区，压上去会两边都看不清。
	_panel.position = Vector2(18, 92)
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(_panel)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 7)
	_panel.add_child(_body)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 5)
	_body.add_child(head)
	head.add_child(_label("调试", 13, Color("#eafaff")))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 3)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tabs)
	_tab_buttons[TAB_FILTER] = _tab_button("滤镜", TAB_FILTER, tabs)
	_tab_buttons[TAB_LIGHT] = _tab_button("光照", TAB_LIGHT, tabs)
	_tab_buttons[TAB_WATER] = _tab_button("水面", TAB_WATER, tabs)
	var close := _button("关闭", func() -> void: set_open(false))
	close.custom_minimum_size = Vector2(46, 24)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	head.add_child(close)

	_body.add_child(_separator())

	_filter_body = VBoxContainer.new()
	_filter_body.add_theme_constant_override("separation", 7)
	_body.add_child(_filter_body)
	_build_filter()

	_light_wrap = VBoxContainer.new()
	_light_wrap.add_theme_constant_override("separation", 6)
	_light_wrap.visible = false
	_body.add_child(_light_wrap)
	_build_light()

	_water_wrap = VBoxContainer.new()
	_water_wrap.add_theme_constant_override("separation", 6)
	_water_wrap.visible = false
	_body.add_child(_water_wrap)
	_build_water()

	_status = _label("P 开关 · 拖动即时生效，数值会记住", 9, Color(0.62, 0.80, 0.86, 0.85))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(PANEL_WIDTH - 24, 0)
	_body.add_child(_status)

	_set_tab(_tab)


func _build_filter() -> void:
	_add_row("exposure", "曝光", EXPOSURE_MIN, EXPOSURE_MAX, 0.01)
	_add_row("brightness", "亮度", ADJ_MIN, ADJ_MAX, 0.01)
	_add_row("contrast", "对比度", ADJ_MIN, ADJ_MAX, 0.01)
	_add_row("saturation", "饱和度", ADJ_MIN, ADJ_MAX, 0.01)

	_filter_body.add_child(_separator())

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 5)
	_filter_body.add_child(buttons)
	buttons.add_child(_button("复位", _on_reset))
	buttons.add_child(_button("复制参数", _on_copy))
	buttons.add_child(_button("写入场景", _on_save_to_scene))


## 光照页：环境 + 太阳两组，参数比滤镜多一个量级，所以自带滚动区。
##
## 这一页的按钮是「复位 / 复制参数 / 写入场景」，语义和滤镜页一致，但写回目标
## 有两个：环境写 `world_env.tres`，太阳写 `main.tscn` 的 Sun 节点。
func _build_light() -> void:
	_light_scroll = ScrollContainer.new()
	_light_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_light_scroll.custom_minimum_size = Vector2(0, _scroll_height())
	_light_wrap.add_child(_light_scroll)

	_light_body = VBoxContainer.new()
	_light_body.add_theme_constant_override("separation", 4)
	_light_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_light_scroll.add_child(_light_body)

	for g in LightParamsLib.GROUPS:
		_add_folder(_light_body, g, _add_light_row)

	_light_wrap.add_child(_separator())

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 5)
	_light_wrap.add_child(buttons)
	buttons.add_child(_button("复位", _on_light_reset))
	buttons.add_child(_button("复制参数", _on_light_copy))
	buttons.add_child(_button("写入场景", _on_light_save))


## 光照页的一行。类型只有 float / bool / color 三种 —— 没有 vec2/vec3，
## 所以不用 `_add_vector_row`；朝向那两行在清单里就是两个 float。
func _add_light_row(parent: VBoxContainer, spec: Dictionary) -> void:
	match String(spec.kind):
		"bool":
			_add_bool_row(parent, spec, _light_write, _light_widgets, _save_light_cfg)
		"color":
			_add_color_row(parent, spec, false, _light_write, _light_widgets, _save_light_cfg)
		_:
			_add_scalar_row(parent, spec, _light_write, _light_widgets, _save_light_cfg)


func _build_water() -> void:
	_build_scheme_bar()
	_build_preset_bar()

	_water_scroll = ScrollContainer.new()
	_water_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_water_scroll.custom_minimum_size = Vector2(0, _scroll_height())
	_water_wrap.add_child(_water_scroll)

	_water_body = VBoxContainer.new()
	_water_body.add_theme_constant_override("separation", 4)
	_water_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_water_scroll.add_child(_water_body)

	for g in _groups():
		_add_group(g)

	_water_wrap.add_child(_separator())

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 5)
	_water_wrap.add_child(buttons)
	buttons.add_child(_button("复位", _on_water_reset))
	buttons.add_child(_button("复制参数", _on_water_copy))
	_save_button = _button("写入 %s" % _mat_file_name(), _on_water_save)
	buttons.add_child(_save_button)


## 顶部一行：两套水之间切换。切换会重建下面整页控件。
##
## 两个都是开关按钮而不是下拉：只有两项，下拉要多一次点击，而且看不出
## 「现在是哪套」之外还有哪套可选。
func _build_scheme_bar() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 5)
	_water_wrap.add_child(bar)

	var tag := _label("方案", 10, Color(0.72, 0.93, 1.0, 0.9))
	tag.custom_minimum_size = Vector2(28, 0)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.tooltip_text = "两套互相独立的水：原版是手绘体色，吸收式按屏幕深度吸收。各自的参数、收藏、存档都分开。"
	bar.add_child(tag)

	_scheme_buttons.clear()
	for id in SCHEME_ORDER:
		var sid := String(id)
		var b := _button(String(SCHEME_LABELS[sid]), func() -> void: set_water_scheme(sid))
		b.custom_minimum_size = Vector2(0, 24)
		b.toggle_mode = true
		b.tooltip_text = "切到「%s」这套水。" % SCHEME_LABELS[sid]
		_scheme_buttons[sid] = b
		bar.add_child(b)
	_sync_scheme_buttons()


func _sync_scheme_buttons() -> void:
	for id in _scheme_buttons:
		var b: Button = _scheme_buttons[id]
		b.button_pressed = id == _scheme
	# 「写入 xxx.tres」的目标文件跟着方案走，不然会以为写进了另一套。
	if _save_button != null:
		_save_button.text = "写入 %s" % _mat_file_name()


func _mat_file_name() -> String:
	return _mat_path().get_file()


## 切换方案。节点上换材质 → 重建参数控件 → 套用该方案自己的存档。
##
## 顺序不能反：`_rebuild_spec()` 之后控件要重新读值，读的是「当前材质」，
## 材质没换就会把另一套的值显示出来。
func set_water_scheme(id: String) -> void:
	if not SCHEME_ORDER.has(id):
		return
	_ensure_water()
	if is_instance_valid(_water_node) and _water_node.has_method("use_scheme"):
		if not _water_node.use_scheme(id):
			_flash("场景里没有注册「%s」这套水" % SCHEME_LABELS.get(id, id))
			return
	_scheme = id
	_rebuild_spec()
	# 强制 _ensure_water 从节点重取材质，别继续拿着旧的那份。
	_water_mat = null
	_ensure_water()
	_rebuild_water_rows()
	_sync_water()
	_water_dirty = false
	_apply_water_cfg()
	_sync_water()
	_refresh_preset_list("")
	_sync_scheme_buttons()
	_write_scheme_to_cfg()
	_flash("已切到「%s」" % SCHEME_LABELS.get(id, id))


## 清空参数区重建成另一套。`_water_widgets` 跟着换：两套的键集合没有交集，
## 留着旧的只会让 `_sync_water` 往上打另一套的值。
func _rebuild_water_rows() -> void:
	if _water_body == null:
		return
	_water_widgets.clear()
	for c in _water_body.get_children():
		_water_body.remove_child(c)
		c.queue_free()
	for g in _groups():
		_add_group(g)


## 顶部一行：收藏下拉 + 存 / 删。
##
## 为什么要有它：参数一共 50 个，想比较「雾天版 / 黄昏版」只能靠记数字，
## 记忆不可靠。这里把整套值按名字存下来，选一下就整套套用。
## 出厂那一项直接读 `water.tres`，所以任何时候都能退回干净状态。
func _build_preset_bar() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 5)
	_water_wrap.add_child(bar)

	var tag := _label("收藏", 10, Color(0.72, 0.93, 1.0, 0.9))
	tag.custom_minimum_size = Vector2(28, 0)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.tooltip_text = "选一套存过的参数整套套用。第一项是 water.tres 的出厂值。"
	bar.add_child(tag)

	_preset_option = OptionButton.new()
	_preset_option.add_theme_font_override("font", _font)
	_preset_option.add_theme_font_size_override("font_size", 10)
	_preset_option.add_theme_color_override("font_color", Color("#e9f8ff"))
	_preset_option.add_theme_stylebox_override("normal", _btn_style(
		Color(14.0 / 255.0, 40.0 / 255.0, 64.0 / 255.0, 0.9),
		Color(110.0 / 255.0, 190.0 / 255.0, 200.0 / 255.0, 0.30)))
	_preset_option.add_theme_stylebox_override("hover", _btn_style(
		Color(32.0 / 255.0, 90.0 / 255.0, 138.0 / 255.0, 0.92),
		Color(124.0 / 255.0, 248.0 / 255.0, 228.0 / 255.0, 0.6)))
	_preset_option.add_theme_stylebox_override("pressed", _btn_style(
		Color(30.0 / 255.0, 104.0 / 255.0, 118.0 / 255.0, 0.95),
		Color(124.0 / 255.0, 248.0 / 255.0, 228.0 / 255.0, 0.75)))
	_preset_option.custom_minimum_size = Vector2(0, 24)
	_preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_option.focus_mode = Control.FOCUS_NONE
	_preset_option.tooltip_text = "选一套存过的参数整套套用，改完再点「存」覆盖。"
	_preset_option.item_selected.connect(_on_preset_selected)
	# 下拉弹层是独立的 PopupMenu，字体得单独给，否则会掉回默认的西文字体。
	var pop := _preset_option.get_popup()
	pop.add_theme_font_override("font", _font)
	pop.add_theme_font_size_override("font_size", 10)
	bar.add_child(_preset_option)

	bar.add_child(_mini_button("存", _on_preset_save, "把当前这一整套参数存成一个收藏。"))
	_preset_delete = _mini_button("删", _on_preset_delete, "删掉下拉里选中的那一套收藏。")
	bar.add_child(_preset_delete)

	_refresh_preset_list("")


func _mini_button(text: String, cb: Callable, tip: String = "") -> Button:
	var b := _button(text, cb)
	b.custom_minimum_size = Vector2(30, 24)
	# `_button` 默认拉满整行，这里要挤在右边，所以改回收缩。
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if tip != "":
		b.tooltip_text = tip
	return b


# ---- 收藏 -------------------------------------------------------------------

## 当前这一整套值，按「面板值」的形态抓一份：颜色是 Color、向量是 Vector3、
## 节点属性是 float。跟 `_water_read` 的输出保持同一套类型，
## 套用的时候原样喂回 `_water_write` 就行，不用再猜格式。
func _capture_values() -> Dictionary:
	var out := {}
	for key in _order:
		var v: Variant = _water_read(key)
		if v == null:
			continue
		out[key] = v
	return out


## 文件里各 section 的顺序不保证，所以顺序单独记在 `[meta] names` 里。
## 顺手兼容「section 存在但 names 漏了」的手改情况。
## 全量顺序，写文件时用。**不能用过滤后的 `_preset_order()` 写盘**：
## 那样会把另一套水的收藏名从 `[meta] names` 里抹掉。
func _preset_order_all() -> Array[String]:
	var names: Array[String] = []
	var cfg := ConfigFile.new()
	if cfg.load(WATER_PRESET_PATH) != OK:
		return names
	for n in cfg.get_value("meta", "names", PackedStringArray()):
		var s := String(n)
		if s != "" and cfg.has_section("preset:" + s) and not names.has(s):
			names.append(s)
	for section in cfg.get_sections():
		if not section.begins_with("preset:"):
			continue
		var s := section.substr(7)
		if not names.has(s):
			names.append(s)
	return names


## 当前方案的收藏名。两套的键集合没有交集，混在一起只会让人点错。
func _preset_order() -> Array[String]:
	var names: Array[String] = []
	var all := _load_presets()
	for s in _preset_order_all():
		if not all.has(s):
			continue
		if _preset_scheme_of(all[s]) != _scheme:
			continue
		names.append(s)
	return names


## 一套收藏属于哪个方案。加这一列之前的收藏都算原版。
func _preset_scheme_of(data: Dictionary) -> String:
	return String(data.get(PRESET_SCHEME_KEY, SCHEME_ORIGINAL))


func _load_presets() -> Dictionary:
	var out := {}
	var cfg := ConfigFile.new()
	if cfg.load(WATER_PRESET_PATH) != OK:
		return out
	for section in cfg.get_sections():
		if not section.begins_with("preset:"):
			continue
		var d := {}
		for key in cfg.get_section_keys(section):
			d[key] = cfg.get_value(section, key)
		out[section.substr(7)] = d
	return out


func _write_presets(names: Array[String], data: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "names", PackedStringArray(names))
	for n in names:
		if not data.has(n):
			continue
		var d: Dictionary = data[n]
		for key in d.keys():
			cfg.set_value("preset:" + n, String(key), d[key])
	cfg.save(WATER_PRESET_PATH)


func _refresh_preset_list(select_key: String) -> void:
	if _preset_option == null:
		return
	_preset_names = _preset_order()
	_preset_option.clear()
	_preset_items.clear()

	_add_preset_item({"kind": "factory", "name": "出厂（%s）" % _mat_file_name()})

	if not _builtin_presets().is_empty():
		_add_separator_item("内置")
		for p in _builtin_presets():
			_add_preset_item({"kind": "builtin", "name": String(p.name)})

	if not _preset_names.is_empty():
		_add_separator_item("我的收藏")
		for n in _preset_names:
			_add_preset_item({"kind": "user", "name": n})

	# 分隔项本身不能被选中，否则按钮上的文字会变成「内置」「我的收藏」。
	var want := 0
	for i in _preset_items.size():
		if String(_preset_items[i].get("kind", "")) == "sep":
			continue
		if _preset_key(_preset_items[i]) == select_key:
			want = i
			break
	_preset_option.select(want)
	_update_preset_delete()


## `add_separator()` 也占一个 index，所以两边必须同步追加，否则选中项会串位。
func _add_preset_item(item: Dictionary) -> void:
	_preset_option.add_item(String(item.name))
	_preset_items.append(item)


func _add_separator_item(title: String) -> void:
	_preset_option.add_separator(title)
	# 同 index 的 item 关掉：点它没反应，select() 也不会停在它上面。
	_preset_option.set_item_disabled(_preset_option.item_count - 1, true)
	_preset_items.append({"kind": "sep", "name": title})


func _preset_key(item: Dictionary) -> String:
	match String(item.get("kind", "")):
		"factory":
			return "factory"
		"builtin":
			return "builtin:" + String(item.name)
		"user":
			return "user:" + String(item.name)
	return ""


func _selected_preset() -> Dictionary:
	if _preset_option == null:
		return {}
	var idx := _preset_option.selected
	if idx < 0 or idx >= _preset_items.size():
		return {}
	return _preset_items[idx]


func _update_preset_delete() -> void:
	if _preset_delete == null:
		return
	# 只有自己存的那几条能删：出厂是资源文件本身，内置写在代码里。
	_preset_delete.disabled = String(_selected_preset().get("kind", "")) != "user"


func _on_preset_selected(index: int) -> void:
	if index < 0 or index >= _preset_items.size():
		return
	var item: Dictionary = _preset_items[index]
	var kind := String(item.get("kind", ""))
	if kind == "sep":
		return
	if kind == "factory":
		if _apply_factory_values():
			_flash("已套用 %s" % "出厂（%s）" % _mat_file_name())
		_update_preset_delete()
		return
	if kind == "builtin":
		var preset := _builtin(String(item.name))
		if preset.is_empty():
			_flash("找不到内置预设「%s」" % item.name)
			return
		# 内置预设只记差异项，其余必须回落到出厂值，否则会带上上一个预设的残留。
		_apply_values(preset.values, true)
		_flash("已套用内置「%s」" % item.name)
		_update_preset_delete()
		return
	var name := String(item.name)
	var all := _load_presets()
	if not all.has(name):
		_flash("找不到收藏「%s」，可能已被删除" % name)
		_refresh_preset_list("")
		return
	_apply_values(all[name])
	_flash("已套用收藏「%s」" % name)
	_update_preset_delete()


## 把一整套值写进材质。
##
## `fill_from_factory` 为真时，`values` 里没出现的参数会被复位成 `water.tres`
## 的值 —— 内置预设只写差异项，靠这个补齐；用户收藏是全量，传 false 即可。
func _apply_values(values: Dictionary, fill_from_factory := false) -> void:
	if not is_instance_valid(_water_mat) and not is_instance_valid(_water_node):
		_flash("找不到水面材质，无法套用")
		return
	var fresh: ShaderMaterial = _load_water_file() if fill_from_factory else null
	for key in _order:
		var spec: Dictionary = _spec.get(key, {})
		if spec.is_empty():
			continue
		if values.has(key):
			_water_write(key, values[key])
			continue
		if not fill_from_factory:
			continue
		if spec.kind == "node":
			_water_write(key, _factory_wave_scale)
			continue
		if fresh != null:
			var v: Variant = fresh.get_shader_parameter(key)
			if v != null:
				_water_write(key, v)
	_sync_water()
	_save_water_cfg()


func _on_preset_save() -> void:
	_ensure_water()
	if not is_instance_valid(_water_mat):
		_flash("找不到水面材质，无法收藏")
		return
	_ensure_name_dialog()
	_name_edit.text = _next_preset_name()
	_name_dialog.popup_centered()
	_name_edit.grab_focus()
	_name_edit.select_all()


func _next_preset_name() -> String:
	var i := 1
	while _preset_names.has("预设 %d" % i):
		i += 1
	return "预设 %d" % i


func _on_preset_name_confirmed() -> void:
	_commit_preset(_name_edit.text)


func _commit_preset(raw_name: String) -> void:
	# ConfigFile 的 section 名用 `[` `]` 收尾，名字里带这两个字符会把文件写坏。
	var name := raw_name.strip_edges().replace("[", "").replace("]", "")
	if name == "":
		name = _next_preset_name()
	if name == PRESET_FACTORY:
		_flash("「出厂」是内置项，换个名字")
		return
	if _builtin_names().has(name):
		_flash("「%s」是内置预设名，换个名字" % name)
		return
	var all := _load_presets()
	var names := _preset_order_all()
	var replaced := all.has(name)
	all[name] = _capture_values()
	# 记下这套属于哪个方案，切到另一套时不会被列出来（键集合不兼容）。
	all[name][PRESET_SCHEME_KEY] = _scheme
	if not names.has(name):
		names.append(name)
	_write_presets(names, all)
	_refresh_preset_list("user:" + name)
	_flash("已%s收藏「%s」" % ["覆盖" if replaced else "存下", name])


func _on_preset_delete() -> void:
	var item := _selected_preset()
	if String(item.get("kind", "")) != "user":
		_flash("只有自己存的收藏能删，出厂和内置都是固定的")
		return
	_ensure_delete_dialog()
	_delete_dialog.dialog_text = "删除收藏「%s」？\n删掉就只能重新调一遍了。" % item.name
	_delete_dialog.popup_centered()


func _do_delete_preset() -> void:
	var item := _selected_preset()
	if String(item.get("kind", "")) != "user":
		return
	var name := String(item.name)
	var all := _load_presets()
	var names := _preset_order_all()
	all.erase(name)
	names.erase(name)
	_write_presets(names, all)
	_refresh_preset_list("")
	_flash("已删除收藏「%s」" % name)


func _ensure_name_dialog() -> void:
	if _name_dialog != null:
		return
	_name_dialog = AcceptDialog.new()
	_name_dialog.title = "收藏当前水面参数"
	_name_dialog.ok_button_text = "保存"
	_name_dialog.add_cancel_button("取消")
	_name_dialog.min_size = Vector2i(300, 0)
	add_child(_name_dialog)

	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(272, 28)
	_name_edit.add_theme_font_override("font", _font)
	_name_edit.add_theme_font_size_override("font_size", 11)
	_name_edit.placeholder_text = "给这套参数起个名字"
	_name_dialog.add_child(_name_edit)
	_name_dialog.register_text_enter(_name_edit)
	_name_dialog.confirmed.connect(_on_preset_name_confirmed)


func _ensure_delete_dialog() -> void:
	if _delete_dialog != null:
		return
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "删除收藏"
	_delete_dialog.ok_button_text = "删除"
	_delete_dialog.cancel_button_text = "取消"
	add_child(_delete_dialog)
	_delete_dialog.confirmed.connect(_do_delete_preset)


## 面板高度得跟着窗口走：720p 下大约 440 px，够看六七行再滚动。
func _scroll_height() -> float:
	var vh := 720.0
	var vp := get_viewport()
	if vp != null:
		vh = vp.get_visible_rect().size.y
	return clampf(vh - 300.0, 240.0, 560.0)


func _add_group(g: Dictionary) -> void:
	_add_folder(_water_body, g, _add_water_row)


## 折叠分组。水面页和光照页共用：两页长得一样、行为一样，没理由写两份。
## `builder(parent, row)` 决定这一行怎么造，这样同一套外壳能装着色器参数
## （水面）和引擎对象属性（光照）。
func _add_folder(host: VBoxContainer, g: Dictionary, builder: Callable) -> void:
	var head := Button.new()
	head.text = "▾  " + String(g.label)
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_theme_font_override("font", _font)
	head.add_theme_font_size_override("font_size", 10)
	head.add_theme_color_override("font_color", Color(0.72, 0.93, 1.0, 0.95))
	head.add_theme_stylebox_override("normal", _btn_style(Color(12.0 / 255.0, 38.0 / 255.0, 62.0 / 255.0, 0.75),
		Color(110.0 / 255.0, 190.0 / 255.0, 200.0 / 255.0, 0.22)))
	head.add_theme_stylebox_override("hover", _btn_style(Color(24.0 / 255.0, 74.0 / 255.0, 118.0 / 255.0, 0.9),
		Color(124.0 / 255.0, 248.0 / 255.0, 228.0 / 255.0, 0.55)))
	head.custom_minimum_size = Vector2(0, 20)
	head.focus_mode = Control.FOCUS_NONE
	host.add_child(head)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	host.add_child(box)

	var note := String(g.get("note", ""))
	if note != "":
		var tip := _label(note, 9, Color(0.60, 0.80, 0.88, 0.72))
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip.custom_minimum_size = Vector2(PANEL_WIDTH - 46, 0)
		box.add_child(tip)

	for row in g.rows:
		builder.call(box, row)

	head.pressed.connect(func() -> void:
		box.visible = not box.visible
		head.text = ("▾  " if box.visible else "▸  ") + String(g.label))


func _add_water_row(parent: VBoxContainer, spec: Dictionary) -> void:
	match String(spec.kind):
		"float", "node":
			_add_scalar_row(parent, spec)
		"bool":
			_add_bool_row(parent, spec)
		"color":
			_add_color_row(parent, spec, false)
		"color4":
			_add_color_row(parent, spec, true)
		"vec3", "vec2":
			_add_vector_row(parent, spec)


func _row_shell(parent: VBoxContainer, spec: Dictionary) -> VBoxContainer:
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 1)
	parent.add_child(holder)
	return holder


## 提示挂在真正接鼠标的控件上才弹得出来 —— Godot 的 tooltip 不往父节点问。
func _tip(c: Control, spec: Dictionary) -> void:
	var hint := String(spec.get("hint", ""))
	if hint != "":
		c.tooltip_text = hint


## 下面四个行构建器都带三个可选口子：`write(key, value)` 写值、`widgets` 收
## 「回填控件」的 Callable、`commit()` 在拖动结束时落盘。
##
## 不传就接水面那套（着色器参数 + `water.cfg`），传了就接光照那套（引擎对象
## 属性 + `filter.cfg`）。这样一份控件代码同时服务两页，不会出现「水面页修了
## 一个排版 bug，光照页还是老样子」。
func _add_scalar_row(parent: VBoxContainer, spec: Dictionary,
		write := Callable(), widgets := {}, commit := Callable()) -> void:
	var sink: Callable = write if write.is_valid() else Callable(self, "_water_write")
	var bag: Dictionary = widgets if write.is_valid() else _water_widgets
	var done: Callable = commit if commit.is_valid() else Callable(self, "_save_water_cfg")
	var holder := _row_shell(parent, spec)
	var spec_key := String(spec.key)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	holder.add_child(line)

	line.add_child(_name_label(spec))

	var slider := _slider(float(spec.min), float(spec.max), float(spec.step))
	_tip(slider, spec)
	line.add_child(slider)

	var value := _value_label()
	line.add_child(value)

	var fmt := String(spec.get("fmt", "%.2f"))
	var unit := String(spec.get("unit", ""))
	slider.value_changed.connect(func(v: float) -> void:
		value.text = fmt % v + unit
		if _syncing:
			return
		sink.call(spec_key, v))
	slider.drag_ended.connect(func(_changed: bool) -> void:
		if not _syncing:
			done.call())
	# 滚轮交给 ScrollContainer：否则在列表里滚动会把参数一路改掉。
	slider.scrollable = false
	value.text = fmt % slider.value + unit

	bag[spec_key] = func(v: Variant) -> void:
		slider.set_value_no_signal(float(v))
		value.text = fmt % float(v) + unit


func _add_bool_row(parent: VBoxContainer, spec: Dictionary,
		write := Callable(), widgets := {}, commit := Callable()) -> void:
	var sink: Callable = write if write.is_valid() else Callable(self, "_water_write")
	var bag: Dictionary = widgets if write.is_valid() else _water_widgets
	var done: Callable = commit if commit.is_valid() else Callable(self, "_save_water_cfg")
	var spec_key := String(spec.key)
	var holder := _row_shell(parent, spec)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	holder.add_child(line)

	line.add_child(_name_label(spec))
	var check := CheckBox.new()
	check.text = ""
	check.add_theme_font_override("font", _font)
	check.focus_mode = Control.FOCUS_NONE
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tip(check, spec)
	check.toggled.connect(func(on: bool) -> void:
		if _syncing:
			return
		sink.call(spec_key, on)
		done.call())
	line.add_child(check)

	bag[spec_key] = func(v: Variant) -> void:
		check.set_pressed_no_signal(bool(v))


func _add_color_row(parent: VBoxContainer, spec: Dictionary, with_alpha: bool,
		write := Callable(), widgets := {}, commit := Callable()) -> void:
	var sink: Callable = write if write.is_valid() else Callable(self, "_water_write")
	var bag: Dictionary = widgets if write.is_valid() else _water_widgets
	var done: Callable = commit if commit.is_valid() else Callable(self, "_save_water_cfg")
	var spec_key := String(spec.key)
	var holder := _row_shell(parent, spec)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	holder.add_child(line)

	line.add_child(_name_label(spec))

	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(52, 18)
	picker.edit_alpha = with_alpha
	picker.focus_mode = Control.FOCUS_NONE
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tip(picker, spec)
	line.add_child(picker)

	var hex := _label("000000", 8, Color(0.72, 0.88, 0.92, 0.8))
	# 只显示六位色值：带透明度是八位，在 48 px 的数值列里放不下，
	# 右对齐会把尾部挤出面板边框（看着像色值少了一截）。透明度用取色器的
	# alpha 条看，这里不重复。
	hex.custom_minimum_size = Vector2(VALUE_W, 0)
	hex.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(hex)

	picker.color_changed.connect(func(c: Color) -> void:
		hex.text = c.to_html(false).trim_prefix("#")
		if _syncing:
			return
		sink.call(spec_key, c)
		done.call())

	bag[spec_key] = func(v: Variant) -> void:
		var c := _as_color4(v) if with_alpha else _as_color3(v)
		picker.color = c
		hex.text = c.to_html(false).trim_prefix("#")


func _add_vector_row(parent: VBoxContainer, spec: Dictionary,
		write := Callable(), widgets := {}, commit := Callable()) -> void:
	var sink: Callable = write if write.is_valid() else Callable(self, "_water_write")
	var bag: Dictionary = widgets if write.is_valid() else _water_widgets
	var done: Callable = commit if commit.is_valid() else Callable(self, "_save_water_cfg")
	var spec_key := String(spec.key)
	var holder := _row_shell(parent, spec)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	holder.add_child(head)
	var name_label := _name_label(spec)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)

	var fmt := String(spec.get("fmt", "%.2f"))
	var unit := String(spec.get("unit", ""))
	var labels: Array = spec.get("sub", ["X", "Y", "Z"])
	var count := 3 if String(spec.kind) == "vec3" else 2
	var sliders: Array[HSlider] = []
	var values: Array[Label] = []

	for i in mini(count, labels.size()):
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		holder.add_child(line)

		var sub := _label(String(labels[i]), 9, Color(0.66, 0.84, 0.90, 0.85))
		sub.custom_minimum_size = Vector2(NAME_W - 24, 0)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(sub)

		var slider := _slider(float(spec.min), float(spec.max), float(spec.step))
		slider.scrollable = false
		_tip(slider, spec)
		line.add_child(slider)
		sliders.append(slider)

		var value := _value_label()
		line.add_child(value)
		values.append(value)

	if sliders.is_empty():
		return

	var push := func() -> void:
		if _syncing:
			return
		if sliders.size() >= 3:
			sink.call(spec_key, Vector3(sliders[0].value, sliders[1].value, sliders[2].value))
		else:
			sink.call(spec_key, Vector2(sliders[0].value, sliders[1].value))

	for i in sliders.size():
		sliders[i].value_changed.connect(func(v: float) -> void:
			values[i].text = fmt % v + unit
			push.call())
		sliders[i].drag_ended.connect(func(_changed: bool) -> void:
			if not _syncing:
				done.call())

	bag[spec_key] = func(v: Variant) -> void:
		var comps: Array[float] = []
		if v is Vector3:
			var t := v as Vector3
			comps = [t.x, t.y, t.z]
		elif v is Vector2:
			var q := v as Vector2
			comps = [q.x, q.y]
		elif v is Vector4:
			var w := v as Vector4
			comps = [w.x, w.y, w.z]
		for i in mini(sliders.size(), comps.size()):
			sliders[i].set_value_no_signal(comps[i])
			values[i].text = fmt % comps[i] + unit


func _slider(lo: float, hi: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(90, 16)
	slider.focus_mode = Control.FOCUS_NONE
	slider.add_theme_stylebox_override("slider", _track_style())
	slider.add_theme_stylebox_override("grabber_area", _grabber_style(Color(0.55, 0.95, 0.85, 0.85)))
	return slider


func _name_label(spec: Dictionary) -> Label:
	# PASS 而不是 IGNORE：名字这一列也要能弹出参数说明。
	var l := _label(String(spec.label), 10, Color(0.90, 0.97, 1.0, 0.92))
	l.custom_minimum_size = Vector2(NAME_W, 0)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	_tip(l, spec)
	return l


func _value_label() -> Label:
	var l := _label("0.00", 9, Color(0.99, 0.92, 0.72, 1.0))
	l.custom_minimum_size = Vector2(VALUE_W, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


func _tab_button(text: String, id: String, parent: HBoxContainer) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 10)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(48, 22)
	b.add_theme_stylebox_override("normal", _btn_style(Color(14.0 / 255.0, 40.0 / 255.0, 64.0 / 255.0, 0.85),
		Color(110.0 / 255.0, 190.0 / 255.0, 200.0 / 255.0, 0.22)))
	b.add_theme_stylebox_override("hover", _btn_style(Color(32.0 / 255.0, 90.0 / 255.0, 138.0 / 255.0, 0.92),
		Color(124.0 / 255.0, 248.0 / 255.0, 228.0 / 255.0, 0.6)))
	b.pressed.connect(func() -> void: _set_tab(id))
	parent.add_child(b)
	return b


func _set_tab(id: String) -> void:
	_tab = id
	for key in _tab_buttons.keys():
		var b: Button = _tab_buttons[key]
		var active: bool = key == id
		b.add_theme_color_override("font_color", Color("#d6fff2") if active else Color(0.72, 0.86, 0.92, 0.8))
		b.add_theme_stylebox_override("normal", _btn_style(
			Color(30.0 / 255.0, 104.0 / 255.0, 118.0 / 255.0, 0.95) if active
				else Color(14.0 / 255.0, 40.0 / 255.0, 64.0 / 255.0, 0.85),
			Color(124.0 / 255.0, 248.0 / 255.0, 228.0 / 255.0, 0.75) if active
				else Color(110.0 / 255.0, 190.0 / 255.0, 200.0 / 255.0, 0.22)))
	if _filter_body != null:
		_filter_body.visible = id == TAB_FILTER
	if _light_wrap != null:
		_light_wrap.visible = id == TAB_LIGHT
	if _water_wrap != null:
		_water_wrap.visible = id == TAB_WATER
	_refresh_status()


func _refresh_status() -> void:
	if _status == null:
		return
	if _tab == TAB_WATER:
		_status.text = "水面参数 · 收藏可整套切换 · 滚轮翻列表，右列是当前值"
	elif _tab == TAB_LIGHT:
		_status.text = "环境与太阳 · 拖动即时生效 · 滚轮翻列表，右列是当前值"
	else:
		_status.text = "P 开关 · 拖动即时生效，数值会记住"


func _add_row(key: String, title: String, lo: float, hi: float, step: float) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	_filter_body.add_child(line)

	var name_label := _label(title, 11, Color(0.90, 0.97, 1.0, 0.92))
	name_label.custom_minimum_size = Vector2(52, 0)
	line.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(150, 18)
	slider.add_theme_stylebox_override("slider", _track_style())
	slider.add_theme_stylebox_override("grabber_area", _grabber_style(Color(0.55, 0.95, 0.85, 0.85)))
	line.add_child(slider)

	var value := _label("1.00", 10, Color(0.99, 0.92, 0.72, 1.0))
	value.custom_minimum_size = Vector2(42, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(value)

	slider.value_changed.connect(func(v: float) -> void:
		_write(key, v)
		value.text = "%.2f" % v)
	slider.drag_ended.connect(func(_changed: bool) -> void: _save_cfg())
	_rows[key] = {"slider": slider, "value": value}


func _write(key: String, v: float) -> void:
	_ensure_env()
	if _env == null:
		return
	match key:
		"exposure":
			_env.tonemap_exposure = v
		"brightness":
			_env.adjustment_enabled = true
			_env.adjustment_brightness = v
		"contrast":
			_env.adjustment_enabled = true
			_env.adjustment_contrast = v
		"saturation":
			_env.adjustment_enabled = true
			_env.adjustment_saturation = v


func _sync_from_env() -> void:
	_ensure_env()
	if _env == null or _rows.is_empty():
		return
	var snap := _snapshot(_env)
	for key in _rows.keys():
		var row: Dictionary = _rows[key]
		var slider: HSlider = row.slider
		slider.set_value_no_signal(float(snap.get(key, 1.0)))


func _refresh_labels() -> void:
	if _rows.is_empty():
		return
	for key in _rows.keys():
		var row: Dictionary = _rows[key]
		var slider: HSlider = row.slider
		var label: Label = row.value
		label.text = "%.2f" % slider.value
	if _env == null:
		_status.text = "找不到 WorldEnvironment，滤镜无法写入"


func _sync_water() -> void:
	_ensure_water()
	if _water_widgets.is_empty():
		return
	if not is_instance_valid(_water_mat):
		if _tab == TAB_WATER:
			_status.text = "找不到 World/Water 的 ShaderMaterial，水面参数无法写入"
		return
	_syncing = true
	for key in _order:
		var setter: Variant = _water_widgets.get(key)
		if setter == null:
			continue
		var v: Variant = _water_read(key)
		if v == null:
			continue
		(setter as Callable).call(v)
	_syncing = false


func _on_reset() -> void:
	_ensure_env()
	if _env == null:
		return
	_env.adjustment_enabled = true
	_env.tonemap_exposure = float(_defaults.get("exposure", 0.96))
	_env.adjustment_brightness = float(_defaults.get("brightness", 1.0))
	_env.adjustment_contrast = float(_defaults.get("contrast", 1.0))
	_env.adjustment_saturation = float(_defaults.get("saturation", 1.0))
	_sync_from_env()
	_refresh_labels()
	_save_cfg()
	_flash("已回到场景默认值")


## 复制成能直接贴进代码 / 文档的一行。
func _on_copy() -> void:
	_ensure_env()
	if _env == null:
		return
	var text := "exposure=%.2f brightness=%.2f contrast=%.2f saturation=%.2f" % [
		_env.tonemap_exposure, _env.adjustment_brightness,
		_env.adjustment_contrast, _env.adjustment_saturation]
	DisplayServer.clipboard_set(text)
	_flash("已复制：" + text)


## 把当前参数写回 assets/materials/world_env.tres：
## 下次启动、以及编辑器里打开的 Environment 都是这套值。
## 只在编辑器/开发环境可用（导出版 res:// 是只读的）。
func _on_save_to_scene() -> void:
	_ensure_env()
	if _env == null:
		return
	var path := "res://assets/materials/world_env.tres"
	if OS.has_feature("template"):
		_flash("导出版无法写回 res://，请用「复制参数」")
		return
	var err := ResourceSaver.save(_env, path)
	if err == OK:
		_save_cfg()
		_flash("已写入 %s（重开游戏生效）" % path)
	else:
		_flash("写入失败：%s" % error_string(err))


# ---- 水面：复位 / 复制 / 写回 -----------------------------------------------

func _on_water_reset() -> void:
	if _apply_factory_values():
		_flash("水面已回到 %s 的出厂值" % _mat_file_name())


## 把整套值退回资源文件里的那份。「复位」按钮和收藏下拉的第一项共用它。
## 返回 false 表示读不到资源，调用方自己决定报什么。
func _apply_factory_values() -> bool:
	_ensure_water()
	var fresh := _load_water_file()
	if fresh == null:
		_flash("读不到 %s，无法复位" % _mat_path())
		return false
	for key in _order:
		var spec: Dictionary = _spec.get(key, {})
		if spec.kind == "node":
			_water_write(key, _factory_wave_scale)
			continue
		var v: Variant = fresh.get_shader_parameter(key)
		if v == null:
			continue
		_water_write(key, v)
	_sync_water()
	_save_water_cfg()
	return true


func _on_water_copy() -> void:
	if not is_instance_valid(_water_mat):
		_flash("找不到水面材质，无法复制")
		return
	var lines := PackedStringArray()
	for key in _order:
		var spec: Dictionary = _spec.get(key, {})
		var v: Variant = _water_read(key)
		if v == null:
			continue
		if spec.kind == "node":
			lines.append("# wave_scale = %s（Water 节点属性，不在材质里）" % var_to_str(v))
			continue
		if spec.kind == "color":
			var c := _as_color3(v)
			lines.append("shader_parameter/%s = %s" % [key, var_to_str(Color(c.r, c.g, c.b, 1.0))])
		elif spec.kind == "color4":
			lines.append("shader_parameter/%s = %s" % [key, var_to_str(_as_color4(v))])
		else:
			lines.append("shader_parameter/%s = %s" % [key, var_to_str(v)])
	var text := "\n".join(lines)
	DisplayServer.clipboard_set(text)
	_flash("已复制 %d 行 shader_parameter" % lines.size())


## 写回 `assets/materials/water.tres`。
##
## 只改文本里的 `shader_parameter/<key> = ...` 行，不走 `ResourceSaver`，原因有三个：
##   · 存过运行时那份材质，会把 u_time / u_ripples / u_boat 这些每帧改的临时值
##     一起写进去，文件变成一堆噪声；
##   · `ResourceSaver` 会给「材质里没有」的参数写一行 `= null`，等于往资源里塞垃圾；
##   · 它会重排整个文件（format / uid / 顺序都变），diff 看不出改了什么。
## 逐行替换的话，没动的行一个字节都不变，uid 和手写注释也留着。
func _on_water_save() -> void:
	_ensure_water()
	if not is_instance_valid(_water_mat):
		_flash("找不到水面材质，无法写回")
		return
	if OS.has_feature("template"):
		_flash("导出版无法写回 res://，请用「复制参数」")
		return
	var text := FileAccess.get_file_as_string(_mat_path())
	if text.is_empty():
		_flash("读不到 %s" % _mat_path())
		return

	# 仓库在 Windows 上是 CRLF 检出，换行风格照原样还回去，别制造整文件 diff。
	var eol := "\r\n" if text.contains("\r\n") else "\n"
	var lines := text.replace("\r\n", "\n").split("\n")
	var written := 0

	for key in _order:
		var spec: Dictionary = _spec.get(key, {})
		if spec.kind == "node":
			continue
		var v: Variant = _water_read(key)
		if v == null:
			continue
		var line := "shader_parameter/%s = %s" % [key, var_to_str(_to_shader_value(spec, v))]
		var prefix := "shader_parameter/%s = " % key
		var found := false
		for i in lines.size():
			if String(lines[i]).begins_with(prefix):
				lines[i] = line
				found = true
				break
		if not found:
			# 文件里缺这一项（新加的参数）就补到末尾，别插进别的段里。
			while not lines.is_empty() and String(lines[lines.size() - 1]).strip_edges() == "":
				lines.remove_at(lines.size() - 1)
			lines.append(line)
			lines.append("")
		written += 1

	var out := eol.join(PackedStringArray(lines))
	var f := FileAccess.open(_mat_path(), FileAccess.WRITE)
	if f == null:
		_flash("写入失败：%s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(out)
	f.close()

	# 兜底自检：写回来的必须是资源文本，且不能夹带每帧改的运行时参数。
	# 这两个条件一旦不成立，立刻用写之前的内容覆盖回去 —— 宁可这次没写成，
	# 也不能让一份坏掉的 water.tres 留在磁盘上（水面会整体失色）。
	var after := FileAccess.get_file_as_string(_mat_path())
	if not after.contains("[gd_resource") or after.contains("shader_parameter/u_ripples"):
		var undo := FileAccess.open(_mat_path(), FileAccess.WRITE)
		if undo != null:
			undo.store_string(text)
			undo.close()
		_flash("写回结果不像资源文本，已还原原文件")
		return

	# 出厂值缓存作废：下次「复位」要按刚写进去的这份。
	_file_defaults.clear()
	_file_defaults_loaded = false
	_save_water_cfg()
	_flash("已写入 %s 的 %d 项（当场生效，重开也保留）" % [_mat_file_name(), written])


func _flash(text: String) -> void:
	if _status == null:
		return
	_status.text = text


# ---- 持久化 -----------------------------------------------------------------

func _apply_saved_on_start() -> void:
	_ensure_env()
	_apply_filter_cfg()
	# 太阳先解析：`_apply_light_cfg` 里既有环境键也有太阳键，
	# 少了这一步太阳那几项会被静默跳过（看起来像存档没生效）。
	_ensure_sun()
	_apply_light_cfg()
	_ensure_water()
	# 上次用哪套水，跟存档一起恢复。切不过去（场景没注册这套）就留在原版，
	# 不要因为一个存档字段整个面板起不来。
	var saved := _saved_scheme()
	if saved != "" and saved != _scheme:
		set_water_scheme(saved)
	_apply_water_cfg()
	_sync_water()


## `water.cfg` 的 `[meta] scheme`。老存档没有这一项，返回空串＝沿用原版。
func _saved_scheme() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(WATER_CFG_PATH) != OK:
		return ""
	var id := String(cfg.get_value("meta", "scheme", ""))
	return id if SCHEME_ORDER.has(id) else ""


## 单独记一次方案。不走 `_save_water_cfg()`：那个只在真调过滑块时才写，
## 而「我刚切到吸收式就关掉面板」也应该被记住。
func _write_scheme_to_cfg() -> void:
	var cfg := ConfigFile.new()
	cfg.load(WATER_CFG_PATH)
	cfg.set_value("meta", "scheme", _scheme)
	cfg.save(WATER_CFG_PATH)


func _apply_filter_cfg() -> void:
	if _env == null:
		return
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return
	_env.tonemap_exposure = float(cfg.get_value("filter", "exposure", _env.tonemap_exposure))
	_env.adjustment_enabled = true
	_env.adjustment_brightness = float(cfg.get_value("filter", "brightness", _env.adjustment_brightness))
	_env.adjustment_contrast = float(cfg.get_value("filter", "contrast", _env.adjustment_contrast))
	_env.adjustment_saturation = float(cfg.get_value("filter", "saturation", _env.adjustment_saturation))


func _apply_water_cfg() -> void:
	if not is_instance_valid(_water_mat) and not is_instance_valid(_water_node):
		return
	var cfg := ConfigFile.new()
	if cfg.load(WATER_CFG_PATH) != OK:
		return
	# 两套水各占一段：`water` 还是旧方案那批键，原存档照旧生效；
	# 吸收式另起一段，互不覆盖。
	var section := _cfg_section()
	# 存档只对「当时那份材质文件」有效。文件换了另一套出厂值（或者这份存档
	# 是加指纹之前留的，读出来是空串），立刻作废 —— 否则新出厂值永远被盖住，
	# 调好的参数看起来像没生效。
	if String(cfg.get_value(section, CFG_SIG_KEY, "")) != _mat_signature():
		return
	for key in _order:
		if not cfg.has_section_key(section, key):
			continue
		var v: Variant = cfg.get_value(section, key)
		if v == null:
			continue
		_water_write(key, v)


func _cfg_section() -> String:
	return String(SCHEME_SECTIONS.get(_scheme, "water"))


## 当前方案材质文件的内容指纹。只用来判断「出厂值有没有换过」，不做完整性校验。
func _mat_signature() -> String:
	var text := FileAccess.get_file_as_string(_mat_path())
	if text.is_empty():
		return ""
	return text.md5_text()


func _save_cfg() -> void:
	_ensure_env()
	if _env == null:
		return
	# 必须先 load：`filter.cfg` 现在同时住着 `[filter]`（这一页）和
	# `[environment]` / `[sun]`（光照页）。新建一份再 save 会把那两段抹掉 ——
	# 表现为「调完光照去拖一下曝光，光照设置全丢」。
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value("filter", "exposure", _env.tonemap_exposure)
	cfg.set_value("filter", "brightness", _env.adjustment_brightness)
	cfg.set_value("filter", "contrast", _env.adjustment_contrast)
	cfg.set_value("filter", "saturation", _env.adjustment_saturation)
	cfg.save(CFG_PATH)


func _save_water_cfg() -> void:
	# 没动过就不写：光开面板看一眼不该留下存档，否则以后改 water.tres
	# 的出厂值会被这份「当时恰好是这样的」存档全盖住。
	if not _water_dirty:
		return
	if not is_instance_valid(_water_mat) and not is_instance_valid(_water_node):
		return
	var cfg := ConfigFile.new()
	cfg.load(WATER_CFG_PATH)
	var section := _cfg_section()
	for key in _order:
		var v: Variant = _water_read(key)
		if v == null:
			continue
		cfg.set_value(section, key, v)
	cfg.set_value(section, CFG_SIG_KEY, _mat_signature())
	cfg.set_value("meta", "scheme", _scheme)
	cfg.save(WATER_CFG_PATH)


# ---- 小工具 -----------------------------------------------------------------

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_color_override("font_color", Color("#e9f8ff"))
	b.add_theme_stylebox_override("normal", _btn_style(Color(18.0 / 255.0, 52.0 / 255.0, 86.0 / 255.0, 0.8),
		Color(120.0 / 255.0, 200.0 / 255.0, 210.0 / 255.0, 0.28)))
	b.add_theme_stylebox_override("hover", _btn_style(Color(44.0 / 255.0, 114.0 / 255.0, 192.0 / 255.0, 0.9),
		Color(124.0 / 255.0, 248.0 / 255.0, 228.0 / 255.0, 0.7)))
	# 按下态：开关按钮（方案的「原版 / 吸收式」）靠它显示当前选中哪套，
	# 只给 normal 会让两个按钮长得一样，看不出现在用的是哪一个。
	var pressed_style := _btn_style(Color(42.0 / 255.0, 132.0 / 255.0, 138.0 / 255.0, 0.95),
		Color(124.0 / 255.0, 248.0 / 255.0, 228.0 / 255.0, 0.85))
	b.add_theme_stylebox_override("pressed", pressed_style)
	b.add_theme_stylebox_override("hover_pressed", pressed_style)
	b.add_theme_color_override("font_pressed_color", Color("#f2fffd"))
	b.add_theme_color_override("font_hover_pressed_color", Color("#f2fffd"))
	# 禁用态（比如「删」在选中出厂项时）画得明显灰一点，别让人以为是没反应。
	b.add_theme_stylebox_override("disabled", _btn_style(Color(18.0 / 255.0, 52.0 / 255.0, 86.0 / 255.0, 0.4),
		Color(120.0 / 255.0, 200.0 / 255.0, 210.0 / 255.0, 0.12)))
	b.add_theme_color_override("font_disabled_color", Color(0.62, 0.78, 0.84, 0.35))
	b.custom_minimum_size = Vector2(0, 24)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _separator() -> Control:
	var line := ColorRect.new()
	line.color = Color(0.42, 0.78, 0.86, 0.22)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(3.0 / 255.0, 14.0 / 255.0, 26.0 / 255.0, 0.88)
	s.border_color = Color(0.34, 0.78, 0.80, 0.42)
	s.set_border_width_all(1)
	s.corner_radius_top_left = 10
	s.corner_radius_top_right = 10
	s.corner_radius_bottom_left = 10
	s.corner_radius_bottom_right = 10
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


func _track_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.24, 0.32, 0.9)
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_left = 3
	s.corner_radius_bottom_right = 3
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s


func _grabber_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_left = 3
	s.corner_radius_bottom_right = 3
	return s


func _btn_style(bg: Color, edge: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(1)
	s.corner_radius_top_left = 7
	s.corner_radius_top_right = 7
	s.corner_radius_bottom_left = 7
	s.corner_radius_bottom_right = 7
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s
