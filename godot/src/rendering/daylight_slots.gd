extends RefCounted
## P 面板「光照」页的分时段调参槽位：季节 → 天气 → 时间段。
##
## 为什么需要这一层：`daylight_rig` 的基准是**一套** 09:00 的数，按时段乘系数
## 输出。想「只把夜里的泛光调亮」就做不到 —— 改基准等于改整天的样子。
## 这里把「时段」提成一级分类，让每个 (季节, 天气, 时段) 能各自留一份偏移，
## 叠加在原有曲线之上。
##
## 偏移是**差值**不是绝对值，这一点是这套东西能成立的关键：
##   绝对值 —— 夕阳段直接拍成 0.70，17:00 到 18:30 就没有渐暗了，动态被调平；
##   差值   —— 整段整体平移 0.14，段内的渐暗形状原样保留。
## 主人要的是「不影响天气变化动态逻辑」，只有差值能满足。
##
## 时段表不是手抄的第二份真相：`SLOTS` 的 label 必须和 `daylight_presets.gd`
## 的 `PRESETS[*].label` 对得上，`verify()` 会当场报出来。改预设不回来改这里，
## 面板就会把某一段的偏移写到相邻段上去。
##
## 季节目前只是**配置分类**：项目没有季节推进系统，运行时固定用 `DEFAULT_SEASON`。
## 四季的偏移都会存下来，等季节系统上线就能直接用 —— 这里不发明季节规则。

const Presets = preload("res://src/rendering/daylight_presets.gd")

const SEASON_ORDER := ["spring", "summer", "autumn", "winter"]
const SEASON_LABELS := {
	"spring": "春",
	"summer": "夏",
	"autumn": "秋",
	"winter": "冬",
}
const DEFAULT_SEASON := "spring"

## 天气 id 直接沿用 `weather_service.gd` 的 `KINDS`，不另立一套同义词。
const WEATHER_ORDER := ["clear", "cloudy", "rain"]
const WEATHER_LABELS := {
	"clear": "晴",
	"cloudy": "多云",
	"rain": "雨",
}
const DEFAULT_WEATHER := "clear"

## 时段槽位。`hour` 是该段第一个关键帧的时刻 —— 面板切到这一段时按这个时刻
## 预览，看到的才是「这一段真实长什么样」。
const SLOTS := [
	{"id": "deep_night", "label": "深夜", "hour": 0.0},
	{"id": "pre_dawn", "label": "黎明前", "hour": 5.5},
	{"id": "dawn", "label": "清晨", "hour": 6.0},
	{"id": "morning", "label": "上午", "hour": 7.0},
	{"id": "noon", "label": "正午", "hour": 12.0},
	{"id": "afternoon", "label": "下午", "hour": 14.2},
	{"id": "sunset", "label": "夕阳", "hour": 17.0},
	{"id": "night", "label": "黑夜", "hour": 19.0},
]

## 下面几张表每次进 apply 都要用，建一次就够。`static var` 在 4.x 里是
## 按脚本共享的，比每帧重建 8 项字典省得多。
static var _ids_cache: Array[String] = []
static var _label_cache := {}


static func slot_ids() -> Array[String]:
	if _ids_cache.is_empty():
		for s in SLOTS:
			_ids_cache.append(String(s.id))
	return _ids_cache


static func slot_label(id: String) -> String:
	for s in SLOTS:
		if String(s.id) == id:
			return String(s.label)
	return id


## 时段 id → 该段第一个关键帧的时刻。面板预览用。
static func slot_hour(id: String) -> float:
	for s in SLOTS:
		if String(s.id) == id:
			return float(s.hour)
	return 0.0


## 预设 label → 时段 id。label 重复是刻意的（上午占 7.0 与 11.0 两个关键帧），
## 重复 label 必须指向同一个时段，否则一个平顶段会被拆成两半。
static func _label_to_id() -> Dictionary:
	if _label_cache.is_empty():
		for s in SLOTS:
			_label_cache[String(s.label)] = String(s.id)
	return _label_cache


## 第 `index` 个关键帧属于哪个时段。
static func slot_of_keyframe(index: int) -> String:
	var presets: Array = Presets.PRESETS
	if index < 0 or index >= presets.size():
		return String(SLOTS[0].id)
	var label := String(presets[index].label)
	var id := String(_label_to_id().get(label, ""))
	if id != "":
		return id
	# label 对不上时退回「按时间找最近的前一个槽位」，而不是抛错：
	# 调试面板宁可少一个分组，也不该把整页打不开。
	return slot_at(float(presets[index].hour))


## `hour` 落在哪一段。区间左闭右开，24:00 归最后一段。
static func slot_at(hour: float) -> String:
	var h := fposmod(hour, 24.0)
	var presets: Array = Presets.PRESETS
	for i in range(presets.size() - 1):
		if h >= float(presets[i].hour) and h < float(presets[i + 1].hour):
			return slot_of_keyframe(i)
	return slot_of_keyframe(presets.size() - 2)


## 某一时刻各时段的混合权重，最多两项。
##
## 和 `Presets.sample()` 用同一个 `smoothstep`，所以「偏移的过渡」和「原来的
## 明暗过渡」是同一条曲线 —— 偏移不会在段边界突然出现或消失。
static func slot_weights(hour: float) -> Dictionary:
	var h := fposmod(hour, 24.0)
	var presets: Array = Presets.PRESETS
	for i in range(presets.size() - 1):
		var a: Dictionary = presets[i]
		var b: Dictionary = presets[i + 1]
		if h < float(a.hour) or h > float(b.hour):
			continue
		var id_a := slot_of_keyframe(i)
		var id_b := slot_of_keyframe(i + 1)
		if id_a == id_b:
			# 平顶段（上午 07:00–11:00）：中间插值没有意义，整段同一个偏移。
			return {id_a: 1.0}
		var t := smoothstep(float(a.hour), float(b.hour), h)
		var out := {}
		if 1.0 - t > 0.0:
			out[id_a] = 1.0 - t
		if t > 0.0:
			out[id_b] = t
		return out
	return {}


## 存档 section 名。三段拼起来，读 cfg 时一眼能看出是哪一套。
static func section_of(season: String, weather: String, slot: String) -> String:
	return "%s|%s|%s" % [season, weather, slot]


static func split_section(section: String) -> Dictionary:
	var parts := section.split("|")
	if parts.size() != 3:
		return {}
	# 不认识的值直接丢掉，别让一份手改坏的 cfg 把面板搞哑。
	if not SEASON_ORDER.has(parts[0]) or not WEATHER_ORDER.has(parts[1]):
		return {}
	if not slot_ids().has(parts[2]):
		return {}
	return {"season": parts[0], "weather": parts[1], "slot": parts[2]}


## 时段表与预设表是否还对得上。`check_light_params.gd` 会调它 ——
## 改了 `daylight_presets.gd` 的 label 却忘了改这里，这条会红。
static func verify() -> Array[String]:
	var problems: Array[String] = []
	var known := _label_to_id()
	for i in range(Presets.PRESETS.size()):
		var label := String(Presets.PRESETS[i].label)
		if not known.has(label):
			problems.append("预设第 %d 项 label「%s」不在时段表里" % [i, label])
	# 反过来：时段表里排了却没有任何关键帧认领，说明这一段永远调不到。
	var used := {}
	for p in Presets.PRESETS:
		used[String(p.label)] = true
	for s in SLOTS:
		if not used.has(String(s.label)):
			problems.append("时段「%s」在预设表里没有对应关键帧" % String(s.label))
	return problems
