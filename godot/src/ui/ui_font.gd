extends RefCounted
## One rounded, full-weight bundled face across every UI presenter and platform.
## The font is unmodified LXGW 975 Yuan SC 700W, distributed under SIL OFL 1.1.
##
## 硬契约：导出包里只有导入后的 .fontdata，源 .ttf 不会被打包。
## 所以这里必须先按资源加载（走 .import 重映射）；直接 FileAccess 读源 .ttf
## 在导出包里只能读到空字节，字体全变豆腐块（Web 端没有系统字体兜底，最明显）。
## 该契约由 scripts/check_pack_assets.py 在每次导出后断言，别再改回只读源文件。
const EMBEDDED_PATH := "res://src/ui/fonts/LXGW975YuanSC-700W.ttf"
static var _embedded: Font = null

static func embedded() -> Font:
	if _embedded == null:
		_embedded = _load_bundled()
	return _embedded

static func make(_font_names: PackedStringArray) -> Font:
	return embedded()

static func _load_bundled() -> Font:
	if ResourceLoader.exists(EMBEDDED_PATH):
		var loaded := ResourceLoader.load(EMBEDDED_PATH)
		if loaded is FontFile and not (loaded as FontFile).data.is_empty():
			var font := loaded as FontFile
			font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
			font.oversampling = 2.0
			return font
	# 兜底：仅工程外隔离副本（没有 .godot 导入缓存）才会走到这里。
	var shared := FontFile.new()
	shared.data = FileAccess.get_file_as_bytes(EMBEDDED_PATH)
	shared.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	shared.oversampling = 2.0
	return shared
