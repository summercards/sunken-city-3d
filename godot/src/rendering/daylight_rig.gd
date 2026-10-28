extends Node
class_name DaylightRig
## Sole lighting writer. Resource/custom-panel values are the unchanged 09:00 baseline.
## Presets modulate sun, sky, fog and water lighting; grading and geometry stay untouched.
## Panels use base_of/adopt and suspend/resume when writing resources.
const Presets = preload("res://src/rendering/daylight_presets.gd")
const Slots = preload("res://src/rendering/daylight_slots.gd")

const SUN_PATH := "World/Lights/Sun"
const ENV_PATH := "World/WorldEnvironment"

const TARGET_SUN := "sun"
const TARGET_ENV := "env"
const TARGET_WATER := "water"
## 天空盒材质（`ocean_sky.tres` 里的 `ProceduralSkyMaterial`）。它不在任何
## `Environment` 属性上，而是在 `Environment.sky.sky_material` 里 —— 只改环境亮度
## 的话，天空**颜色**不动，黄昏时天上还是正午的蓝，这是最假的一种「夜晚」。
const TARGET_SKY := "sky"

## 各目标下归本装置管的属性。光照面板用 light_params 的 prop 映射内部键；
## 水面面板直接使用 uniform 名，不必再维护一张映射表。
const SUN_KEYS := [
	"light_energy", "light_color", "dir:elevation", "dir:azimuth",
	"light_angular_distance", "shadow_opacity",
]
const ENV_KEYS := [
	"ambient_light_energy", "ambient_light_color", "background_energy_multiplier",
	"fog_light_color", "fog_light_energy", "fog_sky_affect", "adjustment_contrast",
]
const WATER_KEYS := [
	"sky_top_color", "sky_horizon_color", "sky_ground_color", "sky_sun_glow",
	"sun_color", "sun_direction", "sun_highlight_strength",
	# 日间水体颜色也随时段走；日间为 `ALBEDO = 0` + `EMISSION`，夜间为真实受光PBR。
	# 日间层的
	# 输出，一个像素都不接收灯光 —— 不动这几项的话，夜里建筑全暗了、
	# 水面还是一片亮青色，那是整幅画面里最假的一块。
	"body_shallow", "body_deep",
	"night_albedo", "night_roughness",
	"night_deep_albedo", "night_depth_distance", "night_shallow_opacity",
]
const SKY_KEYS := [
	"sky_top_color", "sky_horizon_color", "ground_bottom_color", "ground_horizon_color",
	"sun_curve", "sun_angle_max",
]

# ---- 时变曲线 ---------------------------------------------------------------
#
# 全部以 09:00 = 1.0 归一。改这里等于改整天的观感，别在 `apply` 里散着写数字。

## 地平线附近太阳色的暖端。
const WARM_SUN := Color(1.0, 0.60, 0.36)
## 黄昏时环境光转暖的终点。
const DUSK_AMBIENT := Color(0.98, 0.80, 0.70)
## 深夜环境光：偏冷但不是死灰，留一点月光的意思。
const NIGHT_AMBIENT := Color(0.30, 0.40, 0.62)
## 深夜雾色。
const NIGHT_FOG := Color(0.03, 0.07, 0.15)
## 深夜天顶 / 地平线 / 地面（水面反射用）。
const NIGHT_SKY_TOP := Color(0.02, 0.04, 0.10)
const NIGHT_SKY_HORIZON := Color(0.09, 0.13, 0.24)
const NIGHT_SKY_GROUND := Color(0.01, 0.03, 0.06)
## 黄昏天顶偏紫蓝，让日落那一刻的天空真的变色，而不只是变暗。
const DUSK_SKY_TOP := Color(0.22, 0.24, 0.50)
const DUSK_SKY_HORIZON := Color(0.96, 0.66, 0.48)

# 天空盒自己的四个色。和上面水面反射那组是**两套独立的值**：水面反射是美术
# 手调过的解析渐变，不跟着天空盒走（水面那组「基准不纠偏」的注释里有原因）；
# 天空盒是玩家抬头真看到的那个。两套都要改，否则会出现「水是黄昏色、天还是正午蓝」。
const SKY_DUSK_TOP := Color(0.16, 0.19, 0.42)
const SKY_DUSK_HORIZON := Color(0.98, 0.60, 0.34)
const SKY_NIGHT_TOP := Color(0.012, 0.020, 0.055)
const SKY_NIGHT_HORIZON := Color(0.055, 0.080, 0.150)
## 日光体色层在夜间退出；夜间ALBEDO/法线/PBR由真实月光与局部灯照亮。
## 夜间环境/天空能量只在Presets中声明，太阳仍为零。
const NIGHT_WATER_FLOOR := 0.0
## 夜里把海往蓝推一点：月光下的海是蓝的，不是黑的，也不是白天那管青。
const NIGHT_WATER_SHIFT := 0.18
## 黄昏把海面染成的金色。挑得比白天体色**更暗**——夕阳下的海是「暗水 + 金鳞」，
## 不是整片发光。选得比体色亮的话，傍晚的水面会比正午还亮（第一版就踩了）。
##
## 红要明显高于绿：白天体色的绿分量本来就高（0.62 左右），往一个「红绿接近」的
## 暖色插，绿分量几乎不变、红蓝跟着掉，整片海就偏成墨绿 —— 第二版就是这样。
const WARM_WATER := Color(0.86, 0.56, 0.40)
## 水面「被照亮了多少」的合成权重：环境光占 0.55、直射太阳占 0.45。
## 水面不收灯光，这两个比值就是它唯一的亮度来源，必须和环境/太阳同一条曲线。
const WATER_AMBIENT_SHARE := 0.55
const WATER_SUN_SHARE := 0.45
## 夕阳阶段留少量暖色海面反光，再于19:00前随night权重一起退去。
const DUSK_WATER_LEVEL := 0.64

