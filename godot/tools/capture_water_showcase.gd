extends SceneTree
## 20 s stylized-water showcase, recorded through the movie writer's PNG sequence.
## ~/Applications/Godot.app/Contents/MacOS/Godot --path godot --resolution 1440x900 \
##   --write-movie outputs/ocean-absorption/movie/shot.png --fixed-fps 30 \
##   --script res://tools/capture_water_showcase.gd
## The movie writer needs the directory to exist and resolves relative paths under res://.
const FRAMES := 600  # 20 s at 30 Hz

var main: Node

func _init() -> void:
	call_deferred("run")

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	# Show only the water and the world: no HUD, no route ribbon.
	if main.hud != null:
		main.hud.visible = false
	main.ribbon.hide()
	main.cam.suspend_follow()
	main.cam.target = Vector3(4.0, 1.12, -6.0)
	main.cam._orbit(0.9, -0.25)
	main.cam.distance = 50.0
	main.cam.refresh()
	for i in 20:
		await process_frame

	for frame in FRAMES:
		var t := float(frame) / float(FRAMES)
		# Slow right-hand orbit, easing in and out so the ends do not snap.
		main.cam._orbit(0.0013 * (0.30 + 0.70 * sin(PI * t)), 0.0)
		if frame == 90:
			main.cam.distance = 58.0
		elif frame == 210:
			main.cam.distance = 60.0
		elif frame == 330:
			main.cam.distance = 68.0
		elif frame == 430:
			# Lift a little: the swell reads better a touch higher up.
			main.cam._orbit(0.0, 0.10)
			main.cam.distance = 60.0
		elif frame == 510:
			main.cam.distance = 52.0
		await process_frame
		await RenderingServer.frame_post_draw

	print("[water-showcase] frames=", FRAMES)
	quit()
