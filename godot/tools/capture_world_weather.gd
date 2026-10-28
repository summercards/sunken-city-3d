extends SceneTree
## 沿预设表的全部关键帧抓图，作为「真实光照做时差」的渲染证据。
##
## 抓的是**关键帧**而不是随手取整点：`daylight_presets.gd` 定义的那七个小时
## 就是画面的实际状态，中间时刻只是插值。抓关键帧等于直接把可调的设计面拍下来。
##
##   06:00 清晨 —— 太阳贴近海平面，暖光起步
##   09:00 上午 —— **基准帧**，必须与引入昼夜之前的定版画面一致
##   12:00 中午 —— 全天最亮，影子最短
##   15:00 下午 —— 开始转暖，影子拉长
##   18:00 傍晚 —— 暖光最浓，天空转橙紫
##   21:00 夜晚 —— 太阳已落，环境光转冷，水面不再有太阳亮斑
##   00:00 深夜 —— 与 24:00 同值，用来验证跨午夜不跳变
##
## 时钟与天气都暂停，每个时段显式写一次 `seconds` 再驱动 —— 否则抓图期间时间
## 还在走，每一张的时段都和标题对不上。
func _init() -> void: call_deferred("run")

func run() -> void:
	preload("res://tools/lighting_capture_profile.gd").prepare()
	var main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on=false
	main.world_clock.paused=true
	main.weather_service.paused=true
	main.weather_service.set_weather("clear")
	main.title_camera.begin(main.cam)
	var shots: Array = [
		["daylight_0600",6.0],["daylight_0900",9.0],["daylight_1200",12.0],
		["daylight_1500",15.0],["daylight_1800",18.0],["daylight_2100",21.0],["daylight_0000",0.0],
	]
	for entry in shots:
		main.world_clock.from_dict({"day":1,"seconds":float(entry[1])*3600.0,"day_length":1200.0})
		main.daylight_rig.apply(float(entry[1]))
		for i in 12: await process_frame
		await RenderingServer.frame_post_draw
		var path: String = "res://outputs/" + String(entry[0]) + ".png"
		get_root().get_texture().get_image().save_png(path)
		var sun: DirectionalLight3D = main.get_node("World/Lights/Sun")
		var env: Environment = (main.get_node("World/WorldEnvironment") as WorldEnvironment).environment
		print("[daylight-frame] %s sun=%.3f ambient=%.3f sky=%.3f elev=%.1f" % [
			path, sun.light_energy, env.ambient_light_energy,
			env.background_energy_multiplier, main.daylight_rig.sun_angles().x])
	main.queue_free()
	await process_frame
	print("[visual-weather] complete")
	quit()