var _sun: DirectionalLight3D
var _water_moon: DirectionalLight3D
var _fill_lights: Array = []
var _home_lights: Array = []
var _boat_lights: Array = []
var _env: Environment
var _sky: ProceduralSkyMaterial
var _water: ShaderMaterial
var _water_query: Callable
var _base := {TARGET_SUN: {}, TARGET_ENV: {}, TARGET_WATER: {}, TARGET_SKY: {}}
var _base_dir := {"elevation": 0.0, "azimuth": 0.0}
var _suspended := false
var _hour := 9.0
var _sun_basis := Basis.IDENTITY
var _water_bases := {}
var _applied := false

# ---- 分时段偏移 -------------------------------------------------------------
#
# 面板「季节 → 天气 → 时间段」调出来的差值存在这里，`apply()` 最后一步叠上去。
# 结构：`_offsets[season][weather][slot]["target/prop"] = 差值`。
#
# 为什么是差值而不是绝对值、以及为什么不塞进 `_base`：
# 塞进 `_base` 等于挪基准，所有时段一起变 —— 那正是这次要修的问题。
# 差值叠在「本帧已经算好的值」上，曲线的形状、天气的过渡、段间的插值
# 全都原样不动，只是把这个时段整体抬一点或压一点。
var _offsets := {}
var _season := Slots.DEFAULT_SEASON
var _weather := Slots.DEFAULT_WEATHER
## 不归本装置管的键（泛光、遮蔽、雾起止这些）的原始值。
## 这些键本装置从不写，若每帧拿场景当前值再加差值，会一帧加一次越拖越远；
## 所以第一次见到时抓一份，之后一直以它为底。
var _offset_origin := {}
var _last_natural := {}
## 面板锁定预览的时刻（< 0 表示不锁）。面板要看「夕阳段长什么样」，
## 但游戏时间还在往前走，不锁的话刚调完就被下一帧的时变覆盖回去。
var _preview_hour := -1.0

## 面板锁定的「季节 / 天气」预览（空串 = 不锁，跟随游戏实际值）。
##
## 为什么必须锁天气：偏移是按 `季节|天气|时段` 三键存的，而 `_apply_offsets`
## 取的是**本帧生效**的那一组。游戏里天气钉死在晴时，面板点「多云」只是把差值
## 写进 `spring|cloudy|*`，画面照样读 `spring|clear|*` —— 拖动滑杆完全没反应，
## 存下来的数在游戏里也永远看不到。这正是「天气不一样就无法直接调」的根因。
##
## 所以面板打开期间由它接管**渲染用的**上下文，游戏状态（`_season` / `_weather`）
## 一个字都不改：关面板时 `clear_preview()` 一放，画面立刻回到游戏的实际天气。
var _preview_season := ""
var _preview_weather := ""

## 面板按组查找本装置。用组而不是直接引用：面板是独立场景里也能开的调试器，
## 不该为了它把主场景的装配关系写死。
const GROUP := "daylight_rig"

func _ready() -> void:
	add_to_group(GROUP)
	# 偏移存档在 capture 之前读也行：`apply` 找不到环境/太阳会跳过写入，
	# 之后 main 调 `capture` 完那一帧自然就套上了。
	load_offset_cfg()

# ---- 装配 -------------------------------------------------------------------

## 解析场景节点并抄下基准值。找不到的节点留空，后续 `apply` 跳过该目标 ——
## 验证工程里可能没有水面，没必要为此让整个装置失效。
func capture(scene: Node, water_query := Callable()) -> void:
	if is_instance_valid(_sun) == false:
		_sun = scene.get_node_or_null(SUN_PATH) as DirectionalLight3D
	# The three authored fill lights also illuminate the night unless owned here.
	_fill_lights.clear()
	var lights := scene.get_node_or_null("World/Lights")
	if lights != null:
		for light in lights.get_children():
			if light is DirectionalLight3D and light != _sun and light != _water_moon:
				_fill_lights.append({"node":light,"energy":light.light_energy,"color":light.light_color})
	# An actual directional light supplies the sea's broad moon reflection. Its
	# receiver layer isolates it from the already authored building illumination.
	if lights != null and not is_instance_valid(_water_moon):
		_water_moon = DirectionalLight3D.new()
		_water_moon.name = "WaterMoon"
		_water_moon.light_color = Color(0.70,0.80,0.95)
		_water_moon.light_energy = 0.0
		_water_moon.light_cull_mask = 2
		_water_moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		lights.add_child(_water_moon)
		_water_moon.look_at_from_position(Vector3.ZERO,Vector3(-0.55,-0.8,0.65),Vector3.UP)
	var water_node := scene.get_node_or_null("World/Water") as VisualInstance3D
	if water_node != null:water_node.set_layer_mask_value(2,true)
	var we := scene.get_node_or_null(ENV_PATH) as WorldEnvironment
	_home_lights.clear()
	_boat_lights.clear()
	for light in scene.find_children("*", "Light3D", true, false):
		if light.is_in_group("home_lamps"):
			_home_lights.append({"node":light,"energy":light.light_energy})
		elif light.is_in_group("boat_lamps"):
			_boat_lights.append({"node":light,"energy":light.light_energy})
	if we != null:
		_env = we.environment
	_water_query = water_query
	_capture_sun()
	_capture_env()
	_capture_sky()
	_water = null
	_sync_water_material()


## 天空盒在 `Environment.sky.sky_material` 上。它不是 `Environment` 的属性，
## 面板也没有对应行 —— 所以这里只管抄基准和按时段输出，不对外提供改值口。
func _capture_sky() -> void:
	if _env == null or _env.sky == null:
		return
	var material := _env.sky.sky_material
	if material is ProceduralSkyMaterial:
		_sky = material as ProceduralSkyMaterial
	elif material is ShaderMaterial:
		# 换过天空着色器时不猜属性名，直接跳过：宁可天空不随时段变色，
		# 也不要往一个不认识的材质上写不存在的属性。
		_sky = null
		return
	if _sky == null:
		return
	for key in SKY_KEYS:
		_base[TARGET_SKY][key] = _sky.get(key)


