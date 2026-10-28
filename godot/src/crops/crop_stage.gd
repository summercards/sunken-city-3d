extends RefCounted
class_name CropStage
## 作物四个可见阶段。这是 SEA-CROP 唯一允许的阶段定义，别处只准引用。
##
## 阶段由生长进度唯一决定，与 SEA-FARM 的 grow_days 自然对齐：
##   grow_days=3 时 remaining=3/2/1/0 → progress=0/.33/.67/1 → seed/sprout/leaf/harvest
##
## 规则见 docs/features/crop/spec.md SEA-CROP-R02。

const SEED := 0
const SPROUT := 1
const LEAF := 2
const HARVEST := 3

const KEYS: Array[String] = ["seed", "sprout", "leaf", "harvest"]
const NODE_NAMES: Array[String] = ["Stage0Seed", "Stage1Sprout", "Stage2Leaf", "Stage3Harvest"]
const DEFAULT_LABELS: Array[String] = ["播种", "发芽", "二次发芽", "收成"]


static func count() -> int:
	return KEYS.size()


static func is_valid(index: int) -> bool:
	return index >= 0 and index < KEYS.size()


static func key_of(index: int) -> String:
	return KEYS[index] if is_valid(index) else ""


static func node_name(index: int) -> String:
	return NODE_NAMES[index] if is_valid(index) else ""


static func label_of(index: int, labels: Array = DEFAULT_LABELS) -> String:
	if not is_valid(index):
		return ""
	if index < labels.size():
		var text := str(labels[index])
		if text != "":
			return text
	return DEFAULT_LABELS[index]


## 进度到阶段的映射。ready 由规则层给出，不在这里推断。
static func stage_for_progress(progress: float, ready: bool) -> int:
	if ready:
		return HARVEST
	var p := clampf(progress, 0.0, 1.0)
	if p <= 0.001:
		return SEED
	if p < 0.5:
		return SPROUT
	return LEAF


## 阶段在成熟度上的位置，用于 UI 进度条；阶段之间不做插值。
static func ratio_of(index: int) -> float:
	match index:
		SEED: return 0.0
		SPROUT: return 1.0 / 3.0
		LEAF: return 2.0 / 3.0
		HARVEST: return 1.0
	return 0.0
