extends RefCounted
## 统一 UI 字体工厂。
##
## 桌面端用系统字体（Hiragino / PingFang 的排版最好），Web 端浏览器里没有系统字体库，
## SystemFont 会退化成引擎内置字体（只带拉丁字形），简体中文会变成方框 ——
## 所以 Web 强制使用工程内置的 Noto Sans SC（SIL OFL，可随工程分发）。

const EMBEDDED_PATH := "res://assets/fonts/NotoSansSC-Regular.otf"

static var _embedded: Font = null


static func embedded() -> Font:
	if _embedded == null:
		var res: Resource = load(EMBEDDED_PATH)
		if res is Font:
			_embedded = res
	return _embedded


static func make(font_names: PackedStringArray) -> Font:
	var emb := embedded()
	if OS.has_feature("web"):
		if emb != null:
			return emb
	else:
		var sf := SystemFont.new()
		sf.font_names = font_names
		if emb != null:
			# 系统字体缺字时（如繁体/生僻字）用内置字体兜底，避免 LastResort 方框。
			sf.fallbacks = [emb]
		return sf
	var fallback := SystemFont.new()
	fallback.font_names = font_names
	return fallback