func _capture_sun() -> void:
	if not is_instance_valid(_sun):
		return
	_base[TARGET_SUN] = {
		"light_energy": _sun.light_energy,
		"light_color": _sun.light_color,
		"light_angular_distance": _sun.light_angular_distance,
		"shadow_opacity": _sun.shadow_opacity,
	}
	_sun_basis = _sun.global_basis
	var angles := sun_angles()
	_base_dir = {"elevation": angles.x, "azimuth": angles.y}
	_base[TARGET_SUN]["dir:elevation"] = angles.x
	_base[TARGET_SUN]["dir:azimuth"] = angles.y


func _capture_env() -> void:
	if _env == null:
		return
	_base[TARGET_ENV] = {
		"adjustment_contrast": _env.adjustment_contrast,
		"ambient_light_energy": _env.ambient_light_energy,
		"ambient_light_color": _env.ambient_light_color,
		"background_energy_multiplier": _env.background_energy_multiplier,
		"fog_light_color": _env.fog_light_color,
		"fog_light_energy": _env.fog_light_energy,
		"fog_sky_affect": _env.fog_sky_affect,
	}


## 水面材质会被换方案（`use_scheme`），换过之后基准要重新抄 —— 两套水体色
## 本来就不一样。只有在身份变了时候才重抄，否则每帧都会把当前（已被时变改过的）
## 值当基准，越走越黑。
func _sync_water_material() -> void:
	var live: ShaderMaterial = null
	if _water_query.is_valid():
		live = _water_query.call()
	elif is_instance_valid(_water):
		live = _water
	if live == _water:
		return
	_water = live
	if live != null and _water_bases.has(live):
		_base[TARGET_WATER] = _water_bases[live]
		return
	_base[TARGET_WATER] = {}
	if not is_instance_valid(_water):
		return
	for key in WATER_KEYS:
		# 吸收式水面没有 sky_* 这组 uniform，写进去只会在材质里堆没用的参数。
		var value: Variant = _water.get_shader_parameter(key)
		if value != null:
			_base[TARGET_WATER][key] = value
	_water_bases[live] = _base[TARGET_WATER]


# ---- 面板 / 外部查询 ---------------------------------------------------------

func owns(target: String, key: String) -> bool:
	return _base.get(target, {}).has(key)


func base_of(target: String, key: String) -> Variant:
	return _base.get(target, {}).get(key)


## 面板拖动时调这里：改的是基准，下一帧由本装置乘上时变系数输出。
## 这样「白天基准」和「此刻画面」不会互相污染 —— 深夜把太阳强度调到 2.0，
## 基准就是 2.0，第二天09:00看到的也是 2.0。
func adopt(target: String, key: String, value: Variant) -> void:
	if not owns(target, key):
		return
	_base[target][key] = value
	if target == TARGET_SUN and (key == "dir:elevation" or key == "dir:azimuth"):
		_base_dir[key.substr(4)] = float(value)
		_set_sun_angles(_base_dir.elevation,_base_dir.azimuth)
		_sun_basis = _sun.global_basis
	if not _suspended:
		apply(_hour)


## 写回资源文件前调一次：把基准值铺回场景，让 `ResourceSaver` / 场景文本
## 拿到的是基准而不是此刻夜间的值。写完 `resume()` 让时变继续接管。
func suspend() -> void:
	_suspended = true
	_write_base()


func resume() -> void:
	_suspended = false
	apply(_hour)


func is_suspended() -> bool:
	return _suspended


# ---- 分时段偏移 -------------------------------------------------------------

## 当前场景属于哪个季节、什么天气。面板按这两个维度分组存偏移；
## 运行时只应用「当前季节 + 当前天气」那一套，其它组合存着不生效。
##
## 季节暂时固定：项目还没有季节推进规则，这里不发明一个。等季节系统上线，
## 把 `season` 交给它就够了 —— 四季的偏移已经按季节分好类存着了。
func set_scene_context(season: String, weather: String) -> void:
	var changed := season != _season or weather != _weather
	_season = season if Slots.SEASON_ORDER.has(season) else Slots.DEFAULT_SEASON
	_weather = weather if Slots.WEATHER_ORDER.has(weather) else Slots.DEFAULT_WEATHER
	if changed and not _suspended:
		apply(_hour)


func season() -> String:
	return _season


func weather() -> String:
	return _weather


## 当前生效的时刻。锁着预览时返回预览时刻 —— 面板按它决定「现在站在哪一段」。
func hour() -> float:
	return _preview_hour if _preview_hour >= 0.0 else _hour


## 本帧**渲染用**的季节 / 天气：面板锁着预览就是面板选的，否则是游戏实际值。
## 偏移混合只认这两个 —— 面板能预览到多云，就靠这一层把「读取哪一组偏移」
## 和「游戏此刻是什么天气」解耦。
func effective_season() -> String:
	return _preview_season if _preview_season != "" else _season


func effective_weather() -> String:
	return _preview_weather if _preview_weather != "" else _weather


func is_previewing() -> bool:
	return _preview_hour >= 0.0 or _preview_season != "" or _preview_weather != ""


## 面板打开时把画面锁在某个组合。主循环每帧还会照常 `apply(真实时刻)`，
## 但 `apply` 开头会把这些参数换掉，所以画面不会被时间或天气推走。
##
## `season_id` / `weather_id` 传空串表示「这一次不动它」；要整体放开用
## `clear_preview()`。面板每次都传全，空串这条只给单测和探针留口。
func set_preview(hour: float, season_id := "", weather_id := "") -> void:
	_preview_hour = fposmod(hour, 24.0)
	if season_id != "":
		_preview_season = season_id if Slots.SEASON_ORDER.has(season_id) else _season
	if weather_id != "":
		_preview_weather = weather_id if Slots.WEATHER_ORDER.has(weather_id) else _weather
	if not _suspended:
		apply(_hour)


