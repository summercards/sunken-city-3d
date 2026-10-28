extends Node2D
## 屏幕氛围层。只剩雨线 —— 它画的是「天上落下来的东西」，不是「盖在画面上的东西」。
##
## ## 为什么这里不许再画全屏矩形
##
## 2026-10-27 之前这里有一张全屏半透明色块，按日照时间叠深蓝，用来伪造夜晚。
## 结果整个游戏像蒙了一层脏玻璃：叠加式混合（`c' = c·(1-a) + tint·a`）不会压暗
## 暗部，只会把它们抬到 `tint×a`，纯黑永远回不去；而且它和真实光照无关 ——
## 影子方向、水面高光、天空颜色在「夜里」全都还是正午。
##
## 现在时段由 `DaylightRig` 驱动真实光照（太阳、环境光、天空、雾、水面反射、
## 水面高光）。这一层再叠一张纸，就等于在真实光照上又盖一层假的，观感互相打架、
## 数值也没法调。所以：**本文件不得出现覆盖全屏的填充绘制**，违反即视为回退，
## `test_daylight_rig.gd` 会当场报红。
##
## 代价是天气的云量不再直接压暗画面。这是有意的：阴天该由天光变暗，不该由一张
## 半透明纸来冒充；云量仍然通过 `WeatherService.query()` 公开给装配层，
## 需要时由 `DaylightRig` 作为参数吃进去，而不是在屏幕层私自动手。

var daylight := 1.0
var rain := 0.0
var clouds := 0.0
var submerged := false
var elapsed := 0.0

func present(clock: Dictionary, weather: Dictionary, underwater: bool) -> void:
	daylight = float(clock.daylight)
	rain = float(weather.rain)
	clouds = float(weather.cloud)
	submerged = underwater
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()

func _draw() -> void:
	if submerged: return
	if rain <= 0.0: return
	var size := get_viewport_rect().size
	for i in 100:
		var x := fposmod(i*137.1-elapsed*70.0,size.x)
		var y := fposmod(i*83.7+elapsed*550.0,size.y)
		draw_line(Vector2(x,y),Vector2(x-5,y+18),Color(0.65,0.8,0.95,0.24),1.0,true)
