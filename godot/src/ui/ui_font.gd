extends RefCounted
## One rounded, full-weight bundled face across every UI presenter and platform.
## The font is unmodified LXGW 975 Yuan SC 700W, distributed under SIL OFL 1.1.
const EMBEDDED_PATH := "res://src/ui/fonts/LXGW975YuanSC-700W.ttf"
static var _embedded: Font = null

static func embedded() -> Font:
	if _embedded == null:
		var shared := FontFile.new()
		# Read the bundled original directly, including in runner-isolated projects.
		shared.data=FileAccess.get_file_as_bytes(EMBEDDED_PATH)
		shared.antialiasing=TextServer.FONT_ANTIALIASING_GRAY
		shared.oversampling=2.0
		_embedded=shared
	return _embedded

static func make(_font_names: PackedStringArray) -> Font:
	return embedded()