## 面板关掉后必须调它，否则游戏时间会跟着面板一起停住，
## 天气也会一直停在面板最后点的那个上。
func clear_preview() -> void:
	_preview_hour = -1.0
	_preview_season = ""
	_preview_weather = ""
	if not _suspended:
		apply(_hour)


## 面板写入口：给某一组合的某项记一个差值。`full` 形如 `sun/light_energy`。
## 布尔项记的是绝对值（开关只能开或关，没法「差半个开关」）。
func set_offset(season_id: String, weather_id: String, slot: String, full: String, value: Variant) -> void:
	if not Slots.SEASON_ORDER.has(season_id) or not Slots.WEATHER_ORDER.has(weather_id):
		return
	if not Slots.slot_ids().has(slot):
		return
	if value is bool:
		_offsets.get_or_add(season_id, {}).get_or_add(weather_id, {}).get_or_add(slot, {})[full] = value
	elif value is Vector3:
		# 方向向量不能「加一个差值」：加完就没单位长度了，归一化之后等于换了个方向。
		# 而且 `sun_direction` 本来就由 `water_sun_direction()` 每帧按太阳弧算出来，
		# 给它记偏移是跟弧线打架。直接不收。
		return
	else:
		# 差值为 0 / 全零颜色等于没调，不占存档位。
		if _is_zero(value):
			erase_offset(season_id, weather_id, slot, full)
			return
		_offsets.get_or_add(season_id, {}).get_or_add(weather_id, {}).get_or_add(slot, {})[full] = value
	if not _suspended:
		apply(_hour)


func offset_of(season_id: String, weather_id: String, slot: String, full: String) -> Variant:
	return _offsets.get(season_id, {}).get(weather_id, {}).get(slot, {}).get(full)


func erase_offset(season_id: String, weather_id: String, slot: String, full: String) -> void:
	var slots: Dictionary = _offsets.get(season_id, {}).get(weather_id, {})
	if not slots.has(slot):
		return
	(slots[slot] as Dictionary).erase(full)
	_prune(season_id, weather_id, slot)


## 清掉一整套组合的偏移。面板上「复位本段」按这个。
func erase_slot(season_id: String, weather_id: String, slot: String) -> void:
	var slots: Dictionary = _offsets.get(season_id, {}).get(weather_id, {})
	slots.erase(slot)
	_prune(season_id, weather_id, slot)
	if not _suspended:
		apply(_hour)


## 整份替换（存档加载用）。传之前先 `erase_slot` 清干净的组合不会被残留键污染。
func load_offsets(data: Dictionary) -> void:
	_offsets = data.duplicate(true)
	_offset_origin.clear()
	if not _suspended:
		apply(_hour)


func offsets_snapshot() -> Dictionary:
	return _offsets.duplicate(true)


## 某一组合实际存了几项。面板用它标「这一段调过」。
func offset_count(season_id: String, weather_id: String, slot: String) -> int:
	return (_offsets.get(season_id, {}).get(weather_id, {}).get(slot, {}) as Dictionary).size()


## 某个天气下（不分时段）一共存了几项。侧栏的天气按钮靠它打点：
## 点了「多云」画面却没变化时，这个数是 0 —— 说明这套还没调过，
## 不是面板失灵。
func weather_offset_count(season_id: String, weather_id: String) -> int:
	var total := 0
	var by_slot: Dictionary = _offsets.get(season_id, {}).get(weather_id, {})
	for slot in by_slot.keys():
		total += (by_slot[slot] as Dictionary).size()
	return total


## 某个季节下（不分天气、时段）一共存了几项。季节按钮打点用。
func season_offset_count(season_id: String) -> int:
	var total := 0
	var by_weather: Dictionary = _offsets.get(season_id, {})
	for weather in by_weather.keys():
		var by_slot: Dictionary = by_weather[weather]
		for slot in by_slot.keys():
			total += (by_slot[slot] as Dictionary).size()
	return total


func _prune(season_id: String, weather_id: String, slot: String) -> void:
	var slots: Dictionary = _offsets.get(season_id, {}).get(weather_id, {})
	if slots.has(slot) and (slots[slot] as Dictionary).is_empty():
		slots.erase(slot)
	var by_season: Dictionary = _offsets.get(season_id, {})
	if by_season.has(weather_id) and (by_season[weather_id] as Dictionary).is_empty():
		by_season.erase(weather_id)
	if _offsets.has(season_id) and (_offsets[season_id] as Dictionary).is_empty():
		_offsets.erase(season_id)


## 当前时刻这一套偏移混合后的结果。段内恒定、段间按同一条 smoothstep 过渡 ——
## 用的是 `Slots.slot_weights`，和明暗曲线共一条，所以偏移不会在边界突然出现。
func _blend_offsets(season_id: String, weather_id: String, hour: float) -> Dictionary:
	var slots: Dictionary = _offsets.get(season_id, {}).get(weather_id, {})
	if slots.is_empty():
		return {}
	var weights := Slots.slot_weights(hour)
	var out := {}
	for slot in weights.keys():
		var weight := float(weights[slot])
		var data: Dictionary = slots.get(slot, {})
		if data.is_empty():
			continue
		for full in data.keys():
			var v: Variant = data[full]
			if v is bool:
				# 开关没有「半个」：哪一段的权重过半就听哪一段。
				if weight >= 0.5:
					out[full] = v
				continue
			var prev: Variant = out.get(full)
			if prev == null:
				out[full] = _scaled(v, weight)
			else:
				out[full] = _add(prev, _scaled(v, weight))
	return out


