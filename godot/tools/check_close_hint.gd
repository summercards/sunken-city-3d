extends SceneTree
## 右下角关闭键闸门（SEA-UI-R47）。
##
## 为什么需要它：原来桌面右下角挂的是两枚键盘提示胶囊（「Ⓑ 返回 Esc」「Ⓐ 选择 Enter」），
## 每开一个面板就跟着出现，屏幕角上永远有两块奶油色长方形。现在要的是
## **一枚动物森友会式的圆关闭键**，贴在界面右下角、略微歪一点。
##
## 这一条不会让任何脚本报错，只会在画面上"看起来不对"，所以只能靠断言盯着：
##   - 提示排必须只剩一个子节点（多一个 ≅ 又长回去）；
##   - 它必须是圆形按钮且**没有文字**（有文字就是键盘提示回来了）；
##   - 必须真的贴在右下角（差几十像素就是"飘在画面中间"）；
##   - rotation 必须不为 0（摆正就不是 AC 的手绘键）；
##   - 点一下必须真的关掉面板。
##
## 用法：Godot --path godot --script res://tools/check_close_hint.gd
## 退出码：0 = 全部合格，1 = 有不合格项。

const CloseButton = preload("res://src/ui/close_button.gd")
## 贴角容差：按钮自身 62px + 边距 34/30，倾斜 6° 后四角外扩约 3px。
const CORNER_SLACK := 40.0

var checks := 0
var failures := 0


func _init() -> void:
	call_deferred("run")


func ok(value: bool, name: String) -> void:
	checks += 1
	print("[close-hint] ", "PASS " if value else "FAIL ", name)
	if not value:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set("_autosave_on", false)
	await frames(8)
	main.set_process(false)
	var hud = main.hud
	var hints: Control = hud._hints

	ok(hints.get_child_count() == 1, "右下只剩一枚按钮（实际 %d）" % hints.get_child_count())
	var close: Control = hints.get_child(0) if hints.get_child_count() > 0 else null
	ok(close is Button, "它是按钮，不是装饰")
	ok(close is CloseButton, "用的是共享的动物森友会式关闭控件")
	ok(close.text == "", "按钮上没有键盘提示文案")
	for child in hints.get_children():
		ok(not (child is Button) or not ("Esc" in child.text or "Enter" in child.text),
			"右下不再出现「Esc / Enter」提示胶囊")

	# 打开面板：关闭键必须出现，并且真的是屏幕右下角。
	hud.open_tab("bag")
	await frames(6)
	ok(hints.visible, "面板打开时关闭键可见")
	var view: Vector2 = hud._root.size
	var box: Rect2 = hints.get_global_rect()
	ok(box.size.x > 0.0 and box.size.y > 0.0, "关闭键有实际尺寸")
	ok(is_equal_approx(box.size.x, CloseButton.DIAMETER) and is_equal_approx(box.size.y, CloseButton.DIAMETER),
		"圆片是 %.0fpx（实际 %.0f×%.0f）" % [CloseButton.DIAMETER, box.size.x, box.size.y])
	ok(view.x - box.end.x <= CORNER_SLACK and view.y - box.end.y <= CORNER_SLACK,
		"贴在右下角（右边距 %.0f，下边距 %.0f）" % [view.x - box.end.x, view.y - box.end.y])
	ok(view.x - box.end.x >= 0.0 and view.y - box.end.y >= 0.0, "整枚按钮没有被切出画面")
	# AC 的手绘键带一点倾斜；判据用绝对下限，不锁死具体角度，允许以后微调。
	ok(absf(close.rotation) > 0.02, "略微歪（rotation=%.3f rad）" % close.rotation)
	ok(close.pivot_offset.is_equal_approx(close.size * 0.5), "绕圆心旋转，歪了也不会跑位")
	ok(close.has_meta("cozy_skip"), "不吃 cozy 主题，不会被刷回胶囊高度")
	ok(close.tooltip_text != "", "有悬停说明，去掉文字不至于无处可读")

	# 真点一下：面板必须关掉，关掉后关闭键自己收起来。
	close.pressed.emit()
	await frames(4)
	ok(not hud._panel_open, "点关闭键真的关掉面板")
	ok(not hints.visible, "面板关掉后关闭键一起收起")

	print("[close-hint] %d checks, %d failures" % [checks, failures])
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
