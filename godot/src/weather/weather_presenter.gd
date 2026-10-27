extends Node2D
## Presentation consumes values only; never writes clock, crops or render materials.
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
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO,size),Color(0.08,0.15,0.3,(1.0-daylight)*0.32+clouds*0.06))
	if rain <= 0.0: return
	for i in 100:
		var x := fposmod(i*137.1-elapsed*70.0,size.x)
		var y := fposmod(i*83.7+elapsed*550.0,size.y)
		draw_line(Vector2(x,y),Vector2(x-5,y+18),Color(0.65,0.8,0.95,0.24),1.0,true)