## 把混合后的差值叠到本帧已经算好的值上。必须排在 `_apply_sun/env/sky/water`
## 之后：它读的是那些函数刚写出去的数，早一步读到的就是上一帧的旧值。
func _apply_offsets(hour: float) -> void:
	# 换了时段/天气/组合之后，上一轮的原始值快照就过期了；这里清掉让面板
	# 拿不到残留数据，宁可它退回读场景（那时场景值就是原始值）。
	_last_natural.clear()
	if _offsets.is_empty():
		return
	# 用「渲染用」上下文而不是游戏实际值：面板预览多云时，画面要读多云那一组。
	var blended := _blend_offsets(effective_season(), effective_weather(), hour)
	if blended.is_empty():
		return
	for full in blended.keys():
		var parts := String(full).split("/", true, 1)
		if parts.size() != 2:
			continue
		var target := parts[0]
		var prop := parts[1]
		var delta: Variant = blended[full]
		var base: Variant = _offset_base(target, prop)
		if base == null:
			continue
		_last_natural[full] = base
		if delta is bool:
			_scene_write(target, prop, delta)
			continue
		_scene_write(target, prop, _add(base, delta))


## 某一项「没有偏移时应该是多少」。面板拿它算差值：用户拖到 0.70，
## 原始值是 0.54，那要存的就是 +0.16。没有偏移的项返回 null，
## 调用方退回读场景 —— 那时场景值本来就等于原始值。
##
## 两处来源都要看：归本装置管的键每帧重算（`_last_natural`），
## 不归的键只有第一次加偏移时抓过一次（`_offset_origin`）。
func natural_of(full: String) -> Variant:
	if _last_natural.has(full):
		return _last_natural[full]
	return _offset_origin.get(full)


## 加差值之前的「原值」。
##
## 归本装置管的键每帧都由 `_apply_*` 重写，读出来就是本帧的干净值 —— 直接用。
## 不归本装置管的键（泛光、遮蔽、雾起止）本装置从不写，场景里一直是同一个数；
## 若每帧在当前值上再加差值，会一帧加一次越拖越远，所以抓一份原始值缓存住。
func _offset_base(target: String, prop: String) -> Variant:
	if owns(target, prop):
		return _scene_read(target, prop)
	var full := "%s/%s" % [target, prop]
	if not _offset_origin.has(full):
		var v: Variant = _scene_read(target, prop)
		if v == null:
			return null
		_offset_origin[full] = v
	return _offset_origin[full]


## 读/写一个引擎值。四类目标的入口不一样，所以集中在这里，别处只跟 key 打交道：
##   sun   —— DirectionalLight3D 的属性；`dir:*` 是朝向的两个虚拟轴
##   env   —— Environment 的属性
##   sky   —— ProceduralSkyMaterial 的属性（在 `Environment.sky.sky_material` 上）
##   water —— 着色器 uniform（`set_shader_parameter`，不是属性）
##
## 水面这一支必须用 shader parameter 接口：`get_indexed` 在 ShaderMaterial 上
## 拿不到 uniform，会静默返回 null，表现为「存了偏移但画面不动」。
func _scene_read(target: String, prop: String) -> Variant:
	if prop.begins_with("dir:"):
		if not is_instance_valid(_sun):
			return null
		var angles := sun_angles()
		return angles.x if prop == "dir:elevation" else angles.y
	if target == TARGET_WATER:
		if not is_instance_valid(_water):
			return null
		return _water.get_shader_parameter(prop)
	if target == TARGET_SKY:
		if _sky == null:
			return null
		return _sky.get(prop)
	var obj: Object = null
	if target == TARGET_ENV:
		obj = _env
	elif target == TARGET_SUN and is_instance_valid(_sun):
		obj = _sun
	if obj == null:
		return null
	return obj.get_indexed(NodePath(prop))


func _scene_write(target: String, prop: String, value: Variant) -> void:
	if prop.begins_with("dir:"):
		if not is_instance_valid(_sun):
			return
		var angles := sun_angles()
		if prop == "dir:elevation":
			_set_sun_angles(float(value), angles.y)
		else:
			_set_sun_angles(angles.x, float(value))
		return
	if target == TARGET_WATER:
		if is_instance_valid(_water):
			_water.set_shader_parameter(prop, value)
		return
	if target == TARGET_SKY:
		if _sky != null:
			_sky.set(prop, value)
		return
	var obj: Object = null
	if target == TARGET_ENV:
		obj = _env
	elif target == TARGET_SUN and is_instance_valid(_sun):
		obj = _sun
	if obj == null:
		return
	obj.set_indexed(NodePath(prop), value)


static func _is_zero(v: Variant) -> bool:
	if v is float or v is int:
		return is_zero_approx(float(v))
	if v is Color:
		var c := v as Color
		return is_zero_approx(c.r) and is_zero_approx(c.g) and is_zero_approx(c.b)
	return false


static func _scaled(v: Variant, w: float) -> Variant:
	if v is Color:
		var c := v as Color
		return Color(c.r * w, c.g * w, c.b * w, c.a)
	return float(v) * w


static func _add(a: Variant, b: Variant) -> Variant:
	if a is Color:
		var ca := a as Color
		if b is Color:
			var cb := b as Color
			return Color(ca.r + cb.r, ca.g + cb.g, ca.b + cb.b, ca.a)
		var f := float(b)
		return Color(ca.r + f, ca.g + f, ca.b + f, ca.a)
	return float(a) + float(b)


# ---- 偏移存档 ---------------------------------------------------------------
#
# 和 `filter.cfg`（面板那套「基准值」）分开存，两件事：
#   filter.cfg       —— 09:00 基准，改了等于改整天的底色；
#   light_slots.cfg  —— 某一段的差值，只在那一段生效。
# 合在一个文件里，「复位本段」和「复位全部」就会互相踩。

const OFFSET_CFG_PATH := "user://light_slots.cfg"


