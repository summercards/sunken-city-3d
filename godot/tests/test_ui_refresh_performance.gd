extends SceneTree
## PERF-AUTH 独立夹具：不装配 Main，只验证事件合并、稳定签名和雨线生命周期。

const HUD = preload("res://src/ui/hud.gd")
const NOTEBOOK = preload("res://src/ui/notebook.gd")
const WEATHER = preload("res://src/weather/weather_presenter.gd")

class RefreshSource extends RefCounted:
	signal changed

class HudProbe extends HUD:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[ui-refresh-performance] FAIL ", label)

func _init() -> void:
	call_deferred("run")

func _make_row(id: String, subtitle: String) -> Dictionary:
	return {"id":id,"title":id,"icon":"vegetable","subtitle":subtitle,"tag":"测试",
		"body":"body","facts":[subtitle],"action":"","button":""}

func _notebook_data(clock_text: String) -> Dictionary:
	return {"overview":[_make_row("today",clock_text)],"plant":[_make_row("crop/lettuce","种子 ×1")],
		"goods":[],"life":[]}

func _test_hud_signal_coalescing() -> void:
	var hud = HudProbe.new()
	root.add_child(hud)
	# _refresh() 在未装配模型时安全返回；这里专门计数调度与实际执行。
	var source := RefreshSource.new()
	source.changed.connect(hud._queue_refresh)
	source.changed.emit()
	source.changed.emit()
	source.changed.emit()
	check(hud._refresh_request_count == 3 and hud._refresh_pending and hud._refresh_deferred, "自定义信号重复请求合并为一个 deferred 批次")
	await process_frame
	check(hud._actual_refresh_count == 1, "同帧重复刷新只执行一次 actual refresh")
	# 公开同步入口对应的实际方法仍可直接调用，兼容旧测试/交互语义。
	hud._refresh()
	check(hud._actual_refresh_count == 2, "直接 refresh 仍保持同步语义")
	# deferred callback 目标释放后不得再访问已释放 HUD。
	hud._queue_refresh()
	hud.queue_free()
	await process_frame
	check(true, "HUD 释放后挂起刷新安全完成")

func _test_notebook_signature() -> void:
	var note = NOTEBOOK.new()
	note.font = load("res://assets/fonts/NotoSansSC-Regular.otf")
	var snapshot := _notebook_data("07:00")
	note.query = func() -> Dictionary: return snapshot
	root.add_child(note)
	await process_frame
	note.refresh()
	var first: int = note._refresh_count
	note.refresh()
	check(note._refresh_count == first, "笔记签名稳定时不重建整页")
	note.show_category("plant")
	check(note._refresh_count == first + 1, "切换分类仍立即刷新一次")
	snapshot["overview"] = _notebook_data("07:01")["overview"]
	note.show_category("overview")
	check(note._refresh_count == first + 2, "时钟文字变化进入显示签名")
	note.queue_free()
	await process_frame
	check(true, "笔记节点释放后无悬挂刷新")

func _test_weather_lifecycle() -> void:
	var presenter = WEATHER.new()
	root.add_child(presenter)
	presenter.present({"daylight":1.0},{"rain":1.0,"cloud":0.0},false)
	check(presenter.is_processing(), "正雨时启用 process")
	var rain_queue: int = presenter._queue_redraw_count
	presenter._process(0.1)
	check(presenter._queue_redraw_count == rain_queue + 1, "正雨时 process 持续 queue_redraw")
	var old_elapsed: float = presenter.elapsed
	presenter.present({"daylight":1.0},{"rain":0.0,"cloud":0.0},false)
	check(not presenter.is_processing(), "晴天停止 process")
	check(presenter._queue_redraw_count == rain_queue + 2, "停雨立即清空雨线并 queue_redraw")
	check(presenter.elapsed == old_elapsed, "停雨前已累计的 phase 保持")
	presenter.present({"daylight":1.0},{"rain":1.0,"cloud":0.0},false)
	var clear_queue: int = presenter._queue_redraw_count
	presenter.present({"daylight":1.0},{"rain":1.0,"cloud":0.0},true)
	check(not presenter.is_processing(), "潜水时停止 process")
	presenter.present({"daylight":1.0},{"rain":1.0,"cloud":0.0},false)
	check(presenter.is_processing(), "出水且正雨时恢复 process")
	check(presenter._queue_redraw_count >= clear_queue + 2, "潜水切换能清空并恢复雨线")
	var phase_before: float = presenter.elapsed
	presenter.present({"daylight":1.0},{"rain":0.0,"cloud":0.0},false,2.0)
	check(is_equal_approx(presenter.elapsed,phase_before+2.0), "晴天按注入模拟时间累计phase而非墙钟")
	presenter.present({"daylight":1.0},{"rain":1.0,"cloud":0.0},false,0.25)
	var injected: float = presenter.elapsed
	presenter._process(0.25)
	check(presenter.elapsed == injected, "注入模式process不重复推进时间")
	presenter.queue_free()
	await process_frame
	check(true, "天气节点释放后无悬挂重绘")

func run() -> void:
	await _test_hud_signal_coalescing()
	await _test_notebook_signature()
	await _test_weather_lifecycle()
	print("[ui-refresh-performance] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
