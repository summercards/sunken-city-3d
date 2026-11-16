extends RefCounted
## 原创v1粗线字表：不是系统字体、TextMesh或第三方轮廓。
## 每笔为12三角面实体；同轴相邻笔合并后最多5笔60面，双面24字仍受3500面硬门禁。
## O/B/R以留空的轮廓笔画保留真实洞，不用实心板或贴字。

const VERSION := "sea_original_strokes_v1"
const SEGMENTS: Dictionary = {
	"a": [0.12, 0.94, 0.60, 0.94], "b": [0.64, 0.86, 0.64, 0.56],
	"c": [0.64, 0.43, 0.64, 0.14], "d": [0.60, 0.06, 0.12, 0.06],
	"e": [0.08, 0.14, 0.08, 0.43], "f": [0.08, 0.56, 0.08, 0.86],
	"g": [0.12, 0.50, 0.60, 0.50], "h": [0.12, 0.88, 0.33, 0.55],
	"i": [0.60, 0.88, 0.39, 0.55], "j": [0.33, 0.44, 0.12, 0.12],
	"k": [0.39, 0.44, 0.60, 0.12], "l": [0.36, 0.88, 0.36, 0.56],
	"m": [0.36, 0.44, 0.36, 0.12], "n": [0.12, 0.12, 0.60, 0.88],
	"o": [0.12, 0.88, 0.60, 0.12], "p": [0.36, 0.06, 0.36, 0.07],
	"q": [0.36, 0.93, 0.36, 0.28]
}
const TABLE: Dictionary = {
	"A": "abcefg", "B": "abcdefg", "C": "adef", "D": "abcde f",
	"E": "adefg", "F": "aefg", "G": "acdef", "H": "bcefg",
	"I": "adlm", "J": "bcde", "K": "efik", "L": "def",
	"M": "bcefh i", "N": "bcefo", "O": "abcdef", "P": "abefg",
	"Q": "abcdefk", "R": "abefgk", "S": "acdfg", "T": "alm",
	"U": "bcdef", "V": "fjci", "W": "bcefjk", "X": "hijk",
	"Y": "him", "Z": "adn", "0": "abcdef", "1": "bc", "2": "abdeg",
	"3": "abcdg", "4": "bcfg", "5": "acdfg", "6": "acdefg",
	"7": "abc", "8": "abcdefg", "9": "abcdfg", ".": "p", "-": "g",
	"!": "qp", "&": "defghk", " ": ""
}

static func stroke_segments(character: String) -> Array[Dictionary]:
	var strokes: String = str(TABLE.get(character, "")).replace(" ", "")
	var result: Array[Dictionary] = []
	# 合并同一竖边的上下笔，既增加粗字连续性，也降低双面长文面数。
	for pair: String in ["fe", "bc", "lm"]:
		if strokes.contains(pair.substr(0, 1)) and strokes.contains(pair.substr(1, 1)):
			var first: Array = SEGMENTS[pair.substr(0, 1)]
			var second: Array = SEGMENTS[pair.substr(1, 1)]
			var low: float = minf(minf(float(first[1]), float(first[3])), minf(float(second[1]), float(second[3])))
			var high: float = maxf(maxf(float(first[1]), float(first[3])), maxf(float(second[1]), float(second[3])))
			result.append({"id": pair, "segment": [first[0], low, first[0], high]})
			strokes = strokes.replace(pair.substr(0, 1), "").replace(pair.substr(1, 1), "")
	for stroke: String in strokes:
		result.append({"id": stroke, "segment": SEGMENTS[stroke]})
	return result

static func stroke_count(character: String) -> int:
	return stroke_segments(character).size()

static func add(geometry: RefCounted, text: String, center: Vector3, width: float, height: float, depth: float, rotation: Vector3 = Vector3.ZERO, vertical: bool = false, material_role: String = "SEA_Gloss", support: String = "") -> Dictionary:
	var advance: float = 0.87
	var extent_x: float = 0.72 if vertical else maxf(0.72, float(text.length()) * advance - 0.15)
	var extent_y: float = maxf(1.0, float(text.length()) * 1.18 - 0.18) if vertical else 1.0
	var factor: float = minf(width / extent_x, height / extent_y)
	var basis: Basis = Basis.from_euler(rotation)
	var counts: Array[Dictionary] = []
	for index: int in range(text.length()):
		var character: String = text.substr(index, 1)
		var offset := Vector2(-0.36, extent_y * 0.5 - 1.0 - index * 1.18) if vertical else Vector2(-extent_x * 0.5 + index * advance, -0.5)
		var strokes: Array[Dictionary] = stroke_segments(character)
		var before: int = geometry.buckets[material_role].indices.size() / 3
		for stroke_data: Dictionary in strokes:
			var stroke: String = str(stroke_data.id)
			var segment: Array = stroke_data.segment
			var a := Vector2(float(segment[0]), float(segment[1]))
			var b := Vector2(float(segment[2]), float(segment[3]))
			# 字表横轴从阅读左向右；-Z正面观众的右方向是局部-X。
			a.x = -a.x
			b.x = -b.x
			var facing_offset := Vector2(-offset.x, offset.y)
			var position_2d: Vector2 = ((a + b) * 0.5 + facing_offset) * factor
			var position: Vector3 = center + basis * Vector3(position_2d.x, position_2d.y, 0)
			var thickness: float = (0.18 if stroke == "p" else 0.145) * factor
			var stroke_length: float = maxf(a.distance_to(b) * factor, thickness)
			var angle: float = (b - a).angle()
			var combined: Basis = basis * Basis(Vector3.BACK, angle)
			geometry.box("glyph_%02d_%s_%s" % [index, character, stroke], position, Vector3(stroke_length, thickness, depth), material_role, combined.get_euler(), false, 0.02, false)
			geometry.active_part.glyph = character
			geometry.active_part.glyph_index = index
			geometry.active_part.glyph_table_version = VERSION
			geometry.active_part.no_volume = false
			if not support.is_empty():
				geometry.require_connection(support, position + basis.z * depth * 0.40)
		var after: int = geometry.buckets[material_role].indices.size() / 3
		counts.append({"character": character, "input_index": index, "triangles": after - before})
	return {"input": text, "glyph_table_version": VERSION, "glyphs": counts, "uniform_scale": factor, "preserved": true}