func load_offset_cfg() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(OFFSET_CFG_PATH) != OK:
		return
	var data := {}
	for section in cfg.get_sections():
		var parts := Slots.split_section(section)
		if parts.is_empty():
			continue
		for key in cfg.get_section_keys(section):
			var full := _decode_key(String(key))
			if full.split("/").size() != 2:
				continue
			data.get_or_add(String(parts.season), {}).get_or_add(String(parts.weather), {}) \
				.get_or_add(String(parts.slot), {})[full] = cfg.get_value(section, key)
	load_offsets(data)


func save_offset_cfg() -> void:
	var cfg := ConfigFile.new()
	for season in _offsets.keys():
		for weather in (_offsets[season] as Dictionary).keys():
			for slot in ((_offsets[season] as Dictionary)[weather] as Dictionary).keys():
				var data: Dictionary = ((_offsets[season] as Dictionary)[weather] as Dictionary)[slot]
				if data.is_empty():
					continue
				var section := Slots.section_of(String(season), String(weather), String(slot))
				for full in data.keys():
					cfg.set_value(section, _encode_key(String(full)), data[full])
	cfg.save(OFFSET_CFG_PATH)


## 键里的 `/` 换成 `__`。ConfigFile 的键名虽然大多能含斜杠，但它同时被当作
## 路径片段解析，换个分隔符最省心 —— 属性名里没有连续两个下划线，不会撞。
static func _encode_key(full: String) -> String:
	return full.replace("/", "__")


static func _decode_key(key: String) -> String:
	return key.replace("__", "/")


# ---- 时变相位 ---------------------------------------------------------------

## 七个时段的循环插值；day/elevation为相对09:00太阳高度，night/warm为颜色混合权重。
static func phase(hour: float) -> Dictionary:
	return Presets.sample(hour)

func _factors(hour: float) -> Dictionary:
	return Presets.sample(hour)


# ---- 输出 -------------------------------------------------------------------

func apply(hour: float) -> void:
	if _preview_hour >= 0.0:
		hour = _preview_hour
	_hour = hour
	if _suspended:
		return
	_sync_water_material()
	var h := fposmod(hour,24.0)
	if h >= 7.0 and h <= 11.0:
		_write_base()
		_apply_offsets(hour)
		return
	var f := _factors(hour)
	_apply_home_lights(lamp_amount(hour))
	RenderingServer.global_shader_parameter_set("world_night",float(f.night))
	if is_instance_valid(_water_moon):_water_moon.light_energy=0.32*float(f.night)
	RenderingServer.global_shader_parameter_set("world_daylight", clampf(float(f.ambient_energy)+float(f.sun_energy),0.0,1.0)*(1.0-float(f.night)))
	for entry in _fill_lights:
		entry.node.light_energy = float(entry.energy)*float(f.ambient_energy)*(0.55 if _hour>=5.5 and _hour<7.0 else 1.0)
		entry.node.light_color = (entry.color as Color).lerp(DUSK_AMBIENT,float(f.warm)*0.65)
		entry.node.light_color = entry.node.light_color.lerp(NIGHT_AMBIENT,float(f.night))
	_apply_sun(f)
	_apply_env(f)
	_apply_sky(f)
	_apply_water(f)
	_apply_offsets(hour)
	_applied = true


static func lamp_amount(hour: float) -> float:
	var h := fposmod(hour,24.0)
	return smoothstep(18.0,19.0,h) if h>=12.0 else 1.0-smoothstep(5.5,7.0,h)


func _apply_home_lights(amount: float) -> void:
	RenderingServer.global_shader_parameter_set("world_home_lights",amount)
	for entry in _home_lights + _boat_lights:
		if is_instance_valid(entry.node): entry.node.light_energy=float(entry.energy)*amount


func _apply_sun(f: Dictionary) -> void:
	if not is_instance_valid(_sun):
		return
	var base: Dictionary = _base[TARGET_SUN]
	if base.is_empty():
		return
	var warm: float = f.warm
	var night: float = f.night
	var base_color: Color = base["light_color"]
	_sun.light_energy = float(base["light_energy"]) * float(f.sun_energy)
	_sun.light_color = base_color.lerp(Color(1.0,0.48,0.20) if _hour<7.0 else WARM_SUN, warm * 0.92)
	_sun.light_angular_distance = float(base["light_angular_distance"]) * float(f.angular)
	_sun.shadow_opacity = clampf(float(base["shadow_opacity"]) * float(f.shadow_opacity), 0.0, 1.0)
	var angles := arc_angles(_hour)
	_set_sun_angles(angles.x, angles.y)


func _apply_env(f: Dictionary) -> void:
	if _env == null:
		return
	var base: Dictionary = _base[TARGET_ENV]
	if base.is_empty():
		return
	var warm: float = f.warm
	var night: float = f.night
	_env.ambient_light_energy = float(base["ambient_light_energy"]) * float(f.ambient_energy)
	# The authored low contrast lifts RGB zero to gray; preserve true black at night.
	_env.adjustment_contrast = lerpf(float(base["adjustment_contrast"]),1.0,night)
	var ambient: Color = base["ambient_light_color"]
	ambient = ambient.lerp(Color(0.68,0.78,0.92) if _hour < 7.0 else DUSK_AMBIENT, warm * 0.45)
	ambient = ambient.lerp(NIGHT_AMBIENT, night)
	_env.ambient_light_color = ambient
	_env.background_energy_multiplier = float(base["background_energy_multiplier"]) * float(f.sky_energy)
	var fog: Color = base["fog_light_color"]
	fog = fog.lerp(DUSK_SKY_HORIZON, warm * 0.35)
	fog = fog.lerp(NIGHT_FOG, night)
	_env.fog_light_color = fog
	_env.fog_light_energy = float(base["fog_light_energy"]) * float(f.fog_energy)
	# 雾是否盖到天空：白天让它跟着海面融进地平线；夜里天空本身已经够暗，
	# 再让雾压上去会把仅剩的一点星光也糊掉，所以夜间收一点。
	_env.fog_sky_affect = clampf(float(base["fog_sky_affect"]) * (1.0 - 0.4 * night), 0.0, 1.0)


