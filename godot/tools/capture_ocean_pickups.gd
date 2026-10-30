extends SceneTree
var main: Node
var checks := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks+=1
	print("[ocean-pickups-render] ","PASS " if value else "FAIL ",label)
	if not value: failures+=1
func shot(label: String) -> Image:
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	var img: Image=root.get_texture().get_image()
	img.save_png("res://outputs/ocean-pickups-"+label+".png")
	return img
func run() -> void:
	main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on=false
	main.set_process(false)
	main.props.set_process(false)
	main.boat.set_process(false)
	root.get_node("Economy").set_process(false)
	main.world_clock.paused=true
	main.world_clock.from_dict({"day":1,"seconds":9*3600,"day_length":1200})
	main.daylight_rig.apply(9)
	main.cam.suspend_follow()
	var home_bundles := 0
	for item in main.props.crates:
		if preload("res://src/core/play_scope.gd").HOME_WATER.has_point(Vector2(item.base.x,item.base.z)): home_bundles+=1
	check(home_bundles==6,"native sunroom water keeps exactly six bundles")
	main.cam.target=Vector3(9.5,1.12,12)
	main.cam.distance=100
	main.cam.orbit_dir=Vector3(-0.45,0.8,0.6)
	main.cam.refresh()
	await shot("home-density")
	# Unobstructed water beyond both the former home rectangle and 150m fence.
	var at:=Vector3(220,1.12,220)
	main.boat.place_at(at,0)
	main.props.sync_population(main.world_clock.query(),at)
	check(main.props.crates.size()>=16 and main.props.crates.size()<=17 and main.props.schools.size()==36,"native distant water has 30 percent wood and unchanged fish")
	main.cam.target=main.player.global_position
	main.cam.distance=36
	main.cam.orbit_dir=Vector3(-0.45,0.8,0.6)
	main.cam.refresh()
	await shot("distant-sea")
	for kind in ["wood","fish"]:
		var item: Dictionary=main.props.crates[0] if kind=="wood" else main.props.schools[0]
		main.boat.place_at(item.base+Vector3(1.2,0,0),0)
		main.cam.target=main.player.global_position
		main.cam.distance=12
		main.cam.refresh()
		main._begin_pick_sail({"type":"crate" if kind=="wood" else "fish","item":item})
		main._update_pickup_progress(0)
		main._update_pickup_progress(main._pick_span*0.5)
		check(main.pickup_progress.bar.visible and main.pickup_progress.rewards.is_empty(),kind+": no reward before the progress completes")
		await shot(kind+"-gathering")
		main._update_pickup_progress(main._pick_span)
		var view=main.pickup_progress
		check(view.rewards.size()==1,kind+": actual gathering completion starts the effect")
		view.tick(0.12)
		var row: Control=view.rewards[0].node
		check(row.visible and row.position.y+row.size.y<view.bar.position.y,kind+": received item sits above the completed bar")
		var img: Image=await shot(kind+"-received")
		var transform: Transform2D=root.get_screen_transform()
		var a: Vector2=transform*row.position
		var b: Vector2=transform*(row.position+row.size)
		row.hide()
		var without: Image=await shot(kind+"-hidden")
		row.show()
		var changes:=0
		for y in range(maxi(0,int(a.y)),mini(img.get_height(),int(b.y))):
			for x in range(maxi(0,int(a.x)),mini(img.get_width(),int(b.x))):
				if img.get_pixel(x,y).v-without.get_pixel(x,y).v>0.12: changes+=1
		check(changes>40,kind+": reward draws real pixels above progress ("+str(changes)+")")
		var y0:=row.position.y
		view.tick(0.64)
		check(row.position.y<y0 and row.modulate.a<0.9,kind+": native rising and fading stage")
		await shot(kind+"-rising")
		view.tick(2)
		check(view.rewards.is_empty() and not view.bar.visible,kind+": both transient views finish")
		await shot(kind+"-finished")
	print("[ocean-pickups-render] %d checks, %d failures" % [checks,failures])
	main.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