## 天空盒。玩家抬头看到的那片天 —— 这里不改，傍晚的天空就还是正午的蓝。
func _apply_sky(f: Dictionary) -> void:
	if _sky == null:
		return
	var base: Dictionary = _base[TARGET_SKY]
	if base.is_empty():
		return
	var warm: float = f.warm
	var night: float = f.night
	var top: Color = base["sky_top_color"]
	top = top.lerp(Color(0.30,0.46,0.66) if _hour < 7.0 else SKY_DUSK_TOP, warm * 0.85)
	top = top.lerp(SKY_NIGHT_TOP, night)
	var horizon: Color = base["sky_horizon_color"]
	horizon = horizon.lerp(Color(1.0,0.72,0.46) if _hour < 7.0 else SKY_DUSK_HORIZON, warm * 0.9)
	horizon = horizon.lerp(SKY_NIGHT_HORIZON, night)
	var ground_h: Color = base["ground_horizon_color"]
	ground_h = ground_h.lerp(SKY_DUSK_HORIZON, warm * 0.5)
	ground_h = ground_h.lerp(SKY_NIGHT_HORIZON, night)
	var ground_b: Color = base["ground_bottom_color"]
	ground_b = ground_b.lerp(SKY_NIGHT_TOP, night)
	_sky.sky_top_color = top
	_sky.sky_horizon_color = horizon
	_sky.ground_horizon_color = ground_h
	_sky.ground_bottom_color = ground_b
	# 日晕的锐度：太阳低的时候大气散射更散，光晕该更大更软。
	_sky.sun_curve = lerpf(float(base.sun_curve),0.62,warm)
	_sky.sun_angle_max = lerpf(float(base.sun_angle_max),27.0,warm)


func _apply_water(f: Dictionary) -> void:
	if not is_instance_valid(_water):
		return
	var base: Dictionary = _base[TARGET_WATER]
	if base.is_empty():
		return
	var warm: float = f.warm
	var night: float = f.night
	for key in WATER_KEYS:
		if not base.has(key):
			continue
		var value: Variant = base[key]
		match key:
			"night_albedo", "night_roughness", "night_deep_albedo", "night_depth_distance", "night_shallow_opacity":
				_water.set_shader_parameter(key,value)
			"sky_top_color":
				_water.set_shader_parameter(key, (value as Color).lerp(DUSK_SKY_TOP, warm * 0.7).lerp(NIGHT_SKY_TOP, night))
			"sky_horizon_color":
				_water.set_shader_parameter(key, (value as Color).lerp(DUSK_SKY_HORIZON, warm * 0.8).lerp(NIGHT_SKY_HORIZON, night))
			"sky_ground_color":
				_water.set_shader_parameter(key, (value as Color).lerp(NIGHT_SKY_GROUND, night))
			"sky_sun_glow":
				# 日晕只在有太阳的时候存在，夜里归零。
				_water.set_shader_parameter(key, float(value) * float(f.sun_energy))
			"sun_color":
				_water.set_shader_parameter(key, (value as Color).lerp(WARM_SUN, warm * 0.85))
			"sun_highlight_strength":
				# 水面高光靠太阳，太阳落了就不该还在水里留一个亮斑。
				# 用 `lit` 而不是 `day`：黄昏太阳还亮着，水面该有那条金色光路。
				_water.set_shader_parameter(key, float(value) * float(f.sun_energy))
			"sun_direction":
				_water.set_shader_parameter(key, water_sun_direction())
			"body_shallow", "body_deep":
				# 亮度：用和环境光/太阳同一条曲线推出的「照亮程度」，而不是另一套手写系数。
				# 两条曲线一旦分家，就会出现「傍晚的水面比正午还亮」这种明显错的画面
				# （第一版把暖色插值直接乘了上去，就是这个问题）。
				# 色相：黄昏往金偏、深夜往蓝偏，与亮度分开算，别叠成两次压暗。
				#
				# 深水只吃一半暖色：夕阳染金的是浅滩和浪尖，深海在傍晚依然是蓝的。
				# 两处一样染，整片海会变成一片橙糊（浅滩的绿也会被染成橄榄）。
				var body: Color = value
				# 夕阳染金是**色相**变化，不是往绿底上掺橙。
				# 浅水体色的绿分量本来就到 0.95，直接 lerp 暖色，绿依然主导 ——
				# 出来是一片灰橄榄，不是金色（第三版就是这样，18:00 的水看着发灰绿）。
				# 所以先把亮度摘出来，用暖色按同一亮度重建一个颜色，再按权重混回去：
				# 亮度守恒，色相由暖色决定。深水只混一半 —— 深海在傍晚依然是蓝的。
				var warm_mix := warm * (0.62 if key == "body_shallow" else 0.30) * (0.42 if _hour < 7.0 else 1.0)
				if warm_mix > 0.001:
					var lum := body.get_luminance()
					var warm_body := Color(WARM_WATER.r, WARM_WATER.g, WARM_WATER.b) * (lum / maxf(WARM_WATER.get_luminance(), 0.001))
					body = Color(
						lerpf(body.r, clampf(warm_body.r, 0.0, 1.0), warm_mix),
						lerpf(body.g, clampf(warm_body.g, 0.0, 1.0), warm_mix),
						lerpf(body.b, clampf(warm_body.b, 0.0, 1.0), warm_mix))
				var illum := clampf(float(f.ambient_energy) * WATER_AMBIENT_SHARE
					+ float(f.sun_energy) * WATER_SUN_SHARE, NIGHT_WATER_FLOOR, 1.2)
				# 黄昏时太阳角度低，能量的曲线已经掉下去了，但那时的海面**不该跟着变暗**：
				# 落日贴着海平线，光几乎全打在浪面上，正是一天里海最亮的时候之一。
				# 白天到黄昏的亮度下限按 warm 抬起，否则「金色」会和「压暗」叠成灰橄榄。
				illum = maxf(illum, lerpf(NIGHT_WATER_FLOOR, DUSK_WATER_LEVEL, warm)) * (1.0-night)
				# 夜深与黄昏是两件互斥的事：色偏叠加时，黄昏的蓝会抵消刚染上的金。
				var wet_night := night * (1.0 - warm)
				var r := body.r * illum * (1.0 - NIGHT_WATER_SHIFT * 0.5 * wet_night)
				var g := body.g * illum * (1.0 - NIGHT_WATER_SHIFT * 0.3 * wet_night)
				var b := body.b * illum * (1.0 + NIGHT_WATER_SHIFT * 0.25 * wet_night)
				_water.set_shader_parameter(key, Color(clampf(r, 0.0, 1.0), clampf(g, 0.0, 1.0), clampf(b, 0.0, 1.0), 1.0))


## 把当前时变值整体铺回基准 —— 只在 `suspend()` 里用。
func _write_base() -> void:
	RenderingServer.global_shader_parameter_set("world_daylight", 1.0)
	RenderingServer.global_shader_parameter_set("world_night", 0.0)
	if is_instance_valid(_water_moon):_water_moon.light_energy=0.0
	_apply_home_lights(0.0)
	for entry in _fill_lights:
		entry.node.light_energy=entry.energy
		entry.node.light_color=entry.color
	if is_instance_valid(_sun) and not _base[TARGET_SUN].is_empty():
		var s: Dictionary = _base[TARGET_SUN]
		_sun.light_energy = float(s["light_energy"])
		_sun.light_color = s["light_color"]
		_sun.light_angular_distance = float(s["light_angular_distance"])
		_sun.shadow_opacity = float(s["shadow_opacity"])
		_sun.global_basis = _sun_basis
	if _env != null and not _base[TARGET_ENV].is_empty():
		var e: Dictionary = _base[TARGET_ENV]
		_env.ambient_light_energy = float(e["ambient_light_energy"])
		_env.ambient_light_color = e["ambient_light_color"]
		_env.background_energy_multiplier = float(e["background_energy_multiplier"])
		_env.fog_light_color = e["fog_light_color"]
		_env.fog_light_energy = float(e["fog_light_energy"])
		_env.fog_sky_affect = float(e["fog_sky_affect"])
		_env.adjustment_contrast = e["adjustment_contrast"]
	if _sky != null and not _base[TARGET_SKY].is_empty():
		for key in _base[TARGET_SKY]:
			_sky.set(key, _base[TARGET_SKY][key])
	if is_instance_valid(_water) and not _base[TARGET_WATER].is_empty():
		for key in _base[TARGET_WATER]:
			_water.set_shader_parameter(key, _base[TARGET_WATER][key])


# ---- 太阳朝向 ---------------------------------------------------------------

## 场景里那份朝向的高度角与方位角（度）。高度角正数朝上，方位角 0 = +Z。
##
## 这里必须和 `color_grade_panel.gd::_sun_angles()` 用同一套约定：读的是
## **光的行进方向** `-basis.z`，而不是 `basis.z`。两者差 180°，读的时候用一套、
## `_set_sun_angles` 写的时候按另一套解释，正午就会把太阳甩到场景背后去
## （`look_at` 让 -Z 指向目标，所以写出去的方位天然是「行进方向」那一套）。
func sun_angles() -> Vector2:
	if not is_instance_valid(_sun):
		return Vector2.ZERO
	var d := -_sun.global_transform.basis.z.normalized()
	return Vector2(rad_to_deg(asin(clampf(-d.y, -1.0, 1.0))), rad_to_deg(atan2(d.x, d.z)))


## 当前时刻太阳应有的朝向：以场景基准方位为中心、正午最高。
## 关键帧在独立预设中定义，凌晨保持低位，清晨平滑转回日出方向。
func arc_angles(hour: float) -> Vector2:
	if _base_dir.is_empty():
		return sun_angles()
	var p := phase(hour)
	# 高度和方位各自按预设插值，09:00由apply直接恢复原始变换。
	var elevation: float = float(_base_dir["elevation"]) * float(p.elevation)
	return Vector2(maxf(elevation, 1.5), _base_dir["azimuth"] + float(p.azimuth))


func _set_sun_angles(elevation: float, azimuth: float) -> void:
	if not is_instance_valid(_sun):
		return
	var el := deg_to_rad(clampf(elevation, 1.0, 89.0))
	var az := deg_to_rad(azimuth)
	var dir := Vector3(sin(az) * cos(el), -sin(el), cos(az) * cos(el))
	var origin := _sun.global_position
	_sun.look_at_from_position(origin, origin + dir, Vector3.UP)


## 水面那份 `sun_direction` 用的是「指向太阳」的约定（与场景 Sun 的 -Z 相反），
## 而且基准向量和场景太阳的方位在 X 上本来就差一个符号 —— 那是美术手工调过的，
## 不在这里替它纠偏。做法是只沿基准向量自己的方位做等量旋转：09:00严格回到原值。
func water_sun_direction() -> Vector3:
	var base: Variant = _base[TARGET_WATER].get("sun_direction")
	if base == null:
		return Vector3.UP
	var v := (base as Vector3).normalized()
	var el0 := asin(clampf(v.y, -1.0, 1.0))
	var az0 := atan2(v.x, v.z)
	var p := phase(_hour)
	var elevation: float = el0 * float(p.elevation)
	var azimuth: float = az0 + deg_to_rad(float(p.azimuth))
	return Vector3(sin(azimuth) * cos(elevation), sin(elevation), cos(azimuth) * cos(elevation))
